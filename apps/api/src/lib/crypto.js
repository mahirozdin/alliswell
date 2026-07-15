import crypto from 'node:crypto';

/**
 * At-rest encryption for OAuth tokens (OPH-070, BLUEPRINT §15.3 / ADR-0006).
 * AES-256-GCM with a random 12-byte IV per value; the auth tag makes any
 * tampering (or a wrong key) throw instead of returning garbage.
 *
 * Wire format: `v1:<iv b64url>:<tag b64url>:<ciphertext b64url>` — versioned
 * so a future key/algorithm rotation can coexist with old rows.
 */

const VERSION = 'v1';

/** @param {string} hexKey 64 hex chars (validated by config) */
function keyBuffer(hexKey) {
  return Buffer.from(hexKey, 'hex');
}

/**
 * @param {string} plaintext
 * @param {string} hexKey
 * @returns {string}
 */
export function encryptSecret(plaintext, hexKey) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', keyBuffer(hexKey), iv);
  const ciphertext = Buffer.concat([cipher.update(plaintext, 'utf8'), cipher.final()]);
  const tag = cipher.getAuthTag();
  return [
    VERSION,
    iv.toString('base64url'),
    tag.toString('base64url'),
    ciphertext.toString('base64url'),
  ].join(':');
}

/**
 * @param {string} encoded
 * @param {string} hexKey
 * @returns {string}
 */
export function decryptSecret(encoded, hexKey) {
  const [version, iv, tag, ciphertext] = String(encoded).split(':');
  if (version !== VERSION || !iv || !tag || !ciphertext) {
    throw new Error('Unrecognized encrypted-secret format');
  }
  const decipher = crypto.createDecipheriv(
    'aes-256-gcm',
    keyBuffer(hexKey),
    Buffer.from(iv, 'base64url'),
  );
  decipher.setAuthTag(Buffer.from(tag, 'base64url'));
  return Buffer.concat([
    decipher.update(Buffer.from(ciphertext, 'base64url')),
    decipher.final(),
  ]).toString('utf8');
}
