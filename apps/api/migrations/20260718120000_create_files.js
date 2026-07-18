/**
 * OPH-151 — file attachments metadata (Epic 14, ATTACHMENTS.md §3, ADR-0011).
 *
 * Bytes live in S3-compatible object storage (R2); this table is the canonical
 * metadata + authorization record. One polymorphic shape serves all three
 * attachment homes (`target_type` project|task|note) so the project "Files"
 * tab is a query, not a join table.
 *
 * `storage_key` is OPAQUE (`ws/{workspaceId}/{fileId}`) — no filename inside,
 * so rename is a pure metadata update and keys leak nothing. `target_id` has
 * no FK on purpose (polymorphic); the API validates the target at upload-init.
 * Rows are born `status='uploading'` and INVISIBLE to sync; only `ready` rows
 * (verified against the store) are published. Migrations are append-only
 * (AGENTS.md rule 8).
 */

const CHARSET = 'utf8mb4';
const COLLATION = 'utf8mb4_0900_ai_ci';

export async function up(knex) {
  await knex.schema.createTable('files', (t) => {
    t.charset(CHARSET);
    t.collate(COLLATION);
    t.specificType('id', 'char(26)').primary();
    t.specificType('workspace_id', 'char(26)').notNullable();
    t.enu('target_type', ['project', 'task', 'note']).notNullable();
    t.specificType('target_id', 'char(26)').notNullable();
    t.specificType('uploaded_by', 'char(26)').nullable();

    t.string('name', 255).notNullable();
    t.string('mime', 255).notNullable().defaultTo('application/octet-stream');
    t.bigInteger('size_bytes').unsigned().notNullable();
    t.string('storage_key', 300).notNullable();
    t.enu('status', ['uploading', 'ready']).notNullable().defaultTo('uploading');

    t.bigInteger('revision').notNullable().defaultTo(0);
    t.datetime('created_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));
    t.datetime('updated_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));
    t.datetime('deleted_at', { precision: 3 }).nullable();

    t.unique(['storage_key'], { indexName: 'uq_files_storage_key' });
    // Attachment lists ask "what hangs off this entity".
    t.index(['workspace_id', 'target_type', 'target_id'], 'idx_files_workspace_target');
    // The stale-upload sweep asks "which uploads never completed".
    t.index(['status', 'created_at'], 'idx_files_status_created');
    t.foreign('workspace_id', 'fk_files_workspace').references('workspaces.id').onDelete('CASCADE');
  });
}

export async function down(knex) {
  await knex.schema.dropTableIfExists('files');
}
