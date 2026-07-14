/**
 * Feedback round 1 — projects get a README note (GitHub-style: the note that
 * opens on the project Overview tab). References a normal note so it also
 * shows up in note lists/search; SET NULL keeps projects valid if the note
 * row is ever hard-deleted. Migrations are append-only (AGENTS.md rule 8).
 */

export async function up(knex) {
  await knex.schema.alterTable('projects', (t) => {
    t.specificType('readme_note_id', 'char(26)').nullable();
    t.foreign('readme_note_id', 'fk_projects_readme_note')
      .references('notes.id')
      .onDelete('SET NULL');
  });
}

export async function down(knex) {
  await knex.schema.alterTable('projects', (t) => {
    t.dropForeign('readme_note_id', 'fk_projects_readme_note');
    t.dropColumn('readme_note_id');
  });
}
