# ADR-0018 — Quick Links: the first user-scoped sync entity

- **Status:** Accepted
- **Date:** 2026-07-29 (planning, feedback/request round 11)
- **Related task:** Epic 18 (OPH-196…OPH-203) — request round 11 #1
- **Related:** [ADR-0014](0014-folders-and-global-files.md) (the previous "new sync
  entity" precedent), [ADR-0016](0016-in-app-url-routing-and-widget-actions.md)
  (navigation-only URL rule this feature leans on), BLUEPRINT §4.12 / §12.15,
  DESIGN §23

## Context

Request round 11 asks for **Quick Access** ("Hızlı Erişim"): a Notion-style personal
list of shortcuts — projects, tasks, notes, folders, files and external URLs — with a
user-chosen emoji, color and manual order, shown as a sidebar section on wide layouts
and as a draggable floating button on phones. The explicit requirement is **"the same
list on every platform"**, which means the list must sync.

Every synced entity so far (project, task, tag, note, folder, file, external event…)
is **workspace-scoped**: the pull endpoint returns every changed row in the workspace,
and every member converges on the same replica. Quick links break that assumption:
they are **personal**. Workspaces are multi-user by schema (`workspace_members`,
Epic 02 — sharing UI is parked, not the schema), and one member's navigation
shortcuts must never appear in another member's sidebar. A "favorites" list that
leaks across members would be wrong today and embarrassing the day sharing ships.

Constraints: the sync protocol's core (workspace-monotonic `revision`,
`sync_revisions` rows, idempotent `clientMutationId` push, incremental pull) is
proven and must not fork; the app is local-first (the sidebar and the bubble read
the drift replica, offline included); MySQL stays canonical.

## Decision

`quick_link` becomes a **push-pull sync entity that is workspace-stored but
user-filtered** — the first user-scoped entity in the protocol.

1. **Storage:** one table, `quick_links`, carrying both `workspace_id` and
   `user_id`. Revision bookkeeping is unchanged: every write bumps the workspace
   revision and inserts a `sync_revisions` row in the same transaction
   (`recordSyncWrite`), exactly like every other entity.
2. **Pull:** the pull handler adds a single per-entity filter — `quick_link` rows
   are returned **only when `user_id` = the authenticated user**. Other members'
   writes still advance the workspace revision their pulls see; the rows simply
   are not included. Convergence is unaffected: a client that receives nothing for
   a revision has nothing to apply. No second cursor, no second channel.
3. **Push:** mutations validate ownership. A mutation touching a `quick_link` row
   whose `user_id` differs from the caller is rejected with a stable code
   (`QUICK_LINK_NOT_YOURS`); create stamps the caller's `user_id` server-side
   (never trusted from the payload).
4. **Referential integrity by cascade:** hard-deleting a target (task subtree,
   project, note, folder subtree, file) deletes the quick links pointing at it
   **in the same transaction**, with normal revision bumps, so every device's
   panel heals itself on the next pull. Archiving does **not** cascade — archives
   are reversible, and the link stays (rendered muted, DESIGN §23).
5. **Internal targets are stored as `kind` + `target_id`**, never as route
   strings or `alliswell://` URLs. Routes are a client concern (ADR-0016);
   ids survive renames and router refactors. External links are `kind = 'url'`
   with an `http(s)` URL and no `target_id`.

## Alternatives considered

- **Device-local storage (no sync).** Cheapest, and how the board/view
  preferences work. Rejected: the request is explicitly "the same list
  everywhere", and a hand-curated list is exactly the kind of data a user
  expects to survive a device change.
- **A separate user-scoped sync channel** (per-user revision counter, second
  pull cursor). Cleanest in theory; rejected as a second pipeline to build,
  test and reason about for the benefit of a single ≤50-row entity. If more
  user-scoped entities accumulate (reminder profiles and date-format settings
  are parked candidates), this ADR is the natural place to supersede.
- **Workspace-scoped favorites (shared list).** Simplest protocol-wise;
  rejected on product grounds — it answers a different question ("our pinned
  pages") than the one asked ("my quick access"). A shared team list is parked
  as a v2 idea, additive on top of this design.
- **Reusing the existing pin/favorite stars.** The stars sort their own list
  in place; they do not compose a cross-entity navigation list, cannot hold
  URLs, and their semantics (sort hint) would silently change. Two features,
  two affordances (DESIGN §23 Q2).

## Consequences

- The pull handler gains its first per-entity row filter. It is one `where`
  clause, but it is **protocol precedent**: entity handlers may scope rows by
  user. The integration suite gains a two-user isolation test (member A's link
  never reaches member B's pull) that pins the behavior forever.
- Delete paths for five entities gain a `quick_links` cleanup join — the same
  pattern as the attachment cascade, and covered by the same transaction tests.
- The replica gains a small table (drift v13) and every client a
  `QuickAccessStore`; UI reads stay local-first and offline-correct.
- A cap (50 links per user per workspace) keeps the sidebar, the bubble panel
  and the pull payload honest; the API enforces it with `QUICK_LINK_LIMIT`.
- Future user-scoped entities (server-side settings store is already parked)
  inherit a decided pattern instead of re-opening the debate.
