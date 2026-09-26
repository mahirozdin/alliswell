# TASKS — AllisWell backlog

> **How to use:** this file holds **open work only**, in order — the first task below without ⏸️
> is the **next task**. Don't read the file whole to find it: `npm run next` prints it with its
> epic's intro (`-- --batch 4` for a loop turn, `-- --summary` for the counts). The pointer also
> lives in [STATE.md](STATE.md), and `check:docs` keeps the two equal. Rules and workflow:
> [../AGENTS.md](../AGENTS.md). Spec: [BLUEPRINT.md](BLUEPRINT.md). Traps and decisions by area:
> [LESSONS.md](LESSONS.md) (grep the area, don't read it whole).
>
> **Format** (read by `scripts/tasks/tasks.mjs`): `## Epic NN — …` sections, `### OPH-NNN — …`
> tasks, `- [ ]` boxes. **⏸️ in a task heading** = it waits on the owner (an account, a console, a
> store review): it is never picked, STATE must name it, and removing the ⏸️ puts it back in the
> queue. Order is dependency — a task that needs a parked one is parked too.
>
> **A closed task is deleted, not ticked** — its record is git history and the CHANGELOG, and
> `npm run check:docs` fails on a closed task left behind. Before deleting it: a trap that can
> silently recur → LESSONS.md; an owner decision → STATE.md. Every task up to Epic 33
> (OPH-001…OPH-350), with its full notes, is in `git show 85b6c1b:docs/TASKS.md`.

---

## Sahibin adımını bekleyen işler — ajan için kod işi yok

Kod tarafları kapalı; kalan kutular sahibin hesap/panel adımları (STATE → "Kullanıcıdan bekleyen").

### OPH-142 — Critical-alerts entitlement application (user action; code is ready) ⏸️ SAHİP

_(2026-07-24'te başvuru "gönderiliyor" diye kayıtlı; sonucu kayıtlı değil — gönderildiyse ilk
kutuyu işaretle.)_

- [ ] **Mahir (Account Holder):** submit
      <https://developer.apple.com/contact/request/notifications-critical-alerts-entitlement/> —
      justification draft in NOTIFICATIONS.md §2. Expect refusal for a task manager; AlarmKit
      (OPH-141) is the primary path — this is belt-and-braces for muted phones on iOS < 26.
- [ ] If granted: add `com.apple.developer.usernotifications.critical-alerts` = true to
      `Runner.entitlements`, regenerate provisioning profiles. **No code change** — OPH-139
      already gates on the runtime grant, and the second "Critical Alerts" permission prompt +
      Settings toggle appear automatically.

### OPH-273 — Canlıdaki tarayıcı bir yıl boyunca eski uygulamayı çalıştırıyordu (ACİL, sıra dışı) ⏸️ SAHİP

_Origin tarafı 2026-08-17'de düzeldi (`apps/landing/public/.htaccess` ve `docker/web-nginx.conf`:
`/app/` altı `no-cache, must-revalidate`). 2026-09-23 ölçümü: eski immutable kopya gitmiş, `.js`
hâlâ `max-age=14400` — kalan yalnız aşağıdaki panel ayarı._

- [ ] **AÇIK — Cloudflare kenarı, ve düzeltmesi panelde (agent'ın erişimi yok).** Ölçüm:
      | Dosya | Cache-Control | cf-cache-status |
      | --- | --- | --- |
      | `version.json` | `no-cache, must-revalidate` | DYNAMIC (origin'e geçiyor) |
      | `main.dart.js` | **`max-age=14400, must-revalidate`** | EXPIRED (içerik YENİ) |
      | `flutter_bootstrap.js` | **`public, max-age=31536000, immutable`** | **HIT, age 445** |
      İki ayrı Cloudflare davranışı: (1) `.js` CF'nin varsayılan önbelleklenen tipleri
      arasında olduğu için tarayıcı TTL'ini kendi **4 saatine** yeniden yazıyor — origin ne
      derse desin; (2) `flutter_bootstrap.js` kenarda **eski, yıllık-immutable** kopyasıyla
      duruyor (`last-modified` dünkü deploy). **Sahibin yapması gerekenler:** `/app/*` için
      cache **purge**, ve kalıcı çözüm olarak Browser Cache TTL → *Respect Existing Headers*
      ya da `alliswell.space/app/*` için bypass eden bir Cache Rule.
      _Not: purge yapılmasa bile durum yıldan 4 saate indi ve servis edilen kod yeni._

### OPH-274 — Notlar %100 markdown: rich text editör kaldırıldı, motor `markdown_forge` paketi oldu (ADR-0033, v1.7.0) ⏸️ SAHİP

_Kod 2026-08-18'de kapandı (v1.7.0); motor bugün `apps/app/packages/markdown_forge` yolundan geliyor._

- [ ] **AÇIK — sahibin iki adımı:** `bubiapps` GitHub org'u + `markdown_forge` public repo'su
      (paket dizini kopyalanır) ve `dart pub publish` (Google OAuth ister — ajan yapamaz).
      Yayın sonrası `apps/app/pubspec.yaml`'daki `path:` bağımlılığı pub.dev sürümüne döner.

---

## Backlog / v2 parking lot

Yapılmamış ve bir işe bağlanmamış her şey. Bir madde bir epic'e alınınca buradan silinir.

- Workspace sharing & roles UI (multi-user workspaces are schema-ready).
- Project documents (block editor) — Phase 5 detail tasks to be expanded when reached.
- Timeline view; smart lists/filters DSL; global single-screen search (per-screen search
  shipped in Epic 15; kanban shipped in Epic 15 — OPH-168).
- Search v2: FTS5 external-content upgrade (bm25 ranking — ADR-0013 upgrade path),
  server-side fold columns for a first-class API `?q=` (the server's FULLTEXT still folds `I`
  but not `ı` — OPH-167), file-name search in Dosyalar (OPH-170).
- Task description v2: OG link previews (needs a server-side unfurl proxy — OPH-164, OPH-201),
  rich formatting.
- Tag management v2: merge tags, usage counts, tag colors in board/list filters.
- Files v2: desktop drag-to-move into folders (target-picker sheet is v1), bulk move/delete.
- Attachments v2: multipart >5 GB uploads, thumbnails/transcodes, storage quota in the plain
  build (today only the per-file `maxUploadBytes` ceiling), local binary cache for offline
  viewing, inline video playback, public share links (v1 shipped in Epic 14 — ATTACHMENTS.md §11).
- **Round 9 park kuyruğu:** sunucu tarafı zil sesi dönüştürme (ffmpeg → ≤30 sn caf, mp3
  yüklemelerini iOS bildiriminde kullanılabilir kılar — OPH-181 bilinçli olarak
  doğrulama+dürüst mesajla yetiniyor); **watchOS companion hedefi** (özel long-look +
  `WKInterfaceDevice` haptikleri + complication — kararı OPH-183 veriyor); cihazlar arası
  **sunucu tarafı ayar deposu** (hatırlatıcı profili + tarih biçimi + ses seçimi bugün
  cihaz-yerel, `notification_privacy` kalıbıyla aynı); alarm günlüğünün sunucuya raporlanması.
- **Round 10 park kuyruğu (kararı OPH-195 verir):** alt görevler (`parent_task_id` —
  şema, API ve kaskadlı silme hazır, arayüz yok), görev rengi (`tasks.color_rgb` — widget
  kullanıyor, kullanıcı seçemiyor), **elle sıralama** (`sort_order` sıralamada kullanılıyor ama
  sürükleme yok), süre alanları (`estimated_minutes`/`actual_minutes`), `tasks.start_at`,
  proje ikonu/başlangıç-bitiş tarihi; Tamamlananlar ekranında arama + `cancelled`/`archived`
  sekmesi; Pano kartlarında kaydırarak silme (yatay pager jest çakışması); sunucu tarafı
  "tamamlananlar" ucu (bugün tamamen yerel replikadan okunuyor); geri alma olmayan silmeler
  (dosya, checklist öğesi, hatırlatıcı adımı).
- **Round 11 park kuyruğu — Hızlı Erişim (OPH-196'da kesinleşti, 2026-07-29):** Android
  sistem-geneli overlay düğmesi (SYSTEM_ALERT_WINDOW — ayrı izin ve istila, kendi turu;
  Messenger bile chat head'i Android 11'de Bubbles API'sine taşıdı, yani "uygulama dışı
  yüzen düğme" artık OS'un kendi kanalı üzerinden yapılan bir iştir); iOS'ta uygulama dışı
  yüzen düğme (OS üçüncü partiye izin vermez — yazılı sınır); kısayol klasörleri / iç içe
  liste (tek 50'lik liste için ikinci hiyerarşi seviyesi; Slack'in kendi önerisi de "3–5
  bölüm"); dış linklerde OG başlık çekme (unfurl proxy'ye bağlı); workspace-paylaşımlı ekip
  kısayol listesi (ADR-0018 "shared team list" alternatifi — additive, v2); emoji-picker
  paketi (tam ızgara — ADR gerektirir, gerekçesi yok); **kısayol renginde sınırsız palet**
  (`_ColorGridDialog`'un tüm `Colors.primaries` seti — DESIGN §23 Q8a: sınırsız fille
  kontrast garanti edilemiyor, kısayolda yalnız 10'luk palet sunuluyor); **yüzen düğme
  opaklık slider'ı** (AssistiveTouch'ta var; bizde tek anahtar + %40 sabiti yeterli sayıldı);
  kısayol satırından hedefi yeniden adlandırma (kısayol adı hedefin adı değildir — §4.12).
- **Round 11 park kuyruğu — AI (gerekçeler [AI.md](AI.md) + ADR-0019/0022/0023):**
  abonelik-OAuth entegrasyonu (üç sağlayıcıda da kapalı/bekleme listesi — üç ayda bir
  yeniden bakılır; `auth_mode='oauth_subscription'` rezerve); sohbette yazma araçları
  v1.5 (`complete_task`/`reschedule_task` onay-kapılı; **silme kalıcı olarak hariç**);
  yüksek-güvende onay kartını atlama anahtarı (v1.5 opt-in); senkron sohbet geçmişi
  (`conversation` varlığı — gizlilik duruşu değişikliği, bilinçli karar ister);
  sunucu-STT varsayılanı (OpenAI/Gemini ses — v1.5 ayarı); gerçek-zamanlı sesli sohbet
  (speech-to-speech); doğal-dil filtreleri → akıllı liste DSL'i (önce DSL); akıllı
  zamanlama (takvim boş/dolu akıl yürütmesi); otomatik etiket/öncelik önerisi;
  haftalık AI özet e-postası; barındırılan ücretli "AllisWell AI" katmanı (ürün kararı);
  paylaşımda dosya/görsel anlama; günlük/haftalık AI incelemesi + not özetleme +
  toplantı-notu→görevler (v1.5 adayları — Epic 19 çıkarım ucunu yeniden kullanır).
- **Round 17 park kuyruğu — Markdown (gerekçeler [MARKDOWN.md](MARKDOWN.md) §3):**
  `[[wikilink]]`'ler + geri bağlantılar (bir bağlantı indeksi ister — kendi başına bir
  özellik); graf görünümü, PDF üzerine not alma, atıf/BibTeX (**reddedildi** — başka bir
  ürün); yazma hedefleri (Ulysses); editör içi AI ("devam ettir", "yeniden yaz" — Epic 20'nin
  altyapısı hazır, ürün kararı); DOCX/ePub dışa aktarma; klasör/vault izleme (**reddedildi** —
  biz markdown'ı iyi okuyan bir görev uygulamasıyız, Obsidian değiliz); Vim/Emacs kısayolları
  ve özel CSS temaları (**reddedildi** — Rule 11, tek tasarım sistemi); göreli yollu görseller
  (`./x.png` bugün sebepli yer tutucuyla çiziliyor — OPH-247); bölünmüş görünümde satır eşlemeli
  senkron kaydırma (bugün oransal — `markdown_forge/lib/src/edit/source_mode.dart`, OPH-248);
  dış dosyanın diskte değişmesini canlı izleme (bugün yalnız kaydetmede çatışma + elle
  `reprobe` — OPH-251).
- **Round 18 park kuyruğu (gerekçeler ADR-0031/0032):** **generic OIDC girişi**
  ([issue #2](https://github.com/mahirozdin/alliswell/issues/2) — Authentik/Keycloak/
  PocketID; meşru ve Firebase-sosyal-girişten farklı: sunucu yarısı ucuz çünkü ADR-0026'nın
  `src/lib/oauth-identity.js`'i zaten JWKS+issuer+audience doğrulaması ve subject-öncelikli
  hesap merdiveni taşıyor — iş "güvenilen issuer listesi + OIDC discovery'yi konfigürasyona
  açmak"; pahalı olan istemci yarısı: 6 Flutter platformunda authorization-code+PKCE tarayıcı
  akışı, deep-link dönüşü, ayar/doc yüzeyi. Tetikleyici: çok kullanıcılı workspace UI'ı
  açıldığında ya da talep birikince kendi epic'i olur); markdown'a renk sözdizimi (GFM'de yok
  — `==mark==` vurgusu var, gerisi Live/Delta tarafında; DESIGN §33 R6); Home/Projeler liste
  sıralaması (DESIGN §34 L5 yazılı sebepleri); notlar zip/dosya-başına toplu export (v1 JSON —
  OPH-266); API anahtarlarına scope'lar (v1 bilinçli scope'suz — ADR-0032 revizyonu ister);
  sürüm geçmişinde adlandırılmış/sabitlenmiş sürümler (Google Docs deseni; saklama
  inceltmesinden muafiyet mekanizması hazır, UI ürün kararı bekler); not etiketlerinin not
  push protokolüne girmesi (v1 bilinçli sınır: etiket yalnız REST `PUT /notes/:id/tags` ile
  yazılır, pull okur — OPH-261).
- Import from Todoist/TickTick/Apple Reminders; ICS export.
- Metrics endpoint (Prometheus), audit log UI, admin panel.
- E2E tests (Patrol/integration_test), F-Droid/TestFlight packaging.
- **İstemci yüklemelerinin taranması** (2026-09-24 incelemesi) — sunucunun kendi aldığı
  dosyalar bir uzantıda taranabiliyor; istemcinin presigned yüklemesi kovaya doğrudan gider
  ve taranmaz. Doğru çözüm kovada asenkron tarama + indirme kapısıdır (`files` satırında
  durum) — kendi turu.
- **Takvim v2:** Apple aynasının gelen yarısı — takvimde yapılan yabancı düzenlemeyi geri okuma
  (OPH-076'nın Google analoğu; çatışma politikası + ön plan yoklaması — OPH-078); CalDAV iCloud
  bağlayıcısı (yalnız tasarım, [CALDAV.md](CALDAV.md), `CALDAV_ENABLED` varsayılan kapalı — OPH-079).

### Ölçülmüş açıklar ve bilinen sınırlar (2026-09-26 temizliğinde toplandı — hiçbiri bir işe bağlı değildi)

- **GitHub #19** — web'de alarm düzeltme sayfasının "Open settings"i ölü bir `app-settings:`
  sekmesi açıyor (OPH-277'nin düzeltme sayfasının web yüzeyi).
- **Oturum kapanışı yerel replikayı silmiyor** — tek `alliswell.sqlite`; hesap değişince önceki
  hesabın satırları cihazda kalır (`logout()` replikaya dokunmuyor). Sertleştirme.
- **OPH-337** — `LocalKv` okunamazsa "Gizli widget" (ve bildirim gizliliği) hata vermeden
  "hiç ayarlanmamış" okunur → başlıklar widget'a yazılabilir.
- **OPH-226** — AI bağlantısının `baseUrl`'i korumasız bir SSRF yüzeyi (bilinçli kabul; yalnız
  SECURITY.md "AI ayarlarını güvenilen kullanıcılara açın" diyor).
- **ADR-0038 §8** — iOS başsız uyanış ertelendi: kilitli iPhone Keychain'i okuyamıyor
  (`WhenUnlocked`); erişilebilirlik değişikliği kendi güvenlik ADR'sini + yeniden anahtarlama
  göçünü ister.
- **OPH-025** — web'de httpOnly refresh-cookie sertleştirmesi (web oturumu bugün localStorage'da,
  `LocalKvSecretStore`).
- **OPH-324 takibi** — release APK'nın `res/raw` seslerini gerçekten taşıdığını ölçen artefakt
  kapısı hiç yazılmadı (`scripts/android/assert-permissions.sh` kalıbı).
- **OPH-236 (ikon)** — `scripts/design/branding_icons.py --check` hiçbir CI iş akışına bağlı değil.
- **OPH-193** — `check:i18n` yalnız literal kalıpları tarar; `Text(değişken)` ile basılan ham
  enum'u (`Text(project.status)`) göremez — kural ya da lint yok.
- **OPH-318** — uygulama dili değişince Android bildirim kanalının adı eski dilde kalıyor (önce
  ölç: aynı id'yle `createNotificationChannel` adı güncelleyebilir).
- **OPH-336** — widget yapılandırma sayfasının kendi etiketleri ("List", açıklama) İngilizce;
  native metaveri uygulamanın çevirisine ulaşmıyor.
- **OPH-181** — Android'de yüklenen özel ses bildirim kanalının sesi olamaz (FileProvider gerekir;
  bugün yalnız uygulama içi alarmda çalar); AlarmKit'in container'daki (`Library/Sounds`) sesi erken
  iOS 26'da çalmama raporu ölçülmedi — "çalmazsa paketli sese düş" yolu yok.
- **OPH-126** — oturum açılışında uygulama dilini `users.locale`'den tohumlama.
- **OPH-110** — kaskadlı arşivden çıkarma projenin TÜM arşivli öğelerini geri getirir (v1
  sadeleştirmesi; kaskadın dokunduklarını izlemek yeni kolon ister).
- **OPH-261** — proje arşiv kaskadı domain katmanında değil (`routes/projects.js`); MCP'de proje
  arşivleme bu yüzden yok.
- **OPH-168** — Pano: "2/5" konum etiketi ve dikey kenar otomatik kaydırması v1'den kırpıldı.
- **OPH-081** — drift'in üretilmiş şema-test aracına dönüş (drift_dev ↔ drift sürümleri
  hizalanınca); bugün göç testleri elle.
- **OPH-245** — `imageCache` bayt ölçümü hiç alınmadı (büyük fotoğraflarda bellek davranışı varsayım).
- **OPH-256** — macOS Release dağıtım imzası (Developer ID + noterleme) kararı verilmedi.
- **OPH-227** — README/mağaza için AI bubble ve onay kartı ekran görüntüleri yok.
- **`docs/SELF-HOSTING.md` §4** — yükseltme öncesi yedek komutunda `--no-tablespaces` eksik
  (§4b'dekinde var); PROCESS yetkisiz kullanıcıda korkutucu ama zararsız bir "Error:" basar.
