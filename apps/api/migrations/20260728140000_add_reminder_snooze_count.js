/**
 * Round 9 (OPH-177): how many snooze rounds an alarm has been through.
 *
 * Round 9 #6.6: five minutes after snoozing, the re-ring read exactly like the
 * first alert, so the user reasonably called it "the 1st notification again".
 * OPH-176 made it say "snoozed round"; this counter lets it say WHICH round.
 *
 * Reset to 0 whenever the alarm is re-armed to a new instant
 * (`reconcileTaskReminder`) — a moved deadline is a new alarm, not round seven.
 */
export async function up(knex) {
  await knex.schema.alterTable('reminders', (table) => {
    table.integer('snooze_count').unsigned().notNullable().defaultTo(0);
  });
}

export async function down(knex) {
  await knex.schema.alterTable('reminders', (table) => {
    table.dropColumn('snooze_count');
  });
}
