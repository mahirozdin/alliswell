/**
 * OPH-013 — notes, note_tags, note_links (+ FULLTEXT search index).
 * Notes store Quill Delta JSON as canonical content, plus markdown export and
 * plain text for search (BLUEPRINT §9.1). note_links is polymorphic (§9.2).
 */

const CHARSET = 'utf8mb4';
const COLLATION = 'utf8mb4_0900_ai_ci';

function base(table) {
  table.charset(CHARSET);
  table.collate(COLLATION);
  table.specificType('id', 'char(26)').primary();
}

function timestamps(knex, table, { softDelete = true } = {}) {
  table.datetime('created_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));
  table.datetime('updated_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));
  if (softDelete) table.datetime('deleted_at', { precision: 3 }).nullable();
}

export async function up(knex) {
  await knex.schema.createTable('notes', (t) => {
    base(t);
    t.specificType('workspace_id', 'char(26)').notNullable();
    t.specificType('project_id', 'char(26)').nullable();
    t.specificType('created_from_task_id', 'char(26)').nullable();
    t.string('title', 500).notNullable();
    t.json('content_delta').nullable();
    t.specificType('content_markdown', 'mediumtext').nullable();
    t.specificType('plain_text', 'mediumtext').nullable();
    t.boolean('is_pinned').notNullable().defaultTo(false);
    t.boolean('is_archived').notNullable().defaultTo(false);
    t.specificType('created_by', 'char(26)').nullable();
    t.specificType('updated_by', 'char(26)').nullable();
    timestamps(knex, t);
    t.bigInteger('revision').notNullable().defaultTo(0);
    t.index(['workspace_id'], 'idx_notes_workspace');
    t.foreign('workspace_id', 'fk_notes_workspace').references('workspaces.id').onDelete('CASCADE');
    t.foreign('project_id', 'fk_notes_project').references('projects.id').onDelete('SET NULL');
    t.foreign('created_from_task_id', 'fk_notes_created_from_task')
      .references('tasks.id')
      .onDelete('SET NULL');
    t.foreign('created_by', 'fk_notes_created_by').references('users.id').onDelete('SET NULL');
    t.foreign('updated_by', 'fk_notes_updated_by').references('users.id').onDelete('SET NULL');
  });

  await knex.schema.createTable('note_tags', (t) => {
    t.charset(CHARSET);
    t.collate(COLLATION);
    t.specificType('note_id', 'char(26)').notNullable();
    t.specificType('tag_id', 'char(26)').notNullable();
    t.datetime('created_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));
    t.primary(['note_id', 'tag_id']);
    t.index(['tag_id'], 'idx_note_tags_tag');
    t.foreign('note_id', 'fk_note_tags_note').references('notes.id').onDelete('CASCADE');
    t.foreign('tag_id', 'fk_note_tags_tag').references('tags.id').onDelete('CASCADE');
  });

  // Polymorphic links: linked_entity_type ∈ task|project|tag|document|calendar_event (v2),
  // so no FK on the target — application-level integrity + periodic sweeps.
  await knex.schema.createTable('note_links', (t) => {
    base(t);
    t.specificType('note_id', 'char(26)').notNullable();
    t.string('linked_entity_type', 64).notNullable();
    t.specificType('linked_entity_id', 'char(26)').notNullable();
    t.datetime('created_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));
    t.unique(['note_id', 'linked_entity_type', 'linked_entity_id'], {
      indexName: 'uq_note_link',
    });
    t.index(['linked_entity_type', 'linked_entity_id'], 'idx_note_links_entity');
    t.foreign('note_id', 'fk_note_links_note').references('notes.id').onDelete('CASCADE');
  });

  await knex.raw('ALTER TABLE notes ADD FULLTEXT INDEX ft_notes_plain_text (title, plain_text)');
}

export async function down(knex) {
  await knex.schema.dropTableIfExists('note_links');
  await knex.schema.dropTableIfExists('note_tags');
  await knex.schema.dropTableIfExists('notes');
}
