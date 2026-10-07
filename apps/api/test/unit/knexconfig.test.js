import { describe, it, expect } from 'vitest';

import { loadConfig } from '../../src/config.js';
import { buildKnexConfig, pinSessionToUtc } from '../../src/db/knexconfig.js';

describe('knex config keeps the database clock in UTC', () => {
  it('pins every pooled connection to UTC before handing it out', () => {
    const cfg = buildKnexConfig(loadConfig({ NODE_ENV: 'test' }));
    expect(cfg.connection.timezone).toBe('Z');
    expect(cfg.pool.afterCreate).toBe(pinSessionToUtc);
  });

  it('runs the SET on the connection and passes it on', () => {
    const sent = [];
    const conn = { query: (sql, cb) => (sent.push(sql), cb(null)) };
    let handed;
    pinSessionToUtc(conn, (err, c) => (handed = { err, c }));
    expect(sent).toEqual(["SET time_zone = '+00:00'"]);
    expect(handed).toEqual({ err: null, c: conn });
  });

  it('a connection that refuses the SET is not handed out as if it worked', () => {
    const boom = new Error('no');
    const conn = { query: (_sql, cb) => cb(boom) };
    let handed;
    pinSessionToUtc(conn, (err) => (handed = err));
    expect(handed).toBe(boom);
  });
});
