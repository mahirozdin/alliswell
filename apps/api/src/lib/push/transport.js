import { alertTextFor, assertPushPayload } from './payload.js';

/**
 * The one place a push is actually sent, and the only place a device is
 * written off (OPH-312, ADR-0038).
 *
 * ── IT DOES NOT THROW, AND THE ONE EXCEPTION IS DELIBERATE ────────────────
 *
 * A caller is a sweep on a timer. A push that fails must not take the sweep
 * down with it, so every delivery failure comes back as a RESULT — including a
 * sender that throws. The single thing that does throw is an invalid payload,
 * because that is a programming error rather than a delivery one: a body that
 * should never have been built must be loud, not counted (BLUEPRINT §8.3).
 *
 * ── A DEVICE IS WRITTEN OFF ONCE ──────────────────────────────────────────
 *
 * `gone` means the subscription is revoked or the app uninstalled, and it will
 * mean that forever. Marking `invalid_at` is what stops the next sweep from
 * asking again — and the device registry clears the mark the moment the same
 * install registers new credentials, which is the only thing that can honestly
 * undo it.
 */
export function createPushTransport({ db, senders, log }) {
  return {
    /**
     * Which providers this instance can actually reach. A caller that picks
     * its own recipients (the due sweep) has to know before it claims one:
     * claiming a device nobody can send to would burn the idempotency key for
     * an instant that never gets another attempt.
     */
    providers: Object.freeze(Object.keys(senders)),

    /**
     * @param {Array<object>} devices rows from `notification_devices`
     * @param {object} payload ids only — see payload.js
     * @returns {Promise<Array<{deviceId: string, outcome: string}>>}
     */
    async send(devices, payload) {
      assertPushPayload(payload);

      const results = [];
      for (const device of devices) {
        // Already written off. The registry, not the sender, brings it back.
        if (device.invalid_at) continue;
        const sender = senders[device.push_provider];
        if (!sender) continue;

        let result;
        try {
          result =
            device.push_provider === 'webpush'
              ? await sender.send(
                  {
                    endpoint: device.push_endpoint,
                    p256dh: device.push_p256dh,
                    auth: device.push_auth,
                  },
                  payload,
                )
              : // OPH-320: only the mobile lane is handed words. A browser
                // renders them itself from the cache the app wrote, which is
                // why the web still gets nothing but identifiers — and the
                // language is the DEVICE's, because a phone and a laptop on
                // one account can be set to different ones.
                await sender.send(
                  device.push_token,
                  payload,
                  alertTextFor(payload.alert, device.locale),
                );
        } catch (error) {
          // A sender is not supposed to throw; if one does, the sweep still
          // has other devices to reach.
          log?.error?.({ err: error, deviceId: device.id }, 'push sender threw');
          result = { outcome: 'failed', retryable: true, reason: error.message };
        }

        if (result.outcome === 'gone') {
          await db('notification_devices')
            .where({ id: device.id })
            .update({ invalid_at: new Date(), updated_at: new Date() });
        } else if (result.outcome === 'sent') {
          await db('notification_devices')
            .where({ id: device.id })
            .update({ last_push_at: new Date(), updated_at: new Date() });
        } else {
          log?.warn?.({ deviceId: device.id, reason: result.reason }, 'push failed');
        }

        results.push({ deviceId: device.id, ...result });
      }
      return results;
    },
  };
}
