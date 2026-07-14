# STATE — Live development state

> This file is the pointer for the "do the next task" (TR: _"sıradaki işi yap"_) workflow.
> Always read it first; always update it before finishing a session. Backlog: [TASKS.md](TASKS.md).

**Last updated:** 2026-07-15 (feedback round 1 applied on top of OPH-040…044)

**Repository:** https://github.com/mahirozdin/alliswell (public) — CI green since the first push
([run #1](https://github.com/mahirozdin/alliswell/actions)): migrations apply/rollback/re-apply
against real MySQL 8.4 and all unit+integration tests pass.

## Snapshot

| | |
| --- | --- |
| Current phase | Phase 1 — Core domain |
| Current epic | **Epic 05 — Notes** |
| ➡️ **Next task** | **OPH-045 — Markdown export (server-side)** |
| Last completed | OPH-040…044; Epic 04, Epic 03, Epic 02, Epic 01, OPH-090…093 |

## Recently completed

- **Feedback round 1 (2026-07-14/15, kullanıcı testi sonrası):** BLUEPRINT §12 revize.
  (1) Home + Calendar sekmeleri Today/Upcoming'in yerini aldı — kronolojik gruplar
  (`features/home/task_grouping.dart`, saf/test edilebilir) + özel ay takvimi
  (`month_calendar.dart`), gün seçimi vurgula/söndür, mobilde kalıcı tercihe bağlı katlanır
  takvim (`core/persisted_prefs.dart`). (2) Web oturumları localStorage ile kalıcı
  (`PrefsSecretStore`). (3) Projeler: README notu Overview (`projects.readme_note_id`
  migration'ı + `readmeNoteId` alanı, `PROJECT_INVALID_README_NOTE`), hex'siz palet + renk
  ızgarası dialogu, Tasks/Notes sekmelerinde hızlı ekleme; description alanı UI'dan kalktı
  (kolon duruyor). (4) Notlar: liste/A4-kart görünümleri (kalıcı), meta satırı
  (edited/created/proje), yıldızla tek dokunuş pin, arşiv menüsü + Archive çipi
  (`?archived=true`), başlık dokümanın sabit H1 bloğu ve markdown `# başlık` ile başlıyor.
- **Epic 05 — notes (OPH-040…044; 045 export kaldı):** Notes API — delta JSON canonical +
  markdown + server-derived plain_text (FULLTEXT `?q=`), pinned/archived, polymorphic
  task/project links (`NOTE_LINK_EXISTS`), `POST /tasks/:id/notes` (proje miras alır,
  otomatik link), `GET /projects/:id/notes` (attached ∪ linked). App — Notes sekmesi
  (arama + All/Pinned çipleri), proje detayında Notes tab'ı, flutter_quill 11 editör
  (debounce'lu delta autosave, ilk kayıtta POST; client-side delta→markdown dönüştürücü
  `features/notes/data/delta_markdown.dart` + preview sheet). Quill,
  `FlutterQuillLocalizations.localizationsDelegates`'i app.dart'ta gerektiriyor.
- **Epic 04 — complete (OPH-030…037).** On top of the API core below: OPH-035 snooze
  (`POST /tasks/:id/snooze`, presets incl. tomorrow_morning at 09:00 task-tz — DST-safe
  `src/lib/time.js`; task + active reminder snooze together; unrelated patches preserve a
  snooze). App side: Projects list/edit-sheet/detail-tabs (OPH-036, workspace via `GET /me`),
  Inbox/Today/Upcoming live lists + quick-add + task detail with status/priority/urgent/
  dates/tags/checklist (OPH-037). Flutter: feature-first `features/{workspaces,tags,projects,
  tasks}`; widget tests run against a stateful in-memory API (`test/features/projects/
  fake_api.dart`). Route map: `/projects/:id` in-branch, `/tasks/:id` pushed top-level.
- **Epic 04 — core domain API (OPH-030…034):** projects/tags/tasks CRUD under `/api/v1`,
  all workspace-authorized and soft-deleting. **Sync foundation:** `recordSyncWrite()`
  (src/db/sync.js) bumps `workspaces.revision` under row lock + appends `sync_revisions`
  in the same trx as every entity write — entity rows carry their revision. Tasks: filters
  (status/project/tag/due/urgent/parent) + ULID-cursor pagination, subtasks w/ cycle guard +
  subtree delete, checklist sub-resource, `PUT /tasks/:id/tags` diff semantics,
  complete/reopen (idempotent; archived immutable, `TASK_ARCHIVED`), reminder rows
  reconciled with task writes in-transaction (`src/db/reminders.js`). Tags: per-workspace
  slugs, tombstoned on delete so names can be recreated. Error codes in route files.
- **Local infra restored:** colima (brew) provides the Docker daemon — Docker Desktop not
  needed; `docker compose up -d mysql redis` + `npm run db:migrate` + `npm run
  test:integration` all work locally (`.env` maps host port **3307** because a brew MySQL
  9.7 occupies 3306; containers stay MySQL 8.4 internally).
- **Epic 03 — Auth (complete):**
  - **API:** register/login/refresh/logout + `GET /me` under `/api/v1`. argon2id (timing-safe
    dummy verify on unknown email); 15-min JWTs (iss `alliswell-api`, aud `alliswell-app`;
    `@fastify/jwt` v10 — numeric `expiresIn` is SECONDS); opaque 30-day refresh tokens stored
    as HMAC-SHA256(JWT_REFRESH_SECRET), rotation families with reuse detection (replay revokes
    the family, concurrent rotation settled by atomic claim UPDATE). `app.authenticate`
    (expired → `AUTH_TOKEN_EXPIRED`) + `app.requireWorkspaceMember(request, wsId, {roles})`.
    Auth routes rate-limited via `RATE_LIMIT_AUTH_MAX` (10/min default). Production refuses
    placeholder/short/identical JWT secrets. Error codes listed in apps/api/README.md.
  - **App:** feature-first `lib/src/features/auth/` — dio + AuthInterceptor (attach token,
    single-flight refresh-on-401, one retry), AuthRepository (session source of truth,
    change stream), Riverpod `authControllerProvider`, login/register screens, router guard
    (`/splash` → `/login`), Settings sign-out. Sessions persist via flutter_secure_storage
    (web: memory only, refresh-cookie flow planned) and restore on start. Unit tests stub
    knex (`apps/api/test/helpers/fakedb.js`) and dio (fake HttpClientAdapter).
- **Epic 01 — Foundation:** monorepo (npm workspaces), full docs set, Docker Compose
  (MySQL 8.4 + Redis 8 + optional api/adminer), Fastify API skeleton with health endpoints,
  Flutter 6-platform shell (Riverpod + go_router, adaptive navigation), GitHub Actions CI.
- **Epic 02 — Database:** knex migration baseline — 17 tables covering users/workspaces/members,
  refresh_tokens, projects/tags/tasks (+task_tags, checklist_items), notes (+note_tags,
  note_links), sync_revisions + client_mutations, calendar_accounts/calendar_event_links/reminders.
- **Epic 09 (partial):** CONTRIBUTING, SECURITY, issue/PR templates.

## Blocked / notes

- ~~Local Docker daemon missing~~ — fixed 2026-07-14: colima + docker-compose installed via
  brew (`colima start` boots the VM after a reboot); broken Docker Desktop cli-plugin
  symlinks and the dead `credsStore` were cleaned from `~/.docker`. Local MySQL 9.7 (brew
  service) still owns port 3306 → repo `.env` uses `MYSQL_PORT=3307`/`DATABASE_PORT=3307`.
- ~~`JWT_ACCESS_SECRET` / `JWT_REFRESH_SECRET` placeholders~~ — done in OPH-020: config falls
  back to labeled insecure dev secrets, production refuses placeholders/short/identical values.
- Apple EventKit work (OPH-077+) requires macOS/Xcode signing setup on the dev machine.
- Web builds keep tokens in memory only (signed out after a reload) — the httpOnly
  refresh-cookie flow is the planned hardening; see OPH-025 notes in TASKS.md.

## Environment assumptions

- Node ≥ 22 (dev machine: v25), Flutter 3.44 / Dart 3.12, Docker Desktop with compose v2.
- Local infra: `docker compose up -d mysql redis` then `npm run db:migrate`.

## How to continue (for agents)

1. Read [../AGENTS.md](../AGENTS.md) §2 (protocol) if you haven't.
2. Implement **OPH-045** per its checklist in [TASKS.md](TASKS.md) — the server-side
   delta→markdown converter can mirror the client one
   (apps/app/lib/src/features/notes/data/delta_markdown.dart); add
   `GET /notes/:id/export?format=md` and fixture-delta tests.
3. Verify (`npm run lint && npm test`, integration tests if infra up), document, commit,
   then update this file's Snapshot + Recently completed.
