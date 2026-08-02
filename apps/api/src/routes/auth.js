import crypto from 'node:crypto';
import { coded } from '../lib/errors.js';
import { newId } from '../lib/ids.js';
import { hashPassword, verifyPassword } from '../lib/passwords.js';
import { OauthIdentityError, verifyIdentityToken } from '../lib/oauth-identity.js';
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

const oauthResultSchema = {
  type: 'object',
  required: ['user', 'created', 'tokens'],
  properties: {
    user: userSchema,
    // Whether this call brought a new account into existence — the app shows
    // the onboarding tour on true and goes straight to Home on false.
    created: { type: 'boolean' },
    tokens: tokensSchema,
  },
};

const oauthSchema = {
  body: {
    type: 'object',
    additionalProperties: false,
    required: ['provider', 'idToken'],
    properties: {
      provider: { type: 'string', enum: ['google', 'apple'] },
      // Providers do not publish a maximum length; 8 KB is far above any real
      // ID token and far below anything worth parsing from a hostile client.
      idToken: { type: 'string', minLength: 16, maxLength: 8192 },
    },
  },
  response: {
    200: oauthResultSchema,
    201: oauthResultSchema,
    400: errorResponseSchema,
    401: errorResponseSchema,
    409: errorResponseSchema,
    503: errorResponseSchema,
  },
};

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

  // ── OPH-231 — Sign in with Google / Apple (ADR-0026) ──────────────────────
  //
  // The app performs the native sign-in and posts the provider's ID TOKEN here.
  // This route proves the token is genuine (lib/oauth-identity.js) and then maps
  // the identity onto an AllisWell account, which remains the source of truth.
  //
  // The account-matching rule is the security-critical part, so it is spelled
  // out rather than implied:
  //
  //   1. Known (provider, subject)      → that user. The only stable key there is.
  //   2. Unknown subject, VERIFIED email
  //      matching an existing account   → link, and sign in as them.
  //   3. Unknown subject, unverified or
  //      absent email                   → a NEW account. Never a link.
  //
  // Rule 3 is what stops account takeover. An unverified e-mail claim is just a
  // string the provider passed along; honouring it would let anyone who can put
  // `mahir@example.com` in a token adopt that account. Google marks its own
  // addresses verified; Apple's private-relay addresses arrive verified too, and
  // Apple omits the address entirely after the first authorisation — which rule 1
  // already covers.
  app.post('/oauth', { schema: oauthSchema, config: authRateLimit }, async (request, reply) => {
    const { provider, idToken } = request.body;

    let identity;
    try {
      identity = await verifyIdentityToken(app.config, { provider, idToken });
    } catch (err) {
      if (err instanceof OauthIdentityError) {
        const problem =
          err.code === 'OAUTH_PROVIDER_NOT_CONFIGURED'
            ? app.httpErrors.serviceUnavailable(err.message)
            : err.code === 'OAUTH_PROVIDER_UNSUPPORTED'
              ? app.httpErrors.badRequest(err.message)
              : app.httpErrors.unauthorized(err.message);
        throw coded(problem, err.code);
      }
      throw err;
    }

    const existingIdentity = await app
      .db('user_identities')
      .where({ provider: identity.provider, subject: identity.subject })
      .first();

    // Rule 2's candidate — only ever consulted when the provider vouched for
    // the address.
    const linkable =
      !existingIdentity && identity.email && identity.emailVerified
        ? await app
            .db('users')
            .where({ email: identity.email })
            .whereNull('deleted_at')
            .first('id', 'email', 'display_name')
        : null;

    let user;
    let refresh;
    let created = false;

    if (existingIdentity) {
      const row = await app
        .db('users')
        .where({ id: existingIdentity.user_id })
        .whereNull('deleted_at')
        .first('id', 'email', 'display_name');
      if (!row) {
        // The account was deleted but its identity row outlived it — only
        // possible if a cascade was skipped. Refuse rather than resurrect.
        throw coded(
          app.httpErrors.unauthorized('This account no longer exists'),
          'OAUTH_ACCOUNT_GONE',
        );
      }
      user = { id: row.id, email: row.email, displayName: row.display_name };
      await app.db.transaction(async (trx) => {
        await trx('user_identities')
          .where({ id: existingIdentity.id })
          .update({ last_used_at: new Date(), updated_at: new Date() });
        refresh = await createRefreshRecord(trx, auth, {
          userId: user.id,
          familyId: newId(),
          ip: request.ip,
        });
      });
    } else if (linkable) {
      user = { id: linkable.id, email: linkable.email, displayName: linkable.display_name };
      await app.db.transaction(async (trx) => {
        await trx('user_identities').insert({
          id: newId(),
          user_id: user.id,
          provider: identity.provider,
          subject: identity.subject,
          email: identity.email,
          email_verified: identity.emailVerified,
          last_used_at: new Date(),
        });
        refresh = await createRefreshRecord(trx, auth, {
          userId: user.id,
          familyId: newId(),
          ip: request.ip,
        });
      });
    } else {
      created = true;
      const userId = newId();
      const workspaceId = newId();
      const displayName = identity.name ?? null;
      // Apple's "hide my e-mail" and a withheld address both land here. The
      // account still needs a unique, non-null e-mail, so it gets a stable
      // synthetic one derived from the subject — never shown as if the user
      // chose it, and replaceable once they add a real address.
      const email =
        identity.email ?? `${identity.provider}_${identity.subject}@users.noreply.alliswell.space`;
      const workspaceName = `${displayName ?? email.split('@')[0]}'s Space`;
      const workspaceSlug = uniqueSlug(workspaceName);

      try {
        await app.db.transaction(async (trx) => {
          await trx('users').insert({
            id: userId,
            email,
            // No password: this account is reachable only through its provider
            // until the user sets one. `users.password_hash` has been nullable
            // since the first migration precisely for this.
            password_hash: null,
            display_name: displayName,
          });
          await trx('user_identities').insert({
            id: newId(),
            user_id: userId,
            provider: identity.provider,
            subject: identity.subject,
            email: identity.email,
            email_verified: identity.emailVerified,
            last_used_at: new Date(),
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
        if (err?.code === 'ER_DUP_ENTRY' && err.message.includes('uq_users_email')) {
          // An account with this address exists but the provider did not
          // verify it, so rule 3 refused to link. Say so precisely: this is a
          // user who should sign in with their password and link afterwards,
          // not a broken server.
          throw coded(
            app.httpErrors.conflict(
              'An account already uses this e-mail. Sign in with your password, then link this provider.',
            ),
            'OAUTH_EMAIL_TAKEN',
          );
        }
        throw err;
      }
      user = { id: userId, email, displayName };
    }

    return reply.code(created ? 201 : 200).send({
      user,
      created,
      tokens: sessionTokens(app, user, refresh),
    });
  });

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
