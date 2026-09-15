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
