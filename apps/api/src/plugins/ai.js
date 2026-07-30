import fp from 'fastify-plugin';

import { newId } from '../lib/ids.js';
import { coded } from '../lib/errors.js';
import { decryptSecret } from '../lib/crypto.js';

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
     * Resolves the connection a request should use and hands back everything
     * an adapter call needs. `connectionId` pins one; otherwise the caller's
     * most recently used live connection in the workspace wins.
     */
    async function resolveConnection({ request, workspaceId, connectionId = null }) {
      let row;
      if (connectionId) {
        row = await app
          .db('ai_connections')
          .where({ id: connectionId })
          .whereNull('deleted_at')
          .first();
        if (!row || row.workspace_id !== workspaceId) {
          throw coded(
            app.httpErrors.notFound('AI connection not found'),
            'AI_CONNECTION_NOT_FOUND',
          );
        }
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

      return {
        row,
        connectionId: row.id,
        provider: row.provider,
        authMode: row.auth_mode,
        apiKey,
        baseUrl,
        models: { chat: row.default_chat_model ?? null, fast: row.default_fast_model ?? null },
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
      try {
        await app
          .db('ai_connections')
          .where({ id: connectionId })
          .update({ last_used_at: new Date() });
      } catch (err) {
        app.log.warn({ err: err.message }, 'ai connection touch failed');
      }
    }

    app.decorate('ai', {
      enabled: ai.enabled,
      // Provider adapter registry — filled by OPH-216 (lib/ai/providers).
      providers: {},
      resolveConnection,
      recordUsage,
      touchConnection,
      notConfigured,
    });
  },
  { name: 'alliswell-ai', dependencies: ['alliswell-mysql', 'alliswell-redis'] },
);
