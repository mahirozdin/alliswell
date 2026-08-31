import crypto from 'node:crypto';

/**
 * TOTP (RFC 6238) — the second factor, over `node:crypto`.
 *
 * Written here rather than pulled from npm because the whole of it is ~110
 * lines of two RFCs (4226 for the one-time password, 6238 for the clock
 * around it) and a base32 codec, and the dependency would be carried by every
 * install of this product forever to save exactly that.
 *
 * Defaults are the ones every authenticator app assumes without being told:
 * SHA-1, 6 digits, 30-second steps. They are NOT a security judgement about
 * SHA-1 — HOTP uses it as a MAC over a counter, where its collision weakness
 * does not apply, and an authenticator that cannot be enrolled protects
 * nothing.
 *
 * Everything here is PURE: a secret and a moment in, a string out. Storage,
 * replay refusal and enrolment live in `src/db/totp.js`; keeping the split
 * means the arithmetic can be tested against RFC 6238's own vectors without a
 * database.
 */

const BASE32_ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
export const TOTP_STEP_SEC = 30;
export const TOTP_DIGITS = 6;
/** How many steps either side of "now" a code is still accepted. */
export const TOTP_WINDOW = 1;

/** RFC 4648 base32, unpadded — what `otpauth://` URIs carry. */
export function base32Encode(buffer) {
  let bits = 0;
  let value = 0;
  let out = '';
  for (const byte of buffer) {
    value = (value << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      out += BASE32_ALPHABET[(value >>> (bits - 5)) & 31];
      bits -= 5;
    }
  }
  if (bits > 0) out += BASE32_ALPHABET[(value << (5 - bits)) & 31];
  return out;
}

export function base32Decode(secret) {
  const clean = String(secret).toUpperCase().replace(/=+$/, '').replace(/\s+/g, '');
  let bits = 0;
  let value = 0;
  const out = [];
  for (const char of clean) {
    const index = BASE32_ALPHABET.indexOf(char);
    if (index === -1) {
      const err = new Error('Invalid base32 in TOTP secret');
      err.code = 'TOTP_BAD_SECRET';
      throw err;
    }
    value = (value << 5) | index;
    bits += 5;
    if (bits >= 8) {
      out.push((value >>> (bits - 8)) & 255);
      bits -= 8;
    }
  }
  return Buffer.from(out);
}

/** 160 bits — the SHA-1 block size, and what every authenticator expects. */
export function generateTotpSecret(bytes = 20) {
  return base32Encode(crypto.randomBytes(bytes));
}

/** The step number a moment falls in. Stored, so a code cannot be replayed. */
export function totpStep(at = new Date(), stepSec = TOTP_STEP_SEC) {
  return Math.floor(Math.floor(at.getTime() / 1000) / stepSec);
}

/** HOTP (RFC 4226) — the primitive TOTP is a clock wrapped around. */
export function hotp(secret, counter, digits = TOTP_DIGITS) {
  const key = base32Decode(secret);
  const message = Buffer.alloc(8);
  message.writeBigUInt64BE(BigInt(counter));
  const digest = crypto.createHmac('sha1', key).update(message).digest();
  // Dynamic truncation: the low nibble of the last byte picks the offset.
  const offset = digest[digest.length - 1] & 0x0f;
  const binary =
    ((digest[offset] & 0x7f) << 24) |
    (digest[offset + 1] << 16) |
    (digest[offset + 2] << 8) |
    digest[offset + 3];
  return String(binary % 10 ** digits).padStart(digits, '0');
}

export function totp(secret, { at = new Date(), digits = TOTP_DIGITS } = {}) {
  return hotp(secret, totpStep(at), digits);
}

/**
 * Verifies a code and returns the STEP it matched, or null.
 *
 * The step is the return value on purpose: the caller stores it and refuses
 * anything at or below it next time. A TOTP code is a bearer credential for
 * its whole window — without replay refusal, a code read over someone's
 * shoulder works again for up to 90 seconds.
 *
 * @param {object} opts
 * @param {number|null} [opts.lastStep] highest step already spent
 */
export function verifyTotp(
  secret,
  code,
  { at = new Date(), window = TOTP_WINDOW, digits = TOTP_DIGITS, lastStep = null } = {},
) {
  if (typeof code !== 'string' || !new RegExp(`^\\d{${digits}}$`).test(code)) return null;
  const current = totpStep(at);
  for (let drift = -window; drift <= window; drift += 1) {
    const step = current + drift;
    if (step < 0) continue;
    if (lastStep != null && step <= lastStep) continue; // already spent
    const expected = hotp(secret, step, digits);
    // Same length by construction, so timingSafeEqual is safe to reach for —
    // and comparing an OTP with === leaks its prefix to a patient attacker.
    if (crypto.timingSafeEqual(Buffer.from(expected), Buffer.from(code))) return step;
  }
  return null;
}

/**
 * The `otpauth://` URI an authenticator scans. `issuer` appears twice by
 * convention (path prefix AND query) because different apps read different
 * ones — Google Authenticator has historically used the path.
 */
export function totpUri({ secret, email, issuer = 'AllisWell' }) {
  const label = encodeURIComponent(`${issuer}:${email}`);
  const params = new URLSearchParams({
    secret,
    issuer,
    algorithm: 'SHA1',
    digits: String(TOTP_DIGITS),
    period: String(TOTP_STEP_SEC),
  });
  return `otpauth://totp/${label}?${params.toString()}`;
}
