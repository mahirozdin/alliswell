import { describe, it, expect } from 'vitest';
import { loadConfig } from '../../src/config.js';

const strongSecrets = {
  JWT_ACCESS_SECRET: 'a'.repeat(32) + '-access-strong-random-secret',
  JWT_REFRESH_SECRET: 'b'.repeat(32) + '-refresh-strong-random-secret',
};

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
      ...strongSecrets,
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
    expect(Object.isFrozen(config.auth)).toBe(true);
  });
});

describe('loadConfig auth secrets (OPH-020)', () => {
  it('falls back to labeled insecure secrets outside production', () => {
    const config = loadConfig({});
    expect(config.auth.accessSecret).toMatch(/insecure-dev/);
    expect(config.auth.refreshSecret).toMatch(/insecure-dev/);
    expect(config.auth.accessTtlSec).toBe(900);
    expect(config.auth.refreshTtlDays).toBe(30);
  });

  it('accepts strong distinct secrets in production', () => {
    const config = loadConfig({ NODE_ENV: 'production', ...strongSecrets });
    expect(config.auth.accessSecret).toBe(strongSecrets.JWT_ACCESS_SECRET);
    expect(config.auth.refreshSecret).toBe(strongSecrets.JWT_REFRESH_SECRET);
  });

  it('refuses to boot production without secrets', () => {
    expect(() => loadConfig({ NODE_ENV: 'production' })).toThrow(/JWT_ACCESS_SECRET/);
    expect(() =>
      loadConfig({ NODE_ENV: 'production', JWT_ACCESS_SECRET: strongSecrets.JWT_ACCESS_SECRET }),
    ).toThrow(/JWT_REFRESH_SECRET/);
  });

  it('refuses the .env.example placeholders in production', () => {
    expect(() =>
      loadConfig({
        NODE_ENV: 'production',
        JWT_ACCESS_SECRET: 'change-me-generate-a-random-secret',
        JWT_REFRESH_SECRET: strongSecrets.JWT_REFRESH_SECRET,
      }),
    ).toThrow(/JWT_ACCESS_SECRET/);
  });

  it('refuses short or identical secrets in production', () => {
    expect(() =>
      loadConfig({
        NODE_ENV: 'production',
        JWT_ACCESS_SECRET: 'too-short',
        JWT_REFRESH_SECRET: strongSecrets.JWT_REFRESH_SECRET,
      }),
    ).toThrow(/too short/);
    expect(() =>
      loadConfig({
        NODE_ENV: 'production',
        JWT_ACCESS_SECRET: strongSecrets.JWT_ACCESS_SECRET,
        JWT_REFRESH_SECRET: strongSecrets.JWT_ACCESS_SECRET,
      }),
    ).toThrow(/must be different/);
  });

  it('parses token lifetime overrides and rejects nonsense', () => {
    const config = loadConfig({ AUTH_ACCESS_TTL_SEC: '600', AUTH_REFRESH_TTL_DAYS: '7' });
    expect(config.auth.accessTtlSec).toBe(600);
    expect(config.auth.refreshTtlDays).toBe(7);
    expect(() => loadConfig({ AUTH_ACCESS_TTL_SEC: '0' })).toThrow(/positive/);
  });
});
