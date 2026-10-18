---
paths:
  - "apps/api/src/routes/sync.js"
  - "apps/api/src/db/sync.js"
  - "apps/app/lib/src/sync/**"
---
# Sync — critical path

The protocol between every client replica and MySQL; a silent field loss here passes every
suite (OPH-299).

- **K1 extra:** `npm run verify:task -- apps/api/test/integration/sync.test.js` (+
  `apps/app/test/sync/migration_test.dart` when the replica schema moves). `check:sync-fields`
  runs by itself. Touched `SYNC_ENTITY_FIELDS` → `npm run gen:sync-fields` and commit
  `apps/app/lib/src/sync/sync_fields.g.dart` in the same change.
- **Invariants:**
  - MySQL is canonical; clients hold replicas. Every workspace has a monotonic `revision`.
  - Pushes carry `clientMutationId`; the server is idempotent (`client_mutations`).
  - Conflicts: field-level last-write-wins for metadata; document-level optimistic lock +
    conflict copy for notes (BLUEPRINT §6.5, ADR-0007).
  - A write to a synced entity bumps its `revision` and inserts a `sync_revisions` row in the
    same transaction — `recordSyncWrite`/`withRevision` from `src/db/sync.js`.
  - Calendar mapping keys: Google `extendedProperties.private.alliswell_task_id` /
    `alliswell_workspace_id`; Apple events carry `alliswell://task/{taskId}` in the URL field;
    `calendar_event_links` is the source of truth (ADR-0003).
- **Traps (docs/LESSONS.md `sync`, `drift-replica`):**
  - No new sync `operation` verb: the ENUMs and the pull schema hold three, and `default:`
    falls into `applyDelete` → `update` + a virtual field (`orderedIds`, `seriesScope`).
  - Writes go through two seams — `db/*.js` (REST/MCP/import) and the push ENTITIES machine
    (`afterCreate/afterUpdate`): a new rule is wired into both.
  - The pull loader must load a new field, or the shared serializer silently sends `[]`.
  - A tombstone is a revision: whoever removes a row records a sync write in the same
    transaction; test with a real pull.
  - The server rejects the whole mutation on its first unknown field → test with the
    client's real body.
- **Detail:** [ARCHITECTURE §5](../../docs/ARCHITECTURE.md#5-sync-engine-live-end-to-end),
  ADR-0007, ADR-0018, ADR-0044.
