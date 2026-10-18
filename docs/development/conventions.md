# Code conventions

> Last updated: 2026-10-18 — moved from AGENTS.md §4 ([ADR-0060](../adr/0060-phase-workflow-and-a-light-root-contract.md)).
> Old references to "AGENTS §4" point here.

## Backend (`apps/api`)

- ESM imports with `.js` extensions; Node built-ins via the `node:` prefix. JavaScript only (I-01).
- Prettier (single quotes, width 100) + ESLint — `npm run format` before committing.
- Fastify plugins in `src/plugins/`, routes in `src/routes/` (one file per resource, registered
  with a prefix), shared helpers in `src/lib/`, DB helpers in `src/db/`.
- Every route declares an Ajv schema (`body`, `querystring`, `params`, `response`).
- Errors: `@fastify/sensible` (`app.httpErrors.badRequest(...)`) + stable machine-readable
  `code` fields (e.g. `AUTH_INVALID_CREDENTIALS`). Never leak internals in error messages.
- `src/config.js` is the only module that reads environment variables.
- IDs are **ULIDs** (`CHAR(26)`) from `src/lib/ids.js`. Timestamps are UTC `DATETIME(3)`; the
  API serializes ISO-8601 strings. Time-sensitive functions take a `now`.
- Soft delete via `deleted_at`; queries filter `whereNull('deleted_at')` unless they mean to
  include deleted rows.
- A write to a synced entity (project/task/tag/note/…) bumps its `revision` and inserts a
  `sync_revisions` row **in the same transaction** — `recordSyncWrite`/`withRevision` from
  `src/db/sync.js` (OPH-050) — and stamps the returned revision onto the row.
- No N+1 queries: batch with `whereIn`, a join, or one aggregate query.

## App (`apps/app`)

- Riverpod for state, go_router for navigation, feature-first folders under `lib/src/features/`.
- **Local-first (Epic 06):** screens never call the REST APIs directly — reads watch the drift
  replica through the feature stores (`features/*/data/*_store.dart`), writes go through the
  same stores (optimistic row + outbox enqueue in one transaction, then poke the engine). The
  standing exceptions are in LESSONS `sync`. Widget tests that pump the app need
  `test/support/sync_overrides.dart`.
- Keep widgets small; reusable UI goes to `lib/src/widgets/`.
- **No hardcoded user-facing strings** (Epic 11, ADR-0009): `'some.key'.tr()`, with the key in
  `apps/app/assets/i18n/{en,tr}.json` (English is the base). `npm run check:i18n` enforces it;
  escape hatch `// i18n-ignore`.
- `dart format <the files you touched>` — never the whole tree: the local SDK formats
  collections differently from CI's, and `verify:batch` checks your files with CI's formatter
  (LESSONS `ci-release`). Zero `flutter analyze` warnings.
- **UI = [DESIGN.md](../DESIGN.md)** (I-11). Theme/tokens in `lib/src/theme/` (`buildAwTheme`,
  `AwTokens`, `AwSpace`/`AwRadius`/`AwMotion`) — no raw hex or `Colors.*` in widgets; glass
  chrome + aurora in `lib/src/widgets/glass.dart`, chrome only, never under body text; shared
  empty/error states in `lib/src/widgets/status_views.dart` (use them). Lists are card rows with
  `awListPadding(context)`; favorite/pin stars use `AwTokens.warning`; priority colors only via
  `taskPriorityColor*`. Contrast ≥ 4.5:1 text, ≥ 3:1 icons/borders in both themes; tap targets
  ≥ 44 px; every UI change checked in light and dark.

## Commits and risky work

- Conventional Commits: `feat(api): …`, `fix(app): …`, `docs: …`, `chore: …`, `ci: …`,
  `refactor(api): …`, `test(api): …`; scope `api`, `app`, or none for repo-wide. Task id in the
  title, e.g. `feat(api): add register endpoint (OPH-020)`. No co-author line; the message comes
  from a file (`-F`), without backticks.
- Risky things in writing first: a large refactor or a data migration gets a short plan in its
  task or an ADR before the code.
- Prefer boring, proven solutions — this is infrastructure people self-host.
