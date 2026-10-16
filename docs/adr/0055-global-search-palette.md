# ADR-0055 — Search everywhere: one palette over the replica

- **Status:** Accepted
- **Date:** 2026-10-16
- **Related task:** OPH-374

## Context

Search was per screen (OPH-167, DESIGN §12): Home finds tasks and events, Projects finds
projects, Notes finds notes. Tags and files had no search, and nothing searched across kinds.
As data grows, getting to a thing means first guessing which screen holds it. The 2026-10-16
research (Vikunja's quick search, every desktop task app's ⌘K) and our own backlog line
("global single-screen search") asked for one place to type.

Constraints: local-first (the replica answers, offline), one definition of "matches"
(ADR-0013's fold, OPH-326's registry), `check:search-reachable` (every registered entity has a
caller), the markdown editor's own ⌘K/Ctrl+K command palette, and a phone app bar that is
already full (OPH-359).

## Decision

1. **One palette, five kinds.** Tasks, projects, notes, tags and file names, grouped in that
   fixed order, up to five rows each with "shown of total" in the header, from the replica.
   An optional last row, "Create task “text”", opens the normal create sheet prefilled (never a
   silent write; hidden without `tasks.create`). An empty field lists recent items.
2. **The registry grows; no new engine.** `searchNotes`, `searchTags` and `searchFiles` join
   `SearchService` as registry entities. A single-tier entity (a tag, a file: a name and
   nothing else) gets its tier as a constant, because `CASE ELSE 0 END` is not SQL. Notes:
   title (0) and body (2), archived out, README notes in. Files: `ready` rows of the four core
   target types only; an EE `ticket_comment` attachment belongs to its request.
3. **Replica v39: `file_rows.name_fold`.** SQLite `LIKE` cannot fold ç/ı (ADR-0013), and a
   Dart-side filter would be a second "matches". The step is guarded `from >= 5` (the table is
   created at v5 with today's definition), backfills existing rows, and `fileCompanion` — the
   one writer — writes the fold.
4. **Scope.** Tasks follow Home's task scope (in an organisation, the person's own work across
   units) with statuses open, scheduled, in progress, waiting, inbox and completed (shown with
   a check); cancelled is out. Projects, notes, tags and files use the active workspace, the
   content screens' scope. Archived projects are found and labelled.
5. **Entry points.**
   - **Shortcut:** ⌘K on Apple platforms (web on a Mac included), Ctrl+K elsewhere — never
     both, because Ctrl+K is the macOS text field's kill-line. Bound with `CallbackShortcuts`
     at the app root (`AwGlobalSearchHost` in `MaterialApp.builder`), so it is the last
     handler a key meets: a focused field that owns the key — the note editor's command
     palette — keeps it. A second press closes the open palette instead of stacking one.
   - **Wide (rail):** the `NavigationRail` leading slot — a field-shaped button with the
     shortcut written on it when extended, a search icon with the shortcut in its tooltip
     when collapsed.
   - **Phone:** a round glass button at the end of the bottom bar's row (the iOS 26 "search
     beside the tab bar" pattern). No app-bar icon: Home's phone bar is full, and a sixth icon
     would cut the title again (OPH-359). Cost: the bar's label rule becomes width-based —
     below 64 px per tab only the selected label is written, which is now the case on most
     phones (the same state the docked Quick Access bubble already caused, OPH-362).
6. **Opening.** Task → pushed detail; project and note → their branch routes; file → its
   actions sheet (the Quick Access rule — files have no address); tag → Home filtered by that
   tag, switching Home from board to list view if needed. The tag case is an explicit
   navigation the person chose, so DESIGN §12 S5 ("search never mutates state") does not
   apply. Kind → destination is ONE table shared with Quick Access
   (`quickDestinationForTarget`). The palette only chooses; the host acts after the dialog is
   gone, with a `ref` that outlives every route.
7. **Recents** are device-local and person-bound: `localKv` key `search.recent` (in
   `kUserBoundKvPrefixes`, wiped on sign-out), at most 8, most recent first. They come from
   route visits anywhere (a task, project or note opened from any screen, read from the
   router's `state.uri` because a pushed detail does not change the configuration's address)
   plus tag and file picks in the palette. Rows that are gone are dropped silently.
8. **Rule 12.** The MCP `search` tool gains `tag` and `file` (`types` up to five, default all
   five). A file result is metadata — name, mime, target — never a URL or bytes (AI.md §7).
   **Public API: no new endpoint**, for this reason: the palette is a client view over the
   replica; the key surface already has `q` on tasks and notes and full lists of projects,
   tags and files, and ADR-0013 §4 keeps server search secondary.

## Alternatives considered

- **A separate Search section / screen.** A destination nobody navigates to; the palette is
  one keystroke from everywhere and leaves the five sections alone.
- **A sixth app-bar icon on phones.** Cuts Home's title again (OPH-359's fix) and repeats
  per-screen search's icon with a different meaning.
- **Searching file names in Dart** (`foldSearchText(name).contains`). Works, but bypasses the
  registry the reachability gate guards and becomes a second matcher.
- **Binding both ⌘K and Ctrl+K everywhere.** Breaks Ctrl+K kill-line in every macOS field.
- **Recording recents only from palette picks.** Misses the common case: the thing you were
  just in, opened from a list.

## Consequences

- `check:search-reachable` counts 11 entities, all reachable.
- The phone bar shows only the selected tab's label on most phones; tests that tapped a tab by
  its text at phone width tap its icon now. The owner may prefer the app-bar icon instead —
  recorded as an open review in DEVICE-CHECKS.
- Browser ⌘K/Ctrl+K: Flutter web prevents the default only when the framework handles the key;
  a real-browser check is queued (DEVICE-CHECKS).
- A future "show all" for a group belongs to the screen's own search, not the palette.
