import crypto from 'node:crypto';
import { newId } from '../lib/ids.js';
import { hashPassword, verifyPassword } from '../lib/passwords.js';
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

const userSchema = {
  type: 'object',
  required: ['id', 'email'],
  properties: {
    id: { type: 'string' },
    email: { type: 'string' },
    displayName: { type: ['string', 'null'] },
  },
};

// Register and login return this exact same shape (OPH-021).
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
        user: userSchema,
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

const loginSchema = {
  body: {
    type: 'object',
    additionalProperties: false,
    required: ['email', 'password'],
    properties: {
      email: { type: 'string', format: 'email', maxLength: 255 },
      // No policy checks here — any stored password must remain loggable-in.
      password: { type: 'string', minLength: 1, maxLength: 128 },
    },
  },
  response: {
    200: {
      type: 'object',
      required: ['user', 'tokens'],
      properties: { user: userSchema, tokens: tokensSchema },
    },
    401: errorResponseSchema,
  },
};

const refreshBodySchema = {
  type: 'object',
  additionalProperties: false,
  required: ['refreshToken'],
  properties: { refreshToken: { type: 'string', minLength: 20, maxLength: 512 } },
};

const refreshSchema = {
  body: refreshBodySchema,
  response: {
    200: {
      type: 'object',
      required: ['user', 'tokens'],
      properties: { user: userSchema, tokens: tokensSchema },
    },
    401: errorResponseSchema,
  },
};

const logoutSchema = {
  body: refreshBodySchema,
  querystring: {
    type: 'object',
    additionalProperties: false,
    properties: { all: { type: 'boolean', default: false } },
  },
  response: { 204: { type: 'null' } },
};

function emailTakenError(app) {
  const err = app.httpErrors.conflict('An account with this email already exists');
  err.code = 'AUTH_EMAIL_TAKEN';
  return err;
}

function invalidRefreshError(app) {
  const err = app.httpErrors.unauthorized('Invalid or expired refresh token');
  err.code = 'AUTH_INVALID_REFRESH_TOKEN';
  return err;
}

function refreshReusedError(app) {
  const err = app.httpErrors.unauthorized(
    'Refresh token reuse detected; every session in this family has been revoked',
  );
  err.code = 'AUTH_REFRESH_REUSED';
  return err;
}

/** Reuse of any token in a family means the chain may be stolen — kill all of it. */
async function revokeFamily(db, familyId) {
  await db('refresh_tokens')
    .where({ family_id: familyId })
    .whereNull('revoked_at')
    .update({ revoked_at: new Date() });
}

// One error for wrong password AND unknown email — no user/pass distinction (OPH-021).
function invalidCredentialsError(app) {
  const err = app.httpErrors.unauthorized('Invalid email or password');
  err.code = 'AUTH_INVALID_CREDENTIALS';
  return err;
}

/**
 * Inserts a refresh-token row (via `db` or an open trx) and returns the raw token.
 * Every login/register starts a new rotation family; refresh (OPH-022) keeps the family.
 */
async function createRefreshRecord(executor, auth, { userId, familyId, ip }) {
  const token = newRefreshToken();
  const expiresAt = new Date(Date.now() + auth.refreshTtlDays * 24 * 60 * 60 * 1000);
  await executor('refresh_tokens').insert({
    id: newId(),
    user_id: userId,
    family_id: familyId,
    token_hash: hashRefreshToken(token, auth.refreshSecret),
    expires_at: expiresAt,
    created_ip: ip ?? null,
  });
  return { token, expiresAt };
}

function sessionTokens(app, user, refresh) {
  return {
    accessToken: app.signAccessToken(user),
    accessTokenExpiresInSec: app.config.auth.accessTtlSec,
    refreshToken: refresh.token,
    refreshTokenExpiresAt: refresh.expiresAt.toISOString(),
  };
}

export default async function authRoutes(app) {
  const { auth } = app.config;
  // Tighter than the global limiter — credential endpoints are brute-force targets.
  const authRateLimit = {
    rateLimit: { max: app.config.rateLimitAuthMax, timeWindow: '1 minute' },
  };

  // Baseline argon2id hash so unknown-email logins burn the same verify cost as
  // wrong-password logins (no email-existence timing oracle).
  const timingSafeDummyHash = await hashPassword(crypto.randomUUID());

  // OPH-020 — create user + personal workspace + first session, all in one transaction.
  app.post(
    '/register',
    { schema: registerSchema, config: authRateLimit },
    async (request, reply) => {
      const email = request.body.email.toLowerCase();
      const displayName = request.body.displayName?.trim() || null;

      // Fast path for the common case; the unique index stays authoritative under races.
      const existing = await app.db('users').where({ email }).first('id');
      if (existing) throw emailTakenError(app);

      const passwordHash = await hashPassword(request.body.password);

      const userId = newId();
      const workspaceId = newId();
      const workspaceName = `${displayName ?? email.split('@')[0]}'s Space`;
      const workspaceSlug = uniqueSlug(workspaceName);
      let refresh;

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
          refresh = await createRefreshRecord(trx, auth, {
            userId,
            familyId: newId(),
            ip: request.ip,
          });
        });
      } catch (err) {
        // Concurrent register with the same email lost the race on uq_users_email.
        if (err?.code === 'ER_DUP_ENTRY' && err.message.includes('uq_users_email')) {
          throw emailTakenError(app);
        }
        throw err;
      }

      const user = { id: userId, email, displayName };
      return reply.code(201).send({
        user,
        workspace: { id: workspaceId, name: workspaceName, slug: workspaceSlug },
        tokens: sessionTokens(app, user, refresh),
      });
    },
  );

  // OPH-021 — verify credentials, start a new session (new refresh-token family).
  app.post('/login', { schema: loginSchema, config: authRateLimit }, async (request) => {
    const email = request.body.email.toLowerCase();

    const user = await app
      .db('users')
      .where({ email })
      .whereNull('deleted_at')
      .first('id', 'email', 'password_hash', 'display_name');

    // Always run one argon2 verify, even for unknown emails (timing-safe failure path).
    // A null password_hash (future OAuth-only accounts) also verifies against the dummy.
    const passwordOk = await verifyPassword(
      user?.password_hash ?? timingSafeDummyHash,
      request.body.password,
    );
    if (!user || !user.password_hash || !passwordOk) throw invalidCredentialsError(app);

    const refresh = await createRefreshRecord(app.db, auth, {
      userId: user.id,
      familyId: newId(),
      ip: request.ip,
    });

    return {
      user: { id: user.id, email: user.email, displayName: user.display_name ?? null },
      tokens: sessionTokens(app, user, refresh),
    };
  });

  // OPH-022 — rotate: retire the presented token, issue a new one in the SAME family.
  app.post('/refresh', { schema: refreshSchema, config: authRateLimit }, async (request) => {
    const tokenHash = hashRefreshToken(request.body.refreshToken, auth.refreshSecret);
    const row = await app.db('refresh_tokens').where({ token_hash: tokenHash }).first();
    if (!row) throw invalidRefreshError(app);

    // An already-rotated (or revoked) token coming back means theft or a very
    // broken client — either way the whole rotation chain is burned.
    if (row.rotated_at || row.revoked_at) {
      await revokeFamily(app.db, row.family_id);
      throw refreshReusedError(app);
    }
    if (new Date(row.expires_at).getTime() <= Date.now()) throw invalidRefreshError(app);

    const user = await app
      .db('users')
      .where({ id: row.user_id })
      .whereNull('deleted_at')
      .first('id', 'email', 'display_name');
    if (!user) throw invalidRefreshError(app);

    let refresh;
    let claimed = 0;
    await app.db.transaction(async (trx) => {
      // Atomic claim: under two concurrent refreshes only one UPDATE matches.
      claimed = await trx('refresh_tokens')
        .where({ id: row.id })
        .whereNull('rotated_at')
        .whereNull('revoked_at')
        .update({ rotated_at: new Date() });
      if (claimed === 0) return;
      refresh = await createRefreshRecord(trx, auth, {
        userId: user.id,
        familyId: row.family_id,
        ip: request.ip,
      });
    });
    if (claimed === 0) {
      // Lost the race — the token was concurrently rotated, i.e. reused.
      await revokeFamily(app.db, row.family_id);
      throw refreshReusedError(app);
    }

    return {
      user: { id: user.id, email: user.email, displayName: user.display_name ?? null },
      tokens: sessionTokens(app, user, refresh),
    };
  });

  // OPH-022 — revoke the presented token (?all=true: its whole family). Always 204:
  // logout must be idempotent and reveal nothing about token validity.
  app.post('/logout', { schema: logoutSchema, config: authRateLimit }, async (request, reply) => {
    const tokenHash = hashRefreshToken(request.body.refreshToken, auth.refreshSecret);
    const row = await app
      .db('refresh_tokens')
      .where({ token_hash: tokenHash })
      .first('id', 'family_id');
    if (row) {
      if (request.query.all) {
        await revokeFamily(app.db, row.family_id);
      } else {
        await app
          .db('refresh_tokens')
          .where({ id: row.id })
          .whereNull('revoked_at')
          .update({ revoked_at: new Date() });
      }
    }
    return reply.code(204).send();
  });
}
