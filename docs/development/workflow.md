# Workflow — phases, not a loop

> Last updated: 2026-10-18 — [ADR-0060](../adr/0060-phase-workflow-and-a-light-root-contract.md)

Work is started by a person, not by an autonomous loop: `/isler` lists what an agent can do,
`/faz E35` runs one or more phases to the end. The workflow itself — which model, which
account, which reviewer — belongs to the user's command, not to this repo. This page is what
the repo asks of it. Binding rules: [AGENTS.md](../../AGENTS.md).

## Words

- **Phase** = an epic in [TASKS.md](../TASKS.md): `## Epic 35 — …` is phase `E35`. A task id
  (`OPH-401`) is one task. Order inside an epic is dependency order.
- **Parked** = ⏸️ in the task heading: it waits on the owner (an account, a console, a store
  review) and is never picked; STATE names its step under "Kullanıcıdan bekleyen".
- **Critical** = the task names a path in a [critical path](../../AGENTS.md#critical-paths), or
  says `Kritik yol: <area>.` — `next` marks it ⚠ and prints the area.

## Entry points

| Command | What it does |
| --- | --- |
| `/isler` | `npm run next -- --list` + `npm run next -- --summary`: ready tasks by epic, ⚠ critical, parked apart. Changes nothing. |
| `/faz E35 [E36…]` | every open, unparked task of those epics, in order; phase-end test + review + bounded fixes; then the git flow |
| `npm run next -- --list --phase E35 --json` | the phase's task list with full texts, its intro and each task's critical areas |
| `npm run next -- --only OPH-401 --json` | one task's slice |

Exit codes: 0 ready · 3 only parked tasks · 4 nothing open. With `--list` and nothing ready, the
user is told what waits on the owner; nothing is invented to fill the phase.

## One phase

1. **Per task, a fresh agent, one at a time** (one writer per checkout). It gets the task's
   slice, the docs and ADRs it names, the rule file when ⚠, and a line or two per earlier task
   (SHA + what changed) — never all of TASKS/STATE. It greps
   [LESSONS.md](../LESSONS.md) for its area, writes the test first, implements, runs
   **K1** `npm run verify:task -- <the test files it wrote or touched>` (+ the area's extra
   gate when critical), updates the docs by [doc-protocol.md](doc-protocol.md), and makes a
   **local** commit `type(scope): … (OPH-NNN)` with suite counts and injection proofs in the
   body.
2. **Per task, a short check** of that diff only: does it break the task's acceptance or an
   invariant? Not style. A violation is fixed before the next task.
3. **Phase end, once:** `npm run verify:batch` (complete — no `--only`/`--skip`) and
   `npm run verify:smoke`; mobile/desktop behaviour on a device or emulator here when this
   machine can build it — otherwise `NOT RUN` + reason + a [DEVICE-CHECKS.md](../DEVICE-CHECKS.md)
   row. Then a review in a fresh context (another model family when possible) of the phase
   diff against the acceptance criteria and the invariants.
4. **Fix loop:** only in-scope **blocker/major** findings continue it; at most two rounds, and
   it stops early when a round finds no new blocker/major. Minor, pre-existing and new-scope
   findings become tasks in TASKS.md with their reason — not fixes in this phase.
5. **Finish:** K2 once more if anything changed, STATE's Snapshot cells overwritten,
   `npm run check:docs`, then the git flow (branch → PR → merge). CI is not waited on inside a
   phase; at the merge it is read once ([verification.md](verification.md#k3--ci)).

## A lone task

"Do the next task" / _"sıradaki işi yap"_: `npm run next`, then step 1 for that task, then
step 3's checks for it (K2 + smoke) before the PR. Exit 3 → say what waits on the owner and
stop; exit 4 → nothing is open.

## Never in a phase

- Versions, tags, releases, deploys, `gh workflow run`, anything that writes to production or
  to an external account — the owner's (STATE → "Kullanıcıdan bekleyen"). Reading with `curl`
  is fine.
- Growing the scope: a finding is a task in TASKS.md, fixed now only if it breaks this phase.
- Two phase workflows in one checkout. The extension at `ee/` is its own repo with its own
  backlog; a twin task (`⚠️ Çift kapanış ↔`) closes in both repos together.
- Long-lived servers or emulators started outside the machine's resource manager; stop them
  when the phase ends.
