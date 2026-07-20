# ADR-0014 — Folders and the global "Dosyalar" section

- **Status:** Accepted
- **Date:** 2026-07-20
- **Related task:** OPH-169 / OPH-170 (Epic 15, feedback round 8)

## Context

Feedback round 8 (Mahir, 2026-07-20): the main nav should have a **Files
section** — "a simple but effective file manager, like Finder/Windows Explorer":
every file in the workspace visible in one place, uploads that belong to no
project/task/note, folder structures, sorting, delete/upload.

Epic 14 (ADR-0011) shipped attachments as a single polymorphic `files` table
(`target_type` ∈ project|task|note, presigned direct transfer, pull-only `file`
sync entity, no-orphaned-bytes cascades). It deliberately had no standalone
files and no folders. The project Files *tab* already aggregates a project's
attachment universe; round 8 asks for the workspace-wide equivalent plus real
organization.

Constraints inherited from ADR-0011: bytes never transit the API; uploading is
online by nature (hence `file` is pull-only); deletes must never leave orphaned
objects; the feature must stay honest when `STORAGE_S3_*` is unconfigured.

## Decision

1. **Standalone files = a new `workspace` target, same table.**
   `files.target_type` grows a `workspace` member with `target_id` =
   workspace id. One polymorphic table keeps every invariant (opaque keys,
   presigned lifecycle, GC queue, usage endpoint) working unchanged.
2. **Folders are a first-class, push-pull sync entity.** New `folders` table:
   `id` ULID, `workspace_id`, `parent_id` (nullable self-reference; null =
   root), `name` ≤255, `revision`, timestamps, `deleted_at`. Unique
   `(workspace_id, parent_id, name)` — with `utf8mb4_0900_ai_ci` that is
   case/accent-insensitive like Finder. Depth is capped at **10** (validated
   in the API); moves are cycle-checked (a folder cannot enter its own
   subtree). Folders are pure metadata, so unlike files they sync
   **push-pull** (project/tag model): offline create/rename/move is safe and
   truthful. `sync_revisions.entity_type` is a free VARCHAR — no migration
   needed for the type name itself.
3. **Only workspace-target files are folderable.** `files.folder_id` (nullable
   FK) is accepted **only** when `target_type='workspace'` and the folder
   belongs to the same workspace. Attached files (project|task|note) never
   enter folders: their lifecycle belongs to their owner entity (ADR-0011
   cascades), and one file living in two hierarchies (its entity AND a folder)
   would make deletion semantics lie to someone. The global section shows
   attached files in a separate read-only **Kaynaklar** layer (source badges,
   "go to source") — access, not organization.
4. **Folder deletion cascades its subtree, and says so.** DELETE soft-deletes
   the folder, its descendant folders and their workspace files in one
   transaction (each row with its own revision via `recordSyncWrite`), then
   enqueues object GC per file — the ADR-0011 no-orphaned-bytes guarantee
   extends verbatim. The API response reports deleted counts; the app confirm
   states the blast radius before (DESIGN §10 F9).
5. **App surface.** The removed Calendar nav slot (OPH-162) becomes
   **Dosyalar**: breadcrumb navigation over the folder tree, upload into the
   current folder, move via a target-picker sheet (folder tree), rename/delete,
   sort name/size/date, plus the Kaynaklar aggregate reusing the project Files
   tab components verbatim (DESIGN F7). Replica: drift v6 adds `folders` and
   `file_rows.folder_id`.

## Alternatives considered

- **Materialized-path folders** (`path` string column) instead of `parent_id` —
  cheaper subtree queries, but renames/moves rewrite entire subtrees and the
  path duplicates the name. With depth ≤10 and human-scale folder counts,
  recursive walks over `parent_id` are trivial on both MySQL 8 (CTE) and the
  replica. Rejected.
- **Folders organize attached files too** — rejected (double-ownership makes
  delete semantics dishonest; see Decision 3).
- **A separate `workspace_files` table** — rejected: two tables would duplicate
  the entire presign/GC/usage/sync surface for zero model gain.
- **Empty-only folder deletion** — safer but fights the Finder mental model the
  user explicitly asked for; forces tedious manual cleanup. Rejected in favor
  of counted, confirmed recursive delete.
- **Client-side-only folders (app-local kv)** — no server truth, breaks
  multi-device sync and the "workspace's files" promise. Rejected.

## Consequences

- One new migration (`folders` + `files.folder_id` + enum extension), new
  `folders` routes, a `folder` push-pull sync registration, files init/list
  accepting the workspace target — all following existing patterns.
- The `file` pull snapshot now carries `folderId`; the drift applier and
  FileStore learn it in the same task.
- `cascadeDeleteFiles` gains a folder-subtree entry point; the GC queue and
  stale-upload sweep are untouched.
- The app's Files section works fully offline for browsing (metadata replica);
  uploads/downloads stay online — same honesty rules as every other file
  surface.
