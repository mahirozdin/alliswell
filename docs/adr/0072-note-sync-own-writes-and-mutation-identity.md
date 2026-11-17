# ADR-0072 — A note's own device never conflicts with itself, and a sent mutation is never rewritten

- **Status:** Accepted
- **Date:** 2026-11-18
- **Related task:** OPH-486, OPH-487, OPH-488, OPH-489, OPH-490, OPH-491, OPH-492, OPH-493
- **Related:** ADR-0031 (note versions), ADR-0033 (markdown is canonical), ADR-0007 /
  BLUEPRINT §6.5 (document-level lock for notes), [.claude/rules/sync.md](../../.claude/rules/sync.md)

## Context

On 2026-11-18 the owner created a new note on one computer. While they typed, the app said
"this note was edited on another device too", and the banner's other side was empty. Later the
web showed half of the note, and a version labelled "not this device" held the full text. Nobody
else had touched the note. Every cause below was reproduced against the real server and the real
client before the fix:

- **H1, base 0.** A save queued before the note's create had an answer carried
  `baseRevision: 0`. No version exists at revision 0, so the server answered `BASE_MISSING`: a
  conflict against the device's own create, and the server body stayed empty.
- **H2, a rewritten sent row.** The outbox coalesced a newer note body into the OLDEST pending
  update row, even one a push had already carried. The server keyed idempotency on
  `(client_id, client_mutation_id)` only, replayed its first answer, and the newer text was lost
  with no version anywhere. A lost answer (timeout) did the same with no slow network.
- **H3.** A refusal changed nothing in the replica, and "use the other one" only cleared a
  pointer, so the next save silently made it "use mine".
- **Stale-base self-conflicts.** The rolling-head version (ADR-0031 §4) erases intermediate
  revisions, diff3 refuses even a pure append, a body identical to the server's still conflicted,
  and a refused body stored at the revision it lost against won the merge-base lookup.
- **Client edges.** A pull overwrote a body whose save was still queued; the editor's close-flush
  used `ref` after unmount (error swallowed, last 1.5 s lost); the `/notes/new` editor never saw
  its own note; selection moves autosaved; a provider rebuild re-showed the last conflict.

## Decision

**Server (backwards compatible, protects installed clients first):**

1. `baseRevision: 0` is "no answer reached this device yet" and is an ordinary write.
2. A content write applies without a merge when its body equals the current body, or when every
   sync write to the note after its base came from the same `clientId` (attributed through
   `client_mutations.result_revision`, as `foreignChangesSince` already does). A REST or MCP
   write — no client id, or another one — is foreign and keeps the three-way merge.
3. The merge base never reads an `origin = 'conflict'` version. There is no "nearest version"
   fallback: a wrong base silently deletes lines, so a missing base stays an honest conflict.
4. `client_mutations.payload_hash` (SHA-256 of operation, entity, patch and base; not
   `localUpdatedAt`) is recorded with every answer. A resend with the same hash replays; a
   different hash under a recorded id is a new write: the old record moves to a fresh id (keeping
   its `result_revision`, so its write stays this client's own) and the mutation is processed.
   Rows from before the column replay as before.

**Client:**

5. `pending_mutations.sent_at` (replica v41, null for existing rows) is set in the same
   transaction that reads a push batch, and kept through failures. Coalescing only merges into
   rows with `sent_at` null; a save behind a sent row is a row of its own.
6. A save while the note's create is still unsent rides in the create. A content update of a note
   whose replica revision is 0 sends no base.
7. When a note row is **applied** (not merged), the note's unsent update rows that carry its base
   move to the result revision. On **merged**, if another save of the note is queued, the replica
   keeps its body and revision: the queued body lacks the merged lines, so its base must not
   claim them.
8. A pull keeps a note's title, body and revision while a create or update of it is queued; the
   other fields are taken.
9. "Use the other one" fetches the server's note over REST and writes it to the replica, unless a
   save of the note is queued (that body is newer and is kept). The server does not attach a
   rebase to `NOTE_CONTENT_CONFLICT`: the answer to it is only needed when the person chooses.

## Alternatives considered

- **Refusing a reused id with `SYNC_MUTATION_ID_REUSED`** (the investigation's first plan): an
  installed client treats any `rejected` as a refusal, parks it and rebases its replica to the
  server body — it would have thrown away the very text the check exists to save. Processing the
  payload as a new write lets old clients keep what they typed.
- **Merging against the nearest older version** when the exact base is gone: produces clean-looking
  merges that drop lines. Rejected.
- **Re-routing `/notes/new` to `/notes/:id` after the create**: rebuilds the editor and loses cursor
  and focus. The new-note editor follows the replica's copy instead.

## Consequences

- A device continuing its own session never sees a conflict; a real second writer still gets the
  banner and both bodies are kept.
- An old client's coalesced rows now land instead of vanishing; an old client still sends base 0
  for early saves, which the server now applies.
- `client_mutations` and `note_versions` each gained one nullable column (append-only migrations).
- With an OLD self-hosted server, a new client whose push answer was lost may still see one false
  conflict on the save behind it (both bodies are kept as versions); upgrading the server ends it.
- OPH-494 (device and time in history) adds `deviceName`, `devicePlatform` and `updatedAt` to the
  note-version REST rows and `current` to the diff. MCP has no note-version tool (history is a REST
  surface, ADR-0031), so there is nothing to extend there (I-12). Only the caller's own devices
  are named; another member's device reads as "a device not in your device list".
