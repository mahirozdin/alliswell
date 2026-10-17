import { GoogleClient } from '../lib/google.js';
import { encryptSecret, decryptSecret } from '../lib/crypto.js';
import { createCaldavClient } from '../lib/caldav/client.js';

/** One client per app is plenty — it is stateless over fetch. */
export function googleClientFor(app) {
  return new GoogleClient(app.config.google);
}

const EXPIRY_SLACK_MS = 60_000;

/**
 * Returns a usable access token for the account, refreshing (and re-encrypting
 * at rest) when it expires within a minute. A dead refresh token flips the
 * account to `error` so the UI can ask the user to reconnect — Google revokes
 * refresh tokens when the user withdraws consent.
 */
export async function getFreshAccessToken(app, account) {
  const key = app.config.calendar.tokenKey;
  const expiresAt = account.token_expires_at ? new Date(account.token_expires_at).getTime() : 0;
  if (account.encrypted_access_token && expiresAt > Date.now() + EXPIRY_SLACK_MS) {
    return decryptSecret(account.encrypted_access_token, key);
  }

  const refreshToken = account.encrypted_refresh_token
    ? decryptSecret(account.encrypted_refresh_token, key)
    : null;
  if (!refreshToken) {
    throw Object.assign(new Error('Calendar account has no refresh token'), {
      code: 'CALENDAR_ACCOUNT_REAUTH_REQUIRED',
    });
  }

  try {
    const tokens = await googleClientFor(app).refreshAccessToken(refreshToken);
    const patch = {
      encrypted_access_token: encryptSecret(tokens.access_token, key),
      token_expires_at: new Date(Date.now() + (tokens.expires_in ?? 3600) * 1000),
      updated_at: new Date(),
    };
    if (tokens.refresh_token) {
      patch.encrypted_refresh_token = encryptSecret(tokens.refresh_token, key);
    }
    await app.db('calendar_accounts').where({ id: account.id }).update(patch);
    return tokens.access_token;
  } catch (err) {
    if (err?.status === 400 || err?.status === 401) {
      await app.db('calendar_accounts').where({ id: account.id }).update({
        status: 'error',
        last_error: 'refresh token rejected — reconnect the Google account',
        updated_at: new Date(),
      });
      throw Object.assign(new Error('Google refresh token rejected'), {
        code: 'CALENDAR_ACCOUNT_REAUTH_REQUIRED',
      });
    }
    throw err;
  }
}

// ── CalDAV (OPH-380, ADR-0059) ─────────────────────────────────────────────

/** `provider_account_id` of a CalDAV account: `<host>/<username>`. */
export function caldavIdentity(host, username) {
  return `${String(host).toLowerCase()}/${username}`;
}

/** The username half of a CalDAV `provider_account_id`. */
export function caldavUsername(account) {
  const id = String(account.provider_account_id ?? '');
  const slash = id.indexOf('/');
  return slash === -1 ? id : id.slice(slash + 1);
}

/** The host half of a CalDAV `provider_account_id`. */
export function caldavHost(account) {
  const id = String(account.provider_account_id ?? '');
  const slash = id.indexOf('/');
  return slash === -1 ? '' : id.slice(0, slash);
}

const reauth = (message) =>
  Object.assign(new Error(message), { code: 'CALENDAR_ACCOUNT_REAUTH_REQUIRED' });

/**
 * The account's CalDAV client, its password decrypted for this call only.
 * A row without ciphertext (disconnected, or a password rejected earlier)
 * throws `CALENDAR_ACCOUNT_REAUTH_REQUIRED` — the same contract as Google's
 * `getFreshAccessToken`, so callers skip it the same way.
 */
export function caldavClientForAccount(app, account) {
  if (!account.encrypted_app_password) throw reauth('CalDAV account has no stored password');
  const password = decryptSecret(account.encrypted_app_password, app.config.calendar.tokenKey);
  return createCaldavClient({
    kind: account.caldav_kind === 'icloud' ? 'icloud' : 'generic',
    serverUrl: account.caldav_server_url ?? account.calendar_home_url,
    username: caldavUsername(account),
    password,
    config: app.config.caldav,
  });
}

/**
 * The server said 401: the app-specific password was revoked (or changed).
 * Retrying cannot fix that, so the account flips to `error` — and the card asks
 * the user to reconnect — instead of decaying silently (CALDAV.md §6).
 */
export async function markCaldavReauth(app, account) {
  await app.db('calendar_accounts').where({ id: account.id }).update({
    status: 'error',
    last_error: 'password rejected — reconnect the calendar',
    updated_at: new Date(),
  });
}

/** Absolute URL for a stored CalDAV path (hrefs and calendar paths are paths). */
export function caldavUrl(account, path) {
  return new URL(path, account.calendar_home_url ?? account.caldav_server_url).href;
}
