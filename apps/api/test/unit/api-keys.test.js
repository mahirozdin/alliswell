import { describe, it, expect, beforeEach } from 'vitest';
import { buildTestApp, registerUser } from '../helpers/authed.js';

/**
 * OPH-264 — API keys (ADR-0032, issue #3).
 *
 * The load-bearing assertions, in the order they would hurt if they broke:
 * the secret is never stored, a key works on the data routes and NOWHERE else,
 * revoked/expired/foreign keys are 401, the workspace binding is enforced even
 * for a user who legitimately belongs to both workspaces, and the JWT path is
 * untouched.
 */

let app;
let tables;
let owner;

beforeEach(async () => {
  ({ app, tables } = await buildTestApp());
  owner = await registerUser(app, { email: 'keys-owner@example.com' });
});

async function createKey(body = { name: 'Home Assistant' }, headers = owner.headers) {
  const res = await app.inject({
    method: 'POST',
    url: `/api/v1/workspaces/${owner.workspace.id}/api-keys`,
    headers,
    payload: body,
  });
  return res;
}

/** Authorization headers for a raw `awk_…` secret. */
const keyHeaders = (token) => ({ authorization: `Bearer ${token}` });

describe('minting a key', () => {
  it('returns the secret ONCE and stores only its digest', async () => {
    const res = await createKey({ name: 'Yedekleme script’i', expiresInDays: 30 });
    expect(res.statusCode).toBe(201);
    const body = res.json();

    expect(body.key).toMatch(/^awk_[A-Za-z0-9_-]{43}$/);
    expect(body.keyPrefix).toBe(body.key.slice(0, 12));
    expect(body.expiresAt).toBeTruthy();
    expect(body.revokedAt).toBeNull();

    // The row holds a 64-char digest and NOT the secret — asserted by looking
    // for the plaintext across the whole row, not just the column we expect.
    const row = tables.api_keys[0];
    expect(row.key_hash).toMatch(/^[a-f0-9]{64}$/);
    expect(JSON.stringify(row)).not.toContain(body.key.slice(4));

    // …and the list never hands it back.
    const list = await app.inject({
      method: 'GET',
      url: `/api/v1/workspaces/${owner.workspace.id}/api-keys`,
      headers: owner.headers,
    });
    expect(list.json().items).toHaveLength(1);
    expect(JSON.stringify(list.json())).not.toContain(body.key.slice(4));
  });

  it('refuses an expiry the UI does not offer', async () => {
    const res = await createKey({ name: 'Uzun', expiresInDays: 3650 });
    expect(res.statusCode).toBe(400);
  });
});

describe('using a key', () => {
  it('authenticates the data routes: read the account, create and read a task', async () => {
    const { key } = (await createKey()).json();

    const me = await app.inject({ method: 'GET', url: '/api/v1/me', headers: keyHeaders(key) });
    expect(me.statusCode).toBe(200);
    expect(me.json().user.email).toBe('keys-owner@example.com');

    const created = await app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${owner.workspace.id}/tasks`,
      headers: keyHeaders(key),
      payload: { title: 'Script’in yarattığı görev' },
    });
    expect(created.statusCode).toBe(201);

    const listed = await app.inject({
      method: 'GET',
      url: `/api/v1/workspaces/${owner.workspace.id}/tasks`,
      headers: keyHeaders(key),
    });
    expect(listed.json().items.map((t) => t.title)).toContain('Script’in yarattığı görev');
    // The write is the user's own, not an anonymous one.
    expect(tables.tasks.at(-1).created_by).toBe(owner.user.id);
  });

  it('stamps last_used_at so revoking can be an informed decision', async () => {
    const { key, id } = (await createKey()).json();
    expect(tables.api_keys.find((k) => k.id === id).last_used_at).toBeNull();

    await app.inject({ method: 'GET', url: '/api/v1/me', headers: keyHeaders(key) });
    // The stamp is fire-and-forget; give the microtask queue a turn.
    await new Promise((resolve) => setImmediate(resolve));
    expect(tables.api_keys.find((k) => k.id === id).last_used_at).toBeTruthy();
  });

  it('refuses revoked, expired and unknown keys with 401', async () => {
    const { key, id } = (await createKey()).json();

    const revoke = await app.inject({
      method: 'POST',
      url: `/api/v1/api-keys/${id}/revoke`,
      headers: owner.headers,
    });
    expect(revoke.statusCode).toBe(200);
    expect(revoke.json().revokedAt).toBeTruthy();

    const afterRevoke = await app.inject({
      method: 'GET',
      url: '/api/v1/me',
      headers: keyHeaders(key),
    });
    expect(afterRevoke.statusCode).toBe(401);
    expect(afterRevoke.json().code).toBe('AUTH_API_KEY_REVOKED');

    // An expired key: same door, different code.
    const second = (await createKey({ name: 'Süreli', expiresInDays: 30 })).json();
    await app
      .db('api_keys')
      .where({ id: second.id })
      .update({ expires_at: new Date(Date.now() - 1000) });
    const expired = await app.inject({
      method: 'GET',
      url: '/api/v1/me',
      headers: keyHeaders(second.key),
    });
    expect(expired.statusCode).toBe(401);
    expect(expired.json().code).toBe('AUTH_API_KEY_EXPIRED');

    // A secret that was never minted must not leak that fact either.
    const unknown = await app.inject({
      method: 'GET',
      url: '/api/v1/me',
      headers: keyHeaders('awk_thisonewasnevermintedanywhereatall000'),
    });
    expect(unknown.statusCode).toBe(401);
    expect(unknown.json().code).toBe('AUTH_INVALID_API_KEY');
  });

  it('is bound to ONE workspace, even when its owner belongs to both', async () => {
    // The same person, two workspaces: the key must not follow them.
    const second = await app.inject({
      method: 'POST',
      url: '/api/v1/workspaces',
      headers: owner.headers,
      payload: { name: 'İkinci alan' },
    });
    // Workspace creation may not exist as a route in v1 — in that case build
    // the membership directly, which is what the API would have produced.
    let otherWorkspaceId;
    if (second.statusCode === 201) {
      otherWorkspaceId = second.json().id;
    } else {
      const outsider = await registerUser(app, { email: 'keys-other@example.com' });
      otherWorkspaceId = outsider.workspace.id;
      tables.workspace_members.push({
        id: `member-x`.padEnd(26, '0'),
        workspace_id: otherWorkspaceId,
        user_id: owner.user.id,
        role: 'member',
        created_at: new Date(),
        updated_at: new Date(),
      });
    }

    const { key } = (await createKey()).json();
    // The owner IS a member there — a JWT proves it…
    const withJwt = await app.inject({
      method: 'GET',
      url: `/api/v1/workspaces/${otherWorkspaceId}/tasks`,
      headers: owner.headers,
    });
    expect(withJwt.statusCode).toBe(200);
    // …and the key still has no business in that workspace.
    const withKey = await app.inject({
      method: 'GET',
      url: `/api/v1/workspaces/${otherWorkspaceId}/tasks`,
      headers: keyHeaders(key),
    });
    expect(withKey.statusCode).toBe(403);
    expect(withKey.json().code).toBe('AUTH_APIKEY_WORKSPACE');
  });
});

describe('the doors a key may never open (ADR-0032 §4)', () => {
  it('cannot mint or revoke keys — otherwise revocation would be theatre', async () => {
    const { key, id } = (await createKey()).json();

    const mint = await createKey({ name: 'Kendi kendine' }, keyHeaders(key));
    expect(mint.statusCode).toBe(403);
    expect(mint.json().code).toBe('AUTH_APIKEY_FORBIDDEN');

    const list = await app.inject({
      method: 'GET',
      url: `/api/v1/workspaces/${owner.workspace.id}/api-keys`,
      headers: keyHeaders(key),
    });
    expect(list.statusCode).toBe(403);

    const revoke = await app.inject({
      method: 'POST',
      url: `/api/v1/api-keys/${id}/revoke`,
      headers: keyHeaders(key),
    });
    expect(revoke.statusCode).toBe(403);
    // Nothing was minted and nothing was revoked.
    expect(tables.api_keys).toHaveLength(1);
    expect(tables.api_keys[0].revoked_at ?? null).toBeNull();
  });

  it('cannot delete the account it leaked from, nor cancel a deletion', async () => {
    const { key } = (await createKey()).json();

    const remove = await app.inject({
      method: 'DELETE',
      url: '/api/v1/me',
      headers: keyHeaders(key),
    });
    expect(remove.statusCode).toBe(403);
    expect(remove.json().code).toBe('AUTH_APIKEY_FORBIDDEN');
    expect(
      tables.users.find((u) => u.id === owner.user.id).deletion_scheduled_at ?? null,
    ).toBeNull();

    const cancel = await app.inject({
      method: 'POST',
      url: '/api/v1/me/deletion/cancel',
      headers: keyHeaders(key),
    });
    expect(cancel.statusCode).toBe(403);
  });

  it('cannot reach /ai/* — those hold BYOK secrets and spend model money', async () => {
    const { key } = (await createKey()).json();

    const base = `/api/v1/workspaces/${owner.workspace.id}/ai`;
    const connections = await app.inject({
      method: 'GET',
      url: `${base}/connections`,
      headers: keyHeaders(key),
    });
    expect(connections.statusCode).toBe(403);
    expect(connections.json().code).toBe('AUTH_APIKEY_FORBIDDEN');

    const create = await app.inject({
      method: 'POST',
      url: `${base}/connections`,
      headers: keyHeaders(key),
      payload: { provider: 'anthropic', apiKey: 'sk-ant-secret', consentAcknowledged: true },
    });
    expect(create.statusCode).toBe(403);
    expect(tables.ai_connections).toHaveLength(0);

    // Even the read-only status route, which looks harmless, stays shut: the
    // gate is the credential, not the individual endpoint's risk.
    const status = await app.inject({
      method: 'GET',
      url: `${base}/status`,
      headers: keyHeaders(key),
    });
    expect(status.statusCode).toBe(403);

    // The same call with a JWT is fine — nothing is broken, it is refused.
    const withJwt = await app.inject({
      method: 'GET',
      url: `${base}/connections`,
      headers: owner.headers,
    });
    expect(withJwt.statusCode).toBe(200);
  });
});

describe('key management is the owner’s own', () => {
  it('another account can neither see nor revoke this account’s keys', async () => {
    const { id } = (await createKey()).json();
    const outsider = await registerUser(app, { email: 'keys-outsider@example.com' });

    const revoke = await app.inject({
      method: 'POST',
      url: `/api/v1/api-keys/${id}/revoke`,
      headers: outsider.headers,
    });
    // Not "forbidden" — not there. Someone else's key is not their business.
    expect(revoke.statusCode).toBe(404);
    expect(tables.api_keys[0].revoked_at ?? null).toBeNull();

    const list = await app.inject({
      method: 'GET',
      url: `/api/v1/workspaces/${owner.workspace.id}/api-keys`,
      headers: outsider.headers,
    });
    expect(list.statusCode).toBe(403);
  });

  it('revoking twice keeps the first timestamp — when did it stop working?', async () => {
    const { id } = (await createKey()).json();
    const first = await app.inject({
      method: 'POST',
      url: `/api/v1/api-keys/${id}/revoke`,
      headers: owner.headers,
    });
    const second = await app.inject({
      method: 'POST',
      url: `/api/v1/api-keys/${id}/revoke`,
      headers: owner.headers,
    });
    expect(second.statusCode).toBe(200);
    expect(second.json().revokedAt).toBe(first.json().revokedAt);
  });
});
