import { EventEmitter } from 'node:events';
import fp from 'fastify-plugin';

import { newId } from '../lib/ids.js';
import { coded } from '../lib/errors.js';
import { decryptSecret } from '../lib/crypto.js';
import { providers } from '../lib/ai/providers/index.js';
import { catalogDefaults } from '../lib/ai/models.js';
import { createRateLimiter, createDailyCap } from '../lib/ai/ratelimit.js';

/**
 * The AI seam (OPH-215, Epic 20, ADR-0019): connection resolution, key
 * decryption and accounting live here so routes (and later the MCP track)
 * share one implementation.
 *
 * The plugin always registers — even with AI_ENABLED=false — because the
 * decorator is cheap and other modules consult `app.ai.enabled`. The routes
 * themselves are conditionally registered in app.js: a disabled feature
 * answers 404 like a feature that never existed (TASKS' required semantics).
 *
 * Decrypted keys exist only in the returned resolution object on the request
 * stack — they are never logged, stored, or serialized (the ADR-0006 stance).
 */

export default fp(
  async function aiPlugin(app) {
    const { ai } = app.config;

    function notConfigured() {
      return coded(
        app.httpErrors.serviceUnavailable(
          'No AI connection is configured — add a provider in Settings',
        ),
        'AI_NOT_CONFIGURED',
      );
    }

    /**
     * Builds a resolution around a credential an extension supplied
     * (`seam.registerAiConnectionResolver`). Core owns this shape, so the
     * extension describes a credential and nothing more.
     *
     * `row` and `connectionId` are null and stay null: there is no
     * `ai_connections` row behind this credential. Every core path that
     * touches them already tolerates it — the meter's `connection_id` is
     * nullable (and `provider` is denormalized beside it for exactly this
     * kind of reason), and `touchConnection` returns early.
     *
     * `authMode` is `api_key` because the only thing core reads it for is
     * whether the INSTANCE's daily token budget applies, and it does not: an
     * extension that brought its own credential is not spending the
     * operator's. A ceiling on that credential is the extension's to enforce.
     */
    function extensionResolution(credential) {
      const provider = credential?.provider;
      const adapter = providers[provider];
      if (!adapter) {
        throw new Error(
          `AI connection resolver returned an unknown provider "${provider}" — ` +
            `known: ${Object.keys(providers).join(', ')}`,
        );
      }
      const defaults = catalogDefaults(provider);
      return {
        row: null,
        connectionId: null,
        provider,
        adapter,
        authMode: 'api_key',
        apiKey: credential.apiKey ?? null,
        baseUrl: credential.baseUrl ?? ai.baseUrls[provider] ?? null,
        models: {
          chat: credential.models?.chat ?? defaults.chat,
          fast: credential.models?.fast ?? defaults.fast,
        },
      };
    }

    /**
     * The extension chain. Empty on every plain build, which is why the
     * function below is unchanged for CE: an empty array short-circuits
     * before anything is asked.
     *
     * Consulted on EVERY resolution, including a pinned one — but a pinned
     * resolution only honours a REFUSAL (a resolver that throws), never a
     * credential. Pinning names a row out of the caller's own list and core
     * keeps that promise; what an extension may still say is "not this one,
     * not here", which is an authorisation answer rather than a resolution.
     * Consulting only the unpinned path would have made that refusal
     * bypassable by naming a connection, which is not a refusal at all.
     */
    async function resolveFromExtensions(request, { workspaceId, connectionId }) {
      const resolvers = app.ee?.aiConnectionResolvers;
      if (!resolvers || resolvers.length === 0) return null;
      for (const resolver of resolvers) {
        const credential = await resolver(request, { workspaceId, connectionId });
        if (credential) return extensionResolution(credential);
      }
      return null;
    }

    /**
     * Resolves the connection a request should use and hands back everything
     * an adapter call needs. `connectionId` pins one (workspaceId optional —
     * derived from the row after a membership re-check); otherwise the
     * caller's most recently used live connection in `workspaceId` wins.
     */
    async function resolveConnection({ request, workspaceId = null, connectionId = null }) {
      // Before anything else, so a refusal costs no query and a pinned
      // request cannot outrun it. The value is used only when nothing was
      // pinned — see `resolveFromExtensions`.
      const extension = await resolveFromExtensions(request, { workspaceId, connectionId });
      if (extension && !connectionId) return extension;

      let row;
      if (connectionId) {
        row = await app
          .db('ai_connections')
          .where({ id: connectionId })
          .whereNull('deleted_at')
          .first();
        if (!row || (workspaceId && row.workspace_id !== workspaceId)) {
          throw coded(
            app.httpErrors.notFound('AI connection not found'),
            'AI_CONNECTION_NOT_FOUND',
          );
        }
        await app.requireWorkspaceMember(request, row.workspace_id);
        if (row.user_id !== request.user.id) {
          // 404, not 403: the status must not confirm a co-member's row exists.
          throw coded(
            app.httpErrors.notFound('AI connection not found'),
            'AI_CONNECTION_NOT_YOURS',
          );
        }
      } else {
        const rows = await app
          .db('ai_connections')
          .where({ workspace_id: workspaceId, user_id: request.user.id })
          .whereNull('deleted_at')
          .orderBy('last_used_at', 'desc')
          .orderBy('created_at', 'desc')
          .select();
        row = rows[0];
        if (!row) throw notConfigured();
      }

      let apiKey = null;
      let baseUrl = row.base_url ?? ai.baseUrls[row.provider] ?? null;
      if (row.auth_mode === 'instance_env') {
        if (row.provider === 'ollama') {
          baseUrl = ai.baseUrls.ollama;
          if (!baseUrl) throw notConfigured();
        } else {
          apiKey = ai.instanceKeys[row.provider];
          if (!apiKey) throw notConfigured();
        }
      } else if (row.encrypted_key) {
        apiKey = decryptSecret(row.encrypted_key, ai.tokenKey);
      }

      const defaults = catalogDefaults(row.provider);
      return {
        row,
        connectionId: row.id,
        provider: row.provider,
        adapter: providers[row.provider],
        authMode: row.auth_mode,
        apiKey,
        baseUrl,
        models: {
          chat: row.default_chat_model ?? defaults.chat,
          fast: row.default_fast_model ?? defaults.fast,
        },
      };
    }

    /**
     * Accounting, never content (AI.md §2). Fire-and-forget by contract: a
     * broken meter must never break a reply, so failures are logged and eaten.
     */
    async function recordUsage({
      workspaceId,
      userId,
      connectionId = null,
      provider,
      kind,
      model,
      inputTokens = null,
      outputTokens = null,
      durationMs = null,
      requestId = null,
    }) {
      try {
        await app.db('ai_usage_events').insert({
          id: newId(),
          workspace_id: workspaceId,
          user_id: userId,
          connection_id: connectionId,
          provider,
          kind,
          model,
          input_tokens: inputTokens,
          output_tokens: outputTokens,
          duration_ms: durationMs,
          request_id: requestId,
        });
      } catch (err) {
        app.log.warn({ err: err.message }, 'ai usage row failed');
      }
    }

    /** last_used_at bump — plain UPDATE, not a sync entity, fire-and-forget. */
    async function touchConnection(connectionId) {
      // An extension-resolved connection has no row here (and `where id = null`
      // would be a pointless query rather than a wrong one).
      if (!connectionId) return;
      try {
        await app
          .db('ai_connections')
          .where({ id: connectionId })
          .update({ last_used_at: new Date() });
      } catch (err) {
        app.log.warn({ err: err.message }, 'ai connection touch failed');
      }
    }

    // ── OPH-217: rate limiting, daily caps, and the cancel bus ──────────────
    const limiter = createRateLimiter({
      redis: app.redis,
      keyPrefix: app.config.redisKeyPrefix,
      ratePerMinute: ai.ratePerMinute,
      burst: ai.rateBurst,
      log: app.log,
    });
    const dailyCap = createDailyCap({
      redis: app.redis,
      keyPrefix: app.config.redisKeyPrefix,
      capTokens: ai.dailyTokenCap,
      log: app.log,
    });

    /**
     * In-flight streams on THIS worker: requestId → {userId, abort}. The
     * cancel bus fans a cancel out to every worker (Redis pub/sub when up, a
     * local EventEmitter otherwise); ownership is enforced at the worker that
     * HOLDS the stream — a caller can only ever kill their own request.
     */
    const inflight = new Map();
    const localBus = new EventEmitter();
    const cancelChannel = `${app.config.redisKeyPrefix}:ai:cancel`;

    function handleCancel({ requestId, userId }) {
      const entry = inflight.get(requestId);
      if (entry && entry.userId === userId) entry.abort();
    }
    localBus.on('cancel', handleCancel);

    let cancelSub = null;
    if (typeof app.redis?.duplicate === 'function' && app.redis.status === 'ready') {
      const options = { lazyConnect: false, enableOfflineQueue: true, maxRetriesPerRequest: null };
      cancelSub = app.redis.duplicate(options);
      cancelSub.subscribe(cancelChannel).catch((err) => {
        app.log.warn({ err: err.message }, 'ai cancel bus subscribe failed');
      });
      cancelSub.on('message', (channel, message) => {
        if (channel !== cancelChannel) return;
        try {
          handleCancel(JSON.parse(message));
        } catch {
          /* a malformed bus message is noise, not a crash */
        }
      });
      app.addHook('onClose', async () => {
        cancelSub.disconnect();
      });
    }

    async function requestCancel({ requestId, userId }) {
      if (cancelSub) {
        try {
          // Our own subscription delivers locally too — no double-emit path.
          await app.redis.publish(cancelChannel, JSON.stringify({ requestId, userId }));
          return;
        } catch (err) {
          app.log.warn({ err: err.message }, 'ai cancel publish failed; falling back local');
        }
      }
      localBus.emit('cancel', { requestId, userId });
    }

    app.decorate('ai', {
      enabled: ai.enabled,
      providers,
      resolveConnection,
      recordUsage,
      touchConnection,
      notConfigured,
      limiter,
      dailyCap,
      registerInflight: (requestId, userId, abort) => inflight.set(requestId, { userId, abort }),
      unregisterInflight: (requestId) => inflight.delete(requestId),
      requestCancel,
    });
  },
  {
    name: 'alliswell-ai',
    dependencies: ['alliswell-mysql', 'alliswell-redis', 'alliswell-auth'],
  },
);
