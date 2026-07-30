/**
 * Per-user AI rate limiting (OPH-217): ONE token bucket shared by chat and
 * extract (they drain the same provider quota), plus the instance_env daily
 * token cap.
 *
 * Redis present → an atomic Lua bucket keyed per user, shared across PM2
 * workers. Redis absent → a per-process Map with the same math (self-host
 * without Redis must work; under PM2 the cap degrades to per-worker — the
 * queue-runner precedent, and it fails SAFE: stricter, not looser). A Redis
 * command failure fails OPEN with a warning: the limiter is protection, not
 * authorization — availability wins (decision recorded).
 */

const BUCKET_LUA = `
local key = KEYS[1]
local rate = tonumber(ARGV[1])
local burst = tonumber(ARGV[2])
local now = tonumber(ARGV[3])
local state = redis.call('HMGET', key, 'tokens', 'ts')
local tokens = tonumber(state[1])
local ts = tonumber(state[2])
if tokens == nil then tokens = burst end
if ts == nil then ts = now end
local elapsed = now - ts
if elapsed < 0 then elapsed = 0 end
tokens = math.min(burst, tokens + (elapsed / 1000) * (rate / 60))
local allowed = 0
local retry = 0
if tokens >= 1 then
  tokens = tokens - 1
  allowed = 1
else
  retry = math.ceil(((1 - tokens) * 60 / rate))
end
redis.call('HSET', key, 'tokens', tokens, 'ts', now)
redis.call('EXPIRE', key, 600)
return {allowed, retry}
`;

function redisUsable(redis) {
  return typeof redis?.eval === 'function' && redis.status === 'ready';
}

/**
 * @returns {{ take(userId: string): Promise<{allowed: boolean, retryAfterSec?: number}> }}
 */
export function createRateLimiter({ redis, keyPrefix, ratePerMinute, burst, log, now = Date.now }) {
  const memory = new Map(); // userId → {tokens, ts}

  function takeFromMemory(userId) {
    const at = now();
    const state = memory.get(userId) ?? { tokens: burst, ts: at };
    const elapsed = Math.max(0, at - state.ts);
    const tokens = Math.min(burst, state.tokens + (elapsed / 1000) * (ratePerMinute / 60));
    if (tokens >= 1) {
      memory.set(userId, { tokens: tokens - 1, ts: at });
      return { allowed: true };
    }
    memory.set(userId, { tokens, ts: at });
    return { allowed: false, retryAfterSec: Math.ceil(((1 - tokens) * 60) / ratePerMinute) };
  }

  return {
    async take(userId) {
      if (!redisUsable(redis)) return takeFromMemory(userId);
      try {
        const [allowed, retry] = await redis.eval(
          BUCKET_LUA,
          1,
          `${keyPrefix}:ai:rl:${userId}`,
          String(ratePerMinute),
          String(burst),
          String(now()),
        );
        return Number(allowed) === 1
          ? { allowed: true }
          : { allowed: false, retryAfterSec: Number(retry) || 1 };
      } catch (err) {
        log?.warn({ err: err.message }, 'ai rate limiter failed open');
        return { allowed: true };
      }
    },
  };
}

/** UTC day stamp — the cap window every worker agrees on. */
function dayStamp(at) {
  return new Date(at).toISOString().slice(0, 10).replaceAll('-', '');
}

/**
 * @returns {{
 *   isOver(userId: string): Promise<boolean>,
 *   add(userId: string, tokens: number): Promise<void>,
 * }}
 */
export function createDailyCap({ redis, keyPrefix, capTokens, log, now = Date.now }) {
  const memory = new Map(); // `${userId}:${day}` → tokens

  return {
    async isOver(userId) {
      if (!capTokens) return false;
      const key = `${keyPrefix}:ai:cap:${userId}:${dayStamp(now())}`;
      if (!redisUsable(redis)) return (memory.get(key) ?? 0) >= capTokens;
      try {
        const current = Number(await redis.get(key)) || 0;
        return current >= capTokens;
      } catch (err) {
        log?.warn({ err: err.message }, 'ai daily cap check failed open');
        return false;
      }
    },
    async add(userId, tokens) {
      if (!capTokens || !tokens) return;
      const key = `${keyPrefix}:ai:cap:${userId}:${dayStamp(now())}`;
      if (!redisUsable(redis)) {
        memory.set(key, (memory.get(key) ?? 0) + tokens);
        return;
      }
      try {
        await redis.incrby(key, tokens);
        await redis.expire(key, 90000); // one day + slack
      } catch (err) {
        log?.warn({ err: err.message }, 'ai daily cap add failed');
      }
    },
  };
}
