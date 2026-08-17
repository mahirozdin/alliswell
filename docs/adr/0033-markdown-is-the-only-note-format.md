# ADR-0033 — Markdown is the only thing a note is made of

- **Status:** Accepted
- **Date:** 2026-08-18
- **Related task:** OPH-274
- **Binding documents:** [MARKDOWN.md](../MARKDOWN.md) · [DESIGN.md §29](../DESIGN.md)
- **Supersedes:** [ADR-0028](0028-markdown-document-model-and-renderer.md) §1
  (the note model). ADR-0028 §2 (our own renderer over the `markdown` package)
  and §3 (how far diagrams go) stand unchanged and are, if anything, load-bearing
  now — they are the only renderer left.

## Context

ADR-0028 §1 answered "what is a note made of" with **Option C — split by
intent**: a note is either Delta-canonical (the rich editor wrote it) or
markdown-canonical (it came from a file, or the user converted it on purpose),
recorded in a `content_format` column defaulting to `'delta'`. The migration
touched zero rows, which was the decisive argument at the time.

The owner has decided that rich text goes away entirely. That is a product
decision, and it does not need this document to justify it. What this document
records is what the decision *cost*, what it *bought*, and the four things that
had to be true for it to be safe — because every one of them is a place a
future change could quietly break somebody's notes.

Three measurements from the intervening rounds argue that the split had become
the expensive answer rather than the cheap one:

1. **`flutter_quill` 11.5.1 has no table node**, and Delta has no
   representation for footnotes, math, diagrams or nested lists. That was
   already true when ADR-0028 was written and was the reason it needed writing.
   What changed is that OPH-247…252 shipped all of those in the renderer — so
   half of what a note could DISPLAY, it could not BE.
2. **The three-way merge refused to run on Delta notes.** `threeWayNoteWrite`
   returned `NOT_MARKDOWN` unless all three sides were markdown-canonical
   (ADR-0031 decision #7 — you cannot line-merge a JSON op array and get a
   document back). Epic 25 built a conflict engine, and the app's own notes —
   which is to say all of them — were exactly the case it declined to handle.
3. **Two canonical fields split every write path in two**: saving, exporting,
   versioning, merging, and the search index. OPH-261 was an entire task
   spent repairing one branch of that fork (`plain_text` was derived only when a
   Delta arrived, so a markdown note was invisible to search), and the client
   half of the same defect was still live on the day this ADR was written.

## Decision

### 1. A note is markdown. There is no second form.

`notes.content_markdown` is the canonical content. `content_format` is
`'markdown'` for every row, `NoteFormat` is gone from the client, and
`NoteMode` is `{source, reading}` — two modes, both available to every note.

This retires the **D1 amendment** ADR-0028 forced on DESIGN §29. D1 asked for
"exactly three modes"; Option C could not honestly offer all three (a note
could only be edited in the surface matching its canonical form), so the
amendment narrowed D1 and reached the third mode through a warned, one-way
conversion door. With one form there is nothing to convert to, no mode a note
cannot honour, and no disabled segment — which is what §22 wanted all along.

### 2. `content_delta` is never written again, and never dropped.

The column stays in both schemas (MySQL and the drift replica) holding its
pre-2026-08-18 rows. Nothing reads it at runtime and nothing adds to it.

Keeping it is not indecision. It is what makes the migration reversible in the
only sense that matters — a human can read the original document — without
requiring a `down()` that would have to un-convert, which is impossible. The
migration's `down()` therefore restores the column DEFAULT and deliberately
leaves converted rows alone: flipping a live note back to a delta that has not
been maintained since would silently discard every edit made in between.

### 3. A Delta may still ARRIVE. It is converted, never refused.

The web client updates the moment we deploy; the phone in someone's pocket runs
the previous release for weeks. That client sends `contentDelta`,
`contentMarkdown` and `contentFormat` on every autosave, so the server takes the
markdown, derives it from the ops when that is what the write means, and drops
the delta. `noteMarkdownFrom` (`db/notes.js`) is the single place that decides;
REST, sync push, MCP, import and the conflict-capture path all call it.

**A protocol that breaks its own old clients is not a protocol.** The Ajv
schemas keep accepting `contentDelta` and the `'delta'` format value, marked
deprecated; the `notes_content_format_chk` CHECK constraint still permits both.

One normalization detail earns its own sentence, because getting it wrong is
invisible until a user complains: the previous release prefixed `# $title` onto
the markdown it derived for export. Storing that verbatim would make every
migrated note render its title twice. A Delta-canonical write is therefore
re-derived from the ops rather than trusted, and the leading-H1 strip is a
fallback that only fires when the write declares itself Delta-canonical — a
markdown note never had the prefix added, so a heading somebody actually typed
survives.

### 4. Note bodies stay in MySQL. R2 stays for files.

Considered and rejected, so it is not re-litigated:

- **The storage layer is OPTIONAL config.** With `STORAGE_S3_*` unset the API
  boots and answers `STORAGE_NOT_CONFIGURED` (`plugins/storage.js`). Moving note
  bodies there would make notes unreadable on every self-hosted install that has
  not configured object storage. This alone is decisive.
- **`FULLTEXT ft_notes_plain_text`** backs the REST `?q=` filter and the MCP
  search tools. A body in R2 has no index.
- **The three-way merge reads its base body synchronously, inside the request's
  transaction** (`note_versions` by `(note_id, note_revision)`). An object-store
  round trip there is a network call inside a database transaction.
- **The sync pull embeds each note's body in its change row.** N bodies would
  become N round trips before the response could be assembled.
- **Note bodies are small.** ADR-0031 already used this to reject storing diffs
  instead of snapshots; the API caps a body at 1,000,000 characters, and real
  ones are three orders of magnitude under that.

`files` continues to use presigned direct transfer exactly as ADR-0011
describes, and note embeds continue to reference files by
`alliswell://file/{id}` — an id, never a URL.

## Consequences

### What this buys

- **Every conflict is mergeable.** The `NOT_MARKDOWN` outcome is gone from
  `threeWayNoteWrite` because it can no longer happen. Epic 25's merge engine
  now runs on the notes people actually have — proven over real MySQL in
  `test/integration/note-merge.test.js`, including a push shaped exactly like
  the previous release's.
- **The MCP assistant can edit any note.** `update_note` refused a body rewrite
  on Delta notes with `NOTE_NOT_MARKDOWN`, so the assistant could rename a note
  it was not allowed to edit. That refusal is gone with its cause.
- **Tables, nested lists and footnotes reach the PDF.** Export ran through
  `deltaToBlocks`, so a table in a note could not appear in an exported file —
  a document-model gap, not a rendering one. `markdownToBlocks` replaces it.
- **Offline search sees every note.** The client never grew the
  `plainTextFromMarkdown` twin the server got in OPH-261, so markdown-canonical
  notes carried an empty local search column. One canonical field, one
  derivation.
- **Eleven packages leave the tree** with `flutter_quill`, including the
  `quill_native_bridge_*` pods on iOS and macOS.
- **Attachments stop vanishing.** A file that was neither image nor video had no
  Delta node, so it was attached with nothing in the document and an apologetic
  snackbar. Markdown has a link; the reading view opens it.

### What this costs

- **Text colour is gone.** GFM has no syntax for it, so `aw:text-*` had nowhere
  to live. DESIGN §33 R6 had already parked it with that reason. The
  highlight survives as `==mark==`, drawn from the same named palette.
- **WYSIWYG is gone**, replaced by live syntax in the source field
  (Obsidian/Typora style, DESIGN §29 D24). Within a real `TextField` the syntax
  can only be dimmed, never hidden: a `TextEditingController` must return
  exactly the characters of `text`, or every caret offset, selection and IME
  composition after the first difference points at the wrong character.
- **`content_delta` is dead weight in two schemas.** Accepted, per decision 2.

### Follow-ups this creates

- The markdown renderer and editor become extractable — nothing about them is
  AllisWell-specific except three ambient dependencies (`AwTokens`, i18n and a
  riverpod image resolver). OPH-274 packages them as
  `apps/app/packages/markdown_forge` behind injected seams, for publication
  under the `bubiapps` organisation.
- `src/lib/delta.js` and `delta_markdown.dart` survive only to convert incoming
  writes and the replica's old rows. They go when the last pre-2026-08-18 client
  does. The 2026-08-18 migration carries its own frozen copy of the converter
  for exactly this reason — a migration must keep doing what it did on the day
  it ran.
