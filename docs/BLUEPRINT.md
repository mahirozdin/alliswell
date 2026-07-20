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
- Home-screen / masaüstü widget'ları platforma özel App-Extension yüzeyleridir: iOS/macOS'ta
  **WidgetKit** (`WidgetFamily`, App Intents ile etkileşim), Android'de **App Widgets / Jetpack
  Glance**. Flutter uygulaması ile native widget arasında veri köprüsü `home_widget` paketi +
  **App Group** (iOS/macOS) / **SharedPreferences** (Android) üzerinden kurulur — detay
  [WIDGETS.md](WIDGETS.md), karar [ADR-0010](adr/0010-home-screen-widgets-architecture.md).
- Yerelleştirme (i18n): app'e ait, **senkron** JSON dil deposu (`lib/src/i18n/`, `AwI18n`) —
  cihaz/tarayıcı dili otomatik algılanır, İngilizce'ye (`en.json`) fallback, ayarlardan kalıcı dil
  seçimi (localKv). Üçüncü parti i18n paketi yok (yalnız `flutter_localizations` SDK). Karar
  [ADR-0009](adr/0009-localization-i18n-architecture.md).

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
13. **Çok dilli / yerelleştirilebilir** (rev. 2026-07-17, feedback round 5). Uygulamada
    hardcoded metin bulunmaz; tüm arayüz JSON dil dosyalarından beslenir, cihaz/tarayıcı dili
    otomatik algılanır (İngilizce fallback) ve kullanıcı ayarlardan dili kalıcı olarak
    değiştirebilir. Bir dil eklemek = bir JSON dosyası sağlamak (§12.9, §15.5, ADR-0009).
14. **Glanceable erişim — ana ekran widget'ları** (rev. 2026-07-17, feedback round 5). Kullanıcı,
    uygulamayı açmadan görevlerini ana ekranda/masaüstünde görebilmeli, hızlı ekleyebilmeli ve
    hızlı tamamlayabilmelidir (§12.8, §15.6, ADR-0010).

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
- **Arşivleme (rev. 2026-07-17, feedback round 4 — OPH-110):** `archived` statüsü serbest bir
  dropdown seçeneği değil, ÖZEL bir akıştır. Arşivlerken kullanıcıya projenin açık görevlerini
  ve notlarını da arşivlemek isteyip istemediği sorulur (kaskad opsiyonel, sunucuda tek
  transaction); arşivden çıkarma aynı soruyu tersine sorar. Arşivli projeler proje listesinde
  varsayılan GİZLİDİR (yalnız "Archived" filtresiyle görünür) ve görev oluşturma/detay proje
  seçicilerine çıkmazlar.

### 4.3 Task / TODO

Task, sistemin en kritik domainidir.

Özellikler:

- Başlık, açıklama.
- Project relation (optional), parent task (optional), checklist items.
- Status: `inbox`, `open`, `scheduled`, `in_progress`, `waiting`, `completed`, `cancelled`,
  `archived`.
- **`inbox` bir YAKALAMA durumudur (rev. 2026-07-17, feedback round 4 — OPH-107):** Inbox'a
  atılanlar plan listelerinde (Home dahil) GÖRÜNMEZ — yakalama henüz iş değildir. Görev tarih
  YA DA proje kazandığında statü otomatik `open`'a yükselir (triyaj tamamlanmış sayılır);
  ayrıntı §12.6.
- Priority: `none`, `low`, `medium`, `high`, `urgent`.
- Color (optional), tags.
- Due date, start date, scheduled start/end, reminder time (hepsi optional).
- Urgent flag, repeat rule, estimated duration, actual duration.
- Calendar mirror flag, calendar provider mapping.
- Notes relation, attachments (**rev. 2026-07-18, feedback round 7 — v1'e alındı, Epic 14; §4.10**).

Task tipleri: simple task, scheduled task, deadline task, urgent reminder, recurring task,
checklist parent, project milestone (v2).

### 4.4 Tags / labels

Etiketler task ve notları bağlamsal olarak sınıflandırır.

Özellikler: `name`, `slug`, RGB color, icon (optional), `workspace_id`, usage count (v2).

Örnek etiketler: Acil, Beklemede, Müşteri, Yazılım, Finans, 5dk, 30dk, Telefon, Mail, Araştırma.

_(Rev. 2026-07-20, round 8 — OPH-165:)_ Etiketin doğum yeri kullanım anıdır: görev
oluşturma/detay chip-input'unda yazılan ad yoksa etiket **otomatik oluşturulur** (ayrı bir
"önce etiket yarat" ekranı dayatılmaz). UI'da `#ad` biçiminde gösterilir; ad '#'süz saklanır.
Giriş kuralları §12.4, görsel kurallar DESIGN.md §13.

### 4.5 Notes

Note, bağımsız veya task/proje bağlantılı bilgi birimidir.

Özellikler: `title`, `content_delta` (JSON), `content_markdown`, `plain_text`, `project_id`
(optional), `created_from_task_id` (optional), tags, pinned, archived, linked tasks, linked
projects, backlinks (v2).

**Satır içi medya (rev. 2026-07-18, feedback round 7 — Epic 14):** not gövdesi Quill
image/video embed'leri taşır; embed kaynağı HER ZAMAN `alliswell://file/{fileId}` şemasıdır
(ADR-0003 adlandırması) — asla presigned URL değil, çünkü presigned URL'ler süreli ve cihaza
özeldir. Render, dosya id'sini isteğe bağlı mintlenen indirme URL'ine çözer; offline'da dürüst
yer tutucu gösterilir. Ayrıntı: §4.10 + [ATTACHMENTS.md](ATTACHMENTS.md).

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

**Etkin alarm anı (rev. 2026-07-18, feedback round 6):** `remind_at` her zaman kazanır; ama
**acil (`is_urgent`) bir task, `remind_at` verilmemiş olsa bile `due_at` anında alarm çalar** —
acil bir işin bitiş saati sessizce geçiyorsa ürün asıl görevinde başarısız demektir. Tek kural
tek yerde yaşar: API `effectiveRemindAt(task)` (`src/db/reminders.js`, tüm yazım yolları
`reconcileTaskReminder` üzerinden) ve uygulamadaki sentetik alarm türetimi
(`ReminderStore.watchAlarms`) aynı kuralı aynalar — reminder satırı senkrondan önce de alarm
kurulur, satır gelince devralır.

### 4.10 File / Attachment

_(Eklendi 2026-07-18, feedback round 7 — Epic 14; bağlayıcı plan
[ATTACHMENTS.md](ATTACHMENTS.md), karar [ADR-0011](adr/0011-attachments-r2-s3-storage.md).)_

File, bir task/not/projeye ekli ikili dosyadır (resim, video, **her tür** dosya — MIME
allowlist'i yok). Metadata MySQL'de (`files` tablosu), bytes S3-uyumlu obje deposunda
(birincil hedef **Cloudflare R2**; dev/CI'da MinIO).

Alanlar: `id`, `workspace_id`, `target_type` (`project`|`task`|`note`|**`workspace`** —
rev. round 8, OPH-169), `target_id`, `uploaded_by`, `name` (görünen ad; yeniden
adlandırılabilir), `mime`, `size_bytes`, `storage_key` (opak: `ws/{workspaceId}/{fileId}` —
dosya adı içermez), `status` (`uploading`|`ready`), **`folder_id` (nullable — yalnız
`workspace` hedefli dosyalarda anlamlı; §4.11)**, `revision`, `created_at`, `updated_at`,
`deleted_at`.

_(Rev. 2026-07-20, round 8:)_ **`workspace` hedefi** dosyanın hiçbir entiteye değil doğrudan
workspace'e ait olduğu anlamına gelir (`target_id` = workspace id) — global Dosyalar
bölümünün (§12.12) "Klasörlerim" katmanı bunlardan oluşur.

Temel kurallar:

- **Bytes API'den geçmez:** yükleme presigned PUT, indirme presigned GET (varsayılan 1 saat
  TTL). API metadata + yetki servisidir; upload 3 adımdır (init → PUT → complete/HeadObject
  doğrulama). `uploading` satırlar senkrona görünmez; yalnız `ready` olanlar yayınlanır.
- **`file` pull-only senkron varlığıdır** (ADR-0008 modeli): metadata her cihazın
  replikasına iner (listeler offline çalışır); push `SYNC_UNSUPPORTED_ENTITY` cevaplar —
  yükleme doğası gereği online'dır, outbox'ta bekletmek yalan olur.
- **Yetim bayt yok:** task (alt-ağaç dahil) / not / proje silinince dosyaları da aynı
  transaction'da soft-delete edilir (her biri kendi revizyonuyla) ve obje silme işi
  kuyruklanır; 24 saati geçmiş `uploading` artıkları süpürülür. Arşivleme hiçbir şey silmez.
- **Özellik opsiyoneldir:** `STORAGE_S3_*` env yoksa uçlar `STORAGE_NOT_CONFIGURED` döner,
  uygulama dürüst boş durumlar gösterir.

### 4.11 Folder (klasör)

_(Eklendi 2026-07-20, feedback round 8 — OPH-169; bağlayıcı plan
[ATTACHMENTS.md](ATTACHMENTS.md) §14, karar [ADR-0014](adr/0014-folders-and-global-files.md).)_

Folder, global Dosyalar bölümünde (§12.12) `workspace` hedefli dosyaları örgütleyen
kullanıcı klasörüdür — Finder/Explorer zihin modeli, iç içe geçebilir.

Alanlar: `id`, `workspace_id`, `parent_id` (nullable — null = kök), `name`, `revision`,
`created_at`, `updated_at`, `deleted_at`.

Kurallar:

- Aynı üst klasör içinde ad benzersizdir (collation gereği büyük/küçük + aksan duyarsız);
  derinlik sınırı 10 (API'de zorlanır); taşıma döngü yaratamaz (kendi alt ağacına taşınamaz).
- **`folder` push-pull senkron varlığıdır** (proje/etiket gibi): klasör oluşturma/yeniden
  adlandırma/taşıma saf metadata'dır, offline yapılabilir ve outbox'la akar. (Dosyaların
  kendisi pull-only kalır — yükleme online'dır, §4.10.)
- Klasör silme alt ağacı siler (alt klasörler + içindeki workspace dosyaları; onay içerik
  sayısını açıkça söyler); dosya soft-delete + obje GC kuyruğu §4.10'daki kaskad kurallarını
  aynen izler. Ekli (project/task/note hedefli) dosyalar klasörlere GİREMEZ.

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
3. **Primary takvim OTOMATİK seçilir ve ilk full sync + watch anında kuyruklanır** (rev.
   2026-07-20, feedback round 8 — OPH-160). "Bağlandı" demek "veri akıyor" demektir; gizli
   ikinci adım yoktur. Kullanıcı isterse Ayarlar'dan farklı bir takvim seçer — seçim
   değişikliği yeni bir full sync tetikler. (Eski akıştaki "kullanıcı default calendar seçer"
   adımı, bağlanan hesabın hiç veri üretmeden 'bağlı' görünmesine yol açıyordu.)
4. `nextSyncToken` saklanır.
5. Push notification channel kurulur (webhook URL'i yoksa sweep poll'u devralır).
6. Webhook geldiğinde ilgili account "dirty" yapılır.
7. Worker incremental sync yapar; her external-event yazımı `sync:changed` soketini tetikler,
   uygulama anında pull eder. Uygulama tarafı da bağlantı dönüşünde ve takvim değişiminde
   `syncNow()` çağırır (OPH-160) — "bağla → Home'a dön → etkinlikler kendiliğinden akar".
8. App-generated event'ler extended property ile eşleşir.
9. Dışarıdan değiştirilen event task'a uygulanır.

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

**Teslimat sözleşmesi (rev. 2026-07-18, feedback round 6 — bağlayıcı ayrıntı
[NOTIFICATIONS.md](NOTIFICATIONS.md)):** acil alarm bir "ding" değil ALARMDIR — 28 sn'lik alarm
sesi; iOS'ta `timeSensitive` (Uyku/Odak modlarını deler), Android'de alarm ses kanalı
(`USAGE_ALARM`: zil sessizken bile alarm kısıklığında çalar, varsayılan DND'yi deler) +
`FLAG_INSISTENT` (açılana dek döngü) + tam ekran intent. Onaylanana dek T, +2, +5, +10, +30 dk
zinciri. Normal hatırlatıcılar da `timeSensitive` (kullanıcının saat verdiği bildirim tanımı
gereği zamana duyarlıdır; `.active` her Odak modunda sessizce gömülüyordu). iOS'ta sessiz
anahtarını yalnız Apple onaylı **Critical Alerts** (kod yolu hazır, entitlement gate'li —
görev uygulamalarına fiilen verilmiyor) veya **AlarmKit** (iOS 26+, OPH-141) aşar.

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

### 12.0 Tasarım dili — "AllisWell Glass" (kalıcı standart)

_(Eklendi 2026-07-15, tasarım turu 1 — ADR-0005. Tek kaynak:
[docs/DESIGN.md](DESIGN.md); bu bölüm özettir, çelişkide DESIGN.md kazanır.)_

Apple'ın 2026 "Liquid Glass" estetiğinden esinlenen ama **UX'i estetiğin
önüne koyan** tek tasarım dili: arka planda sakin bir aurora yıkaması,
navigasyon çubuğu/rayında buzlu cam (backdrop blur), **okunan ve dokunulan
her şey ise opak, yüksek kontrastlı yüzeylerde**. Girdi alanları her zaman
dolgulu + görünür kenarlıklı + 2 px odak halkalı; dokunma hedefleri ≥ 44 px;
metin kontrastı her iki temada ≥ 4.5:1, ikon/kenarlık ≥ 3:1 (palet
`scripts/design/contrast.py` ile doğrulanır). Renk/boşluk/köşe değerleri
yalnızca `apps/app/lib/src/theme/` token'larından gelir; hex asla widget'a
yazılmaz. **Bundan sonraki TÜM geliştirmelerde tasarım bütünlüğünün
sürdürülmesi esastır** — yeni ekranlar bu dili devralır, sapmalar aynı
değişiklikte DESIGN.md'ye işlenir (AGENTS.md sert kural 11).

### 12.1 Ana navigasyon

Home • Inbox • Projects • Notes • **Files** • Settings

_(Revize 2026-07-20, feedback round 8 — OPH-162/170: **Calendar sekmesi KALDIRILDI** — Home
zaten ay ızgarası + kronolojik listeyi tek görünümde taşıyor, ikinci bir takvim ekranı ölü
ağırlıktı. Yerine **Files (Dosyalar)** geldi: workspace'in tüm dosyalarını gösteren global
dosya yöneticisi, §12.12. "Search" ayrı bir sekme DEĞİLDİR — arama her içerik ekranının kendi
gövdesinde yaşar (§12.10); tek global arama ekranı v2 parking-lot'ta durur.)_

_(Revize 2026-07-14, feedback round 1: Today ve Upcoming ayrı sekmeler olmaktan çıktı —
Home her şeyin göründüğü tek kronolojik görünüm.)_

### 12.2 Home (eski "Dashboard")

Solda kronolojik görev listesi, sağda (geniş ekranda) Apple Takvim tarzı ay ızgarası (işli
günlerde nokta). Takvimden gün seçilince o günün görevleri vurgulu ilk grup olur, kalanlar
sönük (grey) ama görünür kalır — **Tarihsiz grubu hariç** (aşağıda).

_(Revize 2026-07-17, feedback round 4 — OPH-102/103/104. Eski "…→ Sonrası → Tarihsiz" düzeni
kaldırıldı.)_

- **Gruplar ve sıra:** Geciken → **Tarihsiz** → Bugün → Yarın → Bu hafta → **Sonraki 30 gün**.
  Sınırlar: Bugün = yerel gün; Yarın = +1; Bu hafta = +2…+6; Sonraki 30 gün = +7…+30 (dahil).
- **Ufuk 30 gündür; "Sonrası/Later" grubu YOK.** +30 günden ileri tarihli görevler ve takvim
  etkinlikleri Home'un kronolojik akışına girmez — böylece aylık/haftalık tekrar eden bir
  toplantının sonsuz örnekleri listeyi doldurmaz ve önündeki işler rahat görünür. (Ay
  ızgarasının noktaları ufuktan bağımsızdır — her tarihli gün işlenir.) **Seçili gün ufku
  aşar (rev. 2026-07-20, round 8 — OPH-162):** Calendar sekmesi kalktığı için ızgaradan +30
  ötesi bir gün seçilince o günün görev ve etkinlikleri seçili-gün grubunda GÖSTERİLİR —
  uzak tarihlere bakma görevi artık ızgara + arama (§12.10) üzerindedir.
- **Tarihsiz görevler listenin ÜSTÜNDE durur** (Geciken'in hemen altında, Bugün'ün üstünde) ve
  HİÇBİR ZAMAN sönük çizilmez: tarihi olmayan iş "her günün işi"dir; takvimden gün seçiliyken
  bile tam opaklıkta kalır. (Inbox yakalamaları bu gruba GİRMEZ — §12.6.)
- **Mobilde takvim listeyle birlikte kayar:** ay ızgarası kayan içeriğin İLK öğesidir, sabit
  (sticky) başlık DEĞİLDİR — liste yukarı kaydırılınca takvim ekrandan çıkar, en üste dönünce
  geri gelir. "Hide calendar" düğmesi ve kalıcı tercihi (local storage) aynen durur. Quick-add
  çubuğu kaymaz (seri giriş her an elde). Geniş ekranda takvim sağ panelde sabittir (değişmedi).
- **Proje rozeti:** projeye bağlı her görev satırının sağ ucunda projenin renginde DOLU bir
  rozet bulunur; içinde proje adı yazar (6 karakterden uzunsa ilk 6 karakter + "…"); üzerine
  gelince / uzun basınca tam ad tooltip'te görünür. Hangi görev hangi projenin, tek bakışta.
  Görsel kural: DESIGN.md §4 "Project badge".
- **İki görünüm: Liste | Pano (rev. 2026-07-20, round 8 — OPH-168):** Home'un üstünde görünüm
  anahtarı; **Liste varsayılandır** ve yukarıdaki kronolojik davranışın tamamı ona aittir.
  **Pano** aynı görev kümesinin status-sütunlu Kanban görünümüdür (sürükle-bırak, sütun
  gizle/sırala); tercih cihaz-yereldir ve kalıcıdır. Tam spec: §12.11 + DESIGN.md §14.

Görev girişi (feedback round 2): listenin üstünde seri girişli quick-add — Enter sonrası alan
temizlenir ve ODAK KORUNUR (yaz→Enter→yaz→Enter zinciri); gün seçiliyken eklenen görev o güne
**varsayılan görev saatinde** düşer, seçim yokken tarihsiz eklenir. **Varsayılan görev saati
bir AYARDIR (rev. 2026-07-20, round 8 — OPH-161):** fabrika değeri **23:59** ("gün bitene
kadar" anlamı; eski sabit 09:00 sabahın köründe alarm gibi davranıyordu), Ayarlar'dan
kullanıcı değiştirir (cihaz-yerel tercih). Saat tek bir yardımcıdan okunur — quick-add, FAB
ön-dolumu ve tarih seçicilerin saat fallback'i dahil hiçbir yüzey saat sabitlemez.

Sağ altta FAB tam oluşturma sheet'ini açar (seçili gün due'ya önceden dolar). Sheet round 8
ile büyüdü (OPH-163/164/165/166): tarih/saat, hatırlatma, öncelik, urgent'a ek olarak
**açıklama alanı** (§12.4), **etiket girişi** (chip-input, §12.4), **ek seçimi** (dosyalar
kaydetle birlikte yüklenir; depo yapılandırılmamışsa dürüst uyarı) ve proje seçicisinin
sonunda **"+ Proje ekle"** (sheet'ten çıkmadan proje oluştur → otomatik seçilir; aynı seçici
task detayında da bu affordance'ı taşır). Aynı seri-odak davranışı Inbox ve proje Tasks
sekmesindeki quick-add'lerde de geçerlidir.

### 12.3 Project detail sekmeleri

Overview (proje README notu — GitHub repo ana sayfası gibi, `projects.readme_note_id`) •
Tasks (canlı liste + hızlı ekleme) • Notes (canlı liste + hızlı not) • **Files (dosya
yöneticisi — Epic 14)** • Documents • Calendar • Activity

_(Rev. 2026-07-18, feedback round 7 — OPH-155:)_ **Files sekmesi** projenin dosya
yöneticisidir: projenin kendi dosyaları ∪ görevlerinin ∪ notlarının dosyaları tek listede
(replika sorgusu — offline çalışır), kaynak rozetiyle (Project/Task/Not adı). Kaynak filtre
çipleri (All · Project · Tasks · Notes), varsayılan sıralama en yeni; yükle FAB'ı dosyayı
PROJEYE ekler. Satır eylemleri: aç/indir (presigned URL), yeniden adlandır, sil (onaylı).
Depo yapılandırılmamışsa dürüst boş durum (`STORAGE_S3_*` işaret edilir) — spinner değil.

_(Rev. 2026-07-17, feedback round 4 — OPH-109/110:)_ README notu **proje bağlamında**
düzenlenir: Overview'daki "Create README" / kalem, editörü mevcut ekranın ÜSTÜNE push'lar
(Notes sekmesine GEÇMEZ); geri dönüş Overview'a iner ve README kartı canlı güncellenir.
Projenin kendi README'si projenin Notes sekmesinde de listelenmez — yeri Overview'dır.
Proje sekmelere döndüğünde detay değil LİSTE açılır (sekmeler bölümdür, yığın değil —
OPH-108). Arşivli proje detayı "arşivli" bandı + Unarchive eylemi gösterir.

### 12.4 Task detail alanları

Title (yerinde düzenlenebilir, otomatik kayıt), **Description (açıklama — rev. round 8)**,
Project, Status, Priority, Tags, Due date, Reminder, Urgent toggle, Calendar mirror toggle,
Notes, Checklist, **Attachments (Epic 14)**, Activity.

_(Rev. 2026-07-20, feedback round 8 — OPH-164:)_ **Description** görevin kendi açıklama
alanıdır — Notes İLİŞKİSİNDEN ayrıdır ve nota kaydolmaz: görevle ilgili bağlam, linkler,
kısa detaylar burada yaşar. Hem oluşturma sheet'inde hem detayda düzenlenebilir (başlık gibi
otomatik kayıt). Düz metin saklanır (`tasks.description`); görüntülemede **URL'ler otomatik
algılanır ve tıklanabilir** (dokunma sistem tarayıcısında açar). Zengin biçimlendirme ve OG
link önizlemesi bilinçli v2'dir (parking-lot) — görev açıklaması not editörü değildir; uzun
içerik isteyen kullanıcıya doğru cevap bağlı Not'tur.

_(Rev. 2026-07-20, feedback round 8 — OPH-165:)_ **Tags** bölümü artık bir seçici DEĞİL,
giriş alanıdır: chip-input'a yaz, Tab/Enter/virgül chip'e çevirir; mevcut etiketler
büyük/küçük harf ve Türkçe aksan duyarsız önerilir (§12.10 fold kuralı), **olmayan etiket
otomatik OLUŞTURULUR** (workspace-scoped). Chip'ler `#ad` biçiminde görünür ('#' yalnız
gösterimdir; ad '#'süz saklanır, kullanıcı '#' yazarsa yutulur). Chip'in ×'i görevden
çıkarır; "Etiketleri yönet" ile ad/renk düzenleme + workspace'ten silme (onaylı) yapılır.
Aynı chip-input oluşturma sheet'inde de vardır. Görsel kurallar: DESIGN.md §13.

_(Rev. 2026-07-18, feedback round 7 — OPH-154:)_ **Attachments bölümü** checklist'in altında
kendi kartında yaşar: ekle butonu (dosya seçici), yüklerken ilerleme çubuklu satır (iptal
edilebilir), hazır dosyalarda başparmak (resim) / tür ikonu (video, diğer), ad + boyut +
tarih. Dokunma: resim → tam ekran görüntüleyici; diğerleri → aç/indir · yeniden adlandır ·
sil eylem sayfası. Yükleme açıkça görünür ve iptal edilebilir — arka plan kuyruğu yalanı yok
(offline'da dürüst hata).

Görsel standart (feedback round 3; ikonlar rev. 2026-07-17 feedback round 4 — OPH-105):
**statüler ikonla** gösterilir (inbox=gelen kutusu, open=**kum saati** [boş daire DEĞİL —
boş daire satır başındaki dairesel tamamlama kutusuyla karışıyordu], scheduled=takvim,
in_progress=timelapse, waiting=**duraklat dairesi** [kum saatini open'a devretti],
completed=dolu onay, cancelled=iptal, archived=arşiv), **öncelikler renkle**
(low=yeşil, medium=amber, high=turuncu, urgent=kırmızı; none=nötr) — listelerde görev
satırında renkli bayrak + statü ikonu, dropdown'larda ikon/renk + isim birlikte. Proje
seçicilerde projenin rengi isimden önce içi dolu nokta olarak görünür (hex asla gösterilmez).

### 12.5 Notes

All notes • Pinned • Archive • **READMEs** • Project notes • Task linked notes • Search • Editor.
Liste ve A4-kart (Google Docs ana sayfası tarzı) görünümleri; satır/kartlarda son düzenleme +
oluşturma tarihi ve bağlı proje. Pin = tek dokunuşla yıldız (dolu/boş). Not başlığı dokümanın
sabit H1 ilk bloğudur (Apple Notes gibi); markdown export `# başlık` ile başlar.
Renk seçimi her yerde palet üzerinden yapılır — son kullanıcıya hex kodu gösterilmez/yazdırılmaz.

_(Rev. 2026-07-17, feedback round 4 — OPH-109:)_ **README notları varsayılan listelerde
GÖRÜNMEZ** (All/Pinned/Archive onları dışlar) — proje README'si projenin Overview'ına aittir,
not listesinde kopya gürültüdür. Yeni **READMEs** filtre çipi YALNIZ readme notlarını listeler
(satırda projenin renk noktası + adı ile).

_(Rev. 2026-07-18, feedback round 7 — OPH-156:)_ **Editörde satır içi resim/video:** araç
çubuğuna resim/video ekleme butonları gelir; seçilen dosya nota yüklenir (hedef = not) ve
tamamlanınca delta'ya `alliswell://file/{fileId}` kaynaklı standart Quill embed'i düşer.
Render: resimler inline (yüklenme shimmer'ı, dokun = görüntüleyici), video/diğerleri ad +
aç eylemli kutucuk; URL çözülemezse (offline) dosya adlı yer tutucu — kırık-resim glifi asla.
Embed'i gövdeden silmek dosya SATIRINI silmez (undo güvenliği) — dosya, notun eklerinde ve
projenin Files sekmesinde yaşamaya devam eder; oradan açıkça silinebilir. Markdown export
resim embed'ini `![ad](alliswell://file/{id})`, diğerlerini `[ad](…)` olarak yazar.

### 12.6 Inbox — yakalama kutusu

_(Revize 2026-07-17, feedback round 4 — OPH-107. Eski davranış: Inbox quick-add'i sıradan
görev ekliyordu ve bunlar Home'da iş olarak görünüyordu.)_

Inbox bir görev listesi değil, **düşünce yakalama kutusudur** (GTD "inbox"): akla gelen fikir
kaybolmasın diye SERİ yazılır, sonra değerlendirilir/projelendirilir. Davranış:

- Inbox quick-add'i `status=inbox` ile yazar; bu kayıtlar **Home'da ve hiçbir plan listesinde
  görünmez** — yakalama, henüz taahhüt edilmiş iş değildir.
- Satırlar görev satırı gibi DEĞİL, yakalama satırı gibi çizilir: tamamlama kutusu YOK; üç
  triyaj eylemi VAR — **Planla** (tarih/proje/öncelik seçtiren sheet; kaydedince statü `open`
  olur ve kayıt Home'a taşınır), **Nota çevir** (başlığı içerik olan yeni not oluşur, yakalama
  silinir — onay istenir), **Sil**. Satıra dokunmak Planla'yı açar.
- Bir yakalamaya HERHANGİ bir yerden tarih VEYA proje verilirse statü otomatik `open` olur
  (triyaj tamamlanmıştır; §4.3).
- Boş durum ve ipucu metinleri kutunun amacını kullanıcıya AÇIKÇA anlatır ("yaz, sonra ayıkla;
  buraya atılanlar Home'a düşmez").

### 12.7 Onboarding ve özellik turu

_(Eklendi 2026-07-17, feedback round 4 — OPH-111.)_

İlk oturum açılışında (cihaz başına bir kez, yerel kalıcı bayrak) karşılama kartı + navigasyon
öğelerinin adım adım **spotlight turu**: her sekme sırayla vurgulanır (kalanlar karartılır),
baloncuk o bölümün NE olduğunu ve NASIL kullanıldığını 1-2 cümleyle anlatır — Inbox'ın yakalama
anlamı, Home'un 30 günlük ufku, quick-add/FAB farkı ve Settings'teki takvim bağlama dahil.
Sağ üstte her an **Skip**; turu atlamak hiçbir şeyi kilitlemez. Settings'te **"App tour"**
satırı turu istendiği kadar tekrar başlatır. Tur, cam tasarım diliyle uyumlu elle yazılmış bir
overlay'dir (yeni paket bağımlılığı YOK); dar ekranda alt bara, geniş ekranda raya çapalanır.

### 12.8 Ana ekran / masaüstü widget'ları

_(Eklendi 2026-07-17, feedback round 5 — Epic 12. Bağlayıcı plan: [WIDGETS.md](WIDGETS.md);
karar [ADR-0010](adr/0010-home-screen-widgets-architecture.md); görsel spec DESIGN.md §8.
Çelişkide WIDGETS.md + ADR-0010 kazanır.)_

Kullanıcı, uygulamayı açmadan görevlerini ana ekranda görebilmeli; hızlı ekleyip hızlı
tamamlayabilmelidir — Apple Reminders + Apple Takvim widget'larının birleşimi.

- **Platformlar:** iOS, iPadOS, Android, macOS. Web/Windows/Linux'te ana ekran widget yüzeyi
  kapsam dışıdır (widget o platformlarda kendini gizler).
- **Üç boyut** (kullanıcı isteği "4×2 ≈ ekranın ⅓'ü", "4×4 ≈ ⅔", "4×6 / tam ekran"):
  - **4×2 (~⅓):** iOS `systemMedium` · Android 4×2. Kompakt tarih başlığı + ilk 3-4 görev +
    hızlı-ekle "+".
  - **4×4 (~⅔):** iOS `systemLarge` (iPhone'da EN BÜYÜK) · Android 4×4. Tam tarih başlığı +
    kaydırılabilir bucket listesi (~8-10 satır) + hızlı-ekle satırı.
  - **4×6 / tam ekran:** **iPhone'da MÜMKÜN DEĞİL — WidgetKit'te iPhone için `systemLarge`
    (4×4) üstü bir ana ekran boyutu yoktur.** Bu istek platform gerçeğiyle çakışıyor ve şöyle
    karşılanır: **iPad/macOS'ta `systemExtraLarge`** (~8×4 yatay), **Android'de gerçek,
    yeniden boyutlanabilir 4×6**; iPhone'da en büyük tier `systemLarge`'a iner. (Kapsam kesintisi
    değil, platform sınırı — her platformda fiziksel olarak izin verilen kadarı verilir.)
- **A) Sürekli senkron.** Widget, drift replica'sını okuyamaz (ayrı sandbox); uygulama her görev
  değişiminde `home_widget` ile paylaşımlı konteynere küçük bir JSON snapshot yazar ve widget'ı
  tazeler. Ön planda yapılan bu tazelemeler Apple'ın yenileme bütçesinden MUAFtır → widget bedava
  senkron kalır (WIDGETS.md §6).
- **B) Home özeti, kaydırılabilir bucket'lar.** Widget, Home'un kronolojik gruplarını aynalar
  (saf `groupTasksForWidget`, `groupTasksForHome`'un kardeşi): **Gecikmiş → Tarihsiz → Bugün →
  Bu hafta → Bu ay**, içinde kaydırılır. Ufuk ayın sonudur (tekrar eden etkinlikler taşmasın).
- **C) En büyük boyutta takvim başlığı.** Tepede Apple-Takvim tarzı tarih başlığı: o günün
  **gün adı + gün sayısı** (ve `systemExtraLarge`/4×6'da opsiyonel hafta şeridi / mini ay ızgarası).
- **D) Hızlı ekle + hızlı tamamla (uygulamayı açmadan).** iOS 17+/macOS 14+ App Intents
  (`Button/Toggle(intent:)`) ve Android Glance aksiyonları, dairesel checkbox'a dokununca görevi
  arka planda tamamlar (satır ~1-2 sn sonra kaybolur), "+" hızlı ekler. Yazımlar **yerel-önce
  `TaskStore`'dan geçer** (optimistic + outbox → sunucuya senkron olur). iOS 16 tabanında yalnız
  derin bağlantı (dokunma uygulamayı açar). Dokunma hedefleri cömert olmalı (Reminders dersi).
- **Etiketler yerelleştirilmiş gelir:** snapshot metinleri uygulama tarafından çevrilir (Epic 11) —
  native widget çeviri paketi taşımaz. Bu yüzden **Epic 12, Epic 11'e (i18n) bağımlıdır.**
- **Gizlilik:** "Private widget" seçeneği (OPH-064 ruhu) açıkken widget başlık yerine sayı/yer
  tutucu gösterir. Cihaz-yerel ayar.

### 12.9 Uygulama dili ve yerelleştirme (i18n)

_(Eklendi 2026-07-17, feedback round 5 — Epic 11. Karar [ADR-0009](adr/0009-localization-i18n-architecture.md);
mimari §15.5.)_

Uygulamada (ve aynı Flutter kodundan derlenen web'de) hardcoded metin bulunmaz. Davranış:

- **Diller JSON'dur.** `assets/i18n/en.json` (temel/fallback) + `tr.json` ile başlanır. Bir dil
  eklemek = `<kod>.json` sağlamak + locale'i kaydetmek (Dart'a dokunmadan).
- **Otomatik algılama:** kayıtlı bir tercih yoksa cihaz dili kullanılır; desteklenmeyen bir dil
  İngilizce'ye düşer. TR cihaz + `tr.json` varsa uygulama Türkçe açılır.
- **Web:** varsayılan tarayıcı dili; ayarlardan yapılan seçim yine kalıcıdır ve kazanır.
- **Ayarlardan kalıcı değişim:** Settings → **Dil** (Sistem / English / Türkçe …) anında,
  yeniden başlatmadan değiştirir ve seçimi cihazda saklar (localKv).
- **Hesaba bağlı dil:** seçilen dil `PATCH /me { locale }` ile `users.locale`'e yazılır; yeni bir
  cihazda, yerel tercih yoksa uygulama `GET /me.locale` ile o dilde açılır (yerel tercih yereldeyken
  yine öncelikli).
- **Hata mesajları:** API dilden bağımsız `code` döndürür; uygulama `code`'u yerelleştirilmiş
  mesaja çevirir (`error.<CODE>`), yoksa sunucu `message`'ına düşer.
- **RTL v1 kapsamı dışındadır** (en + tr LTR); mimari RTL'i engellemez (v2).

### 12.10 Arama (feedback round 8 — OPH-167)

_(Eklendi 2026-07-20; mimari karar [ADR-0013](adr/0013-local-first-search.md), görsel
kurallar DESIGN.md §12.)_

Arama ayrı bir ekran değil, her içerik ekranının kendi yeteneğidir — **Home** (görevler +
bağlı takvim etkinlikleri + Fikirler yakalamaları), **Notlar** (başlık + gövde), **Projeler**
(ad + açıklama). Notlar'daki mevcut arama alanı kalıbı (gövdede TextField, filtre çipleriyle
AND) tüm ekranlara genellenir.

- **Katmanlı sıralama:** başlık eşleşmesi > etiket eşleşmesi > gövde/açıklama eşleşmesi.
  Eşleşmenin nerede olduğu satırın ikincil metninde dürüstçe gösterilir (ör. gövde snippet'i
  veya `#etiket`).
- **Fold kuralı (ürün sözü):** arama büyük/küçük harf VE Türkçe aksan duyarsızdır —
  `ı/i/İ/I`, `ü/u`, `ö/o`, `ş/s`, `ç/c`, `ğ/g` eş sayılır; "cay" araması "Çay"ı, "ISI"
  araması "ısı"yı bulur. Tek fold fonksiyonu hem sorguya hem metne uygulanır (ADR-0013);
  kelime sırası dayatılmaz (çok kelimeli sorguda her kelime ayrı aranır, hepsi eşleşmeli —
  AND semantiği).
- **Yerel ve anlıktır:** tüm veri zaten cihaz replikasında olduğundan arama drift/SQLite
  üzerinde koşar — offline çalışır, ağ beklemez. Debounce ~250 ms; sonuç gecikirse (büyük
  korpus) spinner değil ilerleme göstergesi satırı görünür. Sunucu paritesi: `?q=` parametresi
  API listelerinde de yaşar (notlar mevcut; görevler round 8'de eklenir — hazır bekleyen
  `ft_tasks_title_description` FULLTEXT index'i kullanılır) — başka istemciler/entegrasyonlar
  için; uygulama kendi aramasında REST'e ÇIKMAZ.
- **Takvim etkinlikleri aramaya dahildir** (Home): `summary` + `location` alanları aynı fold
  kuralıyla aranır; sonuç satırı normal event satırıdır (salt-okunur işaretiyle).

### 12.11 Pano — Home Kanban görünümü (feedback round 8 — OPH-168)

_(Eklendi 2026-07-20; etkileşim spec'i araştırma kaynaklarıyla DESIGN.md §14'te.)_

Pano, Home'daki görev kümesinin status-sütunlu görünümüdür (sütun = `inbox…archived` status
seti; takvim etkinlikleri Pano'ya girmez — onlar görev değildir). Temel kararlar:

- **Sütun yönetimi kullanıcınındır:** "Görünümü düzenle" sheet'i sütun gizle/göster +
  sırala sunar; tercih cihaz-yereldir ve kalıcıdır. Varsayılan görünür set: `open`,
  `in_progress`, `waiting`, `completed` (yakalama kutusu `inbox` Fikirler'de yaşadığı,
  `scheduled` Liste'nin kronolojisinde daha anlamlı olduğu için varsayılanda kapalı —
  kullanıcı isterse açar).
- **Taşıma iki eş yoldur:** sürükle-bırak (masaüstü/web: klasik çoklu sütun; telefonda
  long-press) VE her kartın "Durum değiştir" eylemi (bottom sheet) — ikincisi ekran
  okuyucu/erişilebilirlik yolu ve drag'in çalışmadığı her durumun sigortasıdır. Bırakınca
  optimistic güncelleme + geri-al snackbar'ı.
- **Telefonda pager:** tek sütun ≈ ekran genişliği, komşu sütunun ~%10'u görünür (peek);
  sürükleme sırasında ekran kenarında bekletmek pager'ı bir sütun ilerletir.
- Kart anatomisi görev satırıyla aynı DNA'yı taşır (öncelik bayrağı, proje rozeti, due).
  Boş sütun asla sıfır-yükseklik çizilmez (bırakma hedefi + "+ Görev ekle" affordance'ı).

### 12.12 Dosyalar — global dosya yöneticisi (feedback round 8 — OPH-169/170)

_(Eklendi 2026-07-20; domain modeli §4.10/§4.11, bağlayıcı plan
[ATTACHMENTS.md](ATTACHMENTS.md) §14, karar [ADR-0014](adr/0014-folders-and-global-files.md).)_

Ana menüdeki **Files (Dosyalar)** bölümü workspace'in TÜM dosyalarını tek yerden gösterir —
Finder/Explorer sadeliğinde, iki katmanlı:

- **Klasörlerim:** hiçbir entiteye bağlı olmayan, doğrudan workspace'e yüklenmiş dosyalar +
  kullanıcı klasörleri (iç içe, taşı/yeniden adlandır/sil). Yükleme buraya `workspace`
  hedefiyle yapılır; klasörler YALNIZ bu katmanı örgütler.
- **Kaynaklar:** projelere/görevlere/notlara ekli dosyaların canlı toplu görünümü (kaynak
  rozetli, filtrelenebilir, "kaynağa git" navigasyonu). Ekli dosyalar klasöre TAŞINMAZ —
  yaşam döngüleri sahiplerine bağlıdır (silme kaskadı §4.10); yöneticide görünmeleri
  organizasyon değil erişim içindir.
- Satır eylemleri proje Files sekmesiyle birebir aynı bileşenlerdir (aç/indir, yeniden
  adlandır, sil onaylı; sıralama ad/boyut/tarih). Klasör silme içerik sayısını onayda açıkça
  söyler ve alt ağacı (alt klasörler + dosyalar) siler — depo objeleri GC kuyruğuyla gider,
  yetim bayt kuralı (§4.10) burada da geçerlidir.
- Depo yapılandırılmamışsa bölüm dürüst boş durum gösterir (`STORAGE_NOT_CONFIGURED` —
  spinner yalanı yok); **Kaynaklar** katmanı yine listelenir (metadata replikada).

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
- **Phase 7 — Localization & widgets (v0.2.0, feedback round 5):** JSON i18n (device/browser
  auto-detect, en fallback, settings override, en+tr) — Epic 11; home-screen/desktop widgets on
  iOS/Android/macOS (3 sizes, bucketed summary, calendar header, quick add/complete) — Epic 12.
  i18n ships first so widgets are born localized. Feedback round 6 added Epic 13 (alarm
  backbone) to the same release.
- **Phase 8 — Attachments & files (v0.3.0, feedback round 7):** Cloudflare R2 / S3-compatible
  object storage, presigned direct upload/download, attachments on tasks, inline images/videos
  in notes, project "Files" tab as a simple file manager — Epic 14
  ([ATTACHMENTS.md](ATTACHMENTS.md), ADR-0011).
- **Phase 9 — Feedback round 8: akış hızı, arama, pano, global dosyalar (v0.4.0):** Google
  bağlantısında otomatik primary takvim + anında ilk sync (gizli adım ölür); varsayılan görev
  saati ayarı (23:59); Calendar sekmesi yerine global **Files**; oluşturma sheet'inde inline
  proje + açıklama + etiket chip-input + ek seçimi; görev açıklaması (linkify); TR-duyarsız
  yerel arama (Home/Notlar/Projeler); Home **Pano** (Kanban) görünümü; klasörlü global dosya
  yöneticisi — Epic 15 (ADR-0013 arama, ADR-0014 klasörler).

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

_(Ek 2026-07-18, Epic 14 — obje depolama:)_ S3/R2 kimlik bilgileri YALNIZ sunucuda
(`STORAGE_S3_*` env); istemciler tek-nesne, tek-fiil, süreli presigned URL alır. Storage
key'ler opaktır (`ws/{wsId}/{fileId}` — URL/log'larda dosya adı/PII yok). Dosya adları
görüntü verisidir: kontrol karakterleri reddedilir, path ayırıcılar temizlenir, indirmeler
RFC 5987 `filename*` ile servis edilir. Bytes hiçbir zaman app origin'inden servis edilmez
(SVG-XSS sınıfı bizim domain'e dokunamaz); `response-content-type` DB'den sabitlenir.
Presigned URL'ler loglanmaz, senkrona/export'a yazılmaz.

### 15.4 Backup / export

JSON export, Markdown export for notes, ICS export for calendar items, MySQL backup docs, user
data deletion flow.

### 15.5 Uluslararasılaştırma (i18n)

_(Eklendi 2026-07-17, feedback round 5 — [ADR-0009](adr/0009-localization-i18n-architecture.md).)_

- **Motor:** app'e ait senkron JSON deposu `lib/src/i18n/i18n.dart` (`AwI18n`) — `runApp`'ten
  ÖNCE belleğe yüklenir, `'key'.tr()` build anında senkron çözülür (widget testleri `runAsync`
  istemez). Üçüncü parti paket yok. Motor tek seam'de (`.tr()` extension) — değiştirilebilir kalır.
- **Anahtar düzeni:** noktalı isim alanı (`home.title`, `task.status.open`, `common.save`,
  `widget.bucket.overdue`, `error.<CODE>`). Eksik `tr` anahtarı `en`'e düşer (kısmi çeviri
  yayınlanabilir). `{name}` yer tutucuları `args`'tan doldurulur.
- **Delegate'ler:** Global{Material,Widgets,Cupertino}Localizations + mevcut FlutterQuill
  delegate'leri (yerleşik widget'ları yerelleştirir); app string'leri `AwI18n`'den gelir.
- **Hardcoded-string bekçisi:** CI'da bir grep taraması, allowlist dışındaki ham
  `Text('literal')`/`labelText:`/`hintText:` metinlerinde başarısız olur (yeni metin doğuştan
  anahtarlı gelir).
- **v1 diller:** `en` (temel) + `tr`. RTL v2.

### 15.6 Widget veri köprüsü, tazelik & gizlilik

_(Eklendi 2026-07-17, feedback round 5 — [ADR-0010](adr/0010-home-screen-widgets-architecture.md),
[WIDGETS.md](WIDGETS.md).)_

- **Köprü:** `home_widget` + App Group (iOS/macOS) / SharedPreferences (Android). Uygulama küçük
  (birkaç KB) bir JSON snapshot yazar; widget yalnız onu render eder, DB'ye dokunmaz.
- **Tazelik:** ön planda `updateWidget` push'ları Apple bütçesinden muaf (40-70 reload/gün);
  gece yarısı bucket döndürme için seyrek self-refresh timeline + Android WorkManager.
- **Yazma yolu:** widget'tan tamamla/ekle yerel-önce `TaskStore`'dan geçer (senkron olur) — ayrı
  yazma yolu YOK.
- **Native derleme zorunlu:** `flutter analyze`/`test` Swift/Kotlin derlemez; her native widget
  görevi gerçek `flutter build ios`/`apk`/`macos` + cihaz turuyla doğrulanır (EventKit dersi).
- **Gizlilik:** "Private widget" açıkken başlık yerine sayı/yer tutucu.

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

**Risk 5 — Widget platform sınırları & tazelik bütçesi.** (a) iPhone'da 4×4 üstü ana ekran
widget'ı yoktur → "4×6/tam ekran" iPhone'da karşılanamaz (iPad/macOS `systemExtraLarge`, Android
4×6). (b) WidgetKit yenileme bütçesi (40-70/gün) arka planda kısıtlıdır. (c) Widget ayrı sandbox
— DB'yi okuyamaz. (d) `flutter analyze`/`test` native kodu derlemez. *Mitigation:* boyut haritası
platform gerçeğine göre dokümante edildi (WIDGETS.md §2); ön plan push'ları bütçeden muaf +
midnight self-refresh; App Group snapshot köprüsü; her native görev build+cihaz turuyla doğrulanır.

**Risk 6 — i18n metin genişlemesi.** Çeviriler tight layout'ları taşırabilir; RTL v1'de yok.
*Mitigation:* sabit genişlikli etiket yok (kırpma + tooltip, DESIGN §4/§9); RTL mimaride
engellenmedi (v2); i18n motoru app'e ait ve üçüncü parti bağımlılığı yok (§15.5) — bakım riski
minimal, tüm aramalar tek seam'den geçer.

**Risk 7 — Obje depolama yapılandırması & CORS (Epic 14).** Attachments ikinci bir veri
deposu (R2/S3) getirir. (a) Web'de doğrudan PUT/GET tarayıcı preflight'ından geçer —
self-hoster bucket CORS'unu kurmazsa web yüklemeleri kırılır. (b) API ile bucket arasında
yetim nesne riski (yarım upload, silinen entity) vardır. (c) Yanlış kimlik bilgisi sessiz
bozulma üretebilir. *Mitigation:* özellik tamamen opsiyonel ve dürüst
(`STORAGE_NOT_CONFIGURED` + UI boş durumları); ATTACHMENTS.md §8 CORS rehberi; 3-adımlı
upload'da complete-time HeadObject doğrulaması; sweep + commit-sonrası silme kuyruğu yetim
bırakmaz; entegrasyon testleri gerçek MinIO'ya karşı koşar (CI dahil). _(Round 8 ek:
klasör silme alt-ağaç kaskadı aynı yetim-bayt garantisine bağlıdır — ADR-0014.)_

**Risk 8 — Arama doğruluğu & ölçek (round 8).** Türkçe fold (ı/İ, ü, ö, ş, ç, ğ) standart
kütüphane davranışlarının dışındadır — SQLite `LIKE` yalnız ASCII case-fold yapar, tokenizer
fold'ları `ı→i`'yi kaçırabilir; yanlış katmanda çözülürse arama "bazı kelimeleri bulamayan"
sessiz bir yalancıya döner. Büyük korpusta (on binlerce satır) naif taramalar da ana thread'i
kilitleyebilir. *Mitigation:* tek fold fonksiyonu (uygulamada tek kaynak, hem sorgu hem
metin; birim testli TR eş-sınıfları), strateji ve ölçüm eşikleri ADR-0013'te; arama
sorguları drift'te async koşar, UI debounce + geç-loading gösterir; MySQL tarafı zaten
accent/case-insensitive collation + FULLTEXT index'lerle uyumludur.

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
- **Epic 10 — Feedback round 4 (UX düzeltmeleri):** OPH-100…OPH-111.
- **Epic 11 — Localization (i18n):** OPH-120…OPH-128 (feedback round 5).
- **Epic 12 — Home-screen widgets:** OPH-130…OPH-136 (feedback round 5).
- **Epic 13 — Alarm omurgası:** OPH-137…OPH-143 (feedback round 6).
- **Epic 14 — Attachments & project files (R2/S3):** OPH-150…OPH-157 (feedback round 7).
- **Epic 15 — Feedback round 8 (akış hızı, arama, pano, global dosyalar):** OPH-160…OPH-170.

## 19. Nihai hedef

Bu proje sadece todo uygulaması değildir. Bu proje:

- Kişisel operasyon merkezi.
- Proje bilgi tabanı.
- Calendar-aware task planner.
- Local-first productivity engine.
- Açık kaynak self-host üretkenlik platformudur.

**Her geliştirme kararı bu vizyona göre verilmelidir.**
