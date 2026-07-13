import { describe, it, expect } from 'vitest';
import { loadConfig } from '../../src/config.js';

describe('loadConfig', () => {
  it('applies defaults for an empty environment', () => {
    const config = loadConfig({});
    expect(config.env).toBe('development');
    expect(config.port).toBe(3000);
    expect(config.database).toMatchObject({
      host: '127.0.0.1',
      port: 3306,
      name: 'alliswell',
    });
    expect(config.redisUrl).toBe('redis://127.0.0.1:6379');
    expect(config.corsOrigin).toBe(true);
    expect(config.rateLimitMax).toBe(300);
  });

  it('parses overrides', () => {
    const config = loadConfig({
      NODE_ENV: 'production',
      PORT: '8080',
      DATABASE_PORT: '3307',
      CORS_ORIGIN: 'https://a.example, https://b.example',
      RATE_LIMIT_MAX: '50',
    });
    expect(config.env).toBe('production');
    expect(config.port).toBe(8080);
    expect(config.database.port).toBe(3307);
    expect(config.corsOrigin).toEqual(['https://a.example', 'https://b.example']);
    expect(config.rateLimitMax).toBe(50);
  });

  it('treats "*" CORS origin as allow-all', () => {
    expect(loadConfig({ CORS_ORIGIN: '*' }).corsOrigin).toBe(true);
  });

  it('rejects non-numeric numbers', () => {
    expect(() => loadConfig({ PORT: 'abc' })).toThrow(/PORT/);
    expect(() => loadConfig({ DATABASE_PORT: '33o6' })).toThrow(/DATABASE_PORT/);
  });

  it('rejects out-of-range ports', () => {
    expect(() => loadConfig({ PORT: '0' })).toThrow(/out of range/);
    expect(() => loadConfig({ PORT: '70000' })).toThrow(/out of range/);
  });

  it('returns a frozen config', () => {
    const config = loadConfig({});
    expect(Object.isFrozen(config)).toBe(true);
    expect(Object.isFrozen(config.database)).toBe(true);
  });
});
