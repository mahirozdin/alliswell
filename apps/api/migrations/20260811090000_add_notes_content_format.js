/**
 * Round 17 (OPH-248, ADR-0028 §1): which field is a note's CANONICAL content.
 *
 * The markdown workspace needs an answer to "what is a note made of", and the
 * ADR picked Option C — split by intent. A note is either Delta-canonical (the
 * WYSIWYG wrote it) or markdown-canonical (it came from a file, or the user
 * deliberately converted it). Reading is always a real markdown renderer;
 * Source edits the markdown as text; the rich editor is offered only to Delta
 * notes.
 *
 * **The migration touches zero rows, and that is the point.** Defaulting to
 * 'delta' makes every existing note correct by construction — which is exactly
 * why Option C beat "make markdown canonical everywhere" (ADR-0028
 * §Alternatives), and why OPH-251 can promise a file is written back
 * byte-faithfully or not at all (DESIGN §29 W4).
 *
 * A CHECK constraint rather than an ENUM: MySQL enums are painful to extend,
 * and the ADR's enforcement section asks for the constraint to live in the
 * schema rather than in application code.
 */
const ALLOWED = ['delta', 'markdown'];

export async function up(knex) {
  await knex.schema.alterTable('notes', (table) => {
    table.string('content_format', 16).notNullable().defaultTo('delta');
  });

  // Named so `down` can drop it deterministically — an anonymous constraint
  // gets a generated name that differs between MySQL and MariaDB.
  await knex.raw(
    `ALTER TABLE notes
       ADD CONSTRAINT notes_content_format_chk
       CHECK (content_format IN (${ALLOWED.map(() => '?').join(', ')}))`,
    ALLOWED,
  );
}

export async function down(knex) {
  await knex.raw('ALTER TABLE notes DROP CONSTRAINT notes_content_format_chk');
  await knex.schema.alterTable('notes', (table) => {
    table.dropColumn('content_format');
  });
}
