import crypto from 'node:crypto';
import fs from 'node:fs';

import { assertPushPayload } from './payload.js';
import { classifyPushStatus } from './outcome.js';

/**
 * FCM HTTP v1 (OPH-312, ADR-0038) — Android, and iPhones through FCM's own
 * APNs relay, which is why there is no second provider integration anywhere.
 *
 * ── NO `firebase-admin` ───────────────────────────────────────────────────
 *
 * What that package would do here is sign a JWT and POST it. The signing is
 * twelve lines of `node:crypto`, and the alternative is a large dependency that
 * brings its own HTTP stack, its own retry opinions and a Google-shaped runtime
 * into an API whose only other outbound clients are two `fetch` call sites.
 *
 * ── THE ACCESS TOKEN IS BOUGHT ONCE ───────────────────────────────────────
 *
 * Google's token is good for an hour. Exchanging an assertion for every message
 * would double every send and rate-limit us on a busy minute, so it is cached
 * until shortly before it expires — early, because a token that expires in
 * flight is a 401 nobody can act on.
 */
const TOKEN_URL = 'https://oauth2.googleapis.com/token';
const SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';
/** Refresh this far before expiry, so a token never dies mid-request. */
const EXPIRY_MARGIN_SEC = 60;

const base64url = (value) => Buffer.from(value).toString('base64url');

function signAssertion(account, nowSec) {
  const header = base64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claims = base64url(
    JSON.stringify({
      iss: account.client_email,
      scope: SCOPE,
      aud: TOKEN_URL,
      iat: nowSec,
      exp: nowSec + 3600,
    }),
  );
  const signature = crypto
    .createSign('RSA-SHA256')
    .update(`${header}.${claims}`)
    .sign(account.private_key)
    .toString('base64url');
  return `${header}.${claims}.${signature}`;
}

/** FCM's `data` map is string→string. Every value, no exceptions. */
function asDataMap(payload) {
  return Object.fromEntries(Object.entries(payload).map(([key, value]) => [key, String(value)]));
}

/**
 * Is this the answer that means the token is dead?
 *
 * FCM says so in the body, not only the status: `UNREGISTERED` for an app that
 * was uninstalled or a token that rotated. A 404 without it is something else.
 */
function isUnregistered(status, body) {
  if (status !== 404 && status !== 400) return false;
  return /UNREGISTERED|NOT_FOUND/.test(body ?? '');
}

export function createFcmSender({
  serviceAccountFile,
  projectId,
  fetchImpl = fetch,
  now = () => Date.now(),
}) {
  const account = JSON.parse(fs.readFileSync(serviceAccountFile, 'utf8'));
  const sendUrl = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;
  /** @type {{value: string, expiresAtSec: number}|null} */
  let cached = null;

  async function accessToken() {
    const nowSec = Math.floor(now() / 1000);
    if (cached && cached.expiresAtSec - EXPIRY_MARGIN_SEC > nowSec) return cached.value;

    const response = await fetchImpl(TOKEN_URL, {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        assertion: signAssertion(account, nowSec),
      }).toString(),
    });
    const text = await response.text();
    if (!response.ok) {
      throw new Error(`FCM token exchange failed: HTTP ${response.status} ${text.slice(0, 200)}`);
    }
    const body = JSON.parse(text);
    cached = { value: body.access_token, expiresAtSec: nowSec + (body.expires_in ?? 3600) };
    return cached.value;
  }

  return {
    /**
     * @param {string} deviceToken the FCM registration token
     * @param {object} payload ids only — see payload.js
     * @param {{title: string, body: string}} [alert] the fixed sentence to
     *   show, from `PUSH_ALERT_TEXT`. Omitted for a silent wake-up.
     */
    async send(deviceToken, payload, alert) {
      assertPushPayload(payload);

      let token;
      try {
        token = await accessToken();
      } catch (error) {
        // Credentials or Google being unreachable — both worth trying again,
        // and neither says anything about this device.
        return { outcome: 'failed', retryable: true, reason: error.message };
      }

      try {
        const response = await fetchImpl(sendUrl, {
          method: 'POST',
          headers: { Authorization: `Bearer ${token}`, 'content-type': 'application/json' },
          body: JSON.stringify({
            message: {
              token: deviceToken,
              data: asDataMap(payload),
              // A wake-up is worth waking the radio for; it is the whole point.
              android: { priority: 'high' },
              // OPH-320 — the visible half. Present only when the caller has a
              // sentence from the closed catalogue; a wake-up hint has none and
              // must stay invisible, which on iOS also means it is not
              // delivered at all without a background mode we deliberately do
              // not ask for (ADR-0038 §8).
              ...(alert
                ? {
                    notification: { title: alert.title, body: alert.body },
                    // `alert` interruption-level and a sound: this is the
                    // fallback for a device whose own alarm did not fire, so it
                    // has to be noticeable. Not `time-sensitive`/`critical` —
                    // those are the local alarm's territory (NOTIFICATIONS §2b)
                    // and asking for them from a server push would be claiming
                    // an urgency the server cannot know.
                    apns: { payload: { aps: { sound: 'default' } } },
                  }
                : {}),
            },
          }),
        });
        const text = await response.text();
        if (isUnregistered(response.status, text)) return { outcome: 'gone' };
        return classifyPushStatus(response.status);
      } catch (error) {
        return { outcome: 'failed', retryable: true, reason: error.message };
      }
    },
  };
}
