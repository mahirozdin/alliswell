import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config.js';
import { fakeDb, fakeRedis } from './fakedb.js';

// Epic 04+ suites fire many auth calls per app instance — keep the limiter out
// of the way (it has its own dedicated tests in auth-login.test.js).
const testConfig = loadConfig({ NODE_ENV: 'test', RATE_LIMIT_AUTH_MAX: '1000' });

export async function buildTestApp({ config = testConfig, dbOptions } = {}) {
  const { db, tables } = fakeDb(dbOptions);
  const app = await buildApp({ config, db, redis: fakeRedis() });
  return { app, tables };
}

/** Registers a user via the real endpoint; returns identity + Bearer headers. */
export async function registerUser(app, { email, password = 'test-password-1', displayName } = {}) {
  const res = await app.inject({
    method: 'POST',
    url: '/api/v1/auth/register',
    payload: { email, password, ...(displayName ? { displayName } : {}) },
  });
  if (res.statusCode !== 201) {
    throw new Error(`registerUser failed: ${res.statusCode} ${res.body}`);
  }
  const body = res.json();
  return {
    user: body.user,
    workspace: body.workspace,
    headers: { authorization: `Bearer ${body.tokens.accessToken}` },
  };
}

/** Adds `user` to `workspaceId` with the given role (directly in the fake db). */
export function addMember(tables, { workspaceId, user, role = 'member' }) {
  tables.workspace_members.push({
    id: `member-${tables.workspace_members.length + 1}`.padEnd(26, '0'),
    workspace_id: workspaceId,
    user_id: user.id,
    role,
    created_at: new Date(),
    updated_at: new Date(),
  });
}
