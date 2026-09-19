/**
 * OPH-325 — `files.target_type` stops being a closed list (ADR-0040).
 *
 * The column has been an ENUM since the table was created, and widening it has
 * always meant a migration: `project|task|note` in July, plus `workspace` two
 * days later for folders. That is fine while every kind of attachable thing
 * lives in this repo. It stops being fine the moment an extension wants one,
 * because an extension may not ALTER a core table — so the closed list makes
 * "can this thing have files?" a question only core can answer.
 *
 * The column becomes a `varchar(32)` and the ACCEPTED SET moves into code, as a
 * registry the build fills at boot (`app.ee.attachmentTargets`, the
 * ARCHITECTURE 3b pattern). Three things stay exactly as they were:
 *
 *   - the plain build accepts the same four values and nothing else, because
 *     the registry it boots with is empty;
 *   - an unaccepted value is still refused, by the route rather than by MySQL —
 *     which turns a driver error into the 400 the API already documents;
 *   - every existing row keeps its value; a widening cast touches no data.
 *
 * Why 32 and not 255: the values are identifiers in URLs and JSON, not prose.
 * 32 is room for `ticket_comment`-sized names twice over, and it keeps the
 * `(workspace_id, target_type, target_id)` index the shape it already is.
 *
 * The down() is the only lossy part and it says so: an extension's rows cannot
 * fit back into the old ENUM, so it refuses rather than silently emptying them.
 */
const OLD_ENUM = "ENUM('project','task','note','workspace')";
const CORE_TARGETS = ['project', 'task', 'note', 'workspace'];

export async function up(knex) {
  await knex.raw('ALTER TABLE files MODIFY COLUMN target_type VARCHAR(32) NOT NULL');
}

export async function down(knex) {
  const [rows] = await knex.raw(
    `SELECT DISTINCT target_type FROM files WHERE target_type NOT IN (${CORE_TARGETS.map(
      () => '?',
    ).join(',')})`,
    CORE_TARGETS,
  );
  if (rows.length > 0) {
    const found = rows.map((r) => r.target_type).join(', ');
    throw new Error(
      `files.target_type holds values the old ENUM cannot store (${found}). ` +
        'Remove those rows (and their objects) before rolling this back — narrowing ' +
        'the column would replace them with an empty string, which is a file pointing ' +
        'at nothing rather than an error.',
    );
  }
  await knex.raw(`ALTER TABLE files MODIFY COLUMN target_type ${OLD_ENUM} NOT NULL`);
}
