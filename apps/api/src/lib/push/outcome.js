/**
 * What a push service's answer means (OPH-312).
 *
 * Three outcomes, and the distinction that matters is not success versus
 * failure — it is **gone** versus **try again**. A subscription the user
 * revoked answers 404 or 410 forever; retrying it every sweep is how a delivery
 * log fills with noise that buries the failures worth reading, so `gone` is what
 * writes the device off. A 429 or a 503 is the push service having a moment and
 * means nothing about the device.
 *
 * @typedef {{outcome: 'sent'|'gone'|'failed', retryable?: boolean, reason?: string}} PushOutcome
 */

/** @param {number} status @returns {PushOutcome} */
export function classifyPushStatus(status) {
  if (status >= 200 && status < 300) return { outcome: 'sent' };
  // RFC 8030: the subscription no longer exists. Also what a browser answers
  // after the user clears site data or revokes permission.
  if (status === 404 || status === 410) return { outcome: 'gone' };
  if (status === 429 || status >= 500) {
    return { outcome: 'failed', retryable: true, reason: `HTTP ${status}` };
  }
  // 400/401/403: our request or our credentials. Sending it again unchanged
  // produces the same answer, and the operator needs to see it in the log.
  return { outcome: 'failed', retryable: false, reason: `HTTP ${status}` };
}
