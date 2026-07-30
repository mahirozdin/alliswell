import { describe, it, expect, beforeAll, afterAll, vi } from 'vitest';
import { loadConfig } from '../../src/config.js';
import { buildApp } from '../../src/app.js';
import { newId } from '../../src/lib/ids.js';
import { startFakeAi } from '../helpers/fakeai.js';
import { parseSseStream } from '../../src/lib/ai/sse.js';

/**
 * OPH-217 over real Redis + MySQL: the two properties that ARE the PM2 story —
 * the token bucket is shared across API instances, and a cancel posted to
 * instance B aborts a stream held by instance A. Plus the usage row in a real
 * table. Upstream is the in-process fakeai.
 */
const enabled = process.env.INTEGRATION === '1';

describe.runIf(enabled)('AI chat integration (OPH-217)', () => {
  let fake;
  let appA;
  let appB;
  let baseA;
  let ws;
  let headers;
  const emailPrefix = `ai-chat-int-${Date.now()}`;

  beforeAll(async () => {
    fake = await startFakeAi();
    const env = {
      ...process.env,
      NODE_ENV: 'test',
      AI_RATE_BURST: '3',
      AI_RATE_PER_MINUTE: '1',
      // Its own prefix per run: bucket keys must not collide across runs.
      REDIS_KEY_PREFIX: `aw-ai-int-${Date.now()}`,
    };
    appA = await buildApp({ config: loadConfig(env) });
    appB = await buildApp({ config: loadConfig(env) });
    await appA.listen({ port: 0, host: '127.0.0.1' });
    baseA = `http://127.0.0.1:${appA.server.address().port}`;

    const res = await appA.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      payload: { email: `${emailPrefix}-owner@example.com`, password: 'sifre-12345' },
    });
    const body = res.json();
    ws = body.workspace.id;
    headers = { authorization: `Bearer ${body.tokens.accessToken}` };
    await appA.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${ws}/ai/connections`,
      headers,
      payload: {
        provider: 'anthropic',
        apiKey: 'sk-int-chat-123',
        baseUrl: `${fake.url}/anthropic`,
        consentAcknowledged: true,
      },
    });
  });

  afterAll(async () => {
    if (appA) {
      const users = await appA.db('users').where('email', 'like', `${emailPrefix}%`).select('id');
      const ids = users.map((u) => u.id);
      if (ids.length > 0) {
        await appA.db('workspaces').whereIn('owner_id', ids).delete();
        await appA.db('workspace_members').whereIn('user_id', ids).delete();
        await appA.db('users').whereIn('id', ids).delete();
      }
      await appA.close();
    }
    if (appB) await appB.close();
    if (fake) await fake.app.close();
  });

  it('streams end-to-end and lands the usage row in real MySQL', async () => {
    const requestId = newId();
    const res = await fetch(`${baseA}/api/v1/workspaces/${ws}/ai/chat`, {
      method: 'POST',
      headers: { ...headers, 'content-type': 'application/json' },
      body: JSON.stringify({ requestId, messages: [{ role: 'user', content: 'merhaba' }] }),
    });
    expect(res.status).toBe(200);
    const names = [];
    for await (const event of parseSseStream(res.body)) names.push(event.event);
    expect(names).toEqual(['start', 'text', 'text', 'usage', 'done']);

    await vi.waitFor(async () => {
      const row = await appA.db('ai_usage_events').where({ request_id: requestId }).first();
      expect(row).toMatchObject({ kind: 'chat', input_tokens: 12, output_tokens: 34 });
    });
  });

  it('shares the token bucket across instances (burst 3, one already spent)', async () => {
    // Spend the remaining burst through instance B's counter view.
    const call = (app) =>
      app.inject({
        method: 'POST',
        url: `/api/v1/workspaces/${ws}/ai/chat`,
        headers,
        payload: {
          requestId: newId(),
          messages: [{ role: 'user', content: 'x' }],
          transport: 'socket',
        },
      });
    const second = await call(appB); // burst token 2
    expect([200, 503]).toContain(second.statusCode);
    const third = await call(appA); // burst token 3
    expect([200, 503]).toContain(third.statusCode);
    const fourth = await call(appB); // bucket dry — wherever it lands
    expect(fourth.statusCode).toBe(429);
    expect(fourth.json().code).toBe('AI_RATE_LIMITED');
  });

  it('a cancel POSTed to instance B aborts a stream held by instance A', async () => {
    // A fresh user so the drained bucket above doesn't 429 this scenario.
    const reg = await appA.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      payload: { email: `${emailPrefix}-cancel@example.com`, password: 'sifre-12345' },
    });
    const user2 = reg.json();
    const ws2 = user2.workspace.id;
    const headers2 = { authorization: `Bearer ${user2.tokens.accessToken}` };
    await appA.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${ws2}/ai/connections`,
      headers: headers2,
      payload: {
        provider: 'anthropic',
        apiKey: 'sk-int-cancel-123',
        baseUrl: `${fake.url}/anthropic`,
        consentAcknowledged: true,
      },
    });

    fake.state.stall = true;
    const requestId = newId();
    const res = await fetch(`${baseA}/api/v1/workspaces/${ws2}/ai/chat`, {
      method: 'POST',
      headers: { ...headers2, 'content-type': 'application/json' },
      body: JSON.stringify({ requestId, messages: [{ role: 'user', content: 'uzun iş' }] }),
    });
    const reader = parseSseStream(res.body)[Symbol.asyncIterator]();
    expect((await reader.next()).value.event).toBe('start');

    // The cancel lands on the OTHER instance; Redis pub/sub carries it home.
    const cancel = await appB.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${ws2}/ai/chat/${requestId}/cancel`,
      headers: headers2,
    });
    expect(cancel.statusCode).toBe(204);

    const rest = [];
    for (let step = await reader.next(); !step.done; step = await reader.next()) {
      rest.push({ name: step.value.event, data: JSON.parse(step.value.data) });
    }
    expect(rest.at(-1)).toMatchObject({ name: 'done', data: { cancelled: true } });
    await vi.waitFor(() => expect(fake.state.aborted).toBeGreaterThan(0));
  });
});
