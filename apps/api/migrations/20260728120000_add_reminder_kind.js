/**
 * Round 9 (OPH-175): a task can own TWO alarms, and they are independent — the
 * reminder the user asked for, and (for an urgent task) its own deadline.
 *
 * Until now `effectiveRemindAt` collapsed them into one row: `remind_at ?? due_at`,
 * so setting a reminder ERASED the deadline alarm. The user's report was exactly
 * that — a 22:42 reminder rang and 22:45, the actual due time, passed in silence.
 *
 * `kind` tells the two rows apart. Deliberately NO unique index on
 * (task_id, kind): terminal rows (acknowledged/cancelled/completed) accumulate as
 * history, and every reader already selects the NEWEST ACTIVE row — see
 * `db/reminders.js`.
 */
export async function up(knex) {
  await knex.schema.alterTable('reminders', (table) => {
    table.enu('kind', ['remind', 'due']).notNullable().defaultTo('remind');
  });

  // Backfill: an existing row belongs to the DEADLINE only when its task never
  // had a reminder time and was urgent with a due date (the old
  // `remind_at ?? due_at` fallback). Everything else is a real reminder, which
  // is what the column already defaults to.
  await knex('reminders')
    .update({ kind: 'due' })
    .whereIn(
      'task_id',
      knex('tasks')
        .select('id')
        .whereNull('remind_at')
        .where({ is_urgent: true })
        .whereNotNull('due_at'),
    );
}

export async function down(knex) {
  await knex.schema.alterTable('reminders', (table) => {
    table.dropColumn('kind');
  });
}
