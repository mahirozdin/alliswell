import argon2 from 'argon2';

/**
 * Password hashing for user accounts (BLUEPRINT §5.2: argon2).
 * argon2id (hybrid mode) per OWASP guidance; library defaults for cost parameters
 * (v0.44: m=64 MiB, t=3, p=4) exceed the OWASP minimum and the parameters are
 * embedded in the hash string, so they can be raised later without a migration.
 */

/** @param {string} plain */
export async function hashPassword(plain) {
  return argon2.hash(plain, { type: argon2.argon2id });
}

/**
 * @param {string} hash - stored `password_hash` value
 * @param {string} plain - candidate password
 * @returns {Promise<boolean>} never throws on mismatch — returns false
 */
export async function verifyPassword(hash, plain) {
  return argon2.verify(hash, plain);
}
