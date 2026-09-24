# ADR-0041 — An extension that wrote data must be present to serve it

- **Status:** Accepted
- **Date:** 2026-09-24
- **Related task:** OPH-343 (Epic 33)
- **Revises:** the loader's failure policy in `apps/api/src/lib/ee.js` (EE-002)

## Context

The API loads an optional extension at boot (`loadEeOverlay`). Until now its
failure policy was availability first: an absent extension was the plain build,
and one that was present but failed to load was logged loudly and *also* served
as the plain build — "must not take the instance down with it".

That sentence is right for the process and wrong for the data. An extension does
more than add routes: it registers permission resolvers that `requirePermission`
consults, sync mutation guards, write observers. When it is gone, those rules go
with it, and core's answer without them is membership alone
(`plugins/auth.js`: no resolver → the member row). Every member of a workspace the
extension restricted — "may view tasks, may not delete them" — would be served
with the plain build's wider rights, by a server whose readiness still said `ok`.

An outside review (2026-09-24) named the concrete path: a deploy that loses the
extension's files, a database that still holds what the extension wrote, and a
member deleting what they were never allowed to delete.

## Decision

**The question is not whether the extension is here, but whether the data it
governs is.** When the extension is enabled:

| Extension                     | `EE_REQUIRED` | Answer                                   |
| ----------------------------- | ------------- | ---------------------------------------- |
| loaded                        | any           | open                                     |
| present, failed to load       | any           | **locked** (`EXTENSION_LOAD_FAILED`)     |
| absent                        | `true`        | **locked** (`EXTENSION_REQUIRED`)        |
| absent                        | `false`       | open — the operator accepted plain rules |
| absent                        | unset         | the migration ledger decides             |

The ledger rule: if `knex_migrations` records a migration this build has no file
for, the extension wrote data here → **locked** (`EXTENSION_MISSING`). A clean
ledger is the plain build → open. A ledger that cannot be read yet locks
(`EXTENSION_UNVERIFIED`) and is asked again on the next request; a database that
was never migrated (`ER_NO_SUCH_TABLE`) has written nothing for anyone.

**Locked** means: every request except `/health/*` answers **503
`EXTENSION_UNAVAILABLE`**, and `/health/ready` answers 503 with
`checks.extension = { status: 'down', error: <code> }`. A loaded extension reports
`{ status: 'up' }`. The deploy workflow writes `EE_REQUIRED=true` whenever it ships
an extension (an explicit value in the deploy's env lines still wins).

A present-but-failed extension locks **in every `EE_REQUIRED` state**, `false`
included: an extension that fails halfway through registering has already
installed some of its rules and not others, and that is the worst state to serve
from.

## Alternatives considered

- **Keep failing open, alert loudly.** The status was already on `/ee/status` and
  in the log. Nobody reads a log before a member deletes something; readiness
  said `ok`, which is what load balancers and deploy checks read.
- **Refuse to boot.** Equally closed, but a crash loop under a process manager
  says less than a 503 with a reason, and `/health/live` can no longer tell "the
  process is up" from "the process is gone".
- **Deny per workspace** (only the workspaces the extension governed). Core cannot
  know which those are without learning the extension's schema — the one-way
  dependency forbids it. The whole server is the only boundary core can draw.
- **Operator flag only** (`EE_REQUIRED`, no ledger). Correct for deploys that set
  it, silent for the ones that forget — the ledger is the evidence that does not
  depend on anyone remembering.

## Consequences

- **The plain build is unchanged, byte for byte.** Disabled, or absent with a
  clean ledger: no hook is installed and readiness carries only `mysql` and
  `redis` (both tested). The only cost is one ledger query at boot when an
  extension is enabled but absent.
- **Background sweeps are not locked.** They act as the system, not on behalf of
  a member's permissions, so the hole this closes is not theirs; realtime
  (Socket.IO) carries revision hints, and the reads they prompt are locked.
- An operator who removes an extension on purpose sets `EE_REQUIRED=false` and
  owns that decision.
- A stray ledger row from a test or an aborted migration now locks the server
  instead of being ignored — which is the point, and why the integration test
  removes its own row.
