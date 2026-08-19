/**
 * Account deletion (App Store 5.1.1(v) / Google Play account-deletion policy).
 *
 * Deleting is a two-step story on purpose:
 *
 * 1. **Schedule** — `DELETE /me` stamps `deletion_scheduled_at`. The account
 *    keeps working, so signing back in and cancelling within the grace period
 *    undoes it. A destructive, irreversible action deserves an undo.
 * 2. **Purge** — once that instant passes, the sweep erases everything for
 *    good: no soft delete, no tombstone, no orphaned bytes.
 */

/** Default grace period; overridable per deployment (config.accountDeletionGraceDays). */
export const DEFAULT_GRACE_DAYS = 3;

const DAY_MS = 24 * 60 * 60 * 1000;

/** When a request made at [now] becomes irreversible. */
export function deletionDeadline(now, graceDays = DEFAULT_GRACE_DAYS) {
  return new Date(now.getTime() + graceDays * DAY_MS);
}

/**
 * Marks the account for deletion. Idempotent by intent: asking twice keeps the
 * ORIGINAL deadline, so a second tap cannot quietly extend the countdown.
 * Returns the effective deadline.
 */
export async function scheduleAccountDeletion(db, userId, deadline) {
  const row = await db('users').where({ id: userId }).first('deletion_scheduled_at');
  if (row?.deletion_scheduled_at) return new Date(row.deletion_scheduled_at);

  await db('users')
    .where({ id: userId })
    .update({ deletion_scheduled_at: deadline, updated_at: new Date() });
  return deadline;
}

/** Cancels a pending deletion. Safe to call when none is pending. */
export async function cancelAccountDeletion(db, userId) {
  await db('users')
    .where({ id: userId })
    .update({ deletion_scheduled_at: null, updated_at: new Date() });
}

/** Accounts whose grace period has expired, oldest first. */
export async function accountsDueForPurge(db, now, limit = 50) {
  const rows = await db('users')
    .whereNotNull('deletion_scheduled_at')
    .where('deletion_scheduled_at', '<=', now)
    .orderBy('deletion_scheduled_at', 'asc')
    .limit(limit)
    .select('id');
  return rows.map((r) => r.id);
}

/**
 * Erases the account and everything it owns — irreversibly.
 *
 * Order matters: `workspaces.owner_id` is ON DELETE RESTRICT, so an owner
 * cannot be removed while their workspaces exist. Deleting the workspaces
 * first lets the schema's CASCADEs do the real work (projects, tasks, notes,
 * tags, folders, files, quick links, reminders, revisions…), and deleting the
 * user then cascades what hangs off the person (sessions, memberships,
 * notification devices, calendar accounts, and their quick links inside
 * workspaces they do not own). Workspaces owned by SOMEONE ELSE survive; only
 * this user's membership in them goes.
 *
 * Quick links are the one entity purged by hard delete rather than tombstone
 * (ADR-0018): the owner is gone, and their rows were invisible to every
 * surviving member anyway, so there is nobody left to notify.
 *
 * Storage keys are collected inside the transaction and queued for deletion
 * only AFTER it commits — a rolled-back purge must not have destroyed bytes.
 *
 * @returns {Promise<{workspaces: number, files: number}>}
 */
export async function purgeAccount(app, userId) {
  const keys = [];
  let workspaceCount = 0;

  await app.db.transaction(async (trx) => {
    const owned = await trx('workspaces').where({ owner_id: userId }).select('id');
    let workspaceIds = owned.map((w) => w.id);

    // Extensions may spare owned workspaces (re-homing them inside this
    // transaction) — a spared workspace is not this account's data to erase.
    for (const filter of app.ee?.accountPurgeFilters ?? []) {
      const spared = await filter(trx, { userId, workspaceIds });
      if (Array.isArray(spared) && spared.length > 0) {
        workspaceIds = workspaceIds.filter((id) => !spared.includes(id));
      }
    }
    workspaceCount = workspaceIds.length;

    if (workspaceIds.length > 0) {
      // Every file of every workspace, including uploads that never completed
      // (they hold bytes too).
      const files = await trx('files').whereIn('workspace_id', workspaceIds).select('storage_key');
      for (const file of files) {
        if (file.storage_key) keys.push(file.storage_key);
      }
      await trx('workspaces').whereIn('id', workspaceIds).delete();
    }

    await trx('users').where({ id: userId }).delete();
  });

  if (app.storageGc) {
    for (const key of keys) app.storageGc.enqueueRemove(key);
  }
  return { workspaces: workspaceCount, files: keys.length };
}
