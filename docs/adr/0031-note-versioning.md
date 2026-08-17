# ADR-0031 — Note versioning: server-owned history, coalesced at the head

- **Status:** Accepted
- **Date:** 2026-08-17
- **Related task:** OPH-267 (Epic 25, P4; gate for OPH-268 and OPH-269)
- **Related:** [ADR-0028](0028-markdown-document-model-and-renderer.md) (which
  field is canonical — this table carries all three), [ADR-0022](0022-remote-mcp-server.md)
  §4 (the domain layer capture rides on), [ADR-0032](0032-api-keys.md) (the
  `origin='api'` writer), [BLUEPRINT §6.5](../BLUEPRINT.md), DESIGN §35

## Context

Round 18 opened with a measured bug, not a feature request: **an overwritten
note body was gone.** The survey found four layers to it, and this ADR answers
the one underneath all of them — finding #4, in as many words: *the overwritten
note body is in no table. `sync_revisions` records only which fields changed;
there is no body history.* A conflict copy, a merge, a restore and an undo all
need the same missing thing: **the bytes that were there before.**

The second measured fact shapes the mechanism. Finding #5: the editor autosaves
on a **1.5-second idle debounce**, sending the whole body (`note_editor_screen.dart`).
A person typing for ten minutes produces on the order of *260 writes*. A naive
row-per-write history is not history; it is a transcript nobody can read and a
table nobody can afford.

Twelve products and systems were surveyed before choosing (the owner's standing
condition: at least five sources). The table is kept here because the decisions
below are only defensible next to it:

| Product / system | Mechanism | Verified numbers / lessons | Source |
| --- | --- | --- | --- |
| Google Docs | OT + append-only revision log; every change carries a **base revision** ("what the editor saw"); unnamed revisions are merged over time, named ones are pinned | 40 named versions per doc; deleting version history is permanent | idl.uw.edu 2010 OT whitepaper · support.google.com/docs/answer/190843 |
| CouchDB / PouchDB | MVCC revision tree; both conflicting branches are **kept**, with a deterministic winner; resolution is the application's job | compaction drops bodies, keeps the lineage (`_revs_limit`) | docs.couchdb.org/en/stable/replication/conflicts.html |
| Obsidian Sync | Automatic merge for markdown (diff-match-patch), LWW elsewhere; per-device "merge / conflict file" choice since 1.9.7 | history 1 month (Standard) / 12 months (Plus); copies named `(Conflicted copy device YYYYMMDDHHMM)` | obsidian.md/sync · obsidian.md/help/sync/troubleshoot |
| Joplin | **No merge** — the local version is copied into a Conflicts notebook (its most-complained-about UX); restore does not change the current version | a version every 10 minutes; 90 days by default; retention resolves to the **minimum across devices** → policy belongs on the server | joplinapp.org/help/apps/note_history |
| Standard Notes | versions at ≥5-minute intervals; in-device (free) + remote (paid) history; "Restore" **and** "Restore as a copy" | plan day-counts not verifiable from the official page (bot 403) — flagged | standardnotes.com/help/26 |
| Figma | OT rejected ("unnecessarily complex"), not full CRDT either: **per-field LWW**, text as one property | lesson: LWW suffices for scalar fields; the body needs its own treatment | figma.com/blog/how-figmas-multiplayer-technology-works |
| Yjs / Automerge | character-level automatic merge; history inside the structure | Yjs ~53 % overhead on a real trace; **no maintained Dart port** → FFI risk across six platforms | blog.kevinjahns.de · automerge.org/docs |
| git / diff3 | three-way merge, the gold standard; a conflicting hunk is never silently resolved | the diff3 paper: guarantees hold only in "well-separated" regions — markdown's one-line paragraphs mislead line-level merging → **word-level refinement is required** | cis.upenn.edu/~bcpierce/papers/diff3-short.pdf |
| Notion | page history grouped by day; after a restore you can still go back to any point | 7 days Free / 30 Plus / 90 Business / unlimited Enterprise | notion.com/help/duplicate-delete-and-restore-content |
| Dropbox | "Conflicted copy" naming convention; no merge attempted | 30 / 180 / 365-day tiers | help.dropbox.com/organize/conflicted-copy |
| Libraries | **node-diff3** (MIT, zero deps, active) as the merge engine; **jsdiff** for word-level refinement and history diffs; **diff-match-patch was archived by Google on 2024-08-05** — and fuzzy patching was already unwanted (it is why Obsidian warns it "may produce duplicates"); **no three-way merge package exists on pub.dev** | → merging happens on the SERVER | github.com/bhousel/node-diff3 · github.com/kpdecker/jsdiff |

## Decision

1. **History lives on the server and does not descend to the replica.** A
   version row is never a sync entity: `SNAPSHOT_LOADERS` and `ENTITIES` are
   untouched, and the history screen is an online surface (DESIGN §35 V6).
   Joplin's trap is the argument — when retention is negotiated across devices
   it collapses to the *minimum* any device kept, so a phone that was offline
   for a month silently truncates a laptop's history. Policy that only one
   party can enforce belongs to that party.
2. **Capture is ONE function, deliberately not one call site.** The function is
   `captureNoteVersion`; the domain layer calls it (`db/notes.js` —
   `createNote` and `updateNote`), which covers REST, MCP, an API key and bulk
   import at once, none of them knowing history exists. **The sync push engine
   is the exception, and it is written down rather than glossed:** the generic
   `ENTITIES` machinery in `routes/sync.js` has been its own implementation
   since OPH-218 (different shapes, field-level LWW semantics), so it calls the
   same function through its own `afterCreate`/`afterUpdate` seam. Two call
   sites, one policy — the alternative, letting the offline path write no
   history, would mean the writer most likely to overwrite somebody is the one
   that leaves no trace.
   A capture point callers must *remember* to call is one that will be missed;
   these two are the total set, and a test pins that number.
3. **The head coalesces; older versions do not.** A write whose predecessor is
   the same note, the same `client_id`, `origin='edit'` and less than
   `NOTE_VERSION_COALESCE_MIN` (default 10) minutes old **updates that row in
   place** — a rolling head. Anything else inserts. This is the measured answer
   to finding #5: a ten-minute typing session leaves one row, not 260, and the
   ten-minute window is exactly Joplin's (the one number in the survey with a
   decade of production behind it). Coalescing is deliberately **not** applied
   to `conflict`, `merge`, `restore`, `import` or `api` writes: those are events
   somebody may need to point at.
4. **Identical bodies do not stack.** Every row carries a `content_hash`
   (SHA-256 over title + canonical format + both body fields); a write whose
   hash equals the previous version's writes no row at all. An autosave that
   fires after a cursor move is not a version.
5. **All three content fields are stored, plus the format.** Which field is
   canonical *is* the document's identity (ADR-0028 §1); a version that kept
   only "the body" would restore a markdown note as rich text, or the reverse.
   The version records what the note WAS, format included.
6. **Retention is a server policy with three tiers** (env-tunable): untouched
   for 7 days, thinned to one per note per day from 7 to
   `NOTE_VERSION_RETENTION_DAYS` (90), deleted after that — except
   `conflict|merge|restore|import` rows, which live `NOTE_VERSION_PROTECTED_DAYS`
   (365), because those are the ones somebody comes looking for. A per-note cap
   (`NOTE_VERSION_CAP`, 500) thins from the oldest end. The sweep is a daily job
   on the storage-GC precedent.
7. **Restore never rewrites history.** `mode: 'replace'` applies the old body as
   a NEW head write (`origin='restore'`), so the state you are leaving is itself
   captured and you can go back again — Notion's behaviour, and the inverse of
   Joplin's "restore does not change the current version" surprise.
   `mode: 'copy'` produces a new note instead (Standard Notes' second verb),
   which is what people actually want when they are not sure.
8. **Diffs are computed on the server** (`jsdiff`, word level) and the client
   only draws them. `node-diff3` enters with this ADR as the merge engine
   OPH-268 will use: pub.dev has no three-way merge, and two merge engines in
   two languages would produce two answers to the same question.

## Alternatives considered

- **A CRDT (Yjs/Automerge) for note bodies** — automatic merge and history for
  free, and rejected on platform reach: no maintained Dart port, so six
  platforms would ride an FFI binding, plus ~53 % storage overhead on a real
  trace. Figma reached the same conclusion from the other direction.
- **Version per write, no coalescing** — honest and unusable: ~260 rows per
  ten minutes of typing, a history screen nobody can read, and a table whose
  growth is driven by keystroke rhythm.
- **Client-side history in the drift replica** — free storage and offline
  reads, but it is Joplin's minimum-across-devices trap plus a second place to
  leak from, and the conflict machinery (OPH-268) needs the *server* to hold
  the losing side anyway.
- **Storing diffs rather than snapshots** — smaller, but every read becomes a
  replay, a single corrupt link poisons everything after it, and note bodies
  are small. Snapshots + retention is the boring, restorable choice.
- **Naming versions (Google Docs' pinned revisions)** — a good idea with no
  demand yet; the `origin` column already distinguishes the rows that matter.
  Additive later.

## Consequences

- `note_versions` grows with editing, bounded by the retention tiers and the
  per-note cap. Self-hosters can tune all four numbers; the defaults are sized
  for a personal instance.
- Capture sits inside the note write transaction, so a version and the write it
  describes commit together or not at all — but every note write now costs one
  extra INSERT (or UPDATE, at the coalescing head).
- The history screen is online-only: offline, it says so rather than showing a
  stale list (the OPH-265 rule).
- `origin` is the seam the rest of the epic hangs on: OPH-268 writes `conflict`
  and `merge` rows, OPH-266's import gets `origin='import'` wired here, and the
  UI (OPH-269) labels rows by it.
- Deleting a note takes its versions with it (`ON DELETE CASCADE`) — history is
  part of the note, not a shadow that outlives it.
