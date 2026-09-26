# LOOP.md — the loop contract: one turn, one batch

A ralph loop hands the agent the same prompt every turn; the prompt points here, and this file
is the whole recipe for a turn. The binding rules are [AGENTS.md](AGENTS.md); why the checks are
layered is [ADR-0042](docs/adr/0042-layered-verification-and-the-loop-contract.md). An extension
checked out at `ee/` has its own LOOP.md — one loop per repo at a time, never two.

## A turn

1. **State.** `pwd` is the repo root; `git status --short` is clean. If not, understand it
   first: the previous turn's half-finished task (finish it) or someone else's change (leave it,
   stop, report).
2. **CI, once.** `gh run list -L 3 --json status,conclusion,headSha,name,url`. A failure is this
   turn's first task — read it step by step (`gh run view <id> --json jobs`; `skipped` means
   "did not run", not "passed"). Still running → don't wait; it is read again next turn.
3. **Pick the batch.** `npm run next -- --batch 4` (2 when the batch touches a critical path,
   AGENTS §3). Exit 3 (only tasks parked on the owner) or 4 (nothing open) → **Finish**.
4. **Each task, in order:** read what `next` printed and the docs it names; grep
   [docs/LESSONS.md](docs/LESSONS.md) for the area → implement, inside the task's scope →
   **K1** `npm run verify:task -- <the test files you wrote or touched>` until green → docs
   (task deleted from TASKS, STATE cells overwritten, a CHANGELOG line if a user will see it) →
   **local** commit `type(scope): … (OPH-NNN)`, suite counts and injection proofs in the body.
   A critical path gets its K2 part now (`verify:task` runs the migration round trip by itself;
   for sync, auth and the seam name their suites as targets).
5. **Batch end — K2.** `npm run verify:batch` (it takes minutes: start it in the background and
   wait for the notification, never poll). Red → find the commit (`git log --oneline @{u}..`,
   `git bisect run` when unclear), fix it in its own commit, run K2 again. Green → **one**
   `git push`. Anything worth looking at on a device → [docs/DEVICE-CHECKS.md](docs/DEVICE-CHECKS.md).
6. **Report** in three lines: what was done · K2's verdict and duration · what is next.

## Never in a turn

- Waiting on CI — `gh run watch`, sleep or until loops. CI is read at the start of the next turn.
- Emulators, simulators, devices, screenshot comparisons — they go to DEVICE-CHECKS.md (K4).
- Re-running a check on code that has not changed; the full set after every task.
- A swarm of subagents — at most two read-only explorers.
- Growing the scope. A finding becomes a task in TASKS.md, with its reason; it is fixed in this
  batch only if it breaks this batch.
- Versions, tags, deploys, `gh workflow run`, anything that writes to production or to an
  external account — the owner's (STATE → Kullanıcıdan bekleyen). Reading with `curl` is fine.
- Ending the turn in a subdirectory: the next turn's first commands would run in the wrong repo.

## Finish — the completion promise

Only when `npm run next` exits 3 or 4 **and** the last K2 was green and complete (no
`--only`/`--skip`), the push is done and STATE is current: first a short summary — the owner
steps still open, the device checks queued — then, as the very last line and nowhere earlier in
that message, the promise tag with `KOD_TAMAM` inside. The loop stops on the first tag it finds
in the last text block, so a tag quoted earlier ends it with the wrong text.

## Starting a loop

```
/ralph-loop:ralph-loop "LOOP.md sözleşmesine göre bir tur yap. Bir tur bir öbek." --max-iterations <M> --completion-promise "KOD_TAMAM"
```

- `M` is printed by `npm run next -- --summary --batch 4` (`ceil(ready / 4) + 2`: one turn per
  batch plus two for a red K2 and a red CI). Always pass it — the plugin's default is no limit.
- The plugin pastes the arguments into a shell line. Inside the double quotes a `"`, a `$` or a
  backtick ends or expands the prompt; without the quotes `;`, `&`, `|` and parentheses split it,
  and the loop starts on half a prompt with no stop condition. So the prompt carries none of
  them. Both commands here were dry-run through the plugin's argument loop (2026-09-26).
- `/ralph-baslat` computes the same for a scope: here it takes
  `--manuel "OPH-351 → OPH-356" --adet 6`, since this repo has no TODO.md.
- 2026-09-26: nothing is ready (`next` exits 3 — OPH-142, OPH-273 and OPH-274 wait on the owner),
  so there is no loop to start until a task is unparked or an epic is planned.
