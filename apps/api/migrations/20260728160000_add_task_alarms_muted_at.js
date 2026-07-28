/**
 * Round 9 (OPH-178): "sustur" — silence a task's alarms indefinitely WITHOUT
 * completing it.
 *
 * The user's words: _"kullanıcı isterse acil olarak ayarladığı taski tamamla
 * olarak işaretlemeden de tamamen susturabilmeli."_ Marking a task done to make
 * it shut up is a lie in the data; snoozing to a made-up far future is a lie in
 * the UI. So silence becomes a real, reversible, replicated fact.
 *
 * NULL = alarms live. A timestamp = silenced since then, and
 * `alarmInstantsFor` (already written for this in OPH-175) returns no alarms,
 * which makes `reconcileTaskReminder` cancel the rows on every device.
 */
export async function up(knex) {
  await knex.schema.alterTable('tasks', (table) => {
    table.timestamp('alarms_muted_at', { precision: 3 }).nullable();
  });
}

export async function down(knex) {
  await knex.schema.alterTable('tasks', (table) => {
    table.dropColumn('alarms_muted_at');
  });
}
