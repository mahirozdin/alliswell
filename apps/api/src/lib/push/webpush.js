import webpush from 'web-push';

import { assertPushPayload } from './payload.js';
import { classifyPushStatus } from './outcome.js';

/**
 * Web Push (OPH-312, ADR-0038) — the only way to alert a browser, because no
 * browser can schedule a local notification.
 *
 * ── THE LIBRARY DOES THE CRYPTO, WE DO THE HTTP ───────────────────────────
 *
 * `web-push` can send by itself, and it is not asked to. RFC 8291's encryption
 * — ECDH against the subscription's key, HKDF, AES-128-GCM — is exactly the
 * kind of thing that fails SILENTLY when hand-written, so the library owns it.
 * The request it produces is then sent with `fetch`, like the two other outbound
 * clients in this API: the status mapping, the retry decision and the timeout
 * are ours, and a second HTTP stack with its own opinions is not.
 *
 * `generateRequestDetails` is that seam. It returns the encrypted body and the
 * VAPID headers without touching the network.
 */
export function createWebPushSender({
  publicKey,
  privateKey,
  subject,
  fetchImpl = fetch,
  ttlSec = 600,
}) {
  const vapidDetails = { subject, publicKey, privateKey };

  return {
    /**
     * @param {{endpoint: string, p256dh: string, auth: string}} subscription
     * @param {object} payload ids only — see payload.js
     */
    async send(subscription, payload) {
      assertPushPayload(payload);

      let request;
      try {
        request = webpush.generateRequestDetails(
          {
            endpoint: subscription.endpoint,
            keys: { p256dh: subscription.p256dh, auth: subscription.auth },
          },
          JSON.stringify(payload),
          { vapidDetails, contentEncoding: 'aes128gcm', TTL: ttlSec },
        );
      } catch (error) {
        // A subscription we cannot encrypt to is not a network problem and
        // retrying will not change it.
        return { outcome: 'failed', retryable: false, reason: error.message };
      }

      try {
        const response = await fetchImpl(request.endpoint, {
          method: 'POST',
          headers: request.headers,
          body: request.body,
        });
        return classifyPushStatus(response.status);
      } catch (error) {
        // Offline, DNS, a refused connection: the subscription is probably
        // fine and the next sweep is the right place to find out.
        return { outcome: 'failed', retryable: true, reason: error.message };
      }
    },
  };
}
