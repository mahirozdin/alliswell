import path from 'node:path';
import { EE_FEATURES } from './lib/entitlements.js';
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
 * `TRUST_PROXY` → Fastify's `trustProxy`. Off unless asked for, because
 * trusting `X-Forwarded-For` on a directly reachable API lets any client spoof
 * its address (and with it, the per-IP rate limits).
 *
 * Accepts `true`/`false`, a hop count, or a comma-separated list of trusted
 * proxy addresses/subnets — `TRUST_PROXY=127.0.0.1` is the right answer for the
 * usual "Apache/Nginx on the same box in front of a loopback API" deployment.
 */
function parseTrustProxy(value) {
  if (value === undefined || value === null || value === '') return false;
  const normalized = String(value).trim();
  const lower = normalized.toLowerCase();
  if (lower === 'false' || normalized === '0') return false;
  if (lower === 'true') return true;
  if (/^\d+$/.test(normalized)) return Number.parseInt(normalized, 10); // hop count
  return normalized; // address / subnet list — proxy-addr parses it
}

function toBool(value, fallback, name) {
  if (value === undefined || value === null || value === '') return fallback;
  const normalized = String(value).trim().toLowerCase();
  if (normalized === 'true' || normalized === '1') return true;
  if (normalized === 'false' || normalized === '0') return false;
  throw new Error(`Invalid boolean for ${name}: "${value}"`);
}

// Development/test fallbacks so the app boots without a .env. Deliberately listed as
// insecure below — production refuses to start with any of these (or the .env.example
// placeholders). Generate real values with `openssl rand -hex 32`.
const DEV_ACCESS_SECRET = 'insecure-dev-access-secret-never-use-in-production';
const DEV_REFRESH_SECRET = 'insecure-dev-refresh-secret-never-use-in-production';
// 64 hex chars (32 bytes), obviously patterned so nobody ships it.
const DEV_CALENDAR_TOKEN_KEY = 'deaddeaddeaddeaddeaddeaddeaddeaddeaddeaddeaddeaddeaddeaddeaddead';
// Same shape, different pattern — AI keys must not share the calendar key.
const DEV_AI_TOKEN_KEY = 'feedfeedfeedfeedfeedfeedfeedfeedfeedfeedfeedfeedfeedfeedfeedfeed';
const DEV_TOTP_KEY = 'cafecafecafecafecafecafecafecafecafecafecafecafecafecafecafecafe';
// Extensions that store provider credentials of their own get their own key,
// not this instance's. Separate blast radius, separate rotation.
const DEV_EE_AI_TOKEN_KEY = 'beefbeefbeefbeefbeefbeefbeefbeefbeefbeefbeefbeefbeefbeefbeefbeef';
const INSECURE_SECRETS = new Set([
  DEV_ACCESS_SECRET,
  DEV_REFRESH_SECRET,
  DEV_CALENDAR_TOKEN_KEY,
  DEV_AI_TOKEN_KEY,
  DEV_TOTP_KEY,
  DEV_EE_AI_TOKEN_KEY,
  'change-me-generate-a-random-secret',
  'change-me-generate-another-random-secret',
]);

/**
 * Is this one of the development placeholders shipped in this file?
 *
 * `validateProductionSecret` asks the same question of core's own secrets and
 * refuses to boot. It is exported because an extension can store secrets core
 * knows nothing about, and it must be able to refuse for the same reason —
 * but at the moment it would WRITE one, not at boot. Requiring a new secret
 * at boot would turn an upgrade into a boot failure for every instance that
 * never uses the feature, and "upgrades must never turn into boot failures"
 * is a house rule, not a preference.
 */
export function isPlaceholderSecret(value) {
  return !value || INSECURE_SECRETS.has(value);
}

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
function parseDevEntitlements(env) {
  const raw = env.EE_DEV_ENTITLEMENTS;
  if (!raw) return null;
  if ((env.NODE_ENV ?? 'development') === 'production') {
    throw new Error(
      'EE_DEV_ENTITLEMENTS is a development override and must not be set in production',
    );
  }
  const names = Object.freeze(
    raw
      .split(',')
      .map((s) => s.trim())
      .filter(Boolean),
  );
  for (const name of names) {
    if (!EE_FEATURES.includes(name)) {
      throw new Error(`EE_DEV_ENTITLEMENTS: unknown feature "${name}"`);
    }
  }
  return names.length > 0 ? names : null;
}

/**
 * Outgoing mail is all-or-nothing. `storage` may be partially set and simply
 * stays off, and that is right for it: a missing bucket makes uploads
 * impossible and everybody finds out on the next attempt. Mail is the
 * opposite — a half-filled block looks configured to the operator who filled
 * it in, and the failure surfaces as "the message never arrived", days later,
 * to somebody who cannot see the logs. So it is a boot error, and it names
 * the fields that are missing.
 */
function assertSmtpComplete(config) {
  const { smtp } = config.ee;
  const required = { EE_SMTP_HOST: smtp.host, EE_SMTP_FROM: smtp.from };
  if (!Object.values(required).some(Boolean)) return; // not configured at all
  const missing = Object.entries(required)
    .filter(([, value]) => !value)
    .map(([name]) => name);
  // An anonymous relay is legitimate; half a credential is not.
  if (Boolean(smtp.user) !== Boolean(smtp.password)) {
    missing.push(smtp.user ? 'EE_SMTP_PASSWORD' : 'EE_SMTP_USER');
  }
  if (missing.length > 0) {
    throw new Error(
      `SMTP is half-configured: ${missing.join(', ')} missing. ` +
        'Set the whole block or none of it — a partly-filled one silently stops sending mail.',
    );
  }
}

export function loadConfig(env = process.env) {
  const config = {
    env: env.NODE_ENV ?? 'development',
    host: env.HOST ?? '0.0.0.0',
    port: toInt(env.PORT, 3000, 'PORT'),
    logLevel: env.LOG_LEVEL ?? 'info',
    corsOrigin: parseCorsOrigin(env.CORS_ORIGIN),
    trustProxy: parseTrustProxy(env.TRUST_PROXY),
    rateLimitMax: toInt(env.RATE_LIMIT_MAX, 300, 'RATE_LIMIT_MAX'),
    rateLimitAuthMax: toInt(env.RATE_LIMIT_AUTH_MAX, 10, 'RATE_LIMIT_AUTH_MAX'),
    // Per KEY, not per IP (OPH-264, ADR-0032 §5). Same ceiling as the global
    // per-IP limit: a key is one client, and this is what one client gets.
    apiKeyRateLimitMax: toInt(env.API_KEY_RATE_LIMIT_MAX, 300, 'API_KEY_RATE_LIMIT_MAX'),
    // Note history (OPH-267, ADR-0031 §6). Retention is a SERVER policy: when
    // it is negotiated across devices it collapses to the minimum any device
    // kept, which is how an offline phone truncates a laptop's history.
    noteVersions: Object.freeze({
      // Days where nothing is thinned at all.
      keepAllDays: toInt(env.NOTE_VERSION_KEEP_ALL_DAYS, 7, 'NOTE_VERSION_KEEP_ALL_DAYS'),
      // After this many days ordinary `edit` versions are deleted.
      retentionDays: toInt(env.NOTE_VERSION_RETENTION_DAYS, 90, 'NOTE_VERSION_RETENTION_DAYS'),
      // conflict/merge/restore/import rows live this long — they are the ones
      // somebody comes looking for.
      protectedDays: toInt(env.NOTE_VERSION_PROTECTED_DAYS, 365, 'NOTE_VERSION_PROTECTED_DAYS'),
      cap: toInt(env.NOTE_VERSION_CAP, 500, 'NOTE_VERSION_CAP'),
      // The rolling-head window: a 1.5 s autosave debounce would otherwise
      // leave ~260 rows per ten minutes of typing (finding #5).
      coalesceMin: toInt(env.NOTE_VERSION_COALESCE_MIN, 10, 'NOTE_VERSION_COALESCE_MIN'),
      sweepSec: toInt(env.NOTE_VERSION_SWEEP_SEC, 86400, 'NOTE_VERSION_SWEEP_SEC'),
    }),
    database: Object.freeze({
      host: env.DATABASE_HOST ?? '127.0.0.1',
      port: toInt(env.DATABASE_PORT, 3306, 'DATABASE_PORT'),
      user: env.DATABASE_USER ?? 'alliswell',
      password: env.DATABASE_PASSWORD ?? 'alliswell_dev',
      name: env.DATABASE_NAME ?? 'alliswell',
      // Optional pin for the schema's utf8mb4 collation. Null = auto-detect
      // (MySQL 8 → utf8mb4_0900_ai_ci, MariaDB → utf8mb4_unicode_ci; see
      // src/db/collation.js). Set it only to force something else, e.g.
      // utf8mb4_uca1400_ai_ci on MariaDB 10.10+.
      collation: env.DATABASE_COLLATION || null,
    }),
    // Grace period before a requested account deletion becomes irreversible
    // (src/db/accounts.js). Both app stores require deletion to be reachable
    // in-app; the delay is our own undo window.
    accountDeletionGraceDays: toInt(
      env.ACCOUNT_DELETION_GRACE_DAYS,
      3,
      'ACCOUNT_DELETION_GRACE_DAYS',
    ),
    // How often expired accounts are purged.
    accountSweepSec: toInt(env.ACCOUNT_SWEEP_SEC, 3600, 'ACCOUNT_SWEEP_SEC'),
    // How often the recurring-task window rolls forward (OPH-205, ADR-0020 §5).
    // Daily by default: the window is 12 months, so nothing is urgent about it.
    seriesSweepSec: toInt(env.SERIES_SWEEP_SEC, 86400, 'SERIES_SWEEP_SEC'),
    redisUrl: env.REDIS_URL ?? 'redis://127.0.0.1:6379',
    // Namespaces this deployment's BullMQ keyspace. Two AllisWell instances
    // pointed at one Redis would otherwise consume each other's jobs — and
    // since each has its OWN MySQL, the thief finds no task and drops the job
    // on the floor. Give every deployment sharing a Redis its own prefix.
    redisKeyPrefix: env.REDIS_KEY_PREFIX || 'alliswell',
    auth: Object.freeze({
      accessSecret: env.JWT_ACCESS_SECRET || DEV_ACCESS_SECRET,
      refreshSecret: env.JWT_REFRESH_SECRET || DEV_REFRESH_SECRET,
      accessTtlSec: toInt(env.AUTH_ACCESS_TTL_SEC, 900, 'AUTH_ACCESS_TTL_SEC'),
      refreshTtlDays: toInt(env.AUTH_REFRESH_TTL_DAYS, 30, 'AUTH_REFRESH_TTL_DAYS'),
      // OPH-283 — AES-256-GCM key for TOTP secrets at rest, and the HMAC key
      // for recovery-code digests. Its OWN key, for the reason ADR-0006 gives
      // every time: a calendar-key or AI-key compromise must not hand somebody
      // every second factor in the install. Dev fallback is labeled insecure
      // like its siblings.
      totpKey: env.AUTH_TOTP_KEY || DEV_TOTP_KEY,
    }),
    // Google Calendar (Epic 08). The integration is OPTIONAL — endpoints answer
    // GOOGLE_NOT_CONFIGURED without credentials. Base URLs are configurable so
    // tests can point the client at an in-process fake Google.
    google: Object.freeze({
      clientId: env.GOOGLE_CLIENT_ID || null,
      clientSecret: env.GOOGLE_CLIENT_SECRET || null,
      redirectUri:
        env.GOOGLE_REDIRECT_URI || 'http://localhost:3000/api/v1/integrations/google/callback',
      authBaseUrl: env.GOOGLE_AUTH_BASE_URL || 'https://accounts.google.com',
      tokenBaseUrl: env.GOOGLE_TOKEN_BASE_URL || 'https://oauth2.googleapis.com',
      apiBaseUrl: env.GOOGLE_API_BASE_URL || 'https://www.googleapis.com',
    }),
    // Sign in with Google / Apple (Epic 21, ADR-0026). Separate from the
    // `google` block above, which is CALENDAR sync: different consent, different
    // client, different lifetime. These are the audiences an incoming ID token
    // is allowed to name — one per platform, because one Google project issues a
    // different client ID to Android, iOS and web and all three are equally us.
    //
    // Configure none and the provider is simply off: the endpoint answers
    // OAUTH_PROVIDER_NOT_CONFIGURED rather than accepting tokens minted for
    // somebody else's application.
    signIn: Object.freeze({
      googleWebClientId: env.SIGN_IN_GOOGLE_WEB_CLIENT_ID || null,
      googleIosClientId: env.SIGN_IN_GOOGLE_IOS_CLIENT_ID || null,
      googleAndroidClientId: env.SIGN_IN_GOOGLE_ANDROID_CLIENT_ID || null,
      // Apple names the audience differently per surface: the app's bundle id
      // on iOS/macOS, the Services ID on web and Android.
      appleBundleId: env.SIGN_IN_APPLE_BUNDLE_ID || null,
      appleServiceId: env.SIGN_IN_APPLE_SERVICE_ID || null,
    }),
    // Attachments (Epic 14, ATTACHMENTS.md / ADR-0011). Optional like Google:
    // with no storage env at all the file endpoints answer
    // STORAGE_NOT_CONFIGURED and the app shows honest empty states. The
    // endpoint is S3-compatible — Cloudflare R2 is the documented primary
    // (https://<ACCOUNT_ID>.r2.cloudflarestorage.com, region "auto"); MinIO
    // fills the same role in dev/CI.
    storage: Object.freeze({
      endpoint: env.STORAGE_S3_ENDPOINT || null,
      region: env.STORAGE_S3_REGION || 'auto',
      bucket: env.STORAGE_S3_BUCKET || null,
      accessKeyId: env.STORAGE_S3_ACCESS_KEY_ID || null,
      secretAccessKey: env.STORAGE_S3_SECRET_ACCESS_KEY || null,
      // Bucket-in-path URLs: R2 accepts both styles, MinIO requires path style.
      forcePathStyle: toBool(env.STORAGE_S3_FORCE_PATH_STYLE, true, 'STORAGE_S3_FORCE_PATH_STYLE'),
      maxUploadBytes: toInt(env.STORAGE_MAX_UPLOAD_MB, 512, 'STORAGE_MAX_UPLOAD_MB') * 1024 * 1024,
      presignTtlSec: toInt(env.STORAGE_PRESIGN_TTL_SEC, 3600, 'STORAGE_PRESIGN_TTL_SEC'),
      sweepSec: toInt(env.STORAGE_SWEEP_SEC, 3600, 'STORAGE_SWEEP_SEC'),
    }),
    // AI (Epic 20, ADR-0019, AI.md). Enabled by default: the embedded track is
    // BYOK — it needs no instance credentials to be useful — and `false` is the
    // instance owner's honest kill switch (every /ai/* route answers 404, the
    // app withdraws every AI surface). Base URLs are configurable so tests can
    // point the five adapters at an in-process fake (the ADR-0006 §5 pattern);
    // instance keys turn on `auth_mode = 'instance_env'` connections.
    ai: Object.freeze({
      enabled: toBool(env.AI_ENABLED, true, 'AI_ENABLED'),
      // AES-256-GCM key for BYOK provider keys at rest — the exact ADR-0006
      // pattern under its own key (a calendar-key compromise must not open the
      // AI keys, and vice versa).
      tokenKey: env.AI_TOKEN_KEY || DEV_AI_TOKEN_KEY,
      // OPH-217 stream tunables.
      heartbeatMs: toInt(env.AI_HEARTBEAT_MS, 15000, 'AI_HEARTBEAT_MS'),
      ratePerMinute: toInt(env.AI_RATE_PER_MINUTE, 10, 'AI_RATE_PER_MINUTE'),
      rateBurst: toInt(env.AI_RATE_BURST, 10, 'AI_RATE_BURST'),
      // Daily token ceiling per user, instance_env connections only (the
      // instance owner's money). 0 disables the cap.
      dailyTokenCap: toInt(env.AI_DAILY_TOKEN_CAP, 200000, 'AI_DAILY_TOKEN_CAP'),
      instanceKeys: Object.freeze({
        anthropic: env.AI_ANTHROPIC_API_KEY || null,
        openai: env.AI_OPENAI_API_KEY || null,
        gemini: env.AI_GEMINI_API_KEY || null,
        openrouter: env.AI_OPENROUTER_API_KEY || null,
      }),
      baseUrls: Object.freeze({
        anthropic: env.AI_ANTHROPIC_BASE_URL || 'https://api.anthropic.com',
        openai: env.AI_OPENAI_BASE_URL || 'https://api.openai.com',
        gemini: env.AI_GEMINI_BASE_URL || 'https://generativelanguage.googleapis.com',
        openrouter: env.AI_OPENROUTER_BASE_URL || 'https://openrouter.ai/api',
        // No default: an instance-wide Ollama must be pointed at explicitly
        // (per-user connections carry their own base_url instead).
        ollama: env.AI_OLLAMA_BASE_URL || null,
      }),
    }),
    // Remote MCP server (Epic 20 Track A, ADR-0022). Independent of AI_ENABLED
    // by decision: MCP spends no model money and stores no provider keys.
    // `publicUrl` is the OAuth issuer + resource identity; without it (in
    // production) the MCP/OAuth routes answer 404 MCP_NOT_CONFIGURED — never
    // a boot failure (upgraded deployments must not brick).
    mcp: Object.freeze({
      enabled: toBool(env.MCP_ENABLED, true, 'MCP_ENABLED'),
      publicUrl: (env.API_PUBLIC_URL || '').replace(/\/+$/, '') || null,
      accessTtlSec: toInt(env.MCP_ACCESS_TTL_SEC, 3600, 'MCP_ACCESS_TTL_SEC'),
      refreshTtlDays: toInt(env.MCP_REFRESH_TTL_DAYS, 30, 'MCP_REFRESH_TTL_DAYS'),
      codeTtlSec: 60,
      rateLimitMax: toInt(env.MCP_RATE_LIMIT_MAX, 120, 'MCP_RATE_LIMIT_MAX'),
    }),
    // Enterprise overlay seam (EE-002). The overlay is a sibling checkout the
    // loader (src/lib/ee.js) imports at boot when present; absence IS the CE
    // build — nothing changes, no flag needed. Two knobs only: EE_ENABLED as
    // an ops kill-switch, EE_DIR to relocate the checkout. Default is OFF
    // under NODE_ENV=test so suites behave identically on a machine that has
    // an overlay checked out and in CI, which does not — seam tests opt in
    // with an explicit fixture EE_DIR.
    ee: Object.freeze({
      enabled: toBool(env.EE_ENABLED, (env.NODE_ENV ?? 'development') !== 'test', 'EE_ENABLED'),
      dir: env.EE_DIR || null,
      // EE-129: an optional fence around the operator console. Comma-separated
      // addresses and IPv4 CIDRs; empty means no fence at all (the overlay's
      // own module says why the default is not "nowhere"). Core stores the
      // string and never reads it.
      adminIpAllowlist: env.EE_ADMIN_IP_ALLOWLIST || null,
      // Development override (EE-003): comma-separated feature names, refused
      // outright in production — a leftover override must never hand out paid
      // features. Names are validated against the ONE dictionary so a typo is
      // a boot error, not a silently-missing feature.
      devEntitlements: parseDevEntitlements(env),
      // Signed license file (EE-004). Default path is <overlay dir>/license.json,
      // resolved by the entitlements plugin; the public key override exists for
      // tests and a future rotation.
      licensePath: env.EE_LICENSE_PATH || null,
      licensePublicKey: env.EE_LICENSE_PUBLIC_KEY || null,
      // The apex domain this instance serves (e.g. "example.com"). Extensions
      // may derive host-based request context from it; core ignores it.
      baseDomain: env.EE_BASE_DOMAIN ? env.EE_BASE_DOMAIN.toLowerCase() : null,
      // AES-256-GCM key for provider credentials an extension stores on
      // somebody's behalf. Deliberately NOT `ai.tokenKey`: those two protect
      // secrets with different owners and different lifetimes, and sharing one
      // key would mean rotating either forces re-encrypting both. Core stores
      // nothing under it and never reads it.
      aiTokenKey: env.EE_AI_TOKEN_KEY || DEV_EE_AI_TOKEN_KEY,
      // Outgoing mail for extensions that send any (core sends none). Read
      // like `storage`: absent means the capability is simply off. Unlike
      // storage it is ALL-OR-NOTHING — see assertSmtpComplete below for why a
      // half-filled block has to be a boot error rather than a quiet no-op.
      smtp: Object.freeze({
        host: env.EE_SMTP_HOST || null,
        port: env.EE_SMTP_HOST ? toInt(env.EE_SMTP_PORT, 587, 'EE_SMTP_PORT') : null,
        user: env.EE_SMTP_USER || null,
        password: env.EE_SMTP_PASSWORD || null,
        from: env.EE_SMTP_FROM || null,
        // STARTTLS on 587 by default; set false only for a local relay.
        secure: toBool(env.EE_SMTP_SECURE, false, 'EE_SMTP_SECURE'),
      }),
      // Mobile push for extensions that send any (core sends none — the app's
      // own reminders are local, OPH-061). A BOOLEAN rather than a block, and
      // deliberately: the only thing this decides is whether an extension may
      // queue a push at all, and a block would make `Boolean(config.ee.push)`
      // true the moment it existed. Provider credentials belong to whoever
      // turns this on, and arrive with that work rather than sitting here
      // unread.
      //
      // Default OFF. With it off nothing is enqueued — not a row nobody sends,
      // no row at all — which is what makes "zero effect" a number a test can
      // assert instead of a claim.
      push: toBool(env.EE_PUSH_ENABLED, false, 'EE_PUSH_ENABLED'),
    }),
    calendar: Object.freeze({
      // AES-256-GCM key for OAuth tokens at rest (SECURITY.md / ADR-0006):
      // 64 hex chars → 32 bytes. Dev fallback is labeled insecure on purpose.
      tokenKey: env.CALENDAR_TOKEN_KEY || DEV_CALENDAR_TOKEN_KEY,
      // Public HTTPS address Google POSTs change notifications to (OPH-074).
      // Optional by design: without it we never open a push channel and the
      // sweep polls instead, so localhost/NAT self-hosters still sync.
      webhookUrl: env.GOOGLE_WEBHOOK_URL || null,
      // Requested channel lifetime. Google caps this at its own limit and
      // answers with the real expiration — we renew off THAT, never off this.
      watchTtlSec: toInt(env.CALENDAR_WATCH_TTL_SEC, 604800, 'CALENDAR_WATCH_TTL_SEC'),
      // How often the sweep renews channels, retries dirty accounts, and polls
      // channel-less ones.
      sweepSec: toInt(env.CALENDAR_SYNC_SWEEP_SEC, 300, 'CALENDAR_SYNC_SWEEP_SEC'),
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
  if (!/^[0-9a-fA-F]{64}$/.test(config.calendar.tokenKey)) {
    throw new Error('CALENDAR_TOKEN_KEY must be 64 hex characters (openssl rand -hex 32)');
  }
  if (!/^[0-9a-fA-F]{64}$/.test(config.ai.tokenKey)) {
    throw new Error('AI_TOKEN_KEY must be 64 hex characters (openssl rand -hex 32)');
  }
  if (!/^[0-9a-fA-F]{64}$/.test(config.auth.totpKey)) {
    throw new Error('AUTH_TOTP_KEY must be 64 hex characters (openssl rand -hex 32)');
  }
  if (!/^[0-9a-fA-F]{64}$/.test(config.ee.aiTokenKey)) {
    throw new Error('EE_AI_TOKEN_KEY must be 64 hex characters (openssl rand -hex 32)');
  }
  assertSmtpComplete(config);
  if (config.ai.heartbeatMs < 1000 || config.ai.heartbeatMs > 60000) {
    throw new Error('AI_HEARTBEAT_MS must be between 1000 and 60000 (proxies time out above that)');
  }
  if (config.ai.ratePerMinute < 1 || config.ai.rateBurst < 1) {
    throw new Error('AI_RATE_PER_MINUTE and AI_RATE_BURST must be at least 1');
  }
  if (config.ai.dailyTokenCap < 0) {
    throw new Error('AI_DAILY_TOKEN_CAP must be 0 (off) or positive');
  }
  for (const [provider, baseUrl] of Object.entries(config.ai.baseUrls)) {
    if (baseUrl && !/^https?:\/\//.test(baseUrl)) {
      throw new Error(`AI ${provider} base URL must start with http:// or https://`);
    }
  }
  if (config.mcp.publicUrl && !/^https?:\/\//.test(config.mcp.publicUrl)) {
    throw new Error('API_PUBLIC_URL must start with http:// or https://');
  }
  if (config.mcp.accessTtlSec < 60 || config.mcp.refreshTtlDays < 1) {
    throw new Error('MCP token lifetimes are too small');
  }
  // The collation is interpolated into CREATE TABLE text, so it is validated as
  // a bare identifier here rather than trusted from the environment.
  if (config.database.collation && !/^[A-Za-z0-9_]+$/.test(config.database.collation)) {
    throw new Error('DATABASE_COLLATION must be a bare collation name (letters, digits, _)');
  }
  if (config.calendar.watchTtlSec < 60 || config.calendar.sweepSec < 10) {
    throw new Error('CALENDAR_WATCH_TTL_SEC (≥60) and CALENDAR_SYNC_SWEEP_SEC (≥10) are too small');
  }
  // Storage is all-or-nothing: a half-configured store would boot fine and
  // then fail on the first upload — surface the typo at startup instead.
  {
    const core = ['endpoint', 'bucket', 'accessKeyId', 'secretAccessKey'];
    const set = core.filter((key) => config.storage[key]);
    if (set.length > 0 && set.length < core.length) {
      const missing = core.filter((key) => !config.storage[key]);
      throw new Error(
        `Partial storage config: missing ${missing
          .map((k) => `STORAGE_S3_${k.replace(/([A-Z])/g, '_$1').toUpperCase()}`)
          .join(', ')} (set all of endpoint/bucket/keys, or none to disable attachments)`,
      );
    }
  }
  if (config.storage.maxUploadBytes < 1024 * 1024) {
    throw new Error('STORAGE_MAX_UPLOAD_MB must be at least 1');
  }
  // R2 refuses presigned URLs beyond 7 days; catch the config typo at boot.
  if (config.storage.presignTtlSec < 60 || config.storage.presignTtlSec > 604800) {
    throw new Error('STORAGE_PRESIGN_TTL_SEC must be between 60 and 604800 (7 days, the R2 cap)');
  }
  if (config.accountDeletionGraceDays < 0 || config.accountDeletionGraceDays > 90) {
    throw new Error('ACCOUNT_DELETION_GRACE_DAYS must be between 0 and 90');
  }
  if (config.seriesSweepSec < 10) {
    throw new Error('SERIES_SWEEP_SEC must be at least 10');
  }
  if (config.accountSweepSec < 10) {
    throw new Error('ACCOUNT_SWEEP_SEC must be at least 10');
  }
  if (config.storage.sweepSec < 10) {
    throw new Error('STORAGE_SWEEP_SEC must be at least 10');
  }
  // Google refuses a non-HTTPS webhook address, so catch the typo at boot
  // rather than at the first (invisible, queued) watch call.
  if (config.calendar.webhookUrl && !config.calendar.webhookUrl.startsWith('https://')) {
    throw new Error('GOOGLE_WEBHOOK_URL must be a public https:// address (Google requires TLS)');
  }
  if (config.env === 'production') {
    validateProductionSecret('JWT_ACCESS_SECRET', env.JWT_ACCESS_SECRET);
    validateProductionSecret('JWT_REFRESH_SECRET', env.JWT_REFRESH_SECRET);
    if (env.JWT_ACCESS_SECRET === env.JWT_REFRESH_SECRET) {
      throw new Error('JWT_ACCESS_SECRET and JWT_REFRESH_SECRET must be different values');
    }
    // Calendar tokens may only be stored under a real key. Required as soon
    // as the Google integration is configured.
    if (config.google.clientId) {
      validateProductionSecret('GOOGLE_CLIENT_SECRET', env.GOOGLE_CLIENT_SECRET);
      validateProductionSecret('CALENDAR_TOKEN_KEY', env.CALENDAR_TOKEN_KEY);
    }
    // BYOK keys may only be stored under a real key. Required while the AI
    // feature is enabled (it is enabled by default) — a boot error beats a
    // runtime 500 on the first connection. Opting out is AI_ENABLED=false.
    if (config.ai.enabled) {
      validateProductionSecret('AI_TOKEN_KEY', env.AI_TOKEN_KEY);
    }
  }

  return Object.freeze(config);
}
