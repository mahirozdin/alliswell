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

/**
 * Canonical Quill Delta → Markdown converter (OPH-045). Mirrors the client
 * converter (apps/app/lib/src/features/notes/data/delta_markdown.dart) so an
 * offline preview and a server export produce identical documents. Covers what
 * our toolbar can produce: headers, bold/italic/strike/code, links,
 * bullet/ordered/checked lists, blockquote and code blocks.
 *
 * @param {Array<{ insert?: unknown, attributes?: Record<string, unknown> }>|null|undefined} ops
 * @returns {string}
 */
export function deltaToMarkdown(ops) {
  if (!Array.isArray(ops)) return '';
  const lines = [];
  let buffer = '';

  const inline = (text, attrs) => {
    if (!attrs) return text;
    let out = text;
    if (attrs.code === true) out = `\`${out}\``;
    if (attrs.bold === true) out = `**${out}**`;
    if (attrs.italic === true) out = `_${out}_`;
    if (attrs.strike === true) out = `~~${out}~~`;
    if (typeof attrs.link === 'string' && attrs.link.length > 0) out = `[${out}](${attrs.link})`;
    return out;
  };

  const closeLine = (lineAttributes) => {
    const text = buffer;
    buffer = '';
    const attrs = lineAttributes ?? {};

    if (attrs['code-block'] != null && attrs['code-block'] !== false) {
      // Merge consecutive code lines into one fenced block.
      if (lines.at(-1) === '```') {
        lines.pop();
        lines.push(text, '```');
      } else {
        lines.push('```', text, '```');
      }
      return;
    }

    const header = attrs.header;
    if (Number.isInteger(header) && header >= 1 && header <= 6) {
      lines.push(`${'#'.repeat(header)} ${text}`);
      return;
    }
    if (attrs.blockquote === true) {
      lines.push(`> ${text}`);
      return;
    }
    switch (attrs.list) {
      case 'bullet':
        lines.push(`- ${text}`);
        return;
      case 'ordered':
        lines.push(`1. ${text}`);
        return;
      case 'checked':
        lines.push(`- [x] ${text}`);
        return;
      case 'unchecked':
        lines.push(`- [ ] ${text}`);
        return;
    }
    lines.push(text);
  };

  for (const op of ops) {
    const insert = op?.insert;
    if (typeof insert !== 'string') continue; // embeds are dropped in markdown export
    const attrs = op.attributes;

    let remaining = insert;
    let idx = remaining.indexOf('\n');
    while (idx !== -1) {
      buffer += inline(remaining.slice(0, idx), attrs);
      // In Quill deltas the newline op carries the LINE's block attributes.
      closeLine(attrs);
      remaining = remaining.slice(idx + 1);
      idx = remaining.indexOf('\n');
    }
    if (remaining.length > 0) buffer += inline(remaining, attrs);
  }
  if (buffer.length > 0) closeLine(null);

  // Collapse the trailing empty line Quill documents always end with.
  while (lines.length > 0 && lines.at(-1).trim() === '') lines.pop();
  return lines.join('\n');
}
