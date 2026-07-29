/**
 * OPH-205 — recurring tasks (round 12, Epic 19, ADR-0020, BLUEPRINT §12.17).
 *
 * A series holds the RULE and the TEMPLATE; every occurrence it produces is an
 * ordinary row in `tasks` carrying `series_id` + `occurrence_date`. That is the
 * decision the whole feature turns on (ADR-0020 §4): the widget, search, the
 * alarm planner and the calendar mirror keep working because there is nothing
 * new for them to understand — an occurrence is just a task.
 *
 * `rule` and `template` are JSON rather than columns because both are round
 * -tripped whole by the dialog and diffed whole by sync; splitting the end
 * condition into `until_at`/`count` columns (as the backlog first sketched)
 * would give one value two writers that can disagree. The sweep loads live
 * series and lets the engine decide — there is no query that wants to filter
 * on the end condition in SQL.
 *
 * `tasks.series_id` carries NO foreign key, for the reason `quick_links.
 * target_id` and `files.folder_id` do not (ADR-0014/0018): a series tombstone
 * and its occurrences' tombstones are written in one transaction, and an FK
 * would order them against each other. The unique index is what keeps
 * materialization idempotent — and because MySQL unique indexes skip rows with
 * a NULL in the tuple, ordinary non-recurring tasks are entirely unaffected.
 *
 * Migrations are append-only (AGENTS.md rule 8).
 */

import { CHARSET, PREFERRED_COLLATION, resolveCollation } from '../src/db/collation.js';

let COLLATION = PREFERRED_COLLATION;

export async function up(knex) {
  COLLATION = await resolveCollation(knex);

  await knex.schema.createTable('task_series', (t) => {
    t.charset(CHARSET);
    t.collate(COLLATION);
    t.specificType('id', 'char(26)').primary();
    t.specificType('workspace_id', 'char(26)').notNullable();
    // The ADR-0020 rule object: freq/interval/byWeekday/byMonthDay/byMonth/end.
    t.json('rule').notNullable();
    // The fields every occurrence is stamped with (title, project, priority…).
    t.json('template').notNullable();
    // Wall-clock home of the series: occurrences are computed on this calendar,
    // exactly like `tasks.timezone` (09:00 stays 09:00 across a DST boundary).
    t.string('timezone', 64).notNullable().defaultTo('Europe/Istanbul');
    // Seed instant: supplies both the pattern's first candidate day and the
    // time of day every occurrence inherits.
    t.datetime('anchor_at', { precision: 3 }).notNullable();
    // Who owns the occurrences the daily sweep will create long after the
    // request that made the series is gone.
    t.specificType('created_by', 'char(26)').nullable();

    t.bigInteger('revision').notNullable().defaultTo(0);
    t.datetime('created_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));
    t.datetime('updated_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));
    t.datetime('deleted_at', { precision: 3 }).nullable();

    // The sweep's query: every live series in a workspace.
    t.index(['workspace_id', 'deleted_at'], 'idx_task_series_workspace');
    t.foreign('workspace_id', 'fk_task_series_workspace')
      .references('workspaces.id')
      .onDelete('CASCADE');
    t.foreign('created_by', 'fk_task_series_created_by')
      .references('users.id')
      .onDelete('SET NULL');
  });

  await knex.schema.alterTable('tasks', (t) => {
    t.specificType('series_id', 'char(26)').nullable();
    t.date('occurrence_date').nullable();
    t.unique(['series_id', 'occurrence_date'], { indexName: 'uq_tasks_series_occurrence' });
  });
}

export async function down(knex) {
  await knex.schema.alterTable('tasks', (t) => {
    t.dropUnique(['series_id', 'occurrence_date'], 'uq_tasks_series_occurrence');
    t.dropColumn('occurrence_date');
    t.dropColumn('series_id');
  });
  await knex.schema.dropTableIfExists('task_series');
}
