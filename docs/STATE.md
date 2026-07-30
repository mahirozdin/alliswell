# STATE — Live development state

> This file is the pointer for the "do the next task" (TR: _"sıradaki işi yap"_) workflow.
> Always read it first; always update it before finishing a session. Backlog: [TASKS.md](TASKS.md).

**Last updated:** 2026-07-30 (**OPH-216 BİTTİ — beş adaptör TEK sözleşmede.** `lib/ai/providers/*` (Anthropic SSE + structured outputs; OpenAI `chat/completions` + `json_schema strict` + `include_usage`; Gemini `alt=sse` + `responseSchema`, anahtar DAİMA başlıkta; OpenRouter = OpenAI **lehçe fabrikası**, ~15 satır; Ollama **NDJSON** + tam-şema `format`), elle `lib/ai/sse.js` (SSE + JSON-lines; çok baytlı `ş` chunk sınırında bölünse de stream'li TextDecoder çözer — testte bilerek bölünüyor), `lib/ai/http.js` (el sıkışma-sonrası timeout devre dışı; retry YALNIZ gövde başlamadan — akış ortası retry kullanıcının gördüğü metni kopyalar; süreç-geneli eşzamanlılık kapısı YOK, adalet 217'nin bucket'ında), `lib/ai/models.js` (statik küratörlü katalog + Ollama canlı tags; **Gemini sohbet varsayılanı Flash** — ücretsiz katman Flash-only, 402 yiyen varsayılan yalan olur), `GET /ai/models` + `POST /ai/connections/:id/test` (dürüst `{ok:false, code}`; auth hatası satırı `error`'a çevirir). **Kodun öğrettiği iki şey:** (1) istemci kopuşu `request.raw`'ın değil **`reply.raw`'ın 'close'** olayında görünür — IncomingMessage'ın 'close'u "istek tamamlandı" demek; fakeai'nin abort sayacı 1 sn boyunca hep 0 kaldı, dinleyici değişince 57/57; OPH-217'nin gerçek SSE ucu AYNI dinleyiciyi kullanacak. (2) Hata olayları tel meselesi: adaptörler `AiProviderError` FIRLATIR, ADR-0019'un dördüncü olay adı ('error') route katmanının çevirisidir. Sözleşme süiti ×5 aynı fake'e karşı (TEK Fastify, beş yerel kodlayıcı) — iptalin upstream sokete GERÇEKTEN ulaştığı fake'in `aborted` sayacıyla kanıtlı; tel assert'leri strict/responseSchema/format/başlıkların gerçekten gittiğini sabitler. **API 480 unit (411+69) + 51 entegrasyon**, lint + format temiz. **Sıradaki: OPH-217** (`/ai/chat` SSE + hız sınırı + iptal + socket transportu).) — Önceki: 2026-07-30 (**OPH-215 BİTTİ — EPIC 20 BAŞLADI: AI temeli sunucuda.** Üç tablo: `ai_connections` (UNIQUE (workspace,user,provider) + **canlanan tombstone** — silme anahtar malzemesini NULL'lar, aynı tuple'a POST aynı satırı diriltir, calendar_accounts emsali), `ai_usage_events` (içeriksiz muhasebe, append-only), `ai_action_log` (source ENUM'u ALTI değerle doğdu — TASKS'ın dördü + quick_add/voice; ENUM genişletmek migration ister, bilinen yüzey listesi baştan tam). `AI_TOKEN_KEY` ADR-0006 kalıbının aynısı ama KENDİ anahtarı; **prod + AI_ENABLED=true (varsayılan) iken gerçek anahtar BOOT ŞARTI** — v0.9.0 deploy'undan önce prod .env'e `AI_TOKEN_KEY` + ileride `API_PUBLIC_URL` girilecek (release kontrol listesinde). `plugins/ai.js` (resolveConnection: düz metin yalnız istek yığınında; recordUsage/touchConnection fire-and-forget), `routes/ai.js` (GET status + bağlantı CRUD'u; serializer'ın anahtar türevi TEK alanı **saklanan `key_last4`** — maske için her listede decrypt etmek düz metnin maruziyetini kozmetiğe genişletirdi; create şemasında `consentAcknowledged: const true` — OPH-220'nin onam ekranı yürünmeden create'e ulaşılmaz, kalıcı sunucu izi baştan). `AI_ENABLED=false` = route'lar app.js'te hiç register edilmez → tüm `/ai/*` 404 (kapatılmış özellik hiç var olmamış gibi). **Turun iki kalıcı notu:** (1) **Sıra takası (AGENTS §2 kaydı):** TASKS 218'i (MCP) 219'dan önce sıralar ama 218'in `create_task`'ı "OPH-219'un şeması — tek kaynak" tüketiyor; şema modülünü iki fazda yazmak yerine **219, 218'den önce** koşulacak: 215→216→217→**219→218**→220…227. (2) **Bu Mac'te tam unit süiti paralel yük altında güvenilmez:** 6-7 dosyanın İLK testi (argon2 + app boot) 15 sn timeout'unu aşıyor; stash'le kanıtlandı — TEMİZ main'de de aynı dosyalar aynı şekilde kırmızı, yani ORTAM (10 çekirdekte 45 dosyalık fork fırtınası + arka plan yükü), kod değil; hakem CI. **API 411 unit (+18: 12 CRUD + 6 config) + 51 entegrasyon (+4: gerçek MySQL'de decrypt gidiş-dönüşü, beş ENUM, ER_DUP_ENTRY, tombstone canlanması)**; migration gerçek MySQL'de `db:migrate && db:rollback && db:migrate` çift yönlü yeşil; lint + format temiz; `.env.example`'a AI bölümü. **Sıradaki: OPH-216** (beş adaptör + elle SSE ayrıştırıcı + süreç-içi fakeai + model kataloğu).) — Önceki: 2026-07-29 (**ROUND 13 YAYINLANDI — v0.8.1.** Altı düzeltme
etiketlendi ve prod'a gitti; sürüm dört kaynakta `0.8.1` (pubspec `0.8.1+10`). Önceki
satır:) (**ROUND 13 — kullanıcının 6 maddelik düzeltme listesi
YAPILDI** (task numarası verilmedi, TASKS'ta Epic 19'un altında "Round 13" başlığında).
**İki maddenin kökü beklenenden derindi:** (2) dosya/klasör silme onayı **vardı**,
görünmüyordu — OPH-212 sheet'leri kök navigator'a almıştı ama `showDialog` dokunulmamıştı;
**20 dialog çağrısı** düzeltildi, yani bu sınıf hata kapandı. (6) tekrar cümlesi bayat
değildi, **kural gerçekten değişmiyordu**; artık kapsamlı bir tarih düzenlemesi deseni de
taşıyor (`ruleFollowingDay` — belirsiz kurallar hariç). Diğerleri: takvim koparma düğmesi
(Google+Apple, onaylı), geri al 5 sn → **3 sn**, kart boşlukları tek ritme (**6 px**),
arama **app bar'a** (`AwSearchAction`, Home/Notlar/Projeler; kapanış sorguyu temizler).
**App 654 test, API 393 unit + 47 entegrasyon**, tüm kapılar temiz. (Etiketlendi: **v0.8.1**.)) — Önceki: 2026-07-29 (**EPIC 19 KODSAL OLARAK KAPANDI — v0.8.0: TEKRARLI GÖREVLER
+ TAKVİM HER ZAMAN.** OPH-204…214'ün on biri de bitti; sürüm dört kaynakta **0.8.0**
(pubspec `0.8.0+9`, `kAppVersion`, iki package.json). **Turun kalıcı dersleri:**
(1) **planı kod düzeltir, tersi değil** — üç yerde: "yalnız bu" occurrence'ı DETACH
edemez (slot serbest kalır, kayan pencere ertesi gün kopyasını üretir),
`calendar_mirror_enabled` bastırma bayrağı OLAMAZ (`false` varsayılanı mevcut her
görevi bastırırdı), fikstürdeki 29 Şubat beklentim yanlıştı (kırpma kuralı gereği her
yıl üretilmeli). (2) **`findsOneWidget` bir hatayı üç tur saklayabilir** — proje sheet'i
hep ağaçtaydı, sadece DOKUNULAMIYORDU; testler artık dokunuyor ve düzeltme geri
alınınca "would not hit test" ile düşüyor. (3) **Sessizce düşen olay en pahalı hata
türü** — bildirim yanıtları tamponsuz bir broadcast'e gidiyordu ve dinleyici HomeShell
mount olana kadar doğmuyordu; `getNotificationAppLaunchDetails` ise repoda hiç yoktu.
(4) **İki uygulama tek fikstürle bağlanır** — tekrar motoru (JS/Dart) ve takvim bloğu
(sunucu/Apple) artık ADR-0013'ün fold kalıbıyla birbirine çivili. (5) **Testin tarihi
makinenin saatine bağlıysa pencere dışına düşer.** **API 390 unit + 47 entegrasyon
(gerçek MySQL), app 653 test**, analyze + i18n + kontrast (FAILURES: 0) + lint +
format + no-ts temiz; `db:rollback && db:migrate` CI sırasıyla yeşil.
**v0.8.0 CANLI (2026-07-29 13:49 UTC).** `v0.8.0` etiketi atıldı → CI kapısı yeşil →
GitHub Release (ön sürüm, `alliswell-web-0.8.0.tar.gz`) + ghcr imajları (api/web,
amd64+arm64) → **prod deploy başarılı**. Doğrulandı: `api.alliswell.space/` `0.8.0`
diyor, `/health/ready` `ok` (mysql 3 ms, redis 1 ms), `alliswell.space` 200.
**Not: v0.7.0 hiç etiketlenmemişti** — Epic 18 kodu 0.7.0 olarak CHANGELOG'a yazılmış
ama tag atılmamış; v0.8.0 onu da kapsıyor (eski etiket geriye dönük atılmadı, çünkü
sonradan atmak prod'a 0.8.0'ın ARDINDAN 0.7.0 deploy'u tetiklerdi).
**Kalan: CİHAZ DOĞRULAMASI** — OPH-214 (ekran açıkken alarm: erteleme + dokunma),
OPH-210'un canlı Google/Apple passi, ve devreden OPH-188 widget matrisi + AlarmKit turu.
**Sıradaki kod işi: Epic 20 → OPH-215** (yapay zeka).) — Önceki: 2026-07-29 (**OPH-213 BİTTİ — Home'un görünüm kontrolleri app bar'da.**
Liste|Pano `SegmentedButton` satırı ve kayan "takvimi göster" düğmesi öldü; yerine
ayarların solunda iki ikon (`buildSectionAppBar`a `trailingActions` eklendi). İkon
**geçilecek görünümü** gösteriyor (Notlar kalıbı); takvim ikonu yalnız liste
görünümünde. **Testin öğrettiği:** (1) ikon bir TOGGLE, segment idempotent'ti —
`localKv` global önbelleği yüzünden `openBoard()` bazen panodan LİSTEYE geçiyordu;
yardımcı idempotent oldu + `alliswell_home_view` temizleniyor; (2) H1 testi artık
tersini doğruluyor: toggle kaydırmayla kaybolmuyor (app bar'da), quick-add kayboluyor.
**App 650 test**, kapılar temiz. **Sıradaki: OPH-214** (cihaz taskı: ekran açıkken
alarm — ölü erteleme ikonu + dokununca çökme).) — Önceki: 2026-07-29 (**OPH-212 BİTTİ — sheet'ler yine uygulamanın ÖNÜNDE.**
**Kök neden TASKS'ın hipotezi değildi ve kanıtlandı:** `showModalBottomSheet`
`useRootNavigator` verilmeden çağrılıyordu → sheet dal navigator'ına push edilip
HomeShell'in cam çubuğu + FAB'ı altında kalıyordu. **17 çağrı yerinin hepsi** kök
navigator'a alındı. **Testin dişi:** `findsOneWidget` bu hatayı üç tur kaçırırdı (sheet
ağaçtaydı, dokunulamıyordu) — yeni test sheet'e dokunuyor ve düzeltme geri alınınca
**"would not hit test on the specified widget"** ile düşüyor. **App 649 test.**
**Sıradaki: OPH-213** (Home görünüm kontrolleri app bar'a).) — Önceki: 2026-07-29 (**OPH-211 BİTTİ — geciken grubunda üstü çizili satır kalmıyor.**
Düzeltme **tek satır**: `_completedSince`e vade sınırı (`dueAt IS NULL OR dueAt >=
günBaşlangıcı`). `watchOpen` + `watchProjectTasks` aynı `_watchList`ten geçtiği için
ikisi birden düzeldi; **grup sayaçları ve widget bedavaya doğru oldu** — satır listeye
hiç girmediği için sayılmıyor da. 5 yeni sorgu testi (dün vadeli+tamamlanan listede YOK
arşivde VAR; bugün vadeli KALIR = OPH-185 regresyonu; tarihsiz KALIR; proje listesi aynı;
gece yarısında bugünkü de düşer). **App 648 test**, kapılar temiz.
**Sıradaki: OPH-212** (proje düzenle sheet'i menünün altında).) — Önceki: 2026-07-29 (**OPH-210 BİTTİ — TAKVİM HATTI KAPANDI: her görev takvimde,
seçenek yok.** Switch silindi (app + i18n anahtarları), blok kuralı yazıldı (scheduled →
30 dk → **gece yarısı kenetlemesi** 23:59 → 23:29–23:59 → tarihsiz **ekleniş günü**),
tamamlanan görevin bloğu **kalıyor ve `✓` alıyor** (iptal/arşiv hâlâ siliyor), backfill
**-30g → +12ay** penceresi, `lib/google.js`'e **429/Retry-After + eşzamanlılık kapısı**
(backfill'den ÖNCE, ADR-0021 §5), bağlantı kartına onam cümlesi.
**Planın düzeldiği yer:** `calendar_mirror_enabled`i bastırma bayrağına çevirmek
**imkânsızdı** — kolon `false` varsayılanlı, anlamı ters çevrilse MEVCUT HER GÖREV
bastırılmış olurdu; yeni nullable kolon `calendar_mirror_suppressed_at` geldi (tek yazan
`lib/inbound.js`), eskisi ölü ama yerinde (append-only). **İki ayna tek fikstürle
bağlandı** (`calendar_block_parity.json`, 7 vaka, iki süit). Mirror/inbound süitlerindeki
**8 eski beklenti** yeni kurala çevrildi ve nedenleri yorumda. **API 390 unit + 47
entegrasyon** (gerçek MySQL'de `✓` bloğu ve iptalde silinme kuyruktan uçtan uca),
**app 643 test**, tüm kapılar temiz. Canlı Google/Apple passi cihaz kuyruğunda.
**Sıradaki: OPH-211** (geciken grubunda tamamlanmış satır kalmaz).) — Önceki: 2026-07-29 (**OPH-209 BİTTİ — takvim aynasının şekli karara bağlandı,
kod yazılmadı.** [ADR-0021](adr/0021-calendar-mirror-v2.md). **Kullanıcının bana bıraktığı
karar: todo eşlemesi REDDEDİLDİ** — Google Tasks API'si `due`'nun SAATİNİ atıyor
(*"It isn't possible to read or write the time that a task is scheduled for using the
API"*), oysa AllisWell'in her görevinin bir saati var (varsayılan 23:59, alarm o saatte,
30 dk blok ondan türüyor); üstelik Tasks'ın **watch kanalı yok** (Calendar/Gmail/Drive'ın
var), Apple EKReminder ise **ayrı izin + cihaz-yerel**. Yani event bloğu bir taviz değil,
**saati koruyan tek temsil**; yeniden değerlendirme koşulu ADR'de yazılı. Sabitlenenler:
switch ölür ama **kolon makine bastırma bayrağı olarak kalır** (inbound'un "kullanıcı
Google'da sildi" dalının tek kayıt yeri — kolonu silmek o dalı sessizce yalancı yapardı);
tamamlanan görevin bloğu **kalır + `✓`**; backfill **-30 gün → +12 ay**; **429/Retry-After
+ eşzamanlılık tavanı backfill'den ÖNCE**. **Sıradaki: OPH-210** (aynanın kodu).) — Önceki: 2026-07-29 (**OPH-208 BİTTİ — TEKRAR HATTI KAPANDI (204→208).** Rozet
satırda ve tamamlanınca kalkıyor; create sheet'in switch'i geldi (**kaydet → seri kur**);
silmede **iki seçenekli** kapsam sorusu var — "Tümü" bilinçli olarak YOK, çünkü geçmiş
ve tamamlanmış occurrence'lar tarihtir; "bu ve gelecektekiler" seriyi **kaydırılan
occurrence'ın gününden** durduruyor (`?fromDay=`), bugünden değil. **Zaman dilimi artık
sunucudan geliyor** — istemci IANA adını bilmiyor (cihaz "+03" der), `timezone` isteğe
bağlı oldu ve sunucu kullanıcı profilinden dolduruyor. **Yüzeyler ölçüldü:** widget
`openToday`, widget kovaları, ay takvimi noktası, Home gruplaması, arama fold'u — beşi de
occurrence'ı sıradan görev gibi işliyor (ADR-0020 §4'ün bahsi tutuyor). README'ye tekrar
bölümü, ROADMAP Phase 13 "in progress". **API 386 unit + 47 entegrasyon, app 641 test**,
analyze + i18n + kontrast + lint + format temiz. **Sıradaki: OPH-209** (takvim
araştırması + ADR-0021 — kod yazmaz).) — Önceki: 2026-07-29 (**OPH-207 BİTTİ — tekrar artık EKRANDA.** drift **v14**
(`TaskSeries` + `Tasks.seriesId`/`occurrenceDate`, `from >= 1` guard'ı; migration testi
v1→v14 gerçek SQLite'ta), `core/recurrence.dart` **paritede** (fikstürün 16 vakası iki
süitte de yeşil), `core/recurrence_text.dart` (TR/EN kural bazlı cümle; senaryo C
saklanmıyor **tanınıyor** — `awAfterDayOf`), `repeat_dialog.dart` (preset + Gelişmiş +
"Sonraki 5"), `repeat_row.dart` (switch → dialog otomatik, özet + Değiştir, Tekrarı
durdur) ve **kapsam dialog'u** (varsayılan "bu ve gelecektekiler"; tarih düzenlemesinde
"yalnız bu"), `series_store.dart` (kural local-first, occurrence'lar sunucudan).
**Kodun öğrettikleri:** (1) detay sütunu uzayınca `date_input_test`'in iki dokunuşu
telefon ekranının ALTINA düştü — testler artık `ensureVisible`; (2) **cümle uygulamanın
diline uyar**, `locale` parametresi yalnız tarihi biçimlendirir (i18n cephesi global);
(3) dialog **kök navigator'a** açılıyor — OPH-212'nin dersi peşinen uygulandı;
(4) `RadioListTile.groupValue` deprecated → `RadioGroup` sarmalayıcısı. Create sheet'in
switch'i **OPH-208'e** kaldı (sheet henüz kaydedilmemiş görevle çalışıyor, seri
`fromTaskId` istiyor). **App 635 test**, analyze + i18n + kontrast + format temiz.
**Sıradaki: OPH-208** (rozet, yüzey testleri, silme akışları, README).) — Önceki: 2026-07-29 (**OPH-206 BİTTİ — kapsam sorusunun motoru hazır: bu /
bu ve gelecektekiler / tümü.** `seriesScope` hem REST `PATCH /tasks/:id`'de hem sync
push'ta **virtual alan** olarak taşınıyor (yeni fiil İMKÂNSIZ — ENUM + `default:`
dalı `applyDelete`; `orderedIds` emsali), propagasyon `db/task-series.js`
`propagateSeriesScope`'ta tek transaction'da. **Kodun düzelttiği plan:** "yalnız bu"
DETACH ETMİYOR — `series_id`'yi null'lamak `(series_id, occurrence_date)` **slot'unu**
serbest bırakıyor ve bir sonraki süpürme aynı güne ikinci satır üretiyor; doğrusu
Google'ın "değiştirilmiş instance"ı: satır seride kalır, `occurrence_date` slot'u
tutar, `due_at` gerçeği söyler (ADR-0020 sonuçlarına + DESIGN §25 R8'e işlendi).
İkinci karar: `future`/`all` kapsamlı bir **tarih** düzenlemesi günleri değil **günün
saatini** taşır (günler kuralın işi). Bölünme: eski seri `rule.end.until` alır, yeni
seri doğar, **düzenlenen satır id'sini koruyarak** yenisine geçer (kullanıcının
baktığı görev altından değişmez). **API 385 unit + 47 entegrasyon.**
**Sıradaki: OPH-207** (app: drift v14 + `core/recurrence.dart` portu + parite
fikstürü + tekrar dialog'u + kapsam dialog'u).) — Önceki: 2026-07-29 (**OPH-205 BİTTİ — tekrar motoru ve materyalizasyon CANLI
(sunucu tarafı).** `task_series` + `tasks.series_id`/`occurrence_date` migration'ı gerçek
MySQL'e uygulandı ve `db:rollback && db:migrate` ile geri alınıp yeniden koştu. Yeni:
`src/lib/recurrence.js` (saf motor, 16 vakalık parite fikstürü), `src/db/task-series.js`
(materyalizasyon + kapsam yardımcıları), `routes/task-series.js` (CRUD),
`plugins/series-gc.js` (günlük süpürme), sync'te `task_series` varlığı.
**Kodun öğrettikleri:** (1) **fikstür kendi kararımı düzeltti** — "29 Şubat yıllık kural"
vakasını artık-yıl-only yazmıştım, motor kırpma kuralı gereği her yıl üretti; doğrusu
motorunki (leap-day görevi dört yıl kaybolmaz), fikstür düzeltildi ve karar artık testte
yazılı; (2) **`tasks.repeat_rule` ölü değil CANLI'ydı** — REST+sync yazıyor,
`db/reminders.js` reminder'a kopyalıyordu; yazma yollarından çıkarıldı (ADR-0020 §7);
(3) fakedb'de `.select()` olmadan sorgu iterable dönmüyor (süpürme ilk koşuda patladı);
(4) pull değişikliğinin alanı `snapshot` değil **`data`**; (5) **testin tarihi makinenin
saatine bağlıysa pencere dışına düşer** — seri testleri artık `today()`e göreli ve
`timezone: 'UTC'`. **Üç sapma** (gerekçeleri ADR-0020 + TASKS'ta): süpürme repeatable
değil ev kalıbı `setInterval`; bitiş koşulu ayrı kolon değil `rule.end`; `template` JSON
kolonu eklendi. **API 374 unit + 47 entegrasyon** (gerçek MySQL'de JSON gidiş-dönüşü,
DATE kolonu, tekil indeksin kopyayı reddedişi), lint+format temiz.
**Sıradaki: OPH-206** (kapsam semantiği: bu / bu ve gelecektekiler / tümü —
`seriesScope` virtual alanı, yeni sync fiili İMKÂNSIZ).) — Önceki: 2026-07-29 (**OPH-204 BİTTİ — tekrar sisteminin kuralı yazıldı, kod
yazılmadı.** Kaynaklı tur (RFC 5545, RFC 7529, Google Calendar, Outlook, Todoist,
TickTick, Apple Reminders) TASKS'ta iki tabloya işlendi; kararlar
[ADR-0020](adr/0020-recurring-tasks-and-materialization.md) + **DESIGN §25**.
**Turun üç bulgusu:** (1) "atla" ile "kırp" bir standart değil **ürün** tercihi —
aynı niyet Google'da Şubat'ı atlıyor ("MUST be ignored"), Outlook'ta ayın son gününe
çekiliyor; görevde "31'i" **ay sonu** demek olduğu için KIRPMA seçildi ve
`byMonthDay:[-1]` birinci sınıf değer oldu; (2) senaryo C ("22'sinden sonraki ilk
Pazartesi") **yeni alan istemiyor** — RFC 5545 `BYDAY`i `BYMONTHDAY`in sınırlayıcısı
yapıyor ve spec'in kendi örneği aynı 7 günlük pencere deyimini kuruyor, yani motor üç
ilkelle yetiniyor; (3) **kırpılmış bir kural Google'a tekrar eden etkinlik olarak
anlatılamaz** (`SKIP` `RSCALE`siz yasak, Google böyle kuralı düzenlemiyor) → bu,
materyalizasyonun bağımsız ikinci gerekçesi. Ayrıca iki sapma yazıldı: günlük süpürme
**BullMQ repeatable değil** ev kalıbı `setInterval+unref+decorate` (runner'da repeatable
API'si yok, Redis'siz self-host şart, çok replikada güvenlik jobKey+idempotens'ten
geliyor) ve **`tasks.repeat_rule` donduruluyor** — ölü değil CANLI ama ulaşılamaz bir
yoldu (REST+sync yazıyor, `db/reminders.js:101` reminder'a kopyalıyor), yazma
yollarından çıkıyor. Zaman dilimi işi bedava: `zonedWallTimeToUtc` + `tasks.timezone`
zaten var, motor onları kullanacak. **Sıradaki: OPH-205** — `task_series` migration'ı,
saf JS motoru, +12 ay materyalizasyon ve günlük süpürme.) — Önceki: 2026-07-29 (**EPIC 18 KAPANDI — v0.7.0: HIZLI ERİŞİM CANLI.**
OPH-196…203'ün sekizi de bitti. Kullanıcının cümlesi ("Notion'daki sol menü gibi… mobilde
o beyaz nokta gibi") üç yüzey olarak karşılandı: extended rail bölümü, dar-rail popover'ı,
telefonda sürüklenen düğme + panel — **üçü de tek store'u aynı sırayla okuyor** (DESIGN
§23 Q1). `quick_link` protokolün **ilk kullanıcı-kapsamlı varlığı**: workspace'te duruyor,
pull yalnız sahibine veriyor, hedef silinince sunucu aynı transaction'da kaskad ediyor,
arşiv dokunmuyor. **Turun kalıcı dersleri:** (1) **sayılar kaynaktan gelir, tahminden
değil** — boşta soluklaşma %55 tahminiydi, AssistiveTouch'ın belgeli varsayılanı **%40**;
(2) **bir kural başka bir kuralı ihlal edebilir** — "56 px hedef" ile "kenara yarı gömül"
aynı anda doğru olamazdı, çözüm gömülmeyi BOYAYA indirmekti (Q4a); aynı şekilde "palet
birebir" ile "3:1 kontrast" ancak **halka** ile birlikte doğru (Q8a: 10 renkten 5'i düz
dolguda geçmiyor); (3) **protokol sınırları kodda yazılıdır** — sıralama için yeni bir
`operation` fiili ENUM'lara takılıyor ve dispatch'in `default:` dalı onu **applyDelete'e**
düşürüyordu; çözüm virtual alan; (4) **ownership'i `guard`a koymak sessiz bir güvenlik
boşluğuydu** (`applyDelete` `guard` çağırmıyor) ve `!(await …)` bir kod dizesini geçiriyordu;
(5) **testlerin bulduğu beş gerçek hata**: iki dialog'un controller'ı rota kapanırken
dispose ediliyordu, `mailto:` adresine `https://` ekleniyordu, FakeApi id'leri `padRight`
yüzünden çakışıyordu (50 satır 46 oluyordu) ve FakeApi `quick_link` push'unu hiç
uygulamıyordu (silinen satır pull'da geri geliyordu). **App 603/603, API 323 unit + 43
entegrasyon** (gerçek MySQL'de iki üyeli izolasyon dahil), analyze + i18n + kontrast + lint
+ format + no-ts temiz. **Sürüm 0.7.0** dört kaynakta (pubspec `0.7.0+8`, `kAppVersion`,
iki package.json), drift **v13**, bir migration. **Sıradaki: Epic 19 → OPH-204** (tekrarlı
görevler; round 12'de araya girdi). Cihaz kuyruğu değişmedi: OPH-188 widget matrisi +
AlarmKit turu hâlâ kullanıcıda.) — Önceki: 2026-07-29 (**OPH-202 BİTTİ — emoji, renk, ad.** Emoji sheet'i
(son kullanılanlar + ~48'lik ızgara + serbest alan; **paket yok**), renk sheet'i
(proje paletinin 10 rengi + "renk yok"), ad dialog'u ve "hedef adını al".
**Kararlar/dersler:** (1) `_ColorSwatchDot` `widgets/color_swatch_dot.dart`e taşındı
(`AwColorSwatchDot`) — bir özelliğin başka özelliğin sheet dosyasından widget alması
ev düzenine aykırıydı; (2) kısayolda **yalnız 10'luk palet**: `_ColorGridDialog`ın
sınırsız seti park, çünkü sınırsız fille halka bile kontrastı garanti edemez (Q8a);
(3) kural "tek grafem", "emoji mi" DEĞİL — paketsiz emoji sınıflandırması bayrakları
ve ZWJ ailelerini reddeder; testte açıkça yazılı; (4) **OPH-199'un rename dialog'unda
aynı controller-dispose hatası bulundu** (route kapanma animasyonundayken alan rebuild
oluyor) → artık dialog kendi controller'ının sahibi. **App 595/595** (+8), tüm kapılar
temiz. **Sıradaki: OPH-203** (kırık/arşivli hedef, çevrimdışı link, sürüm dokunuşları,
epic kapanışı → v0.7.0).) — Önceki: 2026-07-29 (**OPH-201 BİTTİ — kısayollar artık nesnenin yanında doğuyor.**
Proje (liste+detay), not (liste/ızgara/editör), görev detayı, klasör ve dosya sheet'lerinde
`bolt` maddesi; ekliyse metin "kaldır" oluyor — **ikinci kez ekleme diye bir yol yok**.
Rail/popover/panel'in "+" düğmeleri dış link dialog'unu açıyor (şemasız girdi `https://`,
açılamayacak adres sesli reddediliyor, boş ad → host). **Testin bulduğu ÜÇ gerçek hata:**
(1) dialog controller'ları `showDialog` döner dönmez dispose ediliyordu — rota hâlâ
kapanma animasyonundayken alanlar rebuild oluyor ("A TextEditingController was used after
being disposed") → dialog kendi controller'larının sahibi oldu; (2) `quickLinkUri` şemalı
girdiye de `https://` ekliyordu: `mailto:a@b.c` → `https://mailto:a@b.c` KABUL ediliyordu →
şema varsa olduğu gibi değerlendiriliyor; (3) FakeApi'nin id üretimi
`'QCK1'.padRight(26,'0')` ile `'QCK10'.padRight(26,'0')`i aynı dizeye çeviriyordu, 50
tohumlanan satırın yalnız **46**'sı replikaya iniyordu — 50 limiti testi bunu yakaladı →
`padLeft`. Dosya maddesi `showFileActionsSheet`in İÇİNE kondu: beş çağıran tek düzenlemeyle
kazandı. **App 587/587** (+6), analyze + i18n + kontrast + format temiz.
**Sıradaki: OPH-202** (emoji, renk, ad).) — Önceki: 2026-07-29 (**OPH-200 BİTTİ — telefonda yüzen düğme + panel canlı.**
Düğme `MaterialApp.builder` katmanında (rota İÇİ bir Stack `/tasks/:id` ve `/settings`
üstünü örterdi), sürüklenip en yakın kenara yapışıyor, konum cihaz-yerel kalıcı, 3 sn
boşta **%40**'a soluklaşıp kenara yarı gömülüyor — **yalnız boya**, kutu 56 px kalıyor
(testte `getSize` ile doğrulanıyor). **Kodun öğrettikleri:** (1) rota-farkındalık
DENENDİ ve GERİ ALINDI — `MaterialApp.builder` içinden router delegate'ini dinlemek
router'ın kendi build'i sırasında rebuild demek (`'!_dirty': is not true`) ve
`GoRouter.state` ilk karede `Bad state: No element` atıyor; auth ekranlarının tanımı
zaten "oturum yok" olduğundan kapı **oturuma** bağlandı — daha az kod, aynı davranış;
(2) modal gizlemesi tek kök `NavigatorObserver` (`PopupRoute` sayan `AwModalRouteObserver`,
`ValueNotifier` çünkü `didPush` build sırasında ateşleyebilir) ve test hem `showDialog`
(root navigator) hem panelin kendisiyle kanıtlıyor — go_router kök observer'ı branch
navigator'lara merge ettiği için tek kayıt yetiyor; (3) builder katmanının `Navigator` ve
`Overlay` atası YOK → panel `awRootNavigatorKey.currentContext` ile açılıyor, tanıtım
ipucu `Tooltip` olamıyor (kendi balonu); (4) sürükleme testi `startGesture`+`moveBy`
ister — tek `drag()` pan tanıyıcıyı ara karesiz bırakıyor. Ayarlar'a anahtar (fabrika
açık), kapalıyken Home app bar'ında `bolt` girişi (jest asla tek yol değil). Yan etki:
Ayarlar listesi bir satır uzayınca `completed_screen_test`in yardımcısı ekran dışındaki
satıra dokunuyordu → `scrollUntilVisible`. **App 581/581** (+19), analyze + i18n +
kontrast + format temiz. **Sıradaki: OPH-201** (her varlık menüsüne "Hızlı erişime ekle"
+ dış link dialog'u).) — Önceki: 2026-07-29 (**OPH-199 BİTTİ — geniş ekranda "Hızlı erişim" bölümü
canlı.** Extended rail'de (≥1160) başlık + katlama + sürükleyerek sıralama; dar rail'de
(800–1160) tek `bolt` düğmesi + çıpalı popover; ikisi de aynı store'u aynı sırayla okuyor.
**Kodun öğrettiği iki tuzak:** (1) `MenuAnchor` menüsünün **intrinsic yüksekliğini ölçüyor**
— shrink-wrap eden bir liste bunu cevaplayamaz ("RenderShrinkWrappingViewport does not
support returning intrinsic dimensions") → popover sabit yükseklik alıyor; (2) iç liste
`PrimaryScrollController`'ı popover paneliyle paylaşınca Scrollbar assert'i patlıyor →
`primary: false`. Ayrıca kırılımlar token'a taşındı (`kAwWideBreakpoint` /
`kAwExtendedRailBreakpoint`) ve bölüm `NavigationRail.trailing`'te duruyor — destination
OLSAYDI `selectedIndex` ↔ `AppSection.values` eşlemesi bozulurdu. **Gezinme tablosu da bu
turda yazıldı** (satır tıklaması olmadan yüzey yarım kalırdı): saf `quickDestinationFor` +
tek `openQuickDestination`; klasör için **yeni rota** `/files/folder/:folderId`
(`FilesScreen.initialFolderId` breadcrumb'ı replikadan kuruyor — sekmeye basınca
`goBranch(initialLocation: true)` konumu sıfırlasın diye provider değil ROTA), dosya için
rota değil `showFileActionsSheet`. OPH-203 bu tabloyu devralıyor (kırık/arşivli/çevrimdışı
+ sürüm dokunuşları). `quick.*` i18n (en+tr, 33 anahtar) + `settings.quickBubble`,
kontrast listesine halka çiftleri (FAILURES: 0), `extraction_test`'e quick grubu.
**App 562/562** (+6). **Sıradaki: OPH-200** (telefonda yüzen düğme + panel).) — Önceki: 2026-07-29 (**OPH-198 BİTTİ — kısayollar cihazda: drift v13 +
`QuickAccessStore`.** Replika tablosu, applier'ın üç kaydı, `currentUserIdProvider`
(`AuthUser.id`'nin ilk çağıranı — Quick Access kullanıcı-kapsamlı olduğu için ilk ihtiyaç
duyan özellik), store (add/rename/emoji/renk/kaldır/reorder) ve dört store'un silme yoluna
yerel kaskad. **Kararlar:** (1) `userId` **wire'a girdi** — sunucu zaten yalnız sahibinin
satırlarını yolluyor ama replika oturum kapanışını hayatta kalıyor, bu yüzden `watchMine`
yerelde de süzüyor; (2) rail tek `customSelect` + beş LEFT JOIN — `readsFrom` seti eksik
olsaydı hedef yeniden adlandığında liste **sessizce donardı** (testi var: proje adı
değişince satır canlı güncelleniyor ama kısayolun ADI değişmiyor, fark "hedef adını al"
için işaretleniyor); (3) aynı hedefi ikinci kez eklemek yeni satır değil MEVCUT id —
menü toggle'ının doğru davranışı; 50'de `null` döner (çevrimdışı dürüstlük);
(4) `reorder` **tek** mutasyon (anchor = listenin başı, patch `{orderedIds}`) —
sunucunun virtual alanıyla birebir; (5) `forgetQuickLinksFor` serbest fonksiyon:
görev/proje/not/klasör store'ları kendi silme transaction'ından çağırıyor ve **outbox'a
hiçbir şey yazmıyor** — sunucu kaskadı zaten duyuruyor, ikinci bir delete "kullanıcı
kaldırdı" yalanı olurdu. **App 556/556** (+12), analyze + i18n + kontrast (FAILURES: 0) +
`dart format` temiz. **Sıradaki: OPH-199** (geniş ekranda rail bölümü + dar rail
popover'ı).) — Önceki: 2026-07-29 (**Feedback round 12 → Epic 19 doğdu ve ARAYA girdi;
yapay zeka Epic 20'ye kaydı (OPH-215…227, Phase 14, v0.9.0 — içerik değişmedi,
MCP/STT ADR'leri 0022/0023'e kaydı; AI.md + ADR-0019 çaprazları güncel).** Mahir'in
6 maddesi → **11 task (OPH-204…214, Phase 13, v0.8.0)**; kalıcı dokümanlar YAZILDI —
kod yazılmadı; Epic 18 implementasyonu paralelde akmaya devam ediyor.
**(1) Tekrarlı görevler (204…208):** v1'den beri boş duran `repeat_rule` parkı bitti —
RFC 5545 alt kümesi + RFC 7529 kırpma semantiği, yapılandırılmış JSON kural
("her ayın 31'i" kısa ayda son güne çekilir; "ayın 2. Salı'sı"; "22'sinden sonraki
ilk Pazartesi" — üçü birinci sınıf); switch → **otomatik dialog** + özet + Değiştir;
"Sonraki 5" canlı önizleme (Dart portu + JS motoru **ortak parite fikstürleri** —
fold kalıbı); **materyalizasyon kararı bana bırakılmıştı, verildi (ADR-0020'ye):**
occurrence'lar gerçek görev satırı, **+12 ay kayan pencere**, günlük süpürme
kaydırır ("biri geçince sıradaki eklenir"), istemci/widget/alarm/arama tekrar
kavramını HİÇ bilmez; düzenleme kapsamı Google modeli — varsayılan **"bu ve
gelecektekiler"** (kullanıcının kuralı), tarih kaydırma istisnası "yalnız bu";
≥3 ürün incelemesi 204'ün şartı (Google Calendar/Todoist/TickTick; Mahir:
"bastırıyorum bir daha"); README'ye örnekli tanıtım + senaryolu liste SC'si (208).
**(2) Takvim aynası seçeneksiz (209…210):** kanıt — mirror `calendar_mirror_enabled`
opt-in ([mirror.js:16](../apps/api/src/lib/mirror.js#L16)) + §7.1'in scheduled/urgent
şartı → sıradan tarihli görev takvime HİÇ gitmiyordu; **§7.1 yeniden yazıldı:**
tarihli her görev 30-dk blok (gece yarısına kenetleme → 23:59/saatsiz **23:29–23:59**),
tarihsiz görev **ekleniş gününe**, `scheduled_*` önceliği (OPH-192) korunur; switch +
`task.showInCalendar*` ölür (hiçbir yerde seçenek yok); **Google Tasks / Apple
Reminders (EKReminder) birebir todo eşlemesi** 209'da değerlendirilir (Mahir:
"destekliyorsa direkt öyle"); backfill + kota stratejisi ADR-0021'e; canlı
Google/Apple passi cihaz kuyruğuna. **(3) Geciken×tamamlanan (211):** 28 Tem vadeli
görev 29'unda tamamlanınca gün sonuna kadar "Geciken"in altında üstü çizili
duruyordu — OPH-185'in "kendi grubunda kalır" kuralının birebir sonucu; kural revize
(BLUEPRINT §12.2 + DESIGN §20 C1): kalıcılık YALNIZ bugün-vadeli/tarihsiz;
**vadesi geçmiş tamamlanan anında arşive düşer**. **(4) Sheet z-order (212):**
[projects_screen.dart:192](../apps/app/lib/src/features/projects/ui/projects_screen.dart#L192)
`onSelected` içinde senkron `showProjectEditSheet` — menü kapanmadan sheet açılıyor;
düzeltme tek kalıp + aynı hatanın repo taraması; Mahir SC gönderecek (bloklamaz).
**(5) Home görünüm kontrolleri app bar'a (213):** Liste|Pano SegmentedButton satırı
([home_screen.dart:146](../apps/app/lib/src/features/home/home_screen.dart#L146)) ve
takvim gizle düğmesi ölür → Notlar'ın app bar ikon kalıbı, ayarların solunda;
DESIGN §16 H1 güçlendi, H3 sapması kendiliğinden çözüldü. **(6) Ekran açıkken alarm
(214, cihaz):** heads-up'taki saat ikonu (erteleme?) ÖLÜ + bildirime dokununca
uygulama açılırken ÇÖKÜYOR (ekran kapalıyken tam ekran doğru); kök neden 214'te —
aksiyon kablolaması ([actions.dart](../apps/app/lib/src/notifications/actions.dart))
+ launch payload; alarm günlüğü (OPH-176) kanıt kaynağı. Revize edilen kalıcı
metinler: BLUEPRINT §7.1 (yeni ayna kuralı) + §12.2 (round 12 #3/#5 rev'leri) +
§12.4 (switch ölümü) + **§12.17 yeni** + §14 Phase 13/14 + §16 **Risk 10** + §18;
DESIGN §16 H1/H3 + §20 C1 rev; ROADMAP Phase 13 yeni + Phase 14 kaydırma; TASKS
park kuyruğu (tekrar parkı kapandı). **Sıra değişmedi: Epic 18 akıyor (196–197
bitti, sırada 198) → Epic 19 (204) → Epic 20 (215).**)
— Önceki: 2026-07-29 (**OPH-197 BİTTİ — `quick_link` sunucuda yaşıyor:
protokolün ilk KULLANICI-KAPSAMLI varlığı.** Migration + `db/quick-links.js` +
`routes/quick-links.js` (5 uç) + push/pull kaydı + beş silme yolunda kaskad.
**Kodun kendi öğrettikleri:** (1) `ownershipOk` bir kod dizesi dönerse eski
`!(await …)` kontrolü onu **sessizce geçiriyordu** — `checkOwnership` yazıldı,
`false` yine `SYNC_ENTITY_NOT_FOUND`; `applyDelete` `guard`'ı hiç çağırmadığı için
sahiplik oraya konmak ZORUNDAYDI (testi de var: başkasının kısayolunu push'la
silmek `QUICK_LINK_NOT_YOURS`); (2) sıralama yeni bir `operation` OLAMAZ —
`sync_revisions`/`client_mutations` ENUM'ları ve pull şeması üç fiile kilitli,
üstelik dispatch'in `default:` dalı bilinmeyen fiili applyDelete'e düşürüp
**anchor'ı silerdi**; çözüm `update` + virtual `orderedIds` (`col:'sort_order'`),
N satır → N revision, `client_mutations` anchor'ı kaydeder, hepsi tek transaction;
(3) pull'da yalnız loader'ı süzmek başkasının ULID'lerini **tombstone olarak**
sızdırıyordu → `userScoped` işareti + `invisible` düşürmesi; kürsör güvenli
(`toRevision` ham pencereden) ve testi var: değişiklik yok ama `toRevision` ilerliyor;
(4) bu düşürme yalnız kısayollar **soft** silindiği sürece doğru → her silme
`deleted_at` + `target_id = NULL` (slot serbest, hedef yeniden eklenebilir);
(5) Fastify Ajv'si bilinmeyen gövde anahtarını reddetmiyor **siliyor** → "hedefi
değiştir" denemesi boş patch olarak geliyordu, sessiz 200 yerine
`QUICK_LINK_EMPTY_PATCH`; (6) dosya kısayolu `softDeleteReadyFile` boğazından,
klasör kısayolu `deleteFolderSubtree`'den kaskad ediyor — REST + push tek yoldan,
altı çağrı yerine iki. **API 323 unit (+31) + 43 entegrasyon (+4, gerçek MySQL'de
iki üyeli izolasyon dahil), lint/format/no-ts temiz.** **Sıradaki: OPH-198**
(drift v13 + `QuickAccessStore`).) — Önceki: 2026-07-29 (**EPIC 18 BAŞLADI —
OPH-196 BİTTİ: araştırma pası üç sayıyı değiştirdi.** Kaynaklı tur (AssistiveTouch, Messenger chat heads, Material FAB,
Notion/Slack sidebar, erişilebilir sıralama literatürü) TASKS OPH-196 altına iki tabloyla
işlendi. **DESIGN §23'te değişenler:** (1) boşta soluklaşma **%55 → %40** — Apple'ın kendi
varsayılanı ("fades to 40 % opacity a few seconds after you stop using it"), yani "iPhone'un
o beyaz noktası" isteğinin gerçek sayısı; (2) **Q4a** yarı gömülme artık YALNIZ BOYA —
56 px'lik kutuyu kaydırmak dokunma hedefini 28 px'e düşürüp §5'i ihlal ediyordu, o yüzden
kutu sabit, daire kayıyor; (3) **Q4b** %40 soluklaşma §20 C3'ün (`Opacity` yasağı) yazılı
istisnası olarak tanımlandı; (4) **Q4c** bubble bir FAB DEĞİL (Material: ekran başına tek
FAB, o da sağ-alttaki oluşturma FAB'ı); (5) **Q8a** renk noktası dolgu + **1 px `outline`
halkası** — ölçüldü: 10 paletten 5'i açık temada 3:1'i geçmiyor (#F59E0B 2.15, #14B8A6 2.49,
#10B981 2.54, #0EA5E9 2.77, #F97316 2.80) ve proje rengi paletle sınırlı bile değil, halka
WCAG 1.4.11'in ölçtüğü sınırı taşıyor; (6) **Q9** sürükleme asla tek sıralama yolu değil
(satır menüsünde yukarı/aşağı taşı). **ADR-0018'e iki sonuç eklendi** (süpersede değil,
aynı kararın uygulama detayı): pull filtresi İKİ yerde olmak zorunda — yalnız loader'da
süzmek başkasının ULID'lerini tombstone olarak sızdırır; ve bu düşürme yalnız kısayollar
**soft** silindiği sürece doğru (hard delete sahibin kendi tombstone'unu yutardı).
**BLUEPRINT §4.12 düzeltildi:** `color` → `color_rgb`, emoji sınırı bayt değil **karakter**
(bir aile emojisi tek grafem ama 25 bayt). Park listesi altı yeni gerekçeyle kesinleşti.
**Sıradaki: OPH-197** (API: `quick_links` migration + CRUD + sync varlığı).) — Önceki:
2026-07-29 (**İstek turu 11 → Epic 18 + Epic 19 doğdu: Hızlı Erişim
ve Yapay Zeka (Phase 12 v0.7.0 + Phase 13 v0.8.0). Kalıcı dokümanlar YAZILDI — kod
yazılmadı; implementasyon OPH-196'dan başlıyor.** Mahir'in iki maddesi → **21 task
(OPH-196…216)**. **#1 Hızlı Erişim (Epic 18, OPH-196…203):** Notion tarzı **kişisel**
kısayol listesi (proje/görev/not/klasör/dosya/dış link; emoji + renk + elle sıra; 50
sınırı); geniş ekranda rail bölümü, dar rail'de popover, telefonda **AssistiveTouch
tarzı sürüklenen yüzen düğme** (kenara yapışır, boşta yarı gömülür, modal açıkken
gizlenir; Ayarlar anahtarı + app bar `bolt` girişi — jest asla tek yol değil, D2);
**ilk kullanıcı-kapsamlı senkron varlık** `quick_link` (workspace'te saklanır, pull
yalnız sahibine — [ADR-0018](adr/0018-quick-links-user-scoped-sync-entity.md)); hedef
hard-delete'inde sunucu kaskadı, arşiv dokunmaz; `kind+target_id` saklanır, rota
dizesi asla (ADR-0016 korunur). **#2 Yapay Zeka (Epic 19, OPH-204…216):** fikir önce
**maksimum-efor araştırma ajanına** verildi (Mahir'in isteği); ajanın doğrulanmış ana
bulgusu: **istenen "API key'siz abonelik bağlama" üç sağlayıcıda da üçüncü partiye
KAPALI** (Anthropic Şub 2026'da yazılı politikayla yasakladı; Google Mar 2026'dan beri
ücretli kullanıcı dahil hesap kapatıyor; OpenAI ilgi-formu önizlemesinde) — Mahir'in
Cloudflare/Notion'da gördüğü deneyim **ters yön**: kendi hesabına MCP bağlayıcısı
eklemek. Plan **iki hat** ([ADR-0019](adr/0019-ai-provider-architecture.md) +
**[AI.md](AI.md)** — kanıt linkleri orada): **Hat A** AllisWell uzak MCP sunucusu
("Claude'una/ChatGPT'ne ekle" — dürüst "aboneliğinle çalışır" hikâyesi; her self-host
instance kendi bağlayıcı URL'i; alliswell.space iki dizine başvurur) + **Hat B**
uygulama içi **BYOK** (beş fetch adaptörü: Anthropic/OpenAI/Gemini/OpenRouter/Ollama;
SDK yok; anahtarlar ADR-0006 kalıbıyla şifreli, yeni `AI_TOKEN_KEY`; `auth_mode`'da
rezerve `oauth_subscription` — program açılırsa şemasız oturur). Yüzeyler: SSE akışlı
bubble (web'de Socket.IO; **prod Apache curl kanıtı DoD'de** — tamponlanan SSE "AI
takıldı" görünür), sol FAB **basılı tut-konuş** (**kaldır-kilitle** — Mahir'in kuralı;
tek dokunuş metin modu, jest asla tek yol değil), cihaz-üstü STT (TR dahil; transkript
hep düzenlenebilir; sunucu-STT v1.5 park), tek şemalı çıkarım (`ai/schema.js`; proje
eşleme LLM'de değil **ADR-0013 fold'unda**; çıplak "yarın" → yarın@varsayılan görev
saati) + **zorunlu onay kartı** → `TaskStore` outbox (AI'ya ikinci yazma yolu yok);
paylaşım hedefi (iOS Share Extension yalnız App Group'a yazar — ağ/AI işi yapmaz);
**enjeksiyon savunması mimari:** v1'de modele HİÇ araç verilmez, silme AI'ya kalıcı
kapalı, CI'da düşman korpusu; onam ekranı sağlayıcı gerçeğini söyler (**Gemini
ücretsiz katman veriyle eğitir — sarı uyarı**); kullanım sayacı içerik değil sayı
tutar. Yazılan kalıcı metinler: **AI.md (yeni)**, ADR-0018 + ADR-0019 (+ index),
BLUEPRINT §4.12/§4.13/§12.15/§12.16/§14 Phase 12-13/§16 **Risk 9**/§18, DESIGN **§23
Q1–Q8** + **§24 AI1–AI10**, ROADMAP iki bölüm, TASKS iki epic + round 11 park kuyruğu
(iki blok). Karara bağlananlar (AGENTS §8): onay kartı v1'de atlanamaz; sohbet
geçmişi cihaz-yerel; beş adaptör v1; alliswell.space BYOK-only açılır; README
iddiaları gerçekle denetlenir. **Sıradaki kod işi: OPH-196.** Cihaz kuyruğu (OPH-188
matrisi + AlarmKit turu) aynen açık; yeni kullanıcı aksiyonları aşağıda.)
— Önceki: 2026-07-29 (**EPIC 17 KODSAL OLARAK KAPANDI — OPH-184…195, v0.6.0.**
Bu turda kalan beşi: **OPH-194** sayfa geçişi hayaleti (kök neden bir animasyon hatası
değildi — her ekran ~%50 saydam ve aurora Navigator'ın ALTINDA tek sefer boyanıyordu;
artık her rota kendi opak zeminini taşıyor, `AwPageBackground`, ve **tek geçiş ailesi**
`AwPageTransitionsBuilder` 220 ms ile Flutter'ın platform başına dağıttığı üç farklı
hareketin yerine geçti); **OPH-187** widget başlığı hizası + `openToday` (snapshot **v2**,
alan yalnız >0 iken yazılıyor, native taraf eksik alana toleranslı); **OPH-188** widget'tan
tamamlama (iOS `AWCompleteTaskIntent` → OPH-182'nin App Group kuyruğu; Android satırında
**iki fill-in intent** — satır açar, daire tamamlar; Dart `widgetCallback` kendi izole
dünyasında `TaskStore.complete`'e gidiyor, **yeni yazma yolu yok**); **OPH-189**
`alliswell://` yönlendirmesi (saf + tablo testli çözücü, ULID doğrulaması, `/` gerçek rota,
`/not-found` kendi ekranımız, şema iki OS'a kaydedildi); **OPH-195** CRUD × varlık matrisi
(TASKS'ta) + park kararları + **DESIGN §22 "ulaşılabilirlik" kuralı**. **App 544/544**,
analyze + i18n + kontrast temiz, `lint`/`format:check`/`no-ts` temiz. **Sürüm 0.6.0+7**
(dört kaynak: pubspec, `kAppVersion`, iki package.json — release workflow üçünü kontrol
eder). **İki tuzak yine kod tarafından öğretildi:** (1) go_router `onException` ile
`errorBuilder`'ı BİRLİKTE kabul etmiyor — ikisi birden verilince sağlayıcı hataya düşüyor
ve **süitin yarısı** kırmızı oluyor (kalan `onException`, çünkü yalnız o yönlendirebiliyor);
(2) `handleWidgetAction` enjekte edilen veritabanını kapatmamalı — sahibi kapatır, aksi
hâlde "can't re-open a database". **AÇIK KALAN TEK İŞ: OPH-188 cihaz matrisi** (gerçek
iPhone/Android'de widget'tan tamamlama) + round 9'un AlarmKit cihaz turu. Önceki:
(**Epic 17'de yedi iş BİTTİ — OPH-184…186 + 190…193.**
Bu turda: düzenlerken **saat de soruluyor** (tek giriş yolu `core/date_input.dart`;
düşüş sırası `time ?? current ?? default` — 14:30'u 23:59 yapan satır buydu),
"planlanan tarih" **koşullu açıklamaya** dönüştü ("Takvimde taşındı — …" + Sıfırla;
sürüklemeyen kullanıcı hiç görmüyor, sunucu davranışı değişmedi), proje **durum
dropdown'ı kalktı** (üç ham enum sızıntısının üçü de kapandı; enum sunucuda duruyor,
migration yok) ve **ses önizlemesi durdurulabilir** oldu (çalar state'e taşındı;
`onPressed: null` yasak — düğme ikonunun söylediğini yapar; `Future.delayed` →
iptal edilebilir `Timer`; **yüklenen seslere ilk kez önizleme**). **App 530/530**
(+10 test), `analyze` + `check:i18n` temiz, kontrast FAILURES: 0, `lint`/
`format:check` temiz. Dersler: (1) bekleyen timer'ı **teardown yakalıyor** —
iptal edilemeyen gecikme, ait olduğu önizleme öldükten sonra bir SONRAKİ sesi
susturabilirdi; (2) ses picker'ı çalışma alanını izlediği için çıplak
`ProviderScope`'ta auth restore'unun 4 sn'lik timer'ı testi yanlış sebepten
düşürüyor → oturum açmış kapsamda pump; (3) ring ekranının özel ertelemesi
**bilinçle dışarıda** (kısıtları farklı: geçmişe ertelenemez, +30 dk varsayılan) —
paylaşılan şey kural, kod değil. **Sıradaki: OPH-194** (sayfa geçişi hayaleti).
Önceki: (**Epic 17'nin ilk üç işi BİTTİ — OPH-184/185/186.**
Silme artık her listede (kaydırınca yarım açılan kırmızı "Sil" + gerçek geri alma),
tamamlanan görev gün sonuna kadar listede kalıp sakinleşiyor, ve Ayarlar → Tamamlananlar
tüm geçmişi sayfalayarak gösteriyor. **App 520/520** (+27 test), `analyze` +
`check:i18n` temiz, kontrast **FAILURES: 0** (8 yeni çift), drift **v12**
(`idx_tasks_completed` — yalnız indeks). Yeni bağımlılık: `flutter_slidable` →
**[ADR-0017](adr/0017-swipe-to-delete-package.md)**. **Testlerin bulduğu iki gerçek
hata:** (1) commit closure'ı widget `WidgetRef`'ini kapatıyordu → satır listeden
düşünce element dispose oluyor ve **silme hiç gerçekleşmiyordu** (store artık
mount'luyken çözülüyor — OPH-170'in UnmountedRef dersi); (2) Pano kartları D6 gereği
sarmalanmadığı için bekleyen silmeyi **hiçbir şey gizlemiyordu** → filtre
`home_board.dart`'a da girdi. **Kontrast gerçeği tasarımı değiştirdi:** onay
dairesinin dolgusunu soldurmak tik glifini ~2.3:1'e düşürüyor (§5 tabanı 3:1) →
dolgu tam güçte kalıyor, sakinlik satırdan geliyor; DESIGN §20 C2 buna göre revize
edildi. **Sıradaki: OPH-191** (düzenlerken saat seçimi). Önceki giriş (turun doğuşu ve
kök nedenleri) aşağıda aynen duruyor.)
— Önceki: 2026-07-28 (**Feedback round 10 → Epic 17 doğdu: silme, tamamlananlar,
widget, sayfa geçişleri (Phase 11, v0.6.0). Kalıcı dokümanlar YAZILDI — kod yazılmadı;
implementasyon OPH-184'ten başlıyor.** Mahir'in 10 maddelik listesi + istediği kapsamlı UX
taraması → **12 task (OPH-184…195)**. Kök nedenler kodda tek tek doğrulandı — tam kanıt
tablosu TASKS Epic 17'de. **Turun tek cümlesi: bulunanların çoğu yazılmamış kod değil,
yazılmış ama yüzeye çıkarılmamış yetenek.** Öne çıkanlar: (1) görev silme motorunun tamamı
(`TaskStore.delete` + outbox + `DELETE /tasks/:id` alt-ağaç tombstone'u + ek kaskadı) v1'den
beri hazır, **tek çağıranı Fikirler satırı** — Home'da, detayda, hiçbir yerde düğmesi yok;
`grep Dismissible` → 0 sonuç, yani uygulamada kaydırarak silme hiç yok. Not silme yalnız
editörde, proje silme yalnız detayda → OPH-184 + OPH-195; (2) `watchOpen` `kPlanningStatuses`
ile filtreliyor → tamamlanan görev aynı karede düşüyor; `TaskTile`'ın hazır "tamamlanmış"
görünümü Home'da hiç görünmüyor → OPH-185 (gün sonuna kadar kalır, `dayBoundaryProvider`
gece yarısında düşürür, sakinleşme `Opacity` ile DEĞİL token'la — kontrast ölçülebilir
kalmalı); (3) `completedAt` drift'te saklı ve pull hiçbir statüyü filtrelemiyor → veri zaten
replikada, ekran yok → OPH-186 (Ayarlar → Tamamlananlar, `dueAt ?? completedAt` DESC, sayfalı,
drift v12 indeksi); (4) widget dörtlüsü: iOS `.firstTextBaseline` başlığı kaydırıyor ve
Android aynı başlığı `center_vertical` ile çiziyor (bir sürümdür iki platform farklı) →
OPH-187 + yeni `openToday` alanı (snapshot v2, **geciken+bugün**; tarihsizler hariç — karar
yazılı); satır dairesi statik `Image`/`TextView`, Android satır kaydı **görev id'sini bile
taşımıyor** → OPH-188 (OPH-132 + OPH-133'ün son kutularını devralır; round 9'un App Intent +
App Group kuyruğu hazır rayı); `alliswell://` şeması **iki OS'ta da kayıtlı değil**
(`CFBundleURLTypes` yok, `intent-filter` yok) + uygulamada çözücü yok → "No route for
alliswell://open/", üstelik hata ekranının "Home" düğmesi **var olmayan `/`**'a gidiyor →
OPH-189 + **yeni [ADR-0016](adr/0016-in-app-url-routing-and-widget-actions.md)** (URL yalnız
GEZİNİR; `alliswell://complete` açıkça yasak — yazan tek yol imzalı App Intent kuyruğu);
(5) ses önizlemesinde üç kusur: çalar metodun içinde doğuyor, stop düğmesi `onPressed: null`
(ikon "stop" ama **devre dışı**, diğer sesler de kilitli), `dispose` yok → sheet kapansa bile
ses devam ediyor; ayrıca **yüklenen seslerin önizlemesi hiç yok** → OPH-190; (6) detaydaki
`_DateRow` yalnız `showDatePicker` çağırıp varsayılan saati uyguluyor → **14:30'luk görevin
gününü değiştirmek saati sessizce 23:59 yapıyor** (create sheet date+time soruyor) → OPH-191
+ DESIGN §17 D5 "tek tarih GİRİŞ yolu"; (7) "Planlanan" satırı BLUEPRINT §12.4'ün alan
listesinde hiç yoktu (OPH-076 sapması) ama alan ölü değil — `desiredEventForTask` bloğu
**önce `scheduled_start_at`'ten** türetiyor ve Google'da sürükleme `due_at`'i değil onu
yazıyor → düz silmek etkinliği görünmez şekilde çivilerdi → OPH-192 **koşullu açıklama
satırı** ("Takvimde taşındı — {tarih}" + Sıfırla); (8) proje statü dropdown'ı yalnız
düzenlemede var (eklemede yok) ve **ham İngilizce enum** basıyor — aynı sızıntı 3 yerde;
`check:i18n` yakalayamıyor çünkü değişken basılıyor → OPH-193 (+ kör nokta OPH-195'e not);
(10) geçiş hayaleti bir animasyon hatası değil **tasarım sistemi kuralının sonucu**:
`scaffoldBackgroundColor: tokens.veil` yarı saydam (açık %58 / koyu %48) ve
`AuroraBackground` **Navigator'ın altında** tek sefer boyanıyor → push/pop'ta gelen ekranın
zemininden giden ekran görünüyor; ayrıca `pageTransitionsTheme` hiç tanımlı değil →
OPH-194 + **DESIGN §4 "Backgrounds" kuralı DEĞİŞTİ**. Revize edilen kalıcı metinler:
DESIGN §4 Backgrounds + §8 W6/**W9** + §17 **D5** + §18 N6 + yeni **§19–§22**,
BLUEPRINT §4.2/§4.3/§12.2/§12.4/§12.8 E-H/**§12.14**/§14 Phase 11, WIDGETS §3.1 (snapshot
v2) + §4, ROADMAP Phase 11, ADR index. Cihaz kuyruğu: yalnız OPH-188 (iOS 17+ ve Android
telefon) — kalan 11 task cihazsız. **Önceki tur (v0.5.0 / Epic 16) cihaz doğrulaması hâlâ
açık** — aşağıdaki "Kullanıcıdan bekleyen" aynen geçerli.)
— Önceki: 2026-07-28 (**v0.5.0 CANLI; Epic 16 KODSAL OLARAK KAPANDI — OPH-171…183.** Son iş
OPH-182'ydi ve round 9'un kök nedenini gerçekten ortadan kaldırdı: AlarmKit hattı artık
Xcode hedeflerinde, `AppDelegate`'te kurulu, Live Activity'siyle birlikte derleniyor ve
bağlantı **ürün ikililerinden** doğrulandı. Epic 16'da kalan tek şey **cihaz
doğrulaması** — kod tarafında iş yok. Ayrıntı: Snapshot ▸ Last completed.)
— Önceki: 2026-07-27 (**Feedback round 9 → Epic 16 doğdu: yenileme, tarih biçimi,
ALARM SİSTEMİ (Phase 10, v0.5.0). Kalıcı dokümanlar YAZILDI — kod yazılmadı; implementasyon
OPH-171'den başlıyor.** Mahir'in 8 maddelik listesi ve kodda doğrulanmış kök nedenleri:
(1) beş bölümde aşağı çekip yenileme yok — `RefreshIndicator` repoda hiç geçmiyor → OPH-171;
(2) Home'da yalnız arama+takvim kayıyor, Liste|Pano satırı ve hızlı ekleme dış `Column`'da
sabit → OPH-172 (telefonda SABİT kalan tek şey app bar); (3) proje/öncelik hizası —
`task.noProjectsHint` `helperText` olarak yükseklik ekliyor + `Row` merkezden hizalıyor →
OPH-173 (yazı silinir); (4) bitiş tarihi bugünle açılıyor (`initialDate: current ?? now`) →
OPH-173 **yarın** varsayılanı; (5) tarih biçimi `toString().split('.')` → OPH-174 tek
biçimlendirici + Ayarlar'da kullanıcı seçimi (varsayılan sistem; tr → 31.12.2026 23:59);
(6) **alarm turu** — 22:45'te (görev saati) hiç ses çıkmadı çünkü `effectiveRemindAt =
remind_at ?? due_at`, yani hatırlatıcı deadline alarmını SİLİYOR → OPH-175 iki alarm anı
(`reminders.kind` remind|due); 1./3. bildirimlerde ses yok, 2.'de var — payload'lar aynı,
fark OS tarafında (ses adı çözülemezse iOS sessizce varsayılana düşer; `timeSensitive` ses
sessiz anahtarıyla susar) → OPH-176 tek yükseklik sözleşmesi + ses bekçisi + **alarm
günlüğü**; erteleme sonrası "yine 1. bildirim" (zincir index 0'dan kuruluyor) + "5 dk sonra
ne olacak?" belirsizliği → OPH-177; süresiz erteleme/susturma yok → OPH-178
(`tasks.alarms_muted_at`, görev AÇIK kalır); (7) hatırlatıcı sayısı/sıklığı/sesi sabit
(`kUrgentChainOffsets`) → OPH-179 kullanıcı profili + "Hatırlatıcı Sistemi Ayarları"
(adımlar arası ≥1 dk, ≤20 adım, 64-slot maliyeti ekranda) ve OPH-181 zil sesi kütüphanesi +
özel ses yükleme (R2 → iOS `Library/Sounds` / Android ses-başına-kanal; ≤30 sn + caf/wav/aiff
kuralı yükleme anında söylenir); uygulama içi ring ekranı hiç ses çalmıyordu
(`HapticAlarmFeedback`) → OPH-180 ses yatağı (yeni bağımlılık kategorisi);
(8) **ekran kapalıyken/sessizde ses gelmiyor — KÖK NEDEN BULUNDU: AlarmKit hiç devreye
girmemiş.** `AlarmKitBridge.swift` HİÇBİR Xcode hedefinde değil ve `AppDelegate` onu kurmuyor
→ `isSupported()` `MissingPluginException` → acil alarmlar sessiz anahtarını aşamayan bildirim
hattında kalmış. → OPH-182 (AlarmKit'i gerçekten bağla: hedef + `AppDelegate` + **widget
extension `ActivityConfiguration` + `NSSupportsLiveActivities`** — round 9 araştırmasının yeni
bulgusu, yoksa sistem alarmları düşürebiliyor; özel ses `AlertConfiguration.AlertSound.named`;
sessiz+Odak+kilitli ekran cihaz DoD'si) ve OPH-183 (Apple Watch: aynalama bedava, AlarmKit
saate de ulaşıyor; watchOS companion kararı ölçümden sonra). Revize edilen kalıcı metinler:
DESIGN §11 A3 (ring ekranı SES ÇALMALI) + A5/A6 + yeni §15–§18, NOTIFICATIONS §2/§2b/§2c/§2d/
§5/§6 + kaynaklar 16-19, BLUEPRINT §4.9/§8.2/§12.13/§14 Phase 10/§16 Risk 4b/§18,
**yeni [ADR-0015](adr/0015-alarm-delivery-and-reminder-profiles.md)**, TASKS Epic 16
(OPH-171…183) + park kuyruğu. Cihaz kuyruğu: OPH-182/183 gerçek iOS 26 cihaz + Apple Watch.)
— Önceki: 2026-07-20 (**Feedback round 8 → Epic 15 doğdu: akış hızı, arama, pano,
global dosyalar (Phase 9, v0.4.0). Kalıcı dokümanlar YAZILDI, implementasyon OPH-160'tan
başlıyor.** Mahir'in 10 maddelik listesi: (1) Google bağlanınca veri akmıyor — kök neden
tanılandı: callback yalnız token yazar, `default_calendar_id` NULL kalır, sync/watch/sweep
üçü de erken çıkar; gizli "takvim seç" adımı + app'in syncNow eksiği → OPH-160 otomatik
primary + anında sync; (2) picker'da "+ Proje ekle" → OPH-163; (3) create'te ek seçimi →
OPH-166; (4) etiket chip-input + otomatik oluşturma + yönetim → OPH-165; (5) TR-duyarsız
katmanlı arama (başlık>etiket>gövde) → OPH-167 + **ADR-0013** (ampirik bulgu: ne SQLite FTS5
ne MySQL ai_ci `ı→i` fold'lar — DUCET'te ayrı ağırlık; çözüm app-owned fold + gölge kolonlar

- LIKE tier UNION; FTS5 belgeli upgrade yolu); (6) varsayılan saat 09:00→23:59 + ayar →
  OPH-161; (7) görev açıklaması + linkify → OPH-164; (8) Home Kanban — kaynaklı mobil UX
  araştırması (Trello/Jira pager+peek, çift yol taşıma: drag + zorunlu "Durum değiştir" sheet;
  NN/g) → OPH-168 + DESIGN §14 K1-K6; (9) Takvim sekmesi kalkar (seçili gün ufku aşar) →
  OPH-162; (10) global Dosyalar + klasörler → OPH-169/170 + **ADR-0014** (`workspace` target,
  push-pull `folder` entity, alt-ağaç kaskadı). Revize: BLUEPRINT §7.2/§12.1/§12.2/§12.4/
  §12.10-12.12/§4.4/§4.10-4.11/§14 Phase 9/§16 Risk 8/§18, DESIGN §10 F7-F9 + §12/§13/§14,
  ARCHITECTURE §6b-6c, ATTACHMENTS §0a/§14, TASKS Epic 15 (OPH-160…170), parking-lot; ADR
  index 0011-0014 tamamlandı. Cihaz kuyruğu (OPH-131…157 manuel matris) aynen bekliyor;
  Epic 15 tamamen cihazsız.) — Önceki: **OPH-143 → foreground alarm ekranı + dürüst uyarı
  banner'ları — Epic 13'ün son CİHAZSIZ işi, BİTTİ:** urgent alarm due olunca uygulama açıksa
  tüm ekranı kaplayan `AlarmRingScreen` (Onayla + snooze + Tamamla/Aç, `PopScope`;
  masaüstü/web'in TEK alarm yüzeyi, mobilde OS bildiriminin foreground eşi),
  `AlarmOverlayController` (replika alarm feed + foreground timer wheel) HomeShell'de tur'un
  ÜSTÜNDE; ses enjekte edilebilir seam (`AlarmFeedback` — haptik bugün, audio cihaz turuna);
  Home'da `AlarmDegradationBanner` (bildirim kapalı / Android exact-alarm reddi, worst-first,
  tap izin akışı). Ring kararı saf fn, auto-show testlerde OFF (OPH-111 idiomu). Yeni
  `alarmSupportProvider` + `alarm.*` i18n (en+tr), DESIGN §11, NOTIFICATIONS §3. **App
  322/322, analyze + check:i18n + kontrast (FAILURES: 0) temiz.** — Önceki: **Design round 8
  (görsel) → "Liquid Glass v2" görsel yenileme, ADR-0012:**
  Mahir'in "renkler belirgin değil, Apple Liquid tarzı değil" geri bildirimi üzerine Apple'ın
  Liquid Glass rehberleri araştırıldı (HIG Materials, Adopting Liquid Glass, Newsroom + 3 kaynak
  daha — ADR'de) ve tüm tema yenilendi: canlı azure/indigo palet (kontrast bekçisi 50 çift,
  FAILURES: 0), yüzen kapsül alt bar + yüzen cam rail (blur+saturation, lens kenarı, gölge),
  renkli aurora, kapsül butonlar, dairesel FAB, iOS-yeşili switch'ler, 12/16/20/28 radius.
  Android widget renkleri W1 gereği birlikte taşındı. Yeni screenshot harness'ı
  `design_screenshots_test.dart` (--dart-define=screenshots=true) DESIGN §5 turunu üretilebilir
  yaptı; gerçek fontla ortaya çıkan iki dar-genişlik taşması sertleştirildi (ay başlığı,
  dropdown etiketleri). App 306/306 yeşil. — Önceki: **Feedback round 7 → Epic 14 doğdu:
  Attachments & project files (Cloudflare R2/S3).** Kalıcı dokümanlar yazıldı — [ATTACHMENTS.md](ATTACHMENTS.md), ADR-0011,
  BLUEPRINT §4.10/§12.3-12.5/§14 Phase 8/§15.3/§16 Risk 7/§18, DESIGN §10, ARCHITECTURE §6b,
  TASKS Epic 14 (OPH-150…157) — ve implementasyon başladı. Epic 12/13'ün cihaz kuyruğu
  (OPH-131 Xcode, 140…143) kullanıcının cihaz turunu bekliyor; Epic 14 cihazsız ilerliyor.
  Hedef v0.3.0.)

**Repository:** https://github.com/mahirozdin/alliswell (public) — CI green since the first push
([run #1](https://github.com/mahirozdin/alliswell/actions)): migrations apply/rollback/re-apply
against real MySQL 8.4 and all unit+integration tests pass.

## Snapshot

|                          |                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| ------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Current phase            | **Phase 14 AKTİF (2026-07-30): Epic 20 — yapay zeka (OPH-215…227, v0.9.0) BAŞLADI; OPH-215 bitti.** Önceki metin: **Round 12 PLANLANDI (2026-07-29): Phase 13 = Epic 19 (tekrarlı görevler + takvim her zaman + düzeltmeler, OPH-204…214, v0.8.0) ARAYA GİRDİ; yapay zeka → Phase 14 / Epic 20 / OPH-215…227 / v0.9.0.** Önceki metin: **Phase 12 + 13 PLANLANDI (2026-07-29, istek turu 11)** — **Epic 18 Hızlı Erişim (OPH-196…203 → v0.7.0)** + **Epic 19 Yapay Zeka (OPH-204…216 → v0.8.0)**; kalıcı dokümanlar YAZILDI (AI.md yeni, ADR-0018/0019, BLUEPRINT §4.12-4.13/§12.15-12.16/§14/§16 Risk 9/§18, DESIGN §23/§24, ROADMAP, TASKS + park), **kod YAZILMADI — implementasyon OPH-196'dan başlıyor.** AI'nın tek cümlesi: abonelik-OAuth üç sağlayıcıda da kapalı → iki hat: **MCP bağlayıcısı** (aboneliğinle) + **BYOK** (uygulama içi; ses/bubble/paylaşım orada). Fiili sürüm durumu: **Phase 11 (v0.6.0)** — **Epic 17 KODSAL OLARAK KAPANDI (2026-07-29, OPH-184…195);** kalan tek iş **OPH-188 cihaz matrisi**. Önceki metin: kalıcı dokümanlar YAZILDI (2026-07-28: DESIGN §4/§8/§17/§18 revizyonları + yeni §19–§22, BLUEPRINT §4.2/§4.3/§12.2/§12.4/§12.8/§12.14/§14, WIDGETS §3.1 snapshot v2 + §4, ADR-0016), **kod YAZILMADI — implementasyon OPH-184'ten başlıyor.** 12 task: 184→186 liste UX çekirdeği · 191→194 tekil düzeltmeler · 187→189 widget hattı · 195 tarama. **Yalnız OPH-188 cihaz ister.** Önceki: Phase 10 (v0.5.0) **CANLI**, Epic 16 kodsal olarak kapandı; **cihaz doğrulaması hâlâ açık** (OPH-182/183 + eski kuyruk). Detay: **Phase 10 (v0.5.0)** — **Epic 16: Feedback round 9 (yenileme, tarih biçimi, alarm sistemi)** aktif; kalıcı dokümanlar YAZILDI (2026-07-27: DESIGN §11 A3/A5/A6 + §15–§18, NOTIFICATIONS §2/§2b/§2c/§2d/§5/§6, BLUEPRINT §4.9/§8.2/§12.13/§14/§16, ADR-0015), **OPH-171…183 KODSAL OLARAK TAMAM (2026-07-28); Epic 16'da kalan tek iş CİHAZ DOĞRULAMASI.** 171–174 cihazsız; 175–181 API+app; **182'nin kodu+wiring bitti ve iOS 26.2 SDK'sına karşı derlendi — kalan yalnız gerçek cihaz matrisi; 183 gerçek Apple Watch ölçümü ister.** Önceki: Phase 9 (v0.4.0) **CANLI** (Epic 15 kapandı, 2026-07-26 deploy yeşil). Eski cihaz kuyruğu (Epic 12 OPH-132/134/135/136, Epic 13 OPH-140/141, Epic 14 OPH-157) hâlâ açık — **OPH-141 artık OPH-182'nin içinde gerçekten bağlanıyor.**                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| Current epic             | **OPH-216 BİTTİ** (2026-07-30: beş adaptör + SSE/NDJSON ayrıştırıcı + fakeai + katalog + test ucu; API 480u+51i), sırada **OPH-217**. Önceki: **Epic 20 — Yapay zeka: MCP bağlayıcısı + BYOK sohbet + sesle görev** (2026-07-30 → **13 task, OPH-215…227**, v0.9.0; koşu sırası 215→216→217→**219→218 (bilinçli takas — MCP, 219 şemasını tüketir)**→220…227): **OPH-215 BİTTİ** (AI temeli: 3 tablo + AI_TOKEN_KEY + plugins/ai.js + status/CRUD + AI_ENABLED kapısı), sırada **OPH-216**. Önceki metin: **Epic 19 — Feedback round 12** (2026-07-29 → **11 task, OPH-204…214**, v0.8.0): **OPH-204 BİTTİ** (kural modeli + ADR-0020 + DESIGN §25), sırada **OPH-205**; hat sırası 204 araştırma → 205→208 tekrar → 209→210 takvim → 211→213 düzeltmeler → 214 (cihaz). Epic 19'un tam dökümü bu satırın devamında. Önceki (KAPANDI): **Epic 18 — Hızlı Erişim** (2026-07-29, istek turu 11 #1 → **8 task, OPH-196…203**): rail bölümü · dar-rail popover · telefonda sürüklenen yüzen düğme + panel · her varlık menüsünde "Hızlı erişime ekle" + dış link · emoji/renk/ad · gezinme tablosu + kırık/arşivli hedef; `quick_link` = **ilk kullanıcı-kapsamlı senkron varlık** (ADR-0018), hedef silmede sunucu kaskadı, 50 sınırı. Ardından **Epic 19 — Feedback round 12** (2026-07-29 → **11 task, OPH-204…214**): tekrarlı görevler — kural motoru (RFC 5545 alt kümesi + kırpma) + switch→otomatik dialog + "Sonraki 5" önizleme + **+12 ay kayan materyalizasyon** + bu/gelecek/tümü kapsamı (204…208) · takvim aynası seçeneksiz — her görev 30-dk blok, tarihsiz ekleniş gününe, Google Tasks/EKReminder değerlendirmesi (209…210) · geciken×tamamlanan kuralı (211) · proje sheet z-order (212) · Home app bar kontrolleri (213) · ekran-açık alarm ölü düğme + çökme (214, cihaz). Sonra **Epic 20 — Yapay Zeka** (istek turu 11 #2 → **13 task, OPH-215…227**; round 12 numaraları +11 kaydırdı): AI temeli (şifreli BYOK, `AI_TOKEN_KEY`) → beş adaptör → SSE `/ai/chat` (prod Apache kanıtı) → **uzak MCP sunucusu** → çıkarım şeması (fold proje eşleme) → ayarlar+onam → bubble → **zorunlu onay kartı → TaskStore outbox** → basılı-konuş FAB + cihaz-üstü STT → ses kablolama → paylaşım hedefi → enjeksiyon sertleştirmesi (CI düşman korpusu) → README/tanıtım. Plan: TASKS Epic 18/19/20 + [AI.md](AI.md) + ADR-0018/0019 (+ implementasyonda 0020 tekrar · 0021 takvim · 0022 MCP · 0023 STT/paylaşım) + DESIGN §23/§24 (+ §25'i OPH-204 yazar) + BLUEPRINT §12.17. Migration'lar: `quick_links` + drift v13 (Epic 18); `task_series` + `tasks.series_id`/`occurrence_date` (Epic 19); `ai_connections`/`ai_usage_events`/`ai_action_log` + drift (Epic 20). Önceki: **Epic 17 — Feedback round 10** (2026-07-28, 10 madde + kapsamlı tarama isteği → **12 task, OPH-184…195**): kaydırarak silme + her listede/detayda silme (motor hazırdı, düğmesi yoktu) · tamamlanan görev gün sonuna kadar listede kalır ve sakinleşir · Ayarlar → Tamamlananlar zaman çizelgesi · widget tarih başlığı hizası + günün açık görev sayısı · widget'tan tamamlama · `alliswell://` yönlendirmesi + gerçek hata çıkışı · ses önizlemesinin durdurulabilmesi · düzenlerken saat seçimi · "planlanan tarih" koşullu olur · proje durumu dropdown'ı kalkar · sayfa geçişi hayaleti · CRUD/UX matris taraması. Plan: TASKS Epic 17 + [ADR-0016](adr/0016-in-app-url-routing-and-widget-actions.md) + DESIGN §19–§22. Migration'lar: yalnız **drift v12** (`tasks(status, completedAt)` indeksi) — **sunucu şeması DEĞİŞMİYOR**. Önceki: **Epic 16 — Feedback round 9** (2026-07-27, 8 madde → 13 task, OPH-171…183): beş bölümde aşağı çekip yenileme, Home'un tek kaydırma katmanı, create sheet hizası + "yarın" varsayılanı, tek kaynaktan tarih biçimi + kullanıcı ayarı, **alarm belkemiği v2** (görev saati kendi alarmı · tek yükseklik sözleşmesi + alarm günlüğü · erteleme netliği · süresiz erteleme · kullanıcı hatırlatıcı profili · zil sesi kütüphanesi + özel ses · uygulama içi alarm sesi · **AlarmKit'i gerçekten devreye alma** · Apple Watch). Plan: TASKS Epic 16 + [ADR-0015](adr/0015-alarm-delivery-and-reminder-profiles.md) + NOTIFICATIONS §5/§6 + DESIGN §15–§18. Migration'lar: `reminders.kind`, `reminders.snooze_count`, `tasks.alarms_muted_at` (+ drift v8). Önceki: **Epic 15 — Feedback round 8** (2026-07-20, 10 madde) KAPANDI.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| ➡️ **Next task**         | **OPH-217 — `/ai/chat`: SSE-over-POST + Redis token bucket + iptal yayını + web Socket.IO transportu** (reply.raw close dersi uygulanacak). Önceki: **OPH-216 — sağlayıcı adaptörleri ×5 + SSE ayrıştırıcı + fakeai + model kataloğu.** (Epic 19 cihaz doğrulamaları değişmedi ve hâlâ açık — aşağıda; Epic 20 kendi cihaz turlarını 223/225 kapanışında ekleyecek.) Önceki metin: **CİHAZ DOĞRULAMASI — Epic 19'un kalan tek işi; kod tarafında iş YOK.** (1) **OPH-214:** acil bir görev kur, **ekran AÇIKKEN** alarmı bekle → heads-up bildirimdeki **saat ikonuna bas** (erteleme çalışmalı ve görev satırında "Ertelendi — HH:mm" görünmeli, OPH-177 sözleşmesi), sonra **bildirimin gövdesine dokun** (doğru görev açılmalı, çökme olmamalı); uygulamayı **tamamen kapatıp** aynı ikisini tekrarla (bu turun asıl düzeltmesi cold-start yolu); **Ayarlar ▸ Alarm günlüğü'nde `action` ve `interacted` satırları** görünmeli — boşsa kablolama hâlâ kopuk demektir; çökme sürerse **adb logcat / Xcode organizer** log'u al. (2) **OPH-210 canlı pass:** gerçek Google hesabıyla — tarihli görev 30 dk blok, 23:59'luk görev **23:29–23:59**, tarihsiz görev **ekleniş gününde**, tamamlanınca blok **kalıp `✓` alıyor**, iptal edince siliniyor; Google'da event'i elle silmek onu geri getirmemeli. Apple tarafında aynı beş madde. (3) Devreden: **OPH-188** widget matrisi + **OPH-182** AlarmKit turu (sessiz anahtar + Odak + kilitli ekran). Sonuçlar STATE'e. (**v0.8.0 etiketi ATILDI ve prod'a deploy edildi — 2026-07-29.**) Sonraki kod işi: **Epic 20 → OPH-215** (yapay zeka temeli). Eski metin: **OPH-214 — ekran açıkken alarm: ölü erteleme ikonu + dokununca çökme (round 12 #6, CİHAZ taskı).** Koddan çıkan iki kuvvetli hipotez (uygulama bu turda yapılacak, doğrulama cihazda): (1) **cold-start kaybı** — repoda `getNotificationAppLaunchDetails`/`didNotificationLaunchApp` HİÇ YOK (`lib`, `ios`, `android` tarandı) ve tüm Android aksiyonları `showsUserInterface: true` (`gateway_local.dart:273-311`), yani aksiyon uygulamayı başlatıyor ama başlatma yanıtı okunmadığı için hiçbir yere düşmüyor = "saat ikonu hiçbir şey yapmıyor"; (2) **dinleyici yarışı** — `gateway_local.dart:51` `_events` broadcast ve TAMPONSUZ, tek dinleyici `notificationSchedulerProvider` (`notifications/providers.dart:165-203`) ve o da HomeShell mount olup workspace çözülünce doğuyor. Yapılacak: `main.dart`'taki widget kalıbının aynısı (ilk kareden önce launch detaylarını oku — `widgetCallback`/`registerInteractivityCallback` emsali), gateway'e küçük replay tamponu, çökme için gerçek crash log (adb logcat / Xcode organizer) + `alliswell://` çözücüsü ve auth restore yarışı denetimi, alarm günlüğüne `action`/`interacted` satırlarının düştüğünün garantisi. Cihaz DoD TASKS'ta. Sonra: **epic kapanışı → v0.8.0** (dört sürüm kaynağı, CHANGELOG, STATE, ROADMAP). Eski metin: **OPH-213 — Home görünüm kontrolleri app bar'a.** `home_screen.dart:141-176` `SegmentedButton` satırı (`home-view-toggle` + `board-edit-columns`) ve `:355-389` takvim göster/gizle düğmesi (`toggle-calendar`) **ölür**; yerine app bar'da iki ikon, **ayarlar düğmesinin solunda**. Kalıp `notes_screen.dart:55-76` (ikon **geçilecek görünümü** gösterir + tooltip). Home `buildSectionAppBar` (`screens/home_shell.dart:305-331`) kullandığı için imzaya **`trailingActions`** eklenecek (ikinci bir AppBar kalıbı doğurmadan). Tercihler aynen (`homeViewProvider`, `homeCalendarVisibleProvider` — `core/persisted_prefs.dart:60/71`), takvim gizlenince seçili günü temizleme davranışı korunur. DESIGN §16 zaten revize (sliver sırası: banner, quick-add, arama, ay takvimi; H3 sapması kendiliğinden çözülür). i18n: mevcut `board.viewList/viewBoard`, `home.showCalendar/hideCalendar` tooltip'e taşınır. Testler: app bar'dan toggle (Liste↔Pano), satırların yokluğu, takvim tercihi, telefon + geniş kırılım, arama modunda davranış; `localKv` global → `setUp`'ta `alliswell_home_view` temizle. Sonra: 214 (cihaz) → kapanış v0.8.0. Eski metin: **OPH-212 — proje düzenle sheet'i.** **Kök neden hipotezi TASKS'takinden farklı ve daha güçlü:** suç senkron çağrı değil, `project_edit_sheet.dart`'ın `showModalBottomSheet`'i **`useRootNavigator` vermeden** çağırması (varsayılan `false`) → sheet `StatefulShellBranch` navigator'ına push ediliyor ve HomeShell'in `extendBody: true` + `bottomNavigationBar` (GlassSurface) + FAB'ı ONUN ÜSTÜNE boyanıyor. Kanıt: aynı fonksiyonu **root** context'ten çağıran `home_shell.dart:95` (Projeler FAB'ı) DOĞRU çalışıyor; `projects_screen.dart:196`, `project_detail_screen.dart:114`, `project_picker.dart:117` dal navigator'ından çağırıyor ve bozuk. **Önce doğrula** (menü kapanışını geciktirmek düzeltmiyorsa hipotez kesinleşir), sonra `useRootNavigator: true` + **repo genelinde tara** (17 `showModalBottomSheet` çağrısının hiçbiri vermiyor; OPH-207'de `showRepeatDialog` peşinen veriyor). Regresyon testi: menüden "Düzenle" → sheet önde **ve tap hedefine gerçekten basılabiliyor** (sadece `findsOneWidget` değil). Sonra: 213 (app bar) → 214 (cihaz) → kapanış v0.8.0. Eski metin: **OPH-211 — Geciken grubunda tamamlanmış satır kalmaz.** Tek yerden düzelir: `apps/app/lib/src/features/tasks/data/task_store.dart` `_completedSince` (satır ~68) — `status=completed AND completedAt >= since`e **vade sınırı** eklenecek: `AND (dueAt IS NULL OR dueAt >= günBaşlangıcı)`. `watchOpen` ve `watchProjectTasks` aynı `_watchList`ten geçtiği için ikisi birden düzeliyor. Ayrıca grup sayaçları (`home_screen.dart` `buildHomeGroupRows`, `'${group.bucket.label} · ${group.items.length}'`) tamamlananı saymamalı ve widget aynı kuralı `openTasksProvider`tan bedavaya alıyor — **test edilecek**. Testler: dün vadeli + bugün tamamlanan → listede YOK/Tamamlananlar'da VAR; bugün vadeli + tamamlanan → grubunun sonunda KALIR (OPH-185 regresyonu); tarihsiz + tamamlanan → kalır; gece yarısı geçişi; sayaç. Bağlayıcı: DESIGN §20 C1 (bu turda revize edildi). Sonra: 212 (sheet z-order) → 213 (app bar) → 214 (cihaz) → kapanış v0.8.0. Eski metin: **OPH-210 — takvim aynası v2.** Sıra ADR-0021'de sabit: (1) **önce** `src/lib/google.js`'e 429/`Retry-After` + üstel geri çekilme + eşzamanlılık tavanı (bugün ÇIPLAK `fetch`, tek geri çekilme BullMQ'nun 5 denemesi); (2) `src/lib/mirror.js`: `calendar_mirror_enabled` erken dönüşü **bastırma** semantiğine döner, blok kuralı (scheduled → 30 dk → gece yarısı kenetlemesi 23:29–23:59 → tarihsiz `created_at` günü), tamamlanan için `✓` başlığı (iptal/arşiv/silinen hâlâ null); (3) `queue/mirror-job.js` `enqueueWorkspaceMirrorSweep` pencere filtresi (-30g → +12ay, idempotent, log'lu); (4) `lib/inbound.js` `stop-mirror` dalı yeni semantiğe bağlanır; (5) app: `task_detail_screen.dart` `calendar-mirror-switch` **silinir** + `task.showInCalendar*` i18n anahtarları kalkar + `calendar_mirror_test` widget yarısı güncellenir; (6) `apple_mirror.dart` aynı kurala bağlanır ve **ortak fikstür** `test/fixtures/calendar_block_parity.json` iki süitte de koşar (§17 D1: iki ayna çelişemez); (7) bağlantı ekranı onam metni. Canlı Google passi cihaz kuyruğuna. Eski metin: **OPH-209 — takvim araştırması + ADR-0021 (KOD YAZMAZ).** Mevcut davranışın dökümü (`lib/mirror.js:16` `calendar_mirror_enabled` erken dönüşü + eski §7.1 şartı), ≥3 todo-app incelemesi (Todoist/TickTick/Any.do: event mi Google Tasks mı, iki yönlü mü), **Google Tasks API + Apple EKReminder değerlendirmesi** (karar bana bırakıldı — yeterliyse faz planı, değilse ret gerekçesi ADR-0021'e; v1 garantisi event bloğu). ADR-0021'e girecek, planlama turunda SABİTLENMİŞ kararlar: blok kuralı (scheduled kazanır → 30 dk → gece yarısı kenetlemesi → tarihsiz ekleniş gününe), **tamamlanan görevin eventi KALIR ve başlığı `✓` alır** (kullanıcı kararı), **backfill penceresi -30 gün → +12 ay** (kullanıcı kararı), `calendar_mirror_enabled` kullanıcı switch'i değil **makine bastırma bayrağı** olur (inbound `stop-mirror` dalının yerine), **rate limit/429 yönetimi yok — 210'un ilk işi**, onam metni. Sonra: 210 (ayna v2) → 211/212/213 (düzeltmeler) → 214 (cihaz). Eski metin: **OPH-208 — seri görünürlüğü, yüzey etkileri, README.** Yapılacak: ↻ rozeti (`task_tile.dart`, detay, Pano kartı — tamamlananda §20 C2 gereği kalkar), **yüzeyler varsayılmaz test edilir** (takvim noktaları `task_grouping.dart`, widget snapshot `features/widgets/widget_grouping.dart` — bugünün occurrence'ı `openToday`'e sayılmalı, arama fold kolonları, alarm planlayıcı `maxPending` penceresi), create sheet'in "Tekrarla" switch'i (kaydet → seri kur sırası), kaydırarak silmenin kapsam sorusuna bağlanması + seri detayında "Tekrarı durdur", README tanıtım bölümü + ekran görüntüsü, ROADMAP/STORE-LISTING dokunuşu. Eski metin: **OPH-207 — App: tekrar dialog'u + Dart motor portu.** Sunucu tarafı hazır (205/206): seri CRUD + `seriesScope` + materyalizasyon. Yapılacak: drift **v14** (`TaskSeries` tablosu + `Tasks.seriesId`/`occurrenceDate`, `if (from < 14)` + `from >=` guard kuralı, ardından `dart run build_runner build`), `sync_applier.dart`'a tombstone+snapshot+`taskSeriesCompanion`, `core/recurrence.dart` (JS motorun portu — **`apps/app/test/fixtures/recurrence_parity.json` 16 vakası Dart süitinde de koşacak**), `core/recurrence_text.dart` (TR/EN kural bazlı cümle; i18n'de çoğul YOK → her form ayrı anahtar), `features/tasks/ui/repeat_dialog.dart` (preset + Gelişmiş A/B/C + "Sonraki 5"), `features/tasks/data/series_store.dart` (replika + outbox, `entityType: 'task_series'`), create/detail sheet'lerinde "Tekrarla" switch'i (ilk açılışta dialog otomatik, iptal → switch kapanır), **kapsam dialog'u** (varsayılan "bu ve gelecektekiler"; tarih düzenlemesinde "yalnız bu"), `test/sync/migration_test.dart`'ta v1 fabrikasyonuna `DROP TABLE task_series` + `user_version` 13→14. Bağlayıcı: ADR-0020 + DESIGN §25 (R1-R9). Sonra: 208 yüzeyler → 209/210 takvim → 211/212/213 → 214 (cihaz). Eski metin: **OPH-206 — kapsam semantiği: bu / bu ve gelecektekiler / tümü.** Bağlayıcı tuzak: sync'e **yeni bir `operation` fiili eklenemez** (`sync_revisions`/`client_mutations` ENUM + dispatch'in `default:` dalı `applyDelete`'e düşürür, ADR-0018'in dersi) → kapsam sıradan bir `update` + **virtual `seriesScope` alanı** olarak taşınır (`orderedIds` emsali: `routes/sync.js` TASK_FIELDS + `ENTITIES.task.afterUpdate`). Mekanik: `future` → seri bölünür (eskisine `rule.end.until`, yeni seri doğar), `all` → seri metadata'sı + `rebuildFuture` (hazır), `this` → occurrence detach (`series_id = NULL`). Alan-bazlı varsayılan: **tarih değişimi → `this`**, başlık/açıklama/öncelik → `future`. Hazır yapı taşları: `db/task-series.js` içindeki `deleteFutureOccurrences`, `rebuildFuture`, `materializeSeries`, `materializationWindow`. Sonra: 207 dialog → 208 yüzeyler → 209/210 takvim → 211/212/213 düzeltmeler → 214 (cihaz). Eski metin: **OPH-205 — API: `task_series` + materyalizasyon motoru + kayan 12 ay penceresi.** Bağlayıcı metin [ADR-0020](adr/0020-recurring-tasks-and-materialization.md) (OPH-204'te kabul edildi): kural JSON'u (`freq/interval/byWeekday(ordinal)/byMonthDay(-1)/byMonth/end`), **kırpma** (31 → 30/29/28, değer başına kırp + tekilleştir), senaryo C kesişimle (`byWeekday`+7 günlük `byMonthDay` penceresi), occurrence'lar **gerçek `tasks` satırı** (+12 ay, tavan 400, `TASK_SERIES_TOO_DENSE`), süpürme ev kalıbı (`setInterval+unref`, `app.decorate('seriesGc')` — test `sweep(now)` çağırır; API süitinde sahte saat YOK, `now` enjeksiyonu konvansiyonu). Dosyalar: yeni migration (`task_series` + `tasks.series_id`/`occurrence_date`, `quick_links` migration'ı şablon), `src/lib/recurrence.js` (saf; `zonedWallTimeToUtc`'ü `src/lib/time.js`'ten kullan), `src/db/task-series.js`, `routes/task-series.js`, `plugins/series-gc.js`, `routes/sync.js` kaydı (+`TASK_FIELDS`ten `repeatRule` çıkar), `test/helpers/fakedb.js` üç yer. Parite fikstürü `apps/app/test/fixtures/recurrence_parity.json` burada doğar (Dart yakası OPH-207'de). Sonra: 206 kapsam → 207 dialog → 208 yüzeyler → 209/210 takvim → 211/212/213 düzeltmeler → 214 (cihaz). Eski metin: Epic 18 KAPANDI — v0.7.0 etiketlenmeye hazır (dört sürüm kaynağı güncel, CHANGELOG'da 0.7.0 bölümü yazılı). _Paralelde açık:_ **CİHAZ DOĞRULAMASI — Epic 17'nin tek kalan işi, kod tarafında iş YOK.** (1) **OPH-188 cihaz matrisi:** iPhone (iOS 17+) ve Android telefonda widget'ı ekle → uygulamayı **açmadan** bir görevi daireden tamamla → widget yerinde güncelleniyor mu, uygulama açılınca görev tamamlanmış mı, **uçak modunda** tamamlayıp ağ gelince senkronlanıyor mu, satıra dokunmak **doğru görevi** açıyor mu (bu, OPH-189'un yönlendirmesinin ilk gerçek sınavı — şema kaydı yoksa OS uygulamayı hiç başlatmaz ve hata SESSİZDİR), iOS 16'da derin bağlantıya düşüyor mu. (2) Round 9'dan devreden **OPH-182 AlarmKit matrisi** (sessiz anahtar + Odak + kilitli ekran) aynı turda. (3) Sonuçlar STATE'e işlenir. Eski metin: **OPH-194 — Sayfa geçişlerinde önceki ekranın hayaleti** (cihazsız ama tasarım sistemine dokunuyor). Kök neden yazılı ve ölçülü: `scaffoldBackgroundColor: tokens.veil` yarı saydam (açık **%58**, koyu **%48**) ve `AuroraBackground` **Navigator'ın ALTINDA** tek sefer boyanıyor → push/pop sırasında iki rota da ağaçtayken gelen ekranın zemininden giden ekran görünüyor. Bu bir animasyon/performans hatası değil, **DESIGN §4 "Backgrounds" kuralının sonucu** — ve o kural bu round'da zaten değiştirildi (§21 T1: "bir rota altındaki rotaya karşı OPAKTIR"). Yapılacak: paylaşılan `AwPageBackground` (aurora + veil, opak) rota sayfalarının altına; alternatiflerin neden elendiği DESIGN'a; `pageTransitionsTheme` **tek aile** olarak tanımlanır (bugün tanımlı değil → Android Zoom, iOS Cupertino, masaüstü üçüncü bir şey); cam yüzeyler geçiş ortasında profillenir; **kontrast yeniden koşar** (zemin bileşimi değişiyor). Testin dişi: geçişin ortasında `pump` edip giden ekranın metninin **görünmediğini** doğrulamak. Sonra: 187 → 189 → 188 (tek cihaz işi) → 195. Eski metin: **OPH-191 — Düzenlerken de saat seçilir: tek tarih-saat giriş yolu** (cihazsız, küçük ve keskin). Bugünün hatası adıyla yazılı: detaydaki `_DateRow` yalnız `showDatePicker` çağırıp **varsayılan görev saatini uyguluyor**, yani 14:30'luk bir görevin sadece GÜNÜNÜ değiştirmek saati sessizce 23:59 yapıyor; oluşturma sheet'i ise date+time soruyor. Yapılacak: paylaşılan `awPickDateTime(context, ref, {current, anchor})` (`core/date_format.dart` yanında) — tarih **biçimi** nasıl tek kaynaktan geliyorsa (OPH-174) **girişi** de öyle olacak (DESIGN §17 D5); create sheet'in `_pickDateTime`'ı, detaydaki **üç** satır ve ring ekranının özel ertelemesi aynı yardımcıya bağlanacak. Test cümlesi: saatli görevin günü değişince **saat korunuyor**. Sonra sırayla OPH-192 (planlanan tarih koşullu olur — kullanıcıya açıklanacak karar TASKS'ta yazılı) → 193 → 190 → 194 → 187 → 189 → 188 (tek cihaz işi) → 195. _Paralelde açık kalan iş:_ **Epic 16'nın CİHAZ DOĞRULAMASI** (aşağıdaki "Kullanıcıdan bekleyen") — kullanıcının telefonuna bağlı, kod işi değil. Eski metin: **CİHAZ DOĞRULAMASI — Epic 16'nın tek kalan işi. Kod tarafında yapılacak iş YOK** (OPH-171…183 kodsal olarak bitti). Elde: gerçek iPhone (iOS 26.5.2) + Xcode 26.2. Yapılacaklar: (1) **OPH-182 cihaz DoD matrisi** — adım adım [ALARMKIT_SETUP.md](../apps/app/ios/Runner/ALARMKIT_SETUP.md) "Device DoD": acil görev, **sessiz anahtarı AÇIK + Uyku Odak AÇIK + ekran KİLİTLİ** → tam ekran alarm; **Onayla** senkronize oluyor (bir kez de uygulama KAPALIYKEN — basış app group kuyruğunda bekleyip sonraki açılışta uygulanmalı); **Ertele** görev satırında "Ertelendi — HH:mm" gösterip o saatte yeniden çalıyor; iOS<26 bildirim zincirine düşüyor; **Ayarlar ▸ Alarm günlüğü'nde `lane=alarmkit` satırları** (boşsa alarm hiç AlarmKit'ten geçmemiş demektir). (2) **OPH-183** — gerçek Apple Watch'ta aynalama/haptik ölçümü; sonuç companion kararını kapatır (bugünkü karar: AÇMA). (3) Sonuçlar STATE'e + TASKS'ın son iki kutusuna işlenir → **v0.5.0**. Ayrıca eski cihaz kuyruğu (Epic 12 OPH-132/134/135/136, Epic 13 OPH-140, Epic 14 OPH-157) aynı turda birleştirilebilir.
| ✅ Kullanıcıdan bekleyen | **Round 11 girişleri ARTIK CANLI (OPH-215 bitti, 2026-07-30):** aşağıdaki (a) OpenAI ilgi-formu kaydı ve (b) üç aylık sağlayıcı politika kontrolü (ilk ~2026-10) artık kod tarafı hazır beklemede — içerik değişmedi. Önceki metin: **Round 12 (yeni):** proje-düzenle sheet sorununun **ekran görüntüsü** (Mahir gönderecek — OPH-212 kök nedeni koddan da üretilebilir, BLOKLAMAZ); ekran-açık alarm gözleminin cihaz/OS bilgisi OPH-214 turunda birlikte netleşir. **Round 11:** (a) **OpenAI "Sign in with ChatGPT" geliştirici ilgi formuna kayıt** (ücretsiz; program açılırsa `auth_mode='oauth_subscription'` hazır — OPH-215 notu); (b) **üç ayda bir sağlayıcı politika kontrolü** (Anthropic/Google/OpenAI abonelik-OAuth duruşu — AI.md §1 güncellenir; ilk kontrol ~2026-10); (c) Epic 20 sonunda alliswell.space için **Claude Connectors Directory + ChatGPT app dizin başvuruları** (OPH-227 hazırlar, inceleme dış taraf). Öncesi: **Round 9 cihaz işleri — Xcode kısmı ARTIK YOK, sadece telefonu kullanmak kaldı:** (0a) **OPH-182 — iOS 26 cihazda AlarmKit passi.** Hedef üyeliği + `AppDelegate` + Live Activity + iki plist **yapıldı ve derlendi**; kalan tamamen elle test: uygulamayı cihaza kur, acil bir görev kur, **sessiz anahtarı AÇIK + Uyku Odak AÇIK + ekran KİLİTLİ** senaryosunu koş, Onayla/Ertele'yi (biri uygulama kapalıyken) dene, **Ayarlar ▸ Alarm günlüğü'nde `lane=alarmkit` satırlarını gör**. İlk çalıştırmada iOS bir **alarm izni** soracak — reddedilirse hat sessizce bildirim zincirine düşer (istenen davranış ama testi geçersiz kılar). Adımlar: [ALARMKIT_SETUP.md](../apps/app/ios/Runner/ALARMKIT_SETUP.md) "Device DoD"; (0b) **OPH-183 — gerçek Apple Watch'ta aynalama/haptik ölçümü** (companion hedefi kararı buna bağlı). Öncesi: **Cihaz turu + macOS imza + Google canlı test HEPSİ TAMAM (2026-07-24).** Kalan eski kullanıcı adımları: (1) **OPH-141 AlarmKit** — **KAPANDI** (2026-07-28): Swift hazırdı ama hiçbir hedefte değildi; OPH-182 bağladı, artık derleniyor; (2) **OPH-142** critical-alerts formu (gönderiliyor — onay gelirse `Runner.entitlements`'e tek satır, KOD DEĞİŞMEZ; asıl yol zaten AlarmKit). Deploy için ayrı (bu tur kapsam dışı): prod R2 + prod Google OAuth redirect + güçlü JWT secret + sunucu/domain.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| Last completed           | **OPH-216 — sağlayıcı adaptörleri (2026-07-30):** 5 adaptör tek sözleşmede, elle SSE parser, fakeai ×5 tel kodlayıcı, katalog + canlı Ollama, bağlantı testi. Önceki: **OPH-215 — AI temeli (2026-07-30):** `ai_connections`/`ai_usage_events`/`ai_action_log` migration'ı, `AI_TOKEN_KEY` (prod boot şartı), `plugins/ai.js`, `routes/ai.js` (status + CRUD, `key_last4`, consent izi), `AI_ENABLED` kapısı; API 411u+51i. Önceki metin: **EPIC 18 (OPH-196…203) — Hızlı Erişim, v0.7.0** (2026-07-29): kullanıcı-kapsamlı `quick_link` varlığı (API + drift v13 + store), rail bölümü, dar-rail popover'ı, telefon bubble'ı + paneli, altı yüzeyde ekleme/kaldırma toggle'ı, dış link dialog'u, emoji/renk/ad, gezinme tablosu + kırık/arşivli/çevrimdışı davranışları. **App 603/603, API 323+43.** Öncesi: **OPH-202 — emoji, renk, ad** (2026-07-29): saf `emoji_input.dart` (tek grafem + recents), emoji/renk sheet'leri, `AwColorSwatchDot` paylaşıma çıktı, rename dialog'unun dispose hatası düzeltildi. **App 595/595.** Öncesi: **OPH-201 — ekleme yolları** (2026-07-29): altı yüzeyde `bolt` toggle'ı (dosya maddesi sheet'in içinde → beş çağıran birden), dış link dialog'u + URL normalizasyonu, 50 limitinin dürüst reddi; üç gerçek hata testlerle bulundu (dialog controller dispose'u, şemalı URL'e https eklenmesi, FakeApi id çakışması). **App 587/587.** Öncesi: **OPH-200 — telefonda yüzen düğme + panel** (2026-07-29): `MaterialApp.builder` katmanında host, saf fizik (kenar yapışma/klamp/boya-recede/kalıcılık), `AwModalRouteObserver` ile modal gizlemesi, kök navigator anahtarıyla açılan panel, Ayarlar anahtarı + app bar yedeği. **App 581/581.** Öncesi: **OPH-199 — geniş ekran rail bölümü + dar rail popover'ı** (2026-07-29): paylaşılan satır/menü/liste widget'ları, `NavigationRail.trailing` bölümü, `MenuAnchor` popover'ı, saf gezinme tablosu + `/files/folder/:id` rotası, `quick.*` i18n ve halka kontrast çiftleri. **App 562/562.** Öncesi: **OPH-198 — Quick Access replikası + store** (2026-07-29): drift **v13** `quick_links` (istemcide `deletedAt` YOK — tombstone satırı siler), applier'ın üç kaydı, `currentUserIdProvider`, `QuickAccessStore` (add/rename/emoji/renk/kaldır + **tek mutasyonluk** reorder), beş LEFT JOIN'li canlı `watchMine` (hedef adı/rengi, arşivli/tamamlanmış/kırık bayrakları) ve dört store'un silme yoluna yerel kaskad (`forgetQuickLinksFor`, outbox'a yazmaz). **App 556/556.** Öncesi: **OPH-197 — `quick_links` API + kullanıcı-kapsamlı sync varlığı** (2026-07-29): migration (iki FK CASCADE, `uq_quick_links_user_target` + iki arama indeksi, `emoji varchar(16)` = 16 KARAKTER), `db/quick-links.js` (limit/tekillik/hedef kontrolleri + `cascadeDeleteQuickLinks` + `writeQuickLinkOrder`; REST ve push tek implementasyon), beş uç, push/pull kaydı, beş silme yolunda kaskad (arşiv dokunmuyor). Üç protokol dokunuşu: `checkOwnership` (kod dizesi dönebilen `ownershipOk` — eskisi string'i sessizce geçiriyordu), `duplicateCode` (sabit `'tag'` kontrolü genelleşti), pull'da `userScoped` loader + görünmeyen satırların **tamamen** düşürülmesi. **API 323 unit + 43 entegrasyon** (gerçek MySQL'de iki üyeli pull izolasyonu, NULL'lu tekillik semantiği ve kaskad dahil). Öncesi: **OPH-196 — Hızlı Erişim araştırma pası + DESIGN §23 kalibrasyonu** (2026-07-29, kod yazmadı): AssistiveTouch'ın **%40** boşta opaklığı (Apple'ın kendi varsayılanı) §23 Q4'teki tahmini %55'in yerini aldı; **Q4a** yarı gömülme yalnız boya oldu (56 px kutu kaydırılırsa dokunma hedefi 28 px'e düşüyordu — §5 ihlali); **Q4b** %40 soluklaşma §20 C3'ün yazılı istisnası; **Q4c** bubble bir FAB değil (Material: ekran başına tek FAB, o da oluşturma FAB'ı); **Q8a** renk noktası dolgu + 1 px `outline` halkası — 10 paletten 5'i açık temada 3:1'i geçmiyor ve proje rengi paletle sınırlı bile değil; **Q9** sürükleme asla tek sıralama yolu değil (satır menüsünde yukarı/aşağı taşı — erişilebilirlik literatürünün standart cevabı). Notion/Slack karşılaştırması iki farkı yazılı hâle getirdi: ad/emoji/renk **kısayola** aittir (Notion'da sayfaya) ve kısayol **destination değildir**. ADR-0018'e iki sonuç (pull filtresi iki yerde olmak zorunda; kısayollar yalnız soft silinebilir), BLUEPRINT §4.12'ye iki düzeltme (`color`→`color_rgb`, emoji bayt→karakter), park listesine altı yeni gerekçe. Öncesi: **OPH-187 + OPH-188 (kod) + OPH-189 + OPH-194 + OPH-195 — widget sayacı, widget'tan tamamlama, derin bağlantılar, geçiş hayaleti, CRUD taraması** (2026-07-29): rota başına opak zemin (`AwPageBackground`) + tek geçiş ailesi (220 ms, her platform) — hayalet bir animasyon hatası değil **tasarım kuralının sonucuydu**; snapshot **v2** + `openToday` (geciken+bugün; tarihsiz hariç, ertelenmiş dahil) ve iOS/Android başlığı artık aynı çiziyor; widget dairesi iOS 17+'da `Button(intent:)`, Android'de satır başına **iki fill-in intent**, Dart `widgetCallback` → `TaskStore.complete` (**yeni yazma yolu yok**, çevrimdışı çalışır); `alliswell://` iki OS'a kaydedildi + saf/tablo testli çözücü + `/` gerçek rota + kendi `/not-found` ekranımız; CRUD × varlık matrisi ve park kararları TASKS'ta, **DESIGN §22** kuralı yazıldı. **App 544/544, analyze+i18n+kontrast temiz, sürüm 0.6.0+7.** Öncesi: **OPH-190 + OPH-191 + OPH-192 + OPH-193 — ses önizlemesi, tarih girişi, planlanan tarih, proje durumu** (2026-07-28): `core/date_input.dart` tek giriş yolu (create sheet + detayın üç satırı; **`time ?? current ?? default`** düşüş sırası hatanın kendisiydi); `_MovedInCalendarRow` yalnız `scheduledStartAt` doluyken görünüyor + Sıfırla ikisini birden null'lıyor (yarım blok §7.1'de ters blok üretirdi); proje statü dropdown'ı + üç ham enum sızıntısı silindi (sunucu enum'u ve mevcut satırlar dokunulmadı — test doğruluyor); ses picker'ında çalar state'e taşındı, `_PreviewButton` **asla `onPressed: null` değil**, `Future.delayed` → iptal edilebilir `Timer`, yüklenen seslere önizleme + dürüst hata. Round 6'nın "scheduled block görünür" testi **"…EXPLAINS itself"e çevrildi**; OPH-110'un dropdown testi "durum değiştirmenin TEK yolu arşiv" hâline güçlendirildi. **App 530/530, analyze+i18n+kontrast temiz.** Öncesi: **OPH-184 + OPH-185 + OPH-186 — silme, tamamlananların kalıcılığı ve arşivi** (2026-07-28): `AwSwipeToDelete` (flutter_slidable üstünde, görünen her şey bizim) + `PendingDeletes` (ertelenmiş commit; **uygulama pencere içinde ölürse hiç silinmez** — güvenli yön) 6 yüzeyde; görev detayına silme; Notlar/Projeler menülerine "Sil"; **not ızgarasına hiç olmayan eylem menüsü**; Pano'da swipe YOK (D6) ama taşıma sayfasında silme var. `watchOpen(..., completedSince:)` + canlı `dayBoundaryProvider` (gece yarısı timer'ı **+1 sn pay** ve `resumed` dinleyicisi — askıdaki uygulamanın timer'ı ateşlemez); tamamlanan satır grubunun SONUNA iniyor (widget de aynı sırayı kullanıyor). `watchCompleted` **join'siz sayfalanıyor** — join'li `LIMIT` JOIN satırlarını sayar, 3 etiketli görev sayfanın üç slotunu yerdi; bedeli (etiket yeniden adlandırmasında yeniden yayınlamaz) yazıldı. drift **v12** `idx_tasks_completed`, `onCreate`'e DE eklendi (drift `createAll` ad-hoc indeks yaratmaz → yeni kullanıcılar sessizce tam-taramada kalırdı), test indeksi **sqlite kataloğundan** doğruluyor. Yan temizlik: proje satırındaki ham `paused` enum'u kalktı. **App 520/520, kontrast FAILURES: 0 (8 yeni çift), analyze+i18n temiz.** Öncesi: **OPH-182 + OPH-183 (kodsal) — AlarmKit hattı GERÇEKTEN bağlandı** (2026-07-28): `AlarmKitBridge.swift` **Runner hedefinde**, `AppDelegate` onu kuruyor, `ios/Shared/AWAlarmShared.swift` (metadata + App Intent'ler) **iki hedefte** derleniyor, `AWAlarmLiveActivity` widget extension'da, `NSSupportsLiveActivities` iki plist'te; wiring **idempotent betikte** (`ios/scripts/wire_alarmkit.rb`). **Kaynak ağacından değil ÜRÜNDEN doğrulandı:** app dylib'i + `.appex` `AlarmKit.framework`'e weak link veriyor, ikisinde de `Metadata.appintents` var. **SDK gerçeği taslağı beş yerde çürüttü:** `AlarmAttributes`/`AlarmConfiguration` generic; **`Alarm`'da `attributes` YOK** → id↔UUID gidiş-dönüşü tek kurtarma yolu; **`State`'te `.stopped` YOK** → düğmeler `LiveActivityIntent` ile geliyor; `alarms` throwing property; `@available(obsoleted:)` overload'u derlenmiyor (taslak hiç derlenmemişti — çünkü hiç derlenmemişti). **Düğmeler uygulama kapalıyken çalışıyor** → intent'ler App Group kuyruğuna (`AWAlarmActionQueue`, 32 tavan) yazıyor, Dart handler kurulur kurulmaz + her öne gelişte `drainPendingActions` ile boşaltıyor. **Bilinçli sapma:** erteleme `.countdown` değil **`.custom`** — planner zaten yeniden kuruyor (`.countdown` tek ertelemeyi İKİ alarma çevirirdi) ve OS'un sahiplendiği erteleme görev satırına/diğer cihazlara ulaşmazdı (ADR-0015 karar 9). Buton metinleri+ses **Dart'tan** geçiyor (ses adı id tohumunda), erteleme = kullanıcının sıralamasındaki ilk preset (ekranda yazılı). **Lane 8 alarmla sınırlı**; sığmayan **bildirim zincirini koruyor** → planner'a bayrak değil **kapsanan reminder id kümesi** gidiyor (bayrak olsa limit üstü acil alarm iki lane arasına düşerdi); taşma + `limit_reached` günlüğe, **reddedilen `degraded`, asla `scheduled` değil**. OPH-183: companion **AÇILMIYOR**, Ayarlar'a Apple Watch yardım satırı + NOTIFICATIONS §2d. Yan kazanç: `Podfile.lock` OPH-180'in `audioplayers`'ını nihayet aldı. **App 493/493, `flutter build ios` iOS 26.2 SDK'sına karşı geçti, analyze+i18n+kontrast temiz.** Öncesi: **OPH-181 — zil sesi kütüphanesi + özel ses yükleme** (2026-07-28): iki paketli ton üretildi (`aw_chime`/`aw_ping`; asset + `res/raw` + `.caf`), **pbxproj'a dokunulmadı** — `UNNotificationSound` container'ı bundle'dan ÖNCE okuduğu için sesler çalışma anında `Library/Sounds`'a kuruluyor (`sound_store.dart`, io/web seam). Özel sesler ayrılmış **"Zil sesleri"** klasöründe sıradan workspace dosyası; seçilince indirilip kuruluyor. **Ses adı plan içeriğinin parçası** → sesi değiştirmek yeniden planlıyor; Android kanalı ses başına (kanallar değişmez). **OPH-176'dan taşınan bekçi burada:** kurulu dosya yoksa `degraded` günlüğe + OS sesine düşüş. **Bilinçli sınır:** Android'de yüklenen ses kanal sesi olamaz (FileProvider gerekir → park), uygulama içi alarmda çalıyor, picker'da yazılı. Format dürüstlüğü (mp3/m4a yalnız uygulama içi) yükleme VE seçim anında söyleniyor. Ders: `RadioListTile.groupValue/onChanged` deprecate → `RadioGroup`. **App 485/485.** Öncesi: **OPH-180 — uygulama içi alarm sesi** (2026-07-28): `audioplayers` seçildi (ADR-0015 §7 güncellendi — tek paket tüm hedefler + iOS `.playback` kategorisi ve Android `USAGE_ALARM`), 28 sn'lik yatak **Flutter varlığı** oldu (`assets/audio/aw_alarm.m4a`), `AudioAlarmFeedback` mevcut seam'e girdi (ses + haptik; `HapticAlarmFeedback` sessiz platformlar için kaldı), **`AlarmFeedback.soundBlocked`** → tarayıcı autoplay'i engellerse ring ekranı "Sesi başlat" gösteriyor (çalan gibi görünen sessiz alarm yok). `syncTestOverrides(alarmFeedback:)` eklendi (aynı provider'ı iki kez override etmek Riverpod hatası). **Masaüstü/web'in ilk gerçek alarm sesi.** Cihazda duyulma testi cihaz turunda. **App 472/472.** Öncesi: **OPH-179 — hatırlatıcı profili + Hatırlatıcı Sistemi Ayarları** (2026-07-28): `kUrgentChainOffsets` **silindi** → `planNotifications(..., profile:)`; saf `ReminderProfile` (JSON saklama, bozuk → fabrika, **asla boş zincir**, ≥1 dk, ≤20, `alarmsFullyCovered = 40 ~/ slot`) + `repeatAfterSnooze` (spec'te yoktu, editörde bariz soru); presetler Sakin/Standart/**Israrcı(10)**; ekran: canlı zaman çizelgesi (22:42 örneğiyle), stepper'ı komşu adımlarla sınırlı adım listesi (1 dk kuralı **düzenlerken** uygulanıyor), 10 uyarı üstünde **dürüst kapasite uyarısı**, fabrikaya dön; **sürükle-bırak yalnız erteleme düğmelerinde** (N4) ve ring ekranı bu sırayı uyguluyor. Dersler: `ReorderableListView` mobil hedefte **gecikmeli** sürükleme ister (düz `drag` çalışmaz), `onReorder` → `onReorderItem`. **App 466/466.** Öncesi: **OPH-178 — süresiz erteleme / alarmı sustur** (2026-07-28): `tasks.alarms_muted_at` migration (gerçek MySQL'de uygulandı) + sıradan task alanı olarak REST PATCH + sync FIELD (**yeni endpoint yok** → çevrimdışı da bedelsiz). **Motor kod değişmedi:** `alarmInstantsFor` OPH-175'te ileriye dönük yazılmıştı; susturunca iki alarm satırı da `cancelled` olup her cihaza gidiyor. App: drift **v11**, `taskAlarmInstants` + **sentetik alarm sorgusuna** `alarmsMutedAt.isNull()` filtresi, ring ekranında "Süresiz ertele", **bildirim aksiyonu `mute`**, detayda switch, görev satırında `notifications_off` çipi + "Geri aç" (an geçmişse dürüstçe söylüyor). **Görev AÇIK kalıyor** — testler `status`/`completedAt`/tarihleri ayrıca doğruluyor (A5). **App 446/446, API 292+39.** Öncesi: **OPH-177 — erteleme netliği** (2026-07-28): preset butonları çalacağı saati yazıyor ("5 dk · 22:47'de çalar"), erteleyince snackbar "22:52'de tekrar çalacak", görev satırı+detay **"Ertelendi — 22:52"** gösteriyor (`snoozedUntil` bugüne kadar hiç görünmüyordu — susturulmuş görev kurulu görünüyordu), **özel ertele** geldi (BLUEPRINT §8.2 borcu), `reminders.snooze_count` (migration gerçek MySQL'de uygulandı; REST + sync artırımı; yeniden kurmada **0**) → `notif.afterSnooze` sayılı ("{count}. tur"). **Sync aynasındaki ikiz hata düzeltildi:** `applyReminderSnooze` da yalnız en yeni satırı erteliyordu. Dersler: ring ekranında `pumpAndSettle` asla durmaz (sonsuz nabız) → açık `pump(süre)`; snackbar'ın 4 sn timer'ı teardown'ı patlatır → sonda `pump(6s)`; ring testi `Scaffold` içinde pump edilmeli. **App 441/441, API 290+39.** Öncesi: **OPH-176 — tek yükseklik sözleşmesi + alarm günlüğü** (2026-07-28): yükseklik kararı **saf** `awDeliveryFor({urgent, criticalEnabled})` → `ScheduledDelivery(sound, level)`; `schedule()` bunu **döndürüyor** → günlük "ne istendi"yi kararı veren katmandan alıyor. Zincirin **her** slotu aynı sound/level'a çözülüyor (test); erteleme sonrası ilk slot `notif.afterSnooze` diyor (`status=='snoozed'` — yeni kolon gerekmedi; **tur sayacı 177'de**). **Alarm günlüğü**: drift **v9** `alarm_events` (200 satırlık halka, **sync DIŞI**) + `AlarmLog` + Ayarlar → "Alarm günlüğü" (kapsam cümlesi verinin üstünde, kopyala). Yazanlar: scheduler (iki lane), aksiyon yönlendiricisi, ring ekranı, izin probu. **Ders:** teşhis, teşhis ettiği şeyi bozmamalı — ilk denemede günlük yazımı probe'u yutup **alarmları kapalı cihazı sağlıklı gösteriyordu**; artık `unawaited` + kendi guard'ı. iOS ses bekçisi **181'e taşındı** (native kanal `analyze`/`test` ile doğrulanamaz). **App 437/437.** Öncesi: **OPH-175 — görev saati de bir alarmdır** (2026-07-28): `effectiveRemindAt` → **`alarmInstantsFor(task)`** (remind + urgent'in due'su **bağımsız**; eşit an tekilleşir; terminal/susturulmuş görev boş liste — `alarms_muted_at` şimdiden tolere ediliyor) + `reminders.kind` ENUM migration (**gerçek MySQL'de uygulandı, `down`+`up` denendi**) + `reconcileTaskReminder` tür başına + snooze `reminderId` (yoksa HEPSİ — eskiden yalnız en yeni satır erteleniyordu, yani 3 dk sonra ikinci alarm çalıyordu) + drift **v8** + `watchAlarms` tür başına sentetik (`local:<kind>:<taskId>`) + `acknowledge` aynı türü çözer + `notif.dueNow`. Round 6'nın "remindAt deadline'ı yer" testi **tersine çevrildi**. Dersler: MySQL ENUM'u **tanım sırasıyla** sıralar (alfabetik değil); bu repoda `npm run db:rollback` **`--all`** demek (yerel dev DB'si boşaldı, prod'a dokunulmadı). **API 288 unit + 39 entegrasyon, app 425.** Öncesi: **OPH-174 — tarih/saat biçimi: tek kaynak + ayar** (2026-07-28): `core/date_format.dart` (6 preset **id ile** saklanır — `system`/`dmy_dot`/`dmy_slash`/`mdy_12h`/`iso`/`dmy_long`; spec `date`+`time`+**`short`** taşır; junk → system) + `dateFormatProvider` + Ayarlar'da **sonucu gösteren** picker (aynı örnek an her seçenekte). **9 çağrı yeri** tek biçimlendiriciye bağlandı (create sheet, detay `_DateRow`, task tile, notlar liste+ızgara, dosya satırı, hesap-silme tarihi, Home quick-add ipucu, takvim etkinliği saati, **widget snapshot**). `system` = `DateFormat.jm(locale)` → tr 24h, **en 12h** (D3 böyle yazılmıştı; İngilizce satırlar ve widget bilinçli değişti). Dersler: CLDR AM/PM'den önce **U+202F** koyuyor → iki testte parça bazlı doğrulama; `external_event_tile` `ConsumerWidget`'a çevrildi (saf biçimlendiricinin bedeli). **App 417/417.** Öncesi: **OPH-173 — sheet hizası + "yarın" varsayılanı** (2026-07-28): `task.noProjectsHint` silindi (hizayı bozan `helperText`'in kendisi), `Row` start hizalı, yeni saf `awInitialPickerDate` (`current ?? anchor ?? yarın`; gün aritmetiği constructor'la — DST dersi), hatırlatıcı/planlanan satırları **bitiş gününe** demirli; testler davranışsal (oluşan görevin `dueAt`/`remindAt`'i) + hiza `getRect` ile. Öncesi: **OPH-172 — Home tek kaydırma katmanı** (2026-07-28): yapı **LayoutBuilder-önce**ye çevrildi (banner + Liste\|Pano satırı eskiden LayoutBuilder'ın DIŞINDAydı, bu yüzden telefonda sabitti) → üç dal: geniş ≥720 değişmedi (H2), telefon+Pano'da toggle sabit (H3 — yatay pager onu kaydıramaz, kaydırırsa Liste'ye dönüş yolu ölür), telefon+Liste'de **tek `CustomScrollView`, yalnız app bar sabit** (H1: banner → toggle → quick-add → arama → takvim → gizle/göster → liste). `HomeScreen` artık `ConsumerStatefulWidget`: quick-add'in controller/focus'u **ekranda** yaşıyor (sliver dispose olunca metin uçuyordu; `QuickAddBar` ikisini opsiyonel parametre alır, sahibi kendi yarattığını dispose eder) + odakta `Scrollable.ensureVisible`. **OPH-171'in bıraktığı sınır kapandı:** `_HomeSearchResults` sliver döndürüyor → telefonda arama modunda da çekip yenileme çalışıyor. Testler 5 yeni (H1 chrome kayıyor, H4 metin sağ çıkıyor — **testin dişi:** widget'ın ağaçtan silindiğini de doğruluyor, H3 toggle duruyor, H2 regresyonsuz, arama modu çekilebilir). **App 402/402, analyze+i18n+kontrast yeşil.** Öncesi: **OPH-171 — beş bölümde aşağı çekip yenileme** (2026-07-28): tek `AwRefresh` sarmalayıcısı (token'lı gösterge, **min 450 ms** tutma — replika ms'de dönüyor, çakan spinner "olmadı" demek) + `refreshSection(ref, section)` (syncNow + bölümün dış gerçeği: Home alarm izni probu, Dosyalar depo durumu) + geniş yerleşimde app bar'da `AwRefreshAction` (fare tekerleği overscroll yapmaz). **`SyncEngine.syncNow()` artık `Future<bool>`** — hatayı yutuyordu, o yüzden kullanıcıya "yenilenemedi" denemiyordu. Boş/hata durumlarına `physics` tarifi (iç `SingleChildScrollView` jesti yutuyordu: `AwRefresh` altında Always, sliver içinde Never). Bilinçli sınır: telefonda **arama modu** çekilemez (iç içe scrollable → `depth != 0`), OPH-172'de kalkar. Testler 8/8 (FakeApi `/sync/pull` sayacı + Pano drag regresyonu + çevrimdışı snackbar + `offline` anahtarı); ders: `localKv` Pano seçimini sonraki teste sızdırıyor → `setUp`'ta sil. **App 397/397, analyze+i18n+kontrast yeşil.** Öncesi: **OPH-170 — global Dosyalar bölümü (app)** (2026-07-20): drift **v7** (folders + fileRows.folderId, `from >= 5` guard'ı), applier folder, `FolderStore` (optimistic ağaç; delete = yerel alt-ağaç + tek kök outbox — server kaskadıyla bire bir; `subtreeCounts` F9 onayı), nav `AppSection.files` (en sonda) + FilesScreen (Klasörlerim breadcrumb gezgini + Kaynaklar workspace-UNION'ı + SourceBadge + kaynağa-git), dosya taşıma (`PATCH /files/:id folderId` — 169'un boşluğu + `FilesApi.move`), upload zinciri folderId uçtan uca, tur 7 kart. Dersler: autoDispose family'yi `ref.read`'leme (UnmountedRef — watch'la), 'Files' etiket çakışması → Tab-scoped test finder'ları. **App 366/366, API 281+37, analyze+i18n+kontrast yeşil.** Öncesi: **OPH-169 — klasörler + workspace dosyaları (API)** (2026-07-20): migration (folders + files.folder_id FK'sız + workspace enum üyesi; NULL-parent unique boşluğu → kök seviye API-guard), `db/folders.js` (depth/cycle/BFS + **deleteFolderSubtree** — tek transaction tombstone + commit-sonrası GC + kök revizyonu döner; REST ve sync push aynı impl), `routes/folders.js` (sayılı recursive DELETE; **ad benzersizliği ADR-0013 fold'uyla** — collation değil), files init/list workspace hedefi + folderId, sync `folder` push-pull (customDelete kontratı: revizyon dönmeli). Unit 281/281, **entegrasyon 37/37 (klasör sil → MinIO objesi ölür, BullMQ poll)**. Dersler: multibyte gövde bayt≠karakter (HeadObject 409), Crockford 'FOLDER'→'01FDR', sync push clientMutationId da 26 karakter. Öncesi: **OPH-168 — Pano (Kanban) Home görünümü** (2026-07-20): Liste | Pano SegmentedButton (`homeViewProvider`); pano **kendi kaynağını** izler (`boardTasksProvider`/`watchAll` — terminal statusların verisi planlama listelerinde yok); sütun görünürlük+sıra `boardColumnsProvider` + "Görünümü düzenle" (ReorderableListView); geniş=320px sütunlar, telefon=PageView .90 peek + 48dp kenar-hover pager ilerletme; Yol A long-press drag (sütun gövdesi komple hedef, undo snackbar + SemanticsService announce), Yol B AÇIK taşı ikonu → status sheet (K3 gizli long-press-release yerine görünür affordance — bilinçli sapma, TASKS'ta); boş sütun `initialStatus`'lu create; `board.*` i18n. 5/5 test; app 362/362; kontrast 0. Öncesi: **OPH-167 — arama: TR fold + 3 ekran** (2026-07-20): JS fold aynası (`lib/fold.js`) + cross-stack parite fixture'ı (`fold_parity.json`, iki süit); drift **v6** (9 `*_fold` kolonu + Dart backfill; ders: v3 createTable güncel tanımı yaratır → v6 addColumn'lara `from >= 3` guard'ı, yoksa duplicate column); applier + 4 store fold dolduruyor; `SearchService` (tier CASE + GROUP_CONCAT tag agregasyonu + LIKE ESCAPE) + `searchSnippet`; `AwSearchField` (250 ms debounce); Home arama modu (görev+Fikirler+etkinlik tek sıralı liste, bağlam satırı, ≥150 ms progress, S5 temizleme), Notlar as-you-type'a terfi + fold motor + başlık>gövde sırası, Projeler fold filtre; tasks `?q=` (fakedb MATCH taklidi genelleşti). Testler: parite ×2, servis ×7, migration v6, 3 akış, API q=. **İki ders:** (1) liste hydration'ı için combineLatest yerine TEK watched JOIN (drift iki tabloyu tek stream'de izler — emisyon semantiği testlerin dayandığı şekilde kalır); (2) telefonda arama alanı SCROLL'UN İLK SLIVER'ı (OPH-103 felsefesi — sabit satır alan yemez) ve searching modunda aynı ağaç konumunda kalır (remount = yazarken odak/metin kaybı); sabit-yükseklik test yüzeyinde sliver'lar fold altını BUILD ETMEZ — sync testleri geniş yüzeye alındı. Öncesi: **OPH-166 — create sheet'te ek seçimi** (2026-07-20): Ekler bölümü (yalnız create modu — edit detaydaki tam bölümü kullanır), `filePickerProvider` ile bekleyen satırlar (kaldırılabilir; upload YOK — sahip task henüz yok), kaydet → `TaskStore.create` id'siyle `uploads.start` (`unawaited`, sheet beklemez), storage-off'ta AttachmentsSection'ın dürüst satırı. Yeni i18n gerekmedi. Test: 2 seç → 1 kaldır → kaydet → tek dosya yeni task id'siyle fake sunucuda ready. Öncesi: **OPH-165 — etiket sistemi: chip-input + otomatik oluşturma + yönetim** (2026-07-20): `TagStore` (optimistic create/rename/setColor/delete + outbox; delete yerel join satırlarını da süpürür), `TagInputField` (Tab/Enter/virgül commit; fold-duyarsız öneriler; "Oluştur: #ad"; '#' yalnız gösterim; seri giriş), create sheet + detail entegrasyonu (_TagPicker öldü), "Etiketleri yönet" sheet'i (palet + sayılı silme onayı), satırlarda ≤2 `_InlineTag` + "+N". **`core/fold.dart` doğdu** (ADR-0013: İ/I/ı→i önce + Latin harita). **Gerçek bug bulundu:** liste watch'ı tagIds hydrate etmiyordu (yalnız watchDetail) → `_watchList` combineLatest'le dolduruyor; ders: `const []`'e cascade `..sort()` çağrısı UnsupportedError — `(x?..sort()) ?? const []` deseni. Öncesi: **OPH-164 — görev açıklaması + linkify** (2026-07-20): create sheet'e açıklama alanı (1→4 satır; boş=null; triage modu ön-doldurur), detail'e `_DescriptionField` (görüntülemede `LinkifiedText` — URL'ler tıklanabilir, `urlLauncherProvider` seam'i; tap→düzenleme; başlığın autosave DNA'sı: 1500 ms debounce + odak kaybında flush; boşken "Açıklama ekle"). Saf `core/linkify.dart` (kayıpsız segmentleme, kuyruk noktalama kırpma, Wikipedia parantez sezgisi, www→https) + recognizer yaşam döngüsünü sahiplenen `widgets/linkified_text.dart`. `signedInAppWith`'e `extra` override param'ı eklendi (gelecek testler için seam). OG önizleme v2 parking. Öncesi: **OPH-163 — proje seçicide "+ Proje ekle"** (2026-07-20): `kCreateProjectValue` sentinel'li girdi + paylaşılan `ProjectPickerField` (sentinel içeride çözülür; uncontrolled DropdownButtonFormField epoch-key'le re-seed — iptal edilen create sentinel'i görünen değer olarak bırakamaz); `showProjectEditSheet` → `Future<String?>` (create dalı id pop'lar); iki site geçirildi (create sheet + detail); `project.addFromPicker` i18n. Widget testi: picker'dan oluştur → seçili gelir → task push'unda projectId eşleşir. Öncesi: **OPH-162 — Takvim sekmesi kaldırıldı; seçili gün ufku aşıyor** (2026-07-20): `AppSection.calendar` + `calendar_screen.dart` + router/FAB/tur bağımlılıkları + `nav.calendar*`/`tour.calendar*` i18n anahtarları silindi (tur 6 karta indi). Kritik keşif: `groupTasksForHome` seçili-gün kontrolünü horizon'dan ÖNCE yapıyor — "seçili gün ufku aşar" davranışı ZATEN doğruydu; bayat yorumlar güncellendi + (+68 gün) testi eklendi. Takvim-sekmesi widget testleri Home-tabanlı eşdeğere dönüştü (meeting satırı + read-only Checkbox'suzluk artık Home'da assert ediliyor). Öncesi: **OPH-161 — varsayılan görev saati: 23:59 + Ayarlar tercihi** (2026-07-20): `defaultTaskTimeProvider` (PersistedChoice 'alliswell_default_task_time', fallback '23:59') + `parseTaskTime` (bozuk tercihte 23:59 — çöp değer görev oluşturmayı kıramaz) + `applyDefaultTaskTime`; 4 sabit 09:00 sitesi tek kaynağa bağlandı (create sheet initialTime+fallback, detail `_DateRow` → ConsumerWidget, home quick-add, shell FAB); Settings'e `showTimePicker`'lı satır (dil satırı idiomu, yerelleştirilmiş saat alt yazısı); `settings.defaultTaskTime.*` i18n (en+tr). Snooze'un "tomorrow morning" 09:00'u AYRI kavram — bilinçle dokunulmadı. Testler: parse/apply/round-trip unit'leri; quick-add 23:59 assert'i (eski test güçlendirildi); notifier'la '07:15' → quick-add kullanıyor. Öncesi: **OPH-160 — Google connect: otomatik primary takvim + anında ilk sync** (2026-07-20): callback artık primary takvimi kendisi seçer (`listCalendars` → `primary:true`), `sync_token=null + sync_dirty_at` yazar ve mirror sweep + `enqueueSync` + `enqueueWatch` kuyruklar — PATCH dalının birebir aynısı; gizli "takvim seç" adımı öldü. Reconnect seçili takvimi KORUR ama feed'i yine tazeler (bayat kanal/cursor). Auto-select non-fatal: listeleme patlarsa tokenlar kayıtlı kalır, eski "takvimi seç" metni döner. App: `_pullSoon()` — `chooseCalendar` sonrası + onResume'da `syncNow()` (60 sn bekleme yok). Callback HTML'i dürüst: "etkinlikler arka planda senkronize ediliyor". Testler: oauth suite'ine uçtan uca yeni test (seed'li meeting callback→idle sonrası `calendar_external_events`'te; reconnect external sayacı artırıyor), app testinde önce-pull-yok/sonra-pull-var assertion'ları. **API 274/274, app 322/322, analyze temiz.** Öncesi: **Round 8 doküman revizyonları** (2026-07-20): 6 paralel keşif (calendar bug izi, app/API/docs haritaları, kanban mobil UX araştırması — Trello/Jira/GitHub/NN-g kaynaklı, arama tech araştırması — SQLite/MySQL ampirik doğrulama) → BLUEPRINT/DESIGN/ARCHITECTURE/ATTACHMENTS revizyonları + ADR-0013 (local-first arama, TR fold) + ADR-0014 (klasörler & global Dosyalar) + TASKS **Epic 15 (OPH-160…170)** + parking-lot güncellemesi + ADR index 0011-0014. Kritik teknik bulgu: `ı→i` fold'unu NE SQLite (FTS5 unicode61) NE MySQL (utf8mb4_0900_ai_ci — DUCET'te ı ayrı primary weight) yapabiliyor → fold app-owned olmak ZORUNDA (tek util + cross-stack parite fixture'ı). Öncesi: **OPH-143 — foreground alarm ekranı + dürüst uyarı banner'ları** (2026-07-19): urgent alarm due olduğunda uygulama açıksa `AlarmRingScreen` (solid takeover + prioUrgent wash + pulsing ring, Onayla + snooze 5/30 dk & 1 saat + Tamamla/Aç, `PopScope(canPop:false)` — alarm cevaplanır, kapatılmaz); `AlarmOverlayController` replika alarm feed'ini + foreground timer wheel'i (sonraki urgent fire'a kurulur) izler, HomeShell'de tur'un ÜSTÜNDE (acil alarm onboarding'i geçer). Ring kararı saf fn (`ringingAlarm(alarms, now)` — DoD "fake clock" = now). Auto-show `alarmOverlayAutoShowProvider` ile testlerde OFF (OPH-111 idiomu — yoksa her tam-app testini kaplardı); insistence seam (`AlarmFeedback` → `HapticAlarmFeedback` haptik; `SilentAlarmFeedback` testte) — audio cihaz turuna ertelendi (mobilde OS bildirimi 28sn bed'i zaten taşıyor; masaüstü/web best-effort). `AlarmDegradationBanner` Home'un tepesinde (bildirim kapalı / Android exact-alarm reddi — worst-first cascade, tap izin akışını yeniden koşar). Yeni `alarmSupportProvider`, `alarm.*` i18n (en+tr), DESIGN §11 (A1…A4), NOTIFICATIONS §3 güncel. **App 322/322, analyze + check:i18n + kontrast (FAILURES: 0) temiz.** Öncesi: **OPH-157 (kod+docs) — usage footer + kurulum dokümanları** (2026-07-18): Files sekmesine "{count} dosya · {size} kullanımda" alt satırı (`FilesApi.usage` + autoDispose provider — kota v2), README 📎 bölümü, ATTACHMENTS.md §0a durum tablosu, SECURITY.md depolama modeli, ROADMAP Phase 8/v0.3.0. Kalan: manuel cihaz/web matrisi (cihaz turu). **App 306/306, API 273 birim + 36 entegrasyon.** Öncesi: **OPH-156 — notlarda satır içi medya** (2026-07-18): NoteMediaButtons (yeni not önce zorla kaydedilir; medya-dışı seçim dürüst snackbar'la SADECE ek olur), `awNoteEmbedBuilders` editör+README'de (`alliswell://file/{id}` → riverpod family ile mint edilen URL; **ders: build içinde future üretme — provider cache'le, yoksa ağaç asla durulmaz**; FileUrlCache artık future memoize ediyor + null'u kısa süre cache'liyor), Dart markdown paritesi (fixture birebir; eski 'skips embeds' fixture'ı API'deki gibi güncellendi), fake ULID dersi (Crockford I/L/O/U dışlar — 'FIL…' seed'leri regex'e takıldı, 'FDS…' oldu). 7 test. **App 306/306.** Öncesi: **OPH-155 — proje Files sekmesi** (2026-07-18): 4. sekme `_ProjectFilesTab` — canlı UNION toplu listesi, kaynak rozetleri + filtre çipleri, ad/boyut/tarih sıralaması, projeye yükleme (üst aksiyon satırı — FAB değil, Tasks/Notes sekme kalıbı), OPH-154'ün paylaşılan satır/aksiyonları aynen. 5 widget testi. **App 299/299.** Öncesi: **OPH-154 — task detayı Attachments** (2026-07-18): paylaşılan dosya UI seti (`file_widgets.dart` — F1 tek satır anatomisi: FileRowTile/UploadRowTile/aksiyon sayfası/rename+silme onayı/tam ekran görüntüleyici/formatBytes), task detayına AttachmentsSection kartı, `file.*` i18n (en+tr), FakeApi'ye storage+file uçları ve `seedFile`; syncTestOverrides `filePicker`+`uploadTransport` paramları. 4 widget testi (satır render, upload→senkron satır, adlı silme onayı, yapılandırılmamış durum). **App 294/294, kontrast FAILURES: 0.** Öncesi: **OPH-153 — app veri katmanı** (2026-07-18): drift **v5** `file_rows` (pull-only, ExternalEvents modeli) + applier + migration testi; `FileStore` (hedef listesi + proje toplu görünümü TEK customSelect UNION'la, canlı stream); `FilesApi` + `FileUrlCache`; `UploadsNotifier` (init→çıplak-dio presigned PUT [auth header imzayı bozar]→complete→syncNow; io'da diskten stream, web'de bytes; iptal→abort DELETE; retry taze init'le); `file_picker` 11 seam'i `syncTestOverrides`'ta. **App 290/290, analyze temiz.** Öncesi: **OPH-152 — okuma yüzeyi + pull-only sync + kaskad** (2026-07-18): download-URL ucu (isteğe bağlı mint, adı RFC 5987 ile taşır), hedef + `?projectId=` toplu listeleme (kaynak rozetli), rename (yalnız metadata), `file` sync pull'da (push `SYNC_UNSUPPORTED_ENTITY` — ADR-0008 modeli), `cascadeDeleteFiles` task alt-ağacı/not/proje silmelerine bağlandı (REST + sync push; commit-sonrası obje-silme kuyruğu), usage ucu, markdown export embed'leri (`![ad](alliswell://file/{id})` — OPH-045 fixture'ı bilinçli güncellendi, Dart paritesi OPH-156'da). Unit 273/273, entegrasyon 36/36. Öncesi: **OPH-151 — upload yaşam döngüsü** (2026-07-18): `files` migration'ı (opak `storage_key`, uploading | ready, rollback doğrulandı), init→PUT→complete el sıkışması (complete idempotent; HeadObject boyut doğrulaması — yalan söyleyen upload'ın objesi silinir, satır düşer), DELETE (abort=hard delete / ready=tombstone), `plugins/storage-gc.js` (storage-delete kuyruğu + 24s stale-upload süpürmesi). Unit 255/255 (15 yeni), entegrasyon 35/35 (gerçek PUT + BullMQ worker'ın objeyi sildiği doğrulandı). Öncesi: **OPH-150 — storage foundation** (2026-07-18): S3/R2 config bloğu (kısmi config = boot hatası), enjekte edilebilir `plugins/storage.js` (presignPut/Get + RFC 5987 `filename*`, head, idempotent remove), `GET /api/v1/storage` durum ucu, compose'da MinIO + CI'da `docker run` MinIO (service container command override edemiyor — sapma TASKS'ta), bucket'ı retry'la yaratan test bootstrap'i. **Unit 240/240 (17 yeni), entegrasyon 32/32 (4'ü gerçek MinIO'ya karşı presigned round-trip), lint+format+no-ts temiz.** Önceki: **OPH-137+138+139 — feedback round 6 çekirdeği** (2026-07-18): TR "Fikirler" + Home dim dürüstlüğü; acil task **due saatinde** alarm (API `effectiveRemindAt` + app sentetik alarm); gerçek alarm sesi (28 sn caf/m4a) + iOS timeSensitive/critical gate + Android `urgent_alarms_v2` (USAGE_ALARM + insistent + FSI) + Settings dürüst izin satırı. **App 280/280, API birim 223/223 + entegrasyon yeşil, analyze + check:i18n + kontrast temiz, `flutter build ios` GEÇTİ (caf bundle'da doğrulandı).** |

## Recently completed

- **🚀 v0.6.0 CANLI (2026-07-29):** `git push origin v0.6.0` → gate (Flutter +
  MySQL + MariaDB) → GitHub Release (prerelease, workflow'un 1.x-olmayan kuralı)
  → GHCR imajları (api + web, amd64/arm64) → prod deploy. Kanıt:
  `https://api.alliswell.space/` → `"version":"0.6.0"`, `/health/ready` →
  mysql+redis up. **Migration YOK** — bu turun tek şema değişikliği istemci
  tarafında (drift v12, yalnız indeks). **Gate ilk turda bir kez düştü ve bu bir
  ders değil bir flake:** MariaDB işinde `files-upload` entegrasyon süiti
  kaydolmada 500 verdi (17/18 dosya yeşildi, MySQL işi tamamen yeşildi) ve
  `git diff v0.5.0..HEAD -- apps/api` **yalnız sürüm satırını** gösteriyor —
  yani API'ye bu turda dokunulmadı. `gh run rerun --failed` ile ikinci turda
  49 sn'de yeşil. Kalıcı not: bu iş paralel container'larla argon2id'li kayıt
  koşuyor; tekrar ederse süitin izolasyonuna bakılmalı, koda değil.

- **🚀 v0.5.0 CANLI (2026-07-28):** `git push origin v0.5.0` → gate (Flutter + MySQL +
  MariaDB) → GitHub Release → GHCR imajları (api+web, amd64/arm64) → prod deploy, **tek
  turda yeşil**. Kanıt: yedek `db-20260728-065331-pre-v0.5.0.sql.gz` (20K), `checked out:
  v0.5.0`, **Batch 2: 4 migration** (Epic 16'nın üçü + bekleyen `add_account_deletion`),
  `https://api.alliswell.space/` → `"version":"0.5.0"`, `/health/ready` → mysql+redis up.
  Release **prerelease** işaretli — workflow'un kendi kuralı (1.x olmayan her şey).
  **Tag iki kez atıldı ve bu bir ders:** ilk tag gate'te düştü çünkü CI **OPH-181'den beri
  kırmızıydı** — `alarm_ring_screen_test.dart` "a custom snooze picks an exact time"
  macOS'ta geçip Linux'ta düşüyordu (ring ekranı kayıyor, custom-snooze butonu 800×600
  yüzeyde tam katlanma noktasında: `Offset(400, 616)`). Isıka tıklama dialog açmıyor,
  sonraki `find.text('OK')` boş dönüyor ve hata bir picker bug'ı gibi okunuyor. Çözüm
  dosyanın kendi idiomu (`ensureVisible`); yüzey 380 px'e indirilip ekran dışı durum
  ZORLANARAK doğrulandı. Hiçbir şey yayınlanmamış olduğu için tag güvenle taşındı.
  **Kalıcı ders: yerelde yeşil ≠ CI'da yeşil; piksel-sınırındaki bir widget'a `tap`
  atmadan önce `ensureVisible`.** İkinci ders (archive'ı submission'da patlatacaktı):
  **app extension'ın sürümü uygulamayla eşleşmek zorunda** — widget extension Xcode
  template varsayılanında (1.0/1) kalmıştı, artık `$(FLUTTER_BUILD_NAME/NUMBER)`'a bağlı.
  Üçüncü: sürüm yükseltince `flutter clean && pub get && pod install` — `Generated.xcconfig`
  eski sürümü cache'liyor ve Xcode Archive onu gömüyor.
- **🚀 v0.4.0 CANLI + CI/CD zinciri uçtan uca yeşil (2026-07-26):** `git push --tags` →
  testler (MySQL+MariaDB+Flutter) → GitHub Release (CHANGELOG'dan notlar) → GHCR imajları
  (api+web, amd64/arm64) → sunucuya deploy. **Deploy 8 turda yeşile ulaştı; her tur gerçek bir
  ortam gerçeğini ortaya çıkardı** (hiçbiri kod hatası değildi, hepsi kalıcı olarak çözüldü):
  (1) PM2 adı yanlış varsayıldı → süreci ÇALIŞTIRDIĞI dizinden bul; (2) PATH'te Node 18 → tüm
  kurulumları tarayıp en yükseğini seç; (3) `/www/server/nodejs` dışında Node yok → `find` ile
  gerçek keşif + envanter raporu; (4) **PM2 kullanıcı başına daemon tutar** — app `www`
  kullanıcısında `alliswellapi` adıyla, root'un listesinde görünmüyordu → çok-kullanıcılı arama
  - `sudo -u www` ile restart; (5) sunucuda yalnız Node 18 var, sahibi bunu tercih etti → sert
    kapı yerine `DEPLOY_MIN_NODE` (varsayılan 18) + her deploy'da uyarı; (6) **rsync "is your shell
    clean?"** — SSH girişinde Telegram bildirimi stdout'a yazıyor → `tar | ssh` akışına geçildi
    (yalnız uzak STDIN kullanır) + dizin swap'i (eski hash'leri de temizler, `.htaccess` taşınır,
    başarısızsa eskisi geri konur); (7) **aaPanel `.user.ini`'yi `chattr +i` yapar** — root bile
    silemiyor → `.user.ini` de taşınıyor, temizlik `chattr -R -i` + best-effort (yayın canlıyken
    artık dosya deploy'u kırmıyor). Deploy artık her koşuda ortam raporu basıyor (node, her
    kullanıcının pm2 listesi) — bir dahaki sorun tek turda teşhis edilebilir. **Kanıt:** yedek
    16K alındı, `checked out: v0.4.0`, 46 dosya yayınlandı, `/health/ready` ilk denemede `ok`.
    Ayrıca `deploy.yml` `workflow_dispatch` ile elle de tetiklenebiliyor (sürüm kesmeden yeniden
    deploy). Ders: sunucu gerçekleri repoda görünmez — pipeline'ın ilk işi ortamı RAPORLAMAK olmalı.
- **Docker dağıtımı + tag'le otomatik deploy (2026-07-26):** `release.yml` iki job kazandı —
  **`images`** (GHCR'a `alliswell-api` + `alliswell-web`, multi-arch amd64/arm64, semver+latest
  etiketleri; web'in Flutter aşaması `--platform=$BUILDPLATFORM` ile tek kez derleniyor, QEMU
  altında iki kez değil) ve **`deploy`** (`vars.DEPLOY_ENABLED` ile korumalı: mysqldump yedeği →
  `git checkout <tag>` → `npm ci --omit=dev` → `db:migrate` → `pm2 restart` → web rsync →
  `/health/ready` "ok" değilse job DÜŞER). **Kilit ders:** non-interactive SSH profili yüklemez ve
  aaPanel Node'u PATH dışına kurar → uzak script PATH'i kendisi kuruyor, yoksa `npm ci`de patlardı.
  **Web imajı için runtime config:** `String.fromEnvironment` derleme anında gömdüğü için hazır
  imaj başkasının domain'ine bağlanamıyordu → `core/runtime_config{,_web,_stub}.dart` +
  `web/alliswell-config.js` + nginx entrypoint'i env'den yazıyor; `apiBaseUrlProvider` sırası
  runtime → dart-define → localhost. **Doğrulama:** API imajı derlenip çalıştırıldı (entrypoint
  migration'ları uyguladı, healthcheck `healthy`, 38005'te `/health/ready` ok), web imajının
  nginx+entrypoint katmanı test edildi (config.js env'den üretildi, `no-store`, SPA `/projects`
  200, tek Cache-Control), ve runtime override GERÇEK tarayıcıda kanıtlandı (login isteği
  derleme varsayılanı 3000 yerine config'in dediği 8080'e gitti). Flutter 379/379, API 283/283.
- **MariaDB desteği — collation sunucuya göre çözülüyor (2026-07-24, deploy sırasında çıktı):**
  aaPanel'li sunucuda `npm run db:migrate` **"Unknown collation: 'utf8mb4_0900_ai_ci'"** ile
  düştü — o collation YALNIZCA MySQL 8'de var, MariaDB'de yok. Envanter çıkarıldı: uyumsuz olan
  TEK şey collation'dı (raw SQL'lerin hepsi — FULLTEXT, `MATCH…AGAINST`, enum `MODIFY` — ve tüm
  kolon tipleri MariaDB uyumlu; window fn/CTE/JSON fn/SKIP LOCKED/CHECK hiç kullanılmıyor).
  Çözüm: `src/db/collation.js` → `resolveCollation(knex)` (pin > `SHOW COLLATION LIKE` probu >
  fallback), 9 migration `let COLLATION` + `up()` içinde resolve; `DATABASE_COLLATION` config'e
  eklendi (DDL'e girdiği için bare-identifier regex'iyle doğrulanıyor) ve `knex.client.config`
  üzerinden migration'lara taşınıyor (AGENTS.md §4: env'i yalnız config.js okur).
  **Doğrulama: MySQL 8.4 37/37 (collation hâlâ 0900 — davranış değişmedi), MariaDB 10.11 37/37
  - rollback/re-apply, MariaDB 11.4 37/37.** CI'a kalıcı `api-mariadb` job'ı eklendi (şema +
    entegrasyon + "unicode_ci'ye düştü mü" assert'i). ADR-0004 §6, ARCHITECTURE §4, .env.example
    güncellendi. Ders: bir collation adı taşınabilirlik sözleşmesidir — sunucuya sor, sabitleme.
- **OPH-141 — iOS 26 AlarmKit lane (Dart done + tested; Swift handed off) + device blockers cleared
  (2026-07-24):** Mahir doğruladı — B1 Google canlı, B2 iOS widget + Time-Sensitive capability, B3
  Android; B4 macOS imza APILLON team `WWRZ5CG3DW`'ye hizalandı (yayın hesabı); B5 critical-alerts
  formu gönderiliyor. **AlarmKit (NOTIFICATIONS.md §2b):** pure `AlarmKitHost` seam
  (`notifications/alarmkit.dart` — MethodChannel + Unsupported default), pure `planAlarmKitAlarms`
  (urgent → tek alarm, zincir YOK — AlarmKit native ring-until-answered) + `planNotifications`
  `routeUrgentToAlarmKit` (çift çalmayı önler), `NotificationScheduler`'a ikinci set-diff (ack/
  complete/snooze AlarmKit alarmını da iptal eder), provider wiring + Onayla/Ertele aynı
  `handleNotificationEvent`'e. Desteklenmez/reddedilirse urgent bildirim zincirine düşer (asla
  kaybolmaz). Swift `ios/Runner/AlarmKitBridge.swift` (Runner-side channel, `@available(iOS 26)`,
  det. UUID + `AWAlarmMetadata` id eşlemesi, `alarmUpdates` gözlemi) + AppDelegate kaydı +
  `NSAlarmKitUsageDescription` — iOS 26 SDK'sına karşı yalnız cihazda derlenir, hand-off (OPH-131
  gibi). Testler: `alarmkit_test.dart` (7) + `scheduler_test.dart` AlarmKit grubu (4), `FakeAlarmKitHost`.
  **App 377/377, analyze + dart format temiz.** Kalan (deploy dışı): widget epiği OPH-132/134/135/136,
  cihaz passleri, OPH-157 QA matrisi.
- **Design round 8 → "Liquid Glass v2" (2026-07-18, ADR-0012):** Apple kaynaklarına dayalı
  tam görsel yenileme — DESIGN.md §1/§3/§4/§5 güncellendi, `tokens.dart`/`theme.dart`/
  `glass.dart`/`home_shell.dart` yeniden yazıldı/geçirildi, `scripts/design/contrast.py`
  yeni paletle 50 çifti doğruluyor (FAILURES: 0), Android widget renk tabloları taşındı,
  kalıcı screenshot harness eklendi (`apps/app/test/design_screenshots_test.dart`).
  Ekran görüntüleri (açık+koyu, telefon+masaüstü) üretildi ve gözden geçirildi.
- **Feedback round 7 → Epic 14 (Attachments & project files, R2/S3) doğdu (2026-07-18):**
  - **Kaynak:** Mahir dosya ekleri istedi — R2 backend'e, tasklara resim/video/dosya eki,
    notlara satır içi resim/video, projede file-manager gibi bir **Files** sekmesi
    (indir/yükle/yeniden adlandır/sil), her tür dosya.
  - **Tasarım kararları ([ATTACHMENTS.md](ATTACHMENTS.md) + ADR-0011):** (1) S3 protokolü
    konuşulur, R2 birincil (MinIO dev/CI) — vendor kilidi yok; (2) **bytes API'den geçmez** —
    3 adımlı presigned upload (init→PUT→complete/HeadObject) + presigned GET indirme (R2
    egress bedava, self-host VPS'i bant genişliği ödemesin); (3) `files` tek polimorfik tablo
    (project|task|note hedefi), key'ler opak `ws/{wsId}/{fileId}`; (4) `file` **pull-only**
    senkron varlığı (ADR-0008 external_event modeli — push `SYNC_UNSUPPORTED_ENTITY`,
    yükleme doğası gereği online); (5) silme kaskadı + commit-sonrası obje-silme kuyruğu +
    24 saat stale-upload süpürmesi = yetim bayt yok; (6) özellik `STORAGE_S3_*` yokken
    kapalı ve dürüst (`STORAGE_NOT_CONFIGURED`); (7) not embed'leri `alliswell://file/{id}`
    şemasıyla (asla presigned URL — süreli); (8) web için R2 bucket **CORS** kurulumu tek
    kullanıcı-tarafı adım (ATTACHMENTS.md §8 rehber).
  - **Kalıcı doküman revizyonları:** BLUEPRINT (§4.3, §4.5, YENİ §4.10, §12.3 Files sekmesi,
    §12.4 Attachments, §12.5 editör medyası, §14 **Phase 8 (v0.3.0)**, §15.3 depolama
    güvenliği, §16 **Risk 7**, §18 Epic 13+14 satırları), DESIGN **§10** (F1…F6 dosya
    bileşen kuralları), ARCHITECTURE **§6b**, TASKS **Epic 14 (OPH-150…157, 8 task)**,
    parking-lot güncellendi (attachments v1'e çekildi; v2 kalanları listelendi).
  - **App keşfi (Explore ajanı):** proje detayı 3 sekmeli `DefaultTabController` (4.'yü
    eklemek yeterli), task detayı `_SectionCard` idiomu, quill 11.5.1 embed builder'sız
    (custom builder gerekecek; `flutter_quill_extensions` YOK), drift v4→v5, REST şablonu
    `GoogleIntegrationsApi` + `urlLauncherProvider` seam'i, `file_picker` eklenmeli.
  - Implementasyon aynı gün OPH-150'den başladı (aşağıya bakın).

- **OPH-133 — Android widget render'ı yazıldı + `flutter build apk` ile DERLENDİ (2026-07-17):**
  - **Ne:** `TasksWidgetProvider : HomeWidgetProvider` (home_widget SharedPreferences snapshot'ını
    okur, tarih başlığı + `setRemoteAdapter` ile scrollable liste, `HomeWidgetLaunchIntent` ile
    tap→uygulama) + `TasksWidgetService`/`TasksRemoteViewsFactory` (bucket'ları düz listeye açar:
    bölüm başlığı + `○/●` check + proje-renk noktası + başlık + saat; lokalize boş durum) +
    `res/xml/tasks_widget_info.xml` (4×2 varsayılan, true 4×6'ya resize) + layout'lar +
    `values(-night)/colors.xml` (DESIGN §3.1 light+dark) + manifest receiver/service.
  - **DOĞRULAMA:** `flutter build apk` **GEÇTİ** (96s; Kotlin+resource+manifest derlenip linklendi;
    tek çıktı home_widget/quill'in KGP-deprecation uyarısı — benim kodumla ilgisiz). Hafıza kuralı:
    Kotlin'i sadece gerçek build derler → bu, cihazsız yapılabilecek en güçlü doğrulama.
  - **Sapma:** Jetpack Glance yerine **RemoteViews** (Compose bağımlılığı ağır + cihazsız
    doğrulaması zor; klasik `ListView`+`RemoteViewsService` daha güvenli derlenir).
  - **Ertelendi (cihaz/arka-plan ister):** etkileşim (uygulamayı açmadan tamamla/ekle — OPH-132 ile
    ortak `widgetCallback`), WorkManager midnight, cihazda görsel tur (3 boyut, light/dark).

- **OPH-131 — iOS widget Swift yazıldı, Xcode/cihaza teslim edildi (2026-07-17):**
  - **Ne yazıldı:** `ios/AllisWellWidget/` — `AllisWellWidget.swift` (OPH-130 JSON'unu birebir
    aynalayan `AWSnapshot` Codable; App-Group `UserDefaults`'tan okuyan `AWProvider`
    TimelineProvider + gece-yarısı `.after` politikası; SwiftUI görünümler: tarih başlığı,
    dairesel checkbox + öncelik noktası + saat + proje rengi olan bucket satırları; boyut başına
    satır bütçesi; `supportedFamilies` medium/large/extraLarge; iOS 17 `containerBackground`
    guard'lı; `.widgetURL(alliswell://open)`), extension `Info.plist` + App-Group `.entitlements`,
    ve **`SETUP.md`** (Xcode adımları).
  - **Neden "bitti" değil:** Widget Extension target'ı yaratmak GUI/pbxproj işi + cihaz build'i
    ister (`analyze`/`test` Swift derlemez). Dosyalar target'ta OLMADIĞI için **app hâlâ derleniyor**
    (270/270); kullanıcı SETUP.md ile target'ı kurup cihazda doğrulayınca kapanır.
  - **Ertelendi:** `alliswell://` deep-link ROUTING (tap doğru ekrana insin) → OPH-132/135.

- **OPH-130 — Widget snapshot core (2026-07-17, Epic 12 başladı):**
  - **Ne:** ana ekran widget'ının Dart tarafı — `lib/src/features/widgets/`. Saf
    `groupTasksForWidget` (overdue→noDate→today→thisWeek→thisMonth, 30-gün rolling ufuk;
    `groupTasksForHome`'un glanceable kardeşi, task-only). `WidgetSnapshot` serializer → küçük JSON
    (WIDGETS.md §3.1: `date{weekday,day,month}` + bucket'lar top-N `items` + `more`), etiketler
    `widget.bucket.*`.tr() ile lokalize, tarih `intl`. `WidgetHost` seam (home_widget üstünde) +
    `WidgetBridge.publish` (configure→save→update) + `widgetSyncProvider` (openTasks/projects
    değişince push; iOS/Android/macOS dışı no-op), `HomeShell`'de izleniyor.
  - **Test edilebilirlik:** bridge `WidgetHost` soyutlamasının arkasında → `FakeWidgetHost` ile
    platform-kanalsız test; `syncTestOverrides`'a da eklendi (tam-app süiti home_widget'a değmez).
    6 test (bucket sınırları + +30 drop, snapshot şekli/en-tr etiket/tarih başlığı/truncation/
    proje rengi, bridge configure-once/save/update). **App 270/270, analyze + check:i18n temiz.**
  - **Sapma:** snapshot task-only (plan "events" diyordu — widget bir görev bakışı; takvim yönünü
    tarih başlığı taşıyor). **Kalan Epic 12 NATIVE** (OPH-131 iOS ext, 132 iOS App Intents, 133
    Android Glance, 134 macOS [imza bloklu], 135 config/gizlilik, 136 docs/QA) — hepsi gerçek
    cihaz/build turu ister; `analyze`/`test` Swift/Kotlin derlemez.

- **OPH-124…128 → Epic 11 (Localization) KAPANDI (2026-07-17):**
  - **OPH-124 (feature string'leri):** projeler/notlar/takvim kartları/onboarding — **3 paralel
    alt-ajan** ~145 string'i çıkardı (proje 62, takvim 39, not+onboarding ~40), her biri İngilizce
    değeri BİREBİR koruyarak (mevcut testler değişmedi). `TourStep` da `AppSection` gibi key+getter'a
    çevrildi. 6 yeni-anahtar gerektiren artık elle bitti. extraction_test spot-check'leri.
  - **OPH-125 (hata + dinamik):** `friendlyAuthMessage` + `home_shell._conflictMessage` lokalize;
    `error.*`/`sync.*` anahtarları; `localizedError()` helper (`AwI18n.maybeTranslate`) + 6
    `AwErrorState('$error')` yeri dönüştürüldü.
  - **OPH-126 (`PATCH /me`):** API endpoint (format-doğrulamalı, sabit allow-list DEĞİL — self-host
    "JSON drop" modelini korur; `loadMe` ortak helper; 4 test). App: `accountLocaleSyncProvider`
    dil seçince best-effort PATCH. **Ertelendi:** sign-in'de me.locale'den seed (app'te `/me` fetch
    akışı yok).
  - **OPH-127 (CI bekçisi):** `scripts/i18n/check.mjs` + `npm run check:i18n` + CI adımı;
    self-test'li. Bekçi 2 kaçağı yakaladı (`month_calendar` ay tooltip'leri) → düzeltildi.
  - **OPH-128 (web lang + docs):** conditional-import ile `<html lang>` (web'de `package:web`),
    `index.html` `lang="en"`; README + CONTRIBUTING "dil ekleme".
  - **Sonuç:** tüm UI EN+TR; dil eklemek = `assets/i18n/<kod>.json` + locale kaydı. **App 264/264,
    API 219/219, `check:i18n` + analyze temiz.** Sıradaki oturum OPH-130 (widget çekirdeği).

- **OPH-120 — i18n foundation (2026-07-17, Epic 11 başladı):**
  - **Ne:** app'e ait **senkron** JSON i18n deposu `lib/src/i18n/i18n.dart` (`AwI18n`
    ChangeNotifier) — `assets/i18n/en.json` (temel/fallback) + `tr.json` `runApp`'ten önce belleğe
    yüklenir (`AwI18n.instance.boot()`), `'key'.tr()` build anında senkron çözülür. Cihaz/tarayıcı
    algılama (`PlatformDispatcher.instance.locales` → ilk desteklenen → `en`; `resolveInitialLocale`
    saf+testli), kalıcı ayar (`localKv` `alliswell_locale`), per-key en fallback, `{name}`
    interpolasyon, runtime switch (`ListenableBuilder`). Üçüncü parti paket YOK (yalnız
    `flutter_localizations` SDK). Widget'lar `'key'.tr()` kullanır; motor tek seam'de.
  - **KİLİT SAPMA (ADR-0009 revize):** önce `easy_localization` kuruldu, sonra geri alındı.
    Paketin `LocalizationsDelegate`'i çevirileri **async** yüklüyor; flutter_test'in fake-async
    saatinde bu yükleme `pumpAndSettle` sırasında bitmiyor → `Localizations` widget'ı tüm app
    alt-ağacını bloke ediyor, **~40 tam-app testi hiçbir şey render etmiyor** ve `.tr()` ham anahtar
    dönüyor. Tek çareler kırılgan (`runAsync` + sabit gecikme) veya paketin `src/`'sine sızıp global
    store'u pre-seed etmek. "Kurumsal kalite" barı için sahip olduğumuz senkron store daha temiz.
    Küçük gerçek bug da yakalandı: `ListenableBuilder`'ın const child'ı locale değişince yeniden
    build EDİLMEZ → `MaterialApp` builder'ın İÇİNDE kuruldu.
  - **Nasıl doğrulandı:** `test/flutter_test_config.dart` (Flutter'ın resmi suite hook'u) JSON'u
    diskten okuyup en+tr'yi senkron cache'e yüklüyor → mevcut testler `pumpAndSettle`'la aynen
    geçiyor, DEĞİŞTİRİLMEDİ. `test/i18n/i18n_test.dart` (11 test): resolveInitialLocale vakaları,
    en/tr çözümü, tr-eksik anahtar en'e fallback, bilinmeyen anahtar passthrough, `{name}` args, +2
    widget testi (`.tr()` render + dil değişimi rebuild) — hepsi plain `pumpAndSettle`. **Süit
    247/247** (236 dokunulmadı + 11), `flutter analyze` temiz.
  - **OPH-121 (dil seçici) de bitti:** Settings → Language modal sheet (System default +
    endonym'ler, check), `setLocale`/`useSystemLocale`, localKv kalıcılık, `boot()` geri yükler;
    `settings.language.*` en+tr'ye eklendi; 5 test (unit + sheet widget). Süit 252/252.
  - **Kalan Epic 11:** string çıkarma (122-124), hata-kodu lokalizasyonu (125), `PATCH /me` (126),
    CI bekçisi (127), web lang + docs (128).

- **Feedback round 5 → Epic 11 (i18n) + Epic 12 (widgets) doğdu (2026-07-17, SADECE docs):**
  - **Kaynak:** Mahir iki özellik istedi — (1) iOS/Android/macOS **ana ekran widget'ları**
    (4×2/4×4/4×6; tasklarla senkron; Home bucket özeti kaydırılabilir; en büyük boyutta Apple-Takvim
    tarzı tarih başlığı; Apple-Reminders tarzı hızlı ekle/tamamla) ve (2) tüm hardcoded string'lerin
    çıkarılıp **JSON dil mekanizması** (cihaz/tarayıcı dili otomatik, en.json fallback, ayarlardan
    kalıcı değişim, en+tr). "Çakışsa bile dokümante et" yetkisiyle kalıcı spec + task olarak işlendi.
  - **Nasıl (araştırma):** widget konusu "çok hassas" istendiği için **2 paralel araştırma ajanı**
    (iOS/macOS WidgetKit + `home_widget`; Android Glance + referans uygulamalar) kaynak-destekli
    tarama yaptı → [WIDGETS.md](WIDGETS.md) (NOTIFICATIONS.md/CALDAV.md analoğu, bağlayıcı plan).
    i18n için `easy_localization` vs slang/gen-l10n karşılaştırıldı.
  - **Araştırmanın kilit bulguları (task/doc'a gömülü ama özet):**
    1. **iPhone'da 4×6 / tam-ekran widget YOK** — WidgetKit'in iPhone tavanı `systemLarge` (4×4).
       "4×6/full" iPad/macOS'ta `systemExtraLarge`, Android'de gerçek 4×6; iPhone'da 4×4'e iner. Bu
       platform sınırı ADR-0010 D6 + WIDGETS.md §2'de revizyon olarak yazıldı (kapsam kesintisi değil).
    2. **Widget ayrı sandbox — drift replica'sını okuyamaz** → App Group (iOS/macOS)/SharedPreferences
       (Android) + `home_widget` ile küçük JSON snapshot köprüsü; native SwiftUI/Glance render eder.
    3. **Etkileşim** iOS 17+/macOS 14+ App Intents (`Button/Toggle(intent:)`), Android Glance
       aksiyonları → `@pragma('vm:entry-point')` Dart callback → yerel-önce `TaskStore` (senkron).
       iOS 16 fallback: derin bağlantı. Ön-plan `updateWidget` push'ları yenileme bütçesinden MUAF.
    4. **Widget = App-Extension target** → plugin paketi vending EDEMEZ; `project.pbxproj` +
       entitlement'lar commit edilir (EventKit "pbxproj yok" modelinden bilinçli sapma).
    5. **i18n:** başta `easy_localization` seçildi ama uygulamada (OPH-120) geri alındı —
       async yüklemesi fake-async test süitiyle çakıştı; app'e ait **senkron** JSON deposuna
       (`AwI18n`) çevrildi (ADR-0009 revize). slang de reddedilmişti (JSON'u derliyor → runtime
       dil DROP edilemez). Sonuç kullanıcının tüm isteklerini karşılıyor, üçüncü parti paket yok.
    6. **`groupTasksForHome` zaten widget bucket'larını üretiyor** — widget onu aynalar
       (`groupTasksForWidget`); `HomeBucketLabel` string'leri i18n'in çıkaracağı türden →
       **Epic 11 (i18n), Epic 12'den (widgets) ÖNCE** gider (widget snapshot'ı lokalize etiket yazsın).
  - **Kalıcı değişiklikler:** BLUEPRINT (§2.6 tech-ref, §3 prensip 13-14, YENİ §12.8 widgets /
    §12.9 i18n, §14 Phase 7, YENİ §15.5 i18n / §15.6 widget köprüsü, §16 Risk 5-6, §18 Epic 11-12),
    DESIGN (§8 widget tasarımı / §9 yerelleştirme), ARCHITECTURE (§7), **ADR-0009** (i18n) +
    **ADR-0010** (widgets), **WIDGETS.md** (yeni). TASKS.md'ye **Epic 11 (OPH-120…128, 9 task)** +
    **Epic 12 (OPH-130…136, 7 task)** ayrıntılı yazıldı.
  - Not: bu tur SADECE dokümantasyon; kod değişmedi, testler koşulmadı (round 4 gibi). Sıradaki
    oturum **OPH-120**'den başlar. Kullanıcı isterse Epic 11↔12 sırası takas edilebilir.

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
    1. _Web sign-out crash'i (OPH-100):_ `auth_api._post` 204'ün web-dio'daki `''`
       gövdesini `as Map` ile cast ediyor; TypeError `AuthException` olmadığından
       `logout()` yerel temizliğe HİÇ ulaşmıyor — sunucu oturumu ölü, app "girili".
    2. _FAB'lar (OPH-101):_ shell `extendBody: true` + cam NavigationBar; iç
       Scaffold'ların FAB'ı (home/projects/notes ×3) barın ALTINA çiziliyor.
    3. _Inbox (OPH-107):_ `status='inbox'` zaten var ve quick-add onu yazıyor; sızıntı
       `kOpenStatuses`'ın inbox'ı içermesi → Home'a düşüyor. Şema işi sıfır.
    4. _Proje arşivi (OPH-110):_ `projects.status` enum'ında `archived` GÜN 1'den beri
       var (migration 20260714000200), sync/REST kabul ediyor — migration GEREKMEZ;
       eksik olan akış (kaskad + varsayılan-gizli listeler + dürüst dialoglar).
    5. _Create sheet'te proje seçici (OPH-106) aslında VAR_ — sıfır projede tek "No
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
    1. _Mezar taşı yarışı:_ bayrak görev yazımından ÖNCE kalıcı olmalı — görev yazımı
       mirror kuyruğunu tetikliyor ve henüz bayraklanmamış link sıradan bayat link gibi
       görünüp siliniyordu.
    2. _Kuyruk keyspace çakışması (üretim hatası, testte ortaya çıktı):_ tüm dağıtımlar
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
    - widget testleri FakeApi'nin yeni `/sync/pull`+`/sync/push` uçlarıyla tam döngüyü
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
- ~~**⚠️ macOS build'i KIRIK (devralınan, OPH-077'de ortaya çıktı, 2026-07-16).**~~ **ÇÖZÜLDÜ
  2026-07-24:** macOS `DEVELOPMENT_TEAM` iOS/APILLON team'i `WWRZ5CG3DW` ile hizalandı (eski
  `QB8VR32GWN` üç yerde değişti) + kullanıcı Xcode'da "Automatically manage signing"i tetikledi.
  iOS ve macOS artık AYNI takımda imzalanıyor (APILLON BİLGİ TEKNOLOJİLERİ — yayın hesabı). macOS
  widget'ı (OPH-134) artık imzaya bloklu değil. Tarihsel bağlam aşağıda:
  `flutter build macos` şu hatayla düşüyor: _"Runner has entitlements that require
  signing with a development certificate"_. **Benim değişikliğim değil** — ölçüldü:
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
2. Sıradaki iş **OPH-171 — aşağı çekip yenileme** (Epic 16, TASKS.md sonu). **Epic 16 sırası
   bağlayıcı:** 171→174 (UI akışı, cihazsız) → 175→181 (alarm belkemiği; 175/177/178 migration
   içerir, 180 yeni bağımlılık) → 182/183 (cihaz). Bağlayıcı metin:
   [ADR-0015](adr/0015-alarm-delivery-and-reminder-profiles.md),
   [NOTIFICATIONS.md](NOTIFICATIONS.md) §2/§2b/§2c/§2d/§5/§6, DESIGN §11 A3/A5/A6 + §15–§18,
   BLUEPRINT §4.9/§8.2/§12.13. **Native uyarı (round 9'un pahalı dersi):** `flutter analyze`/
   `test` Swift/Kotlin DERLEMEZ — repoda duran bir Swift dosyası hedef üyeliği yoksa hiç
   çalışmaz ve köprü sessizce "desteklenmiyor" döner (AlarmKit round 6'dan beri yazılıydı,
   round 9'a kadar bir kez bile çalışmadı). Her native task gerçek `flutter build ios`/`apk`/
   `macos` + cihaz turuyla doğrulanır. UI işlerinde kontrast bekçisi + açık/koyu tema zorunlu
   (sert kural 11); alarm işlerinde **dürüstlük kuralı**: OS'un vermediği bir şeyi vermiş gibi
   gösteren tek satır bile kabul edilmez (DESIGN §11 A4/A6).
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
