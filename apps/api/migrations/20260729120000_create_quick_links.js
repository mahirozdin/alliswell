/**
 * OPH-197 — quick links (round 11, Epic 18, ADR-0018, BLUEPRINT §4.12).
 *
 * A Quick Link is one row of a user's personal shortcut rail: a project, task,
 * note, folder, file or external URL, with the user's own title, emoji, colour
 * and manual order.
 *
 * This is the protocol's FIRST user-scoped sync entity: the row is stored per
 * workspace (revision bookkeeping is unchanged — every write bumps the
 * workspace revision), but the pull hands it only to `user_id`. Hence both
 * foreign keys, both cascading: dropping a workspace or a user takes their
 * shortcuts with it, and account purge (db/accounts.js) needs no new code.
 *
 * `target_id` is polymorphic across five tables and therefore carries NO
 * foreign key — the same reason `files.folder_id` has none (ADR-0014): a
 * target's tombstone and the shortcut's tombstone are written in one
 * transaction, and an FK would order them against each other.
 *
 * Uniqueness note (the mirror image of the folders one): MySQL unique indexes
 * ignore rows with a NULL in the indexed tuple, so `uq_quick_links_user_target`
 * covers exactly the entity kinds — and deliberately does NOT cover
 * `kind = 'url'` rows, whose `target_id` is NULL. Two shortcuts to the same URL
 * with different names are legitimate; entity targets are toggles and are not.
 * Deletes null `target_id` out (see db/quick-links.js) so the slot frees up and
 * a target can be re-added after removal.
 *
 * Migrations are append-only (AGENTS.md rule 8).
 */

import { CHARSET, PREFERRED_COLLATION, resolveCollation } from '../src/db/collation.js';

// Resolved against the live server in up(): MySQL 8 keeps utf8mb4_0900_ai_ci,
// MariaDB has no *_0900_* collation and gets utf8mb4_unicode_ci instead.
let COLLATION = PREFERRED_COLLATION;

export async function up(knex) {
  COLLATION = await resolveCollation(knex);
  await knex.schema.createTable('quick_links', (t) => {
    t.charset(CHARSET);
    t.collate(COLLATION);
    t.specificType('id', 'char(26)').primary();
    t.specificType('workspace_id', 'char(26)').notNullable();
    t.specificType('user_id', 'char(26)').notNullable();
    t.enu('kind', ['project', 'task', 'note', 'folder', 'file', 'url']).notNullable();
    t.specificType('target_id', 'char(26)').nullable();
    t.string('url', 2048).nullable();
    t.string('title', 200).notNullable();
    // 16 CHARACTERS, not bytes (MySQL counts characters): a ZWJ family emoji is
    // a single grapheme of 7 code points and 25 bytes — it has to fit.
    t.string('emoji', 16).nullable();
    t.specificType('color_rgb', 'char(7)').nullable();
    t.integer('sort_order').notNullable().defaultTo(0);

    t.bigInteger('revision').notNullable().defaultTo(0);
    t.datetime('created_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));
    t.datetime('updated_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));
    t.datetime('deleted_at', { precision: 3 }).nullable();

    t.unique(['workspace_id', 'user_id', 'kind', 'target_id'], {
      indexName: 'uq_quick_links_user_target',
    });
    // The list query (one user's live rail) and the limit count.
    t.index(['workspace_id', 'user_id', 'deleted_at'], 'idx_quick_links_workspace_user');
    // The cascade probe: "who points at this target?" — across all members.
    t.index(['workspace_id', 'kind', 'target_id'], 'idx_quick_links_target');
    t.foreign('workspace_id', 'fk_quick_links_workspace')
      .references('workspaces.id')
      .onDelete('CASCADE');
    t.foreign('user_id', 'fk_quick_links_user').references('users.id').onDelete('CASCADE');
  });
}

export async function down(knex) {
  await knex.schema.dropTableIfExists('quick_links');
}
