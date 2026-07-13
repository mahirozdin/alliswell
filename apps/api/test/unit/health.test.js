import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config.js';

const testConfig = loadConfig({ NODE_ENV: 'test' });

function fakeDb({ fail = false } = {}) {
  return {
    raw: async () => {
      if (fail) throw new Error('mysql is down');
      return [[{ 1: 1 }]];
    },
  };
}

function fakeRedis({ fail = false } = {}) {
  return {
    ping: async () => {
      if (fail) throw new Error('redis is down');
      return 'PONG';
    },
  };
}

describe('health endpoints (all dependencies up)', () => {
  let app;

  beforeAll(async () => {
    app = await buildApp({ config: testConfig, db: fakeDb(), redis: fakeRedis() });
  });

  afterAll(async () => {
    await app.close();
  });

  it('GET / returns the API identity', async () => {
    const res = await app.inject({ method: 'GET', url: '/' });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ name: 'AllisWell API', health: '/health/ready' });
  });

  it('GET /health/live reports ok', async () => {
    const res = await app.inject({ method: 'GET', url: '/health/live' });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.status).toBe('ok');
    expect(body.version).toBeDefined();
  });

  it('GET /health/ready reports every component up', async () => {
    const res = await app.inject({ method: 'GET', url: '/health/ready' });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.status).toBe('ok');
    expect(body.checks.mysql.status).toBe('up');
    expect(body.checks.redis.status).toBe('up');
  });

  it('assigns a request id and echoes x-request-id', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/health/live',
      headers: { 'x-request-id': 'test-req-1' },
    });
    expect(res.statusCode).toBe(200);
  });
});

describe('health degradation', () => {
  it('reports 503 with mysql down', async () => {
    const app = await buildApp({
      config: testConfig,
      db: fakeDb({ fail: true }),
      redis: fakeRedis(),
    });
    const res = await app.inject({ method: 'GET', url: '/health/ready' });
    expect(res.statusCode).toBe(503);
    const body = res.json();
    expect(body.status).toBe('degraded');
    expect(body.checks.mysql.status).toBe('down');
    expect(body.checks.mysql.error).toMatch(/mysql is down/);
    expect(body.checks.redis.status).toBe('up');
    await app.close();
  });

  it('reports 503 with redis down', async () => {
    const app = await buildApp({
      config: testConfig,
      db: fakeDb(),
      redis: fakeRedis({ fail: true }),
    });
    const res = await app.inject({ method: 'GET', url: '/health/ready' });
    expect(res.statusCode).toBe(503);
    const body = res.json();
    expect(body.status).toBe('degraded');
    expect(body.checks.mysql.status).toBe('up');
    expect(body.checks.redis.status).toBe('down');
    await app.close();
  });
});
