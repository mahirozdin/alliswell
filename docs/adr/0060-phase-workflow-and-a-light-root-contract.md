# ADR-0060 — The phase workflow and a light root contract (blueprint-system v3)

- **Status:** Accepted
- **Date:** 2026-10-18
- **Related task:** — (process; the owner's `/blueprint-system upgrade` of 2026-10-18)
- **Partly supersedes:** [ADR-0042](0042-layered-verification-and-the-loop-contract.md) — its
  loop contract (LOOP.md, `next --batch`, the completion promise). Its four layers, its
  critical-path rule, its task picker and its departures from the recipe stand.

## Context

ADR-0042 made the checks layered and the next task machine-picked, and ran many tasks through
an autonomous loop (ralph) that handed an agent the same prompt every turn. Two things were
left:

1. **The root contract was paid for by everything.** AGENTS.md had grown to 236 lines and
   16.2 KB. It is loaded into every session, every workflow agent and every context after a
   compaction — an `@import` does not make that cheaper — and Codex truncates its AGENTS.md
   chain at 32 KiB without a warning. Most of it (code conventions, the test matrix, the sync
   invariants, the per-area DoD lines) mattered to one task in ten.
2. **A loop is the wrong shape for review.** A turn had no place for a review in a fresh
   context or for a bounded fix round; "never more than two subagents" and "never an emulator
   in a turn" kept the loop cheap by leaving those checks to nobody. Measured elsewhere on the
   same recipe: two-thirds of a phase's cost was long-lived implementation agents, review was
   4%, and unbounded fix rounds chased minor findings (5 → 6 → 3) after the majors had closed.

## Decision

- **Execution is a phase workflow started by a person.** `/isler` lists what an agent can do
  (`npm run next -- --list`: ready tasks by epic, ⚠ on critical paths, parked ones apart);
  `/faz E35 …` runs the epics: a fresh agent per task (K1 + local commit), a short per-task
  check of that diff, then once per phase `verify:batch` + `verify:smoke`, a review in a fresh
  context against the acceptance criteria and the invariants, and at most two fix rounds driven
  only by in-scope blocker/major findings. A **phase is an epic**; TASKS.md, its OPH ids, ⏸️ and
  the STATE pointer are unchanged. LOOP.md, `--batch` and the loop's iteration count are gone.
  The workflow's models and accounts belong to the user's command, not to this repo.
- **The root contract is small and gated.** AGENTS.md ≤ 120 lines / 10 KB: the product
  sentence, the reading order, the invariants (I-01…I-12 are the old rules 1–12, I-13/I-14
  lift the push-privacy and extension rules that were in §3/§8), the critical paths table,
  commands, the DoD, source priority and what no gate catches. CLAUDE.md is `@AGENTS.md` plus
  two lines. Detail moved, unchanged in substance: conventions → `docs/development/conventions.md`;
  layers, test matrix, CI → `verification.md`; doc updates → `doc-protocol.md`; commands →
  `commands.md`; the phase contract → `workflow.md`; each critical path's gate, invariants and
  traps → `.claude/rules/<area>.md` (≤ 60 lines, loaded by Claude when a matching path is
  touched; the table points other agents at it).
- **The rule files' `paths:` are the one list of critical globs.** `next` reads them to mark a
  task ⚠ when its text names such a path (or says `Kritik yol: <area>.`).
- **`verify:smoke`** — the API is started for real against a throw-away MySQL + Redis and the
  core flow is driven over HTTP (register → project → task → sync push/pull → REST read), plus
  the web bundle in headless Chromium when one is built.
- **CI stays on GitHub-hosted runners in this repo** (owner, 2026-10-18). The user's global
  rule moves CI to self-hosted runners to save Actions minutes; this repository is public, so
  its minutes are free, and a self-hosted runner on a public repo would run fork code. `ci.yml`,
  `release.yml` (with its Windows desktop build, ADR-0051) and `diagnose.yml` stay as they are;
  the deploy keeps running on the server's runner (ADR-0043). CI is not waited on inside a
  phase; at the merge it is read once, and red blocks the merge.

## Alternatives considered

- **Keep the loop.** Cheap per turn, but no review and no device check anywhere, and the
  stop condition only fits "do tasks", not "review and fix".
- **Keep everything in the root.** Simplest to find, paid by every agent; past 32 KiB
  Codex silently loses the bottom of it.
- **Review after every task.** The measured cost is in fix rounds, not reviews; a per-task
  diff check catches a broken invariant early and the full review runs once per phase.
- **Rewrite TASKS.md into the recipe's `TODO.md`/`P<n>.<nn>` and add a RUNLOG.md.** Rejected
  again for ADR-0042's reasons: hundreds of commits, the CHANGELOG and the extension's twin-task gate
  name OPH ids, and the owner's lean-docs decision puts evidence in commit messages.
- **Copy the recipe's Python `doc_budget.py`/`next_task.py`/`ci_guard.py`.** The budgets went
  into the existing JS module both `next` and `check:docs` read, so there is one reader; there
  is no TODO/RUNLOG to archive or rotate; `ci_guard` would contradict the CI decision above.

## Consequences

- Every agent loads ~7 KB of contract instead of 16 KB; area detail arrives with the area.
- Old references to "AGENTS §N" in code comments and earlier ADRs resolve through the mapping
  line in AGENTS.md's reading order (§1.N → I-0N, §4 conventions, §5 verification, §6 sync).
- A new critical path is a new rule file — its globs, gate and traps in one place.
- Adding a rule to AGENTS.md now costs a line someone has to remove; a rule a gate can hold
  becomes the gate.

## Enforcement

- `check:docs`: AGENTS.md ≤ 120 lines / 10 KB, CLAUDE.md ≤ 20 lines / 2 KB, the AGENTS +
  CLAUDE + imports chain ≤ 24 KB, each `.claude/rules/*.md` ≤ 60 lines (numbers in
  `scripts/tasks/tasks.mjs`); every `npm run <script>` named in AGENTS.md, CLAUDE.md,
  `docs/development/` or a rule file exists in package.json; their relative links resolve.
  Each was injected once on 2026-10-18 and went red with its own message.
- `npm run next -- --check-budget` runs the same budgets.
- `apps/api/test/unit/tasks-next.test.js` pins `--list`, the ⚠ marking from the rule files'
  globs, and the root budgets.
- `npm run verify:smoke` exits non-zero on a failed step.
