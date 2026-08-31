import { describe, it, expect } from 'vitest';

import {
  TOTP_STEP_SEC,
  base32Decode,
  base32Encode,
  generateTotpSecret,
  totp,
  totpStep,
  totpUri,
  verifyTotp,
} from '../../src/lib/totp.js';

/// OPH-283 — the arithmetic, against the RFC's own answers.
///
/// Hand-rolled crypto earns its place by being checked against the published
/// vectors rather than against itself. RFC 6238 Appendix B is the whole point
/// of this file: if these six numbers come out right, the HMAC, the counter
/// packing, the dynamic truncation and the modulus are all correct together,
/// and no amount of "it verifies what it generated" would have told us that.
describe('TOTP (RFC 6238)', () => {
  // The RFC's SHA-1 seed: the ASCII string "12345678901234567890".
  const SECRET = base32Encode(Buffer.from('12345678901234567890', 'ascii'));

  // RFC 6238 Appendix B, the SHA-1 rows, 8 digits.
  const VECTORS = [
    [59, '94287082'],
    [1111111109, '07081804'],
    [1111111111, '14050471'],
    [1234567890, '89005924'],
    [2000000000, '69279037'],
    [20000000000, '65353130'],
  ];

  it.each(VECTORS)('T=%i gives %s', (unixSeconds, expected) => {
    expect(totp(SECRET, { at: new Date(unixSeconds * 1000), digits: 8 })).toBe(expected);
  });

  it('round-trips base32 for arbitrary bytes', () => {
    const bytes = Buffer.from([0, 1, 2, 250, 251, 252, 253, 254, 255]);
    expect(base32Decode(base32Encode(bytes))).toEqual(bytes);
  });

  it('refuses a secret that is not base32, rather than hashing nonsense', () => {
    expect(() => base32Decode('not-base32!')).toThrowError(
      expect.objectContaining({ code: 'TOTP_BAD_SECRET' }),
    );
  });

  it('mints 160-bit secrets, which is what authenticators expect', () => {
    const secret = generateTotpSecret();
    expect(secret).toMatch(/^[A-Z2-7]+$/);
    expect(base32Decode(secret)).toHaveLength(20);
  });
});

describe('verification', () => {
  const secret = generateTotpSecret();
  const at = new Date(1_700_000_000_000);

  it('accepts the current code and returns the step it matched', () => {
    const step = verifyTotp(secret, totp(secret, { at }), { at });
    expect(step).toBe(totpStep(at));
  });

  it('accepts one step of drift either way, and nothing beyond it', () => {
    const early = new Date(at.getTime() - TOTP_STEP_SEC * 1000);
    const late = new Date(at.getTime() + TOTP_STEP_SEC * 1000);
    const tooEarly = new Date(at.getTime() - TOTP_STEP_SEC * 2000);

    expect(verifyTotp(secret, totp(secret, { at: early }), { at })).not.toBeNull();
    expect(verifyTotp(secret, totp(secret, { at: late }), { at })).not.toBeNull();
    expect(verifyTotp(secret, totp(secret, { at: tooEarly }), { at })).toBeNull();
  });

  it('refuses a code at or below a step already spent', () => {
    // The replay guarantee: a code read over somebody's shoulder is good for
    // up to ninety seconds without this.
    const code = totp(secret, { at });
    const step = verifyTotp(secret, code, { at });
    expect(verifyTotp(secret, code, { at, lastStep: step })).toBeNull();
  });

  it('refuses anything that is not six digits without touching the secret', () => {
    for (const bad of ['', '12345', '1234567', 'abcdef', '12 34 56']) {
      expect(verifyTotp(secret, bad, { at })).toBeNull();
    }
  });
});

describe('the enrolment URI', () => {
  it('carries the parameters an authenticator needs, and the issuer twice', () => {
    const uri = totpUri({ secret: 'ABCDEFGH', email: 'ada@example.com' });
    expect(uri).toMatch(/^otpauth:\/\/totp\/AllisWell%3Aada%40example\.com\?/);
    // Path AND query: different apps have historically read different ones.
    expect(uri).toContain('issuer=AllisWell');
    expect(uri).toContain('algorithm=SHA1');
    expect(uri).toContain('digits=6');
    expect(uri).toContain('period=30');
  });
});
