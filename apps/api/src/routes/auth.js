import crypto from 'node:crypto';
import { coded } from '../lib/errors.js';
import { ULID_RE, newId } from '../lib/ids.js';
import { hashPassword, verifyPassword } from '../lib/passwords.js';
import { OauthIdentityError, audiencesFor, verifyIdentityToken } from '../lib/oauth-identity.js';
import { linkIdentity, matchSocialIdentity, touchIdentity } from '../db/identities.js';
import { hashPasswordResetToken, hashRefreshToken } from '../lib/tokens.js';
import {
  EMAIL_RESETS_PER_HOUR,
  issuePasswordReset,
  resetLink,
  resetLinkBase,
  resetMail,
  retirePasswordResets,
} from '../lib/password-reset.js';
import { uniqueSlug } from '../lib/slug.js';
import { credentialRateLimit } from '../lib/rate-limit.js';
import { assertSignInFactors } from '../lib/sign-in-factors.js';
import {
  createRefreshRecord,
  deviceLabel,
  familyOfToken,
  listUserSessions,
  revokeOtherSessions,
  revokeSession,
  rotateRefreshRecord,
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

// OPH-434 (#48) — the notification device (`notification_devices.id`) this
// sign-in runs on. Optional on every door that starts a session family and on
// /refresh; it binds the family once (`refresh_tokens.device_id`), so a device
// row can name the sessions that live on it. A client that never sends it
// gets an unbound family, exactly as before. Anything but a ULID is a 400.
const deviceIdField = {
  type: 'string',
  pattern: ULID_RE.source,
  description:
    'Optional. The notification device (its id from PUT /notification-devices) this session runs on. Binds the session once; a ULID, anything else is a 400.',
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
      deviceId: deviceIdField,
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
      deviceId: deviceIdField,
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
  // /logout keeps the bare body; only a refresh may bind its family (OPH-434).
  body: {
    ...refreshBodySchema,
    properties: { ...refreshBodySchema.properties, deviceId: deviceIdField },
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

/**
 * Reuse of any token in a family means the chain may be stolen — kill all of
 * it. `revokeSession` also removes the notification device the family is
 * bound to (OPH-435): a burned family is a signed-out install either way.
 */
function revokeFamily(db, row) {
  return revokeSession(db, { userId: row.user_id, familyId: row.family_id });
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
      // OPH-381 — the same field, bounds and meaning as on /login: the
      // provider proves the first factor, an enrolled account still owes its
      // authenticator or recovery code. The app resends the SAME idToken with
      // it after an AUTH_MFA_REQUIRED, rather than running the provider again.
      totpCode: { type: 'string', minLength: 6, maxLength: 32 },
      deviceId: deviceIdField,
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

// OPH-406 (ADR-0064). One code for a link that is unknown, spent or expired:
// whoever holds the link learns only that it no longer works.
function invalidResetError(app) {
  const err = app.httpErrors.badRequest('This reset link is invalid or has expired');
  err.code = 'AUTH_RESET_INVALID';
  return err;
}

const forgotSchema = {
  body: {
    type: 'object',
    additionalProperties: false,
    required: ['email'],
    properties: {
      email: { type: 'string', format: 'email', maxLength: 255 },
      // The language of the mail. Absent or unknown → English.
      locale: { type: 'string', enum: ['en', 'tr'] },
    },
  },
  response: {
    202: {
      type: 'object',
      additionalProperties: false,
      required: ['delivery'],
      properties: {
        // `email` — if the address has an account here, a link is on its way.
        // `admin` — this server sends no mail: ask its operator for a link.
        // A property of the SERVER, the same for every address.
        delivery: { type: 'string', enum: ['email', 'admin'] },
      },
    },
    429: errorResponseSchema,
  },
};

const resetSchema = {
  body: {
    type: 'object',
    additionalProperties: false,
    required: ['token', 'password'],
    properties: {
      token: { type: 'string', minLength: 20, maxLength: 128 },
      password: { type: 'string', minLength: 8, maxLength: 128 },
    },
  },
  response: {
    204: { type: 'null' },
    400: errorResponseSchema,
    429: errorResponseSchema,
  },
};

/**
 * The extension's password rules (length, reuse, a team's own policy), for
 * every door that sets a password: the change below and the reset link.
 */
async function assertPasswordAllowed(app, { user, request, password }) {
  for (const requirement of app.ee.passwordRequirements ?? []) {
    const refusal = await requirement({ db: app.db, user, request, password });
    if (refusal) {
      throw coded(
        app.httpErrors.badRequest(refusal.message ?? 'That password is not allowed'),
        refusal.code ?? 'AUTH_PASSWORD_REJECTED',
      );
    }
  }
}

export default async function authRoutes(app) {
  const { auth } = app.config;
  // Tighter than the global limiter — these are brute-force targets. Signed-in
  // routes (MFA, password, sessions) count per user like everything else.
  const authRateLimit = {
    rateLimit: { max: app.config.rateLimitAuthMax, timeWindow: '1 minute' },
  };
  // The credential endpoints have no identity yet (ADR-0045 §2): per IP + the
  // account the body names, under one per-IP ceiling for all of them.
  const credentialLimit = {
    onRequest: [app.credentialIpCeiling],
    config: credentialRateLimit(app),
  };

  // OPH-392 (E-23) — which social sign-ins this server can complete, asked by
  // the sign-in screen before it offers a button. Without it the app offered
  // Google everywhere, and on a server with no SIGN_IN_GOOGLE_* client the tap
  // ended in OAUTH_PROVIDER_NOT_CONFIGURED. Booleans only — the client ids are
  // not secrets, but nothing needs them here. Public, like the doors it
  // describes; the global limiter is enough for a read with no lookup.
  app.get(
    '/providers',
    {
      schema: {
        response: {
          200: {
            type: 'object',
            additionalProperties: false,
            required: ['google', 'apple'],
            properties: {
              google: { type: 'boolean' },
              apple: { type: 'boolean' },
            },
          },
        },
      },
    },
    async () => ({
      google: audiencesFor(app.config, 'google').length > 0,
      apple: audiencesFor(app.config, 'apple').length > 0,
    }),
  );

  // Baseline argon2id hash so unknown-email logins burn the same verify cost as
  // wrong-password logins (no email-existence timing oracle).
  const timingSafeDummyHash = await hashPassword(crypto.randomUUID());

  // OPH-020 — create user + personal workspace + first session, all in one transaction.
  app.post('/register', { schema: registerSchema, ...credentialLimit }, async (request, reply) => {
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
          deviceId: request.body.deviceId ?? null,
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
  });

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
  app.post('/oauth', { schema: oauthSchema, ...credentialLimit }, async (request, reply) => {
    const { provider, idToken, totpCode } = request.body;

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

    // The rule ladder above lives in db/identities.js, shared with the MCP
    // consent page (OPH-366) so the two cannot drift apart.
    const match = await matchSocialIdentity(app.db, identity);

    let user;
    let refresh;
    let created = false;

    if (match.kind === 'gone') {
      throw coded(
        app.httpErrors.unauthorized('This account no longer exists'),
        'OAUTH_ACCOUNT_GONE',
      );
    }
    // OPH-381 — a provider's token is the FIRST factor, never the whole
    // sign-in: an existing account clears its second factor and the
    // extension's policy exactly as /login does (same helper, same codes),
    // and BEFORE anything is written — a refused attempt must not link an
    // identity, touch it or leave a refresh row behind.
    if (match.kind === 'known' || match.kind === 'link') {
      await assertSignInFactors(app, { user: match.user, request, totpCode });
    }

    if (match.kind === 'known') {
      const row = match.user;
      user = { id: row.id, email: row.email, displayName: row.display_name };
      await app.db.transaction(async (trx) => {
        await touchIdentity(trx, match.identityId);
        refresh = await createRefreshRecord(trx, auth, {
          userId: user.id,
          familyId: newId(),
          ip: request.ip,
          deviceName: deviceLabel(request),
          deviceId: request.body.deviceId ?? null,
        });
      });
    } else if (match.kind === 'link') {
      const row = match.user;
      user = { id: row.id, email: row.email, displayName: row.display_name };
      await app.db.transaction(async (trx) => {
        await linkIdentity(trx, user.id, identity);
        refresh = await createRefreshRecord(trx, auth, {
          userId: user.id,
          familyId: newId(),
          ip: request.ip,
          deviceName: deviceLabel(request),
          deviceId: request.body.deviceId ?? null,
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
          await linkIdentity(trx, userId, identity);
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
          // A brand-new account has no second factor, but the policy still
          // decides whether it may sign in. Inside the transaction, so a
          // refusal (or a throwing policy) rolls the account back instead of
          // leaving one nobody can enter, and the policy sees its rows.
          await assertSignInFactors(app, {
            user: { id: userId, email, display_name: displayName },
            request,
            db: trx,
          });
          refresh = await createRefreshRecord(trx, auth, {
            userId,
            familyId: newId(),
            ip: request.ip,
            deviceName: deviceLabel(request),
            deviceId: request.body.deviceId ?? null,
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
  app.post('/login', { schema: loginSchema, ...credentialLimit }, async (request) => {
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
    await assertSignInFactors(app, { user, request, totpCode: request.body.totpCode });

    const refresh = await createRefreshRecord(app.db, auth, {
      userId: user.id,
      familyId: newId(),
      ip: request.ip,
      deviceName: deviceLabel(request),
      deviceId: request.body.deviceId ?? null,
    });

    return {
      user: { id: user.id, email: user.email, displayName: user.display_name ?? null },
      tokens: sessionTokens(app, user, refresh),
    };
  });

  // OPH-022 — rotate: retire the presented token, issue a new one in the SAME family.
  app.post('/refresh', { schema: refreshSchema, ...credentialLimit }, async (request) => {
    const tokenHash = hashRefreshToken(request.body.refreshToken, auth.refreshSecret);
    const row = await app.db('refresh_tokens').where({ token_hash: tokenHash }).first();
    if (!row) throw invalidRefreshError(app);

    // An already-rotated (or revoked) token coming back means theft or a very
    // broken client — either way the whole rotation chain is burned.
    if (row.rotated_at || row.revoked_at) {
      await revokeFamily(app.db, row);
      throw refreshReusedError(app);
    }
    if (new Date(row.expires_at).getTime() <= Date.now()) throw invalidRefreshError(app);

    const user = await app
      .db('users')
      .where({ id: row.user_id })
      .whereNull('deleted_at')
      .first('id', 'email', 'display_name');
    if (!user) throw invalidRefreshError(app);

    const refresh = await rotateRefreshRecord(app.db, auth, {
      row,
      ip: request.ip,
      // The family KEEPS the device it was born on. A rotation is the same
      // session on the same machine, so re-reading the User-Agent buys
      // nothing — and costs the name outright when a client sends none on
      // its refresh calls, which is common and is how this line was found.
      // The fallback covers families that predate this column being written.
      deviceName: row.device_name ?? deviceLabel(request),
      // OPH-434 — the device binding travels the same way, and is set once:
      // a bound family keeps its device whatever this call names (a family
      // is one install; relabelling it only makes sense with a stolen
      // token), an unbound one takes the device this refresh names. The
      // binding is re-read under the claim's lock (OPH-458), not taken from
      // `row`, which a registration may have bound since it was read.
      deviceId: request.body.deviceId ?? null,
    });
    if (refresh === null) {
      // Lost the race — the token was concurrently rotated, i.e. reused.
      await revokeFamily(app.db, row);
      throw refreshReusedError(app);
    }

    return {
      user: { id: user.id, email: user.email, displayName: user.display_name ?? null },
      tokens: sessionTokens(app, user, refresh),
    };
  });

  // OPH-022 — revoke the presented token (?all=true: its whole family). Always 204:
  // logout must be idempotent and reveal nothing about token validity.
  app.post('/logout', { schema: logoutSchema, ...credentialLimit }, async (request, reply) => {
    const tokenHash = hashRefreshToken(request.body.refreshToken, auth.refreshSecret);
    const row = await app
      .db('refresh_tokens')
      .where({ token_hash: tokenHash })
      .first('id', 'family_id', 'user_id');
    if (row) {
      if (request.query.all) {
        await revokeFamily(app.db, row);
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
      await assertPasswordAllowed(app, { user, request, password: request.body.newPassword });

      const now = new Date();
      await app.db.transaction(async (trx) => {
        // The account row's lock serialises this with a reset link being spent
        // (OPH-406): whichever writes second sees the other's change.
        await trx('users').where({ id: user.id }).forUpdate().first('id');
        await trx('users')
          .where({ id: user.id })
          .update({
            password_hash: await hashPassword(request.body.newPassword),
            password_changed_at: now,
          });
        // Every session ends, and the devices bound to them go too (OPH-435).
        await revokeOtherSessions(trx, { userId: user.id, at: now });
        // A reset link sent before this change must not undo it (OPH-406).
        await retirePasswordResets(trx, user.id, now);
      });
      return reply.code(204).send();
    },
  );

  // ── OPH-406: "I forgot my password" (ADR-0064) ──────────────────────────
  //
  // Two public doors under the credential limits (per IP + the address named,
  // and the shared per-IP ceiling). Neither says whether an account exists:
  // the forgot form answers the same for every address, and the answer only
  // describes the server — whether it can send mail at all.

  app.post(
    '/password/forgot',
    { schema: forgotSchema, ...credentialLimit },
    async (request, reply) => {
      const base = resetLinkBase(app.config);
      if (!app.mailer || !base) return reply.code(202).send({ delivery: 'admin' });

      const email = request.body.email.trim().toLowerCase();
      const { locale } = request.body;
      // Everything about the address — the lookup, the hourly count, the
      // issue, the SMTP round trip — runs after the answer. Database work done
      // only for real accounts would otherwise be a timing answer to "does
      // this address exist?". A failure is logged without the address; the
      // person can ask again.
      app.mailQueue.defer(
        async () => {
          const user = await app
            .db('users')
            .where({ email })
            .whereNull('deleted_at')
            .first('id', 'email');
          if (!user) return;
          // Over the hourly count the ask is dropped: the rate limit stops one
          // address hammering, this stops many addresses filling one person's
          // inbox. The count and the issue are one locked step.
          const minutes = auth.passwordResetTtlMin;
          const issued = await issuePasswordReset(app.db, {
            userId: user.id,
            secret: auth.refreshSecret,
            ttlMs: minutes * 60 * 1000,
            source: 'email',
            perHourLimit: EMAIL_RESETS_PER_HOUR,
          });
          if (!issued) return;
          const mail = resetMail(locale, resetLink(base, issued.token), minutes);
          await app.mailer.send({ to: user.email, ...mail });
        },
        (err) => request.log.warn({ err: err.message }, 'password reset mail failed'),
      );
      return reply.code(202).send({ delivery: 'email' });
    },
  );

  /**
   * Spending a link. Same effects as changing the password (ADR-0006): every
   * session ends. A second factor stays enrolled — the link replaces the
   * password, not the authenticator, so the next sign-in still asks for it.
   */
  app.post(
    '/password/reset',
    { schema: resetSchema, ...credentialLimit },
    async (request, reply) => {
      const tokenHash = hashPasswordResetToken(request.body.token, auth.refreshSecret);
      const now = new Date();
      const row = await app.db('password_resets').where({ token_hash: tokenHash }).first();
      if (!row || row.used_at || new Date(row.expires_at).getTime() <= now.getTime()) {
        throw invalidResetError(app);
      }
      const user = await app
        .db('users')
        .where({ id: row.user_id })
        .whereNull('deleted_at')
        .first('id', 'password_hash', 'password_changed_at');
      if (!user) throw invalidResetError(app);
      // A link older than the current password is not spent by a door that
      // forgot to retire it: the password it was sent to replace is gone.
      if (
        user.password_changed_at &&
        new Date(row.created_at).getTime() < new Date(user.password_changed_at).getTime()
      ) {
        throw invalidResetError(app);
      }

      // Before the link is spent: a refused password leaves it usable.
      await assertPasswordAllowed(app, { user, request, password: request.body.password });
      const passwordHash = await hashPassword(request.body.password);

      let claimed = 0;
      await app.db.transaction(async (trx) => {
        // Every door that sets a password writes under the account row's lock.
        // The checks above ran outside it: a change that landed since then
        // (its own retirement stamps this link's expiry with the change time,
        // later than our `now`) is seen here, and the link is refused.
        const locked = await trx('users')
          .where({ id: user.id })
          .whereNull('deleted_at')
          .forUpdate()
          .first('password_changed_at');
        const changedAt = (v) => (v ? new Date(v).getTime() : null);
        if (
          !locked ||
          changedAt(locked.password_changed_at) !== changedAt(user.password_changed_at)
        ) {
          return;
        }
        // Atomic claim: of two requests with one link, only one UPDATE matches.
        claimed = await trx('password_resets')
          .where({ id: row.id })
          .whereNull('used_at')
          .where('expires_at', '>', now)
          .update({ used_at: now });
        if (claimed === 0) return;
        await trx('users')
          .where({ id: user.id })
          .update({ password_hash: passwordHash, password_changed_at: now });
        // Every session ends, and the devices bound to them go too (OPH-435).
        await revokeOtherSessions(trx, { userId: user.id, at: now });
        // Any other link still out there stops working with this one.
        await retirePasswordResets(trx, user.id, now);
      });
      if (claimed === 0) throw invalidResetError(app);
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
