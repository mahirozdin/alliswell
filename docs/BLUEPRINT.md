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
- **Kullanıcının gördüğü iki durum vardır: AÇIK ve ARŞİVLİ (rev. 2026-07-28, feedback
  round 10 #8 — OPH-193).** Proje düzenleme ekranında statü seçtiren dropdown KALKAR:
  yalnız düzenlemede beliriyordu (eklemede yoktu — aynı nesnenin iki farklı formu),
  kullanıcıya ham İngilizce enum basıyordu ve arşivin kaskad sorusunu atlatan ikinci bir
  yol öneriyordu. Bir projenin durumu **arşiv akışıyla** değişir, başka hiçbir yerden.
  `paused`/`completed` sunucu enum'unda KALIR (migration yok, geriye uyum bozulmaz) ama
  arayüz onları ne üretir ne gösterir; arşivli olmayan her proje "açık" davranır.
  Genel kural: **son kullanıcıya iç durum makinesi gösterilmez** — round 1'in "teknik
  kavram yok" kuralının statü enum'larına uygulanması.

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
- **`completed` ANINDA kaybolmaz (rev. 2026-07-28, feedback round 10 #2 — OPH-185):**
  tamamlanan görev **o yerel gün boyunca** kendi grubunda, grubunun sonunda, soluk
  görünümüyle kalır; sonraki yerel gece yarısında plan listelerinden düşer ve
  Tamamlananlar'da (§12.14) yaşamaya devam eder. Gerekçe: tıklamanın anında yok olması
  kullanıcıyı "ne oldu?" diye bıraktığı gibi, tek doğal geri alma yolunu (aynı kutuya
  tekrar dokunmak) ve günün ilerleme hissini de siler.
- **Silme kullanıcının erişebildiği bir eylemdir (rev. 2026-07-28, feedback round 10 #1 —
  OPH-184):** görev silme motoru (yerel iyimser silme + outbox + sunucuda alt ağaç
  tombstone'u + ek kaskadı) v1'den beri hazırdı ama **hiçbir görev satırında düğmesi
  yoktu**. Kural: oluşturulabilen her kayıt, **listesinden** silinebilir (kaydırma) ve
  detayından silinebilir; jest tek yol olamaz (menü/app bar karşılığı zorunlu); yaprak
  silmeler dialog yerine **geri alınabilir** snackbar kullanır. Ayrıntı: DESIGN §19.
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

**Rev. 2026-07-27 (feedback round 9, Epic 16 — bağlayıcı ayrıntı
[ADR-0015](adr/0015-alarm-delivery-and-reminder-profiles.md) + [NOTIFICATIONS.md](NOTIFICATIONS.md) §5):**
round 6'nın "remind_at her zaman kazanır" kuralı **yanlıştı** — kullanıcı hem uyarı hem
son teslim istiyor: _"velevki hatırlatıcı kurdum, tam görev saatinde de alarm gibi çalmalı."_

- **Bir task'ın en çok İKİ alarm anı vardır ve bunlar birbirinden bağımsızdır:** `remind`
  (`remind_at`) ve `due` (acil task'ın `due_at`'i, **hatırlatıcı olsa bile**). Her biri kendi
  reminder satırıdır (`reminders.kind` ∈ `remind`|`due`); iki an aynıysa tek satıra iner
  (tek an için iki kez çalmak hatadır). `effectiveRemindAt` yerini `alarmInstantsFor(task)`
  alır; `reconcileTaskReminder` türler üzerinde döner, her satır kendi revizyonunu tutar.
- **Susturma bir durumdur:** `tasks.alarms_muted_at` (null = canlı) "süresiz erteleme"yi
  senkronlanan, geri alınabilir bir gerçeğe çevirir — anlar boşalır, satırlar iptal edilir,
  **görev AÇIK kalır** (susturmak tamamlamak değildir) ve arayüz alarmın kapalı olduğunu
  söylemeye devam eder.
- **Tekrar zinciri kullanıcının profilidir** (cihaz-yerel: adım listesi, adımlar arası ≥ 1 dk,
  ≤ 20 adım) ve erteleme sonrası turlar aynı profili aynı yükseklikte çalar; tur sayacı
  `reminders.snooze_count`.
- **Tek yükseklik sözleşmesi:** acil bir alarmın her slotu alarm sesi + alarm sınıfı
  teslimat taşır; "sessiz ilk slot" diye bir şey yoktur.

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

### 4.12 Quick Link (hızlı erişim öğesi)

_(Eklendi 2026-07-29, istek turu 11 — Epic 18; karar
[ADR-0018](adr/0018-quick-links-user-scoped-sync-entity.md), yüzeyler §12.15,
görsel kurallar DESIGN §23.)_

Quick Link, kullanıcının kendi seçtiği bir gezinme kısayoludur: proje, görev, not,
klasör, dosya veya dış URL. Notion'ın kenar çubuğu favorileri zihin modeli — ama
**kişiseldir**: aynı workspace'in iki üyesi birbirinin kısayollarını asla görmez.

Alanlar: `id`, `workspace_id`, `user_id`, `kind` (`project|task|note|folder|file|url`),
`target_id` (nullable — yalnız varlık kind'larında), `url` (nullable — yalnız `url`
kind'ında, `http/https`), `title` (≤200), `emoji` (nullable, **tek grafem**;
kolon `varchar(16)` — MySQL karakter sayar, yani ZWJ dizileri de sığar), `color_rgb`
(nullable, proje paleti — üç kardeş tablodaki adla aynı), `sort_order`, `revision`,
`created_at`, `updated_at`, `deleted_at`.
_(Kolon adı ve emoji sınırı 2026-07-29'da OPH-196'da netleşti: planlama turunda `color` ve
"≤16 bayt" yazılmıştı; `projects/tags.color_rgb` ile hizalandı ve bayt→karakter düzeltildi —
bir aile emojisi tek grafem ama 25 bayttır.)_

Kurallar:

- **İlk kullanıcı-kapsamlı senkron varlık (ADR-0018):** workspace'te saklanır,
  pull yalnız sahibine döndürür, push sahiplik doğrular. Revision düzeni aynen
  workspace-monoton kalır.
- Aynı hedef aynı kullanıcıda tekildir; kullanıcı+workspace başına **50 sınırı**
  (`QUICK_LINK_LIMIT`). Dahili hedef `kind + target_id` olarak saklanır — rota
  dizesi veya `alliswell://` ASLA saklanmaz (ADR-0016: URL yalnız gezinir).
- Hedef **hard-delete** edilirse kısayol sunucuda aynı transaction'da kaskadla
  silinir; **arşiv** kısayola dokunmaz (arşiv geri dönüşlüdür; satır soluk çizilir).
- `title` hedeften önerilir ama kullanıcınındır: hedef yeniden adlanınca kısayol
  adı kendiliğinden değişmez; arayüz farkı gösterir ve tek dokunuşla eşitletir.
- Emoji ve renk kişiselleştirmedir, anlam değildir (DESIGN G5): tür ikonu her
  zaman erişilebilir kalır, renk yalnız vurgudur ve metne girmez.

### 4.13 AI Connection (yapay zeka bağlantısı)

_(Eklendi 2026-07-29, istek turu 11 — Epic 19; bağlayıcı plan [AI.md](AI.md), karar
[ADR-0019](adr/0019-ai-provider-architecture.md), yüzeyler §12.16 + DESIGN §24.)_

AI Connection, kullanıcının kendi yapay zeka erişimini AllisWell'e bağlamasıdır.
**İki hat vardır (ADR-0019):** Hat A — AllisWell'in uzak MCP sunucusunu kullanıcının
kendi Claude/ChatGPT hesabına bağlayıcı olarak eklemesi (aboneliğiyle çalışır; sunucuda
anahtar durmaz); Hat B — uygulama içi AI için **BYOK** (kendi API anahtarı:
Anthropic/OpenAI/Gemini/OpenRouter; self-host için Ollama base-URL). Tüketici
abonelik-OAuth'u üç sağlayıcıda da üçüncü partilere kapalıdır (kanıt AI.md §1);
`auth_mode='oauth_subscription'` ileride açılırsa diye **rezervedir**.

Tablolar: `ai_connections` (`user_id`, `workspace_id`, `provider`, `auth_mode
api_key|instance_env|oauth_subscription`, `encrypted_key` — ADR-0006 AES-256-GCM kalıbı,
`AI_TOKEN_KEY`; serializer'dan asla çıkmaz, arayüz `…son4` görür —, `base_url`,
`default_chat_model`, `default_fast_model`, `status`, `last_used_at`);
`ai_usage_events` (istek başına tür/model/token/süre — **içerik asla**);
`ai_action_log` (AI önerisi + kullanıcı onayı denetim izi).

Kurallar:

- **AI önerir, kanıtlanmış yazma yolu commit'ler:** gömülü AI'nın v1'de yazma aracı
  YOKTUR; onaylanan öneri `TaskStore` outbox'ından geçer (ikinci yazma yolu yok —
  ADR-0016 ilkesi). MCP araçları domain katmanını REST'le aynı Ajv+authz+revision
  yolundan çağırır. **Silme AI'ya kalıcı olarak kapalıdır.**
- Sohbet geçmişi cihaz-yereldir (drift `ai_messages`); senkron `conversation`
  varlığı bilinçli olarak parktadır (gizlilik duruşu değişikliği).
- `AI_ENABLED=false` instance'ta özelliği dürüstçe kapatır (yüzeyler çekilir);
  hiç bağlantı yokken `AI_NOT_CONFIGURED` boş durumları (`STORAGE_NOT_CONFIGURED`
  kalıbı). Instance-env anahtarında kullanıcı-başı günlük token tavanı.
- Onamsız hiçbir AI yüzeyi açılmaz; onam ekranı sağlayıcının saklama/eğitim duruşunu
  tek dürüst cümleyle söyler (Gemini ücretsiz katmanın veriyle eğittiği açık uyarıdır).

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

**Rev. 2026-07-27 (feedback round 9 — ilk gerçek alarm turu; bağlayıcı:
[NOTIFICATIONS.md](NOTIFICATIONS.md) §2/§2b/§5, [ADR-0015](adr/0015-alarm-delivery-and-reminder-profiles.md)):**

- **iOS'ta birincil hat artık AlarmKit'tir** (iOS 26+). Sebebi teoriden değil sahadan:
  `timeSensitive` bildirim sesi hâlâ bir *bildirim* sesidir — sessiz anahtarı ve zil ses
  seviyesi onu susturur. **Round 9'da anlaşıldı ki AlarmKit hattı hiç çalışmamış:**
  `AlarmKitBridge.swift` hiçbir Xcode hedefinde değildi (OPH-182 bunu bağlar). AlarmKit
  bize iPhone'un kendi alarm davranışını verir: tam ekran uyarı, kilit ekranı/Dynamic
  Island, native ertele/durdur, sessiz + Odak modunu delen ses, **entitlement gerekmez**
  (yalnız kullanıcı izni) ve **Apple Watch'a da ulaşır**. iOS < 26 ve izin verilmemiş
  durumlar bildirim zincirine düşer — düşüş dürüstçe söylenir.
- **Erteleme seçenekleri ne yapacağını söyler** ("5 dk sonra tekrar çalar"), erteleme
  görev satırında görünür ("Ertelendi — 22:52") ve **süresiz erteleme** (§4.9) bir seçenektir.
- **Sesler kullanıcının:** acil alarm sesi ve hatırlatıcı sesi ayrı seçilir; kullanıcı kendi
  zil sesini yükleyebilir (R2 → cihazda iOS `Library/Sounds` / Android ses-başına-kanal;
  ≤30 sn + caf/wav/aiff kuralı yükleme anında dürüstçe söylenir). Uygulama içi ring
  ekranı da ses çalar (önplan `.playback` oturumu).
- **Ayarlanabilirlik ve dürüstlük birlikte:** hatırlatıcı sayısı/sıklığı Ayarlar →
  "Hatırlatıcı Sistemi Ayarları"nda; iOS'un 64 bekleyen bildirim sınırının seçilen profile
  maliyeti aynı ekranda yazılır (sessiz kırpma yok). Her alarm olayı yerel **alarm
  günlüğüne** yazılır — bir daha "hangi ses çaldı?" sorusu hafızayla tartışılmaz.

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
- **Bugün tamamlananlar listede kalır (rev. 2026-07-28, round 10 #2 — OPH-185):** tamamlanan
  görev anında kaybolmaz; **kendi grubunda, grubunun en sonunda**, sakin görünümüyle (dolu
  onay dairesi + üstü çizili + soluk ton) gün bitene kadar durur. Sonraki yerel gece
  yarısında düşer — sınır **canlıdır** (gece yarısına kurulu zamanlayıcı + uygulama öne
  gelince yeniden hesap), yani ekran açık kalsa bile liste kendini yeniler. Ay ızgarasının
  noktaları tamamlananları saymaz (bitmiş gün "dolu gün" değildir). Aynı kural ana ekran
  widget'ında da geçerlidir — widget ile uygulama kullanıcının önünde çelişemez.
  Görsel kurallar: DESIGN §20.
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
Notes, Checklist, **Attachments (Epic 14)**, Activity, **Sil (rev. round 10)**.

_(Rev. 2026-07-28, feedback round 10 #1/#6/#7 — OPH-184/191/192:)_ Üç kural:

1. **Silme app bar'dadır.** Not editörü ve proje detayı zaten böyle; görev detayı bu
   eylemden yoksundu, yani uygulamanın en çok kullanılan nesnesi tek silinemeyen nesneydi.
2. **Tarih alanları saat de sorar.** Detaydaki tarih satırları yalnız takvim açıp saati
   varsayılana çekiyordu: 14:30'luk bir görevin gününü değiştirmek saati sessizce 23:59
   yapıyordu. Oluşturma sheet'i ile detay **aynı** giriş yolunu kullanır (DESIGN §17 D5) —
   düzenleme, kullanıcının dokunmadığı bir parçayı değiştiremez.
3. **"Planlanan tarih" sabit bir alan değildir; koşullu bir açıklamadır.** Alan listesinde
   hiç yer almamıştı — OPH-076 takvim sürüklemesi için eklemişti ve kullanıcı için
   anlamsız bir üçüncü tarih olarak duruyordu. Bundan sonra **yalnız `scheduled_start_at`
   doluyken** görünür ve ne olduğunu söyler ("Takvimde taşındı — {tarih}"), yanında
   "Sıfırla" ile temizlenir. Tamamen silinemez, çünkü §7.1 takvim bloğunu **önce**
   `scheduled_*`'tan türetir ve kullanıcı etkinliği takvimde sürüklediğinde sunucu
   `due_at`'i değil `scheduled_*`'ı yazar (bloğu taşımak "o saatte yapacağım" demektir,
   "son tarih değişti" değil) — görünmeyen bir alan, takvim etkinliğini sessizce yerine
   çivilerdi.

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

_(Rev. 2026-07-28, feedback round 10 #4 — OPH-187/188/189. İlk gerçek "widget'ı kullandım"
turu; dördü de aynı ekranda çıktı:)_

- **E) Başlıktaki sayı: "bugün üzerimde kaç iş var".** Tarih başlığının sağ hizasında
  **geciken + bugün** toplamı yazar (ertelenmiş/susturulmuş görevler dahil — hâlâ açık iştir;
  tarihsiz görevler **hariç** — onlar her günün işi olduğu için her günü şişirirdi). Sıfırsa
  rozet gizlenir. Sayı Dart snapshot'ında hesaplanır (saf + birim testli), native tarafta
  değil; etiketi de diğer bütün widget kelimeleri gibi çevrilmiş olarak gelir.
- **F) Tarih başlığı iki platformda AYNI çizilir.** Gün sayısı ile gün adı/ay bloğu birbirine
  göre **optik olarak ortalanır**; taban çizgisine hizalamak 34 punto sayının yanında ay
  satırını sarkıtır ve dizgi hatası gibi okunur. iOS ile Android bir sürüm boyunca bu başlığı
  farklı çizdi — DESIGN §8 W1'in "token paritesi" kuralı **yerleşime de** uygulanır.
- **G) Widget'tan tamamlama artık kapsamdadır ve yolu round 9'da açıldı.** OPH-182, App
  Intent'leri iki hedefte derleyen ve **uygulama kapalıyken basılan düğmeleri App Group
  kuyruğunda bekleten** altyapıyı kurdu; widget tamamlaması aynı hattı kullanır — sıfırdan
  mekanizma yazılmaz. Android tarafında önce eksik veri kapatılır: widget satır kaydı bugün
  **görev id'sini taşımıyor**, dolayısıyla ne tamamlama ne satır bağlantısı mümkün.
- **H) Widget'a dokunmak bir yere gitmelidir.** `alliswell://` şeması bugün iOS
  `Info.plist`'te ve Android manifest'inde **kayıtlı değil** ve uygulamada hiçbir yönlendirme
  yok → dokunuş "No route for alliswell://open/" hatasıyla karşılanıyor, hata ekranının
  "Home" düğmesi de var olmayan `/` rotasına gidiyor. Şema kaydedilir, saf bir çözücü
  (`alliswell://open` → Home, `alliswell://task/{id}` → görev detayı,
  `alliswell://file/{id}` → Dosyalar) yönlendirmeyi yapar, `/` gerçek bir rotaya bağlanır ve
  yönlendiricinin hata ekranı kendi yazdığımız, çalışan çıkışı olan ekran olur. Sözleşme:
  **[ADR-0016](adr/0016-in-app-url-routing-and-widget-actions.md)** — dışarıdan gelen bağlantı
  yalnız GEZİNİR, asla veri yazmaz; yazan tek yol imzalı App Intent kuyruğudur.

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

### 12.13 Yenileme, tarih biçimi ve hatırlatıcı ayarları (feedback round 9 — OPH-171…181)

_(Eklendi 2026-07-27; bağlayıcı tasarım [DESIGN.md](DESIGN.md) §15–§18 ve §11 A3/A5/A6.)_

- **Aşağı çekip yenileme beş bölümde birden vardır** (Home — Liste ve Pano —, Fikirler,
  Projeler, Notlar, Dosyalar). Yenileme = "şimdi senkronize et" + o ekranın dış gerçeği
  (Home: takvim etkinlikleri + alarm izni; Dosyalar: depo durumu). Gösterge sabit filtre
  satırının ALTINDA doğar, en az ~450 ms görünür (replika milisaniyede döner; çakıp kaybolan
  spinner "olmadı" demektir), listeyi yerinden oynatmaz, aramayı/filtreyi bozmaz. Fare
  tekerleği overscroll yapmadığı için geniş yerleşimde app bar'a bir "Yenile" eylemi eklenir —
  aynı yetenek, her platformun kendi deyimiyle.
- **Telefonda Home'da SABİT kalan tek şey app bar'dır** (bölüm başlığı + ayarlar). Uyarı
  bandı, Liste|Pano anahtarı, hızlı ekleme, arama, takvim ve "takvimi gizle" — hepsi tek
  kaydırmanın parçasıdır (OPH-103 felsefesinin sonuna kadar götürülmesi). Tek istisna:
  Pano'da yatay pager kaydırılamayacağı için Liste|Pano anahtarı sabit kalır, yoksa Liste'ye
  dönüş yolu kaybolur.
- **Tarih/saat gösterimi tek biçimlendiriciden gelir ve kullanıcı seçer.** Varsayılan
  "sistem" (uygulama diline uyar; tr → **31.12.2026 23:59**), yanında en sık kullanılan
  presetler. Ayar ekranı **biçim dizgesi değil sonucu** gösterir (round 1 kuralı: son
  kullanıcıya teknik kavram yok) ve seçim ana ekran widget'ına da taşınır — widget ile
  uygulama kullanıcının önünde çelişemez.
- **"Hatırlatıcı Sistemi Ayarları" tek adrestir:** hazır profiller (Sakin/Standart/Israrcı),
  adım adım zincir editörü (dakika stepper'ı, araya adım ekleme, canlı zaman çizelgesi),
  erteleme presetlerinin sırası (burada sürükle-bırak anlamlıdır — sıralı zincirde değil),
  alarm/hatırlatıcı sesi + özel zil sesi yükleme (önizlemeli), süresiz erteleme davranışı ve
  alarm günlüğü. Sınırlar sessizce uygulanmaz, ekranda söylenir (adımlar arası ≥ 1 dk;
  iOS'un 64 bekleyen bildirim bütçesinin seçilen profile maliyeti).

### 12.14 Silme, tamamlananlar ve erişilebilirlik (feedback round 10 — OPH-184…195)

_(Eklendi 2026-07-28; bağlayıcı tasarım [DESIGN.md](DESIGN.md) §19–§22.)_

- **Silme bir liste eylemidir.** Oluşturulabilen her kayıt satırından silinebilir: satır
  sağdan sola çekilince **yarı açılır** ve kırmızı "Sil" düğmesini gösterir — tek bir
  savurmayla hiçbir şey yok olmaz. Aynı eylem her zaman görünür bir karşılıkla da vardır
  (satır menüsü / detay app bar'ı): fare kaydırmaz, anahtar-kontrol kullanıcısı hiç
  kaydırmaz. Yaprak silmeler (görev, not) onay dialog'u yerine **"Geri al" snackbar'ı**
  kullanır ve gerçek silme snackbar kapanana kadar **hiç yazılmaz** — uygulama arada
  ölürse kayıp olmaz. Kaskadlı silmeler (proje, klasör, etiket) onayını korur.
- **Tamamlananların bir adresi vardır.** Gün içinde tamamlanan iş Home'da kalır (§12.2);
  geçmişin tamamı **Ayarlar → Tamamlananlar**'da yaşar: yeniden eskiye, gün başlıklı,
  kaydırdıkça yüklenen bir zaman çizelgesi. Sıralama anahtarı **görevin kendi tarihi
  varsa o, yoksa tamamlanma zamanı**. Tamamen yerel replikadan okunur — arşiv, ağ
  gerektiriyorsa güvenilmez. Kapsamı verinin üstünde yazılıdır (v1: yalnız `completed`).
- **Erişilebilirlik = ulaşılabilirlik.** Şemada duran bir alan, store'da duran bir metot
  veya sunucuda duran bir uç, bir insan ona dokunamıyorsa **özellik değildir**. Round 10'un
  bulgularının çoğu eksik kod değil, yüzeye çıkarılmamış yetenekti (görev silme, alt
  görevler, elle sıralama, görev rengi, widget etkileşimi). Bundan sonra her task **hangi
  ekranda, telefonda ve masaüstünde nereye dokunulacağını** yazar; cevabı "henüz hiçbir
  yerde" ise bu, park kuyruğuna açıkça yazılır. CRUD bir matris olarak denetlenir —
  eksilen hücre her zaman **silme**dir, çünkü hiçbir demo onu göstermez (DESIGN §22).

### 12.15 Hızlı Erişim (istek turu 11 — Epic 18, OPH-196…203)

_(Eklendi 2026-07-29. Varlık: §4.12; karar: [ADR-0018](adr/0018-quick-links-user-scoped-sync-entity.md);
görsel/davranış kuralları: DESIGN §23. Kullanıcının tarifi: "Notion'daki sol menü gibi —
istediğini ekleyeceksin; mobilde AssistiveTouch gibi sürüklenen bir düğme, tıklayınca
aynı liste.")_

Tek liste, üç yüzey — hepsi aynı `QuickAccessStore`'u okur:

- **Geniş ekran (≥1160, extended rail):** navigasyon hedeflerinin altında "Hızlı erişim"
  bölümü — başlık + "+" (dış link ekle) + katlama; satırlar: emoji (yoksa tür ikonu) +
  ad + renk noktası + dış-link glifi. Satır menüsü (hover VE klavye odağı): yeniden
  adlandır · emoji · renk · kaldır. Fare ile sürükleyerek sıralama.
- **Dar rail (800–1160):** hedeflerin altında `bolt` ikonu → çıpalı popover, aynı liste.
  Kısayollar bir navigasyon destination'ı DEĞİLDİR — seçili sekme state'i bozulmaz.
- **Telefon:** **yüzen düğme** (bubble) — uygulama içi overlay, sürüklenir, en yakın
  dikey kenara yapışır, konumu cihaz-yerel kalıcıdır, boşta kenara yarı gömülür.
  Dokun → bottom sheet paneli: aynı liste + düzenleme modu (sıralama kulpu) + "+".
  Ayarlar'da açma/kapama anahtarı (fabrika: açık); kapalıyken Home app bar'ına
  `bolt` ikonu girer — özellik jeste mahkûm edilmez (DESIGN §19 D2'nin genel ilkesi).
  Düğme modal rota (dialog/sheet) açıkken ve auth/onboarding'de görünmez; liste
  boşken de görünmez (ilk öğe menülerden eklenir, tek seferlik tooltip tanıtır).

Davranış:

- **Ekleme yolları:** proje/not/görev/klasör/dosya menülerinde "Hızlı erişime ekle ⇄
  kaldır" toggle'ı; panel ve rail'de "+" ile dış link dialog'u (http/https doğrulama,
  boş ad → host adı). OG başlık çekme v1'de yok (unfurl proxy parking-lot'ta).
- **Gezinme:** varlık kısayolları go_router rotalarına gider (project → detay,
  task → görev detayı, note → editör, folder → Dosyalar o klasörde, file → dosya
  eylem sayfası); `url` kısayolu **dış tarayıcıda** açılır (uygulama içi webview yok).
- **Kırık/arşivli hedef:** silinmiş hedefin satırı soluk + "kaynak silinmiş" alt
  metni ve kaldırma teklifi (sunucu kaskadı zaten temizler — bu yalnız yarış
  penceresi); arşivli hedef soluk ama tıklanır.
- **Kişiselleştirme:** emoji (son kullanılanlar + kürasyonlu ızgara + serbest tek
  grafem alanı — paket yok), renk (proje paletinin aynı swatch bileşeni + "yok"),
  ad (200 karakter; boşaltınca hedef adına döner).
- **Sınır:** kullanıcı+workspace başına 50; aşımda dürüst mesaj.

### 12.16 Yapay zeka yüzeyleri (istek turu 11 — Epic 19, OPH-204…216)

_(Eklendi 2026-07-29. Mimari: [AI.md](AI.md) + [ADR-0019](adr/0019-ai-provider-architecture.md);
görsel/davranış kuralları: DESIGN §24. Kullanıcının tarifi: "solda ikinci FAB'a basılı
tutup konuşayım, 'Ahmet projesine şu işleri yarın hatırlat' deyince todo kendiliğinden
eklensin; bubble açılınca elimi kaldırabileyim, kapanmasın; paylaştığım metin bubble'da
açılsın.")_

- **AI FAB (sol alt):** mevcut oluşturma FAB'ı sağ altta YERİNDE kalır; sol alttaki AI
  FAB'ına **basılı tut → konuş** (bubble açılır, canlı transkript), **parmağı kaldır →
  kayıt kilitli sürer, bubble açık kalır**; sola kaydır → iptal. Tek dokunuş bubble'ı
  metin+mikrofon modunda açar (jest asla tek yol değil). Geniş ekranda giriş rail'in
  altındadır; masaüstünde tıkla-konuş + klavye kısayolu.
- **Bubble:** opak içerik yüzeyi (cam yalnız krom); durumlar: dinliyor (dalga formu),
  düşünüyor, **akış** (token'lar canlı, durdur düğmesi), hata, çevrimdışı. Cevaplar
  bubble'da **stream** edilir. Her mesajda "bağlam çipi" neyin gönderildiğini açar.
  Çevrimdışı/AI'sız: transkript tek dokunuşla **Inbox yakalaması** olur — sesle
  yakalama sıfır AI ile bile çalışır (§12.6 semantiği).
- **Sesle görev:** cihaz-üstü STT (v1) → hızlı-sınıf modelde niyet+çıkarım tek
  yolculukta → **onay kartı** (oluşturma sheet'inin alan satırları; çok görevli söz →
  çok satırlı kart; proje eşleme ADR-0013 fold'uyla BİZDE; "yarın" çıplaksa
  yarın@varsayılan görev saati). Onaysız commit yok (v1 değişmezi); kabul edilen görev
  `TaskStore` outbox'ından geçer, çevrimdışı da çalışır.
- **Paylaşım hedefi:** herhangi bir uygulamadan metin/URL paylaş → bubble "paylaşılan
  içerik" bloğuyla açılır → çipler: **Görev yap · Not al · Özetle · Soru sor**.
  iOS Share Extension yalnız App Group'a yazar (ağ/AI işi yapmaz); soğuk başlangıç
  auth restore'u bekler. Oturumsuz/AI'sız: "Inbox'a kaydet" her zaman vardır.
- **Sohbet (verinle konuş):** bağlam cihazda paketlenir (T0 proje adları/sayımlar,
  T1 bugün+geciken dilimleri, T2 fold-arama alıntıları; ~4–8K token bütçe, görünür
  kırpma). Ek baytları, presigned URL'ler, başka üyenin verisi asla gönderilmez.
- **Ayarlar → Yapay zeka:** sağlayıcı bağla (BYOK, `…son4`), model seçimi, kullanım
  sayacı, sağlayıcı-başına onam; **MCP bölümü**: "AllisWell'i Claude'a/ChatGPT'ye
  ekle" — instance'ın `/mcp` URL'i ve kurulum yönergesi.
- **Quick-add binicisi:** uzun metni yapıştır → "✨ ayrıştır" → aynı çıkarım + aynı
  onay kartı.

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
- **Phase 10 — Feedback round 9: yenileme, tarih biçimi, alarm sistemi (v0.5.0):** beş bölümde
  aşağı çekip yenileme; telefonda Home'un tek kaydırma katmanı (yalnız app bar sabit); detaylı
  ekleme sheet'inde hiza + "yarın" varsayılanı; tek kaynaktan tarih/saat biçimi + kullanıcı
  ayarı; **alarm belkemiği v2** — görev saati kendi alarmı (`reminders.kind`), tek yükseklik
  sözleşmesi + alarm günlüğü, erteleme netliği, **süresiz erteleme** (`tasks.alarms_muted_at`),
  kullanıcı hatırlatıcı profili + "Hatırlatıcı Sistemi Ayarları", zil sesi kütüphanesi + özel
  ses yükleme, uygulama içi alarm sesi, **iOS 26 AlarmKit'in gerçekten devreye alınması** ve
  Apple Watch davranışının doğrulanması — Epic 16
  ([ADR-0015](adr/0015-alarm-delivery-and-reminder-profiles.md), NOTIFICATIONS §2b/§5/§6,
  DESIGN §15–§18).
- **Phase 11 — Feedback round 10: silme, tamamlananlar, widget, geçişler (v0.6.0):** ilk
  "günlük kullanım" turunun ürettiği liste. **Kaydırarak silme + her listede ve her detayda
  silme** (motor v1'den beri hazırdı, düğmesi hiç konmamıştı) geri alınabilir snackbar'la;
  **tamamlanan görev gün sonuna kadar listede kalır** ve sakin görünüme geçer; **Ayarlar →
  Tamamlananlar** sonsuz kaydırmalı zaman çizelgesi; widget'ta **tarih başlığı hizası + günün
  açık görev sayısı** ve **widget'tan tamamlama** (round 9'un App Intent + App Group
  altyapısı üstünde); **`alliswell://` derin bağlantı yönlendirmesi** + yönlendiricinin
  gerçek hata çıkışı; **ses önizlemesinin durdurulabilmesi**; **düzenlerken de saat
  seçimi** (tek tarih-giriş yolu); "planlanan tarih" koşullu açıklamaya dönüşür; proje
  durumu dropdown'ı kalkar; **sayfa geçişlerindeki hayalet** (yarı saydam ekran zemininin
  altındaki rotayı göstermesi) tasarım sistemi kuralı değiştirilerek çözülür; ve
  **kapsamlı CRUD/UX matrisi taraması** — Epic 17
  ([ADR-0016](adr/0016-in-app-url-routing-and-widget-actions.md), DESIGN §19–§22).
- **Phase 12 — İstek turu 11 #1: Hızlı Erişim (v0.7.0):** Notion tarzı kişisel kısayol
  listesi — proje/görev/not/klasör/dosya/dış link; emoji + renk + elle sıra; geniş
  ekranda rail bölümü, dar rail'de popover, telefonda **sürüklenen yüzen düğme** +
  panel; **ilk kullanıcı-kapsamlı senkron varlık** (`quick_link`) ve hedef silmede
  sunucu kaskadı — Epic 18
  ([ADR-0018](adr/0018-quick-links-user-scoped-sync-entity.md), §4.12/§12.15, DESIGN §23).
- **Phase 13 — İstek turu 11 #2: Yapay zeka (v0.8.0):** iki hat — **AllisWell uzak MCP
  bağlayıcısı** ("Claude'una/ChatGPT'ne ekle"; abonelik-OAuth üç sağlayıcıda da üçüncü
  partiye kapalı, kanıt AI.md §1) + **uygulama içi BYOK AI** (Anthropic/OpenAI/Gemini/
  OpenRouter/Ollama, fetch adaptörleri, SDK yok); SSE akışlı bubble, sol FAB **basılı
  tut-konuş** (kaldır-kilitle), cihaz-üstü STT, tek şemalı görev çıkarımı + zorunlu onay
  kartı → `TaskStore` outbox commit'i, paylaşım hedefi (Share Extension App Group
  el-değiştirmesi), enjeksiyon savunması (v1'de modele araç yok; silme kalıcı kapalı),
  onam + kullanım sayacı — Epic 19
  ([AI.md](AI.md), [ADR-0019](adr/0019-ai-provider-architecture.md), §4.13/§12.16,
  DESIGN §24).

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

**Risk 4b — Bildirim hattı bir alarm değildir (round 9'da gerçekleşti).** iOS'ta
`timeSensitive` özel ses **zil seviyesinde** çalar, sessiz anahtarı onu tamamen susturur ve
`UNNotificationSound` adı çözülemezse sistem sessizce varsayılan sese düşer — yani "alarm"
sözü verilip ding çıkması ya da hiç ses çıkmaması mümkündür (round 9'da üçü de yaşandı).
Üstüne, hangi hattın hangi sesle çaldığına dair **hiçbir kaydımız yoktu**. *Mitigation:*
iOS 26+ için birincil hat **AlarmKit** (entitlement gerekmez, sessiz+Odak'ı deler, native tam
ekran; OPH-182) ve bu hattın gerçekten derlendiğini kanıtlayan cihaz DoD'si; tek yükseklik
sözleşmesi (her slot alarm sınıfı); ses çözümleme bekçisi + Ayarlar'da dürüst durum;
yerel **alarm günlüğü** (OPH-176) — teşhis bir daha hafızayla yapılmaz; iOS'un 64 bekleyen
bildirim bütçesi kullanıcı profiline karşı ekranda hesaplanır (sessiz kırpma yok).
**Kalıcı ders:** native bir dosyanın repoda olması onun derlendiği anlamına gelmez —
`flutter analyze`/`test` Swift/Kotlin derlemez; hedef üyeliği olmayan bir köprü sessizce
"desteklenmiyor" döner (AlarmKit round 6'dan beri yazılıydı, round 9'a kadar hiç çalışmadı).

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

**Risk 9 — AI: sağlayıcı politikası, enjeksiyon, akış ve anahtar emaneti (round 11).**
(a) Sağlayıcı programları oynaktır: abonelik-OAuth 2026'da üç kez politika değiştirdi ve
bugün üçünde de kapalı — üstüne kurulan her UX bir gecede kırılabilir. (b) Görev/not
başlıkları modele giren **güvenilmez girdidir** (OWASP LLM01) — araçlı bir modele "hepsini
sil" yazan bir not eylem üretebilir. (c) Prod'daki Apache reverse proxy SSE'yi
tamponlayabilir — tamponlanan akış kullanıcıya "AI takıldı" gibi görünür. (d) BYOK
anahtarları sunucuda durur — sızması kullanıcının faturasıdır; paylaşılan self-host'ta tek
kullanıcı instance anahtarını yakabilir. *Mitigation:* (a) iki hatlı mimari + rezerve
`auth_mode` + üç aylık politika kontrolü (ADR-0019); README iddiaları gerçekle denetlenir
(OPH-216). (b) v1'de modele **hiç yazma aracı verilmez**; öneri→Ajv→**onay kartı**→
`TaskStore`; silme AI'ya kalıcı kapalı; provenance çitleri + CI'da düşman korpusu
(OPH-215). (c) deploy kontrol listesi + **prod'a karşı curl artımlı-akış kanıtı** DoD'de;
Socket.IO tek-dikiş yedek transport (web'de birincil). (d) ADR-0006 şifreleme kalıbı +
`AI_TOKEN_KEY`, anahtar serializer'dan çıkmaz, kullanıcı-başı hız sınırı + instance-env'de
günlük token tavanı + `ai_usage_events` isnat izi.

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
- **Epic 16 — Feedback round 9 (yenileme, tarih biçimi, alarm sistemi):** OPH-171…OPH-183.
- **Epic 17 — Feedback round 10 (silme, tamamlananlar, widget, geçişler):** OPH-184…OPH-195.
- **Epic 18 — İstek turu 11 #1 (Hızlı Erişim):** OPH-196…OPH-203.
- **Epic 19 — İstek turu 11 #2 (Yapay zeka — MCP + BYOK):** OPH-204…OPH-216.

## 19. Nihai hedef

Bu proje sadece todo uygulaması değildir. Bu proje:

- Kişisel operasyon merkezi.
- Proje bilgi tabanı.
- Calendar-aware task planner.
- Local-first productivity engine.
- Açık kaynak self-host üretkenlik platformudur.

**Her geliştirme kararı bu vizyona göre verilmelidir.**
