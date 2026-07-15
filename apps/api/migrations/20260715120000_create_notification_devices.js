/**
 * OPH-060 — notification device registry (BLUEPRINT §8). One row per app
 * install; `id` is the device-generated ULID (the app reuses its sync client
 * id). `push_token` stays nullable — local-notification-only platforms
 * register without one. NOT a synced entity: no revision column, devices are
 * per-user infrastructure, not workspace data.
 */

const CHARSET = 'utf8mb4';
const COLLATION = 'utf8mb4_0900_ai_ci';

export const PLATFORMS = ['ios', 'android', 'macos', 'windows', 'linux', 'web'];

export async function up(knex) {
  await knex.schema.createTable('notification_devices', (t) => {
    t.charset(CHARSET);
    t.collate(COLLATION);
    t.specificType('id', 'char(26)').primary();
    t.specificType('user_id', 'char(26)').notNullable();
    t.enu('platform', PLATFORMS).notNullable();
    t.string('push_token', 512).nullable();
    t.string('device_name', 255).nullable();
    t.string('app_version', 64).nullable();
    t.datetime('last_seen_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));
    t.datetime('created_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));
    t.datetime('updated_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));
    t.index(['user_id'], 'idx_notification_devices_user');
    t.foreign('user_id', 'fk_notification_devices_user').references('users.id').onDelete('CASCADE');
  });
}

export async function down(knex) {
  await knex.schema.dropTableIfExists('notification_devices');
}
