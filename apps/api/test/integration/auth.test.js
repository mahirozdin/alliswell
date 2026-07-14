import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config.js';
import { hashRefreshToken } from '../../src/lib/tokens.js';

// Needs real MySQL + Redis with migrations applied (see test/integration/ready.test.js).
const enabled = process.env.INTEGRATION === '1';

const emailPrefix = `oph020-${Date.now()}`;

describe.runIf(enabled)('integration: POST /api/v1/auth/register', () => {
  let app;

  beforeAll(async () => {
    app = await buildApp({ config: loadConfig({ ...process.env, NODE_ENV: 'test' }) });
  });

  afterAll(async () => {
    if (!app) return;
    // Workspaces first (owner FK is RESTRICT); deleting users cascades members + tokens.
    const users = await app.db('users').where('email', 'like', `${emailPrefix}%`).select('id');
    const ids = users.map((u) => u.id);
    if (ids.length > 0) {
      await app.db('workspaces').whereIn('owner_id', ids).delete();
      await app.db('users').whereIn('id', ids).delete();
    }
    await app.close();
  });

  it('registers a user and persists workspace, membership and hashed refresh token', async () => {
    const email = `${emailPrefix}-happy@example.com`;
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      payload: { email, password: 'integration-pw-1', displayName: 'Integration Kişi' },
    });

    expect(res.statusCode).toBe(201);
    const body = res.json();

    // The issued access token is verifiable by the server (acceptance: usable immediately).
    const claims = app.jwt.verify(body.tokens.accessToken);
    expect(claims.sub).toBe(body.user.id);

    const user = await app.db('users').where({ id: body.user.id }).first();
    expect(user.email).toBe(email);
    expect(user.password_hash).toMatch(/^\$argon2id\$/);
    expect(user.created_at).toBeTruthy();

    const workspace = await app.db('workspaces').where({ id: body.workspace.id }).first();
    expect(workspace.owner_id).toBe(body.user.id);
    expect(workspace.name).toBe("Integration Kişi's Space");

    const member = await app
      .db('workspace_members')
      .where({ workspace_id: body.workspace.id, user_id: body.user.id })
      .first();
    expect(member.role).toBe('owner');

    const token = await app.db('refresh_tokens').where({ user_id: body.user.id }).first();
    expect(token.token_hash).toBe(
      hashRefreshToken(body.tokens.refreshToken, app.config.auth.refreshSecret),
    );
    expect(new Date(token.expires_at).getTime()).toBeGreaterThan(Date.now());
  });

  it('rejects a duplicate email with 409 AUTH_EMAIL_TAKEN and leaves a single user row', async () => {
    const email = `${emailPrefix}-dup@example.com`;
    const payload = { email, password: 'integration-pw-2' };

    expect(
      (await app.inject({ method: 'POST', url: '/api/v1/auth/register', payload })).statusCode,
    ).toBe(201);

    const res = await app.inject({ method: 'POST', url: '/api/v1/auth/register', payload });
    expect(res.statusCode).toBe(409);
    expect(res.json()).toMatchObject({ code: 'AUTH_EMAIL_TAKEN' });

    const rows = await app.db('users').where({ email });
    expect(rows).toHaveLength(1);
  });

  it('rejects weak passwords with 400 and writes nothing', async () => {
    const email = `${emailPrefix}-weak@example.com`;
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      payload: { email, password: 'seven77' },
    });
    expect(res.statusCode).toBe(400);
    expect(await app.db('users').where({ email })).toHaveLength(0);
  });
});
