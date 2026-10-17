import { totpStatus, verifyUserTotp } from '../db/totp.js';

/**
 * OPH-283 / OPH-381 — everything a sign-in must clear AFTER its first factor
 * (a password, or a provider's verified ID token): the account's own second
 * factor, then the extension's `signInRequirements`.
 *
 * One function for every door — `POST /auth/login`, `POST /auth/oauth` and the
 * MCP consent page — because the doors drifted once already: the password
 * route asked for the code and Google / Apple sign-in did not (OPH-381). A door
 * that skips this is a way round the second factor, so none gets its own copy.
 *
 * Returns `{ ok: true, factors }` or `{ ok: false, reason, code, message }`:
 *
 *   - `required` — a factor is enrolled and no code came with the request;
 *   - `invalid`  — a code came and is neither the current TOTP nor an unused
 *                  recovery code (a recovery code is spent by the check);
 *   - `refused`  — the extension's policy said no (`code` defaults to
 *                  `AUTH_SIGN_IN_REFUSED`).
 *
 * The factor is checked BEFORE the policy and the policy sees the outcome as
 * `{ totpEnrolled, totpVerified }`. A requirement that throws propagates: a
 * policy that fails open is not a policy. Callers must call this before they
 * write anything that belongs to the session (refresh record, identity link),
 * so a refusal leaves no trace beyond the spent TOTP step / recovery code.
 *
 * `db` defaults to `app.db`; a caller that has just created the account inside
 * a transaction passes that transaction so the policy can see the new rows.
 *
 * @param {object} app Fastify instance (`db`, `ee`, `config.auth.totpKey`).
 * @param {{ user: { id: string }, request: object, totpCode?: string | null, db?: object }} ctx
 */
export async function checkSignInFactors(app, { user, request, totpCode = null, db = app.db }) {
  const status = await totpStatus(db, user.id);
  let totpVerified = false;
  if (status.enrolled) {
    if (!totpCode) {
      return {
        ok: false,
        reason: 'required',
        code: 'AUTH_MFA_REQUIRED',
        message: 'This account needs its authenticator code',
      };
    }
    const check = await verifyUserTotp(db, {
      userId: user.id,
      code: totpCode,
      key: app.config.auth.totpKey,
    });
    if (!check.ok) {
      return {
        ok: false,
        reason: 'invalid',
        code: 'AUTH_MFA_INVALID',
        message: 'That code is not right',
      };
    }
    totpVerified = true;
  }

  const factors = { totpEnrolled: status.enrolled, totpVerified };
  for (const requirement of app.ee.signInRequirements) {
    const refusal = await requirement({ db, user, request, factors });
    if (refusal) {
      return {
        ok: false,
        reason: 'refused',
        code: refusal.code ?? 'AUTH_SIGN_IN_REFUSED',
        message: refusal.message ?? 'Sign-in refused',
      };
    }
  }
  return { ok: true, factors };
}

/**
 * The REST form: a refusal becomes a 401 carrying the outcome's stable code —
 * deliberately distinguishable from `AUTH_INVALID_CREDENTIALS`, so a client
 * knows to ask for the code instead of saying the password was wrong.
 */
export async function assertSignInFactors(app, ctx) {
  const outcome = await checkSignInFactors(app, ctx);
  if (!outcome.ok) {
    const err = app.httpErrors.unauthorized(outcome.message);
    err.code = outcome.code;
    throw err;
  }
  return outcome.factors;
}
