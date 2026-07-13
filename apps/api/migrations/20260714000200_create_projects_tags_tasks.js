/**
 * OPH-012 — projects, tags, tasks, task_tags, checklist_items (+ FULLTEXT search index).
 * Schema per BLUEPRINT §10.2/§10.3; additions per ADR-0004 (sort_order, actual_minutes,
 * snoozed_until). Migrations are append-only.
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

function audit(table) {
  table.specificType('created_by', 'char(26)').nullable();
  table.specificType('updated_by', 'char(26)').nullable();
}

export async function up(knex) {
  await knex.schema.createTable('projects', (t) => {
    base(t);
    t.specificType('workspace_id', 'char(26)').notNullable();
    t.string('name', 255).notNullable();
    t.text('description').nullable();
    t.specificType('color_rgb', 'char(7)').notNullable().defaultTo('#2563EB');
    t.string('icon', 64).nullable();
    t.enu('status', ['active', 'paused', 'completed', 'archived'])
      .notNullable()
      .defaultTo('active');
    t.datetime('start_at', { precision: 3 }).nullable();
    t.datetime('due_at', { precision: 3 }).nullable();
    t.integer('sort_order').notNullable().defaultTo(0);
    t.boolean('is_favorite').notNullable().defaultTo(false);
    audit(t);
    timestamps(knex, t);
    t.bigInteger('revision').notNullable().defaultTo(0);
    t.index(['workspace_id', 'status'], 'idx_projects_status');
    t.foreign('workspace_id', 'fk_projects_workspace')
      .references('workspaces.id')
      .onDelete('CASCADE');
    t.foreign('created_by', 'fk_projects_created_by').references('users.id').onDelete('SET NULL');
    t.foreign('updated_by', 'fk_projects_updated_by').references('users.id').onDelete('SET NULL');
  });

  await knex.schema.createTable('tags', (t) => {
    base(t);
    t.specificType('workspace_id', 'char(26)').notNullable();
    t.string('name', 100).notNullable();
    t.string('slug', 120).notNullable();
    t.specificType('color_rgb', 'char(7)').notNullable().defaultTo('#64748B');
    t.string('icon', 64).nullable();
    timestamps(knex, t);
    t.bigInteger('revision').notNullable().defaultTo(0);
    t.unique(['workspace_id', 'slug'], { indexName: 'uq_tags_workspace_slug' });
    t.foreign('workspace_id', 'fk_tags_workspace').references('workspaces.id').onDelete('CASCADE');
  });

  await knex.schema.createTable('tasks', (t) => {
    base(t);
    t.specificType('workspace_id', 'char(26)').notNullable();
    t.specificType('project_id', 'char(26)').nullable();
    t.specificType('parent_task_id', 'char(26)').nullable();
    t.string('title', 500).notNullable();
    t.text('description').nullable();
    t.enu('status', [
      'inbox',
      'open',
      'scheduled',
      'in_progress',
      'waiting',
      'completed',
      'cancelled',
      'archived',
    ])
      .notNullable()
      .defaultTo('open');
    t.enu('priority', ['none', 'low', 'medium', 'high', 'urgent']).notNullable().defaultTo('none');
    t.specificType('color_rgb', 'char(7)').nullable();
    t.datetime('start_at', { precision: 3 }).nullable();
    t.datetime('due_at', { precision: 3 }).nullable();
    t.datetime('scheduled_start_at', { precision: 3 }).nullable();
    t.datetime('scheduled_end_at', { precision: 3 }).nullable();
    t.datetime('remind_at', { precision: 3 }).nullable();
    t.datetime('snoozed_until', { precision: 3 }).nullable();
    t.string('timezone', 64).notNullable().defaultTo('Europe/Istanbul');
    t.boolean('is_urgent').notNullable().defaultTo(false);
    t.boolean('requires_acknowledgement').notNullable().defaultTo(false);
    t.text('repeat_rule').nullable();
    t.integer('estimated_minutes').nullable();
    t.integer('actual_minutes').nullable();
    t.integer('sort_order').notNullable().defaultTo(0);
    t.datetime('completed_at', { precision: 3 }).nullable();
    t.boolean('calendar_mirror_enabled').notNullable().defaultTo(false);
    audit(t);
    timestamps(knex, t);
    t.bigInteger('revision').notNullable().defaultTo(0);
    t.index(['workspace_id', 'status'], 'idx_tasks_workspace_status');
    t.index(['workspace_id', 'due_at'], 'idx_tasks_due');
    t.index(['workspace_id', 'remind_at'], 'idx_tasks_remind');
    t.index(['workspace_id', 'is_urgent', 'remind_at'], 'idx_tasks_urgent');
    t.foreign('workspace_id', 'fk_tasks_workspace').references('workspaces.id').onDelete('CASCADE');
    t.foreign('project_id', 'fk_tasks_project').references('projects.id').onDelete('SET NULL');
    t.foreign('parent_task_id', 'fk_tasks_parent').references('tasks.id').onDelete('CASCADE');
    t.foreign('created_by', 'fk_tasks_created_by').references('users.id').onDelete('SET NULL');
    t.foreign('updated_by', 'fk_tasks_updated_by').references('users.id').onDelete('SET NULL');
  });

  await knex.schema.createTable('task_tags', (t) => {
    t.charset(CHARSET);
    t.collate(COLLATION);
    t.specificType('task_id', 'char(26)').notNullable();
    t.specificType('tag_id', 'char(26)').notNullable();
    t.datetime('created_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));
    t.primary(['task_id', 'tag_id']);
    t.index(['tag_id'], 'idx_task_tags_tag');
    t.foreign('task_id', 'fk_task_tags_task').references('tasks.id').onDelete('CASCADE');
    t.foreign('tag_id', 'fk_task_tags_tag').references('tags.id').onDelete('CASCADE');
  });

  await knex.schema.createTable('checklist_items', (t) => {
    base(t);
    t.specificType('task_id', 'char(26)').notNullable();
    t.string('title', 500).notNullable();
    t.boolean('is_done').notNullable().defaultTo(false);
    t.integer('sort_order').notNullable().defaultTo(0);
    timestamps(knex, t);
    t.bigInteger('revision').notNullable().defaultTo(0);
    t.index(['task_id'], 'idx_checklist_items_task');
    t.foreign('task_id', 'fk_checklist_items_task').references('tasks.id').onDelete('CASCADE');
  });

  await knex.raw(
    'ALTER TABLE tasks ADD FULLTEXT INDEX ft_tasks_title_description (title, description)',
  );
}

export async function down(knex) {
  await knex.schema.dropTableIfExists('checklist_items');
  await knex.schema.dropTableIfExists('task_tags');
  await knex.schema.dropTableIfExists('tasks');
  await knex.schema.dropTableIfExists('tags');
  await knex.schema.dropTableIfExists('projects');
}
