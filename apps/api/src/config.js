import path from 'node:path';
import { fileURLToPath } from 'node:url';
import dotenv from 'dotenv';

const apiDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const repoRoot = path.resolve(apiDir, '..', '..');

// Load .env files once at import time. The apps/api/.env (first) wins over the repo-root .env.
dotenv.config({ path: [path.join(apiDir, '.env'), path.join(repoRoot, '.env')], quiet: true });

function toInt(value, fallback, name) {
  if (value === undefined || value === null || value === '') return fallback;
  const parsed = Number.parseInt(value, 10);
  if (!Number.isInteger(parsed) || String(parsed) !== String(value).trim()) {
    throw new Error(`Invalid integer for ${name}: "${value}"`);
  }
  return parsed;
}

function parseCorsOrigin(value) {
  if (value === undefined || value === '' || value === '*') return true;
  return value.split(',').map((origin) => origin.trim());
}

// Development/test fallbacks so the app boots without a .env. Deliberately listed as
// insecure below — production refuses to start with any of these (or the .env.example
// placeholders). Generate real values with `openssl rand -hex 32`.
const DEV_ACCESS_SECRET = 'insecure-dev-access-secret-never-use-in-production';
const DEV_REFRESH_SECRET = 'insecure-dev-refresh-secret-never-use-in-production';
const INSECURE_SECRETS = new Set([
  DEV_ACCESS_SECRET,
  DEV_REFRESH_SECRET,
  'change-me-generate-a-random-secret',
  'change-me-generate-another-random-secret',
]);

function validateProductionSecret(name, value) {
  if (!value || INSECURE_SECRETS.has(value)) {
    throw new Error(
      `${name} must be set to a strong random value in production (openssl rand -hex 32)`,
    );
  }
  if (value.length < 32) {
    throw new Error(`${name} is too short for production: need at least 32 characters`);
  }
}

/**
 * Builds the application config from an environment map (defaults to process.env).
 * The only module allowed to read environment variables (AGENTS.md §4).
 *
 * @param {Record<string, string | undefined>} env
 */
export function loadConfig(env = process.env) {
  const config = {
    env: env.NODE_ENV ?? 'development',
    host: env.HOST ?? '0.0.0.0',
    port: toInt(env.PORT, 3000, 'PORT'),
    logLevel: env.LOG_LEVEL ?? 'info',
    corsOrigin: parseCorsOrigin(env.CORS_ORIGIN),
    rateLimitMax: toInt(env.RATE_LIMIT_MAX, 300, 'RATE_LIMIT_MAX'),
    database: Object.freeze({
      host: env.DATABASE_HOST ?? '127.0.0.1',
      port: toInt(env.DATABASE_PORT, 3306, 'DATABASE_PORT'),
      user: env.DATABASE_USER ?? 'alliswell',
      password: env.DATABASE_PASSWORD ?? 'alliswell_dev',
      name: env.DATABASE_NAME ?? 'alliswell',
    }),
    redisUrl: env.REDIS_URL ?? 'redis://127.0.0.1:6379',
    auth: Object.freeze({
      accessSecret: env.JWT_ACCESS_SECRET || DEV_ACCESS_SECRET,
      refreshSecret: env.JWT_REFRESH_SECRET || DEV_REFRESH_SECRET,
      accessTtlSec: toInt(env.AUTH_ACCESS_TTL_SEC, 900, 'AUTH_ACCESS_TTL_SEC'),
      refreshTtlDays: toInt(env.AUTH_REFRESH_TTL_DAYS, 30, 'AUTH_REFRESH_TTL_DAYS'),
    }),
  };

  if (config.port < 1 || config.port > 65535) {
    throw new Error(`PORT out of range: ${config.port}`);
  }
  if (config.database.port < 1 || config.database.port > 65535) {
    throw new Error(`DATABASE_PORT out of range: ${config.database.port}`);
  }
  if (config.auth.accessTtlSec < 1 || config.auth.refreshTtlDays < 1) {
    throw new Error('Auth token lifetimes must be positive');
  }
  if (config.env === 'production') {
    validateProductionSecret('JWT_ACCESS_SECRET', env.JWT_ACCESS_SECRET);
    validateProductionSecret('JWT_REFRESH_SECRET', env.JWT_REFRESH_SECRET);
    if (env.JWT_ACCESS_SECRET === env.JWT_REFRESH_SECRET) {
      throw new Error('JWT_ACCESS_SECRET and JWT_REFRESH_SECRET must be different values');
    }
  }

  return Object.freeze(config);
}
