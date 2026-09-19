# ADR-0040 — `files.target_type` is a registry, not a list

- **Status:** Accepted
- **Date:** 2026-09-19
- **Related task:** OPH-325 (Epic 31)
- **Revises:** [ADR-0011](0011-attachments-r2-s3-storage.md) §3 (the column's shape)

## Context

`files` has been polymorphic since the day it was created: one table, a
`target_type` + `target_id` pair naming the owner, and the project "Files" tab as
a query rather than a join table (ADR-0011). The set of owners has been an ENUM
in the column, and widening it has meant a migration — twice already:
`project|task|note` on 2026-07-18, plus `workspace` two days later when folders
landed (ADR-0014).

That is a sound arrangement while every attachable thing lives in this
repository. It stops being sound the moment an extension has one. An extension
may not ALTER a core table (it is a separate repository with its own migration
directory joined into the same chain), so the closed list makes "can this kind
of thing have files?" a question only core can answer — about entities core
knows nothing about.

The alternative the extension would be forced into is its own table, and that is
the option worth naming because it looks cheap: a second file table with a second
upload lifecycle, a second cascade and a second garbage collector. The bytes are
in object storage; the only thing that ever removes them is the sweep walking
core's rows. A second table means a second place to leak, and the way anyone
finds out is a storage bill.

## Decision

**The column becomes `varchar(32)` and the accepted set becomes a registry the
build fills at boot.**

1. `app.ee.attachmentTargets` — populated through `seam.registerAttachmentTarget(type, check)`,
   the ARCHITECTURE §3b pattern every other extension hook already uses.
2. `check` is `async ({ app, db, request, workspaceId, targetId }) => boolean`,
   called by the upload-init route AFTER `requireWorkspaceMember`. It answers the
   one question core cannot: *is this a real target of this workspace, for this
   caller?* Returning `false` produces the same `FILE_INVALID_TARGET` a bad core
   target produces — a caller probing ids must not be able to tell "no such
   thing" from "not yours". Throwing is how an extension says something
   different (a missing verb is a 403, and saying so leaks nothing: the caller is
   already a proven member).
3. **The request schemas are built from the registry at route registration.** The
   seam's contract is that the overlay registers before any route does, so the
   list is final by then — and in a plain build it is exactly the four values
   this repository owns.
4. The registry may not shadow a built-in kind, and a type must be a short
   snake_case name (it travels in URLs and JSON).
5. Core registers nothing and reads nothing from it. `app.ee.attachmentTargets`
   is `{}` in every plain build, which is what makes point 3 a tautology there.

## Alternatives considered

| Alternative | Why it lost |
| --- | --- |
| Leave the ENUM; add values as extensions need them | Core would carry names for entities it has no code for, and every extension release would need a core migration. The dependency runs the wrong way. |
| A second table owned by the extension | Two upload lifecycles, two cascades, two garbage collectors. ADR-0016 §D16.2 settled this from the other side: "a second file path is a second garbage-collection bug." |
| `target_type` free-form, validated nowhere | The ENUM was doing real work — a typo became a driver error instead of a row pointing at nothing. The registry keeps the refusal and moves it up one layer, where it can be a documented 400. |
| Registry holds a TABLE name, core does the query | Simpler, and not enough: the extension's rule is not only "does the row exist" but "may this person contribute to it", which is a permission core does not have. A function says both. |

## Consequences

**Easier.** An extension can give its own entities attachments with no core
change, and they ride the lifecycle that is already tested: presigned upload,
completion check, soft delete, the sweep, the quick-link cascade.

**Harder.** The accepted set is no longer visible in the schema. `SHOW COLUMNS`
used to answer "what can have a file"; now the answer is the boot-time registry,
and the place to read it is this document plus whatever the build registered.
The response schema lost its `enum` for the same reason — a serializer that still
listed four values would be deciding which attachments may be described.

**The rollback is the lossy direction, and it refuses rather than truncating.**
`down()` throws if any row holds a type the old ENUM cannot store, because
narrowing would replace those values with an empty string: a file pointing at
nothing, which is worse than an error.

## Enforcement

| What | Who enforces it |
| --- | --- |
| A plain build accepts exactly the four core kinds | `test/unit/ee-seam.test.js` — CE refuses a kind no build registered, and `app.ee.attachmentTargets` is asserted empty |
| A registered kind is accepted, an unknown id is refused | Same file, with the fixture overlay: upload to a registered target succeeds; a random id gets `FILE_INVALID_TARGET` |
| The four built-in kinds keep working unchanged | Same case ends by attaching to a task through the normal path; `test/unit/files-read.test.js` covers the rest |
| A type cannot shadow a core kind, or be malformed | `registerAttachmentTarget` throws at registration — boot fails loudly rather than a route accepting something unroutable |
