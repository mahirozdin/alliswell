import crypto from 'node:crypto';

import { newId } from './ids.js';
import { hashPasswordResetToken } from './tokens.js';

/**
 * Password-reset links (OPH-406, ADR-0064). The route (`routes/auth.js`) and
 * the operator's command (`cli/password-reset-link.js`) both issue through
 * here, so the two kinds of link differ only in lifetime and `source`.
 */

/** How long the operator's link works. It travels by hand, so longer. */
export const ADMIN_RESET_TTL_MS = 24 * 60 * 60 * 1000;

/** E-mailed links per account per hour; more asks are answered and dropped. */
export const EMAIL_RESETS_PER_HOUR = 3;

/** The client route a link opens (hash routing — the token never reaches a server log). */
export const RESET_ROUTE = '/#/reset-password';

/**
 * Where links point: `APP_PUBLIC_URL`, else the one CORS origin when there is
 * exactly one (the self-host compose serves the web app at that origin's
 * root). `null` = no address to build a link on.
 *
 * @param {{ appPublicUrl: string|null, corsOrigin: true|string[] }} config
 */
export function resetLinkBase(config) {
  if (config.appPublicUrl) return config.appPublicUrl;
  const origins = config.corsOrigin;
  if (Array.isArray(origins) && origins.length === 1 && /^https?:\/\/[^*]+$/.test(origins[0])) {
    return origins[0].replace(/\/+$/, '');
  }
  return null;
}

/** @param {string} base @param {string} token */
export function resetLink(base, token) {
  return `${base}${RESET_ROUTE}?token=${encodeURIComponent(token)}`;
}

/**
 * Every link of this account still out there stops working (its `expires_at`
 * becomes `now`). Each door that sets a password calls it in its own
 * transaction: a link sent before the change must not undo it.
 *
 * @param {import('knex').Knex} db  a transaction, or the pool
 * @param {string} userId
 * @param {Date} now
 */
export function retirePasswordResets(db, userId, now) {
  return db('password_resets')
    .where({ user_id: userId })
    .whereNull('used_at')
    .where('expires_at', '>', now)
    .update({ expires_at: now });
}

/**
 * Mints a link for one account. Earlier unused links of that account stop
 * working (their `expires_at` becomes now): the newest mail is the one that
 * counts, and an old one forwarded or left open is not a second way in.
 *
 * @param {import('knex').Knex} db
 * @param {{ userId: string, secret: string, ttlMs: number, source: 'email'|'admin' }} opts
 * @returns {Promise<{ token: string, expiresAt: Date }>}
 */
export async function issuePasswordReset(db, { userId, secret, ttlMs, source }) {
  const token = crypto.randomBytes(32).toString('base64url');
  const now = new Date();
  const expiresAt = new Date(now.getTime() + ttlMs);
  await db.transaction(async (trx) => {
    await retirePasswordResets(trx, userId, now);
    await trx('password_resets').insert({
      id: newId(),
      user_id: userId,
      token_hash: hashPasswordResetToken(token, secret),
      source,
      expires_at: expiresAt,
      created_at: now,
    });
  });
  return { token, expiresAt };
}

/**
 * E-mailed links this account was sent in the last hour (admin links are not
 * counted: the operator is not the abuse the throttle is for).
 *
 * @param {import('knex').Knex} db
 * @param {string} userId
 */
export async function recentEmailResets(db, userId) {
  const since = new Date(Date.now() - 60 * 60 * 1000);
  const row = await db('password_resets')
    .where({ user_id: userId, source: 'email' })
    .where('created_at', '>', since)
    .count({ n: '*' })
    .first();
  return Number(row?.n ?? 0);
}

const MAIL = {
  en: (link, minutes) => ({
    subject: 'Reset your AllisWell password',
    text:
      'Someone asked to reset the password of your AllisWell account.\n\n' +
      `Open this link to choose a new password. It works once, for ${minutes} minutes:\n\n` +
      `${link}\n\n` +
      'If it was not you, ignore this mail. Your password stays as it is.\n',
  }),
  tr: (link, minutes) => ({
    subject: 'AllisWell parolanı sıfırla',
    text:
      'AllisWell hesabının parolasını sıfırlamak için bir istek geldi.\n\n' +
      `Yeni parolanı seçmek için bu bağlantıyı aç. Bir kez ve ${minutes} dakika boyunca çalışır:\n\n` +
      `${link}\n\n` +
      'Bunu sen istemediysen bu e-postayı yok say. Parolan değişmez.\n',
  }),
};

/**
 * @param {'en'|'tr'|undefined} locale
 * @param {string} link
 * @param {number} minutes
 */
export function resetMail(locale, link, minutes) {
  return (MAIL[locale] ?? MAIL.en)(link, minutes);
}
