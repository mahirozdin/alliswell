import { newId } from '../lib/ids.js';
import { coded } from '../lib/errors.js';
import { toIso } from '../lib/serialize.js';
import { encryptSecret } from '../lib/crypto.js';
import { formatInstantWithOffset } from '../lib/time.js';
import { parseJsonColumn } from '../db/task-series.js';
import { MODEL_CATALOG, catalogDefaults } from '../lib/ai/models.js';
import { upstreamMessage } from '../lib/ai/http.js';
import { buildExtractionPrompt, extractTasks } from '../lib/ai/extract.js';
import {
  runChat,
  sseSink,
  socketSink,
  ABORT_CANCELLED,
  ABORT_CLIENT_GONE,
} from '../lib/ai/chat.js';

const ULID_PARAM = { type: 'string', minLength: 26, maxLength: 26 };

export const AI_PROVIDERS = ['anthropic', 'openai', 'gemini', 'openrouter', 'ollama'];

const errorResponseSchema = {
  type: 'object',
  properties: {
    statusCode: { type: 'integer' },
    code: { type: 'string' },
    error: { type: 'string' },
    message: { type: 'string' },
  },
};

const connectionSchema = {
  type: 'object',
  required: ['id', 'workspaceId', 'userId', 'provider', 'authMode', 'status'],
  properties: {
    id: { type: 'string' },
    workspaceId: { type: 'string' },
    userId: { type: 'string' },
    provider: { type: 'string' },
    authMode: { type: 'string' },
    keyLast4: { type: ['string', 'null'] },
    baseUrl: { type: ['string', 'null'] },
    defaultChatModel: { type: ['string', 'null'] },
    defaultFastModel: { type: ['string', 'null'] },
    status: { type: 'string' },
    lastUsedAt: { type: ['string', 'null'] },
    createdAt: { type: 'string' },
    updatedAt: { type: 'string' },
  },
};

/**
 * The response schema is the leak barrier: fast-json-stringify serializes ONLY
 * the whitelisted fields, and the one key-derived field on the wire is
 * `keyLast4`, a stored column computed from the plaintext at write time. The
 * serializer has no code path that could touch `encrypted_key` (ADR-0006).
 */
export function serializeAiConnection(row) {
  return {
    id: row.id,
    workspaceId: row.workspace_id,
    userId: row.user_id,
    provider: row.provider,
    authMode: row.auth_mode,
    keyLast4: row.key_last4 ?? null,
    baseUrl: row.base_url ?? null,
    defaultChatModel: row.default_chat_model ?? null,
    defaultFastModel: row.default_fast_model ?? null,
    status: row.status,
    lastUsedAt: toIso(row.last_used_at),
    createdAt: toIso(row.created_at),
    updatedAt: toIso(row.updated_at),
  };
}

/**
 * AI settings surface (OPH-215, Epic 20, ADR-0019, BLUEPRINT §4.13).
 *
 * Registered ONLY when AI_ENABLED=true (app.js) — a disabled instance answers
 * 404 on every /ai/* route, indistinguishable from a server that never had the
 * feature. Status codes follow the house family: 400 malformed, 404 not
 * visible to you, 409 uniqueness, 422 valid-but-refused, 503 not configured.
 */
export default async function aiRoutes(app) {
  const auth = { onRequest: [app.authenticate] };

  const CODE_STATUS = {
    AI_KEY_REQUIRED: 'badRequest',
    AI_KEY_NOT_ALLOWED: 'badRequest',
    AI_BASE_URL_REQUIRED: 'badRequest',
    AI_CONNECTION_EXISTS: 'conflict',
    AI_INSTANCE_KEY_MISSING: 'unprocessableEntity',
  };

  const CODE_MESSAGE = {
    AI_KEY_REQUIRED: 'This provider needs an API key',
    AI_KEY_NOT_ALLOWED: 'Instance-managed connections do not take a key',
    AI_BASE_URL_REQUIRED: 'Ollama needs a base URL (your own server address)',
    AI_CONNECTION_EXISTS: 'You already have a connection for this provider here',
    AI_INSTANCE_KEY_MISSING: 'This instance has no key configured for that provider',
  };

  function fail(code) {
    return coded(app.httpErrors[CODE_STATUS[code]](CODE_MESSAGE[code]), code);
  }

  /** Loads one live connection and proves the caller may touch it. */
  async function loadOwn(request, connectionId) {
    const row = await app
      .db('ai_connections')
      .where({ id: connectionId })
      .whereNull('deleted_at')
      .first();
    if (!row) {
      throw coded(app.httpErrors.notFound('AI connection not found'), 'AI_CONNECTION_NOT_FOUND');
    }
    await app.requireWorkspaceMember(request, row.workspace_id);
    if (row.user_id !== request.user.id) {
      // 404, not 403: the status must not confirm a co-member's row exists.
      throw coded(app.httpErrors.notFound('AI connection not found'), 'AI_CONNECTION_NOT_YOURS');
    }
    return row;
  }

  /** Providers this instance can serve in `auth_mode = 'instance_env'`. */
  function instanceProviders() {
    const fromKeys = Object.entries(app.config.ai.instanceKeys)
      .filter(([, key]) => Boolean(key))
      .map(([provider]) => provider);
    if (app.config.ai.baseUrls.ollama) fromKeys.push('ollama');
    return fromKeys;
  }

  // ── Status: the app's single surface-withdrawal gate ──────────────────────
  app.get(
    '/workspaces/:workspaceId/ai/status',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { workspaceId: ULID_PARAM } },
        response: {
          200: {
            type: 'object',
            properties: {
              configured: { type: 'boolean' },
              providers: { type: 'array', items: { type: 'string' } },
              instanceProviders: { type: 'array', items: { type: 'string' } },
            },
          },
          403: errorResponseSchema,
        },
      },
    },
    async (request) => {
      const { workspaceId } = request.params;
      await app.requireWorkspaceMember(request, workspaceId);
      const rows = await app
        .db('ai_connections')
        .where({ workspace_id: workspaceId, user_id: request.user.id })
        .whereNull('deleted_at')
        .select();
      return {
        configured: rows.length > 0,
        providers: rows.map((row) => row.provider),
        instanceProviders: instanceProviders(),
      };
    },
  );

  // ── List: the caller's own connections ────────────────────────────────────
  app.get(
    '/workspaces/:workspaceId/ai/connections',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { workspaceId: ULID_PARAM } },
        response: {
          200: {
            type: 'object',
            properties: { items: { type: 'array', items: connectionSchema } },
          },
          403: errorResponseSchema,
        },
      },
    },
    async (request) => {
      const { workspaceId } = request.params;
      await app.requireWorkspaceMember(request, workspaceId);
      const rows = await app
        .db('ai_connections')
        .where({ workspace_id: workspaceId, user_id: request.user.id })
        .whereNull('deleted_at')
        .orderBy('created_at', 'asc')
        .select();
      return { items: rows.map(serializeAiConnection) };
    },
  );

  // ── Create (or revive the tombstone occupying the tuple) ──────────────────
  app.post(
    '/workspaces/:workspaceId/ai/connections',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { workspaceId: ULID_PARAM } },
        body: {
          type: 'object',
          additionalProperties: false,
          // `consentAcknowledged: const true` makes the create unreachable
          // without walking the consent screen (DESIGN §24 AI8) — the durable
          // server-side trace of that walk.
          required: ['provider', 'consentAcknowledged'],
          properties: {
            provider: { type: 'string', enum: AI_PROVIDERS },
            // `oauth_subscription` is reserved (ADR-0019): the column accepts
            // it the day a sanctioned program exists, the API does not.
            authMode: { type: 'string', enum: ['api_key', 'instance_env'] },
            apiKey: { type: 'string', minLength: 8, maxLength: 512 },
            baseUrl: { type: 'string', maxLength: 2048, pattern: '^https?://' },
            defaultChatModel: { type: 'string', minLength: 1, maxLength: 128 },
            defaultFastModel: { type: 'string', minLength: 1, maxLength: 128 },
            consentAcknowledged: { const: true },
          },
        },
        response: {
          201: connectionSchema,
          400: errorResponseSchema,
          403: errorResponseSchema,
          409: errorResponseSchema,
          422: errorResponseSchema,
        },
      },
    },
    async (request, reply) => {
      const { workspaceId } = request.params;
      await app.requireWorkspaceMember(request, workspaceId);
      const userId = request.user.id;
      const provider = request.body.provider;
      const authMode = request.body.authMode ?? 'api_key';
      const apiKey = request.body.apiKey ?? null;
      const baseUrl = request.body.baseUrl ?? null;

      if (authMode === 'api_key') {
        // Ollama is keyless by default (an optional key covers authed proxies);
        // every cloud provider requires one.
        if (provider !== 'ollama' && !apiKey) throw fail('AI_KEY_REQUIRED');
        if (provider === 'ollama' && !baseUrl) throw fail('AI_BASE_URL_REQUIRED');
      } else {
        if (apiKey) throw fail('AI_KEY_NOT_ALLOWED');
        const available =
          provider === 'ollama'
            ? Boolean(app.config.ai.baseUrls.ollama)
            : Boolean(app.config.ai.instanceKeys[provider]);
        if (!available) throw fail('AI_INSTANCE_KEY_MISSING');
      }

      const fields = {
        auth_mode: authMode,
        encrypted_key: apiKey ? encryptSecret(apiKey, app.config.ai.tokenKey) : null,
        key_last4: apiKey ? apiKey.slice(-4) : null,
        base_url: baseUrl,
        default_chat_model: request.body.defaultChatModel ?? null,
        default_fast_model: request.body.defaultFastModel ?? null,
        status: 'active',
        last_used_at: null,
      };

      const existing = await app
        .db('ai_connections')
        .where({ workspace_id: workspaceId, user_id: userId, provider })
        .first();
      if (existing && !existing.deleted_at) throw fail('AI_CONNECTION_EXISTS');

      let id;
      if (existing) {
        // The unique tuple ignores soft deletes on purpose — a re-add revives
        // the tombstone with fresh key material (calendar_accounts precedent).
        id = existing.id;
        await app
          .db('ai_connections')
          .where({ id })
          .update({ ...fields, deleted_at: null, updated_at: new Date() });
      } else {
        id = newId();
        try {
          await app.db('ai_connections').insert({
            id,
            workspace_id: workspaceId,
            user_id: userId,
            provider,
            ...fields,
          });
        } catch (err) {
          // Lost a double-tap race against our own uniqueness index.
          if (err?.code === 'ER_DUP_ENTRY') throw fail('AI_CONNECTION_EXISTS');
          throw err;
        }
      }
      const row = await app.db('ai_connections').where({ id }).first();
      return reply.code(201).send(serializeAiConnection(row));
    },
  );

  // ── Rotate key / models / base URL ────────────────────────────────────────
  // Provider and auth mode are immutable: switching providers is remove + add
  // (the quick-links immutable-target precedent).
  app.patch(
    '/ai/connections/:connectionId',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { connectionId: ULID_PARAM } },
        body: {
          type: 'object',
          additionalProperties: false,
          minProperties: 1,
          properties: {
            apiKey: { type: 'string', minLength: 8, maxLength: 512 },
            baseUrl: {
              anyOf: [{ type: 'null' }, { type: 'string', maxLength: 2048, pattern: '^https?://' }],
            },
            defaultChatModel: {
              anyOf: [{ type: 'null' }, { type: 'string', minLength: 1, maxLength: 128 }],
            },
            defaultFastModel: {
              anyOf: [{ type: 'null' }, { type: 'string', minLength: 1, maxLength: 128 }],
            },
          },
        },
        response: { 200: connectionSchema, 400: errorResponseSchema, 404: errorResponseSchema },
      },
    },
    async (request) => {
      const row = await loadOwn(request, request.params.connectionId);
      const patch = {};
      if (request.body.apiKey !== undefined) {
        if (row.auth_mode === 'instance_env') throw fail('AI_KEY_NOT_ALLOWED');
        patch.encrypted_key = encryptSecret(request.body.apiKey, app.config.ai.tokenKey);
        patch.key_last4 = request.body.apiKey.slice(-4);
        // A fresh key clears an auth-failure flag until proven otherwise.
        patch.status = 'active';
      }
      if ('baseUrl' in request.body) {
        if (row.provider === 'ollama' && row.auth_mode === 'api_key' && !request.body.baseUrl) {
          throw fail('AI_BASE_URL_REQUIRED');
        }
        patch.base_url = request.body.baseUrl ?? null;
      }
      if ('defaultChatModel' in request.body) {
        patch.default_chat_model = request.body.defaultChatModel ?? null;
      }
      if ('defaultFastModel' in request.body) {
        patch.default_fast_model = request.body.defaultFastModel ?? null;
      }

      await app
        .db('ai_connections')
        .where({ id: row.id })
        .update({ ...patch, updated_at: new Date() });
      const fresh = await app.db('ai_connections').where({ id: row.id }).first();
      return serializeAiConnection(fresh);
    },
  );

  // ── Remove: soft delete AND scrub the key material ────────────────────────
  app.delete(
    '/ai/connections/:connectionId',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { connectionId: ULID_PARAM } },
        response: { 204: { type: 'null' }, 404: errorResponseSchema },
      },
    },
    async (request, reply) => {
      const row = await loadOwn(request, request.params.connectionId);
      // The secret dies at disconnect; the row remains as the FK anchor for
      // usage history and as the revivable tombstone occupying the tuple.
      await app.db('ai_connections').where({ id: row.id }).update({
        deleted_at: new Date(),
        encrypted_key: null,
        key_last4: null,
        updated_at: new Date(),
      });
      return reply.code(204).send();
    },
  );

  const modelOptionSchema = {
    type: 'object',
    properties: { id: { type: 'string' }, label: { type: 'string' } },
  };

  /** Maps an AiProviderError onto our stable upstream codes. */
  function upstreamCode(err) {
    if (err?.code === 'upstream_auth') return 'AI_UPSTREAM_AUTH_FAILED';
    if (err?.code === 'upstream_rate_limited') return 'AI_UPSTREAM_RATE_LIMITED';
    return 'AI_UPSTREAM_ERROR';
  }

  // ── Models: static catalog for the cloud four, live tags for Ollama ───────
  app.get(
    '/workspaces/:workspaceId/ai/models',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { workspaceId: ULID_PARAM } },
        querystring: {
          type: 'object',
          additionalProperties: false,
          properties: { connectionId: ULID_PARAM },
        },
        response: {
          200: {
            type: 'object',
            properties: {
              provider: { type: 'string' },
              connectionId: { type: 'string' },
              source: { type: 'string', enum: ['catalog', 'live'] },
              models: {
                type: 'object',
                properties: {
                  chat: { type: 'array', items: modelOptionSchema },
                  fast: { type: 'array', items: modelOptionSchema },
                },
              },
              defaults: {
                type: 'object',
                properties: {
                  chat: { type: ['string', 'null'] },
                  fast: { type: ['string', 'null'] },
                },
              },
            },
          },
          403: errorResponseSchema,
          404: errorResponseSchema,
          502: errorResponseSchema,
          503: errorResponseSchema,
        },
      },
    },
    async (request) => {
      const { workspaceId } = request.params;
      await app.requireWorkspaceMember(request, workspaceId);
      const resolution = await app.ai.resolveConnection({
        request,
        workspaceId,
        connectionId: request.query.connectionId ?? null,
      });

      if (resolution.adapter.capabilities().liveModels) {
        let listed;
        try {
          listed = await resolution.adapter.listModels({
            baseUrl: resolution.baseUrl,
            apiKey: resolution.apiKey,
          });
        } catch (err) {
          throw coded(
            app.httpErrors.badGateway('The model list could not be fetched'),
            upstreamCode(err),
          );
        }
        const options = listed.map((m) => ({ id: m.id, label: m.id }));
        const first = options[0]?.id ?? null;
        return {
          provider: resolution.provider,
          connectionId: resolution.connectionId,
          source: 'live',
          // A self-host usually pulls one model; fast = chat there.
          models: { chat: options, fast: options },
          defaults: {
            chat: resolution.row.default_chat_model ?? first,
            fast: resolution.row.default_fast_model ?? first,
          },
        };
      }

      const entry = MODEL_CATALOG[resolution.provider];
      const defaults = catalogDefaults(resolution.provider);
      return {
        provider: resolution.provider,
        connectionId: resolution.connectionId,
        source: 'catalog',
        models: { chat: entry.chat, fast: entry.fast },
        defaults: {
          chat: resolution.row.default_chat_model ?? defaults.chat,
          fast: resolution.row.default_fast_model ?? defaults.fast,
        },
      };
    },
  );

  // ── Connection test: an honest result, not a thrown 502 ──────────────────
  // A test that RAN and found a bad key is a successful test — OPH-220's
  // button wants {ok:false, code} to render, so upstream failures are data.
  app.post(
    '/ai/connections/:connectionId/test',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { connectionId: ULID_PARAM } },
        response: {
          200: {
            type: 'object',
            properties: {
              ok: { type: 'boolean' },
              latencyMs: { type: 'integer' },
              code: { type: 'string' },
              message: { type: 'string' },
            },
          },
          403: errorResponseSchema,
          404: errorResponseSchema,
          503: errorResponseSchema,
        },
      },
    },
    async (request) => {
      const resolution = await app.ai.resolveConnection({
        request,
        connectionId: request.params.connectionId,
      });
      const started = Date.now();
      try {
        await resolution.adapter.verify({
          baseUrl: resolution.baseUrl,
          apiKey: resolution.apiKey,
          signal: AbortSignal.timeout(10000),
        });
        return { ok: true, latencyMs: Date.now() - started };
      } catch (err) {
        const code = upstreamCode(err);
        if (code === 'AI_UPSTREAM_AUTH_FAILED') {
          await app
            .db('ai_connections')
            .where({ id: resolution.connectionId })
            .update({ status: 'error', updated_at: new Date() });
        }
        return { ok: false, code, message: 'The provider refused the connection test' };
      }
    },
  );

  // ── Chat: SSE-over-POST (or the web's Socket.IO room) ─────────────────────
  const chatBodySchema = {
    type: 'object',
    additionalProperties: false,
    required: ['requestId', 'messages'],
    properties: {
      // Client-generated: the cancellation rendezvous and the log correlator.
      requestId: ULID_PARAM,
      connectionId: ULID_PARAM,
      model: { type: 'string', minLength: 1, maxLength: 128 },
      messages: {
        type: 'array',
        minItems: 1,
        maxItems: 40,
        items: {
          type: 'object',
          additionalProperties: false,
          required: ['role', 'content'],
          properties: {
            role: { type: 'string', enum: ['user', 'assistant'] },
            content: { type: 'string', minLength: 1, maxLength: 32768 },
          },
        },
      },
      // STRUCTURED client-packed context (AI.md §7) — the server is the one
      // place fence syntax exists (lib/ai/context.js), so the app's context
      // chip stays an honest view of exactly this structure.
      context: {
        type: 'object',
        additionalProperties: false,
        properties: {
          segments: {
            type: 'array',
            maxItems: 80,
            items: {
              type: 'object',
              additionalProperties: false,
              required: ['tier', 'source', 'text'],
              properties: {
                tier: { type: 'string', enum: ['t0', 't1', 't2'] },
                source: { type: 'string', minLength: 1, maxLength: 32 },
                id: { type: 'string', maxLength: 26 },
                text: { type: 'string', minLength: 1, maxLength: 4000 },
              },
            },
          },
          truncated: { type: 'boolean' },
        },
      },
      transport: { type: 'string', enum: ['sse', 'socket'] },
    },
  };

  app.post(
    '/workspaces/:workspaceId/ai/chat',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { workspaceId: ULID_PARAM } },
        body: chatBodySchema,
        // The SSE branch hijacks the reply, so only the JSON answers are
        // schema-serialized (socket ack + the pre-hijack errors).
        response: {
          200: {
            type: 'object',
            properties: { requestId: { type: 'string' }, transport: { type: 'string' } },
          },
          400: errorResponseSchema,
          403: errorResponseSchema,
          404: errorResponseSchema,
          429: errorResponseSchema,
          503: errorResponseSchema,
        },
      },
    },
    async (request, reply) => {
      const { workspaceId } = request.params;
      await app.requireWorkspaceMember(request, workspaceId);
      const userId = request.user.id;
      const { requestId } = request.body;

      // Rate limit BEFORE any hijack — a 429 is a normal JSON error.
      const verdict = await app.ai.limiter.take(userId);
      if (!verdict.allowed) {
        reply.header('retry-after', String(verdict.retryAfterSec ?? 60));
        throw coded(
          app.httpErrors.tooManyRequests('Slow down — the AI limit refills in a minute'),
          'AI_RATE_LIMITED',
        );
      }

      const resolution = await app.ai.resolveConnection({
        request,
        workspaceId,
        connectionId: request.body.connectionId ?? null,
      });
      if (resolution.authMode === 'instance_env' && (await app.ai.dailyCap.isOver(userId))) {
        reply.header('retry-after', '3600');
        throw coded(
          app.httpErrors.tooManyRequests('Daily AI budget on this instance is used up'),
          'AI_DAILY_CAP',
        );
      }
      const model = request.body.model ?? resolution.models.chat;
      if (!model) {
        throw coded(
          app.httpErrors.badRequest('Pick a model for this connection first'),
          'AI_MODEL_REQUIRED',
        );
      }

      const ac = new AbortController();
      app.ai.registerInflight(requestId, userId, () => ac.abort(ABORT_CANCELLED));
      const chatInput = {
        app,
        resolution,
        requestId,
        model,
        messages: request.body.messages,
        context: request.body.context ?? null,
        userId,
        workspaceId,
        signal: ac.signal,
      };

      if (request.body.transport === 'socket') {
        // Ack now; the stream lands in the caller's personal room. Detached by
        // design — the HTTP request is done, the work is not.
        runChat({ ...chatInput, sink: socketSink(app.io, userId, requestId) })
          .catch((err) => app.log.error({ err: err.message, requestId }, 'ai socket chat failed'))
          .finally(() => app.ai.unregisterInflight(requestId));
        return { requestId, transport: 'socket' };
      }

      // SSE: the reply is hijacked from here on. Client disconnects surface on
      // reply.raw 'close' (NOT request.raw — the OPH-216 fake taught us).
      reply.raw.on('close', () => {
        if (!ac.signal.aborted) ac.abort(ABORT_CLIENT_GONE);
      });
      try {
        await runChat({ ...chatInput, sink: sseSink(reply) });
      } finally {
        app.ai.unregisterInflight(requestId);
      }
    },
  );

  // ── Cancel: always 204 — idempotent, existence never asserted ─────────────
  app.post(
    '/workspaces/:workspaceId/ai/chat/:requestId/cancel',
    {
      ...auth,
      schema: {
        params: {
          type: 'object',
          properties: { workspaceId: ULID_PARAM, requestId: ULID_PARAM },
        },
        response: { 204: { type: 'null' }, 403: errorResponseSchema },
      },
    },
    async (request, reply) => {
      const { workspaceId, requestId } = request.params;
      await app.requireWorkspaceMember(request, workspaceId);
      // Ownership is enforced at the worker holding the stream: the bus
      // message carries the caller's id and only a matching entry aborts.
      await app.ai.requestCancel({ requestId, userId: request.user.id });
      return reply.code(204).send();
    },
  );

  // ── Extraction: utterance → schema-validated proposal (OPH-219) ───────────
  const actionSchema = {
    type: 'object',
    properties: {
      id: { type: 'string' },
      workspaceId: { type: 'string' },
      userId: { type: 'string' },
      source: { type: 'string' },
      requestId: { type: ['string', 'null'] },
      proposal: { type: 'object', additionalProperties: true },
      accepted: { type: ['boolean', 'null'] },
      entityRefs: {
        type: ['array', 'null'],
        items: {
          type: 'object',
          properties: { type: { type: 'string' }, id: { type: 'string' } },
        },
      },
      createdAt: { type: 'string' },
      decidedAt: { type: ['string', 'null'] },
    },
  };

  function serializeAiAction(row) {
    return {
      id: row.id,
      workspaceId: row.workspace_id,
      userId: row.user_id,
      source: row.source,
      requestId: row.request_id ?? null,
      proposal: parseJsonColumn(row.proposal) ?? {},
      accepted: row.accepted === null || row.accepted === undefined ? null : Boolean(row.accepted),
      entityRefs: parseJsonColumn(row.entity_refs),
      createdAt: toIso(row.created_at),
      decidedAt: toIso(row.decided_at),
    };
  }

  app.post(
    '/workspaces/:workspaceId/ai/extract',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { workspaceId: ULID_PARAM } },
        body: {
          type: 'object',
          additionalProperties: false,
          required: ['text', 'source'],
          properties: {
            text: { type: 'string', minLength: 1, maxLength: 8000 },
            source: { type: 'string', enum: ['bubble', 'share', 'quick_add', 'voice'] },
            connectionId: ULID_PARAM,
            locale: { type: 'string', maxLength: 16 },
            timezone: { type: 'string', maxLength: 64 },
            // The app-side default-task-time setting (OPH-161) — invisible to
            // the server, so the client sends it; the fallback IS the
            // product's default default, never an invented hour.
            defaultTaskTime: { type: 'string', pattern: '^([01][0-9]|2[0-3]):[0-5][0-9]$' },
            projectNames: {
              type: 'array',
              maxItems: 100,
              items: { type: 'string', minLength: 1, maxLength: 120 },
            },
          },
        },
        response: {
          200: {
            type: 'object',
            properties: {
              requestId: { type: 'string' },
              actionId: { type: 'string' },
              repaired: { type: 'boolean' },
              proposal: { type: 'object', additionalProperties: true },
            },
          },
          400: errorResponseSchema,
          403: errorResponseSchema,
          422: errorResponseSchema,
          429: errorResponseSchema,
          502: errorResponseSchema,
          503: errorResponseSchema,
        },
      },
    },
    async (request, reply) => {
      const { workspaceId } = request.params;
      await app.requireWorkspaceMember(request, workspaceId);
      const userId = request.user.id;

      // One bucket with chat — both drain the same provider quota.
      const verdict = await app.ai.limiter.take(userId);
      if (!verdict.allowed) {
        reply.header('retry-after', String(verdict.retryAfterSec ?? 60));
        throw coded(
          app.httpErrors.tooManyRequests('Slow down — the AI limit refills in a minute'),
          'AI_RATE_LIMITED',
        );
      }
      const resolution = await app.ai.resolveConnection({
        request,
        workspaceId,
        connectionId: request.body.connectionId ?? null,
      });
      if (resolution.authMode === 'instance_env' && (await app.ai.dailyCap.isOver(userId))) {
        reply.header('retry-after', '3600');
        throw coded(
          app.httpErrors.tooManyRequests('Daily AI budget on this instance is used up'),
          'AI_DAILY_CAP',
        );
      }
      // Extraction ALWAYS runs on the fast class (the ADR-0019 cost ceiling —
      // no per-request override).
      const model = resolution.models.fast ?? resolution.models.chat;
      if (!model) {
        throw coded(
          app.httpErrors.badRequest('Pick a model for this connection first'),
          'AI_MODEL_REQUIRED',
        );
      }

      const userRow = await app.db('users').where({ id: userId }).first();
      const timezone = request.body.timezone ?? userRow?.timezone ?? 'UTC';
      const now = new Date();
      const prompt = buildExtractionPrompt({
        nowIso: formatInstantWithOffset(now, timezone),
        timezone,
        weekday: new Intl.DateTimeFormat('en-US', { timeZone: timezone, weekday: 'long' }).format(
          now,
        ),
        defaultTaskTime: request.body.defaultTaskTime ?? '23:59',
        locale: request.body.locale ?? userRow?.locale ?? null,
        projectNames: request.body.projectNames ?? [],
        source: request.body.source,
        text: request.body.text,
      });

      const requestId = newId();
      let totalTokens = 0;
      const onUsage = async (usage) => {
        totalTokens += (usage?.inputTokens ?? 0) + (usage?.outputTokens ?? 0);
        await app.ai.recordUsage({
          workspaceId,
          userId,
          connectionId: resolution.connectionId,
          provider: resolution.provider,
          kind: 'extract',
          model,
          inputTokens: usage?.inputTokens ?? null,
          outputTokens: usage?.outputTokens ?? null,
          requestId,
        });
      };

      let outcome;
      try {
        outcome = await extractTasks({
          adapter: resolution.adapter,
          provider: resolution.provider,
          baseUrl: resolution.baseUrl,
          apiKey: resolution.apiKey,
          model,
          prompt,
          onUsage,
          now,
        });
      } catch (err) {
        if (err?.code === 'AI_EXTRACTION_INVALID') {
          // Usage rows exist (the calls happened); NO action-log row — the
          // log records proposals that reached a human.
          throw coded(
            app.httpErrors.unprocessableEntity('The AI could not produce a valid proposal'),
            'AI_EXTRACTION_INVALID',
          );
        }
        if (err?.name === 'AiProviderError') {
          // Same discipline as runChat: log the provider's verdict (status +
          // capped message, no content) — the live 502s were unexplainable
          // without it — and let the client show something actionable.
          const detail = upstreamMessage(err);
          request.log.warn(
            { err: err.message, status: err.status ?? null, upstream: detail },
            'ai extract upstream failed',
          );
          throw coded(
            app.httpErrors.badGateway(detail ?? 'The AI provider failed'),
            upstreamCode(err),
          );
        }
        throw err;
      } finally {
        await app.ai.touchConnection(resolution.connectionId);
        if (resolution.authMode === 'instance_env') {
          await app.ai.dailyCap.add(userId, totalTokens);
        }
      }

      const actionId = newId();
      await app.db('ai_action_log').insert({
        id: actionId,
        workspace_id: workspaceId,
        user_id: userId,
        source: request.body.source,
        request_id: requestId,
        proposal: JSON.stringify(outcome.proposal),
        accepted: null,
      });
      return { requestId, actionId, repaired: outcome.repaired, proposal: outcome.proposal };
    },
  );

  // ── Decision: the human verdict on a proposal (append-once evidence) ──────
  app.post(
    '/ai/actions/:actionId/decision',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { actionId: ULID_PARAM } },
        body: {
          type: 'object',
          additionalProperties: false,
          required: ['accepted'],
          properties: {
            accepted: { type: 'boolean' },
            entityRefs: {
              type: 'array',
              maxItems: 20,
              items: {
                type: 'object',
                additionalProperties: false,
                required: ['type', 'id'],
                properties: {
                  type: { type: 'string', enum: ['task', 'note'] },
                  id: ULID_PARAM,
                },
              },
            },
          },
        },
        response: {
          200: actionSchema,
          404: errorResponseSchema,
          409: errorResponseSchema,
        },
      },
    },
    async (request) => {
      const row = await app.db('ai_action_log').where({ id: request.params.actionId }).first();
      if (!row) {
        throw coded(app.httpErrors.notFound('AI action not found'), 'AI_ACTION_NOT_FOUND');
      }
      await app.requireWorkspaceMember(request, row.workspace_id);
      if (row.user_id !== request.user.id) {
        // 404, not 403 — the co-member privacy stance, as everywhere.
        throw coded(app.httpErrors.notFound('AI action not found'), 'AI_ACTION_NOT_YOURS');
      }

      const accepted = request.body.accepted;
      if (row.accepted !== null && row.accepted !== undefined) {
        // First decision wins — evidence is append-once (the Epic 16 lesson).
        // The SAME decision repeated is a quiet no-op so the app's offline
        // report queue can retry safely; a DIFFERENT one is a conflict.
        if (Boolean(row.accepted) === accepted) return serializeAiAction(row);
        throw coded(
          app.httpErrors.conflict('This proposal was already decided'),
          'AI_ACTION_DECIDED',
        );
      }

      await app
        .db('ai_action_log')
        .where({ id: row.id })
        .update({
          accepted,
          entity_refs: request.body.entityRefs ? JSON.stringify(request.body.entityRefs) : null,
          decided_at: new Date(),
        });
      const fresh = await app.db('ai_action_log').where({ id: row.id }).first();
      return serializeAiAction(fresh);
    },
  );
}
