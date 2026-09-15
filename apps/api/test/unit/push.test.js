import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import crypto from 'node:crypto';
import { buildTestApp, registerUser } from '../helpers/authed.js';
import { loadConfig } from '../../src/config.js';

/** A real P-256 pair — VAPID keys are raw points, and the config checks that. */
function vapidKeys() {
  const { privateKey } = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  const jwk = privateKey.export({ format: 'jwk' });
  return {
    public: Buffer.concat([
      Buffer.from([0x04]),
      Buffer.from(jwk.x, 'base64url'),
      Buffer.from(jwk.y, 'base64url'),
    ]).toString('base64url'),
    private: Buffer.from(jwk.d, 'base64url').toString('base64url'),
  };
}

const keys = vapidKeys();

const configWith = (env) => loadConfig({ NODE_ENV: 'test', RATE_LIMIT_AUTH_MAX: '1000', ...env });

let app;
let owner;

afterEach(async () => {
  if (app) await app.close();
  app = undefined;
});

/**
 * OPH-310 — the credentials are the switch, and the 404 is how a client finds
 * out. An instance with no keys does not have this route at all, which is the
 * same answer as "there is no key": the app never offers the setting.
 */
describe('the VAPID public key endpoint', () => {
  describe('with web push configured', () => {
    beforeEach(async () => {
      ({ app } = await buildTestApp({
        config: configWith({
          PUSH_VAPID_PUBLIC_KEY: keys.public,
          PUSH_VAPID_PRIVATE_KEY: keys.private,
          PUSH_VAPID_SUBJECT: 'mailto:ops@alliswell.space',
        }),
      }));
      owner = await registerUser(app, { email: 'owner@example.com' });
    });

    it('hands out the public key, and only the public one', async () => {
      const res = await app.inject({
        method: 'GET',
        url: '/api/v1/push/public-key',
        headers: owner.headers,
      });
      expect(res.statusCode).toBe(200);
      expect(res.json()).toEqual({ publicKey: keys.public });
      expect(res.body).not.toContain(keys.private);
    });

    it('still wants a caller it recognises', async () => {
      const res = await app.inject({ method: 'GET', url: '/api/v1/push/public-key' });
      expect(res.statusCode).toBe(401);
    });
  });

  describe('with nothing configured', () => {
    beforeEach(async () => {
      ({ app } = await buildTestApp({ config: configWith({}) }));
      owner = await registerUser(app, { email: 'owner@example.com' });
    });

    it('does not have the route at all', async () => {
      const res = await app.inject({
        method: 'GET',
        url: '/api/v1/push/public-key',
        headers: owner.headers,
      });
      expect(res.statusCode).toBe(404);
    });
  });
});

/**
 * The wiring, because this epic's whole lesson is that correct code nothing
 * reaches is not a feature (OPH-309's dead registry).
 */
describe('the transport is reachable, or honestly absent', () => {
  it('is null on an instance with no credentials', async () => {
    ({ app } = await buildTestApp({ config: configWith({}) }));
    expect(app.pushTransport).toBeNull();
  });

  it('is there as soon as one provider is configured', async () => {
    ({ app } = await buildTestApp({
      config: configWith({
        PUSH_VAPID_PUBLIC_KEY: keys.public,
        PUSH_VAPID_PRIVATE_KEY: keys.private,
        PUSH_VAPID_SUBJECT: 'mailto:ops@alliswell.space',
      }),
    }));
    expect(app.pushTransport).not.toBeNull();
    expect(typeof app.pushTransport.send).toBe('function');
  });
});
