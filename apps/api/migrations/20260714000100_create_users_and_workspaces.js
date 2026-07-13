/**
 * OPH-011 — users, workspaces, workspace_members, refresh_tokens.
 * Conventions: ADR-0004 (ULID CHAR(26) ids, UTC DATETIME(3), soft delete, utf8mb4).
 * Migrations are append-only (AGENTS.md rule 8) — never edit this file after it has run.
 */

const CHARSET = 'utf8mb4';
const COLLATION = 'utf8mb4_0900_ai_ci';

function base(table) {
  table.charset(CHARSET);
  table.collate(COLLATION);
  table.specificType('id', 'char(26)').primary();
}

function timestamps(knex, table, { softDelete = true } = {}) {
  table.datetime('created_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));
  table.datetime('updated_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));
  if (softDelete) table.datetime('deleted_at', { precision: 3 }).nullable();
}

export async function up(knex) {
  await knex.schema.createTable('users', (t) => {
    base(t);
    t.string('email', 255).notNullable();
    t.string('password_hash', 255).nullable();
    t.string('display_name', 255).nullable();
    t.text('avatar_url').nullable();
    t.string('timezone', 64).notNullable().defaultTo('Europe/Istanbul');
    t.string('locale', 16).notNullable().defaultTo('tr-TR');
    timestamps(knex, t);
    t.unique(['email'], { indexName: 'uq_users_email' });
  });

  await knex.schema.createTable('workspaces', (t) => {
    base(t);
    t.specificType('owner_id', 'char(26)').notNullable();
    t.string('name', 255).notNullable();
    t.string('slug', 255).notNullable();
    t.specificType('color_rgb', 'char(7)').notNullable().defaultTo('#2563EB');
    t.string('icon', 64).nullable();
    t.string('default_timezone', 64).notNullable().defaultTo('Europe/Istanbul');
    t.bigInteger('revision').notNullable().defaultTo(0);
    timestamps(knex, t);
    t.unique(['slug'], { indexName: 'uq_workspaces_slug' });
    t.foreign('owner_id', 'fk_workspaces_owner').references('users.id').onDelete('RESTRICT');
  });

  await knex.schema.createTable('workspace_members', (t) => {
    base(t);
    t.specificType('workspace_id', 'char(26)').notNullable();
    t.specificType('user_id', 'char(26)').notNullable();
    t.enu('role', ['owner', 'admin', 'member']).notNullable().defaultTo('member');
    timestamps(knex, t, { softDelete: false });
    t.unique(['workspace_id', 'user_id'], { indexName: 'uq_workspace_members' });
    t.index(['user_id'], 'idx_workspace_members_user');
    t.foreign('workspace_id', 'fk_wm_workspace').references('workspaces.id').onDelete('CASCADE');
    t.foreign('user_id', 'fk_wm_user').references('users.id').onDelete('CASCADE');
  });

  // Rotating refresh tokens (Epic 03): opaque tokens stored as SHA-256 hex hashes.
  // family_id groups a rotation chain so token reuse can revoke the whole family.
  await knex.schema.createTable('refresh_tokens', (t) => {
    base(t);
    t.specificType('user_id', 'char(26)').notNullable();
    t.specificType('family_id', 'char(26)').notNullable();
    t.specificType('token_hash', 'char(64)').notNullable();
    t.string('device_name', 255).nullable();
    t.datetime('expires_at', { precision: 3 }).notNullable();
    t.datetime('rotated_at', { precision: 3 }).nullable();
    t.datetime('revoked_at', { precision: 3 }).nullable();
    t.string('created_ip', 45).nullable();
    timestamps(knex, t, { softDelete: false });
    t.unique(['token_hash'], { indexName: 'uq_refresh_tokens_hash' });
    t.index(['user_id'], 'idx_refresh_tokens_user');
    t.index(['family_id'], 'idx_refresh_tokens_family');
    t.foreign('user_id', 'fk_rt_user').references('users.id').onDelete('CASCADE');
  });
}

export async function down(knex) {
  await knex.schema.dropTableIfExists('refresh_tokens');
  await knex.schema.dropTableIfExists('workspace_members');
  await knex.schema.dropTableIfExists('workspaces');
  await knex.schema.dropTableIfExists('users');
}
