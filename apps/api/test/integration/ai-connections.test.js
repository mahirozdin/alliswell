import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { loadConfig } from '../../src/config.js';
import { buildApp } from '../../src/app.js';
import { newId } from '../../src/lib/ids.js';
import { decryptSecret } from '../../src/lib/crypto.js';

/**
 * OPH-215 — AI connections over real MySQL: the properties the fake db cannot
 * prove. The ciphertext round-trip through a real TEXT column, the ENUM
 * accepting exactly the five providers, and the real unique index both
 * refusing duplicates (ER_DUP_ENTRY) and staying occupied by a soft-deleted
 * row so the revival path is the only way back in.
 */
const enabled = process.env.INTEGRATION === '1';

describe.runIf(enabled)('AI connections integration (OPH-215)', () => {
  let app;
  let ws;
  let headers;
  let userId;
  const emailPrefix = `ai-conn-int-${Date.now()}`;
  const KEY = 'sk-int-test-key-123456';

  beforeAll(async () => {
    const config = loadConfig({ ...process.env, NODE_ENV: 'test' });
    app = await buildApp({ config });
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      payload: { email: `${emailPrefix}-owner@example.com`, password: 'sifre-12345' },
    });
    expect(res.statusCode).toBe(201);
    const body = res.json();
    ws = body.workspace.id;
    userId = body.user.id;
    headers = { authorization: `Bearer ${body.tokens.accessToken}` };
  });

  afterAll(async () => {
    if (!app) return;
    const users = await app.db('users').where('email', 'like', `${emailPrefix}%`).select('id');
    const ids = users.map((u) => u.id);
    if (ids.length > 0) {
      await app.db('workspaces').whereIn('owner_id', ids).delete();
      await app.db('workspace_members').whereIn('user_id', ids).delete();
      await app.db('users').whereIn('id', ids).delete();
    }
    await app.close();
  });

  it('stores ciphertext that decrypts back to the submitted key', async () => {
    const res = await app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${ws}/ai/connections`,
      headers,
      payload: { provider: 'anthropic', apiKey: KEY, consentAcknowledged: true },
    });
    expect(res.statusCode).toBe(201);
    expect(res.body).not.toContain(KEY);

    const row = await app.db('ai_connections').where({ id: res.json().id }).first();
    expect(row.encrypted_key).toMatch(/^v1:/);
    expect(row.encrypted_key).not.toContain(KEY);
    expect(decryptSecret(row.encrypted_key, app.config.ai.tokenKey)).toBe(KEY);
    expect(row.key_last4).toBe(KEY.slice(-4));
  });

  it('accepts every provider ENUM value', async () => {
    // anthropic exists from the previous test; the other four here.
    for (const provider of ['openai', 'gemini', 'openrouter']) {
      const res = await app.inject({
        method: 'POST',
        url: `/api/v1/workspaces/${ws}/ai/connections`,
        headers,
        payload: { provider, apiKey: `${KEY}-${provider}`, consentAcknowledged: true },
      });
      expect(res.statusCode).toBe(201);
    }
    const ollama = await app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${ws}/ai/connections`,
      headers,
      payload: { provider: 'ollama', baseUrl: 'http://127.0.0.1:11434', consentAcknowledged: true },
    });
    expect(ollama.statusCode).toBe(201);

    const rows = await app.db('ai_connections').where({ workspace_id: ws }).select();
    expect(rows.map((r) => r.provider).sort()).toEqual([
      'anthropic',
      'gemini',
      'ollama',
      'openai',
      'openrouter',
    ]);
  });

  it('raw duplicate insert trips the real unique index', async () => {
    await expect(
      app.db('ai_connections').insert({
        id: newId(),
        workspace_id: ws,
        user_id: userId,
        provider: 'anthropic',
        auth_mode: 'api_key',
      }),
    ).rejects.toMatchObject({ code: 'ER_DUP_ENTRY' });
  });

  it('soft delete keeps the tuple occupied; re-add revives the same row', async () => {
    const list = await app.inject({
      method: 'GET',
      url: `/api/v1/workspaces/${ws}/ai/connections`,
      headers,
    });
    const anthropic = list.json().items.find((c) => c.provider === 'anthropic');

    const del = await app.inject({
      method: 'DELETE',
      url: `/api/v1/ai/connections/${anthropic.id}`,
      headers,
    });
    expect(del.statusCode).toBe(204);
    const tombstone = await app.db('ai_connections').where({ id: anthropic.id }).first();
    expect(tombstone.deleted_at).not.toBeNull();
    expect(tombstone.encrypted_key).toBeNull();

    const again = await app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${ws}/ai/connections`,
      headers,
      payload: { provider: 'anthropic', apiKey: 'sk-revived-key-0001', consentAcknowledged: true },
    });
    expect(again.statusCode).toBe(201);
    expect(again.json().id).toBe(anthropic.id);
    expect(again.json().keyLast4).toBe('0001');

    const rows = await app
      .db('ai_connections')
      .where({ workspace_id: ws, provider: 'anthropic' })
      .select();
    expect(rows).toHaveLength(1);
    expect(rows[0].deleted_at).toBeNull();
  });
});
