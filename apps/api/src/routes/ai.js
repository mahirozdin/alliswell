import { newId } from '../lib/ids.js';
import { coded } from '../lib/errors.js';
import { toIso } from '../lib/serialize.js';
import { encryptSecret } from '../lib/crypto.js';

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
}
