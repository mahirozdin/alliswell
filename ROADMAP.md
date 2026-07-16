# AllisWell Roadmap

Where AllisWell is and where it's going. Generated from the phase plan in
[BLUEPRINT §14](docs/BLUEPRINT.md) and kept honest against the real state in
[docs/STATE.md](docs/STATE.md) and the backlog in [docs/TASKS.md](docs/TASKS.md).

**Legend:** ✅ shipped · 🟡 partial (rest deferred) · ⏳ planned · 💤 v2 parking lot

> This file is a summary. The authoritative, task-by-task status is
> [docs/TASKS.md](docs/TASKS.md) (epics OPH-001…OPH-095); the live pointer to
> "what's next" is [docs/STATE.md](docs/STATE.md). When they disagree, they win.

---

## v0.1.0 — the MVP (current)

Everything through **Phase 4** is shipped and verified. That is a complete
single-workspace productivity hub: sign in, capture and plan tasks, keep
projects and notes, work fully offline with local-first sync, get exact-time
reminders, and two-way sync your tasks with Google Calendar (plus your own
calendar events flowing back in). See [release notes](#release-history).

### Phase 0 — Foundation ✅

Monorepo (npm workspaces), full docs set, AGPL-3.0, Docker Compose (MySQL 8.4 +
Redis 8), Fastify API skeleton, Flutter 6-platform shell, GitHub Actions CI.
_Epic 01._

### Phase 1 — Core domain ✅

Auth (argon2id, JWT + rotating refresh tokens, reuse detection), workspaces,
projects, tags, tasks (subtasks, checklists, filters, urgent/remind fields,
snooze), and notes (Delta-canonical, FULLTEXT search, markdown export). Flutter
screens for all of it. _Epics 02, 03, 04, 05._

### Phase 2 — Local-first sync ✅

The app reads and writes a local SQLite replica; every write queues in an outbox
and pushes idempotently with field-level last-write-wins conflict resolution;
pulls converge every device; a Socket.IO channel fans changes out within a
round-trip. Offline is the default, not a fallback. _Epic 06._

### Phase 3 — Reminder system ✅

Local notifications on every platform, scheduled from the replica with
content-hash diffing; snooze presets; urgent alarms that demand acknowledgement
with a re-alert chain; a privacy mode that hides task content on the lock
screen. Delivery strategy researched and documented in
[docs/NOTIFICATIONS.md](docs/NOTIFICATIONS.md). _Epic 07._

> ⏳ **Device pass pending:** exact-delivery behaviour (Doze, alarm-clock icon,
> Focus break-through) is device-observable only. The logic layer is fully
> unit-tested; a run on real Android + iOS hardware is the remaining step.

### Phase 4 — Calendar sync ✅

- **Google (server-side, always-on):** OAuth with encrypted tokens, task→event
  mirror, push-notification webhook, incremental `syncToken` sync, and a
  two-way conflict policy (etag echo-suppression, foreign edits applied to the
  task, tombstone handling). Your own calendar events flow back into Home and
  the Calendar tab as a read-only entity.
- **Apple (device-side):** an EventKit bridge — permission, calendar list, and
  a task→event mirror that runs in the app (Apple has no server API). One-way
  in v1.
- **CalDAV:** [design doc](docs/CALDAV.md) only (v2 scope).

_Epic 08. ADRs [0006](docs/adr/0006-google-oauth-token-crypto-and-mirror-queue.md),
[0007](docs/adr/0007-google-inbound-sync-and-conflict-policy.md),
[0008](docs/adr/0008-external-calendar-events.md)._

> ⏳ **Device pass pending:** the EventKit write round-trip is device-only.
> **macOS build** needs a local signing certificate (iOS builds today).

---

## Toward v0.2.0

### Phase 5 — Rich notes & documents 🟡

Shipped: the flutter_quill editor, Delta storage, client + server markdown
export, and note↔task/project links. _Deferred to v2:_ project documents (a
block editor), richer backlinks, and a global search screen.

### Phase 6 — Polish & open-source readiness 🟡 (in progress)

Shipped: the "AllisWell Glass" design system (light/dark, WCAG-verified,
[ADR-0005](docs/adr/0005-alliswell-glass-design-system.md)), accessibility pass,
CONTRIBUTING / SECURITY / issue + PR templates, **this roadmap**, and
**release automation** (a tagged GitHub Actions release pipeline). ⏳ Remaining:
import/export from other apps, a performance pass, and packaged distribution
(Docker image publish, TestFlight/F-Droid).

---

## v2 parking lot 💤

Deliberately out of scope for v1 — schema-ready or designed, not built:

- Multi-user workspace sharing & roles UI (the schema already supports members).
- Project documents (block editor); Kanban & timeline views; smart-list / filter DSL.
- Attachments (S3-compatible); import from Todoist / TickTick / Apple Reminders; ICS export.
- CalDAV connector for iCloud ([design](docs/CALDAV.md)); the inbound half of the Apple mirror.
- Metrics endpoint (Prometheus), audit-log UI, admin panel.
- E2E tests (Patrol / integration_test), web httpOnly refresh-cookie hardening.

---

## Tracking

Day-to-day status lives in the repo, not a separate tool:

- **[docs/STATE.md](docs/STATE.md)** — the live "what's done / what's next" pointer.
- **[docs/TASKS.md](docs/TASKS.md)** — the full backlog, every OPH-xxx task with acceptance notes.
- **[CHANGELOG.md](CHANGELOG.md)** — what changed, per release.

A GitHub Projects board can be layered on top of these if the project grows a
team; for now the markdown files are the single source of truth (and they are
what the AI-agent workflow reads and updates — see the README).

<a id="release-history"></a>
## Release history

See [CHANGELOG.md](CHANGELOG.md). Releases are cut by pushing a `vX.Y.Z` tag,
which runs the full test suite and publishes a GitHub Release automatically.
