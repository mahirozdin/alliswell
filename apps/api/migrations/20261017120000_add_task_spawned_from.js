/**
 * OPH-375 — repeat N days/weeks/months after completion (ADR-0056).
 *
 * An after-completion series grows one occurrence at a time: completing the
 * open one makes the server create the next. `spawned_from_task_id` names the
 * completed occurrence a row was born from, so that
 *
 * - uncompleting that occurrence withdraws exactly the row its completion made
 *   (and nothing the user has since finished), and
 * - a repeated completion (two devices, a retried push) cannot create a second
 *   successor — the server asks "does this task already have one?" first.
 *
 * Server-owned: not a sync field, not serialized, never written by a client.
 * No foreign key, for the reason `tasks.series_id` has none (migration
 * 20260729180000): tombstones are written together in one transaction, and an
 * FK would order them against each other.
 *
 * Migrations are append-only (AGENTS.md rule 8).
 */

export async function up(knex) {
  await knex.schema.alterTable('tasks', (t) => {
    t.specificType('spawned_from_task_id', 'char(26)').nullable();
    t.index(['spawned_from_task_id'], 'idx_tasks_spawned_from');
  });
}

export async function down(knex) {
  await knex.schema.alterTable('tasks', (t) => {
    t.dropIndex(['spawned_from_task_id'], 'idx_tasks_spawned_from');
    t.dropColumn('spawned_from_task_id');
  });
}
