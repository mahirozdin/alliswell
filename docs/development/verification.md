# Verification — four layers

> Last updated: 2026-10-18 — [ADR-0060](../adr/0060-phase-workflow-and-a-light-root-contract.md)
> (layers: [ADR-0042](../adr/0042-layered-verification-and-the-loop-contract.md))

A task pays for its own proof; a phase pays for the full set, once.

| Layer | When | Command | Then |
| --- | --- | --- | --- |
| **K1** | every task | `npm run verify:task -- <tests>` | local commit |
| **K2** | end of a phase, or of a lone task | `npm run verify:batch` (`-- --list` shows the plan) + `npm run verify:smoke` | push / PR, only when green |
| **K3** | at the merge | CI on GitHub Actions | read once; a release closes only on green |
| **K4** | when the owner can | device, emulator, screenshots | [DEVICE-CHECKS.md](../DEVICE-CHECKS.md) — never a closing condition |

## K1 — the task's narrow check

`verify:task` lints and formats the changed files, runs every gate whose input changed, and
runs the named tests (API suites on the sandbox `sbx`, Flutter here). Without a sandbox it runs
the suites against `docker compose up -d mysql redis minio radicale`. Name the test files you
wrote or touched; with none named and API code changed, it runs the API unit suite.

**Critical paths run their K2 part at K1 time** — the area's rule file in `.claude/rules/`
names the extra gate (migration round trip, sync/auth/seam suites, push payload and notify
matrix gates). See [AGENTS.md → Critical paths](../../AGENTS.md#critical-paths).

## K2 — the full set, once per phase

`verify:batch` = every gate, lint, format, the API unit + migration round trip + integration
suites, Flutter analyze + test + the web build, and CI's own Dart formatter on the changed
files — for what changed since the last push (`-- --all` for everything). It exits non-zero on
any red or not-run step and says "not a push verdict" for a partial run. What only CI covers
is printed at the end. `scripts/verify/verify.mjs` is the table: a gate added to CI is a row
there too.

### `verify:smoke` — the app actually runs

`npm run verify:smoke` ([scripts/verify/smoke.mjs](../../scripts/verify/smoke.mjs)) starts a
throw-away MySQL + Redis (its own compose project on free ports), migrates, starts the API as
a process and drives the core flow over HTTP: health → register → create a project and a task
→ sync push → sync pull sees it → REST read → sign out. When a built web bundle exists
(`apps/app/build/web`, or `-- --web` to build it) it also serves it and loads it in headless
Chromium until Flutter has rendered. It tears everything down and prints `PASS`, `FAIL` or
`NOT RUN` + reason per step. No paid or external calls.

Mobile and desktop builds are not in it: they run on a device or emulator here before the
merge when this machine can build them; otherwise `NOT RUN` + reason and a DEVICE-CHECKS row.

## K3 — CI

`.github/workflows/ci.yml` runs every job with real MySQL/Redis service containers (and a
MariaDB job), migrations first. **CI stays on GitHub-hosted runners in this repo** — it is
public, so Actions minutes are free; the owner decided on 2026-10-18 to keep `ci.yml`,
`release.yml` (incl. the Windows desktop build) and `diagnose.yml` as they are (ADR-0060). The
deploy runs on the server's runner (ADR-0043).

CI is not waited on inside a phase. At the merge it is waited on once, in the background;
red → no merge, the fix is a commit on the same PR. An epic or a release closes only on green.

## K4 — people and devices

What only a person or a real device can judge goes to [DEVICE-CHECKS.md](../DEVICE-CHECKS.md);
it never holds a task open (owner decision 2026-09-23).

## Test matrix

| Layer | Tool | Location | Needs infra? |
| --- | --- | --- | --- |
| API unit | Vitest + `app.inject()` | `apps/api/test/unit/` | No (stub db/redis via `buildApp({ db, redis })`) |
| API integration | Vitest | `apps/api/test/integration/` | Yes (MySQL+Redis; `npm run test:integration`) |
| App widget/unit | flutter_test | `apps/app/test/` | No |

## Evidence

A box is not ticked and a task is not deleted without its check having run. A check that could
not run is written `NOT RUN` + reason (commit body, PR, report) — never left out. Suite counts
and injection proofs go in the commit message, not in the docs.
