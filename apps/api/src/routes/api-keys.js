import { newId } from '../lib/ids.js';
import { coded } from '../lib/errors.js';
import { toIso } from '../lib/serialize.js';
import { apiKeyPrefixOf, newApiKey } from '../lib/api-keys.js';
import { hashApiKey } from '../lib/tokens.js';

/**
 * API-key management (OPH-264, ADR-0032, issue #3).
 *
 * JWT ONLY: every route here carries `rejectApiKeys`, because a key that can
 * mint or revoke keys makes revocation meaningless — the attacker holding a
 * leaked key would simply issue a second one.
 *
 * The secret leaves the server exactly once, in the 201 body. After that only
 * its digest exists, so "show it again" is not a feature we declined to build,
 * it is a thing that cannot be done.
 */

const ULID_PARAM = { type: 'string', minLength: 26, maxLength: 26 };

// The three the UI offers (OPH-265), plus open-ended when omitted. An enum
// rather than a free integer: a key that expires in 100000 days is a key that
// never expires, said less honestly.
const EXPIRY_CHOICES = [30, 90, 365];

const errorResponseSchema = {
  type: 'object',
  properties: {
    statusCode: { type: 'integer' },
    code: { type: 'string' },
    error: { type: 'string' },
    message: { type: 'string' },
  },
};

const apiKeySchema = {
  type: 'object',
  required: ['id', 'name', 'keyPrefix', 'createdAt'],
  properties: {
    id: { type: 'string' },
    workspaceId: { type: 'string' },
    name: { type: 'string' },
    keyPrefix: { type: 'string' },
    createdAt: { type: 'string' },
    expiresAt: { type: ['string', 'null'] },
    lastUsedAt: { type: ['string', 'null'] },
    revokedAt: { type: ['string', 'null'] },
  },
};

export function serializeApiKey(row) {
  return {
    id: row.id,
    workspaceId: row.workspace_id,
    name: row.name,
    keyPrefix: row.key_prefix,
    createdAt: toIso(row.created_at),
    expiresAt: toIso(row.expires_at),
    lastUsedAt: toIso(row.last_used_at),
    revokedAt: toIso(row.revoked_at),
  };
}

export default async function apiKeyRoutes(app) {
  const auth = { onRequest: [app.authenticate], preHandler: [app.rejectApiKeys] };

  app.get(
    '/workspaces/:workspaceId/api-keys',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { workspaceId: ULID_PARAM } },
        response: {
          200: {
            type: 'object',
            properties: { items: { type: 'array', items: apiKeySchema } },
          },
          403: errorResponseSchema,
        },
      },
    },
    async (request) => {
      const { workspaceId } = request.params;
      await app.requireWorkspaceMember(request, workspaceId);
      // A key belongs to the person who made it: co-members of a workspace do
      // not see (or revoke) each other's keys.
      const rows = await app
        .db('api_keys')
        .where({ workspace_id: workspaceId, user_id: request.user.id })
        .orderBy('created_at', 'desc')
        .select();
      return { items: rows.map(serializeApiKey) };
    },
  );

  app.post(
    '/workspaces/:workspaceId/api-keys',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { workspaceId: ULID_PARAM } },
        body: {
          type: 'object',
          additionalProperties: false,
          required: ['name'],
          properties: {
            name: { type: 'string', minLength: 1, maxLength: 100 },
            expiresInDays: { type: 'integer', enum: EXPIRY_CHOICES },
          },
        },
        response: {
          201: {
            ...apiKeySchema,
            required: [...apiKeySchema.required, 'key'],
            properties: {
              ...apiKeySchema.properties,
              // The ONLY time this value exists outside the caller's hands.
              key: { type: 'string' },
            },
          },
          400: errorResponseSchema,
          403: errorResponseSchema,
        },
      },
    },
    async (request, reply) => {
      const { workspaceId } = request.params;
      await app.requireWorkspaceMember(request, workspaceId);

      const token = newApiKey();
      const id = newId();
      const expiresAt = request.body.expiresInDays
        ? new Date(Date.now() + request.body.expiresInDays * 86400000)
        : null;

      await app.db('api_keys').insert({
        id,
        user_id: request.user.id,
        workspace_id: workspaceId,
        name: request.body.name,
        key_hash: hashApiKey(token, app.config.auth.refreshSecret),
        key_prefix: apiKeyPrefixOf(token),
        expires_at: expiresAt,
      });

      // Deliberately NOT logged, at any level: this is the one line that could
      // put a live credential in a log file.
      request.log.info({ apiKeyId: id, workspaceId }, 'api key created');

      const row = await app.db('api_keys').where({ id }).first();
      return reply.code(201).send({ ...serializeApiKey(row), key: token });
    },
  );

  app.post(
    '/api-keys/:keyId/revoke',
    {
      ...auth,
      schema: {
        params: { type: 'object', properties: { keyId: ULID_PARAM } },
        response: { 200: apiKeySchema, 403: errorResponseSchema, 404: errorResponseSchema },
      },
    },
    async (request) => {
      const row = await app.db('api_keys').where({ id: request.params.keyId }).first();
      // Somebody else's key is not "forbidden", it is not there — the same
      // rule the rest of the API follows about other people's rows.
      if (!row || row.user_id !== request.user.id) {
        throw coded(app.httpErrors.notFound('API key not found'), 'API_KEY_NOT_FOUND');
      }
      // Idempotent: revoking a revoked key keeps the original timestamp, which
      // is the honest answer to "when did this stop working?".
      if (!row.revoked_at) {
        await app.db('api_keys').where({ id: row.id }).update({ revoked_at: new Date() });
      }
      return serializeApiKey(await app.db('api_keys').where({ id: row.id }).first());
    },
  );
}
