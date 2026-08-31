/**
 * Enrolling, checking and recovering a second factor (OPH-283).
 *
 * `lib/totp.js` does the arithmetic and knows nothing about anybody; this
 * file is where a factor becomes a fact about a person — which means it owns
 * the three things the arithmetic cannot do on its own:
 *
 *   1. **The staged state.** A secret exists before it is trusted. Between
 *      `startEnrolment` and `confirmEnrolment` the row is there with
 *      `enrolled_at` NULL, and everything that asks "does this person have a
 *      second factor?" says no.
 *   2. **Replay refusal.** `verifyTotp` returns the STEP it matched and this
 *      file writes it down, so the same code cannot be spent twice.
 *   3. **Recovery.** A second factor that can be lost with a phone is a way
 *      to lose an account. The codes are minted once, shown once, stored as
 *      digests, and each one works exactly once.
 */
import crypto from 'node:crypto';

import { decryptSecret, encryptSecret } from '../lib/crypto.js';
import { newId } from '../lib/ids.js';
import { hashRecoveryCode } from '../lib/tokens.js';
import { generateTotpSecret, totpUri, verifyTotp } from '../lib/totp.js';

export const RECOVERY_CODE_COUNT = 10;
/** Crockford-ish: no I, L, O, U — the characters people mistype off paper. */
const RECOVERY_ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
const RECOVERY_CODE_CHARS = 10;

/** `XXXXX-XXXXX` — grouped because it is read aloud and typed by hand. */
export function newRecoveryCode() {
  const bytes = crypto.randomBytes(RECOVERY_CODE_CHARS);
  let out = '';
  for (let i = 0; i < RECOVERY_CODE_CHARS; i += 1) {
    out += RECOVERY_ALPHABET[bytes[i] % RECOVERY_ALPHABET.length];
  }
  return `${out.slice(0, 5)}-${out.slice(5)}`;
}

/** The row, or undefined. Nothing else in the codebase selects this table. */
export function totpRow(db, userId) {
  return db('user_totp').where({ user_id: userId }).first();
}

/**
 * `{ enrolled, staged, recoveryCodesLeft }` — what a settings screen shows and
 * what sign-in branches on. One query for the factor, one for the codes, and
 * the second is skipped when there is no factor to recover.
 */
export async function totpStatus(db, userId) {
  const row = await totpRow(db, userId);
  if (!row) return { enrolled: false, staged: false, recoveryCodesLeft: 0 };
  if (!row.enrolled_at) return { enrolled: false, staged: true, recoveryCodesLeft: 0 };
  const [{ n = 0 } = {}] = await db('user_totp_recovery_codes')
    .where({ user_id: userId })
    .whereNull('used_at')
    .count({ n: '*' });
  return { enrolled: true, staged: false, recoveryCodesLeft: Number(n) };
}

/**
 * Mints a fresh secret and stages it. Replacing a staged row is deliberate: a
 * person who abandoned setup and started again should get a new secret, not
 * be told they already have one they never saw.
 *
 * Refuses when a CONFIRMED factor exists — replacing that silently would let
 * anybody holding a live session swap the second factor without proving they
 * hold the old one. Disable first, which asks for a code.
 */
export async function startTotpEnrolment(db, { userId, email, key, issuer }) {
  const existing = await totpRow(db, userId);
  if (existing?.enrolled_at) {
    const err = new Error('Two-factor authentication is already set up');
    err.code = 'TOTP_ALREADY_ENROLLED';
    throw err;
  }
  const secret = generateTotpSecret();
  const now = new Date();
  const encrypted = encryptSecret(secret, key);
  if (existing) {
    await db('user_totp')
      .where({ id: existing.id })
      .update({ encrypted_secret: encrypted, last_step: null, updated_at: now });
  } else {
    await db('user_totp').insert({
      id: newId(),
      user_id: userId,
      encrypted_secret: encrypted,
      enrolled_at: null,
      created_at: now,
      updated_at: now,
    });
  }
  return { secret, uri: totpUri({ secret, email, ...(issuer ? { issuer } : {}) }) };
}

/**
 * Proves the authenticator agrees, then turns the factor on and hands back the
 * recovery codes — the only moment they are ever visible.
 *
 * One transaction: a factor that is on with no way to recover it is exactly
 * the state that turns a lost phone into a lost account.
 */
export async function confirmTotpEnrolment(db, { userId, code, key, at = new Date() }) {
  const row = await totpRow(db, userId);
  if (!row) {
    const err = new Error('Start two-factor setup first');
    err.code = 'TOTP_NOT_STAGED';
    throw err;
  }
  if (row.enrolled_at) {
    const err = new Error('Two-factor authentication is already set up');
    err.code = 'TOTP_ALREADY_ENROLLED';
    throw err;
  }
  const secret = decryptSecret(row.encrypted_secret, key);
  const step = verifyTotp(secret, code, { at, lastStep: row.last_step ?? null });
  if (step == null) {
    const err = new Error('That code is not right');
    err.code = 'TOTP_CODE_WRONG';
    throw err;
  }

  const codes = Array.from({ length: RECOVERY_CODE_COUNT }, () => newRecoveryCode());
  await db.transaction(async (trx) => {
    await trx('user_totp')
      .where({ id: row.id })
      .update({ enrolled_at: at, last_step: step, updated_at: at });
    await trx('user_totp_recovery_codes').where({ user_id: userId }).del();
    await trx('user_totp_recovery_codes').insert(
      codes.map((c) => ({
        id: newId(),
        user_id: userId,
        code_hash: hashRecoveryCode(c, key),
        created_at: at,
      })),
    );
  });
  return { recoveryCodes: codes };
}

/**
 * Checks a code against an ENROLLED factor. A recovery code is accepted in
 * the same call and spent by it, because from sign-in's point of view they
 * answer the same question — "is this the person?" — and a caller that had to
 * choose which one it was being given would have to guess from the shape of
 * the string.
 *
 * @returns {Promise<{ok: boolean, used: 'totp'|'recovery'|null}>}
 */
export async function verifyUserTotp(db, { userId, code, key, at = new Date() }) {
  const row = await totpRow(db, userId);
  if (!row?.enrolled_at) return { ok: false, used: null };

  const secret = decryptSecret(row.encrypted_secret, key);
  const step = verifyTotp(secret, code, { at, lastStep: row.last_step ?? null });
  if (step != null) {
    // The spent step is written before the caller is told yes: a crash here
    // must not leave a code that has been accepted once still spendable.
    await db('user_totp').where({ id: row.id }).update({ last_step: step, updated_at: at });
    return { ok: true, used: 'totp' };
  }

  // A conditional update IS the single-use guarantee: two simultaneous uses of
  // one recovery code race in the database, where exactly one wins.
  const spent = await db('user_totp_recovery_codes')
    .where({ user_id: userId, code_hash: hashRecoveryCode(code, key) })
    .whereNull('used_at')
    .update({ used_at: at });
  if (spent > 0) return { ok: true, used: 'recovery' };

  return { ok: false, used: null };
}

/** Turns the factor off and takes the recovery codes with it. */
export async function disableTotp(db, userId) {
  await db.transaction(async (trx) => {
    await trx('user_totp_recovery_codes').where({ user_id: userId }).del();
    await trx('user_totp').where({ user_id: userId }).del();
  });
}

/** A fresh set; the old ones stop working the moment these are handed over. */
export async function regenerateRecoveryCodes(db, { userId, key, at = new Date() }) {
  const codes = Array.from({ length: RECOVERY_CODE_COUNT }, () => newRecoveryCode());
  await db.transaction(async (trx) => {
    await trx('user_totp_recovery_codes').where({ user_id: userId }).del();
    await trx('user_totp_recovery_codes').insert(
      codes.map((c) => ({
        id: newId(),
        user_id: userId,
        code_hash: hashRecoveryCode(c, key),
        created_at: at,
      })),
    );
  });
  return codes;
}
