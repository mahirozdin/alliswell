import { describe, it, expect } from 'vitest';
import { loadConfig } from '../../src/config.js';

const strongSecrets = {
  JWT_ACCESS_SECRET: 'a'.repeat(32) + '-access-strong-random-secret',
  JWT_REFRESH_SECRET: 'b'.repeat(32) + '-refresh-strong-random-secret',
  // AI is enabled by default (OPH-215), so a minimal production env includes
  // a real AI_TOKEN_KEY — the deliberate upgrade speed bump ADR-0019 records.
  AI_TOKEN_KEY: 'a1b2c3d4'.repeat(8),
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
    expect(config.rateLimitAuthMax).toBe(10);
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

  // Behind a proxy every request reads as 127.0.0.1 unless this is on, which
  // would collapse the per-IP rate limits into one shared bucket.
  it('parses TRUST_PROXY, defaulting to off', () => {
    expect(loadConfig({}).trustProxy).toBe(false);
    expect(loadConfig({ TRUST_PROXY: 'false' }).trustProxy).toBe(false);
    expect(loadConfig({ TRUST_PROXY: '0' }).trustProxy).toBe(false);
    expect(loadConfig({ TRUST_PROXY: 'true' }).trustProxy).toBe(true);
    expect(loadConfig({ TRUST_PROXY: '1' }).trustProxy).toBe(1); // hop count
    expect(loadConfig({ TRUST_PROXY: '127.0.0.1' }).trustProxy).toBe('127.0.0.1');
    expect(loadConfig({ TRUST_PROXY: '127.0.0.1,10.0.0.0/8' }).trustProxy).toBe(
      '127.0.0.1,10.0.0.0/8',
    );
  });

  // The collation is interpolated into CREATE TABLE text (src/db/collation.js).
  it('validates DATABASE_COLLATION as a bare identifier', () => {
    expect(loadConfig({}).database.collation).toBeNull();
    expect(loadConfig({ DATABASE_COLLATION: 'utf8mb4_unicode_ci' }).database.collation).toBe(
      'utf8mb4_unicode_ci',
    );
    expect(() => loadConfig({ DATABASE_COLLATION: 'utf8mb4; DROP TABLE users' })).toThrow(
      /DATABASE_COLLATION/,
    );
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

describe('loadConfig AI (OPH-215)', () => {
  it('is enabled by default with the labeled dev key', () => {
    const config = loadConfig({});
    expect(config.ai.enabled).toBe(true);
    expect(config.ai.tokenKey).toMatch(/^(feed)+$/);
    expect(config.ai.heartbeatMs).toBe(15000);
    expect(config.ai.ratePerMinute).toBe(10);
    expect(config.ai.dailyTokenCap).toBe(200000);
    expect(Object.isFrozen(config.ai)).toBe(true);
    expect(Object.isFrozen(config.ai.baseUrls)).toBe(true);
  });

  it('parses the kill switch and instance keys', () => {
    const off = loadConfig({ AI_ENABLED: 'false' });
    expect(off.ai.enabled).toBe(false);
    const config = loadConfig({ AI_OPENAI_API_KEY: 'sk-test-1234' });
    expect(config.ai.instanceKeys.openai).toBe('sk-test-1234');
    expect(config.ai.instanceKeys.anthropic).toBeNull();
  });

  it('rejects a non-hex AI_TOKEN_KEY in every environment', () => {
    expect(() => loadConfig({ AI_TOKEN_KEY: 'not-hex' })).toThrow(/AI_TOKEN_KEY/);
    expect(() => loadConfig({ AI_TOKEN_KEY: 'ff'.repeat(16) })).toThrow(/AI_TOKEN_KEY/);
  });

  const withoutAiKey = { ...strongSecrets };
  delete withoutAiKey.AI_TOKEN_KEY;

  it('refuses production without a real AI_TOKEN_KEY while AI is enabled', () => {
    expect(() => loadConfig({ NODE_ENV: 'production', ...withoutAiKey })).toThrow(/AI_TOKEN_KEY/);
    // The patterned dev placeholder is refused by name.
    expect(() =>
      loadConfig({ NODE_ENV: 'production', ...withoutAiKey, AI_TOKEN_KEY: 'feed'.repeat(16) }),
    ).toThrow(/AI_TOKEN_KEY/);
  });

  it('boots production without the key when AI_ENABLED=false', () => {
    const config = loadConfig({ NODE_ENV: 'production', AI_ENABLED: 'false', ...withoutAiKey });
    expect(config.ai.enabled).toBe(false);
  });

  it('bounds the stream tunables and base URLs', () => {
    expect(() => loadConfig({ AI_HEARTBEAT_MS: '100' })).toThrow(/AI_HEARTBEAT_MS/);
    expect(() => loadConfig({ AI_HEARTBEAT_MS: '90000' })).toThrow(/AI_HEARTBEAT_MS/);
    expect(() => loadConfig({ AI_RATE_PER_MINUTE: '0' })).toThrow(/AI_RATE_PER_MINUTE/);
    expect(() => loadConfig({ AI_DAILY_TOKEN_CAP: '-1' })).toThrow(/AI_DAILY_TOKEN_CAP/);
    expect(() => loadConfig({ AI_OLLAMA_BASE_URL: 'ftp://nope' })).toThrow(/base URL/);
    expect(loadConfig({ AI_OLLAMA_BASE_URL: 'http://127.0.0.1:11434' }).ai.baseUrls.ollama).toBe(
      'http://127.0.0.1:11434',
    );
  });
});
