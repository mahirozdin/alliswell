import { describe, it, expect } from 'vitest';
import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config.js';
import { fakeDb, fakeRedis } from '../helpers/fakedb.js';

/**
 * OPH-392 (E-23) — which social sign-ins this server can complete.
 *
 * The app offered "Continue with Google" on every server, and on one with no
 * SIGN_IN_GOOGLE_* client the tap could only end in
 * OAUTH_PROVIDER_NOT_CONFIGURED. The sign-in screen asks this first. Booleans
 * only: the client ids themselves stay on the server.
 */
async function appWith(env) {
  const { db } = fakeDb();
  return buildApp({ config: loadConfig({ NODE_ENV: 'test', ...env }), db, redis: fakeRedis() });
}

const providers = (app) => app.inject({ method: 'GET', url: '/api/v1/auth/providers' });

describe('GET /api/v1/auth/providers (OPH-392)', () => {
  it('reports nothing on a server with no sign-in client configured', async () => {
    const app = await appWith({});
    const res = await providers(app);
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ google: false, apple: false });
    await app.close();
  });

  it('reports each provider whose client is configured, without its id', async () => {
    const app = await appWith({
      SIGN_IN_GOOGLE_IOS_CLIENT_ID: 'ios.apps.googleusercontent.com',
      SIGN_IN_APPLE_BUNDLE_ID: 'com.alliswell.alliswell',
    });
    const res = await providers(app);
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ google: true, apple: true });
    expect(res.body).not.toContain('googleusercontent');
    expect(res.body).not.toContain('com.alliswell');
    await app.close();
  });

  it('answers without a session', async () => {
    const app = await appWith({ SIGN_IN_GOOGLE_WEB_CLIENT_ID: 'web.apps.googleusercontent.com' });
    const res = await providers(app);
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ google: true, apple: false });
    await app.close();
  });
});
