/**
 * The usage meter learns the names of vendors that only transcribe.
 *
 * `ai_usage_events.provider` was an ENUM of the five vendors with a chat
 * adapter, because until now every vendor this instance could spend money with
 * was one of those five. Transcription vendors are not: they hold no
 * conversation, so they are deliberately NOT connectable as a chat provider
 * (see `lib/ai/vendors.js`) — but the work they do still costs, and a meter
 * that cannot name a vendor simply omits it.
 *
 * Quietly, too, which is the reason this is a migration rather than a nice-to-
 * have. `recordUsage` swallows its own failures on purpose ("a broken meter
 * must never break a reply"), so an unknown enum value produces a warning line
 * and a missing row — the usage report is short and nothing says so.
 *
 * `ai_connections.provider` is deliberately NOT widened. A connection is a
 * chat credential; a settings screen that offered a transcription-only vendor
 * would be offering one that fails at the first message.
 *
 * Migrations are append-only (AGENTS.md rule 8), so the values are written out
 * here rather than imported: this file must go on meaning what it meant on the
 * day it ran, even after the code's list changes again.
 */
const CHAT = ['anthropic', 'openai', 'gemini', 'openrouter', 'ollama'];
const TRANSCRIBE_ONLY = ['assemblyai', 'deepgram'];

const quoted = (values) => values.map((v) => `'${v}'`).join(',');

export async function up(knex) {
  await knex.raw(
    `ALTER TABLE ai_usage_events MODIFY COLUMN provider ENUM(${quoted([
      ...CHAT,
      ...TRANSCRIBE_ONLY,
    ])}) NOT NULL`,
  );
}

export async function down(knex) {
  // Rows naming a vendor the narrower enum cannot hold would be silently
  // coerced to '' by MySQL, so they go first. A reversal of this migration is
  // an operator's deliberate act and losing the meter rows for vendors the
  // reverted code cannot talk to is the honest half of it.
  await knex('ai_usage_events').whereIn('provider', TRANSCRIBE_ONLY).del();
  await knex.raw(
    `ALTER TABLE ai_usage_events MODIFY COLUMN provider ENUM(${quoted(CHAT)}) NOT NULL`,
  );
}
