import crypto from 'node:crypto';
import { coded } from '../lib/errors.js';
import { newId } from '../lib/ids.js';
import { hashPassword, verifyPassword } from '../lib/passwords.js';
import { OauthIdentityError, verifyIdentityToken } from '../lib/oauth-identity.js';
import { hashRefreshToken } from '../lib/tokens.js';
import { uniqueSlug } from '../lib/slug.js';
import {
  createRefreshRecord,
  deviceLabel,
  familyOfToken,
  listUserSessions,
  revokeOtherSessions,
  revokeSession,
  sessionTokens,
} from '../db/sessions.js';
import {
  confirmTotpEnrolment,
  disableTotp,
  regenerateRecoveryCodes,
  startTotpEnrolment,
  totpStatus,
  verifyUserTotp,
} from '../db/totp.js';

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
      // OPH-283. Optional because most accounts have no second factor; when
      // one is enrolled its absence is a 401 with its own code, so a client
      // knows to ask rather than to say the password was wrong.
      // Wide enough for a recovery code, which is the other thing this field
      // legitimately carries.
      totpCode: { type: 'string', minLength: 6, maxLength: 32 },
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
 * OPH-283 — the refusals that come AFTER a correct password.
 *
 * Deliberately distinguishable from `AUTH_INVALID_CREDENTIALS`, and the reason
 * is not convenience: a client that cannot tell "your password is wrong" from
 * "now give me your code" has to guess, and every guess it makes is a worse
 * prompt for the person typing. The disclosure this costs is real and small —
 * it tells somebody who ALREADY HAS the right password that the account has a
 * second factor, which they were about to discover anyway.
 */
function mfaError(app, code, message) {
  const err = app.httpErrors.unauthorized(message);
  err.code = code;
  return err;
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
            deviceName: deviceLabel(request),
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
          deviceName: deviceLabel(request),
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
          deviceName: deviceLabel(request),
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
            deviceName: deviceLabel(request),
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

    const found = await app
      .db('users')
      .where({ email })
      .whereNull('deleted_at')
      .first('id', 'email', 'password_hash', 'display_name');

    // ── OPH-286: is this credential ours to check at all? ────────────────
    //
    // Asked BEFORE the password and for EVERY address, including ones with no
    // account here — see `registerCredentialVerifier`. With none registered
    // (every CE install) the loop does not run, `claim` stays null, and every
    // line below is the one that was here before.
    let claim = null;
    for (const verify of app.ee.credentialVerifiers) {
      const outcome = await verify({
        db: app.db,
        email,
        password: request.body.password,
        user: found ?? null,
        request,
      });
      // Anything falsy means "not mine" — the answer that keeps this seam
      // invisible. The first verifier to claim the address settles it.
      if (outcome) {
        claim = outcome;
        break;
      }
    }

    const refuse = async () => {
      // OPH-283: tell whoever is counting, then refuse exactly as before.
      // Errors are swallowed on purpose — a counter that throws would turn
      // this 401 into a 500 and hand an attacker an oracle.
      for (const observe of app.ee.signInFailureObservers) {
        try {
          await observe({ db: app.db, email, user: found ?? null, request });
        } catch (err) {
          request.log.warn({ err: err.message }, 'sign-in failure observer threw');
        }
      }
      throw invalidCredentialsError(app);
    };

    let user;
    if (claim === null) {
      // Always run one argon2 verify, even for unknown emails (timing-safe failure path).
      // A null password_hash (future OAuth-only accounts) also verifies against the dummy.
      const passwordOk = await verifyPassword(
        found?.password_hash ?? timingSafeDummyHash,
        request.body.password,
      );
      if (!found || !found.password_hash || !passwordOk) await refuse();
      user = found;
    } else if (!claim.ok) {
      await refuse();
    } else {
      // A verifier names who signed in; core decides whether that person
      // exists. Re-read rather than trusting the handed-back row: the account
      // in MySQL is the source of truth, so a claim naming a deleted or
      // unknown id is a refusal, not a session.
      user = await app
        .db('users')
        .where({ id: claim.userId })
        .whereNull('deleted_at')
        .first('id', 'email', 'password_hash', 'display_name');
      if (!user) await refuse();
    }

    // ── OPH-283: the second factor, and then the policy ──────────────────
    //
    // Both run only after the password is right. A factor check on an unknown
    // address would answer a question the caller has not earned, and a policy
    // consulted before the password would let an extension refuse sign-ins for
    // accounts whose credentials were never presented.
    const factors = await totpStatus(app.db, user.id);
    let totpVerified = false;
    if (factors.enrolled) {
      if (!request.body.totpCode) {
        throw mfaError(app, 'AUTH_MFA_REQUIRED', 'This account needs its authenticator code');
      }
      const check = await verifyUserTotp(app.db, {
        userId: user.id,
        code: request.body.totpCode,
        key: app.config.auth.totpKey,
      });
      if (!check.ok) throw mfaError(app, 'AUTH_MFA_INVALID', 'That code is not right');
      totpVerified = true;
    }

    for (const requirement of app.ee.signInRequirements) {
      // No try/catch: a policy that throws refuses the sign-in, which is the
      // seam's documented contract. Failing open here would make the policy
      // a suggestion.
      const refusal = await requirement({
        db: app.db,
        user,
        request,
        factors: { totpEnrolled: factors.enrolled, totpVerified },
      });
      if (refusal) {
        throw mfaError(
          app,
          refusal.code ?? 'AUTH_SIGN_IN_REFUSED',
          refusal.message ?? 'Sign-in refused',
        );
      }
    }

    const refresh = await createRefreshRecord(app.db, auth, {
      userId: user.id,
      familyId: newId(),
      ip: request.ip,
      deviceName: deviceLabel(request),
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
        // The family KEEPS the device it was born on. A rotation is the same
        // session on the same machine, so re-reading the User-Agent buys
        // nothing — and costs the name outright when a client sends none on
        // its refresh calls, which is common and is how this line was found.
        // The fallback covers families that predate this column being written.
        deviceName: row.device_name ?? deviceLabel(request),
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

  // ── OPH-283: managing your own second factor, and your own password ─────
  //
  // Every route here is about the CALLER's account and takes its subject from
  // the token, never from the body. "Whose factor is this?" is not a question
  // a request gets to answer.
  //
  // `rejectApiKeys` on all of them, following `api-keys.js`: a long-lived
  // machine credential must not be able to change the credentials of the
  // person who issued it. An API key is delegated access to data, not to an
  // identity.
  const selfAuth = { onRequest: [app.authenticate], preHandler: [app.rejectApiKeys] };
  const mfaStatusSchema = {
    type: 'object',
    additionalProperties: false,
    properties: {
      enrolled: { type: 'boolean' },
      staged: { type: 'boolean' },
      recoveryCodesLeft: { type: 'integer' },
    },
  };

  app.get(
    '/mfa/totp',
    { ...selfAuth, schema: { response: { 200: mfaStatusSchema } } },
    async (request) => totpStatus(app.db, request.user.id),
  );

  // Step one: mint a secret and show it. Nothing is protected yet.
  app.post(
    '/mfa/totp',
    {
      ...selfAuth,
      config: authRateLimit,
      schema: {
        response: {
          201: {
            type: 'object',
            additionalProperties: false,
            properties: { secret: { type: 'string' }, uri: { type: 'string' } },
          },
        },
      },
    },
    async (request, reply) => {
      const user = await app.db('users').where({ id: request.user.id }).first('id', 'email');
      if (!user) throw app.httpErrors.notFound('Not found');
      try {
        const started = await startTotpEnrolment(app.db, {
          userId: user.id,
          email: user.email,
          key: app.config.auth.totpKey,
        });
        return reply.code(201).send(started);
      } catch (err) {
        if (err.code === 'TOTP_ALREADY_ENROLLED') {
          throw coded(app.httpErrors.conflict(err.message), err.code);
        }
        throw err;
      }
    },
  );

  // Step two: prove the authenticator agrees. The recovery codes are in this
  // response and in no other, ever.
  app.post(
    '/mfa/totp/confirm',
    {
      ...selfAuth,
      config: authRateLimit,
      schema: {
        body: {
          type: 'object',
          additionalProperties: false,
          required: ['code'],
          properties: { code: { type: 'string', minLength: 6, maxLength: 10 } },
        },
        response: {
          200: {
            type: 'object',
            additionalProperties: false,
            properties: {
              enrolled: { type: 'boolean' },
              recoveryCodes: { type: 'array', items: { type: 'string' } },
            },
          },
        },
      },
    },
    async (request) => {
      try {
        const { recoveryCodes } = await confirmTotpEnrolment(app.db, {
          userId: request.user.id,
          code: request.body.code,
          key: app.config.auth.totpKey,
        });
        return { enrolled: true, recoveryCodes };
      } catch (err) {
        if (err.code === 'TOTP_CODE_WRONG') {
          throw coded(app.httpErrors.unauthorized(err.message), err.code);
        }
        if (err.code === 'TOTP_NOT_STAGED') {
          throw coded(app.httpErrors.badRequest(err.message), err.code);
        }
        if (err.code === 'TOTP_ALREADY_ENROLLED') {
          throw coded(app.httpErrors.conflict(err.message), err.code);
        }
        throw err;
      }
    },
  );

  // Turning it off asks for a live code, for the same reason turning it on
  // did: a session somebody else is holding must not be able to remove the
  // thing that would have stopped them.
  app.delete(
    '/mfa/totp',
    {
      ...selfAuth,
      config: authRateLimit,
      schema: {
        body: {
          type: 'object',
          additionalProperties: false,
          required: ['code'],
          properties: { code: { type: 'string', minLength: 6, maxLength: 32 } },
        },
      },
    },
    async (request, reply) => {
      const status = await totpStatus(app.db, request.user.id);
      if (!status.enrolled) throw app.httpErrors.notFound('Not found');
      const check = await verifyUserTotp(app.db, {
        userId: request.user.id,
        code: request.body.code,
        key: app.config.auth.totpKey,
      });
      if (!check.ok) throw mfaError(app, 'AUTH_MFA_INVALID', 'That code is not right');
      await disableTotp(app.db, request.user.id);
      return reply.code(204).send();
    },
  );

  // A fresh set, when the old paper is lost or half spent. Asks for a code
  // because handing out ten new keys is exactly as sensitive as the first ten.
  app.post(
    '/mfa/totp/recovery-codes',
    {
      ...selfAuth,
      config: authRateLimit,
      schema: {
        body: {
          type: 'object',
          additionalProperties: false,
          required: ['code'],
          properties: { code: { type: 'string', minLength: 6, maxLength: 32 } },
        },
        response: {
          200: {
            type: 'object',
            additionalProperties: false,
            properties: { recoveryCodes: { type: 'array', items: { type: 'string' } } },
          },
        },
      },
    },
    async (request) => {
      const status = await totpStatus(app.db, request.user.id);
      if (!status.enrolled) throw app.httpErrors.notFound('Not found');
      const check = await verifyUserTotp(app.db, {
        userId: request.user.id,
        code: request.body.code,
        key: app.config.auth.totpKey,
      });
      if (!check.ok) throw mfaError(app, 'AUTH_MFA_INVALID', 'That code is not right');
      const recoveryCodes = await regenerateRecoveryCodes(app.db, {
        userId: request.user.id,
        key: app.config.auth.totpKey,
      });
      return { recoveryCodes };
    },
  );

  /**
   * Changing your own password (OPH-283).
   *
   * It asks for the current one, and that is the whole security story: a
   * stolen access token lives fifteen minutes, and without this check those
   * fifteen minutes would be enough to take the account permanently.
   *
   * EVERY refresh family is revoked, the caller's included. A password change
   * is what somebody does BECAUSE they think another person has the old one,
   * and leaving any family alive would make the act ceremonial. Sparing the
   * caller's own would need the family id on the access token, which it does
   * not carry — and adding it to spare somebody one sign-in would be paying in
   * the token's blast radius for a convenience.
   */
  app.post(
    '/password',
    {
      ...selfAuth,
      config: authRateLimit,
      schema: {
        body: {
          type: 'object',
          additionalProperties: false,
          required: ['currentPassword', 'newPassword'],
          properties: {
            currentPassword: { type: 'string', minLength: 1, maxLength: 128 },
            newPassword: { type: 'string', minLength: 8, maxLength: 128 },
          },
        },
      },
    },
    async (request, reply) => {
      const user = await app
        .db('users')
        .where({ id: request.user.id })
        .whereNull('deleted_at')
        .first('id', 'password_hash');
      if (!user) throw app.httpErrors.notFound('Not found');
      // An account with no password (a provider-only one, OPH-283's other
      // caller) cannot "change" one — there is nothing to prove.
      if (!user.password_hash) {
        throw coded(
          app.httpErrors.conflict('This account signs in through a provider'),
          'AUTH_NO_PASSWORD',
        );
      }
      const ok = await verifyPassword(user.password_hash, request.body.currentPassword);
      if (!ok) throw invalidCredentialsError(app);

      // Extensions get to refuse a new password (length, reuse, a team's own
      // rules). Same contract as sign-in: it runs only once the CURRENT
      // password has been proven, so it can say "no, pick a better one" and
      // never "wrong password, but here is a policy hint".
      for (const requirement of app.ee.passwordRequirements ?? []) {
        const refusal = await requirement({
          db: app.db,
          user,
          request,
          password: request.body.newPassword,
        });
        if (refusal) {
          throw coded(
            app.httpErrors.badRequest(refusal.message ?? 'That password is not allowed'),
            refusal.code ?? 'AUTH_PASSWORD_REJECTED',
          );
        }
      }

      const now = new Date();
      await app.db.transaction(async (trx) => {
        await trx('users')
          .where({ id: user.id })
          .update({
            password_hash: await hashPassword(request.body.newPassword),
            password_changed_at: now,
          });
        await trx('refresh_tokens')
          .where({ user_id: user.id })
          .whereNull('revoked_at')
          .update({ revoked_at: now });
      });
      return reply.code(204).send();
    },
  );

  // ── OPH-284: where am I signed in, and closing one of them ──────────────
  //
  // A session here is a refresh FAMILY, not a token row — `db/sessions.js`
  // says why at length. The short version: rows are rotations, and a list of
  // rotations tells somebody they are signed in ninety-six times.
  const sessionSchema = {
    type: 'object',
    additionalProperties: false,
    properties: {
      id: { type: 'string' },
      deviceName: { type: ['string', 'null'] },
      createdIp: { type: ['string', 'null'] },
      lastIp: { type: ['string', 'null'] },
      createdAt: { type: 'string' },
      lastSeenAt: { type: 'string' },
      expiresAt: { type: 'string' },
      revokedAt: { type: ['string', 'null'] },
      current: { type: 'boolean' },
    },
  };

  app.get(
    '/sessions',
    {
      ...selfAuth,
      schema: {
        // The caller may name their own session so the list can mark it. An
        // access token carries no family claim, and adding one to spare this
        // parameter would widen what a stolen access token reveals.
        querystring: {
          type: 'object',
          additionalProperties: false,
          properties: { refreshToken: { type: 'string', minLength: 20, maxLength: 512 } },
        },
        response: { 200: { type: 'array', items: sessionSchema } },
      },
    },
    async (request) => {
      const currentFamilyId = request.query.refreshToken
        ? await familyOfToken(
            app.db,
            hashRefreshToken(request.query.refreshToken, auth.refreshSecret),
          )
        : null;
      return listUserSessions(app.db, request.user.id, { currentFamilyId });
    },
  );

  app.delete(
    '/sessions/:id',
    {
      ...selfAuth,
      schema: {
        params: {
          type: 'object',
          additionalProperties: false,
          required: ['id'],
          properties: { id: { type: 'string', minLength: 26, maxLength: 26 } },
        },
      },
    },
    async (request, reply) => {
      // Scoped by user as well as family: a family id is something the owner's
      // own screen shows them, and it must never end anybody else's session.
      const revoked = await revokeSession(app.db, {
        userId: request.user.id,
        familyId: request.params.id,
      });
      if (revoked === 0) throw app.httpErrors.notFound('Not found');
      return reply.code(204).send();
    },
  );

  app.post(
    '/sessions/revoke-others',
    {
      ...selfAuth,
      config: authRateLimit,
      schema: {
        body: {
          type: 'object',
          additionalProperties: false,
          // Optional, and its absence is meaningful: no token named means keep
          // nothing, which is "sign me out everywhere including here".
          properties: { refreshToken: { type: 'string', minLength: 20, maxLength: 512 } },
        },
        response: {
          200: {
            type: 'object',
            additionalProperties: false,
            properties: { revoked: { type: 'integer' } },
          },
        },
      },
    },
    async (request) => {
      const keepFamilyId = request.body?.refreshToken
        ? await familyOfToken(
            app.db,
            hashRefreshToken(request.body.refreshToken, auth.refreshSecret),
          )
        : null;
      const revoked = await revokeOtherSessions(app.db, {
        userId: request.user.id,
        keepFamilyId,
      });
      return { revoked };
    },
  );
}
