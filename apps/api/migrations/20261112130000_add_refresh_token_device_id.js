/**
 * OPH-434 (#48) — bind a session family to the notification device it runs on.
 *
 * `refresh_tokens.device_id` names the `notification_devices` row of the
 * install that holds the family. A session is a `family_id` family; the id is
 * copied from row to row on every rotation, exactly like `device_name`, so any
 * live row of a family answers "which device is this session on".
 *
 * Nullable and NOT backfilled: nothing on the server knows which install holds
 * an old family. A live family binds itself the next time its client refreshes
 * with a `deviceId`, which happens within one access-token lifetime. A family
 * whose client never sends one stays NULL — that is "not bound", not an error.
 *
 * No foreign key: a device row is deleted on sign-out and on unregister while
 * its family may outlive it for a moment; a dangling id is harmless, an FK
 * cascade into the session table is not.
 *
 * `idx_refresh_tokens_user_device` serves "the families of this user on this
 * device". `idx_refresh_tokens_user` stays, so the FK on `user_id` keeps an
 * index after `down()`. No collation is pinned: CHAR(26) takes the table's.
 */

export async function up(knex) {
  await knex.schema.alterTable('refresh_tokens', (table) => {
    table.specificType('device_id', 'char(26)').nullable();
    table.index(['user_id', 'device_id'], 'idx_refresh_tokens_user_device');
  });
}

export async function down(knex) {
  await knex.schema.alterTable('refresh_tokens', (table) => {
    table.dropIndex(['user_id', 'device_id'], 'idx_refresh_tokens_user_device');
  });
  await knex.schema.alterTable('refresh_tokens', (table) => {
    table.dropColumn('device_id');
  });
}
