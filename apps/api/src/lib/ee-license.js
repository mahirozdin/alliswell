import { readFileSync } from 'node:fs';
import crypto from 'node:crypto';

import { EE_FEATURES } from './entitlements.js';

/**
 * Ed25519 license verification (EE-004). Verification is deliberately OPEN
 * code: the public key only ever verifies — possession of this file mints
 * nothing. The signing key lives with BubiApps, offline; enterprise installs
 * work air-gapped because nothing here phones home.
 *
 * File format (ADR-0003 in the overlay repo): the payload travels as the
 * EXACT bytes that were signed — `p` is base64(JSON), `s` is base64(signature
 * over those bytes) — so verification never depends on JSON key order.
 *
 *   { "alliswellLicense": 1, "p": "<base64>", "s": "<base64>" }
 *
 * Payload: { customer, seats, teams, features[], issuedAt, expiresAt, graceDays }.
 */

// BubiApps EE license signing public key (raw Ed25519, base64). Overridable
// via EE_LICENSE_PUBLIC_KEY for tests and for a future key rotation.
export const BUBIAPPS_EE_LICENSE_PUBLIC_KEY = 'V5MvsMg6TgHWWDj56esGWRQYsWUU52tmszkqJVY7N8E=';

function keyFromBase64(base64) {
  return crypto.createPublicKey({
    key: Buffer.concat([
      // SPKI prefix for a raw Ed25519 public key (RFC 8410).
      Buffer.from('302a300506032b6570032100', 'hex'),
      Buffer.from(base64, 'base64'),
    ]),
    format: 'der',
    type: 'spki',
  });
}

/**
 * @returns {{ state: 'none'|'active'|'grace'|'readonly', payload: object|null, error: string|null }}
 * `state: 'none'` covers both "no license" and "invalid license" — an invalid
 * file must not be distinguishable from no file by behaviour (it IS the CE
 * mode), but the error string is kept for the operator's log line.
 */
export function verifyLicenseFile({ path, raw, publicKeyBase64, now = new Date() }) {
  let text = raw;
  if (text == null) {
    try {
      text = readFileSync(path, 'utf8');
    } catch (err) {
      // ONLY a missing file is the silent CE mode. Everything else — EISDIR
      // (a bad bind mount materializes as an empty directory), EACCES, EIO —
      // is a real deployment fault and must reach the operator's log, or the
      // paid features vanish with no trace. Measured, not guessed: a Docker
      // volume whose source the VM cannot see mounts as a directory.
      if (err.code === 'ENOENT') return { state: 'none', payload: null, error: null };
      return {
        state: 'none',
        payload: null,
        error: `license unreadable: ${err.code ?? err.message}`,
      };
    }
  }

  let payload;
  try {
    const file = JSON.parse(text);
    if (file.alliswellLicense !== 1 || !file.p || !file.s) throw new Error('not a license file');
    const payloadBytes = Buffer.from(file.p, 'base64');
    const ok = crypto.verify(
      null,
      payloadBytes,
      keyFromBase64(publicKeyBase64),
      Buffer.from(file.s, 'base64'),
    );
    if (!ok) throw new Error('signature verification failed');
    payload = JSON.parse(payloadBytes.toString('utf8'));
  } catch (err) {
    return { state: 'none', payload: null, error: err.message };
  }

  const bad = validatePayload(payload);
  if (bad) return { state: 'none', payload: null, error: bad };

  const expires = new Date(payload.expiresAt);
  const graceEnd = new Date(expires.getTime() + (payload.graceDays ?? 0) * 86400000);
  // Expiry NEVER bricks (overlay ADR-0001 §3): past the grace window the
  // license still names its features — state alone tells modules to degrade.
  const state = now < expires ? 'active' : now < graceEnd ? 'grace' : 'readonly';
  return { state, payload, error: null };
}

function validatePayload(payload) {
  if (typeof payload.customer !== 'string' || !payload.customer) return 'license: customer missing';
  if (!Array.isArray(payload.features) || payload.features.length === 0) {
    return 'license: features missing';
  }
  for (const f of payload.features) {
    if (!EE_FEATURES.includes(f)) return `license: unknown feature "${f}"`;
  }
  if (Number.isNaN(Date.parse(payload.expiresAt))) return 'license: expiresAt unreadable';
  return null;
}
