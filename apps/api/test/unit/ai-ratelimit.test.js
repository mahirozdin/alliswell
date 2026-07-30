import { describe, it, expect } from 'vitest';
import { createRateLimiter, createDailyCap } from '../../src/lib/ai/ratelimit.js';
import { loadConfig } from '../../src/config.js';
import { buildTestApp, registerUser } from '../helpers/authed.js';

/**
 * OPH-217 — the memory bucket's math with an injected clock, and the
 * pre-hijack 429 as a normal JSON error at the route.
 */

describe('createRateLimiter (memory path)', () => {
  function limiter({ ratePerMinute = 10, burst = 2 } = {}) {
    let at = 0;
    const l = createRateLimiter({
      redis: null,
      keyPrefix: 't',
      ratePerMinute,
      burst,
      now: () => at,
    });
    return { l, tick: (ms) => (at += ms) };
  }

  it('honors the burst, then refuses with a retry hint', async () => {
    const { l } = limiter();
    expect(await l.take('u1')).toEqual({ allowed: true });
    expect(await l.take('u1')).toEqual({ allowed: true });
    const third = await l.take('u1');
    expect(third.allowed).toBe(false);
    expect(third.retryAfterSec).toBeGreaterThanOrEqual(1);
  });

  it('refills at ratePerMinute — one token every 6 s at 10/min', async () => {
    const { l, tick } = limiter();
    await l.take('u1');
    await l.take('u1');
    expect((await l.take('u1')).allowed).toBe(false);
    tick(6000);
    expect((await l.take('u1')).allowed).toBe(true);
    expect((await l.take('u1')).allowed).toBe(false);
  });

  it('caps the refill at the burst and keeps users independent', async () => {
    const { l, tick } = limiter();
    tick(600000); // ten minutes idle refills to burst=2, not 100
    expect((await l.take('u1')).allowed).toBe(true);
    expect((await l.take('u1')).allowed).toBe(true);
    expect((await l.take('u1')).allowed).toBe(false);
    expect((await l.take('u2')).allowed).toBe(true); // separate bucket
  });
});

describe('createDailyCap (memory path)', () => {
  it('counts per UTC day and flips at the cap; 0 disables', async () => {
    let at = Date.UTC(2026, 6, 30, 10, 0, 0);
    const cap = createDailyCap({ redis: null, keyPrefix: 't', capTokens: 100, now: () => at });
    expect(await cap.isOver('u1')).toBe(false);
    await cap.add('u1', 60);
    expect(await cap.isOver('u1')).toBe(false);
    await cap.add('u1', 40);
    expect(await cap.isOver('u1')).toBe(true);
    at += 24 * 3600 * 1000; // next UTC day → fresh window
    expect(await cap.isOver('u1')).toBe(false);

    const off = createDailyCap({ redis: null, keyPrefix: 't', capTokens: 0, now: () => at });
    await off.add('u1', 999999);
    expect(await off.isOver('u1')).toBe(false);
  });
});

describe('the route-level 429 (pre-hijack JSON)', () => {
  it('answers AI_RATE_LIMITED with a Retry-After header', async () => {
    const config = loadConfig({
      NODE_ENV: 'test',
      RATE_LIMIT_AUTH_MAX: '1000',
      AI_RATE_BURST: '1',
      AI_RATE_PER_MINUTE: '1',
    });
    const { app } = await buildTestApp({ config });
    const owner = await registerUser(app, { email: 'ai-rl@example.com' });
    const payload = {
      requestId: '01AI0000000000000000000001',
      messages: [{ role: 'user', content: 'merhaba' }],
    };
    // First call consumes the single token, then honestly 503s (no connection).
    const first = await app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${owner.workspace.id}/ai/chat`,
      headers: owner.headers,
      payload,
    });
    expect(first.statusCode).toBe(503);
    expect(first.json().code).toBe('AI_NOT_CONFIGURED');

    const second = await app.inject({
      method: 'POST',
      url: `/api/v1/workspaces/${owner.workspace.id}/ai/chat`,
      headers: owner.headers,
      payload,
    });
    expect(second.statusCode).toBe(429);
    expect(second.json().code).toBe('AI_RATE_LIMITED');
    expect(Number(second.headers['retry-after'])).toBeGreaterThanOrEqual(1);
  });
});
