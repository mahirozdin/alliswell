import { describe, it, expect, beforeEach } from 'vitest';
import { loadConfig } from '../../src/config.js';
import { decryptSecret } from '../../src/lib/crypto.js';
import { buildTestApp, registerUser, addMember } from '../helpers/authed.js';

/**
 * OPH-215 — AI connection CRUD. The load-bearing assertions: ciphertext at
 * rest, plaintext never stored and never serialized, ownership as 404, the
 * tombstone-revival semantics of the unique tuple, and the AI_ENABLED gate.
 */

const KEY = 'sk-ant-api03-verysecret-2026';

function createBody(overrides = {}) {
  return {
    provider: 'anthropic',
    apiKey: KEY,
    consentAcknowledged: true,
    ...overrides,
  };
}

describe('AI connections (OPH-215)', () => {
  let app;
  let tables;
  let owner;

  beforeEach(async () => {
    ({ app, tables } = await buildTestApp());
    owner = await registerUser(app, { email: 'ai-owner@example.com' });
  });

  async function createConnection(body = createBody(), headers = owner.headers) {
    return app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${owner.workspace.id}/ai/connections`,
      headers,
      payload: body,
    });
  }

  it('creates a connection: key encrypted at rest, only last4 on the wire', async () => {
    const res = await createConnection();
    expect(res.statusCode).toBe(201);
    const body = res.json();
    expect(body.provider).toBe('anthropic');
    expect(body.authMode).toBe('api_key');
    expect(body.keyLast4).toBe(KEY.slice(-4));
    // The response never carries the key or any ciphertext fragment.
    expect(res.body).not.toContain(KEY);
    expect(res.body).not.toContain('v1:');
    expect(body.apiKey).toBeUndefined();
    expect(body.encryptedKey).toBeUndefined();

    const row = tables.ai_connections[0];
    expect(row.encrypted_key).toMatch(/^v1:/);
    expect(row.encrypted_key).not.toContain(KEY);
    expect(decryptSecret(row.encrypted_key, app.config.ai.tokenKey)).toBe(KEY);
  });

  it('requires a key for cloud providers and a base URL for BYOK ollama', async () => {
    const noKey = await createConnection(createBody({ apiKey: undefined }));
    expect(noKey.statusCode).toBe(400);
    expect(noKey.json().code).toBe('AI_KEY_REQUIRED');

    const ollamaNoUrl = await createConnection(
      createBody({ provider: 'ollama', apiKey: undefined }),
    );
    expect(ollamaNoUrl.statusCode).toBe(400);
    expect(ollamaNoUrl.json().code).toBe('AI_BASE_URL_REQUIRED');

    const ollama = await createConnection(
      createBody({ provider: 'ollama', apiKey: undefined, baseUrl: 'http://127.0.0.1:11434' }),
    );
    expect(ollama.statusCode).toBe(201);
    expect(ollama.json().keyLast4).toBeNull();
  });

  it('refuses the reserved oauth_subscription mode at the schema', async () => {
    const res = await createConnection(createBody({ authMode: 'oauth_subscription' }));
    expect(res.statusCode).toBe(400);
  });

  it('refuses consentAcknowledged !== true at the schema', async () => {
    const res = await createConnection(createBody({ consentAcknowledged: false }));
    expect(res.statusCode).toBe(400);
    const missing = await createConnection({ provider: 'openai', apiKey: KEY });
    expect(missing.statusCode).toBe(400);
  });

  it('handles instance_env: needs the env key, refuses a user key', async () => {
    const missing = await createConnection(
      createBody({ authMode: 'instance_env', apiKey: undefined, provider: 'openai' }),
    );
    expect(missing.statusCode).toBe(422);
    expect(missing.json().code).toBe('AI_INSTANCE_KEY_MISSING');

    const withKey = await createConnection(
      createBody({ authMode: 'instance_env', provider: 'openai' }),
    );
    expect(withKey.statusCode).toBe(400);
    expect(withKey.json().code).toBe('AI_KEY_NOT_ALLOWED');

    // Same instance, env key present → 201 with no key material of our own.
    const config = loadConfig({
      NODE_ENV: 'test',
      RATE_LIMIT_AUTH_MAX: '1000',
      AI_OPENAI_API_KEY: 'sk-instance-key-123',
    });
    const { app: app2 } = await buildTestApp({ config });
    const user2 = await registerUser(app2, { email: 'ai-inst@example.com' });
    const ok = await app2.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${user2.workspace.id}/ai/connections`,
      headers: user2.headers,
      payload: createBody({ authMode: 'instance_env', apiKey: undefined, provider: 'openai' }),
    });
    expect(ok.statusCode).toBe(201);
    expect(ok.json().keyLast4).toBeNull();
  });

  it('enforces one live connection per provider, and revives the tombstone', async () => {
    const first = await createConnection();
    expect(first.statusCode).toBe(201);
    const id = first.json().id;

    const dup = await createConnection();
    expect(dup.statusCode).toBe(409);
    expect(dup.json().code).toBe('AI_CONNECTION_EXISTS');

    // Delete scrubs the key material but keeps the row occupying the tuple.
    const del = await app.inject({
      method: 'DELETE',
      url: `/api/v1/ai/connections/${id}`,
      headers: owner.headers,
    });
    expect(del.statusCode).toBe(204);
    const tombstone = tables.ai_connections.find((row) => row.id === id);
    expect(tombstone.deleted_at).not.toBeNull();
    expect(tombstone.encrypted_key).toBeNull();
    expect(tombstone.key_last4).toBeNull();

    // Re-add revives the SAME row with fresh material.
    const again = await createConnection(createBody({ apiKey: 'sk-new-key-after-delete' }));
    expect(again.statusCode).toBe(201);
    expect(again.json().id).toBe(id);
    expect(again.json().keyLast4).toBe('lete');
    expect(tables.ai_connections.filter((row) => row.provider === 'anthropic')).toHaveLength(1);
  });

  it('lists only the caller’s own rows', async () => {
    await createConnection();
    const mate = await registerUser(app, { email: 'ai-mate@example.com' });
    addMember(tables, { workspaceId: owner.workspace.id, user: mate.user });
    const res = await app.inject({
      method: 'GET',
      url: `/api/v1/workspaces/${owner.workspace.id}/ai/connections`,
      headers: mate.headers,
    });
    expect(res.statusCode).toBe(200);
    expect(res.json().items).toHaveLength(0);
  });

  it('hides a co-member’s row as 404 and an outsider’s workspace as 403', async () => {
    const created = await createConnection();
    const id = created.json().id;

    const mate = await registerUser(app, { email: 'ai-mate2@example.com' });
    addMember(tables, { workspaceId: owner.workspace.id, user: mate.user });
    const patch = await app.inject({
      method: 'PATCH',
      url: `/api/v1/ai/connections/${id}`,
      headers: mate.headers,
      payload: { defaultChatModel: 'x' },
    });
    expect(patch.statusCode).toBe(404);
    expect(patch.json().code).toBe('AI_CONNECTION_NOT_YOURS');

    const outsider = await registerUser(app, { email: 'ai-out@example.com' });
    const del = await app.inject({
      method: 'DELETE',
      url: `/api/v1/ai/connections/${id}`,
      headers: outsider.headers,
    });
    expect(del.statusCode).toBe(403);
  });

  it('rotates the key via PATCH and clears an error status', async () => {
    const created = await createConnection();
    const id = created.json().id;
    tables.ai_connections.find((row) => row.id === id).status = 'error';

    const res = await app.inject({
      method: 'PATCH',
      url: `/api/v1/ai/connections/${id}`,
      headers: owner.headers,
      payload: { apiKey: 'sk-rotated-key-9999' },
    });
    expect(res.statusCode).toBe(200);
    expect(res.json().keyLast4).toBe('9999');
    expect(res.json().status).toBe('active');
    const row = tables.ai_connections.find((r) => r.id === id);
    expect(decryptSecret(row.encrypted_key, app.config.ai.tokenKey)).toBe('sk-rotated-key-9999');
  });

  it('updates model defaults and refuses stripping ollama’s base URL', async () => {
    const ollama = await createConnection(
      createBody({ provider: 'ollama', apiKey: undefined, baseUrl: 'http://127.0.0.1:11434' }),
    );
    const id = ollama.json().id;

    const models = await app.inject({
      method: 'PATCH',
      url: `/api/v1/ai/connections/${id}`,
      headers: owner.headers,
      payload: { defaultChatModel: 'llama3.3', defaultFastModel: 'llama3.2' },
    });
    expect(models.statusCode).toBe(200);
    expect(models.json().defaultChatModel).toBe('llama3.3');

    const strip = await app.inject({
      method: 'PATCH',
      url: `/api/v1/ai/connections/${id}`,
      headers: owner.headers,
      payload: { baseUrl: null },
    });
    expect(strip.statusCode).toBe(400);
    expect(strip.json().code).toBe('AI_BASE_URL_REQUIRED');
  });

  it('reports status: configured flag, providers, instance providers', async () => {
    const empty = await app.inject({
      method: 'GET',
      url: `/api/v1/workspaces/${owner.workspace.id}/ai/status`,
      headers: owner.headers,
    });
    expect(empty.statusCode).toBe(200);
    expect(empty.json()).toEqual({ configured: false, providers: [], instanceProviders: [] });

    await createConnection();
    const after = await app.inject({
      method: 'GET',
      url: `/api/v1/workspaces/${owner.workspace.id}/ai/status`,
      headers: owner.headers,
    });
    expect(after.json().configured).toBe(true);
    expect(after.json().providers).toEqual(['anthropic']);
  });

  it('AI_ENABLED=false answers 404 on every /ai/* route', async () => {
    const config = loadConfig({
      NODE_ENV: 'test',
      RATE_LIMIT_AUTH_MAX: '1000',
      AI_ENABLED: 'false',
    });
    const { app: offApp } = await buildTestApp({ config });
    const user = await registerUser(offApp, { email: 'ai-off@example.com' });
    const ws = user.workspace.id;
    const calls = [
      { method: 'GET', url: `/api/v1/workspaces/${ws}/ai/status` },
      { method: 'GET', url: `/api/v1/workspaces/${ws}/ai/connections` },
      { method: 'POST', url: `/api/v1/workspaces/${ws}/ai/connections`, payload: createBody() },
      {
        method: 'PATCH',
        url: `/api/v1/ai/connections/${'0'.repeat(26)}`,
        payload: { apiKey: KEY },
      },
      { method: 'DELETE', url: `/api/v1/ai/connections/${'0'.repeat(26)}` },
    ];
    for (const call of calls) {
      const res = await offApp.inject({ ...call, headers: user.headers });
      expect(res.statusCode).toBe(404);
      expect(res.json().code ?? 'FST_ERR_NOT_FOUND').not.toBe('AI_CONNECTION_NOT_FOUND');
    }
  });
});
