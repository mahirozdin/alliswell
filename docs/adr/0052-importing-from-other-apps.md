# ADR-0052 — Importing from Todoist and TickTick

- **Status:** Accepted
- **Date:** 2026-10-16
- **Related task:** OPH-371

## Context

People who leave another task app want their tasks with them. The bulk import API (OPH-266,
`POST import/tasks|notes`) takes only our own JSON. No screen calls it, and it has no external
ids, no checklist, no recurrence and no completed status. The research round found switching
cost to be a real barrier (Vikunja ships importers). The owner asked for a wizard for Todoist
and TickTick, and for the README and landing page to say it exists.

What the two exports are (checked on 2026-10-16):

- **Todoist.** A CSV per project with the columns `TYPE, CONTENT, DESCRIPTION, PRIORITY,
  INDENT, AUTHOR, RESPONSIBLE, DATE, DATE_LANG, TIMEZONE, DURATION, DURATION_UNIT, DEADLINE,
  DEADLINE_LANG` (help article 360000748525 and its template). A backup is a ZIP of those
  CSVs. Labels live inside CONTENT as `@label`, PRIORITY 1 is p1 (the highest), INDENT nests
  sub-tasks, and DATE is the phrase the user typed. There are **no task ids** and **no
  completed tasks**, and a recurrence's "starting …" part is dropped.
- **TickTick.** The web backup CSV: a quoted preamble with a record that spans several lines,
  then 24 named columns including `taskId`/`parentId`, RRULE repeats, ISO-8601 reminder
  durations, a status for completed/archived, and checklist lines marked ▫/▪. A child may
  come before its parent.
- **Apple Reminders** has no export file. It is not offered and not promised.

## Decision

1. **The server parses.** `POST /api/v1/workspaces/:id/import/apps` takes
   `{source, files:[{name, content}], dryRun, options}`. Pure modules in
   `apps/api/src/lib/importers/` (csv, dates, recurrence, todoist, ticktick) build a
   normalized plan, and `src/db/app-import.js` writes it through the domain layer (`createTask`,
   `addChecklistItem`, `createTaskSeries`, `createNote`, `createProject`, `createTag`), one
   transaction per item. One implementation serves the app, an API key and curl. The
   preview is the same request with `dryRun: true` (DESIGN §37 I1). The tz and recurrence math
   reuses `lib/time.js` and `lib/recurrence.js validateRule`, and the Dart client needs no CSV,
   date or RRULE parser. The client only unzips a Todoist backup (the `archive` package it
   already has) and decodes UTF-8, so the server gains no dependency.
2. **Idempotency is a ledger.** The new server-only table `import_ledger` has
   `UNIQUE(workspace_id, source, external_key)`, where the key is a sha256 hex. TickTick's key
   is its `taskId`. Todoist has no ids, so its key is a fingerprint of project + section +
   title + occurrence index, **deliberately without the date**, so a re-export after
   rescheduling still matches. The ledger row is inserted first, in the item's own
   transaction: a duplicate key means "already imported, skip", and two identical requests at
   once leave one row and one task. A re-import **never updates or resurrects** anything: a
   task deleted after its import stays deleted. Known limit: renaming a Todoist project,
   section or task and re-exporting imports that item again.
3. **Batches.** At most `options.maxItems` (default 250, max 500) new items are written per
   call. `remaining` says how many are left, and the app calls again until it is 0. The route
   body limit is 10 MiB, and the self-hosting nginx sample gets `client_max_body_size 10m`.
4. **Mapping.**
   - Priorities: Todoist p1/p2/p3/p4 and TickTick high/medium/low/none map to
     high/medium/low/none. "Urgent" stays the user's own choice.
   - Imported tasks **never arm urgent alarms** (`isUrgent` false, no acknowledgement). A
     reminder is kept only when TickTick has one and it is in the future.
   - A date without a time takes the user's default task time. The zone is the row's own IANA
     zone, then `options.timezone`, then the profile's. The client never sends a guess.
   - Sections and board columns become tags. Lists and projects become projects (an existing
     project with the same Turkish-folded name is reused). Folders are flattened, and two
     lists with one name keep `List (Folder)`. An Inbox is no project.
   - Sub-tasks become checklist items (the owner's rule, since there is no subtask screen). A
     repeat we can represent exactly becomes a `task_series`. Anything else (a phrase without
     an anchor day, `every!`, non-English text, BYSETPOS) stays in the description in a short
     block written in the wizard's language, and is counted as a warning. Comments and
     attachment links are appended to the description, and TickTick NOTE items become notes.
   - Completed tasks are opt-in.
5. **Rule 12.** The public API gets the capability as is; the key surface authenticates the
   same route. **MCP gets no tool**: an export file is file bytes (AI.md §7), bulk import is
   script-shaped (LESSONS ai-mcp), and the assistant already has `create_task` /
   `add_checklist_item`.

## Consequences

- One parser to fix when a real export shows a new date shape. The kept-in-note blocks make
  such misses visible to the user instead of silent.
- Every imported task mirrors to Google Calendar like any other (lib/mirror.js: not a
  setting), and undated ones land on the import day. The preview says so when Google is
  connected. Suppressing that would be a separate owner decision.
- `createProject`, `createTag`, `createNote` and `addChecklistItem` take an optional `trx`,
  and `createTask` stamps `completed_at` when a task is created completed. Series creation
  moved from the route closure into `db/task-series.js createTaskSeries`, which the route and
  the importer share.
- The ledger cascades with the workspace, so account deletion purges it.
