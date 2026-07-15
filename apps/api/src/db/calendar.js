import { GoogleClient } from '../lib/google.js';
import { encryptSecret, decryptSecret } from '../lib/crypto.js';

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
