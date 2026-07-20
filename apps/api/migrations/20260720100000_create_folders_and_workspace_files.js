/**
 * OPH-169 — folders + standalone workspace files (round 8, ATTACHMENTS.md §14,
 * ADR-0014).
 *
 * `folders` organizes ONLY workspace-target files (the global "Dosyalar"
 * section's Klasörlerim layer). Attached files (project|task|note) never
 * enter folders — their lifecycle belongs to their owner entity. Folders are
 * a PUSH-PULL sync entity (pure metadata, offline-safe), hence
 * revision + deleted_at like project/tag.
 *
 * `files.target_type` grows `workspace` (target_id = the workspace id) and
 * files gain a nullable `folder_id` — only meaningful on workspace-target
 * rows; the API enforces that (no FK on folder_id: a folder tombstone must
 * not block the file tombstones written in the same cascade transaction).
 *
 * Root-level name uniqueness note: the unique index cannot cover
 * parent_id = NULL rows (MySQL allows duplicate NULLs), so the API guards
 * names at EVERY level itself; the index still hardens non-root levels
 * against races. Migrations are append-only (AGENTS.md rule 8).
 */

const CHARSET = 'utf8mb4';
const COLLATION = 'utf8mb4_0900_ai_ci';

export async function up(knex) {
  await knex.schema.createTable('folders', (t) => {
    t.charset(CHARSET);
    t.collate(COLLATION);
    t.specificType('id', 'char(26)').primary();
    t.specificType('workspace_id', 'char(26)').notNullable();
    t.specificType('parent_id', 'char(26)').nullable();
    t.string('name', 255).notNullable();

    t.bigInteger('revision').notNullable().defaultTo(0);
    t.datetime('created_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));
    t.datetime('updated_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));
    t.datetime('deleted_at', { precision: 3 }).nullable();

    t.unique(['workspace_id', 'parent_id', 'name'], {
      indexName: 'uq_folders_workspace_parent_name',
    });
    t.index(['workspace_id', 'parent_id'], 'idx_folders_workspace_parent');
    t.foreign('workspace_id', 'fk_folders_workspace')
      .references('workspaces.id')
      .onDelete('CASCADE');
    t.foreign('parent_id', 'fk_folders_parent').references('folders.id').onDelete('CASCADE');
  });

  // MySQL 8: appending an enum member in place is safe (no row rewrite).
  await knex.schema.raw(
    "ALTER TABLE files MODIFY COLUMN target_type ENUM('project','task','note','workspace') NOT NULL",
  );
  await knex.schema.alterTable('files', (t) => {
    t.specificType('folder_id', 'char(26)').nullable();
    t.index(['workspace_id', 'folder_id'], 'idx_files_workspace_folder');
  });
}

export async function down(knex) {
  await knex.schema.alterTable('files', (t) => {
    t.dropIndex(['workspace_id', 'folder_id'], 'idx_files_workspace_folder');
    t.dropColumn('folder_id');
  });
  // Workspace-target rows would violate the narrowed enum — they exist only
  // if the feature was used; a rollback drops them (their objects are already
  // subject to the GC sweep).
  await knex('files').where({ target_type: 'workspace' }).delete();
  await knex.schema.raw(
    "ALTER TABLE files MODIFY COLUMN target_type ENUM('project','task','note') NOT NULL",
  );
  await knex.schema.dropTableIfExists('folders');
}
