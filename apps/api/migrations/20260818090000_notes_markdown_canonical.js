/**
 * OPH-274 (ADR-0033): markdown becomes a note's ONLY canonical content.
 *
 * ADR-0028 §1 split notes by intent — a note was either Delta-canonical (the
 * WYSIWYG wrote it) or markdown-canonical (it came from a file). That column
 * defaulted to 'delta' and touched zero rows, which was the whole reason
 * Option C beat "make markdown canonical everywhere".
 *
 * The rich editor is now gone, so the second half of the split has no writer.
 * This migration converts every Delta-canonical row — in `notes` AND in
 * `note_versions` — to markdown, and moves the column default with it.
 *
 * ## `note_versions` is not optional
 *
 * The three-way merge reads its BASE body out of `note_versions` by
 * `(note_id, note_revision)` and refuses to merge unless all three sides are
 * markdown (`db/notes.js` `threeWayNoteWrite`). Converting only `notes` would
 * leave every pre-existing version as a delta, so the first conflict against
 * any history older than this deploy would fall to `NOT_MARKDOWN` — the exact
 * failure Epic 25 was built to end.
 *
 * ## Nothing is destroyed
 *
 * `content_delta` is left in place. It is never written again, but it stays
 * readable: a lossless escape hatch if a conversion turns out wrong, and the
 * reason this migration does not need a lossy `down`.
 *
 * ## Why the converter is copied rather than imported
 *
 * Same rule as `20260817090000_backfill_markdown_plain_text.js`: a migration
 * must keep doing what it did on the day it ran. `src/lib/delta.js` still
 * exists (it normalizes writes from clients that have not updated yet) but it
 * will be deleted once those clients are gone, and this file must survive that.
 *
 * Migrations are append-only (AGENTS.md rule 8).
 */

import crypto from 'node:crypto';

const MAX_PLAIN_TEXT = 60000;
const PAGE = 500;

// Attachment embeds reference files by the app scheme (ADR-0011) — a stable
// id, never an expiring URL. The URI is PRESERVED through the conversion; only
// the label becomes the file's current name.
const FILE_EMBED_RE = /^alliswell:\/\/file\/([0-9A-HJKMNP-TV-Z]{26})$/;

/** File ids referenced by image/video embeds in a delta (unique, in order). */
function embedFileIds(ops) {
  if (!Array.isArray(ops)) return [];
  const ids = [];
  for (const op of ops) {
    const insert = op?.insert;
    if (insert === null || typeof insert !== 'object') continue;
    const source = typeof insert.image === 'string' ? insert.image : insert.video;
    const match = typeof source === 'string' ? source.match(FILE_EMBED_RE) : null;
    if (match && !ids.includes(match[1])) ids.push(match[1]);
  }
  return ids;
}

/** JSON column that may arrive as a string, depending on the driver. */
function parseDelta(value) {
  if (value == null) return null;
  if (typeof value === 'string') {
    try {
      return JSON.parse(value);
    } catch {
      return null;
    }
  }
  return value;
}

/** Quill Delta → Markdown, frozen at the shape it had on 2026-08-18. */
function deltaToMarkdown(ops, { embedLabel } = {}) {
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
    if (typeof insert !== 'string') {
      if (insert !== null && typeof insert === 'object') {
        const kind = typeof insert.image === 'string' ? 'image' : 'video';
        const source = kind === 'image' ? insert.image : insert.video;
        if (typeof source === 'string' && source.length > 0) {
          const label = embedLabel?.(source, kind) ?? null;
          buffer +=
            kind === 'image'
              ? `![${label ?? ''}](${source})`
              : `[${label ?? 'attachment'}](${source})`;
        }
      }
      continue;
    }
    const attrs = op.attributes;

    let remaining = insert;
    let idx = remaining.indexOf('\n');
    while (idx !== -1) {
      buffer += inline(remaining.slice(0, idx), attrs);
      closeLine(attrs);
      remaining = remaining.slice(idx + 1);
      idx = remaining.indexOf('\n');
    }
    if (remaining.length > 0) buffer += inline(remaining, attrs);
  }
  if (buffer.length > 0) closeLine(null);

  while (lines.length > 0 && lines.at(-1).trim() === '') lines.pop();
  return lines.join('\n');
}

/** Markdown → the words a person would search for, frozen at 2026-08-18. */
function markdownToPlainText(markdown) {
  if (typeof markdown !== 'string' || markdown === '') return '';
  return markdown
    .replace(/^```[\s\S]*?^```/gm, ' ')
    .replace(/^~~~[\s\S]*?^~~~/gm, ' ')
    .replace(/^---\n[\s\S]*?\n---\n/, ' ')
    .replace(/!\[[^\]]*\]\([^)]*\)/g, ' ')
    .replace(/\[([^\]]*)\]\([^)]*\)/g, '$1')
    .replace(/<[^>\s]+>/g, ' ')
    .replace(/`([^`]*)`/g, '$1')
    .replace(/^\s{0,3}#{1,6}\s+/gm, '')
    .replace(/^\s{0,3}>\s?/gm, '')
    .replace(/^\s*[-*+]\s+\[[ xX]\]\s+/gm, '')
    .replace(/^\s*[-*+]\s+/gm, '')
    .replace(/^\s*\d+[.)]\s+/gm, '')
    .replace(/^\s{0,3}([-*_])\s*(?:\1\s*){2,}$/gm, ' ')
    .replace(/\|/g, ' ')
    .replace(/(\*\*|__|~~|==)(.*?)\1/g, '$2')
    .replace(/(^|[^\w])[*_]([^*_\n]+)[*_]([^\w]|$)/g, '$1$2$3')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, MAX_PLAIN_TEXT);
}

/**
 * Resolves `alliswell://file/{id}` sources to the files' current names, for one
 * page of rows. Batched per page rather than per row: a page of 500 notes with
 * embeds would otherwise be 500 round trips.
 */
async function embedLabelsFor(knex, deltas) {
  const ids = [];
  for (const delta of deltas) {
    for (const id of embedFileIds(delta)) if (!ids.includes(id)) ids.push(id);
  }
  if (ids.length === 0) return undefined;
  const files = await knex('files').whereIn('id', ids).select('id', 'name');
  const names = new Map(files.map((f) => [`alliswell://file/${f.id}`, f.name]));
  return (source) => names.get(source) ?? null;
}

/**
 * The version digest, matching `db/note-versions.js` `contentHash` over the
 * post-ADR-0033 snapshot (delta slot empty, format 'markdown').
 *
 * Recomputed rather than left alone: the hash is what makes "identical bodies
 * do not stack" work (ADR-0031 §4). A converted row whose digest still
 * describes its Delta would never match the next capture, so the first edit
 * after this deploy would stack a duplicate version onto every note.
 */
function versionHash({ title, markdown }) {
  return crypto
    .createHash('sha256')
    .update([title ?? '', 'markdown', markdown ?? '', ''].join(' '))
    .digest('hex');
}

/**
 * Converts one table's Delta-canonical rows, oldest id first.
 *
 * Soft-deleted notes are converted too: a tombstone still syncs and can be
 * restored, and a restored note must not come back as the one row in the
 * database whose canonical field no longer has a writer.
 */
async function convertTable(knex, { table, withPlainText, withHash }) {
  const columns = ['id', 'content_delta', 'content_markdown'];
  if (withHash) columns.push('title');
  let after = '';
  let converted = 0;

  for (;;) {
    // Not filtered on `content_delta IS NOT NULL`: a note that was
    // Delta-canonical but never actually edited has a null delta, and leaving
    // it behind would strand the one row in the table whose format still names
    // a writer that no longer exists. Those rows keep whatever markdown they
    // had (usually none) and simply change format.
    const rows = await knex(table)
      .where('content_format', 'delta')
      .where('id', '>', after)
      .orderBy('id')
      .limit(PAGE)
      .select(columns);
    if (rows.length === 0) break;

    const deltas = rows.map((row) => parseDelta(row.content_delta));
    const embedLabel = await embedLabelsFor(knex, deltas.filter(Boolean));

    for (const [index, row] of rows.entries()) {
      const delta = deltas[index];
      // An unparseable delta keeps whatever markdown it already had rather than
      // becoming an empty note. The delta column is still there to inspect.
      const markdown = delta
        ? deltaToMarkdown(delta, { embedLabel })
        : (row.content_markdown ?? '');
      const patch = { content_markdown: markdown, content_format: 'markdown' };
      if (withPlainText) patch.plain_text = markdownToPlainText(markdown);
      if (withHash) patch.content_hash = versionHash({ title: row.title, markdown });
      await knex(table).where({ id: row.id }).update(patch);
      converted += 1;
    }
    after = rows[rows.length - 1].id;
  }
  return converted;
}

export async function up(knex) {
  const notes = await convertTable(knex, { table: 'notes', withPlainText: true });
  const versions = await convertTable(knex, { table: 'note_versions', withHash: true });

  // New notes are markdown from birth. The CHECK constraint deliberately still
  // ALLOWS 'delta': a client that has not updated yet keeps sending it, and the
  // write path normalizes rather than rejecting. A protocol that breaks its own
  // old clients is not a protocol.
  await knex.schema.alterTable('notes', (table) => {
    table.string('content_format', 16).notNullable().defaultTo('markdown').alter();
  });
  await knex.schema.alterTable('note_versions', (table) => {
    table.string('content_format', 16).defaultTo('markdown').alter();
  });

  // eslint-disable-next-line no-console
  console.log(`markdown-canonical: converted ${notes} note(s), ${versions} version(s)`);
}

export async function down(knex) {
  // Only the DEFAULT is restored. The converted rows are left as markdown on
  // purpose: flipping them back would re-point live notes at a `content_delta`
  // that has not been written since this migration ran, silently discarding
  // every edit made in between. The lossless escape hatch is that the delta
  // column was never cleared — a human can read it and decide.
  await knex.schema.alterTable('notes', (table) => {
    table.string('content_format', 16).notNullable().defaultTo('delta').alter();
  });
  await knex.schema.alterTable('note_versions', (table) => {
    table.string('content_format', 16).defaultTo('delta').alter();
  });
}
