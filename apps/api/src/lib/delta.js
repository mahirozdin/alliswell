/**
 * Quill Delta helpers (BLUEPRINT §9.1). The delta is the canonical note
 * content; plain text is derived server-side so FULLTEXT search always
 * matches what was actually saved.
 */

const MAX_PLAIN_TEXT = 60000;

/**
 * Extracts searchable plain text from a Quill Delta ops array. String inserts
 * are concatenated; embeds (images, etc.) are skipped; whitespace collapses.
 *
 * @param {Array<{ insert?: unknown }>|null|undefined} ops
 * @returns {string}
 */
export function deltaToPlainText(ops) {
  if (!Array.isArray(ops)) return '';
  let text = '';
  for (const op of ops) {
    if (typeof op?.insert === 'string') text += op.insert;
  }
  return text.replace(/\s+/g, ' ').trim().slice(0, MAX_PLAIN_TEXT);
}

/** A structurally valid ops array: objects whose `insert` is string or object. */
export function isValidDelta(ops) {
  return (
    Array.isArray(ops) &&
    ops.every(
      (op) =>
        op !== null &&
        typeof op === 'object' &&
        'insert' in op &&
        (typeof op.insert === 'string' || typeof op.insert === 'object'),
    )
  );
}
