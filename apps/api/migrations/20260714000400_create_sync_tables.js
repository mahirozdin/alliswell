/**
 * OPH-014 — sync_revisions (workspace-scoped monotonic change log, BLUEPRINT §6.2)
 * and client_mutations (idempotency store for offline push, §6.3).
 * Append-heavy log tables: indexes kept minimal on purpose (ADR-0004 §5).
 */

const CHARSET = 'utf8mb4';
const COLLATION = 'utf8mb4_0900_ai_ci';

export async function up(knex) {
  await knex.schema.createTable('sync_revisions', (t) => {
    t.charset(CHARSET);
    t.collate(COLLATION);
    t.specificType('id', 'char(26)').primary();
    t.specificType('workspace_id', 'char(26)').notNullable();
    t.bigInteger('revision').notNullable();
    t.string('entity_type', 64).notNullable();
    t.specificType('entity_id', 'char(26)').notNullable();
    t.enu('operation', ['create', 'update', 'delete']).notNullable();
    t.json('changed_fields').nullable();
    t.datetime('created_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));
    t.unique(['workspace_id', 'revision'], { indexName: 'uq_workspace_revision' });
    t.index(['entity_type', 'entity_id'], 'idx_entity');
    t.foreign('workspace_id', 'fk_sync_revisions_workspace')
      .references('workspaces.id')
      .onDelete('CASCADE');
  });

  await knex.schema.createTable('client_mutations', (t) => {
    t.charset(CHARSET);
    t.collate(COLLATION);
    t.specificType('id', 'char(26)').primary();
    t.specificType('workspace_id', 'char(26)').notNullable();
    t.specificType('user_id', 'char(26)').nullable();
    t.specificType('client_id', 'char(26)').notNullable();
    t.specificType('client_mutation_id', 'char(26)').notNullable();
    t.string('entity_type', 64).notNullable();
    t.specificType('entity_id', 'char(26)').notNullable();
    t.enu('operation', ['create', 'update', 'delete']).notNullable();
    t.enu('status', ['applied', 'conflict', 'rejected']).notNullable();
    t.bigInteger('result_revision').nullable();
    t.string('error_code', 64).nullable();
    t.datetime('created_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));
    t.unique(['client_id', 'client_mutation_id'], { indexName: 'uq_client_mutation' });
    t.index(['workspace_id'], 'idx_client_mutations_workspace');
    t.foreign('workspace_id', 'fk_client_mutations_workspace')
      .references('workspaces.id')
      .onDelete('CASCADE');
    t.foreign('user_id', 'fk_client_mutations_user').references('users.id').onDelete('SET NULL');
  });
}

export async function down(knex) {
  await knex.schema.dropTableIfExists('client_mutations');
  await knex.schema.dropTableIfExists('sync_revisions');
}
