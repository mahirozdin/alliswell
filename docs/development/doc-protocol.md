# Doc protocol — what a change updates

> Last updated: 2026-10-18 — [ADR-0060](../adr/0060-phase-workflow-and-a-light-root-contract.md)

The working docs stay small: STATE is the pointer, TASKS is open work only, LESSONS holds traps
by area, git and the CHANGELOG are the record (owner decision 2026-09-26). `npm run check:docs`
enforces what it can; the rest is this table.

## Every task

- **TASKS.md:** delete the finished task's block — never tick and keep it. A gap found while
  measuring becomes a new task with an id, or `[~]` + one sentence.
- **STATE.md:** overwrite the Snapshot cells in place ("➡️ Next task" = what `npm run next`
  prints, or **BACKLOG BOŞ**). No "Önceki metin" chains, no session blocks. An owner decision →
  "Sahip kararları"; an open owner step → "Kullanıcıdan bekleyen" (every ⏸️ task is named there).
- **LESSONS.md:** a trap that could silently recur → one or two lines under its area.
- **CHANGELOG.md:** one short entry under `[Unreleased]` only when a user will see the change.
- **Commit:** Conventional Commit with the task id; verification evidence in the body.

## By change type

| Change | Also update |
| --- | --- |
| Structure (module, service, data flow) | [ARCHITECTURE.md](../ARCHITECTURE.md) |
| Architectural decision (new dependency category, schema redesign, protocol, security choice) | a new ADR in `docs/adr/` + its row in [adr/README.md](../adr/README.md) (I-06) |
| User-facing capability (entity, field, operation) | MCP tools + [MCP.md](../MCP.md) and the key-authenticated REST surface + [API.md](../API.md), or a one-line reason in the task (I-12); `npm run api:docs` regenerates the reference |
| New/changed endpoint | its Ajv schemas; `npm run openapi` when the public surface moved |
| UI | [DESIGN.md](../DESIGN.md) when the design language moves (I-11); palette edits → `python3 scripts/design/contrast.py` |
| User-facing string | `apps/app/assets/i18n/{en,tr}.json` (`npm run check:i18n`) |
| Sync push fields | `npm run gen:sync-fields` + the generated Dart file ([sync rule](../../.claude/rules/sync.md)) |
| Notification gateway / token path / channel | `platform_matrix.dart` + `npm run check:notify-matrix -- --write` → NOTIFICATIONS.md §3 |
| Calendar claims (Apple is one-way) | README, COMPARISON, SUPPORT(.tr), STORE-LISTING, landing, `llms.txt` together — `check:docs` holds the claim |
| Something to look at on a device | a [DEVICE-CHECKS.md](../DEVICE-CHECKS.md) row |
| Self-hosting / env var | `.env.example`, [SELF-HOSTING.md](../SELF-HOSTING.md) |
| An npm script renamed or added | [commands.md](commands.md); `check:docs` fails on a contract that names a missing script |
| Agent contract | AGENTS.md stays ≤ 120 lines / 10 KB, a rule file ≤ 60 lines — detail goes here, to [conventions.md](conventions.md) or a `.claude/rules/` file |

## Never

- A log in STATE/TASKS, or a closed task left in TASKS.
- Editing the frozen [BLUEPRINT.md](../BLUEPRINT.md) — a deviation is an ADR.
- The extension's design in a public doc or commit — the core only says "the extension".
- Real user data in any doc or image: screenshots come from golden tests and the demo seed.
