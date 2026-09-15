import { isUlid } from '../ids.js';

/**
 * The push payload contract (OPH-308, BLUEPRINT §8.3, ADR-0038).
 *
 * ── WHY THIS FILE IS THE ONLY PLACE A PUSH BODY IS BUILT ──────────────────
 *
 * A push crosses Google's, Apple's or Mozilla's servers before it reaches the
 * device. `docs/PRIVACY.md` promises that a task's title and contents never
 * make that trip, and the promise is only as good as the narrowest point the
 * data passes through. So there is exactly one such point: every transport
 * takes a payload from a builder here and calls `assertPushPayload` before it
 * sends. A body assembled anywhere else has no way in.
 *
 * ── WHAT A PAYLOAD MAY SAY ────────────────────────────────────────────────
 *
 * Identifiers, a protocol version, an instant, and — for a push the user is
 * meant to SEE — the *name* of a fixed message rather than the message. The
 * device already has the text: it pulled the reminder row. What the wire
 * carries is which row, not what it says.
 *
 * Amended by OPH-320 for one lane: a force-quit phone has no running code to
 * look a name up with, so APNs and FCM are handed the sentence itself — from
 * [PUSH_ALERT_TEXT] below, which is a closed catalogue of strings identical
 * for every user, never anything a task says. The payload proper is unchanged;
 * the words travel beside it, and the gate reads both.
 *
 * ── AND WHY THE VALUES ARE CHECKED, NOT ONLY THE KEYS ─────────────────────
 *
 * The obvious leak is a new key called `title`. The quiet one is a known key
 * holding prose — `taskId: 'Ameliyat sonucu'` passes any key-set check ever
 * written. So ids must be ULID-shaped, the instant must be an ISO instant, and
 * `alert` must be one of a closed set of identifiers. A field that cannot hold
 * a sentence cannot leak one.
 *
 * ── THE BUILDERS IGNORE WHAT THEY ARE NOT ALLOWED TO SEND ─────────────────
 *
 * Deliberately a pick, not a rejection. Real call sites spread a database row
 * into these functions; a builder that threw on every extra key would be
 * annoying enough that somebody would eventually assemble a body by hand, and
 * a hand-built body is the one thing this file exists to prevent. Making the
 * safe path the easy path is the point.
 */

export const PUSH_PROTOCOL_VERSION = 1;

/**
 * The fixed messages a VISIBLE push may name. Not text — an identifier the
 * device (or the transport, from its own table) resolves into a localised
 * constant. Adding one is a deliberate act: `npm run check:push-payload`
 * fails until the allowlist is regenerated, and the diff says what was added.
 */
export const PUSH_ALERT_IDS = Object.freeze(['reminder_due']);

/**
 * The words a VISIBLE push may carry, and the only words that exist (OPH-320).
 *
 * ── WHY THERE ARE WORDS HERE AT ALL ───────────────────────────────────────
 *
 * The payload names a row and the device looks the sentence up — that is the
 * web's story, and the service worker can do it because a browser tab has a
 * cache the app wrote. A force-quit iPhone has no such moment: APNs must
 * render the alert itself, from what the push carries, or nothing appears. The
 * guaranteed half of Epic 30 is the one that works with the app not running,
 * so a fixed sentence crosses the wire on the mobile lane.
 *
 * ── WHAT THAT DOES AND DOES NOT GIVE AWAY ─────────────────────────────────
 *
 * These strings are identical for every user of every instance. They say that
 * somebody has a reminder due — which the existence of the push already says —
 * and nothing about WHICH reminder, whose, or what it concerns. The sentence
 * `docs/PRIVACY.md` prints is unchanged: a task's title and contents still
 * never reach a push service.
 *
 * ── AND WHY THE SERVER PICKS THE LANGUAGE ─────────────────────────────────
 *
 * APNs and FCM can both render a LOCALISATION KEY instead of a sentence
 * (`loc-key`, `body_loc_key`), which would keep even this off the wire. It
 * resolves against the app bundle's strings in the DEVICE'S OS language, and
 * AllisWell's language is an in-app setting that a phone in English may well
 * be running in Turkish. `notification_devices.locale` exists precisely
 * because that difference is real (OPH-309), and a reminder that arrives in a
 * language the user did not choose is a worse failure than a public sentence.
 *
 * Adding or changing a string here is a deliberate act: `npm run
 * check:push-payload` fails until the allowlist is regenerated, and the diff
 * shows a human exactly which words started crossing a push provider.
 */
export const PUSH_ALERT_TEXT = Object.freeze({
  reminder_due: Object.freeze({
    en: Object.freeze({ title: 'AllisWell', body: 'You have 1 reminder' }),
    tr: Object.freeze({ title: 'AllisWell', body: '1 hatırlatıcın var' }),
  }),
});

/** The language this catalogue answers in when it has nothing better. */
export const PUSH_ALERT_FALLBACK_LOCALE = 'en';

/**
 * The sentence for one alert in one language, or `null` when the alert names
 * no visible text (a wake-up hint has none by design).
 *
 * `tr-TR`, `tr`, and a device that never said all resolve to the same entry —
 * the catalogue is keyed by LANGUAGE, because a fixed sentence has no regional
 * variants and pretending otherwise would multiply the policy file by every
 * locale tag a browser can invent.
 *
 * @param {string|undefined} alertId one of [PUSH_ALERT_IDS]
 * @param {string|null|undefined} locale a BCP-47 tag, or null
 */
export function alertTextFor(alertId, locale) {
  const entry = PUSH_ALERT_TEXT[alertId];
  if (!entry) return null;
  const language = String(locale ?? '')
    .trim()
    .toLowerCase()
    .split(/[-_]/)[0];
  return entry[language] ?? entry[PUSH_ALERT_FALLBACK_LOCALE];
}

/**
 * Every key each payload type may carry. `required` is what the device needs
 * to act; anything outside `all` is refused.
 */
export const PUSH_PAYLOAD_KEYS = Object.freeze({
  wake: Object.freeze(['v', 'type']),
  reminder: Object.freeze(['v', 'type', 'reminderId', 'taskId', 'fireAt', 'alert']),
});

const REQUIRED_KEYS = Object.freeze({
  wake: Object.freeze(['v', 'type']),
  reminder: Object.freeze(['v', 'type', 'reminderId', 'taskId', 'fireAt']),
});

/** `2026-09-20T07:30:00.000Z` — an instant, not a date a human typed. */
const ISO_INSTANT_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$/;

export class PushPayloadError extends Error {
  constructor(message) {
    super(message);
    this.name = 'PushPayloadError';
    this.code = 'PUSH_PAYLOAD_INVALID';
  }
}

const VALUE_CHECKS = {
  v: (value) => value === PUSH_PROTOCOL_VERSION,
  type: (value) => Object.hasOwn(PUSH_PAYLOAD_KEYS, value),
  reminderId: isUlid,
  taskId: isUlid,
  fireAt: (value) => typeof value === 'string' && ISO_INSTANT_RE.test(value),
  alert: (value) => PUSH_ALERT_IDS.includes(value),
};

/**
 * Throws unless `payload` is something this contract allows on the wire.
 * Every transport calls this last, so a payload that reached it another way
 * still cannot be sent.
 *
 * @param {unknown} payload
 * @returns {object} the same payload, so it can be used inline
 */
export function assertPushPayload(payload) {
  if (payload === null || typeof payload !== 'object' || Array.isArray(payload)) {
    throw new PushPayloadError('a push payload must be a plain object');
  }

  const { type } = payload;
  const allowed = PUSH_PAYLOAD_KEYS[type];
  if (!allowed) {
    throw new PushPayloadError(`unknown push payload type: ${JSON.stringify(type)}`);
  }

  const unknown = Object.keys(payload).filter((key) => !allowed.includes(key));
  if (unknown.length > 0) {
    throw new PushPayloadError(
      `push payload carries ${unknown.join(', ')}, which the contract does not declare — ` +
        'task content must never cross a push provider (BLUEPRINT §8.3)',
    );
  }

  const missing = REQUIRED_KEYS[type].filter((key) => !Object.hasOwn(payload, key));
  if (missing.length > 0) {
    throw new PushPayloadError(`push payload is missing ${missing.join(', ')}`);
  }

  for (const [key, value] of Object.entries(payload)) {
    if (VALUE_CHECKS[key](value)) continue;
    throw new PushPayloadError(
      `push payload ${key} is not a value this contract allows — ` +
        'a field that can hold a sentence can leak one',
    );
  }

  return payload;
}

/**
 * "Something changed, sync." Carries no idea what changed, because the device
 * is about to find out for itself and nothing else needs to cross the wire.
 */
export function buildWakePayload() {
  return assertPushPayload({ v: PUSH_PROTOCOL_VERSION, type: 'wake' });
}

/**
 * Names one reminder. `alert` turns it into a push the user sees; without it
 * the device is being woken to schedule the alarm itself.
 *
 * @param {{reminderId: string, taskId: string, fireAt: string, alert?: string}} input
 */
export function buildReminderPayload({ reminderId, taskId, fireAt, alert } = {}) {
  const payload = { v: PUSH_PROTOCOL_VERSION, type: 'reminder', reminderId, taskId, fireAt };
  if (alert !== undefined) payload.alert = alert;
  return assertPushPayload(payload);
}
