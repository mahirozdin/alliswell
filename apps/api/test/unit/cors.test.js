import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config.js';
import { fakeDb, fakeRedis } from '../helpers/fakedb.js';

let app;

beforeAll(async () => {
  app = await buildApp({
    config: loadConfig({ NODE_ENV: 'test' }),
    db: fakeDb().db,
    redis: fakeRedis(),
  });
});

afterAll(async () => {
  await app.close();
});

describe('CORS preflight (feedback round 3)', () => {
  // The web app PATCHes tasks/notes/projects from another origin — the
  // preflight must allow every verb the API actually uses.
  it.each(['PATCH', 'PUT', 'DELETE'])('allows %s in preflight', async (method) => {
    const res = await app.inject({
      method: 'OPTIONS',
      url: '/api/v1/tasks/01AAAAAAAAAAAAAAAAAAAAAAAA',
      headers: {
        origin: 'http://localhost:8080',
        'access-control-request-method': method,
      },
    });
    expect(res.statusCode).toBe(204);
    expect(res.headers['access-control-allow-methods']).toContain(method);
    expect(res.headers['access-control-allow-origin']).toBe('http://localhost:8080');
  });
});
