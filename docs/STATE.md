# STATE — Live development state

> This file is the pointer for the "do the next task" (TR: _"sıradaki işi yap"_) workflow.
> Always read it first; always update it before finishing a session. Backlog: [TASKS.md](TASKS.md).

**Last updated:** 2026-07-15 (Epic 05 kapandı; Epic 06 sunucu çekirdeği: OPH-050…053)

**Repository:** https://github.com/mahirozdin/alliswell (public) — CI green since the first push
([run #1](https://github.com/mahirozdin/alliswell/actions)): migrations apply/rollback/re-apply
against real MySQL 8.4 and all unit+integration tests pass.

## Snapshot

| | |
| --- | --- |
| Current phase | Phase 2 — Sync |
| Current epic | **Epic 06 — Sync** |
| ➡️ **Next task** | **OPH-054 — Flutter local DB (drift + outbox şeması)** |
| Last completed | OPH-045 (Epic 05 ✔); OPH-050…053 (sync sunucu çekirdeği); Epic 04…01 |

## Recently completed

- **Epic 05 closed + Epic 06 server core (2026-07-15, OPH-045 + OPH-050…053):**
  - **OPH-045:** `GET /notes/:id/export?format=md` streams `text/markdown` (attachment,
    slugified filename) converted server-side from the canonical delta — `deltaToMarkdown`
    in `src/lib/delta.js` mirrors the Dart converter fixture-for-fixture; stored markdown is
    only the delta-less fallback.
  - **OPH-050:** `withRevision(trx, wsId, type, id, op, changedFields)` joined
    `recordSyncWrite` as the blueprint-named form (same implementation, `src/db/sync.js`);
    all write paths already used it. Integration proof: 12 concurrent writers → gapless
    revisions 1..12.
  - **OPH-051 pull:** revision-ascending batches (default 200/max 500, `limit+1` →
    `hasMore`), coalesced to each entity's latest change; snapshots are CURRENT rows (tasks
    embed tagIds, notes embed content+links); currently-deleted rows always tombstone, even
    when the delete log row lies past the window. Types: project/tag/task/note/
    checklist_item/reminder.
  - **OPH-052 push:** body = `clientId` + `workspaceId` (documented §6.3 deviation) +
    `baseRevision` + ≤100 mutations; per-mutation `applied`/`conflict`/`rejected` (+
    `errorCode`, `discardedFields`, `replayed`). Field-level LWW: only FOREIGN writers
    conflict (own pushes attributed via `client_mutations.result_revision`), newer wall
    clock wins (`localUpdatedAt` vs server `updated_at`), losers drop per field,
    all-dropped → `SYNC_STALE_MUTATION`. Note content: doc-level lock →
    `NOTE_CONTENT_CONFLICT`. Domain rules preserved in-transaction: urgent⇒ack default,
    completed_at, reminder reconcile, archived immutability, tag slugs, subtree delete,
    project-delete role guard. SYNC_* error codes listed in `src/routes/sync.js`.
  - **OPH-053 idempotency:** every outcome recorded in `client_mutations` (applied ones in
    the SAME trx as the entity write); replays return the recorded result
    (`replayed: true`); scoped per clientId; races settle on `uq_client_mutation`.
  - Tests: unit 135/135 (fakedb gained `client_mutations`), integration 23/23 on real
    MySQL. Remaining in Epic 06: OPH-054…057 (Flutter drift replica, outbox, conflict UI,
    Socket.IO fanout).
- **Design round 1 (2026-07-15):** "AllisWell Glass" tasarım sistemi — KALICI görsel dil
  (ADR-0005; tek kaynak `docs/DESIGN.md`; AGENTS.md sert kural 11 → bundan sonraki TÜM UI
  işlerinde tasarım bütünlüğü zorunlu). Liquid-Glass esinli ama UX-önce: cam yalnız
  navigasyon chrome'unda (`widgets/glass.dart`), içerik opak + WCAG-doğrulanmış (metin
  ≥4.5:1, ikon/kenarlık ≥3:1 — bekçi: `scripts/design/contrast.py`, FAILURES: 0). El
  ayarı light/dark ColorScheme + `AwTokens` (`lib/src/theme/`), tüm bileşen temaları
  merkezî; kart-satır listeler, dairesel checkbox, drag-handle'lı/genişlik-sınırlı
  sheet'ler, görünür input kenarlığı + 2px odak halkası, şifre göster/gizle, ikonlu hata
  bantları, kırmızı "Overdue", ortak `AwEmptyState/AwErrorState`. Öncelik/yıldız renkleri
  tema-duyarlı token'lara taşındı (`taskPriorityColor(priority, brightness)` — eski amber
  beyazda ~2:1 idi). Widget testleri scroll-bilinçli finder'lara güncellendi (69/69 yeşil,
  analyze temiz). Web'de light+dark, geniş+mobil görsel doğrulama yapıldı (design@ hesabı).
- **Feedback round 3 (2026-07-15):** KRİTİK — @fastify/cors default'u yüzünden web'den
  PATCH/PUT/DELETE preflight'ta engelleniyordu (görev tarihi kaydetme vb. hiç sunucuya
  ulaşmıyordu); metotlar artık explicit + preflight regresyon testi var. Görev başlığı
  detayda yerinde düzenlenebilir (debounce'lu autosave). Görsel standart: statü→ikon,
  öncelik→renk (`features/tasks/ui/task_visuals.dart`) — satırlarda renkli bayrak + statü
  ikonu, dropdown'larda ikon/renkli etiket, proje seçicilerde renk noktası. Başarısız
  yazımlar artık snackbar'la görünür.
- **Feedback round 2 (2026-07-15):** Home görev girişi geri geldi — listenin üstünde
  seri girişli quick-add (`features/tasks/ui/quick_add_bar.dart`, Enter sonrası odak
  korunur; gün seçiliyken o güne 09:00, değilse tarihsiz) + sağ altta FAB →
  `task_create_sheet.dart` (due/remind tarih+saat, öncelik, proje, urgent; seçili gün
  prefill). Inbox ve proje Tasks sekmesi aynı QuickAddBar'ı kullanıyor.
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
2. Implement **OPH-054** per its checklist in [TASKS.md](TASKS.md): drift schema mirroring
   the server entities + a `pending_mutations` outbox table; repositories read local-first.
   The server contract to mirror is live in `apps/api/src/routes/sync.js` —
   `GET /sync/pull` (coalesced snapshots + tombstones, `hasMore`) and `POST /sync/push`
   (statuses `applied`/`conflict`/`rejected`, `discardedFields`, `replayed`).
3. Verify (`npm run lint && npm test`, integration tests if infra up; `flutter analyze` +
   `flutter test` for app changes), document, commit, then update this file's Snapshot +
   Recently completed.
