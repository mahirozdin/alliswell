# ADR-0042 — Layered verification, a machine-picked next task, and the loop contract

- **Status:** Accepted
- **Date:** 2026-09-26
- **Related task:** — (process; follows the owner's decisions of 2026-09-25 "checks at the end"
  and 2026-09-26 "lean working docs")

## Context

Work here is driven by "do the next task" and, for runs of many tasks, by an autonomous loop
(ralph) that hands an agent the same prompt every turn. Three things made those runs slow
without making them safer:

1. **Every task paid for the whole check set.** AGENTS §2 asked each task to run lint, the unit
   suite, the integration suite and Flutter, and loops added a push and a CI watch after each
   one. The suites run on a shared remote sandbox, so a task's wall-clock was mostly transfer,
   stack start-up and waiting. The owner stopped a loop halfway on 2026-09-25: code the tasks
   one by one with a targeted local test and a local commit, run the heavy checks once at the
   end (STATE → Sahip kararları).
2. **What was next lived in prose.** The pointer in STATE and the order in TASKS were read and
   interpreted by the agent each time; "is anything left for an agent?" had no machine answer,
   so a loop's stop condition was the model's judgement — too early when it got stuck, never
   when it did not.
3. **The files every session reads had become logs** (STATE 484 KB, TASKS 932 KB). The
   2026-09-26 cleanup cut them to the pointer, the owner's
   decisions and the open work, and `check:docs` gained budgets. What remained was to keep the
   loop itself from re-growing them.

## Decision

**Four layers of verification**, each with one entry point and one moment:

| Layer | When | What | Then |
| --- | --- | --- | --- |
| **K1** `npm run verify:task -- <tests>` | end of every task | lint/format of the changed files, the gates whose input changed, the named tests (API ones on the sandbox, Flutter ones here) — or the API unit suite when API code changed and none was named | local commit |
| **K2** `npm run verify:batch` | end of a batch (3–6 tasks, one loop turn), or of a single interactive task | every gate, lint, format, the API unit + migration round trip + integration suites, Flutter analyze + test + the web build, CI's own Dart formatter on the changed files — for what changed since the last push (`--all` for everything) | one push, only when green |
| **K3** CI | after the push, asynchronously | every job, always | read once at the start of the next turn; never waited on |
| **K4** people and devices | when the owner can | emulator/device/screenshot checks | [DEVICE-CHECKS.md](../DEVICE-CHECKS.md); never a task's closing condition |

**Critical paths run their K2 part at K1 time** (AGENTS §3): migrations (the round trip runs
automatically when one changes), the sync protocol and its field contract, auth/sessions/keys,
the push payload's privacy contract, the notification platform matrix and the extension seam.
A mistake there is expensive or irreversible, so the batch's safety net comes too late for it.

**`npm run next` picks the work** (`scripts/tasks/next.mjs`): the first task in TASKS.md
without ⏸️, its epic's intro and its block; `--batch N` for a turn; exit **0** ready ·
**3** only parked tasks (waiting on the owner) · **4** nothing open · **5** over budget. It reads
TASKS through `scripts/tasks/tasks.mjs`, the module `check:docs` reads it through, so the
picker and the gate cannot disagree about what is open. ⏸️ in a task heading is the one
dependency marker: order is dependency, and a task that needs a parked one is parked too.

**[LOOP.md](../../LOOP.md) is the loop contract**: one turn = one batch; state → CI once →
`next --batch` → per task implement + K1 + local commit → K2 + one push → report. The
completion promise is written only when `next` exits 3 or 4 and the last K2 is green and
pushed — the stop condition is a script's exit code, not a judgement.

**The sandbox receives only committable files.** `verify` sends what git tracks or would
track (untracked, not ignored), minus the app's sources and the image trees, and refuses any
path shaped like a secret. The remote tree is rebuilt from that payload every run (a deleted
test or migration cannot linger there); the dependency install moves across while the
lockfiles are unchanged. `sbx push`/`sbx link` are not used: they ignore .gitignore and once
shipped `.env`, `.env.production` and a signing key.

**Deliberate departures from the blueprint-system recipe this follows:** no `RUNLOG.md` — the
owner's lean-docs decision puts evidence in commit messages, and `git log --oneline` already is
one line per task; no `TODO.md`/`P<n>.<nn>` ids — TASKS.md and its OPH/EE ids stay, `next`
reads them; no `CLAUDE.md`/`BOOT.md` — agents load AGENTS.md directly, the interactive start is
AGENTS §2 and the loop's light start is LOOP.md §1.

## Alternatives considered

- **Full verification after every task** (the previous §2). Correct, and the most expensive
  way to be correct: the cost multiplies by the number of tasks, and the owner stopped it.
- **Verification only at the end of a whole loop.** Cheapest, but a red suite after thirty
  commits is an archaeology job; a batch of 3–6 separately committed tasks keeps the search to
  a `git bisect run` over a handful.
- **Waiting for CI per task or per batch.** CI is the asynchronous safety net for the
  combinations a machine here cannot run (MariaDB, service containers only CI starts);
  reading it once at the start of the next turn gives the same signal without
  the wait.
- **Rewriting TASKS.md into the recipe's TODO.md format.** It would rename the ids that 350
  commits, the CHANGELOG and the extension's twin-task gate refer to.

## Consequences

- A task costs its narrow check; the full set runs once per batch and nothing red is pushed.
- "What is next" and "is anything left" are answered by a script, and a loop ends on its own.
- K1 can miss a cross-cutting break; K2 catches it before the push, and the fix is its own
  commit. `git bisect run` is cheap because each task is a commit.
- The verify table must track CI: a gate added to CI is a row in `scripts/verify/verify.mjs`
  too. What K2 cannot run here is printed after every batch run as "CI only" (the MariaDB job,
  the landing assertions written inline in ci.yml).
- The sandbox runs the suites with 120 s test/hook timeouts: the shared host is slower than a
  CI runner (three SSE unit tests and the AI chat integration file time out at the defaults
  there and only there). A hanging test still fails, later.
- Native platform builds run in K2 only when native files changed: they are the only thing
  that compiles Swift/Kotlin, and they take minutes.

## Enforcement

- `check:docs` (CI, and K1 whenever a doc changes): STATE/TASKS/LESSONS byte budgets
  (16/150/48 KB) and a 2 KB line budget for STATE and TASKS; a closed task may not stay in
  TASKS; STATE's "Next task" cell names what `npm run next` prints, or **BACKLOG BOŞ** when
  nothing is ready; every ⏸️ task is named in STATE. Each rule was injected once on
  2026-09-26 and went red with its own message.
- `npm run next` exit codes are LOOP.md's completion condition; `npm run next -- --check-budget`
  is the same budget check for a loop that wants it without the rest of `check:docs`.
- `apps/api/test/unit/tasks-next.test.js` and `verify-payload.test.js` (CI's API job) pin the
  task parser, the exit codes, the secret-shape filter and the payload selection.
- `verify:batch` exits non-zero on any red or not-run step and says "not a push verdict" for a
  partial (`--only`/`--skip`) run; LOOP.md allows the push only after a green, complete one.
