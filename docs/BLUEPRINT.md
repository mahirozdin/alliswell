# BLUEPRINT — AllisWell (Open Productivity Hub)

> **Projects, Tasks, Notes, Calendar & Reminders**
>
> Bu doküman ürünün kaynak vizyonudur (source of truth). Uygulama sırasında yapılan bilinçli
> sapmalar `docs/adr/` altında ADR olarak kayıt altına alınır (bkz. özellikle ADR-0003).
> Görev kırılımı için `docs/TASKS.md`, güncel durum için `docs/STATE.md` kullanılır.

## 1. Ürün vizyonu

Bu proje; task, proje, not, doküman, takvim ve hatırlatıcıları tek merkezde birleştiren açık
kaynak, self-host edilebilir, çapraz platform bir üretkenlik uygulamasıdır.

Hedef ürün; Apple Reminders'ın hızlı hatırlatıcı deneyimini, Things 3'ün proje/alan yaklaşımını,
Todoist'in etiket/filtre/priority ve calendar entegrasyonlarını, TickTick'in
takvim/kanban/timeline/not detaylarını ve Notion'ın proje dokümanı yaklaşımını birleştirir.

Ana hedef:

- Kişisel iş yönetimi.
- Kurumsal proje/task/not yönetimi.
- Açık kaynak contributor dostu yapı.
- AI ajanlarıyla sürdürülebilir geliştirme.
- Web, macOS, Windows, Android ve iOS desteği (+ Linux, bkz. ADR-0003).

## 2. Araştırma ve referans ürün analizi

### 2.1 Apple Reminders

Apple Reminders; subtasks, attachments, time/location alerts gibi güçlü temel reminder özellikleri
sunuyor. Ayrıca Smart Lists ile tags, dates, times, locations, flags ve priority gibi kriterlerle
otomatik listeler oluşturabiliyor.

Alınacak özellikler:

- Hızlı task/reminder ekleme.
- Tarih/saat bazlı hatırlatma.
- Subtask/checklist.
- Flag/priority benzeri önem alanı.
- Akıllı liste/filtre mantığı.

Eksik görülen alan:

- Proje dokümantasyonu.
- Notlarla güçlü ilişki.
- Gelişmiş calendar two-way sync kontrolü.
- Açık kaynak/self-host yapı.

### 2.2 Things 3

Things 3; kişisel task yönetiminde proje, area, today/upcoming gibi sade fakat güçlü bir akış
sunuyor. Ürün kendi sitesinde calendar integration, headings ve checklists gibi özellikleri öne
çıkarıyor.

Alınacak özellikler:

- Inbox.
- Today.
- Upcoming.
- Anytime.
- Someday / later.
- Project yapısı.
- Area benzeri yüksek seviye gruplama.
- Temiz ve hızlı UX.

Eksik görülen alan:

- Apple merkezli yapı.
- Android/Web/Windows için doğal destek zayıf.
- Açık kaynak değil.
- Not/doküman sistemi Notion kadar güçlü değil.

### 2.3 Todoist

Todoist; Google/Outlook Calendar entegrasyonu ile Today/Upcoming içinde calendar event gösterme ve
time-blocked task'ları takvime sync etme yeteneği sunuyor. Ayrıca labels, filters ve priority
sistemi güçlü.

Alınacak özellikler:

- Labels.
- Priority.
- Filters/custom views.
- Calendar layout.
- Task-to-calendar sync.
- Hızlı task entry.
- Cross-platform ürün disiplini.

Eksik görülen alan:

- Calendar sync bazı provider'larla sınırlı.
- Notes/project docs birinci sınıf domain değil.
- Self-host/open-source değil.

### 2.4 TickTick

TickTick; calendar görünümü, list/kanban/timeline view mode'ları, task detayında
not/resim/Markdown rich text yaklaşımıyla bu proje için güçlü referanstır.

Alınacak özellikler:

- Calendar-first planlama.
- Kanban görünümü.
- Timeline görünümü.
- Task detayında not.
- Markdown/rich text desteği.
- Çoklu view mode.

Eksik görülen alan:

- Açık kaynak/self-host değil.
- Proje dokümanı Notion kadar ana domain değil.
- Calendar sync kontrolü tam geliştiriciye ait değil.

### 2.5 Notion

Notion'da sayfalar hızlı notlardan paylaşımlı dokümanlara kadar birçok bilgi tipini taşıyan ana
yapı olarak kullanılıyor; API tarafında page content block'lar üzerinden modelleniyor.

Alınacak özellikler:

- Proje doküman sayfaları.
- Blok tabanlı içerik yaklaşımı.
- Notların task/proje ile bağlanması.
- İçeriklerin bilgi tabanı gibi kullanılabilmesi.

Eksik görülen alan:

- Native reminder deneyimi zayıf.
- Hızlı todo/reminder UX'i Apple Reminders kadar direkt değil.
- Calendar/task otomasyonu ana ürün omurgası değil.

### 2.6 Teknik platform referansları

- Flutter, mobile, web ve desktop uygulamaların tek kod tabanından geliştirilmesini destekler;
  resmi dokümantasyon Android/iOS, web, Windows/macOS/Linux hedeflerini listeler.
- Google Calendar API incremental synchronization ve push notifications destekler; bu sayede
  calendar provider değişiklikleri polling maliyeti düşürülerek izlenebilir.
- Google Calendar extended properties, event içine uygulamaya özel metadata yazmaya izin verir;
  task id ile calendar event eşleştirmek için kullanılmalıdır.
- Apple EventKit, Apple platformlarında calendar ve reminders verisi oluşturma, okuma ve düzenleme
  için kullanılan framework'tür.
- CalDAV standardı calendar verisinin sunucu üzerinde canonical state olarak tutulduğu,
  client'ların değişiklik gönderebildiği ve offline sync senaryolarına hazırlıklı olması gereken
  bir model tanımlar.
- Socket.IO Redis adapter, birden fazla Node.js process/server arasında client'lara event iletmeyi
  destekler; realtime sync ölçeklendirme için değerlendirilecektir.
- Flutter local notifications paketi, Flutter uygulamalarında platforma göre özelleştirilebilir
  local notification gösterme ve schedule etmeyi destekler.
- Flutter Quill, Android, iOS, web ve desktop için rich text editor sağlayan WYSIWYG editor olarak
  değerlendirilecektir.

## 3. Ürün prensipleri

1. Local-first hissi.
2. Realtime multi-device sync.
3. Offline çalışabilme.
4. Calendar ile gerçek çift yönlü ilişki.
5. Task, proje ve notların doğal bağlanması.
6. Hızlı giriş.
7. Açık kaynak ve self-host.
8. Kurumsal güvenlik.
9. AI-agent friendly repository.
10. Platform native bildirim deneyimi.
11. Veri taşınabilirliği.
12. Minimum vendor lock-in.

## 4. Ana domain modeli

### 4.1 Workspace

Workspace, tüm verinin üst konteyneridir.

Alanlar: `id`, `owner_id`, `name`, `slug`, `color`, `icon`, `default_timezone`, `created_at`,
`updated_at`, `deleted_at`.

### 4.2 Project

Project, task ve notların bağlandığı ana iş alanıdır.

Özellikler:

- İsim, açıklama, RGB renk, icon.
- Status: `active`, `paused`, `completed`, `archived`.
- Start date, due date, sort order, favorite.
- Workspace relation.

### 4.3 Task / TODO

Task, sistemin en kritik domainidir.

Özellikler:

- Başlık, açıklama.
- Project relation (optional), parent task (optional), checklist items.
- Status: `inbox`, `open`, `scheduled`, `in_progress`, `waiting`, `completed`, `cancelled`,
  `archived`.
- Priority: `none`, `low`, `medium`, `high`, `urgent`.
- Color (optional), tags.
- Due date, start date, scheduled start/end, reminder time (hepsi optional).
- Urgent flag, repeat rule, estimated duration, actual duration.
- Calendar mirror flag, calendar provider mapping.
- Notes relation, attachments (v2).

Task tipleri: simple task, scheduled task, deadline task, urgent reminder, recurring task,
checklist parent, project milestone (v2).

### 4.4 Tags / labels

Etiketler task ve notları bağlamsal olarak sınıflandırır.

Özellikler: `name`, `slug`, RGB color, icon (optional), `workspace_id`, usage count (v2).

Örnek etiketler: Acil, Beklemede, Müşteri, Yazılım, Finans, 5dk, 30dk, Telefon, Mail, Araştırma.

### 4.5 Notes

Note, bağımsız veya task/proje bağlantılı bilgi birimidir.

Özellikler: `title`, `content_delta` (JSON), `content_markdown`, `plain_text`, `project_id`
(optional), `created_from_task_id` (optional), tags, pinned, archived, linked tasks, linked
projects, backlinks (v2).

### 4.6 Project Documents

Project document, Notion benzeri proje sayfasıdır.

Özellikler: `project_id`, `title`, `blocks`, sort order, permissions (v2), templates (v2).

Blok tipleri: `paragraph`, `heading_1..3`, `checklist`, `bullet_list`, `numbered_list`, `quote`,
`code`, `divider`, `link`, `task_reference`, `note_reference`, `table` (v2), `image/file` (v2).

### 4.7 Calendar Account

Calendar account, dış provider bağlantısıdır.

Provider: `google`, `apple_eventkit`, `apple_caldav`, `local_device`.

Alanlar: `provider`, `provider_account_id`, `encrypted_access_token`, `encrypted_refresh_token`,
`expires_at`, `sync_token`, `webhook_channel_id`, `webhook_resource_id`, `default_calendar_id`,
`status`, `last_synced_at`.

### 4.8 Calendar Event Link

Task ile calendar event arasındaki eşleştirme.

Alanlar: `task_id`, `calendar_account_id`, `provider`, `provider_calendar_id`,
`provider_event_id`, `provider_event_uid`, `etag`, `last_provider_updated_at`,
`last_local_updated_at`, `sync_direction`, `conflict_status`.

### 4.9 Reminder / Alarm

Reminder, task alarm yaşam döngüsüdür.

Alanlar: `task_id`, `remind_at`, `timezone`, `alarm_level`, `is_urgent`,
`requires_acknowledgement`, `delivered_at`, `acknowledged_at`, `snoozed_until`, `repeat_rule`.

## 5. Sistem mimarisi

### 5.1 Yüksek seviye mimari

```txt
Flutter App
  ├─ iOS
  ├─ Android
  ├─ macOS
  ├─ Windows
  ├─ Linux
  └─ Web
      │
      │ REST + WebSocket
      ▼
Node.js JavaScript API
  ├─ Auth Module
  ├─ Project Module
  ├─ Task Module
  ├─ Notes Module
  ├─ Reminder Module
  ├─ Calendar Sync Module
  ├─ Sync Engine
  ├─ Notification Module
  └─ Audit Module
      │
      ├─ MySQL
      ├─ Redis
      ├─ Job Worker
      └─ Calendar Providers
            ├─ Google Calendar API
            ├─ Apple EventKit Bridge
            └─ Apple CalDAV Connector
```

### 5.2 Backend stack

- Runtime: Node.js LTS.
- Language: **JavaScript only** (TypeScript yasak).
- Framework: Fastify.
- DB driver: mysql2. Migration: knex.
- Validation: JSON schema / Ajv.
- Auth: JWT access token + refresh token rotation. Password hashing: argon2.
- Realtime: Socket.IO. Scale-out: Redis adapter.
- Jobs: BullMQ (Redis).
- Tests: Vitest. Logging: pino.
- OpenAPI: generated or manually maintained contract.

### 5.3 Flutter stack

- Flutter stable, Dart.
- Riverpod, go_router, dio.
- drift/sqlite (local DB), flutter_secure_storage.
- flutter_local_notifications; firebase_messaging optional for push.
- flutter_quill (editor adayı); table_calendar veya custom calendar view.
- Platform channels for Apple EventKit.

## 6. Sync mimarisi

### 6.1 Sync hedefi

Uygulama offline çalışabilmeli, sonra sunucu ile güvenli şekilde senkronize olmalıdır.

Temel yaklaşım: MySQL canonical source • client local DB • server revision log • client mutation
outbox • idempotent push • incremental pull • WebSocket change notification.

### 6.2 Server revision

Her workspace için monoton `revision` değeri; `sync_revisions` tablosunda entity değişiklikleri
tutulur.

```sql
CREATE TABLE sync_revisions (
  id CHAR(26) PRIMARY KEY,
  workspace_id CHAR(26) NOT NULL,
  revision BIGINT NOT NULL,
  entity_type VARCHAR(64) NOT NULL,
  entity_id CHAR(26) NOT NULL,
  operation ENUM('create','update','delete') NOT NULL,
  changed_fields JSON NULL,
  created_at DATETIME(3) NOT NULL,
  UNIQUE KEY uq_workspace_revision (workspace_id, revision),
  KEY idx_entity (entity_type, entity_id)
);
```

### 6.3 Client push

Client offline değişiklikleri `client_mutation_id` ile yollar:

```json
{
  "clientId": "01H...",
  "baseRevision": 123,
  "mutations": [
    {
      "clientMutationId": "01H...",
      "entityType": "task",
      "entityId": "01H...",
      "operation": "update",
      "patch": { "title": "Yeni başlık", "priority": "urgent" },
      "localUpdatedAt": "2026-07-14T10:00:00.000Z"
    }
  ]
}
```

Server: mutation id daha önce işlendi mi kontrol eder → authorization kontrol eder → conflict
kontrol eder → değişikliği uygular → revision üretir → WebSocket event yayınlar.

### 6.4 Client pull

```txt
GET /api/v1/sync/pull?workspaceId=...&sinceRevision=123
```

```json
{
  "workspaceId": "01H...",
  "fromRevision": 123,
  "toRevision": 130,
  "changes": [
    { "revision": 124, "entityType": "task", "entityId": "01H...", "operation": "update", "data": {} }
  ]
}
```

### 6.5 Conflict policy

Metadata: field-level last-write-wins; server timestamp canonical; client patch bazlı update.

Notes: v1 document-level optimistic lock; conflict olursa duplicate draft ("Local conflicted
copy") oluştur, kullanıcı merge eder. v2 block-level conflict. v3 CRDT değerlendir.

Calendar: Google etag/updated timestamp; CalDAV ETag; Apple EventKit local event id.
Conflict durumları: `local_changed_provider_changed`, `provider_deleted_local_exists`,
`local_deleted_provider_exists`, `time_conflict`.

## 7. Calendar sync blueprint

### 7.1 Calendar event üretim kuralı

Task şu koşullarda calendar event'e mirror edilir:

- `calendar_mirror_enabled = true`, ve
- task scheduled start/end içeriyor, veya
- urgent reminder calendar block olarak gösterilmek isteniyor.

Event title: `[Task] {task.title}`

Event metadata: internal task id, workspace id, project id, sync source, last local revision.

Google için (bkz. ADR-0003 — key isimleri):

- `extendedProperties.private.alliswell_task_id`
- `extendedProperties.private.alliswell_workspace_id`

Apple EventKit için:

- Notes içine machine-readable marker (v1).
- URL field içine custom scheme (v1): `alliswell://task/{taskId}`.
- Backend mapping tablosu zorunlu.

CalDAV için: ICS UID mapping + ETag mapping.

### 7.2 Google Calendar sync akışı

1. Kullanıcı Google hesabı bağlar.
2. OAuth token encrypted saklanır.
3. Kullanıcı default calendar seçer.
4. İlk full sync yapılır.
5. `nextSyncToken` saklanır.
6. Push notification channel kurulur.
7. Webhook geldiğinde ilgili account "dirty" yapılır.
8. Worker incremental sync yapar.
9. App-generated event'ler extended property ile eşleşir.
10. Dışarıdan değiştirilen event task'a uygulanır.

### 7.3 Apple Calendar sync

Level 1 — iOS/macOS EventKit: Flutter platform channel, permission request, calendar list, event
CRUD, event read, app-created event mapping, foreground/background sync.

Level 2 — macOS helper capability: daha geniş local calendar sync; background refresh limitleri
ayrıca incelenir.

Level 3 — CalDAV (optional, v2): iCloud app-specific password, server-side connector,
ETag/sync-token based sync, kullanıcıya güvenlik uyarısı.

## 8. Bildirim stratejisi

### 8.1 Bildirim tipleri

Normal reminder, urgent reminder, snoozed reminder, calendar sync conflict, task assigned (v2),
project update (v2).

### 8.2 Acil bildirim UX

Acil task alarmında aksiyonlar: Tamamlandı • 5 dk ertele • 30 dk ertele • 1 saat ertele •
Yarın sabah ertele • Özel ertele.

### 8.3 Gizlilik

Bildirim payload'ı minimum bilgi içerir; task içeriği push provider üzerinden gönderilmez:

```json
{ "type": "urgent_task", "taskId": "01H...", "notificationId": "01H..." }
```

## 9. Not ve doküman stratejisi

### 9.1 Editor kararı

İlk sürüm için rich text editor (Flutter Quill adayı). Kullanıcı renk, link, heading, checklist,
kod bloğu ister; saf Markdown genel UX için zayıf kalabilir.

Storage: Delta JSON canonical • Markdown export • plain text search.

### 9.2 Note linking

Not şu entity'lere bağlanabilir: project, task, tag, document, calendar event (v2).

```sql
CREATE TABLE note_links (
  id CHAR(26) PRIMARY KEY,
  note_id CHAR(26) NOT NULL,
  linked_entity_type VARCHAR(64) NOT NULL,
  linked_entity_id CHAR(26) NOT NULL,
  created_at DATETIME(3) NOT NULL,
  UNIQUE KEY uq_note_link (note_id, linked_entity_type, linked_entity_id)
);
```

## 10. MySQL şema taslağı

> Uygulanan gerçek şema `apps/api/migrations/` altındadır ve bu taslağı temel alır
> (eklenen kolonlar için ADR-0004'e bakın).

### 10.1 users

```sql
CREATE TABLE users (
  id CHAR(26) PRIMARY KEY,
  email VARCHAR(255) NOT NULL,
  password_hash VARCHAR(255) NULL,
  display_name VARCHAR(255) NULL,
  avatar_url TEXT NULL,
  timezone VARCHAR(64) NOT NULL DEFAULT 'Europe/Istanbul',
  locale VARCHAR(16) NOT NULL DEFAULT 'tr-TR',
  created_at DATETIME(3) NOT NULL,
  updated_at DATETIME(3) NOT NULL,
  deleted_at DATETIME(3) NULL,
  UNIQUE KEY uq_users_email (email)
);
```

### 10.2 projects

```sql
CREATE TABLE projects (
  id CHAR(26) PRIMARY KEY,
  workspace_id CHAR(26) NOT NULL,
  name VARCHAR(255) NOT NULL,
  description TEXT NULL,
  color_rgb CHAR(7) NOT NULL DEFAULT '#2563EB',
  icon VARCHAR(64) NULL,
  status ENUM('active','paused','completed','archived') NOT NULL DEFAULT 'active',
  start_at DATETIME(3) NULL,
  due_at DATETIME(3) NULL,
  sort_order INT NOT NULL DEFAULT 0,
  is_favorite BOOLEAN NOT NULL DEFAULT FALSE,
  created_by CHAR(26) NULL,
  updated_by CHAR(26) NULL,
  created_at DATETIME(3) NOT NULL,
  updated_at DATETIME(3) NOT NULL,
  deleted_at DATETIME(3) NULL,
  revision BIGINT NOT NULL DEFAULT 0,
  KEY idx_projects_workspace (workspace_id),
  KEY idx_projects_status (workspace_id, status)
);
```

### 10.3 tasks

```sql
CREATE TABLE tasks (
  id CHAR(26) PRIMARY KEY,
  workspace_id CHAR(26) NOT NULL,
  project_id CHAR(26) NULL,
  parent_task_id CHAR(26) NULL,
  title VARCHAR(500) NOT NULL,
  description TEXT NULL,
  status ENUM('inbox','open','scheduled','in_progress','waiting','completed','cancelled','archived') NOT NULL DEFAULT 'open',
  priority ENUM('none','low','medium','high','urgent') NOT NULL DEFAULT 'none',
  color_rgb CHAR(7) NULL,
  start_at DATETIME(3) NULL,
  due_at DATETIME(3) NULL,
  scheduled_start_at DATETIME(3) NULL,
  scheduled_end_at DATETIME(3) NULL,
  remind_at DATETIME(3) NULL,
  timezone VARCHAR(64) NOT NULL DEFAULT 'Europe/Istanbul',
  is_urgent BOOLEAN NOT NULL DEFAULT FALSE,
  requires_acknowledgement BOOLEAN NOT NULL DEFAULT FALSE,
  repeat_rule TEXT NULL,
  estimated_minutes INT NULL,
  completed_at DATETIME(3) NULL,
  calendar_mirror_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  created_by CHAR(26) NULL,
  updated_by CHAR(26) NULL,
  created_at DATETIME(3) NOT NULL,
  updated_at DATETIME(3) NOT NULL,
  deleted_at DATETIME(3) NULL,
  revision BIGINT NOT NULL DEFAULT 0,
  FULLTEXT KEY ft_tasks_title_description (title, description),
  KEY idx_tasks_workspace_status (workspace_id, status),
  KEY idx_tasks_project (project_id),
  KEY idx_tasks_due (workspace_id, due_at),
  KEY idx_tasks_remind (workspace_id, remind_at),
  KEY idx_tasks_urgent (workspace_id, is_urgent, remind_at)
);
```

### 10.4 notes

```sql
CREATE TABLE notes (
  id CHAR(26) PRIMARY KEY,
  workspace_id CHAR(26) NOT NULL,
  project_id CHAR(26) NULL,
  created_from_task_id CHAR(26) NULL,
  title VARCHAR(500) NOT NULL,
  content_delta JSON NULL,
  content_markdown MEDIUMTEXT NULL,
  plain_text MEDIUMTEXT NULL,
  is_pinned BOOLEAN NOT NULL DEFAULT FALSE,
  is_archived BOOLEAN NOT NULL DEFAULT FALSE,
  created_by CHAR(26) NULL,
  updated_by CHAR(26) NULL,
  created_at DATETIME(3) NOT NULL,
  updated_at DATETIME(3) NOT NULL,
  deleted_at DATETIME(3) NULL,
  revision BIGINT NOT NULL DEFAULT 0,
  FULLTEXT KEY ft_notes_plain_text (title, plain_text),
  KEY idx_notes_workspace (workspace_id),
  KEY idx_notes_project (project_id)
);
```

## 11. API contract özeti

### 11.1 Task create

```http
POST /api/v1/tasks
```

```json
{
  "workspaceId": "01H...",
  "projectId": "01H...",
  "title": "Netgross teklifini bitir",
  "description": "Kalemleri tekrar hesapla",
  "priority": "urgent",
  "dueAt": "2026-07-15T12:00:00.000+03:00",
  "remindAt": "2026-07-15T11:30:00.000+03:00",
  "isUrgent": true,
  "tags": ["01H..."],
  "calendarMirrorEnabled": true
}
```

### 11.2 Task snooze

```http
POST /api/v1/tasks/:id/snooze
```

```json
{ "snoozeUntil": "2026-07-14T14:30:00.000+03:00", "reason": "30_min" }
```

### 11.3 Note create linked to task

```http
POST /api/v1/notes
```

```json
{
  "workspaceId": "01H...",
  "projectId": "01H...",
  "title": "Teklif hesaplama notları",
  "contentDelta": {},
  "contentMarkdown": "# Notlar\n\n...",
  "links": [{ "entityType": "task", "entityId": "01H..." }]
}
```

## 12. Flutter ekranları

### 12.1 Ana navigasyon

Home • Inbox • Calendar • Projects • Notes • Search • Settings

_(Revize 2026-07-14, feedback round 1: Today ve Upcoming ayrı sekmeler olmaktan çıktı —
Home her şeyin göründüğü tek kronolojik görünüm; Calendar yalnızca ay görünümü.)_

### 12.2 Home (eski "Dashboard")

Solda kronolojik görev listesi: Geciken → Bugün → Yarın → Bu hafta → Sonrası → Tarihsiz.
Sağda Apple Takvim tarzı ay ızgarası (işli günlerde nokta). Takvimden gün seçilince o günün
görevleri vurgulu ilk grup olur, kalanlar sönük (grey/disabled) ama görünür kalır. Mobilde
takvim üst yarıda, "Hide calendar" ile katlanır; tercih kalıcıdır (local storage).

Görev girişi (feedback round 2): listenin üstünde seri girişli quick-add — Enter sonrası alan
temizlenir ve ODAK KORUNUR (yaz→Enter→yaz→Enter zinciri); gün seçiliyken eklenen görev o güne
(09:00) düşer, seçim yokken tarihsiz eklenir. Sağ altta FAB, tarih/saat, hatırlatma, öncelik,
proje ve urgent seçenekli tam oluşturma sheet'ini açar (seçili gün due'ya önceden dolar).
Aynı seri-odak davranışı Inbox ve proje Tasks sekmesindeki quick-add'lerde de geçerlidir.

### 12.3 Project detail sekmeleri

Overview (proje README notu — GitHub repo ana sayfası gibi, `projects.readme_note_id`) •
Tasks (canlı liste + hızlı ekleme) • Notes (canlı liste + hızlı not) • Documents • Calendar •
Activity

### 12.4 Task detail alanları

Title, Project, Status, Priority, Tags, Due date, Reminder, Urgent toggle, Calendar mirror toggle,
Notes, Checklist, Activity.

### 12.5 Notes

All notes • Pinned • Archive • Project notes • Task linked notes • Search • Editor.
Liste ve A4-kart (Google Docs ana sayfası tarzı) görünümleri; satır/kartlarda son düzenleme +
oluşturma tarihi ve bağlı proje. Pin = tek dokunuşla yıldız (dolu/boş). Not başlığı dokümanın
sabit H1 ilk bloğudur (Apple Notes gibi); markdown export `# başlık` ile başlar.
Renk seçimi her yerde palet üzerinden yapılır — son kullanıcıya hex kodu gösterilmez/yazdırılmaz.

## 13. Open-source repo kalitesi

### 13.1 README içeriği

Ürün tanımı, ekran görüntüleri (placeholder), neden bu proje, özellikler, roadmap, mimari, tech
stack, local development, docker compose, contributing, license, security policy, AI agent guide
linkleri.

### 13.2 AGENTS.md içeriği

Kodlama kuralları; JavaScript-only backend kuralı; TypeScript yasağı; MySQL zorunluluğu; test
yazma zorunluluğu; her task sonrası docs update zorunluluğu; ADR yazma kriteri; "sıradakini yap"
davranışı; riskli kararları önce dokümante etme; büyük refactor'da migration planı yazma.

### 13.3 TASKS.md formatı

```md
### OPH-001 — Create monorepo skeleton
- [ ] Create root files
- [ ] Create apps/api
- [ ] ...
Acceptance:
- Repo boots locally.
Tests:
- N/A
```

## 14. Roadmap

- **Phase 0 — Foundation:** monorepo, docs, license, docker compose, CI, code style, backend
  skeleton, Flutter skeleton.
- **Phase 1 — Core domain:** auth, workspace, projects, tags, tasks, notes, basic API, basic
  Flutter UI.
- **Phase 2 — Local-first sync:** local DB, sync outbox, revision pull, mutation push, WebSocket
  updates, conflict handling.
- **Phase 3 — Reminder system:** local notifications, snooze, urgent reminders, notification
  devices, privacy mode.
- **Phase 4 — Calendar sync:** Google OAuth, event mirror, webhook, incremental sync, two-way
  sync, Apple EventKit bridge, Apple mapping, CalDAV design doc.
- **Phase 5 — Rich notes/documents:** Flutter rich editor, delta storage, markdown export, project
  documents, task/note backlinks, search.
- **Phase 6 — Polish & open-source readiness:** import/export, theming, accessibility,
  performance, contribution guide, public roadmap, release automation.

## 15. Kurumsal kalite gereksinimleri

### 15.1 Observability

Structured logs, request id, error code standardı, audit logs, healthcheck, metrics endpoint (v2).

### 15.2 Performance

Cursor pagination, MySQL indexes, fulltext search, WebSocket room by workspace/user, Redis fanout,
background workers, avoid N+1 queries.

### 15.3 Security

OAuth tokens encrypted, refresh token rotation, rate limit, input validation, SQL injection
protection, XSS protection for rendered notes, CSP for web, secure storage on mobile, secrets
never committed, dependency scanning.

### 15.4 Backup / export

JSON export, Markdown export for notes, ICS export for calendar items, MySQL backup docs, user
data deletion flow.

## 16. Teknik riskler

**Risk 1 — Apple Calendar cross-platform sync.** Apple tarafı Google kadar kolay değildir.
iOS/macOS için EventKit ile native entegrasyon; web/windows/android için CalDAV opsiyonel ve daha
karmaşıktır. *Mitigation:* v1 EventKit bridge; v2 CalDAV connector; UI'da destek seviyesi açık
gösterilecek.

**Risk 2 — Notes conflict.** Rich text notlarda multi-device conflict karmaşıktır. *Mitigation:*
v1 optimistic lock + conflict copy; v2 block-level versioning; v3 CRDT.

**Risk 3 — Offline sync complexity.** Offline-first sistemlerde conflict ve idempotency
zorunludur. *Mitigation:* revision log, idempotency key, deterministic mutation order, clear
conflict UI.

**Risk 4 — Notification reliability.** Mobile OS'ler background task ve notification
davranışlarını kısıtlayabilir. *Mitigation:* local scheduled notification; push only as
supplement; foreground resync; kullanıcıya permission health screen.

## 17. MVP kabul kriterleri

- Kullanıcı kayıt/giriş yapabilir; workspace oluşur.
- Proje eklenir/güncellenir/silinir; projeye RGB renk verilir.
- Task eklenir; tarihli veya tarihsiz olabilir; urgent yapılabilir; snooze edilebilir.
- Etiket eklenir; task'a etiket bağlanır.
- Not eklenir; task'a ve projeye bağlanır.
- Flutter app iOS/Android/Web/Desktop shell olarak çalışır.
- Local cache vardır; offline task oluşturulup online olunca sync olur.
- WebSocket ile başka cihazdaki değişiklik görünür.
- Local notification çalışır.
- Google Calendar'a task event olarak yazılır; event zamanı değişince task güncellenir.
- Apple EventKit bridge için permission ve create event skeleton çalışır.
- Testler CI'da çalışır.
- README açık kaynak kullanıcı için, AGENTS.md ajanların devam edebilmesi için yeterlidir.

## 18. İlk issue listesi

> Görev kırılımının canlı hali `docs/TASKS.md` dosyasındadır; aşağıdaki liste ilk plandır.

- **Epic 01 — Foundation:** OPH-001 monorepo skeleton, OPH-002 root docs, OPH-003 Docker Compose,
  OPH-004 Fastify app, OPH-005 healthcheck, OPH-006 Flutter shell, OPH-007 CI.
- **Epic 02 — Database:** OPH-010 knex setup, OPH-011 users/workspaces, OPH-012
  projects/tags/tasks, OPH-013 notes/note_links, OPH-014 sync_revisions, OPH-015 calendar tables.
- **Epic 03 — Auth:** OPH-020 register, OPH-021 login, OPH-022 refresh rotation, OPH-023 auth
  middleware, OPH-024 Flutter auth repository, OPH-025 secure token storage.
- **Epic 04 — Projects/Tags/Tasks:** OPH-030…OPH-037.
- **Epic 05 — Notes:** OPH-040…OPH-045.
- **Epic 06 — Sync:** OPH-050…OPH-057.
- **Epic 07 — Notifications:** OPH-060…OPH-064.
- **Epic 08 — Calendar:** OPH-070…OPH-079.
- **Epic 09 — Open-source readiness:** OPH-090…OPH-095.

## 19. Nihai hedef

Bu proje sadece todo uygulaması değildir. Bu proje:

- Kişisel operasyon merkezi.
- Proje bilgi tabanı.
- Calendar-aware task planner.
- Local-first productivity engine.
- Açık kaynak self-host üretkenlik platformudur.

**Her geliştirme kararı bu vizyona göre verilmelidir.**
