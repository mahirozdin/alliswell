/**
 * The meter learns one vendor's name and forgets another's.
 *
 * Yesterday's migration widened `ai_usage_events.provider` to hold the two
 * transcription-only vendors this instance could spend money with. One of them
 * changed: `deepgram` is out, `elevenlabs` is in. The comparison behind that
 * belongs beside the vendor list (`lib/ai/vendors.js`) rather than in a
 * migration header; what belongs here is what it does to the column.
 *
 * ── WHY THIS DROPS A VALUE, WHICH MIGRATIONS USUALLY DO NOT ──────────────
 *
 * Leaving `deepgram` in the enum would cost nothing and say something false:
 * that the meter is still prepared to bill against a vendor no adapter can
 * reach. An enum is a dictionary, and a dictionary that keeps words the
 * language dropped is how the next reader learns the wrong list. So the value
 * goes, and the rows that could name it go with it — see below.
 *
 * ── THE DELETE IS NOT DEFENSIVE, IT IS THE HONEST HALF ───────────────────
 *
 * MySQL coerces a value the narrowed enum cannot hold into `''` rather than
 * failing, so a surviving `deepgram` row would become a nameless one — a
 * usage record for a vendor nobody can identify, which is worse than no
 * record. In practice this deletes nothing: the adapter landed and was removed
 * inside one unreleased epic and no instance ever transcribed with it. Saying
 * "in practice nothing" out loud beats a `WHERE` clause that looks like it
 * expects something.
 *
 * Values are written out rather than imported, same as the migration before
 * it: this file has to keep meaning what it meant on the day it ran (AGENTS.md
 * rule 8), even after the code's list moves again.
 */
const CHAT = ['anthropic', 'openai', 'gemini', 'openrouter', 'ollama'];
const BEFORE = ['assemblyai', 'deepgram'];
const AFTER = ['assemblyai', 'elevenlabs'];

const quoted = (values) => values.map((v) => `'${v}'`).join(',');

const modify = (knex, values) =>
  knex.raw(`ALTER TABLE ai_usage_events MODIFY COLUMN provider ENUM(${quoted(values)}) NOT NULL`);

export async function up(knex) {
  await knex('ai_usage_events').where({ provider: 'deepgram' }).del();
  await modify(knex, [...CHAT, ...AFTER]);
}

export async function down(knex) {
  await knex('ai_usage_events').where({ provider: 'elevenlabs' }).del();
  await modify(knex, [...CHAT, ...BEFORE]);
}
