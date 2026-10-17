/**
 * OPH-371 — the import ledger: which item of which export already came in.
 *
 * Importing the same Todoist or TickTick file twice must not duplicate
 * anything (ADR-0052). One row per imported thing, keyed by
 * `(workspace_id, source, external_key)`:
 *
 *   • `external_key` is a sha256 hex of the source's own identity — TickTick's
 *     taskId, or for Todoist (whose CSV has no ids) a fingerprint of project,
 *     section, title and occurrence index. Hashed so the key length is fixed
 *     and no task title is stored twice.
 *   • `source` is VARCHAR, not ENUM: the code constant IMPORT_SOURCES
 *     (src/lib/importers/index.js) is the vocabulary, pinned by a test, and a
 *     third source needs no ALTER.
 *   • The UNIQUE index is the idempotency AND the race guard: the writer
 *     inserts the ledger row first, in the same transaction as the entity, so
 *     two identical requests at once leave one row and one task.
 *   • `entity_id` is kept even after the entity is deleted — a re-import
 *     never brings back what the user removed.
 *
 * Server-only: not a synced entity, no revision, nothing on the clients.
 * Workspace FK cascades, so account deletion purges it (db/accounts.js).
 *
 * Migrations are append-only (AGENTS.md rule 8).
 */

import { CHARSET, PREFERRED_COLLATION, resolveCollation } from '../src/db/collation.js';

let COLLATION = PREFERRED_COLLATION;

export async function up(knex) {
  COLLATION = await resolveCollation(knex);

  await knex.schema.createTable('import_ledger', (t) => {
    t.charset(CHARSET);
    t.collate(COLLATION);
    t.specificType('id', 'char(26)').primary();
    t.specificType('workspace_id', 'char(26)').notNullable();
    t.string('source', 16).notNullable();
    t.specificType('external_key', 'char(64)').notNullable();
    // 'project' | 'task' | 'task_series' | 'note'
    t.string('entity_type', 16).notNullable();
    t.specificType('entity_id', 'char(26)').nullable();
    t.specificType('created_by', 'char(26)').nullable();
    t.datetime('created_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));

    t.unique(['workspace_id', 'source', 'external_key'], { indexName: 'uq_import_ledger_key' });
    t.foreign('workspace_id', 'fk_import_ledger_workspace')
      .references('workspaces.id')
      .onDelete('CASCADE');
  });
}

export async function down(knex) {
  await knex.schema.dropTableIfExists('import_ledger');
}
