/**
 * OPH-267 — note history (ADR-0031, round 18 finding #4).
 *
 * The table that was missing: `sync_revisions` records WHICH fields changed,
 * never what they held, so an overwritten body was gone. Every accepted
 * content-changing write now leaves a snapshot here.
 *
 * All THREE content fields plus the format, on purpose (ADR-0031 §5): which
 * field is canonical is the document's identity (ADR-0028 §1), and a version
 * that kept only "the body" would restore a markdown note as rich text.
 *
 * `content_hash` is what keeps an idle autosave from stacking identical rows,
 * and `(note_id, created_at)` is the coalescing lookup — "is the newest row for
 * this note still within the rolling-head window?" — as well as the history
 * screen's own query.
 *
 * No `deleted_at`: a version is either kept or swept (ADR-0031 §6), and
 * deleting the note takes its history with it (CASCADE) — history is part of
 * the note, not a shadow that outlives it.
 *
 * Migrations are append-only (AGENTS.md rule 8).
 */

import { CHARSET, PREFERRED_COLLATION, resolveCollation } from '../src/db/collation.js';

let COLLATION = PREFERRED_COLLATION;

export async function up(knex) {
  COLLATION = await resolveCollation(knex);

  await knex.schema.createTable('note_versions', (t) => {
    t.charset(CHARSET);
    t.collate(COLLATION);
    t.specificType('id', 'char(26)').primary();
    t.specificType('workspace_id', 'char(26)').notNullable();
    t.specificType('note_id', 'char(26)').notNullable();
    // The note revision this snapshot captured — the join back to
    // `sync_revisions` when someone asks "which sync write was this?".
    t.bigInteger('note_revision').notNullable().defaultTo(0);

    t.string('title', 500).notNullable().defaultTo('');
    t.json('content_delta').nullable();
    t.text('content_markdown', 'mediumtext').nullable();
    t.string('content_format', 16).notNullable().defaultTo('delta');

    // Who/what produced this write. The seam the rest of Epic 25 hangs on:
    // OPH-268 writes `conflict`/`merge`, restore writes `restore`, bulk import
    // writes `import`, an API key writes `api`, an MCP tool writes `mcp`.
    t.string('origin', 16).notNullable().defaultTo('edit');
    // Which client sent it — the coalescing key, and how the UI can say
    // "this device".
    t.specificType('client_id', 'char(26)').nullable();
    t.specificType('created_by', 'char(26)').nullable();
    // SHA-256 of title + format + both bodies: identical content never stacks.
    t.specificType('content_hash', 'char(64)').notNullable();
    t.datetime('created_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));

    // The history screen (newest first) and the coalescing lookup.
    t.index(['note_id', 'created_at'], 'idx_note_versions_note_created');
    // "Which snapshot belongs to that sync revision?"
    t.index(['note_id', 'note_revision'], 'idx_note_versions_note_revision');
    // The retention sweep walks a workspace's oldest rows.
    t.index(['workspace_id', 'created_at'], 'idx_note_versions_workspace_created');
    t.foreign('note_id', 'fk_note_versions_note').references('notes.id').onDelete('CASCADE');
    t.foreign('workspace_id', 'fk_note_versions_workspace')
      .references('workspaces.id')
      .onDelete('CASCADE');
  });
}

export async function down(knex) {
  await knex.schema.dropTableIfExists('note_versions');
}
