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
  };

  if (config.port < 1 || config.port > 65535) {
    throw new Error(`PORT out of range: ${config.port}`);
  }
  if (config.database.port < 1 || config.database.port > 65535) {
    throw new Error(`DATABASE_PORT out of range: ${config.database.port}`);
  }

  return Object.freeze(config);
}
