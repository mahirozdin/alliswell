import { describe, it, expect, beforeAll, afterAll, beforeEach } from 'vitest';
import { buildTestApp, registerUser } from '../helpers/authed.js';
import { startFakeAi } from '../helpers/fakeai.js';
import { MODEL_CATALOG } from '../../src/lib/ai/models.js';

/**
 * OPH-216 — GET /ai/models (catalog vs live) and the honest connection test.
 * Per-connection base_url points every upstream call at the in-process fake.
 */

let fake;
let app;
let tables;
let owner;

beforeAll(async () => {
  fake = await startFakeAi();
});
afterAll(async () => {
  await fake.app.close();
});

beforeEach(async () => {
  fake.reset();
  ({ app, tables } = await buildTestApp());
  owner = await registerUser(app, { email: 'ai-models@example.com' });
});

async function connect(provider, extra = {}) {
  const res = await app.inject({
    method: 'POST',
    url: `/api/v1/workspaces/${owner.workspace.id}/ai/connections`,
    headers: owner.headers,
    payload: { provider, apiKey: 'sk-model-test-123', consentAcknowledged: true, ...extra },
  });
  expect(res.statusCode).toBe(201);
  return res.json();
}

describe('GET /ai/models (OPH-216)', () => {
  it('serves the static catalog with factory defaults for a cloud provider', async () => {
    await connect('anthropic', { baseUrl: `${fake.url}/anthropic` });
    const res = await app.inject({
      method: 'GET',
      url: `/api/v1/workspaces/${owner.workspace.id}/ai/models`,
      headers: owner.headers,
    });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.provider).toBe('anthropic');
    expect(body.source).toBe('catalog');
    expect(body.models.chat).toEqual(MODEL_CATALOG.anthropic.chat);
    expect(body.defaults).toEqual(MODEL_CATALOG.anthropic.defaults);
  });

  it('prefers the connection’s own default models over the catalog', async () => {
    const conn = await connect('openai', {
      baseUrl: `${fake.url}/openai`,
      defaultChatModel: 'gpt-5',
    });
    const res = await app.inject({
      method: 'GET',
      url: `/api/v1/workspaces/${owner.workspace.id}/ai/models?connectionId=${conn.id}`,
      headers: owner.headers,
    });
    expect(res.json().defaults.chat).toBe('gpt-5');
    expect(res.json().defaults.fast).toBe(MODEL_CATALOG.openai.defaults.fast);
  });

  it('lists Ollama models LIVE from the instance’s tags', async () => {
    await connect('ollama', { apiKey: undefined, baseUrl: `${fake.url}/ollama` });
    const res = await app.inject({
      method: 'GET',
      url: `/api/v1/workspaces/${owner.workspace.id}/ai/models`,
      headers: owner.headers,
    });
    const body = res.json();
    expect(body.source).toBe('live');
    expect(body.models.chat.map((m) => m.id)).toEqual(['llama3.3:latest', 'llama3.2:1b']);
    expect(body.defaults.chat).toBe('llama3.3:latest');
  });

  it('answers 503 AI_NOT_CONFIGURED with no connection at all', async () => {
    const res = await app.inject({
      method: 'GET',
      url: `/api/v1/workspaces/${owner.workspace.id}/ai/models`,
      headers: owner.headers,
    });
    expect(res.statusCode).toBe(503);
    expect(res.json().code).toBe('AI_NOT_CONFIGURED');
  });

  it('maps an unreachable Ollama onto AI_UPSTREAM_ERROR (502)', async () => {
    await connect('ollama', { apiKey: undefined, baseUrl: 'http://127.0.0.1:1' });
    const res = await app.inject({
      method: 'GET',
      url: `/api/v1/workspaces/${owner.workspace.id}/ai/models`,
      headers: owner.headers,
    });
    expect(res.statusCode).toBe(502);
    expect(res.json().code).toBe('AI_UPSTREAM_ERROR');
  });
});

describe('POST /ai/connections/:id/test (OPH-216)', () => {
  it('answers ok:true with a latency for a healthy connection', async () => {
    const conn = await connect('anthropic', { baseUrl: `${fake.url}/anthropic` });
    const res = await app.inject({
      method: 'POST',
      url: `/api/v1/ai/connections/${conn.id}/test`,
      headers: owner.headers,
    });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.ok).toBe(true);
    expect(body.latencyMs).toBeGreaterThanOrEqual(0);
  });

  it('a bad key is a SUCCESSFUL test: ok:false + code, and the row flips to error', async () => {
    const conn = await connect('openai', { baseUrl: `${fake.url}/openai` });
    fake.state.failNext = { status: 401, times: 1 };
    const res = await app.inject({
      method: 'POST',
      url: `/api/v1/ai/connections/${conn.id}/test`,
      headers: owner.headers,
    });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ ok: false, code: 'AI_UPSTREAM_AUTH_FAILED' });
    expect(tables.ai_connections.find((r) => r.id === conn.id).status).toBe('error');
  });

  it('a co-member cannot test somebody else’s connection (404)', async () => {
    const conn = await connect('gemini', { baseUrl: `${fake.url}/gemini` });
    const outsider = await registerUser(app, { email: 'ai-models-out@example.com' });
    const res = await app.inject({
      method: 'POST',
      url: `/api/v1/ai/connections/${conn.id}/test`,
      headers: outsider.headers,
    });
    // Outsider is not even a member → the membership gate answers first.
    expect(res.statusCode).toBe(403);
  });
});

describe('usage accounting pipe (OPH-216)', () => {
  it('recordUsage lands a content-free row in ai_usage_events', async () => {
    await app.ai.recordUsage({
      workspaceId: owner.workspace.id,
      userId: owner.user.id,
      connectionId: null,
      provider: 'anthropic',
      kind: 'chat',
      model: 'claude-sonnet-5',
      inputTokens: 812,
      outputTokens: 257,
      durationMs: 1234,
      requestId: '0'.repeat(26),
    });
    expect(tables.ai_usage_events).toHaveLength(1);
    const row = tables.ai_usage_events[0];
    expect(row).toMatchObject({
      provider: 'anthropic',
      kind: 'chat',
      model: 'claude-sonnet-5',
      input_tokens: 812,
      output_tokens: 257,
      duration_ms: 1234,
    });
    // Accounting, never content: the row has no prompt/text-bearing column.
    expect(Object.keys(row).join(',')).not.toMatch(/prompt|content|text|message/);
  });

  it('a failing usage insert never throws into the request path', async () => {
    tables.ai_usage_events = null; // sabotage: fakeDb will throw on insert
    await expect(
      app.ai.recordUsage({
        workspaceId: owner.workspace.id,
        userId: owner.user.id,
        provider: 'openai',
        kind: 'extract',
        model: 'gpt-5-mini',
      }),
    ).resolves.toBeUndefined();
  });
});
