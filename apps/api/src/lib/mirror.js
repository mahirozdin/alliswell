/**
 * Task → Google event derivation (OPH-072, BLUEPRINT §7.1) — pure, so the
 * mirroring rule is unit-testable without Google or a database.
 *
 * A task mirrors when `calendar_mirror_enabled` AND it has a time to show:
 * scheduled block first, then the due slot, then an urgent reminder block.
 * Finished/archived/deleted tasks mirror to NOTHING (event gets removed).
 */

const SLOT_MINUTES = 30;
const GONE_STATUSES = new Set(['completed', 'cancelled', 'archived']);

/** @returns {object|null} Google event resource, or null = no event wanted */
export function desiredEventForTask(task) {
  if (!task || task.deleted_at != null) return null;
  if (!task.calendar_mirror_enabled) return null;
  if (GONE_STATUSES.has(task.status)) return null;

  let start;
  let end;
  if (task.scheduled_start_at) {
    start = new Date(task.scheduled_start_at);
    end = task.scheduled_end_at
      ? new Date(task.scheduled_end_at)
      : new Date(start.getTime() + SLOT_MINUTES * 60000);
  } else if (task.due_at) {
    start = new Date(task.due_at);
    end = new Date(start.getTime() + SLOT_MINUTES * 60000);
  } else if (task.is_urgent && task.remind_at) {
    start = new Date(task.remind_at);
    end = new Date(start.getTime() + SLOT_MINUTES * 60000);
  } else {
    return null;
  }

  return {
    summary: `[Task] ${task.title}`,
    ...(task.description ? { description: task.description } : {}),
    start: { dateTime: start.toISOString() },
    end: { dateTime: end.toISOString() },
    // ADR-0003 mapping keys + §7.1 metadata. The mapping TABLE stays the
    // source of truth; these let foreign events be re-linked (OPH-073).
    extendedProperties: {
      private: {
        alliswell_task_id: task.id,
        alliswell_workspace_id: task.workspace_id,
        ...(task.project_id ? { alliswell_project_id: task.project_id } : {}),
        alliswell_source: 'alliswell',
        alliswell_revision: String(task.revision),
      },
    },
  };
}
