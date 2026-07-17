import { describe, it, expect } from 'vitest';
import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config.js';
import { fakeDb, fakeRedis } from '../helpers/fakedb.js';

const testConfig = loadConfig({ NODE_ENV: 'test', RATE_LIMIT_AUTH_MAX: '100' });

async function appWithSession() {
  const { db, tables } = fakeDb();
  const app = await buildApp({ config: testConfig, db, redis: fakeRedis() });
  const res = await app.inject({
    method: 'POST',
    url: '/api/v1/auth/register',
    payload: {
      email: 'mahir@example.com',
      password: 'correct-horse-battery',
      displayName: 'Mahir',
    },
  });
  expect(res.statusCode).toBe(201);
  const body = res.json();
  return { app, tables, registered: body, accessToken: body.tokens.accessToken };
}

const me = (app, token) =>
  app.inject({
    method: 'GET',
    url: '/api/v1/me',
    headers: token ? { authorization: `Bearer ${token}` } : {},
  });

describe('GET /api/v1/me (OPH-023)', () => {
  it('returns profile and workspaces for a fresh registration (epic acceptance)', async () => {
    const { app, registered, accessToken } = await appWithSession();
    const res = await me(app, accessToken);

    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.user).toMatchObject({
      id: registered.user.id,
      email: 'mahir@example.com',
      displayName: 'Mahir',
      timezone: 'Europe/Istanbul',
      locale: 'tr-TR',
    });
    expect(new Date(body.user.createdAt).getTime()).not.toBeNaN();
    expect(body.workspaces).toHaveLength(1);
    expect(body.workspaces[0]).toMatchObject({
      id: registered.workspace.id,
      name: "Mahir's Space",
      slug: registered.workspace.slug,
      colorRgb: '#2563EB',
      role: 'owner',
    });

    await app.close();
  });

  it('rejects a missing token with AUTH_INVALID_TOKEN', async () => {
    const { app } = await appWithSession();
    const res = await me(app);
    expect(res.statusCode).toBe(401);
    expect(res.json()).toMatchObject({ code: 'AUTH_INVALID_TOKEN' });
    await app.close();
  });

  it('rejects garbage and wrong-signature tokens', async () => {
    const { app } = await appWithSession();

    expect((await me(app, 'not-a-jwt')).statusCode).toBe(401);

    // Signed with a different secret (attacker-forged).
    const evil = await buildApp({
      config: loadConfig({
        NODE_ENV: 'test',
        JWT_ACCESS_SECRET: 'completely-different-secret-string-000',
      }),
      db: fakeDb().db,
      redis: fakeRedis(),
    });
    const forged = evil.signAccessToken({ id: 'someone', email: 'x@example.com' });
    const res = await me(app, forged);
    expect(res.statusCode).toBe(401);
    expect(res.json()).toMatchObject({ code: 'AUTH_INVALID_TOKEN' });

    await evil.close();
    await app.close();
  });

  it('rejects an expired token with AUTH_TOKEN_EXPIRED', async () => {
    const { app, registered } = await appWithSession();
    const shortLived = app.jwt.sign(
      { sub: registered.user.id, email: registered.user.email },
      { expiresIn: 1 }, // seconds
    );
    await new Promise((resolve) => setTimeout(resolve, 1100));
    const res = await me(app, shortLived);
    expect(res.statusCode).toBe(401);
    expect(res.json()).toMatchObject({ code: 'AUTH_TOKEN_EXPIRED' });
    await app.close();
  });

  it('rejects a valid token whose user was deleted meanwhile', async () => {
    const { app, tables, accessToken } = await appWithSession();
    tables.users[0].deleted_at = new Date();
    const res = await me(app, accessToken);
    expect(res.statusCode).toBe(401);
    expect(res.json()).toMatchObject({ code: 'AUTH_INVALID_TOKEN' });
    await app.close();
  });
});

const patchMe = (app, token, payload) =>
  app.inject({
    method: 'PATCH',
    url: '/api/v1/me',
    headers: token ? { authorization: `Bearer ${token}` } : {},
    payload,
  });

describe('PATCH /api/v1/me (OPH-126) — account language', () => {
  it('updates the locale and returns (and persists) the fresh profile', async () => {
    const { app, accessToken } = await appWithSession();

    const res = await patchMe(app, accessToken, { locale: 'en' });
    expect(res.statusCode).toBe(200);
    expect(res.json().user.locale).toBe('en');

    // A follow-up GET sees the persisted value.
    const after = await me(app, accessToken);
    expect(after.json().user.locale).toBe('en');

    await app.close();
  });

  it('accepts a region variant (tr-TR)', async () => {
    const { app, accessToken } = await appWithSession();
    const res = await patchMe(app, accessToken, { locale: 'tr-TR' });
    expect(res.statusCode).toBe(200);
    expect(res.json().user.locale).toBe('tr-TR');
    await app.close();
  });

  it('rejects a malformed locale with 400', async () => {
    const { app, accessToken } = await appWithSession();
    const res = await patchMe(app, accessToken, { locale: 'english!' });
    expect(res.statusCode).toBe(400);
    await app.close();
  });

  it('rejects an unauthenticated request with 401', async () => {
    const { app } = await appWithSession();
    const res = await patchMe(app, null, { locale: 'en' });
    expect(res.statusCode).toBe(401);
    await app.close();
  });
});

describe('app.requireWorkspaceMember (OPH-023)', () => {
  it('allows members, enforces roles, and rejects outsiders with 403', async () => {
    const { app, tables, registered } = await appWithSession();
    const request = { user: { id: registered.user.id } };
    const workspaceId = registered.workspace.id;

    const member = await app.requireWorkspaceMember(request, workspaceId);
    expect(member.role).toBe('owner');

    await expect(
      app.requireWorkspaceMember(request, workspaceId, { roles: ['owner', 'admin'] }),
    ).resolves.toMatchObject({ role: 'owner' });

    // Demote to member: owner-only actions must now fail.
    tables.workspace_members[0].role = 'member';
    await expect(
      app.requireWorkspaceMember(request, workspaceId, { roles: ['owner', 'admin'] }),
    ).rejects.toMatchObject({ statusCode: 403, code: 'AUTH_WORKSPACE_FORBIDDEN' });

    // Outsider: no membership row at all.
    await expect(
      app.requireWorkspaceMember({ user: { id: 'someone-else' } }, workspaceId),
    ).rejects.toMatchObject({ statusCode: 403, code: 'AUTH_WORKSPACE_FORBIDDEN' });

    await app.close();
  });
});
