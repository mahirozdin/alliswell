/**
 * OPH-261: give markdown-canonical notes the search column they never had.
 *
 * `plain_text` feeds the FULLTEXT index, the REST `?q=` filter and the MCP
 * `search`/`get_note` tools. Until this round it was written in exactly one
 * place — the branch that handles an incoming Quill delta — so a note that
 * ADR-0028 made markdown-canonical carried an empty or stale value from the
 * day it was converted. The note existed, was synced, was exported, and could
 * not be found. §22's reachability rule, seen from the search side.
 *
 * The code fix (both write paths derive from whichever field is canonical)
 * only helps a note that is written again. This backfills the ones already
 * sitting there.
 *
 * Scope is deliberately narrow: only rows whose canonical field IS markdown.
 * Delta notes are already correct and must not be touched — their `plain_text`
 * comes from the delta, and re-deriving it from the generated markdown would
 * rewrite a correct column with a worse one.
 *
 * Derivation is duplicated here rather than imported: a migration must keep
 * doing what it did on the day it ran, and `markdownToPlainText` will keep
 * evolving with the renderer. The parity that matters is with the value the
 * app writes NEXT time — and the next write overwrites this one anyway.
 *
 * Migrations are append-only (AGENTS.md rule 8).
 */
const MAX_PLAIN_TEXT = 60000;

function toPlainText(markdown) {
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

export async function up(knex) {
  // Paged rather than one UPDATE…SELECT: the derivation is JS, and a workspace
  // with many converted notes should not hold one long transaction open.
  const PAGE = 500;
  let after = '';
  let updated = 0;

  for (;;) {
    const rows = await knex('notes')
      .where('content_format', 'markdown')
      .whereNull('deleted_at')
      .whereNotNull('content_markdown')
      .where('id', '>', after)
      .orderBy('id')
      .limit(PAGE)
      .select('id', 'content_markdown', 'plain_text');
    if (rows.length === 0) break;

    for (const row of rows) {
      const next = toPlainText(row.content_markdown);
      // Only when it actually differs — an unchanged row is a wasted write and
      // an unnecessary `updated_at` bump on a table clients watch.
      if (next !== (row.plain_text ?? '')) {
        await knex('notes').where({ id: row.id }).update({ plain_text: next });
        updated += 1;
      }
    }
    after = rows[rows.length - 1].id;
  }

  if (updated > 0) {
    // eslint-disable-next-line no-console
    console.log(`backfilled plain_text for ${updated} markdown-canonical note(s)`);
  }
}

export async function down() {
  // Nothing to undo: this only repaired a derived column, and the value it
  // replaced was empty or stale. Restoring that would restore the defect.
}
