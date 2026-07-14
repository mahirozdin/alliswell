import { newId } from '../lib/ids.js';
import { hashPassword } from '../lib/passwords.js';
import { newRefreshToken, hashRefreshToken } from '../lib/tokens.js';
import { uniqueSlug } from '../lib/slug.js';

const errorResponseSchema = {
  type: 'object',
  properties: {
    statusCode: { type: 'integer' },
    code: { type: 'string' },
    error: { type: 'string' },
    message: { type: 'string' },
  },
};

// Login (OPH-021) must return this exact same shape.
const tokensSchema = {
  type: 'object',
  required: ['accessToken', 'accessTokenExpiresInSec', 'refreshToken', 'refreshTokenExpiresAt'],
  properties: {
    accessToken: { type: 'string' },
    accessTokenExpiresInSec: { type: 'integer' },
    refreshToken: { type: 'string' },
    refreshTokenExpiresAt: { type: 'string' },
  },
};

const registerSchema = {
  body: {
    type: 'object',
    additionalProperties: false,
    required: ['email', 'password'],
    properties: {
      email: { type: 'string', format: 'email', maxLength: 255 },
      password: { type: 'string', minLength: 8, maxLength: 128 },
      displayName: { type: 'string', minLength: 1, maxLength: 255 },
    },
  },
  response: {
    201: {
      type: 'object',
      required: ['user', 'workspace', 'tokens'],
      properties: {
        user: {
          type: 'object',
          required: ['id', 'email'],
          properties: {
            id: { type: 'string' },
            email: { type: 'string' },
            displayName: { type: ['string', 'null'] },
          },
        },
        workspace: {
          type: 'object',
          required: ['id', 'name', 'slug'],
          properties: {
            id: { type: 'string' },
            name: { type: 'string' },
            slug: { type: 'string' },
          },
        },
        tokens: tokensSchema,
      },
    },
    409: errorResponseSchema,
  },
};

function emailTakenError(app) {
  const err = app.httpErrors.conflict('An account with this email already exists');
  err.code = 'AUTH_EMAIL_TAKEN';
  return err;
}

export default async function authRoutes(app) {
  const { auth } = app.config;

  // OPH-020 — create user + personal workspace + first session, all in one transaction.
  app.post('/register', { schema: registerSchema }, async (request, reply) => {
    const email = request.body.email.trim().toLowerCase();
    const displayName = request.body.displayName?.trim() || null;

    // Fast path for the common case; the unique index stays authoritative under races.
    const existing = await app.db('users').where({ email }).first('id');
    if (existing) throw emailTakenError(app);

    const passwordHash = await hashPassword(request.body.password);

    const userId = newId();
    const workspaceId = newId();
    const workspaceName = `${displayName ?? email.split('@')[0]}'s Space`;
    const workspaceSlug = uniqueSlug(workspaceName);
    const refreshToken = newRefreshToken();
    const refreshExpiresAt = new Date(Date.now() + auth.refreshTtlDays * 24 * 60 * 60 * 1000);

    try {
      await app.db.transaction(async (trx) => {
        await trx('users').insert({
          id: userId,
          email,
          password_hash: passwordHash,
          display_name: displayName,
        });
        await trx('workspaces').insert({
          id: workspaceId,
          owner_id: userId,
          name: workspaceName,
          slug: workspaceSlug,
        });
        await trx('workspace_members').insert({
          id: newId(),
          workspace_id: workspaceId,
          user_id: userId,
          role: 'owner',
        });
        await trx('refresh_tokens').insert({
          id: newId(),
          user_id: userId,
          family_id: newId(),
          token_hash: hashRefreshToken(refreshToken, auth.refreshSecret),
          expires_at: refreshExpiresAt,
          created_ip: request.ip,
        });
      });
    } catch (err) {
      // Concurrent register with the same email lost the race on uq_users_email.
      if (err?.code === 'ER_DUP_ENTRY' && err.message.includes('uq_users_email')) {
        throw emailTakenError(app);
      }
      throw err;
    }

    return reply.code(201).send({
      user: { id: userId, email, displayName },
      workspace: { id: workspaceId, name: workspaceName, slug: workspaceSlug },
      tokens: {
        accessToken: app.signAccessToken({ id: userId, email }),
        accessTokenExpiresInSec: auth.accessTtlSec,
        refreshToken,
        refreshTokenExpiresAt: refreshExpiresAt.toISOString(),
      },
    });
  });
}
