# STATE — Live development state

> This file is the pointer for the "do the next task" (TR: _"sıradaki işi yap"_) workflow.
> Always read it first; always update it before finishing a session. Backlog: [TASKS.md](TASKS.md).

**Last updated:** 2026-07-17 (feedback round 4 yakalandı → **Epic 10 açıldı: OPH-100…111**; BLUEPRINT §4/§12 + DESIGN §4 revize)

**Repository:** https://github.com/mahirozdin/alliswell (public) — CI green since the first push
([run #1](https://github.com/mahirozdin/alliswell/actions)): migrations apply/rollback/re-apply
against real MySQL 8.4 and all unit+integration tests pass.

## Snapshot

| | |
| --- | --- |
| Current phase | **v0.1.0 hazır**; ilk kullanıcı testi geri bildirimi **v0.1.1 (Phase 4.9)** olarak planlandı |
| Current epic | **Epic 10 — Feedback round 4** (OPH-100…111): kullanıcı testinden 13 madde, hepsi TASKS.md'de ayrıntılı task |
| ➡️ **Next task** | **OPH-107 — Inbox yakalama kutusu** (sonra 109 README, 110 arşiv, 111 onboarding). Bitti: OPH-100/101/102/103/104/105/106 ✅ + OPH-108 (sekme kökü) ✅. |
| ✅ Kullanıcıdan bekleyen | Zorunlu YOK. v0.1.0 tag'i hâlâ maintainer'da (dışa yayın; Epic 10 v0.1.1'i besler). Opsiyonel: `GOOGLE_WEBHOOK_URL`, macOS geliştirme sertifikası, Apple/Android cihaz turu. |
| Last completed | **Feedback round 4 dokümantasyonu** (BLUEPRINT §4.2/§4.3/§12.2-12.7 revize, DESIGN §4 "Project badge", Epic 10 backlog). Öncesi: Epic 09 tam (OPH-094/095), Epic 08 tam. |

## Recently completed

- **Feedback round 4 → Epic 10 doğdu (2026-07-17):**
  - **Nasıl:** tüm yığın yerelde koşuldu (colima + MySQL 3307 + Redis + API 3000 +
    `flutter run` web 8080 + iPhone 17 Pro simülatörü; kayıt/giriş smoke'u geçti) ve
    kullanıcı İLK gerçek el testini yaptı — 13 numaralı madde bildirdi. Hepsi aynı gün
    koda karşı araştırıldı; kalıcı spec değişiklikleri BLUEPRINT'e (§4.2 arşiv, §4.3
    inbox=yakalama, §12.2 Home 30-gün ufku + rozet + kayan takvim, §12.3 README bağlamı,
    §12.4 statü ikonları, §12.5 README filtresi, YENİ §12.6 Inbox / §12.7 Onboarding) ve
    DESIGN §4'e ("Project badge" bileşeni) işlendi; sonra TASKS.md'ye **Epic 10
    (OPH-100…111)** olarak, uygulayacak ajanın karar vermesine yer bırakmayan ayrıntıda
    yazıldı (madde↔task eşleme tablosu epic başında).
  - **Araştırmanın kilit bulguları (task'lara gömülü ama özet):**
    1. *Web sign-out crash'i (OPH-100):* `auth_api._post` 204'ün web-dio'daki `''`
       gövdesini `as Map` ile cast ediyor; TypeError `AuthException` olmadığından
       `logout()` yerel temizliğe HİÇ ulaşmıyor — sunucu oturumu ölü, app "girili".
    2. *FAB'lar (OPH-101):* shell `extendBody: true` + cam NavigationBar; iç
       Scaffold'ların FAB'ı (home/projects/notes ×3) barın ALTINA çiziliyor.
    3. *Inbox (OPH-107):* `status='inbox'` zaten var ve quick-add onu yazıyor; sızıntı
       `kOpenStatuses`'ın inbox'ı içermesi → Home'a düşüyor. Şema işi sıfır.
    4. *Proje arşivi (OPH-110):* `projects.status` enum'ında `archived` GÜN 1'den beri
       var (migration 20260714000200), sync/REST kabul ediyor — migration GEREKMEZ;
       eksik olan akış (kaskad + varsayılan-gizli listeler + dürüst dialoglar).
    5. *Create sheet'te proje seçici (OPH-106) aslında VAR* — sıfır projede tek "No
       project" girdisine çöküp görünmez oluyor; detay ekranında ise gerçekten yok.
  - **OPH-083'teki bayat `[ ]` kapatıldı** (madde OPH-084 olarak çoktan bitmişti) —
    "sıradaki işi yap" artık yanlış pozitif bulamaz.
  - Not: bu tur SADECE dokümantasyon; kod değişmedi, testler koşulmadı (gerek yok).
    Sıradaki oturum OPH-100'den başlar.

- **Epic 09 KAPANDI — ROADMAP + release otomasyonu → tüm MVP backlog'u bitti (2026-07-16, OPH-094/095):**
  - **[ROADMAP.md](../ROADMAP.md)** (OPH-094): fazlardan üretilmiş, gerçek duruma karşı
    dürüst (✅/🟡/⏳/💤), v0.1.0 milestone + v2 park listesi. README docs index'ten VE üst
    durum satırından bağlı. "GitHub Projects notu" bilinçli: markdown dosyaları (STATE/
    TASKS/CHANGELOG) tek gerçek kaynak kalıyor — board opsiyonel — çünkü AI-agent akışı bu
    dosyaları okuyup yazıyor.
  - **`.github/workflows/release.yml`** (OPH-095): `v*.*.*` tag'iyle tetiklenir, tag = sürüm.
    (1) `ci.yml`'i `workflow_call` ile YENİDEN KULLANIR (tam test süiti geçmeden tag yayınlamaz
    — kopya yok, drift yok); (2) tag'in `apps/api` + `apps/app` sürümleriyle EŞLEŞTİĞİNİ
    doğrular; (3) release notlarını CHANGELOG'dan ÇIKARIR (awk "Development log" işaretinde
    durur → düzenli Highlights + Known limitations); (4) **web bundle** kurar
    (`alliswell-web-<v>.tar.gz`); (5) 1.0 altı prerelease olarak GitHub Release yayınlar.
    `ci.yml`'e `workflow_call` trigger'ı eklendi. CHANGELOG düzenli `## [0.1.0]` bölümüyle
    yeniden yapılandırıldı. **Yerel doğrulama:** sürüm eşleşmesi + awk çıkarıcı (28 satır) +
    her iki workflow'un YAML'i (`python3 yaml.safe_load`) — hepsi geçti.
  - **v0.1.0 tag'ini kesmek maintainer'a bırakıldı** — tag push dışa yayın; otomasyon hazır.
  - Not: OPH-095'in başındaki "OPH-077/078 Xcode'a bloklu" ifadesi bayattı; artık her ikisi
    de bitti (imza hazır, iOS build geçiyor).

- **Apple EventKit köprüsü + event CRUD → Epic 08 KAPANDI (2026-07-16, OPH-077/078):**
  - **Neden cihaz-tarafı:** Apple'ın sunucu-tarafı takvim API'si YOK. Google mirror'ı
    sunucuda BullMQ ile koşarken, Apple mirror'ı **uygulamanın içinde** koşuyor — replica'yı
    dinliyor (`appleMirrorProvider` açık-görev stream'ini izler, home shell canlı tutar).
    v1'de tek yön: görev → etkinlik. Yabancı Apple düzenlemesini geri okumak ertelendi
    (OPH-076'nın Apple karşılığı; çakışma politikası + push yok, yalnız foreground yoklama).
  - **Plugin paketi, pbxproj cerrahisi SIFIR:** Swift'i `Runner`'a koymak yerine
    `packages/alliswell_eventkit` — Flutter tooling podspec'i iOS+macOS için kendi bağlar.
    Tek Swift dosyası iki platforma birden (macOS kaynağı iOS'a symlink + koşullu import).
  - **4. saf karar fonksiyonu** (ADR-0008 öngörmüştü): `desiredAppleEvent(task)` sunucunun
    `desiredEventForTask`'ını fixture-fixture aynalar — aynı §7.1, aynı ters-blok koruması —
    böylece görev Google'a da Apple'a da gitse aynı saatte oturuyor. `decideAppleMirror`
    create/update/noop/remove matrisi ayrı testli; motor yalnız uygular.
  - **İmza koruması** (map satırında içerik parmak izi) → her replica emit'inde tüm seti
    uzlaştırmak, yalnız gerçekten değişeni yazıyor. **drift v4** (`apple_event_links`,
    cihaz-yerel, senkron DEĞİL — Apple etkinlikleri cihazda yaşar); `alliswell://task/{id}`
    URL'i re-link kurtarma anahtarı (ADR-0003 — EventKit id'si iCloud taşımasında değişebilir).
    **Yetim süpürme**: tümüyle kaybolan görevlerin etkinliğini `reconcileAll` siler.
  - **Ulaşılabilir** (OPH-080 dersi): Apple takvim Settings kartı — izin iste, takvim seç,
    dürüst durum (seçilene dek amber; reddedilmişse "sistem ayarlarından izin ver").
    Apple-olmayan platformlarda tamamen gizlenir. iOS 17 `writeOnly` "verildi" sayılmıyor
    (yaratır ama okuyamaz → re-link kırılır).
  - **Yol boyunca OPH-077 defekti düzeldi:** commit'teki (`e3cb3ea`) Swift dosyası BOŞTU
    (stash bozması). Yeniden yazıldı + `flutter build ios` GEÇTİ.
  - **Testler:** app 158/158 → +27 (saf türetme, karar matrisi, motor sahte gateway +
    gerçek in-memory replica üstünde, kanal CRUD sözleşmesi, v4 migration). analyze temiz,
    iOS build geçti. ⚠️ Gerçek EventKit yazma turu cihazda gözlenmeli (OPH-061 gibi bekliyor);
    macOS hâlâ build olmuyor (devralınan imza açığı).

- **OPH-084 — takvimin Home'un kronolojik akışında (2026-07-16):**
  - `HomeGroup.tasks` → `HomeGroup.items`: sealed `HomeItem` (`TaskItem` | `EventItem`),
    `at` sıralama anahtarıyla. Yani 10:00 toplantısı 16:00 görevinin ÜSTÜNDE render
    oluyor — §12'nin "tek kronolojik görünüm"ü ile "yan tarafta takvim paneli"
    arasındaki fark bu. Ay ızgarası artık yalnız toplantı taşıyan günleri de
    noktalıyor.
  - **İki ürün kuralı** (ikisi de testli, ikisi de "kullanıcıya yalan söyleme"):
    (1) **Etkinlikler Overdue'ya GİRMEZ** — Overdue "bunu hâlâ yapman lazım" demek;
    olmuş bir toplantı borç değil, tarihtir → Home'dan tamamen düşer.
    (2) **Süregelen çok-günlük etkinlik Today'e aittir, bir kez** — pazar başlayıp
    perşembe biten seyahat ŞU AN oluyor; ne overdue (geçmişte başladı) ne de
    kapsadığı her bucket'ta tekrarlanır. Geçmemiş ilk gününe oturur.
  - Takvim bağlı değilse Home eskisi gibi (boş liste — hata değil, spinner değil).
  - Testler: app 131/131 (7 yeni), analyze temiz, kontrast FAILURES: 0.
    Mevcut `groupTasksForHome` testleri yeni sözleşmeye taşındı.

- **Kendi takvimin artık AllisWell'de (2026-07-16, OPH-082/083; ADR-0008):**
  - **Nasıl bulundu:** kullanıcı gerçek Google hesabını bağladı ve "takvimimdekiler
    gelmedi" dedi. Doğruydu ve bilinçliydi — `lib/inbound.js` bizim olmayan her etkinliği
    yok sayıyordu. Ama sınır yanlış yerdeydi: Calendar sekmesi olan ve §12'de Home için
    "her şeyin göründüğü tek kronolojik görünüm" denen bir üründe, "günüm nasıl görünüyor"
    sorusu görevlerle cevaplanamaz. **BLUEPRINT harici etkinliklerden hiç bahsetmiyordu**
    (v2 park listesinde bile yok) → spec deliği, kod hatası değil.
  - **Veri zaten elimizdeydi:** OPH-075 worker'ı her geçişte tüm etkinlik akışını çekip
    yabancı yarısını çöpe atıyordu. Artık saklıyor — senkron başına bir ekstra istek,
    etkinlik başına değil.
  - **İki sözleşme bulgusu tasarımı belirledi** (kaynaktan doğrulandı, varsayılmadı):
    (1) `timeMin`/`timeMax`, `syncToken` ile KULLANILAMIYOR → senkron tarihle
    pencerelenemez, Google koleksiyonun tamamını senkronlar; pencereyi SAKLARKEN
    uyguluyoruz (31 gün geri / 400 ileri). (2) `singleEvents` iki tüketiciye birden
    hizmet edemez: görev aynalaması seri master'ını görmeli (`time_conflict`, ADR-0007,
    testli), ızgara ise örnekleri. → **iki akış, iki cursor** (`sync_token` +
    `external_sync_token`), mevcut akışa hiç dokunulmadı.
  - **Salt-okunur, kod yazmadan:** push `ENTITIES` kaydında olmaması zaten
    `SYNC_UNSUPPORTED_ENTITY` veriyor. Store'un yazma yolu hiç yok — o yokluk garantinin
    kendisi. `ExternalEventTile` bilinçli olarak `TaskTile`'dan farklı bir tür: checkbox
    yerine saat rayı — bir düğünü "tamamlayamazsın", satır da bunu ima etmemeli.
  - **Değişmemiş etkinlik revizyon harcamıyor** — tam resync tüm takvimi tekrar oynatır,
    yoksa her toplantı için her cihaz uyanırdı.
  - **Gerçek hesapta doğrulandı:** 41 etkinlik, gerçek `syncToken`, pencere tuttu
    (2026-06-16 → 2027-07-23, eski geçmiş elendi), gerçek bir etkinlik Calendar
    sekmesinde açık+koyu temada göründü. Testler: API 209/209, app 124/124.
  - **Ertelendi (OPH-084):** Home'un kronolojik gruplarında etkinlikler. §12 istiyor ama
    `HomeGroup` görev taşıyor; karıştırmak saf gruplama fonksiyonunu ve satır şeklini
    değiştirir — kendi task'ını hak ediyor, buraya kaçak sokulmaz.
- **Epic 08 app tarafı — dikey artık ULAŞILABİLİR (2026-07-15, OPH-079…081):**
  - **Neden bu paket:** OPH-070…076 ile eksiksiz bir Google API dikeyi vardı ve
    **hiçbir kullanıcı ona ulaşamıyordu** — app'te bağlanma ekranı yoktu,
    `calendarMirrorEnabled` Flutter modelinde hiç yoktu. OPH-077/078 Xcode'a bloklu
    olduğu için AGENTS.md §2'nin "bloklu işi atla" kuralıyla bunlar alındı
    (OPH-080/081 backlog'a bu oturumda eklendi; BLUEPRINT §12 zaten "Calendar mirror
    toggle" şart koşuyordu — task'ı yazılmamıştı).
  - **OPH-079 [CALDAV.md](CALDAV.md):** v2 iCloud connector tasarımı, 9 kaynak, kod yok.
    Başlık: app-specific password **OAuth token DEĞİL** — kapsamsız, süresiz, bizden
    iptal edilemez ve tasarımı gereği at-rest geri döndürülebilir (her istekte tekrar
    oynatmamız gerek, kanal token'ı gibi hash'lenemez). Bu yüzden: connector
    **varsayılan KAPALI** (`CALDAV_ENABLED`), saklamadan önce doğrula, sade dille
    onam, ve disconnect kullanıcıya iptalin diğer yarısının onda olduğunu söyler.
    Kilit bulgu: **ADR-0007'nin çakışma matrisi aynen taşınır** — `lib/inbound.js`'e
    normalize edilmiş event verilirse; bu normalizasyonu ÖNCE yapmak, connector ile
    Epic 08'in ikinci bir kopyası arasındaki fark.
  - **OPH-080 bağlantı UI'ı:** `features/integrations/` — REST, bilinçli olarak sync
    protokolü DIŞINDA (takvim hesapları kullanıcı başına sunucu durumu; önbelleklenmiş
    bir "bağlı" yalan olurdu). `url_launcher` (yeni bağımlılık) onamı GERÇEK tarayıcıda
    açar (`externalApplication`; app OAuth code'a hiç dokunmaz — kimlik sunucunun imzalı
    state'inde, ADR-0006). İkon rengi doğruyu söyler: takvim seçilmemişse amber (hiçbir
    şey aynalanmıyor), çalışınca yeşil, reauth'ta kırmızı.
  - **OPH-081 toggle + replica:** sunucu `calendarMirrorEnabled`'ı OPH-072'den beri
    taşıyordu → **sıfır sunucu işi**. drift kolonu (şema v2 — projenin İLK replica
    migration'ı), applier, model, store dalı, §12 toggle'ı. Alt metin göreve göre dürüst:
    "Adds a block…" / "Add a date below and it will appear". **OPH-076'nın bir deliği de
    kapandı:** `scheduled_*` sürüklenen etkinliğin indiği yer ve app iki alanı da
    modellemiyordu — iki yönlü senkron görünmezdi. Artık Scheduled satırı var.
  - **Tarayıcıda gerçekten koşturarak bulunan İKİ hata (testler yeşilken):**
    1. **Riverpod 3 hata veren HER provider'ı varsayılan olarak 10 kez, 200ms→6.4s
       backoff'la yeniden deniyor** ve bu sırada `AsyncLoading` bildiriyor → takvim
       seçici ~38 sn spinner'da kaldı ve ölü bir Google kimliğine **11 kez** sordu;
       tasarladığımız hata ekranı ulaşılamazdı. Canlı ölçüm: 225/420/821/1628/3222/6426 ms.
       Politika `core/retry.dart` (`awRetry`, TÜM ProviderScope'larda — testler dahil):
       yalnız retry'nin düzeltebileceğini (sunucuya hiç ulaşamama) dene. Sonrası:
       **1 istek, hata anında.** Bu app'teki tüm FutureProvider'ları etkiliyordu.
    2. **Testler neden kaçırdı:** kendi `ProviderScope`'larını kuruyorlar (üretim
       politikası yoktu) ve `pumpAndSettle` backoff'u sahte zamanda yakıyor — testte
       "anında", kullanıcıda 38 saniye. Regresyon testi bu yüzden politikanın kendi
       birim testi (`test/core/retry_test.dart`).
  - **API tarafında bir sertleştirme:** `desiredEventForTask`, taşınan bir start'ın
    geride bıraktığı `scheduled_end_at`'ten ters blok türetebiliyordu — Google
    `end <= start`'a 400 veriyor ve kuyruk bunu asla retry'layamaz. Artık 30 dk'lık
    varsayılan slota düşüyor.
  - **Testler:** app 114/114 (13 yeni: migration, replica turu, toggle, Scheduled,
    Google kartının 6 durumu, retry politikası); API 196/196 + 28/28. `flutter analyze`
    temiz, kontrast bekçisi FAILURES: 0, açık+koyu tema tarayıcıda doğrulandı.
    Uçtan uca kanıt: UI toggle → optimistic replica → outbox → sync push → MySQL
    (`calendar_mirror_enabled=1` + `changed_fields:["calendar_mirror_enabled"]`).
  - **Demo:** `.claude/launch.json` → `api-calendar-demo` (sahte Google kimlikleriyle
    `configured: true`) + `app-web-built` (statik build servisi). Not: preview sandbox'ı
    `flutter run`'ı çalıştıramıyor, o yüzden `flutter build web` + python http.server.
    **Dikkat:** python http.server `Cache-Control` göndermiyor → tarayıcı bayat bundle
    servis edebiliyor; yeniden build sonrası SW'yi kaldır + `fetch(..., {cache:'reload'})`
    ile tazele, yoksa düzelttiğin hatayı hâlâ görürsün (yarım saatimi bu yedi).

- **Epic 08 gelen dikey — Google → AllisWell (2026-07-15, OPH-074…076; ADR-0007):**
  - **OPH-074 webhook:** `POST /api/v1/integrations/google/webhook`. Google'ın
    bildiriminde GÖVDE YOK — mesaj başlıkların kendisi — bu yüzden route kendi
    content-type scope'unda (Fastify'ın JSON parser'ı gövdesiz POST'a 400 verirdi).
    Kapı **kanal token'ı**: biz üretiyoruz, Google'a bir kez veriyoruz, veritabanına
    yalnız `HMAC-SHA256('channel:'+token)` (`webhook_channel_token_hash`) yazıyoruz —
    plaintext'e bir daha ihtiyaç yok (yenileme yeni token basar), karşılaştırma
    sabit zamanlı. Sahte token → `401 GOOGLE_WEBHOOK_INVALID_TOKEN`; bilinmeyen/emekli
    kanal → `200` (retry kanalı var etmez; hesap olmadan `channels.stop` da
    çağrılamaz); `X-Goog-Resource-State: sync` kanal-açıldı el sıkışması, dirty
    yapmaz. Gerçek bildirim → `sync_dirty_at` + kuyruk (alıcı hızlı cevap vermeli).
  - **Kanal yenileme:** yeni kanal ESKİSİ KAPANMADAN önce açılır (boşluk yok; örtüşme
    yalnız bildirimi çiftler, sync idempotent). Yenileme, istediğimiz ttl'e değil
    Google'ın döndüğü `expiration`'a göre. Disconnect artık token'ı iptal etmeden
    ÖNCE kanalı durduruyor.
  - **OPH-075 worker:** `plugins/calendar-sync.js` — mirror kuyruğunun aynadaki ikizi
    (ikisi de artık ortak `queue/runner.js`: Redis varsa BullMQ, yoksa inline).
    Cursor'a güvenmeden önce SON sayfaya kadar sayfalama (Google `nextSyncToken`'ı
    yalnız orada verir); `410` → token düşer, tam resync (yerel silme GEREKMEZ —
    `calendar_event_links` event id ile anahtarlı, her etkinlik yolda kendini
    uzlaştırır); dirty bayrağı compare-and-clear ile temizlenir (sync sırasında gelen
    webhook kendi geçişini hak eder). Hatalar bilinçli olarak GÜRÜLTÜLÜ (bubble →
    backoff → `last_error` status ucunda): yorumlayamadığımız etkinlikler
    `time_conflict` cevaplıyor, dolayısıyla throw gerçekten altyapı demek.
  - **OPH-076 çakışma:** tüm matris SAF fonksiyon (`src/lib/inbound.js` —
    `desiredEventForTask`'ın gelen taraftaki ikizi), dört durum da Google'sız/DB'siz
    test edildi, sonra uçtan uca tekrar. **Echo bastırma etag temelli**: her giden
    yazımın etag'i saklanır, kendi değişikliğimiz geri geldiğinde kullanıcı düzenlemesi
    sanılmaz — mirror ⇄ sync döngüsünü kesen şey bu. Yabancı taşıma `scheduled_*`'a
    yazılır, `due_at`'e ASLA (bloğu sürüklemek "o saatte yaparım" demek), ve §7.1'in
    TÜRETTİĞİ pencereyle karşılaştırılır — yoksa etkinliği renklendirmek, due'dan
    türeyen görevi sessizce takvime çivilerdi. Tüm-gün etkinlikler görev saat diliminde
    gece yarısına eşlenir (Google'ın dışlayıcı `end.date`'i onurlandırılır).
    Dört durum: `local_changed_provider_changed` (iki taraf da oynadı → §6.5 LWW,
    kaybeden düşer, bayrak kalır; sonraki temiz yazım `none`'a çeker = uzlaşıldı),
    `provider_deleted_local_exists` (kullanıcı etkinliği sildi → görevi KORU, aynalamayı
    kapat, bayraklı link mezar taşı olarak kalır ve mirror job onu atlar — ne diril, ne
    görevi sil), `local_deleted_provider_exists` (görev artık etkinlik hak etmiyor ama
    kayıt yaşıyor ve değişti → yerel kanonik, sil), `time_conflict` (tekrar eden seri
    veya kullanılamaz sınırlar → bayrakla, iki tarafa da dokunma).
  - **Polling yedeği:** `GOOGLE_WEBHOOK_URL` opsiyonel (Google public HTTPS + güvendiği
    sertifika şart). Yoksa kanal açılmaz, süpürme (`CALENDAR_SYNC_SWEEP_SEC`, 5 dk)
    o hesapları yoklar — localhost/NAT self-hoster'lar dışarıda kalmaz.
  - **Testler:** birim 195/195 (25 yeni: saf matris + worker uçtan uca + webhook/kanal
    yaşam döngüsü); entegrasyon 28/28 — gelen dikey gerçek MySQL+Redis/BullMQ üzerinde
    (webhook → dirty → kuyruk → incremental sync → görev yazımı → sync revision).
    Migration apply→rollback→re-apply doğrulandı. Entegrasyon 5 kez üst üste yeşil
    (kararlılık kontrolü).
  - **Yakalanan iki ince hata:**
    1. *Mezar taşı yarışı:* bayrak görev yazımından ÖNCE kalıcı olmalı — görev yazımı
       mirror kuyruğunu tetikliyor ve henüz bayraklanmamış link sıradan bayat link gibi
       görünüp siliniyordu.
    2. *Kuyruk keyspace çakışması (üretim hatası, testte ortaya çıktı):* tüm dağıtımlar
       BullMQ'nun varsayılan `bull:` keyspace'ini kullanıyordu → aynı Redis'i paylaşan
       iki AllisWell birbirinin işini tüketir; hırsızın kendi MySQL'inde görev
       olmadığından iş sessizce DÜŞER (yanlış yere gitmez, kaybolur). Artık
       `REDIS_KEY_PREFIX` (varsayılan `alliswell`) ile isim alanı var; ikinci kuyruk
       eklenince flaky entegrasyon olarak yüzeye çıktı.
  - Kalan (Epic 08): OPH-077/078 (EventKit — Xcode imza), OPH-079 (CalDAV doc).
    App tarafında "Google'ı bağla" UI'ı hâlâ ayrı bir iş; `calendarMirrorEnabled`
    Flutter modelinde henüz yok (doğrulandı — bu dikey app'e dokunmadı).

- **Epic 08 giden dikey — Google Takvim (2026-07-15, OPH-070…073; ADR-0006):**
  - **OPH-070 bağlantı:** `POST /workspaces/:id/integrations/google/connect` → consent
    URL'i (10 dk'lık imzalı `state`, `purpose: google_oauth` — oturum JWT'si state olarak
    GEÇMEZ, testli); kimliksiz callback kodu takas eder, id_token'dan kimliği çözer,
    `calendar_accounts`'a upsert eder (yeniden bağlanma çoğaltmaz). Tokenlar dinlenmede
    **AES-256-GCM** (`src/lib/crypto.js`, `CALENDAR_TOKEN_KEY` 64 hex; Google
    yapılandırılmışsa production placeholder'ı reddeder). Entegrasyon opsiyonel:
    kimlik yokken `GOOGLE_NOT_CONFIGURED`. Disconnect Google'da revoke (best-effort) +
    ciphertext NULL.
  - **OPH-071:** `GET …/accounts/:id/calendars` — süresi dolan access token yerinde
    yenilenip yeniden şifrelenir; reddedilen refresh → hesap `error` +
    `CALENDAR_ACCOUNT_REAUTH_REQUIRED` (502). `PATCH …/accounts/:id {defaultCalendarId}`
    seçimi kaydeder ve sweep başlatır (workspace'in mirror-enabled görevleri kuyruğa).
  - **OPH-072/073 aynalama:** görevler `calendarMirrorEnabled` ile opt-in (REST + sync
    push + snapshot'lar). Saf türetme `src/lib/mirror.js` (§7.1: scheduled blok → due
    slotu → acil reminder bloğu; biten/arşivlenen/silinen → etkinlik kalkar). Commit
    sonrası entity olayları görev başına mirror işi kuyruklar: Redis varsa **BullMQ**
    (exponential backoff, bekleyen işlerde task başına dedupe), yoksa deterministik
    inline runner (`app.mirror.idle()` testler için). Etkinlikler `[Task] {title}` +
    ADR-0003 extended-properties (+project/source/revision); oluşturma öncesi
    `privateExtendedProperty` araması kopyayı ÖNLER (kayıp link satırında yeniden
    bağlanır, testli). Uzaktan silinen etkinlik yeniden oluşturulur (çakışma politikası
    OPH-076'da). Eşleme tablosu `calendar_event_links` kanonik.
  - **Testler:** birim 164/164 (in-process sahte Google: OAuth uçları, kripto
    tamper/yanlış-anahtar, türetme, yaşam döngüsü, re-link, sweep); entegrasyon 26/26 —
    BullMQ yolu gerçek Redis'te uçtan uca (yazım → kuyruk → worker → etkinlik;
    complete → silinir). İnce hata bulundu: gövdesiz DELETE'te `content-type: json`
    göndermek titiz sunucularda 400 — istemci artık yalnız gövde varsa content-type
    koyuyor.
- **Epic 07 — bildirim katmanı (2026-07-15, OPH-061…064; plan NOTIFICATIONS.md):**
  - **Mantık cihazsız ve tam testli:** `notifications/planner.dart` (saf: replika
    alarmları → istenen OS bildirimleri; iOS 64-bekleyen sınırına karşı ≤40 pencere;
    acil+onay zinciri T,+2,+5,+10,+30 dk) + `scheduler.dart` (içerik-hash id'lerle
    desired-vs-pending diff'i: fazlaları iptal, eksikleri kur; izin reddi sessizce
    degrade olur). Plugin'e yalnız `gateway_local.dart` dokunur: acil →
    `alarmClock` + Darwin `timeSensitive`; normal → `exactAllowWhileIdle`.
  - **Aksiyonlar (OPH-062) local-first:** bildirimden Tamamla/Ertele(5dk/30dk/1sa/
    yarın)/Onayla → store yazımları (optimistic + outbox) — online/offline ayrımı
    tek yola indi. Sunucu push'ı artık task `snoozedUntil` kabul ediyor (update-only;
    REST snooze semantiği aynı trx'te reminder'ı da uyutur/yeniden kurar; geçmiş
    zaman kabul edilir — offline kuyruk geç gelebilir).
  - **Acil UX (OPH-063):** `urgent_alarms` kanalı (max önem, alarm kategorisi,
    verildiyse full-screen intent); onay zinciri her cihazda senkronla söner.
    Acknowledge: `ReminderStore.acknowledge` → dar push entity'si
    `reminder {status: acknowledged}` + REST `POST /reminders/:id/acknowledge`
    (idempotent; sönmüş alarm → `REMINDER_INVALID_TRANSITION`).
  - **Gizlilik (OPH-064):** Settings → "Private notifications" (cihaz başına
    kalıcı) — kilit ekranında yalnız "AllisWell / Bir hatırlatıcın var"; tıklama
    id ile derin bağlanır. Planlayıcı tüm zincire uygular.
  - **Platform:** manifest izin+receiver'lar, gradle desugaring, macOS
    time-sensitive entitlement; iOS Xcode capability adımı NOTIFICATIONS.md'de.
  - Testler: app 97/97 (planner/scheduler/actions 15 yeni), API 150/150 + 25/25.
- **Epic 06 closed + Epic 07 opened (2026-07-15, OPH-057 + OPH-060):**
  - **OPH-057 canlı fanout:** `src/plugins/socket.js` — Socket.IO aynı HTTP
    listener'da; handshake'te access token doğrulanır, soket üyelik başına
    `ws:<id>` odalarına katılır (connect anında snapshot; yeni workspace →
    reconnect). `recordSyncWrite` commit SONRASI in-process emitter'a yayınlar
    (workspace başına tick'te TEK event, en yüksek revizyonla — REST + sync
    push ikisi de duyurulur). Redis hazırsa adapter bağlanır (pub/sub çifti
    eager connect + kuyruklu; health-check istemcisi gibi fail-fast DEĞİL),
    değilse tek-node mod. App: `sync_socket.dart` + `syncSocketProvider` —
    oturum başına bir soket (token rotasyonunda yeniden kurulur, forceNew),
    eşleşen `sync:changed` → `SyncEngine.syncNow()`; 60 sn periyodik pull
    artık yedek. Testler: sunucu 5 birim (auth reddi, oda izolasyonu, burst
    coalescing, push fanout) + Redis-adapter'lı entegrasyon; app'te sahte
    soketle canlı-güncelleme widget testi (yerel yazma OLMADAN yabancı
    düzenleme UI'a düşer). Dikkat: `sync:ready` connect ack'iyle aynı TCP
    segmentinde gelebilir — istemci dinleyicileri handshake'ten ÖNCE bağlanmalı.
  - **OPH-060 cihaz kaydı:** `notification_devices` migration'ı +
    `PUT/GET/DELETE /api/v1/notification-devices[/:id]` (kayıt=heartbeat
    upsert, 201/200; hesap değişiminde cihaz devralınır; DELETE her zaman 204).
    push_token opsiyonel (v1 bildirimleri yerel). Senkron varlık DEĞİL.
  - **Bildirim araştırması (OPH-060 notu):** [NOTIFICATIONS.md](NOTIFICATIONS.md)
    — 11 kaynaklı, OPH-061…064 için bağlayıcı plan. Özet: Android acil →
    `setAlarmClock` (asla ertelenmez, Doze'dan muaf) + Android 14'te varsayılan
    reddedilen `SCHEDULE_EXACT_ALARM` akışı; iOS acil → `timeSensitive` +
    64-bekleyen-bildirim sınırına karşı ≤40'lık pencere yöneticisi;
    onaylanana-dek-tekrar zili iki platformda da ÖN-planlanmış zincir;
    critical-alerts entitlement bayraklı hedef.
- **Epic 06 client side — the app is local-first (2026-07-15, OPH-054…056):**
  - **Replica:** drift database (`apps/app/lib/src/sync/db/database.dart`) mirrors all
    synced entities + `pending_mutations` outbox + per-workspace `sync_states` (clientId,
    lastRevision). Timestamps as ISO text (DATETIME(3) precision). Native: sqlite file via
    background isolate; web: drift wasm — `web/sqlite3.wasm` + `web/drift_worker.js`
    COMMITTED, pinned to sqlite3 3.4.0 / drift 2.34.2 (pubspec upgrade'inde birlikte
    güncelle). Client id'ler `core/ulid.dart` ULID'leri.
  - **Stores (OPH-054):** `features/{tasks,projects,notes}/data/*_store.dart` + tags —
    okumalar drift watch stream'leri (provider adları/şekilleri korundu: ekranlara
    dokunulmadı), yazmalar optimistic yerel satır + AYNI transaction'da outbox kaydı.
    UI'dan REST çağrısı kalmadı (auth + /me hariç). Not araması offline substring
    (FULLTEXT sunucuda kanonik kalır).
  - **Engine (OPH-055):** `sync/sync_engine.dart` — sıralı batch push (≤100) →
    sonuç işleme → sayfalı pull (`sync_applier.dart` upsert/tombstone). Tetikler:
    yazma sonrası debounce, başlangıç, 60 sn periyodik fallback (OPH-057 socket'i
    bunu ikincilleştirecek). Hata → outbox durur, exponential backoff (1s→60s cap).
  - **Conflicts (OPH-056):** applied-dışı sonuçlar `SyncConflict` stream'i →
    shell snackbar. `NOTE_CONTENT_CONFLICT` → yerel içerik "(çakışan kopya)" notu
    olarak yeni create ile kuyruğa girer; pull orijinali sunucu haliyle geri yükler.
  - **Tests:** `test/sync/` (şema round-trip, applier, outbox/backoff, conflict copy)
    + widget testleri FakeApi'nin yeni `/sync/pull`+`/sync/push` uçlarıyla tam döngüyü
    sürüyor. `flutter analyze` temiz, **80/80** yeşil. Widget testleri
    `test/support/sync_overrides.dart` kullanmalı (in-memory db —
    `closeStreamsSynchronously: true`, drift'in stream-cache Timer'ı flutter_test'in
    pending-timer kontrolüne takılır; pull timer kapalı, debounce 0).
  - Not: replica sign-out'ta silinmiyor (gelecek sertleştirme, web token notuyla
    aynı sınıf); Socket.IO fanout OPH-057'de.
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
- ~~OPH-077/078 (Apple EventKit) Xcode imzasına bloklu~~ — **2026-07-15'te ölçüldü: BLOKLU
  DEĞİL, not bayatmış.** `flutter doctor` tamamen yeşil (Xcode 26.2 ✓, Android SDK 37 ✓),
  `ios/Runner.xcodeproj` içinde `DEVELOPMENT_TEAM = QB8VR32GWN` + `CODE_SIGN_STYLE = Automatic`
  zaten ayarlı, provisioning profile'lar mevcut, emülatörler (Pixel 9 Pro XL, Medium Phone
  API 36.1, iOS Simulator) ve gerçek bir iPhone (iOS 26.5, kablosuz) bağlanabiliyor.
  **OPH-077/078 hemen başlanabilir.** Tek eksik: `ios/Runner/Runner.entitlements` YOK →
  Time Sensitive Notifications capability henüz eklenmemiş (Xcode'da 3 tık; macOS
  entitlement'ları zaten var). Ders: bir "bloklu" notunu devralmadan önce ölç.
- **⚠️ macOS build'i KIRIK (devralınan, OPH-077'de ortaya çıktı, 2026-07-16).**
  `flutter build macos` şu hatayla düşüyor: *"Runner has entitlements that require
  signing with a development certificate"*. **Benim değişikliğim değil** — ölçüldü:
  `macos/Runner.xcodeproj`'da `DEVELOPMENT_TEAM` HİÇ yoktu (iOS'ta 3 yerde var) ve imza
  gerektiren `com.apple.developer.usernotifications.time-sensitive` entitlement'ı Epic
  07'den beri HEAD'de duruyor → macOS zaten imzasız derlenemiyordu, kimse denememişti.
  OPH-077'de takım kimliği eklendi (`DEVELOPMENT_TEAM = QB8VR32GWN`, iOS ile aynı) ama
  YETMİYOR: makinede iPhone için sertifika var, **macOS geliştirme sertifikası yok**.
  **Kullanıcıdan gereken (küçük):** Xcode → Settings → Accounts → takım seçili haldeyken
  `macos/Runner.xcworkspace` açılıp Signing & Capabilities'te bir kez "Automatically
  manage signing" tetiklenmeli (Xcode sertifikayı kendi üretir). Sonucu: iOS derleniyor,
  macOS derlenmiyor — **OPH-077'nin Swift'i iOS build'iyle doğrulandı, macOS yolu
  (symlink + `import FlutterMacOS`) HENÜZ DERLENMEDİ.** Bloklayıcı değil (iOS ana hedef).
- ~~OPH-077 analyze koşturulmadan commit edildi~~ — **çözüldü 2026-07-16.** `build/`'i
  DOĞRUDAN sildim (`rm -rf`, `flutter clean`'i baypas), analyze 7 saniyede koştu: temiz.
  Teşhis doğruydu — 1.1 GB `build/` (harici SSD) analyzer'ı tıkıyordu, kod değil. **Ders
  (hafızaya işlendi):** üç platformu peş peşe build etme; analyze tıkanırsa önce `build/`'i
  sil. **Daha kötü bir şey de bulundu:** OPH-077 commit'i (`e3cb3ea`) **BOŞ bir Swift
  plugin dosyası** taşıyordu — önceki oturumun `git stash` kurtarması dosyayı iOS build
  GEÇTİKTEN sonra ama commit'ten ÖNCE sıfırlamıştı; analyze Swift derlemediği için
  yakalamadı. OPH-078'de yeniden yazıldı (CRUD'la birlikte) ve gerçek `flutter build ios`
  ile doğrulandı. İkinci ders: **deney için `git stash` kullanma, önce commit et.**
- **Epic 07 cihaz turu bekliyor:** exact teslim davranışı (Doze, alarm ikonu, Focus
  delme, aksiyon butonları) yalnız cihaz/emülatörde gözlenebilir — mantık katmanı tam
  unit-testli; bir Android + bir iOS/macOS cihazda NOTIFICATIONS.md senaryolarını
  koşup sonucu buraya işleyin. iOS time-sensitive capability Xcode'da eklenecek
  (pbxproj elle düzenlenmedi); Android arka-plan aksiyon isolate'i v1'de yok
  (aksiyonlar uygulamayı öne getirir).
- Web builds keep tokens in memory only (signed out after a reload) — the httpOnly
  refresh-cookie flow is the planned hardening; see OPH-025 notes in TASKS.md.

## Environment assumptions

- Node ≥ 22 (dev machine: v25), Flutter 3.44 / Dart 3.12, Docker Desktop with compose v2.
- Local infra: `docker compose up -d mysql redis` then `npm run db:migrate`.

## How to continue (for agents)

1. Read [../AGENTS.md](../AGENTS.md) §2 (protocol) if you haven't.
2. Sıradaki iş **OPH-100 — web sign-out crash** (Epic 10, TASKS.md sonu). Epic 10 sırayla
   gider: iki bug (OPH-100/101) → Home paketi (102/103/104) → küçük UI (105/106) → büyük
   akışlar (107 inbox, 108 sekme kökü, 109 README, 110 arşiv, 111 onboarding). Her task
   kendi içinde teşhis + spec + test listesi taşıyor; BLUEPRINT §12.2-12.7 ve DESIGN §4
   bağlayıcı metin. UI işlerinde kontrast bekçisi + açık/koyu tema kontrolü zorunlu
   (sert kural 11).
3. Verify (`npm run lint && npm test`, integration tests if infra up; `flutter analyze` +
   `flutter test` for app changes), document, commit, then update this file's Snapshot +
   Recently completed.

### Epic 08 gelen dikeyi devralacaklara notlar

- Politika `src/lib/inbound.js`'te SAF olarak duruyor; davranışı değiştireceksen önce
  oradaki karar tablosunu ve `test/unit/google-inbound.test.js`'in ilk describe'ını oku —
  worker sadece uygular.
- **Etag = echo anahtarı.** Giden tarafta bir yazım yapıp dönen etag'i
  `calendar_event_links.etag`'e YAZMAZSAN, o değişiklik gelen tarafta kullanıcı
  düzenlemesi sanılır ve mirror ⇄ sync döngüye girer.
- Gerçek Google CI'da YOK: her şey `test/helpers/fakegoogle.js`'e karşı koşuyor (watch/
  stop/`syncToken` feed'i/410 dahil). Sahtenin sözleşmesi Google'ın dokümante ettiği
  davranışı modelliyor — `nextSyncToken` yalnız son sayfada, iptaller feed'de.
- Webhook'u elle denemek public HTTPS ister; yerelde `GOOGLE_WEBHOOK_URL`'i boş bırak,
  süpürme yoklamayla aynı işi yapar (`app.calendarSync.sweep()`).
