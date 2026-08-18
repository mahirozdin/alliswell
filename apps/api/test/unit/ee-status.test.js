import { describe, it, expect, afterEach } from 'vitest';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';

import { buildTestApp, registerUser } from '../helpers/authed.js';
import { loadConfig } from '../../src/config.js';
import { verifyLicenseFile } from '../../src/lib/ee-license.js';

/**
 * EE-003/EE-004 — instance entitlements and the Ed25519 license source. The
 * contract: /ee/status ALWAYS answers (CE = empty 200, never 404); the dev
 * override exists only outside production; a license walks active → grace →
 * readonly and NOTHING ever bricks; tampering and wrong keys read as CE.
 */

function ephemeralLicense(payload, { tamper = false, wrongKey = false } = {}) {
  const { privateKey, publicKey } = crypto.generateKeyPairSync('ed25519');
  const payloadBytes = Buffer.from(JSON.stringify(payload), 'utf8');
  const signed = crypto.sign(null, payloadBytes, privateKey);
  const file = {
    alliswellLicense: 1,
    p: (tamper
      ? Buffer.from(JSON.stringify({ ...payload, seats: 99999 }), 'utf8')
      : payloadBytes
    ).toString('base64'),
    s: signed.toString('base64'),
  };
  const keySource = wrongKey ? crypto.generateKeyPairSync('ed25519').publicKey : publicKey;
  const publicBase64 = keySource
    .export({ format: 'der', type: 'spki' })
    .subarray(12)
    .toString('base64');
  return { raw: JSON.stringify(file), publicBase64 };
}

const payloadAt = (expiresAt, graceDays = 10) => ({
  customer: 'Test Fabrikası A.Ş.',
  seats: 100,
  teams: 3,
  features: ['teams', 'itsm'],
  issuedAt: '2026-08-01T00:00:00.000Z',
  expiresAt,
  graceDays,
});

let app;

afterEach(async () => {
  await app?.close();
});

describe('GET /ee/status (EE-003)', () => {
  it('answers an empty 200 on a CE build — never a 404', async () => {
    ({ app } = await buildTestApp());
    const owner = await registerUser(app, { email: 'ee-ce@example.com' });
    const res = await app.inject({
      method: 'GET',
      url: '/api/v1/ee/status',
      headers: owner.headers,
    });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({
      state: 'none',
      features: [],
      expiresAt: null,
      overlay: 'disabled',
    });
  });

  it('requires authentication', async () => {
    ({ app } = await buildTestApp());
    const res = await app.inject({ method: 'GET', url: '/api/v1/ee/status' });
    expect(res.statusCode).toBe(401);
  });

  it('serves the dev override and gates has() through the one dictionary', async () => {
    const config = loadConfig({
      NODE_ENV: 'test',
      RATE_LIMIT_AUTH_MAX: '1000',
      EE_DEV_ENTITLEMENTS: 'teams, itsm',
    });
    ({ app } = await buildTestApp({ config }));
    const owner = await registerUser(app, { email: 'ee-dev@example.com' });
    const res = await app.inject({
      method: 'GET',
      url: '/api/v1/ee/status',
      headers: owner.headers,
    });
    expect(res.json()).toMatchObject({ state: 'active', features: ['teams', 'itsm'] });
    expect(app.entitlements.has('teams')).toBe(true);
    expect(app.entitlements.has('sla')).toBe(false);
    expect(() => app.entitlements.has('bogus')).toThrow(/dictionary/);
  });

  it('refuses the dev override in production, and unknown names anywhere', () => {
    expect(() =>
      loadConfig({
        NODE_ENV: 'production',
        JWT_ACCESS_SECRET: 'a'.repeat(32) + '-access-strong-random-secret',
        JWT_REFRESH_SECRET: 'b'.repeat(32) + '-refresh-strong-random-secret',
        AI_TOKEN_KEY: 'a1b2c3d4'.repeat(8),
        EE_DEV_ENTITLEMENTS: 'teams',
      }),
    ).toThrow(/must not be set in production/);
    expect(() => loadConfig({ NODE_ENV: 'test', EE_DEV_ENTITLEMENTS: 'teems' })).toThrow(
      /unknown feature "teems"/,
    );
  });
});

describe('license source (EE-004)', () => {
  const writeLicense = (raw) => {
    const dir = mkdtempSync(path.join(tmpdir(), 'aw-ee-license-'));
    const licensePath = path.join(dir, 'license.json');
    writeFileSync(licensePath, raw);
    return licensePath;
  };

  const appWithLicense = async (raw, publicBase64) => {
    const config = loadConfig({
      NODE_ENV: 'test',
      RATE_LIMIT_AUTH_MAX: '1000',
      EE_LICENSE_PATH: writeLicense(raw),
      EE_LICENSE_PUBLIC_KEY: publicBase64,
    });
    return buildTestApp({ config });
  };

  it('a live license answers active with its features and expiry', async () => {
    const { raw, publicBase64 } = ephemeralLicense(payloadAt('2099-01-01T00:00:00.000Z'));
    ({ app } = await appWithLicense(raw, publicBase64));
    const owner = await registerUser(app, { email: 'ee-lic@example.com' });
    const res = await app.inject({
      method: 'GET',
      url: '/api/v1/ee/status',
      headers: owner.headers,
    });
    expect(res.json()).toMatchObject({
      state: 'active',
      features: ['teams', 'itsm'],
      expiresAt: '2099-01-01T00:00:00.000Z',
    });
    expect(app.entitlements.has('teams')).toBe(true);
  });

  it('tampered payloads and wrong keys read as CE — indistinguishable by behaviour', async () => {
    const tampered = ephemeralLicense(payloadAt('2099-01-01T00:00:00.000Z'), { tamper: true });
    ({ app } = await appWithLicense(tampered.raw, tampered.publicBase64));
    expect(app.entitlements.state).toBe('none');
    expect(app.entitlements.list()).toEqual([]);
    await app.close();

    const wrong = ephemeralLicense(payloadAt('2099-01-01T00:00:00.000Z'), { wrongKey: true });
    ({ app } = await appWithLicense(wrong.raw, wrong.publicBase64));
    expect(app.entitlements.state).toBe('none');
  });

  it('walks active → grace → readonly on the clock, and readonly never bricks', () => {
    const { raw, publicBase64 } = ephemeralLicense(payloadAt('2026-08-10T00:00:00.000Z', 10));
    const at = (iso) =>
      verifyLicenseFile({ raw, publicKeyBase64: publicBase64, now: new Date(iso) });
    expect(at('2026-08-09T00:00:00.000Z').state).toBe('active');
    expect(at('2026-08-15T00:00:00.000Z').state).toBe('grace'); // within 10 grace days
    expect(at('2026-08-25T00:00:00.000Z').state).toBe('readonly'); // past them
    // readonly still NAMES its features — degradation is a state, not amnesia.
    expect(at('2026-08-25T00:00:00.000Z').payload.features).toEqual(['teams', 'itsm']);
  });

  it('has() is true through grace and false in readonly', async () => {
    const graceLicense = ephemeralLicense({
      ...payloadAt(new Date(Date.now() - 86400000).toISOString(), 10), // expired yesterday
    });
    ({ app } = await appWithLicense(graceLicense.raw, graceLicense.publicBase64));
    expect(app.entitlements.state).toBe('grace');
    expect(app.entitlements.has('teams')).toBe(true);
    await app.close();

    const deadLicense = ephemeralLicense({
      ...payloadAt('2026-01-01T00:00:00.000Z', 5), // long past + short grace
    });
    ({ app } = await appWithLicense(deadLicense.raw, deadLicense.publicBase64));
    expect(app.entitlements.state).toBe('readonly');
    expect(app.entitlements.has('teams')).toBe(false);
    expect(app.entitlements.list()).toEqual(['teams', 'itsm']); // named, not erased
  });

  it('a license path that is a DIRECTORY surfaces an error instead of silent CE', () => {
    // The bad-bind-mount shape: Docker materializes an unshared volume source
    // as an empty directory at the target. That must not read as "no license".
    const dir = mkdtempSync(path.join(tmpdir(), 'aw-ee-dirlic-'));
    const result = verifyLicenseFile({ path: dir, publicKeyBase64: 'AA==' });
    expect(result.state).toBe('none');
    expect(result.error).toMatch(/unreadable/);
  });

  it('a license naming an unknown feature reads as CE (dictionary is law)', async () => {
    const { raw, publicBase64 } = ephemeralLicense({
      ...payloadAt('2099-01-01T00:00:00.000Z'),
      features: ['teams', 'timetravel'],
    });
    ({ app } = await appWithLicense(raw, publicBase64));
    expect(app.entitlements.state).toBe('none');
  });
});
