# ADR-0004 — ULID ids, UTC timestamps, schema conventions

- **Status:** Accepted
- **Date:** 2026-07-14
- **Related task:** OPH-010…OPH-015

## Context

Offline-first clients must create entities locally (no server round-trip for an id), sync must
stay ordered and idempotent, and MySQL is the canonical store.

## Decision

1. **IDs are ULIDs**, stored as `CHAR(26)` (matches BLUEPRINT DDL). Clients and server both
   generate them (`apps/api/src/lib/ids.js`; Dart `ulid` package later). Lexicographically
   sortable by creation time, index-friendly, no coordination needed.
2. **All timestamps are UTC `DATETIME(3)`** (millisecond precision). The API serializes ISO-8601
   with `Z`. User-facing timezone math uses the `timezone` columns (users, tasks, reminders).
3. **Soft delete** everywhere user data lives: `deleted_at DATETIME(3) NULL`; hard deletes only
   via the (future) data-deletion flow.
4. **`revision BIGINT` on synced entities** (projects, tags, tasks, checklist_items, notes,
   reminders, workspaces) — bumped with every write together with a `sync_revisions` row.
5. **Foreign keys ON:** core relations get real FKs — `CASCADE` from workspace ownership chains,
   `SET NULL` for optional relations (task.project_id, note.project_id, created_by/updated_by).
   Append-heavy log tables (`sync_revisions`, `client_mutations`) get indexes + workspace FK only
   (no per-entity FK) to stay cheap.
6. **Charset:** `utf8mb4` / `utf8mb4_0900_ai_ci` explicitly on every table.
7. **Additions over BLUEPRINT §10** (needed by features already in scope):
   - `tasks.sort_order INT` — manual ordering in lists (Things/TickTick-style).
   - `tasks.snoozed_until DATETIME(3)` — cheap snooze queries without joining reminders.
   - `tasks.actual_minutes INT` — §4.3 lists "actual duration" but DDL omitted it.
   - `refresh_tokens` — hashed opaque tokens with rotation `family_id` (reuse detection).
   - `client_mutations` — idempotency store (unique `client_id`+`client_mutation_id`).
   - `calendar_accounts.webhook_expires_at` — Google notification channels expire and must be renewed.

## Alternatives considered

- **UUIDv4:** random ordering fragments InnoDB clustered indexes; not sortable.
- **UUIDv7:** equivalent properties, but ULID matches the blueprint's CHAR(26) and has better
  cross-language library ergonomics today.
- **Auto-increment ints:** impossible for offline client-side creation.

## Consequences

- Every table creation must follow these conventions (see migration helpers).
- Sync engine (Epic 06) can rely on `revision` + `sync_revisions` existing from day one.
