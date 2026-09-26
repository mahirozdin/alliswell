# LESSONS — alan bazında dersler ve kararlar

> Bütün okunmaz: dokunacağın alanın başlığını grep'le — `grep -n -A60 "^## <alan>" docs/LESSONS.md`.
> **KARAR** bağlayıcıdır (değiştirmek sahibe sorulur) · **DERS** sessizce tekrar edebilecek bir
> tuzaktır (belirti → neden → ne yap) · **NOT** koddan çıkmayan kalıcı bir gerçektir.
> Yeni madde 1–2 satır; aynı sınıftan bir madde varsa yenisini ekleme, onu güncelle. Bütçe: `check:docs`.
> Kaynak: 2026-09-26 temizliği — tam bağlam `git show 85b6c1b:docs/STATE.md` ve `…:docs/TASKS.md`.

## ci-release — CI adımları, sürüm etiketi, imajlar
- **KARAR** MinIO CI ve compose'da `cgr.dev/chainguard/minio:latest`'ten (herkese açık imaj kalmadı, Docker Hub/quay 401; ücretsiz katman yalnız latest, eski root birimi için `user: '0:0'`); yedek `bitnamilegacy/minio`.
- **DERS** "Kırmızı ama yalnız biçim" = testler hiç koşmadı: kırmızı adım sonrakileri atlatır → CI'ı adım adım oku, her süitte success gör; `skipped` = koşmadı.
- **DERS** `v*` etiketi prod deploy'unu tetikler → atlanan sürüm sonradan etiketlenmez (yeninin ardından eskiyi deploy eder); sonraki sürüm onu kapsar.

## deploy-prod — dağıtım kapısı, web önbelleği, yedek
- **KARAR** Uzantılı dağıtım yalnız uzantı CI'ının (`DEPLOY_OVERLAY_CI_WORKFLOW`, varsayılan `EE CI`) en yeni koşusu yeşilse çıkar; sunucuya denetlenen SHA gider, koşu okunamazsa durur — kırmızı uzantı commit'i sunucuya çıkamaz.
- **DERS** Flutter web adları hash'siz (`main.dart.js`, `flutter_bootstrap.js`) → `immutable` tarayıcıyı bir yıl eski uygulamada tuttu; `/app/` `no-cache, must-revalidate`; "deploy başarılı" ≠ yeni kod → servis edileni ölç.
- **DERS** `mysqldump` `--no-tablespaces`'sız "Error:" basar ama 0 ile tam dump üretir; takvim/AI/TOTP sırları `.env` anahtarlarıyla şifreli → başka anahtarla geri yükleme kusursuz görünür, 2FA'lıları kilitler.
- **NOT** Docroot: landing kökte, Flutter web `/app` (`--base-href /app/`); `.htaccess` build'den gelir (sunucununkini taşıma, /app sessizce ölür); Vite `public/` nokta dosyalarını kopyalamaz → özel plugin.

## docs-gates-process — kapılar, enjeksiyon, belge doğruluğu
- **KARAR** Her düzeltmenin yanına aynı kusur SINIFINI yakalayan kapı ya da değişmez testi konur; kapı sahte ihlalle kırmızıya düşürülerek kanıtlanır.
- **KARAR** İnsanın dokunamadığı yetenek (şema alanı, store metodu, uç) özellik değildir: iş yüzeyini adıyla yazar, uygulamada koşturularak kapanır (DESIGN §22).
- **DERS** Kapının ölçmediği yeşil okunur: yeni kapı sahte ihlalle exit 1, kaldırınca 0 vermeli; boş kümede kırmızı; iki yönde enjekte et; eşanlamlı (`AnimatedOpacity`) kapsanır, yorum satırı ihlal değil.
- **DERS** Üretilmiş fixture'ı üreten kodla kıyaslayan kapı döngüseldir → bir taraf POLİTİKA: elle onaylı allowlist + bilinçli `--write` (`allowed-payload-keys.txt` kalıbı); liste bağımsız kaynakla (şema) doğrulanır.
- **DERS** Enjeksiyon yanlış sebepten geçebilir (örtüşen savunmalar birbirini maskeler) → kuralı çıplak testle çivile, savunmaları ayrı enjekte et; ardışık test eşzamanlılığı kanıtlamaz.
- **DERS** "Bu işi geri alsam hangi kapı kırmızı?" Hiçbiriyse iş bitmedi: okunmayan bayrak, çağrılmayan adaptör hep yeşildir → çağıran + test yaz.
- **DERS** Davranış değişince doğru olan docstring/kullanıcı metni yalana döner, `check:docs` görmez → davranışı değiştiren tur yorumu ve metni aynı turda düzeltir.
- **DERS** `docs/adr/README.md` dizininin kapısı yok (iki kez bayatladı) → ADR'nin dizin satırı aynı commit'te.
- **NOT** `check:docs` sürüm iddialarını kök `package.json`'a kapılar (kaçış `docs-check-ignore`); test sayıları bilerek kapısız → belgede çürümeyen biçim ("1,200+").
- **NOT** İkiz uygulamalar ortak fikstürle çivili, biri değişirse öteki + fikstür aynı değişiklikte: fold `fold_parity.json`, proje eşleme `project_match_parity.json`, takvim bloğu `calendar_block_parity.json`, tekrar motoru.
- **DERS** Görev kimliği kalıbı `\d{3}\b` dört haneli kimliği hiç görmez (OPH-1000'de üçüncü haneden sonra kelime sınırı yok): iş hem `next`'ten hem kapıdan sessizce düşer → `\d{3,}`; TASKS'ı yalnız `scripts/tasks/tasks.mjs` okur, kapı ve `next` ondan (enjeksiyonla ölçüldü).

## api-db — Fastify rotaları, MySQL, kuyruk, test DB
- **KARAR** Hata kodu ailesi: 400 biçim · 404 sana görünmez (403 değil) · 409 tekillik · 422 iş kuralı (gövde şemaya uyar, kural reddeder); her hata stabil `code` taşır.
- **KARAR** Periyodik iş `setInterval`+`unref()`+`env!=='test'` ev kalıbıyla (`series-gc.js`), BullMQ repeatable değil — self-host Redis'siz de koşmalı; çok replikada dedupe + idempotens.
- **DERS** Kuralı route'a yazma, ikinci yol atlar (MCP'nin etiket-yalnız yazımı arşiv kuralını atladı) → kural domain fonksiyonunda (`db/tasks.js`), REST ve MCP onu çağırır.
- **DERS** Fastify Ajv bilinmeyen gövde anahtarını reddetmez SİLER → yalnız bilinmeyen alanlı PATCH sessiz 200 alır: boş patch'i kodla reddet (`*_EMPTY_PATCH`); hata serileştiricisi yalnız `{statusCode,code,error,message}` yayar.
- **DERS** Aynı milisaniyedeki düz `ulid()` sıralanmaz → `orderBy('id')` sayfası iki kaydı ters verir (aralıklı flake) → `ids.js` `monotonicFactory`.
- **DERS** Yalnız yapılandırılınca kaydedilen rota OpenAPI üretecine görünmez → üreteç özelliği tek kullanımlık kimlikle açar; "yapılandırılmamışken 404" testi rota yokken de geçer → koşulsuz kayıtla kırmızıyı gör.
- **DERS** `fakedb.js` MySQL değil: rollback, aggregate/subquery yok; benzersizlik `===` (datetime'lı unique tutmadı), `Date`'i referansla sıraladı → bu davranışlar entegrasyonla kanıtlanır; tuhaflıkta önce fakedb'den şüphelen.
- **DERS** MySQL NULL'lu UNIQUE tekilliği zorlamaz → kök seviye (parent NULL) ad tekilliği API guard'ında; `deleted_at`'li aktif tekillik VIRTUAL `active_flag` + unique. ENUM tanım sırasıyla sıralanır.
- **DERS** Toplu yazımda `ER_LOCK_DEADLOCK` kalem kaybettirir → `transactionWithRetry` (`src/db/tx.js`, 1205 denenmez); entegrasyon dosyaları tek MySQL'e sıralı koşar (`fileParallelism` kapalı).
- **DERS** Eşzamanlılık ardışık testle/SQLite'la kanıtlanmaz → gerçek MySQL'de paralel test; "bir kez" etkisi (bildirim, süpürge) koşullu tek `UPDATE … AND status=…` + `affectedRows===1` ile.
- **DERS** BullMQ varsayılan `bull:` keyspace'i: aynı Redis'i paylaşan iki kurulum birbirinin işini tüketir, iş sessizce kaybolur → her dağıtıma ayrı `REDIS_KEY_PREFIX`.
- **DERS** Kod sabiti ile migration ENUM'u ikizdir, REST şemasına elle yazılan enum kayar → şemayı sabitten türet, pin testi; ENUM'u ALTER'la genişlet, canlıda daraltma. Tekillik/zorunluluk şemada (importer modeli atlar).
- **NOT** Ölü kolonlar yazılmaz: `tasks.repeat_rule` (tekrar `task_series`'te), `calendar_mirror_enabled` (bastırma `calendar_mirror_suppressed_at`), `notes.content_delta` (okunur kaçış ambarı).
- **NOT** Tek kopya zemin, ikincisini yazma: `queue/runner.js`, `plugins/storage.js`, `lib/crypto.js`, `lib/tokens.js`, `lib/time.js`, `calendar-sync.js` süpürge idiomu, `db/sync.js` `publishEntityChanged` (commit sonrası).

## migrations — knex göçleri, kolon tasarımı
- **DERS** Yeni kolonun varsayılanı her mevcut satıra uygulanır: `false` varsayılanlı bastırma bayrağı her satırı bastırır, anlamı sonra çevrilemez → bayrağı bugünkü davranışı koruyacak yönde adlandır.
- **DERS** Prod MariaDB'dir: `utf8mb4_0900_ai_ci` yalnız MySQL 8'de → migration collation sabitlemez, `resolveCollation(knex)` (`DATABASE_COLLATION` pin'i); `api-mariadb` CI işi yakalar.
- **DERS** Kanonik biçim değişince migration `content_hash`'i yeni imzayla yeniden hesaplar (yoksa her notun ilk düzenlemesi mükerrer sürüm yığar); eski kolonu silme, `down()` dürüst kalsın.

## sync — push/pull protokolü, kapsam, yazma dikişleri
- **KARAR** Yerel-önce istisnaları (ekran doğrudan REST): `/me`, takvim hesapları (önbellekte "bağlı" yalan olurdu), depolama durumu, dosya yükle/adlandır/sil (+`syncNow`), çok varlıklı arşiv kaskadı.
- **KARAR** Not etiketleri not PUSH protokolünde yok (`NOTE_FIELDS`'ta `tagIds` yok, yalnız REST `PUT /notes/:id/tags`); pull yükler — bilinçli v1 sınırı.
- **DERS** Yeni sync `operation` fiili eklenemez: ENUM'lar ve pull şeması üç fiile kilitli, dispatch `default:` bilinmeyeni `applyDelete`'e düşürür → `update` + virtual alan (`orderedIds`, `seriesScope`).
- **DERS** Push `guard` create+update'te koşar, DELETE'te ASLA → sahiplik `checkOwnership`'te; `!(await ownershipOk())` dönen hata KODU dizesini geçirir; silinmesi denetlenecek varlığa delete açma.
- **DERS** Yazma iki dikişten geçer: REST/MCP/import `db/*.js` domain'inden, sync push kendi ENTITIES makinesinden (`afterCreate/afterUpdate`) → her yeni kural (not sürümü, `noteMarkdownFrom`, erteleme) ikisine bağlanır.
- **DERS** Serileştiriciyi REST ile sync PULL paylaşır → yeni alanı (`tagIds`) pull yükleyicisi yüklemezse her snapshot sessizce boş değer (`[]`) taşır.
- **DERS** Not kilidinin base'i notun KENDİ revizyonudur, workspace imleci değil — imleç soket pull'uyla karşı yazımı geçer, gövde sessizce ezilir; kendi başarılı push'u base'i ilerletir.
- **DERS** LWW intent adı gerçekten yazılan kolon olmalı: emekli kolona bağlı intent hiç eşleşmez, kilit log'suz kilitlemeyi bırakır → kolon emekliye çıkınca intent'i taşı.
- **DERS** Kullanıcı-kapsamlı varlıkta filtre yalnız loader'daysa başkasının ULID'leri tombstone olarak sızar → `userScoped` + görünmeyeni düşür, yalnız soft sil; replika çıkışta silinmez → yerelde de `userId` süz (ADR-0018).
- **DERS** Tombstone bir revizyondur: imleçten ileri `sync_revisions` satırı yoksa hiçbir çekme onu görmez → satırı kaldıran iş aynı txn'de sync yazımı kaydeder; testi gerçek çekmeyle yap.
- **DERS** Genel push makinesi silmeyi `deleted_at` adıyla yazar ve onunla tombstone'lar → push'lanan her varlığın soft-delete kolonu `deleted_at` olmalı.
- **DERS** `registerSyncEntity` tip başına tek kayıt, tek serileştirici → aynı tabloyu iki kitleye iki alan kümesiyle sunmak ayrı tip ya da server-only REST ister.
- **DERS** Sunucu patch'teki ilk bilinmeyen alanda mutation'ın TAMAMINI reddeder (reddedilen create yerel satırı bırakır) → testte istemcinin gerçek gövdesini gönder; `enqueueMutation` assert'i yalnız koşulan yolu görür.
- **DERS** Socket.IO `sync:ready` connect ack'iyle aynı TCP segmentinde gelebilir → istemci dinleyicilerini handshake'ten ÖNCE bağla.
- **NOT** Soket oda üyeliği bağlantı anında donar (JWT yalnız bağlanırken doğrulanır) → yeni workspace üyeliği yeniden bağlanana dek `sync:changed` almaz; periyodik pull yedektir.

## drift-replica — istemci replikası, göçler, outbox
- **DERS** drift'in varsayılan `onUpgrade`'i fırlatır: basamaksız `schemaVersion` artışı her replikayı tuğlalar → her sürüm `if (from < n)` basamağı; replika outbox taşır, "sil, yeniden çek" güvenli değil.
- **DERS** Eski basamaktaki `createTable(x)` GÜNCEL tanımı yaratır → x'e sonra eklenen `addColumn` `from >= <createTable sürümü>` korumalı olmalı (yoksa duplicate column; üç kez oldu).
- **DERS** Göç testi gerçek dosyalı SQLite'ta (`drift_dev` şema araçları bu zincirde kırık); sürüm fixture'ı sonra eklenen HER şeyi düşürüp gerçek satırla açılır, yoksa korumalı ALTER hiç koşmaz; adımı silip kırmızıyı gör.
- **DERS** `createAll` ad-hoc indeks yaratmaz → indeksi `onUpgrade`'e ek olarak `onCreate`'e de koy (yoksa taze kurulum sessizce tam tarama); Migrator'da `customStatement` yok → `db.customStatement`.
- **DERS** Türetilmiş kolon (fold gölgesi) eski satırlarda boş kalır, çekme artımlıdır → göçte geri doldur, alanı yazan her yol gölgeyi de yazar; sunucu-sahipli yeni kolon satır değişene dek null.
- **DERS** Cihazın YAZDIĞI replika tablosuna kolon eklenince applier onu da eşlemeli, yoksa itmeden sonraki çekme ekrandaki değeri siler.
- **DERS** JOIN'li `customSelect`'te `readsFrom`'a her tablo yazılmazsa stream JOIN'lenen tablo değişince SESSİZCE donar.
- **DERS** JOIN'li sorguda `LIMIT` join satırlarını sayar (3 etiketli görev 3 slot yer) → sayfayı ana satırda al, ilişkiyi sonra oku; kararlı eşitlik bozucu (`id` DESC).
- **DERS** Outbox koalesansı + settle'da koşulsuz silme uçuştayken yazılan gövdeyi siler → settle yalnız `localUpdatedAt` eşleşirse siler; açık editör temizse pull'u yerinde alır (`adoptRemote`), kirliyse metnini korur.
- **DERS** Replikanın iki yazarı var (widget arka plan izolatı + uygulama) → `awSqlitePragmas`: WAL + `busy_timeout=5000`.
- **DERS** Web replikası commit'li `web/sqlite3.wasm` + `web/drift_worker.js`'e dayanır, drift/sqlite3 sürümüne sabittir → drift yükseltilirken ikisi birlikte yenilenir.

## flutter-app — ürün sözleşmeleri, Riverpod, go_router, testler
- **KARAR** Inbox ("Fikirler") yakalama kutusudur: yakalamalar Home'da asla görünmez; tarih ya da proje verilince aynı yazımda `open`'a terfi eder.
- **KARAR** Proje kullanıcıya yalnız açık/arşivli görünür (`paused`/`completed` enum'da kalır, arayüz üretmez); kaskadlı arşivden çıkarma projenin TÜM arşivli öğelerini getirir (v1 bilinçli).
- **KARAR** `alliswell://` URL'leri yalnız gezinir, asla yazmaz (`complete` yok, `add` parametre almaz); bilinmeyen URL hata değil; widget'tan yazan tek yol imzalı App Intent / App Group kuyruğu (ADR-0016).
- **KARAR** Gizli widget modunda başlık App Group/SharedPreferences'a hiç yazılmaz. Hızlı Erişim `quick_link` kullanıcıya özel, `kind+target_id` saklar, rota dizesi asla; ≤50 (ADR-0018).
- **DERS** `PersistedChoice`/`Toggle` depo okunmadan varsayılanı söyler → kısa ömürlü süreçte varsayılan cevap olur (self-host jetonu hosted API'ye), gizli ayar ilk cevapta sızar → `localKv`'yi doğrudan oku.
- **DERS** go_router boş yolu `/`'ye çevirir, `alliswell://add` kök rotaya eşleşip `onException`'a varmaz → şemayı üst düzey `redirect`'te çöz; soğuk açılışta `?add=1` `/splash` parkında kaybolur → niyeti provider bayrağıyla taşı.
- **DERS** `ref.listen` yalnız değişimde ateşler → açılışta zaten bekleyen yük (paylaşım) hiç işlenmez: ilk kareden sonra bekleyeni süpür; sonradan beliren değeri tek atımlı okuma, akışı izle.
- **DERS** Hazır olmayan/hatalı async provider "boş" okunur (`.value` null → "anahtarın yok", sahte çevrimdışı) → eylemde `await x.future`; sunucu hakkında iddia eden ekran hatayı fırlatır, boş liste göstermez.
- **DERS** HomeShell `extendBody:true` + cam çubuk: iç Scaffold FAB'ı ve `useRootNavigator`'sız sheet/dialog çubuğun ALTINDA kalır → FAB shell'de, sheet/dialog kök navigator'a; `findsOneWidget` kaçırır → testte dokun.
- **DERS** `AppSection.values` ↔ shell dal indeksi ↔ rail/bar hedefleri KONUMSAL kimliktir; hedef listesini filtrelemek yanlış ekranı açar → gizleme `visibleSections` ile, golden'la.
- **DERS** Ertelenmiş closure (geri al, commit) `WidgetRef` yakalarsa satır dispose olunca iş sessizce koşmaz → store'u mount'luyken çöz; autoDispose family'yi akış ortasında `ref.read`'leme.
- **DERS** `State.mounted` `dispose()` sırasında hâlâ true → dispose'tan tetiklenen `setState` çöker; Notifier dispose sonrası `state` yazımı `UnmountedRefException` → ayrı `_disposed` bayrağı.
- **DERS** Flutter 3.44'te eylemli `SnackBar` süre dolunca kapanmaz (`persist ?? action != null`) → eylemli snackbar yalnız `showAwActionSnackBar` (`persist:false`).
- **DERS** Web'de dio 204 gövdesini `''` verir → `as Map` TypeError atar, temizlik atlanır (logout sunucuda öldü, app "girili" kaldı) → `data is Map ? … : {}`.
- **DERS** Gün sınırlı liste gece yarısı yenilenmez (askıda timer ateşlemez) → gece yarısı+1 sn timer + `resumed`'da yeniden hesap, saat `nowProvider`'dan; gün aritmetiği `DateTime(y,m,d+1)` (`add(Duration)` DST'de kayar).
- **DERS** Test: Riverpod 3 çift override'ı assert eder → fake'ler `syncTestOverrides(...)` parametresiyle; FakeApi yeni senkron varlığı push'ta uygulamazsa silinen satır sonraki pull'da geri döner.
- **DERS** Test: sonsuz animasyonda `pumpAndSettle` dönmez → `pump(süre)`; snackbar timer'ı teardown'ı patlatır → sonda `pump(6s)`; sürükleme `startGesture`+`moveBy`; gerçek async kurulum `tester.runAsync` içinde.
- **DERS** Dokunmatik panel kare başına birden çok hareket olayı verir: gesture callback'i `build`'in yereline eklerse (`centre + d.delta`) sonuncusu dışındakiler düşer, `DragStartBehavior.start` da eşiği yutar → state alanına biriktir, `.down`; test aralarında `pump` olmayan art arda `moveBy` ile (#17).
- **DERS** `flutter test --platform chrome` koşamaz (test config i18n'i `dart:io` ile okur); `kIsWeb` VM testinde sabit false → web kararını provider'a taşı, gerçek web davranışını tarayıcıda gör.

## design-ui — tokenlar, kontrast, yüzeyler
- **KARAR** Renk yalnız paletten, kullanıcıya hex asla; not rengi ADIYLA saklanır, her tema kendi değerini çözer (tek hex iki temada 4.5 tutmaz); markdown'a renk sözdizimi yok, yalnız `==vurgu==` (DESIGN §33).
- **KARAR** Not yazma ekranında hiçbir şey yüzmez (`awIsDocumentRoute`); Ayarlar satır icat etmez (tema anahtarı yok), yeni ayar yeni kök grup açmaz, var olan Ayarlar URL'leri taşınmaz.
- **DERS** `contrast.py` "FAILURES: 0" yalan söyleyebilir: çiftte olmayan yüzey ölçüsüzdür → çift = widget'ın GERÇEKTEN boyadığı karışım; `warning` metne verilmez (2.96); `ListTile` seçimi etiketi `primary` boyar.
- **DERS** Metni saran `Opacity` kontrastı ölçülemez kılar (satır 2.11:1) → sakinlik yüzey tokenıyla (`awRecededSurface`); meşru kullanım `check:opacity` izin listesinde.
- **DERS** Shell `extendBody:true` gövdeyi cam çubuğun altına uzatır → alt boşluksuz kaydırılabilir son satırları gizler: `awListPadding`; "sonun ötesine kaydır" boşluğu kaydırılabilir İÇERİK olmalı.
- **DERS** Düğme rengini `foregroundColor`'la ver; iç `TextButtonTheme` ambient temanın yerine geçip global 44 px dokunma hedefini sessizce düşürür.

## i18n — AwI18n, anahtarlar, check:i18n
- **KARAR** i18n uygulamanın senkron deposu `AwI18n`, paket yok (async delegate fake-async testte yüklenmez); `boot()` `runApp`'ten önce, `MaterialApp` dil dinleyicisinin İÇİNDE (const child yenilenmez) (ADR-0009).
- **DERS** `check:i18n` yalnız literal tarar: `Text(değişken)`'le basılan ham enum, argümanla ya da `.tr(` içinde geçen yanlış anahtar, kullanıcının BELGESİNE yazılan dize kaçar → enum'u etiketten geçir, `extraction_test.dart`.
- **DERS** Çoğul yok → her form ayrı anahtar; `locale` yalnız tarihi biçimler; CLDR AM/PM'den önce U+202F koyar → saati parça bazlı doğrula; dile göre değişen kural her dil için ayrı iddia ister.

## search — TR fold, yerel-önce arama
- **KARAR** Arama yerel-önce: replikadaki fold motoru otoriter, sunucu FULLTEXT ikincil (ADR-0013, ADR-0014); dışarıya "aksanları yok sayan arama" diye anlatılır, Türkçe farklılaştırıcı diye pazarlanmaz.
- **DERS** Ne FTS5 ne `utf8mb4_0900_ai_ci` `ı→i` fold'lar → fold uygulamada (`core/fold.dart` ↔ `lib/fold.js`), İ/I/ı→i lowercase'ten ÖNCE; `*_fold` gölgeleri Dart'ta dolar; ad tekilliği de fold'la.
- **DERS** Arama metni istemci/sunucuda ikizdir (`core/markdown_text.dart` ↔ `markdownToPlainText`): tek dalda türetilen `bodyFold` markdown notları iki aramada da kör bıraktı.

## markdown-notes — markdown_forge, editör, sürümler, PDF
- **KARAR** Not %100 markdown, ikinci form yok (Quill kalktı); motor in-repo `markdown_forge`; eski delta istemci tek kapıda (`noteMarkdownFrom`) çevrilir — yeniden tartışılmaz (ADR-0033).
- **KARAR** Mermaid ve matematik gerçekten çizilir, web view ASLA (güvenilmez belge + JS motoru) (ADR-0028).
- **KARAR** Editör eylemleri TEK listeden (`mdActions()`): palet, slash, kısayol — dördüncü tanım yasak; kaynak modu biçim göstermez (`markersOnly`), biçim Okuma modunun işi.
- **KARAR** Pano kendi kanalımızla (`clipboardRead()`; Flutter kanalı yalnız `text/plain`, `text/html` hep null); `super_clipboard` reddedildi (altı platforma ve CI'a Rust toolchain).
- **KARAR** Dış .md aynı editörde; geri yazma bayt-sadık ya da hiç: katı UTF-8, BOM/satır sonu korunur, değilse salt-okunur; autosave/dispose yazmaz; tutamak `LocalKv`'de, senkron DB'de asla (ADR-0030).
- **KARAR** Sürümler ve merge SUNUCUDA (diff3), replikaya inmez; fuzzy patch ve otomatik kopya yok, kaybeden taraf daima sürüm + banner (ADR-0031).
- **DERS** PDF yürüyücüsünün `default:` dalı bilinmeyen öğenin çocuklarına iner → yeni md öğesi (resim, `==mark==`, uyarı, dipnot) PDF'te sessizce düşer; ekranın çizdiği her öğeyi sayfaya ekle, kapsam testi.
- **DERS** `buildTextSpan` `text`'i karakter karakter döndürmeli: işaret gizlemek imleç/seçim/undo/IME ofsetini kaydırır → söndür, gizleme.
- **DERS** `markdown` AST'si konum taşımaz → damga için `withDefaultBlockSyntaxes: false` şart; `HeaderWithIdSyntax` Türkçe harfi atar → slug `core/fold.dart`'la; `Uri.decodeComponent` ham Türkçede fırlatır.
- **DERS** `SingleActivator` "meta VEYA control" diyemez → kısayol sessizce yalnız-macOS olur: `metaOrControl()` çifti; alan kısayolunun işleyicisi alanın KENDİ focus node'unda.
- **DERS** `allowMalformed: true` ile çözülen metni geri yazmak UTF-8 olmayan her baytı U+FFFD yapar → açılışta tespit edilen kodlamayla yaz.
- **NOT** diff3'te aynı noktaya iki farklı ekleme gerçek çakışmadır (`OVERLAP` reddi doğru). Sync `NOTE_FIELDS` eski `contentDelta`'yı kabul eder, saklamaz — kaldırmadan önce eski istemci kalmadığını ölç.

## files-storage — ekler, S3/R2, presigned
- **KARAR** Baytlar API'den geçmez (presigned PUT/GET, R2 birincil, dev/CI MinIO); `files` pull-only sync varlığı; not gömmesi `alliswell://file/{id}`, asla süreli URL; `STORAGE_S3_*` yoksa özellik kapalı (ADR-0011).
- **KARAR** Dar istisna: yalnız istemcisi OLMAYAN (sunucunun aldığı) dosya `storeServerFile`'dan yazılır, korumalar aynen (tavan, ilk baytlardan tür, ölçülen boyutla guard) (ADR-0011).
- **KARAR** Ek hedefi ENUM değil defter (`target_type` varchar + `registerAttachmentTarget`); kayıtsız/izinsiz hedefe aynı kötü-hedef cevabı ("yok" ile "senin değil" ayrılmaz) (ADR-0040).
- **DERS** Presigned PUT'a Authorization başlığı S3 imzasını bozar → yükleme çıplak dio'yla; io'da dosya yoldan akıtılır (video belleğe sığmaz); obje silme commit SONRASI kuyruklanır.
- **DERS** Yükleme guard'ı (tavan/kota) iki fazda: beyan edilen boyutla erken, HeadObject'le ÖLÇÜLEN boyutla commit'te — tek faz eşzamanlı yüklemelerle tavanı aştırır.

## calendar — takvim aynası, Google/EventKit, tekrar, DST
- **KARAR** Ayna seçeneksiz: her görev 30 dk blok, güne kenetli (23:59 → 23:29–23:59), tarihsiz → ekleniş günü; tamamlanan `✓` ile kalır, iptal/silinen gider; backfill −30g→+12ay (ADR-0021).
- **KARAR** Blok önce `scheduled_start_at`'ten türer; Google'da sürükleme `due_at`'i değil `scheduled_*`'ı yazar; "Planlanan tarih" alanı yok, yalnız doluyken "Takvimde taşındı — Sıfırla" (ADR-0007).
- **KARAR** Tekrar: RFC 5545 alt kümesi + RFC 7529 kırpma (31 → ay sonu); occurrence gerçek görev satırı, yalnız sunucu üretir (+12 ay, günlük süpürme); istemci/widget/alarm tekrarı bilmez (ADR-0020).
- **DERS** Echo bastırma etag'le: giden her yazımda dönen etag `calendar_event_links.etag`'e yazılmazsa kendi değişikliğimiz kullanıcı düzenlemesi sanılır → ayna ⇄ inbound döngüsü.
- **DERS** Google: `nextSyncToken` yalnız son sayfada, 410 → token düş + tam resync; `timeMin/Max` `syncToken`'la kullanılamaz; `singleEvents` iki tüketiciye yetmez (iki akış, iki cursor); webhook gövdesiz POST'tur.
- **DERS** Yalnız `scheduledStartAt` sıfırlanırsa ters blok türer, Google `end<=start`'a 400 verir, kuyruk aşamaz → iki alan birlikte null; kenetleme görevin KENDİ diliminde.
- **DERS** "Yalnız bu" düzenlemesinde `series_id` null'lanmaz (slot boşalır, süpürme aynı güne kopya üretir) → satır seride kalır, zamanı `due_at` söyler; seri `timezone`'u kullanıcı profilinden (cihaz "+03" der).
- **DERS** EventKit: id iCloud taşımasında değişir → yeniden bağlama URL alanındaki `alliswell://task/{id}`'le (ADR-0003); iOS 17 `writeOnly` "verildi" değil; izin `EKEventStore` örneğine bağlı → tek örnek.
- **DERS** Europe/Istanbul DST'siz → onunla DST testi hiçbir şey kanıtlamaz; `lib/time.js` `zonedWallTimeToUtc` boşluktaki saati 1 sa ileri kaydırır, örtüşmede GEÇ oluşu seçer → politikayı seç, iki vakayı testle.

## notifications-alarm — yerel alarmlar, AlarmKit, başsız tur
- **KARAR** Görev saati de alarmdır: hatırlatıcı deadline alarmını silmez (`reminders.kind` remind|due); süresiz susturma (`alarms_muted_at`) görevi açık bırakır — susturmak tamamlamak değildir (ADR-0015).
- **KARAR** Dürüstlük: reddedilen alarm günlükte `degraded`, asla `scheduled`; acil alarmın her slotu aynı ses/seviyede, sessiz düşüş yasak — her düşüş ekranda + günlükte söylenir (ADR-0015).
- **KARAR** Sessiz anahtarlı iPhone'da meşru yol AlarmKit (iOS 26+), critical-alerts yalnız iOS<26 yedeği; arka plan ses hilesi reddedildi; Watch hedefi açılmaz (ADR-0015).
- **DERS** Bildirim id'si çevrilmiş metnin hash'i, Android kanal adı `.tr()` → i18n'siz arka plan turu alarmı çift kurar, kanalı ham anahtarla adlandırır → başsız tur önce `AwI18n.boot()`; iki okuyucu tek `mergeAlarms`.
- **DERS** Başsız tur: workspace `/me`'den değil `sync_states`'ten (çevrimdışı "iş yok" olur), base URL `PersistedChoice`'tan değil `localKv`'den; `ProviderContainer` kurma; oturum yoksa sessiz çık.
- **DERS** İki hatlı (AlarmKit/bildirim) planlamada dışlanan küme niyetten değil KABUL edilenden hesaplanır (yoksa reddedilen alarm hiçbir hatta kalmaz); her `schedule()` ayrı try/catch; yetkiyi yeniden oku.
- **DERS** Soğuk açılışta bildirim yanıtı tamponsuz broadcast'te dinleyici doğmadan kaybolur → tampon + ilk kareden önce `getNotificationAppLaunchDetails`; iOS eylemi `.foreground` değilse kayıtsız işleyiciye düşer.
- **DERS** Teşhis teşhis ettiğini bozmamalı: günlük yazımı durum probunu yutup alarmları kapalı cihazı sağlıklı gösterdi → günlük yazımı `unawaited` + kendi try/catch.
- **DERS** iOS 64 bekleyen bildirimin fazlasını sessizce atar → pencere 40; AlarmKit en yakın 8, taşan bildirim zincirinde (planner'a kapsanan id KÜMESİ); iOS teslimi bildirmez → günlük teslim iddia etmez.
- **DERS** iOS ses adı çözülemezse sessizce ding'e düşer, önce `Library/Sounds`'a bakılır → sesler oraya kurulur, yoksa `degraded`; ≤30 sn caf/aiff/wav (mp3 çalmaz); sessiz anahtar `timeSensitive` sesini susturur.

## push — sunucu push'u, web push, FCM/APNs
- **KARAR** Yük yalnız kimlik; gövde tek yerde (`lib/push/payload.js`), olay sınıfı taşınmaz; görünür yedek herkese aynı katalog cümlesi (dil cihaz→hesap→en; loc-key reddedildi), görev adı yok (ADR-0038).
- **KARAR** Kimlik yoksa özellik yok (ana anahtar yok); FCM servis hesabı yalnız DOSYA YOLU (env'deki anahtar ps/dump'a düşer); `/push/public-key` yalnız yapılandırılınca kayıtlı; yarım yapılandırma boot'u düşürür (ADR-0038).
- **KARAR** Taşıyıcı: `firebase-admin` yok (JWT `node:crypto`), `web-push` yalnız şifreleme, istek `fetch`; 404/410 abonelik ölü, 429/5xx sonra dene (ADR-0038).
- **KARAR** Teslim: uyandırma ipucu (yalnız Android), vadede içeriksiz görünür yedek (bayat = `last_seen_at < reminders.updated_at`; web'in tek yolu), periyodik tazeleme; iOS'a veri push'u ve `UIBackgroundModes` yok (ADR-0038).
- **KARAR** `web/aw_push_sw.js` karar vermez (çeviri/gizlilik/`silent` uygulamanın yazdığı önbellekten), her yol bir bildirimle biter; web modu cihaz-yerel Kapalı/Sessiz (varsayılan)/Sesli, Kapalı aboneliği bırakır (ADR-0039).
- **DERS** Web Push `userVisibleOnly`: bildirim göstermeyen işleyiciye Chrome jenerik kart basar → "sessiz" web push yok, susturmak = abonelikten çıkmak. Firefox `silent`'ı yok sayar ama true döner → UA kontrolü.
- **DERS** Web'de izin ≠ ulaşılabilirlik (VAPID yok ya da abonelik iptal) → ayrı `AlarmProblem.webPushOff`; tarayıcı yerel bildirim zamanlayamaz; iOS web push yalnız Ana Ekran uygulamasında; SW `localStorage` göremez.
- **DERS** `url_launcher` web'de bilinmeyen şemada (`app-settings:`) hata vermez, ölü sekme açar → "best effort + catch" web'de hiç düşmez; web'in reddi üç sorun (istenmemiş / engellenmiş / desteklenmiyor), düzeltme sayfasının aksiyonu `AlarmProblem` üzerinde exhaustive switch (#19).
- **DERS** iOS'ta `notification` bloğu olmayan FCM mesajı teslim edilmez → görünür yedek `notification` + `aps.sound` taşır. Firebase'e APNs anahtarı yüklenmezse token üretilir, hiçbir şey gitmez, test görmez.
- **DERS** FCM token bir aboneliktir: geri yüklemede döner → yenilemeyi dinle; çıkışta önce sunucu kaydını, sonra token'ı sil. VAPID anahtarı 65/32 bayt — yer değiştirmiş çift "dolu mu"dan geçer, uzunluğu ölç.
- **DERS** Ertelenen hatırlatıcı `remind_at`'ini korur, yeni an `snoozed_until`'de → vadesi gelenler iki ayrı sorgu (OR indeksi kullanamaz); idempotenlik `uq_reminder_push`'a INSERT.
- **NOT** `EE_PUSH_ENABLED` uzantının push kuyruğa alıp alamayacağını, `config.push` (VAPID/FCM) çekirdeğin gönderebilmesini söyler — iki ayrı soru, iki anahtar.

## ios-native — Runner, uzantılar, WidgetKit, AlarmKit
- **KARAR** Native kod in-repo eklenti paketinde (`packages/alliswell_eventkit`; pbxproj cerrahisi yok); App Extension paketle gelemez → hedef + entitlement betikle (`wire_*.rb`); yeni Swift mevcut `AlarmKitBridge.swift`'e.
- **DERS** `flutter analyze/test` Swift/Kotlin derlemez: hedefte olmayan Swift hiç çalışmaz (köprü sessizce "desteklenmiyor"), pod'lar Flutter'ın alt iOS hedefinde derlenir → native işi gerçek `flutter build`'le doğrula.
- **DERS** Uzantı hedefi eklerken (SETUP.md): base xcconfig yoksa `MARKETING_VERSION` boş → App Store reddi; sanal `Flutter` grubunda tam yol; pod uzantıda → `inherit! :search_paths`; Embed fazı Thin Binary'den önce.
- **DERS** Share uzantısı dyld'de raporsuz ölüyordu (`@rpath/AppAuth`): Pods runpath vermez → `AllisWellShare*.xcconfig`'teki `@executable_path/../../Frameworks` korunur (`otool -l | grep LC_RPATH`).
- **DERS** iOS 18+ uzantı ana uygulamayı açamaz, `getInitialMedia()` App Group'u okumaz → açılış/resume'da drain (ADR-0029); iOS 26'da dönüş URL'i rota sanılıp /not-found'a gider → SceneDelegate `super`'e vermez.
- **DERS** Uzantı sürümü `$(FLUTTER_BUILD_NAME/NUMBER)` olmalı (yeni hedef 1.0/1 doğar); yükseltince `flutter clean && pub get && pod install`. App Group dizesi her yerde bayt-bayt aynı: `group.com.alliswell.alliswell`.
- **DERS** `LiveActivityIntent` DAİMA ana uygulamada koşar (widget'tan tamamlama Flutter'ı başsız başlatıp çökertti) → widget sürecinde düz `AppIntent` + App Group kuyruğu; Dart her öne gelişte `drainPendingActions`.
- **DERS** WidgetKit'te canlı saat yok → dakikalık girdiler, ufuk bayttan (~16.6 MB arşivi aşınca chronod hepsini atar, widget placeholder'da kalır); timeline şimdi + 4 gece yarısı, başlık tarihi ENTRY'den.
- **DERS** Snapshot'a yeni alan: native taraf eksiğe toleranslı (Swift opsiyonel, Kotlin `optInt`), JSONSerialization (Codable yeni alanı düşürür); iki platformun yerleşimi de pariteye tabi.
- **DERS** Oturum `kSecAttrAccessibleWhenUnlocked` → kilitli iPhone'da başsız yol Keychain'i null okuyup "çıkış yapılmış" sanar → oturum yoksa sessiz çıkış, widget'ı replikadan yine çiz.
- **DERS** AlarmKit: `Alarm`'da attributes yok (id↔UUID eşlemesi), `.stopped` yok (düğmeler `LiveActivityIntent`), erteleme `.custom` (`.countdown` alarmı ikiler); `NSSupportsLiveActivities` iki Info.plist'te.
- **DERS** Focus `.active`'i gömer → hatırlatıcı `timeSensitive`; izinsiz iOS onu sessizce `.active`'e düşürür, plugin ayarı vermez → native sonda; `critical` yalnız `isCriticalEnabled`'da; kategori ~4 eylem gösterir.
- **NOT** iOS ve macOS aynı takımla imzalanır: `WWRZ5CG3DW` (eski `QB8VR32GWN` hiçbir yerde kalmamalı). AlarmKit'in Xcode bağlantısı `ios/scripts/wire_alarmkit.rb`'de (idempotent).

## android-native — manifest, izinler, kanallar, widget
- **KARAR** Kesin alarm: `USE_EXACT_ALARM` + `SCHEDULE_EXACT_ALARM` (minSdk 24; Play beyanı `docs/store/exact-alarm-declaration.md`); izin yalnız alarmlara — widget'ın gece yarısı tazelemesi bilerek kesin değil (ADR-0037).
- **KARAR** Uygulama medya/kamera izni istemez: kamera `image_picker`'la (`camera` paketi reddedildi), CAMERA dahil 7 izin `tools:node="remove"`; release APK manifesti allowlist'le TAM KÜME (`assert-permissions.sh`) (ADR-0027).
- **DERS** İzin ekleyen eklenti kapıyı kırar → `assert-permissions.sh --write`, farkı commit'te gerekçelendir; `tools:node="remove"` eşleşmeyince sessizdir, paket izni geri birleştirebilir → derlenmiş APK'yı denetle.
- **DERS** Release'te R8 kaynak küçültmesi adla istenen `res/raw` seslerini atar → acil alarm OS'a hiç kurulmaz, Ayarlar "Ready" der → her ses `aw_sounds_keep.xml` `tools:keep`'te (`keep.xml` adı bağımlılık kuralını ezer).
- **DERS** `targetSdk` 36: Android 14+'ta `SCHEDULE_EXACT_ALARM` varsayılan reddedilir → runtime izin akışı; acil slotlar `alarmClock` modunda (Doze'dan muaf); yeni izin `allowed-permissions.txt`'e.
- **DERS** Kanal sesi/önemi oluşturulunca değişmez → ses başına sürümlü kanal (`urgent_alarms_v2_<ses>`) + eskileri sil; kanal sesi yalnız `res/raw` ya da `content://` (app-private dosya → FileProvider).
- **DERS** `home_widget` 0.9.3 manifest'i boş: `HomeWidgetBackgroundReceiver` yoksa yayın hatasız kaybolur → alıcı manifest'te `exported="false"`; kendini kuran WorkManager işi `REPLACE` (`KEEP` zinciri keser).
- **DERS** Widget arka planı: satır/daire ayrımı intent extra'yla (tek PendingIntent şablonu); callback'e `@pragma('vm:entry-point')` (yoksa release'te sessiz no-op); yeni host `awIsBackgroundAction`'a ve `uri.host`'a.
- **DERS** SAF yazımı `openOutputStream(uri, "wt")` — `"w"` çoğu sağlayıcıda kesmez, eski kuyruk kalır; bulutta `COLUMN_LAST_MODIFIED` null → hash; atomik yazma yok → önce `external_recovery/` kopyası.

## macos-native — imza, widget köprüsü, sandbox
- **KARAR** macOS widget hedefi betikle kurulur (`scripts/add_widget_extension.rb`, elle pbxproj yok); takım/otomatik imza sahibin Xcode adımı (`macos/AllisWellWidgetMac/SETUP.md`).
- **DERS** `home_widget` macOS'u desteklemez (her yazım sessiz `MissingPluginException`) → kanalı `AWMacWidgetBridge` karşılar; widget tabanı macOS 14, uygulama 12; kayıtsız uzantı kimliği `flutter build macos`'u imzada düşürür.
- **DERS** Eklentide macOS kaynaklarını DİZİN-seviyesi sembolik bağla paylaşmak pod'da 0 kaynak üretir (köprü sessizce boş) → dosya-seviyesi bağ; xcodebuild'in Swift derleme satırlarını say.
- **DERS** macOS'u hiçbir CI işi derlemez (derleme haftalarca kırık kaldı) → macOS'a dokunan işte `flutter build macos` koş; hedef sürüm Podfile + pbxproj'da, derlemenin göçlerini commit'le.
- **DERS** Sandbox'ta eksik entitlement hata vermez, dosya sessizce salt-okunur döner; `isWritableFile` POSIX'i söyler → `resourceValues([.isWritableKey])`; `.atomic` yazma kardeş temp dosyayla imzalı build'de patlar.

## web-landing — landing, legal sayfalar, web yapılandırması
- **KARAR** Lisans PolyForm Noncommercial 1.0.0 (v0.9.0 ve öncesi AGPL): her yüzeyde "open source" değil "source-available"; katkılar ticari lisanslamaya izinle kabul edilir (ADR-0024).
- **KARAR** Pazarlama sahibin beş özelliğiyle (MARKDOWN §8); mağaza metni hiçbir biçimde "offline/çevrimdışı" diyemez (Play bir sürümü bu yüzden reddetti).
- **DERS** Cloudflare Email Address Obfuscation JS'siz legal sayfalardaki e-postayı uçuşta bozar → `<!--email_off-->`; deploy build edileni değil servis edileni doğrular.
- **DERS** Landing `public/` hash'lenmez, `.htaccess` her `.css`'e `immutable, max-age=1y` verir → içerik değişince dosya adındaki tutamağı artır (`api-docs-1.css`); `.json` bilerek immutable değil.
- **DERS** `String.fromEnvironment` derlemede gömülür, hazır web imajı başka domaine bağlanamaz → çalışma anı `alliswell-config.js` (env'den, `no-store`); `apiBaseUrlProvider` sırası runtime → dart-define → localhost.
- **NOT** `/privacy` ve `/support` build'de `docs/PRIVACY*.md`/`docs/SUPPORT*.md`'den üretilir → md'yi düzenle. İki karşılaştırma tablosu var (`docs/COMPARISON.md`, `content.js` `comparison`) — birlikte güncelle.

## ai-mcp — BYOK AI, uzak MCP, araç politikası
- **KARAR** AI iki hat: uzak MCP (kullanıcının aboneliği) + uygulama içi BYOK (`fetch` adaptörleri, SDK yok, anahtar `AI_TOKEN_KEY`'le şifreli, arayüzde `key_last4`); abonelik-OAuth kapalı (ADR-0019).
- **KARAR** Onay kartı atlanamaz, kabul `TaskStore` outbox'undan yazılır (tek istisna ✨ hızlı ekleme: anında düz görev, zenginleştirme sonra UPDATE); modele yazma aracı yok; silme AI'ya/MCP'ye kalıcı kapalı (ADR-0019, ADR-0022).
- **KARAR** Sohbet geçmişi cihaz-yerel, STT cihaz-üstü; onam ekranı sağlayıcı gerçeğini söyler (Gemini ücretsizi veriyle eğitir); proje eşleme LLM'e bırakılmaz; basılı-konuş kilitli sürer, transkript otomatik gönderilmez.
- **KARAR** Uzak MCP elle yazılmış stateless Streamable HTTP + kendi OAuth 2.1 AS (PKCE S256 zorunlu, opak token); `MCP_ENABLED`+`API_PUBLIC_URL` ayrı kapı, eksikse 404, boot hatası asla (ADR-0022).
- **KARAR** MCP'ye girmez: `delete_*` (API anahtarında var), dosya baytı, proje arşivleme, toplu içe/dışa aktarma; `update_task` `parentTaskId`/`sortOrder`/`colorRgb`/`alarmsMutedAt`/`seriesScope` almaz (ADR-0022).
- **KARAR** MCP hata politikası: domain 4xx + stabil `code` modelin okuduğu tool sonucu, 5xx opak; Ajv hatası `isError:true`; metni ezebilen araç `destructiveHint:true`; belirsiz proje → yaratmaz, aday listesi döner.
- **DERS** Yeni MCP yazma aracı: önce `findMcpReplay()`, sonra `recordMcpAction()` (ledger LAST) + `requireScope('mcp:write')` + TAM annotation dörtlüsü (eksik hint = bilinmiyor, host sessizce koşar).
- **DERS** Çağıranı olmayan kod çalıştığı sanılan koddur: bağlam paketleyiciyi hiçbir sohbet turu çağırmıyordu, hiçbir okuma aracı alarm id'si vermiyordu → uçtan uca kablolama testi; id'yi okuma aracının çıktısından al.
- **DERS** Fastify'da istemci kopuşu `reply.raw`'ın 'close'unda görünür (`request.raw` değil) → SSE abort'unu oraya bağla; sağlayıcı retry'ı yalnız gövde başlamadan (akış ortası retry metni kopyalar).
- **DERS** `AI_PROVIDERS` (sohbet) ≠ `AI_USAGE_PROVIDERS` + iki MySQL ENUM; `recordUsage` hatayı yutar → ENUM'da olmayan sağlayıcı sessizce sayılmaz: yeni ad = liste + ENUM genişleten migration.

## security — kimlik, anahtarlar, oturum, SSRF
- **KARAR** API anahtarı `awk_` düz Bearer: tek gösterim, HMAC-SHA256 hash, v1 scope'suz (sınır workspace bağı); `/auth/*`, hesap silme, `/ai/*`, anahtar yönetimi anahtara kapalı; anahtar listesi replikaya inmez (ADR-0032).
- **KARAR** Doğrulanan sır anahtarlı özet, kullandığımız sır şifreli + `last4`; her sır sınıfı kendi anahtarıyla (`AUTH_TOTP_KEY`…); TOTP bağımlılıksız (`node:crypto`); parola değişimi tüm oturumları kapatır (ADR-0006).
- **KARAR** Web oturumu localStorage'da (`LocalKvSecretStore`) — XSS ödünü self-host v1 için kabul, httpOnly refresh-cookie park (OPH-025); "web token yalnız bellekte" diyen metin bayattır.
- **DERS** `app.rejectApiKeys` preHandler'dır (authenticate'ten SONRA); `/ai/*` kapısı plugin-seviyesi hook (yeni rota unutamaz); rate limiter kimlikten ÖNCE koşar → `keyGenerator` başlığa bakar.
- **DERS** Rate limit app seviyesinde (`request.ip`) → ikinci limitleyici yazma, rotayı `config.rateLimit`'le daralt; `TRUST_PROXY` varsayılan kapalı → proxy arkasında herkes 127.0.0.1 tek kova.
- **DERS** Kullanıcıya özel akış (AI sohbeti) `user:{userId}` soket odasına gider; `ws:*` workspace odası onu tüm üyelere yayınlar.
- **DERS** `routes/oauth.js` `renderPage` title'ı kaçırır, body'yi HAM basar; helmet CSP kapalı → kullanıcı içeriği basan HTML sayfası her enterpolasyonu kaçırır, CSP seçer, payload'lı test.
- **DERS** İki OAuth ters yöne bakar: `routes/oauth.js` MCP için OAuth 2.1 SUNUCUSU, `lib/oauth-identity.js` yalnız Google/Apple ID token; harici kimlik ayrı uçtan — `/auth/login`'i dallandırmak dummy verify'ı bozar.
- **DERS** Kullanıcı kontrollü dış URL SSRF'tir: yalnız http/https, IP denetimi DNS'ten SONRA ve her yönlendirmede, gövde tavanı; AI `baseUrl`'inde (`aiFetch`) allowlist yok — bilinçli kabul (SECURITY.md).
- **DERS** `refresh_tokens` her yenilemede satır yazar: "oturum" = `family_id` ailesi, liste/iptal aile başına; yenileme UA göndermeyebilir → cihaz adı yalnız INSERT'te ("kolon var" ≠ "kolon dolu").

## extension-seam — uzantı dikişi (yalnız public yüzey)
- **KARAR** Uzantı ayrı özel depoda (`ee/` iç içe checkout; `.gitignore` + `check:no-ee`); çekirdek işleri CE davranışını değiştirmez (boş defter); public belge/commit'e uzantı tasarımı değil yalnız kayıt kimliği girer.
- **KARAR** Veriyi yazan uzantı yoksa veri sunulmaz: yüklenemeyen uzantı + defterde yabancı migration (ya da `EE_REQUIRED=true`) → `/health/*` dışı her istek 503 `EXTENSION_UNAVAILABLE`; fail-open-to-CE geçersiz (ADR-0041).
- **KARAR** Uzantının kimlik doğrulayıcısı parola kontrolünden ÖNCE, her adres için sorulur, üç cevaplı (null/ret/kabul); hesabı var edemez, yalnız adlandırır; fırlatırsa 5xx — hesap-var-mı kehaneti yok.
- **KARAR** Uzantı replika tabloları ayrı drift dosyası açmaz (ikinci dosya = ikinci WAL/`busy_timeout`); göç adımı iş başına; her tablo arama gölge kolonlarını da alır.
- **DERS** Seam'in taşıyıcısı SIRALAMA: loader altyapı eklentilerinden sonra, rotalardan önce; kayıt defterleri app-scoped (modül düzeyi iki test app'inde çakışır); önce kaydolan eklenti uzantı durumunu istek anında okur.
- **DERS** Yetenek keşfinde 404 (eski sunucu) ile boş liste aynıdır: "kapalı", hata değil; `/ee/status` her derlemede kayıtlı (CE: boş 200), `localKv`'de KULLANICI bazlı önbelleklenir.
- **NOT** Üretimde `EE_ENABLED` varsayılanı açık; sade kurulum (uzantı yok + temiz defter ya da `EE_REQUIRED=false`) bayt bayt aynı kalır — kilit kancası yalnız kilitlenebilecekken takılır.
- **NOT** ADR numaraları iki depoda çakışır → atıfta depoyu yaz; core `docs/adr/0002-*` AGPL lisans ADR'si (ADR-0024 geçersiz kıldı), seam sözleşmesi ve revizyonu uzantı deposunun ADR-0002'sinde.

## sandbox-tooling — betikler, yamalar, uzak koşu
- **DERS** Python/sed yaması eşleşmezse (kaçış farkı, `dart format`'ın böldüğü çağrı) sessizce hiçbir şey yapmaz → her yamaya "eski metin vardı / yeni yazıldı" assert'i.
- **DERS** Enjeksiyonda `cp` hatasında dur ("yeşil kaldı" yalanı); geri alınan dosyayı sandbox'a yeniden gönder + checksum; hedefli tar'a girmeyen dizin sandbox'ta bayat kalıp ölçülür (`apps/app/assets/i18n` her pakette).
- **DERS** `&&` zinciri eşleşmeyen grep'te (exit 1) sessizce kesilir, "ölçüm yok" "sıfır" görünür → ölçüm zincirinde `;`; zsh'te tırnaksız `--include=*.js` "no matches found" verir.
- **DERS** Yerelde npm betikleri guard hook'a takılır → kapıları `node scripts/…` ile koş; `apps/app/lib` okuyan core kapıları sandbox'ta ENOENT verir → onları yerelde koş.
- **KARAR** Süitler `npm run verify:task|batch` ile koşar (ADR-0042): sandbox'a yalnız git'in izlediği/izleyeceği dosyalar gider (`apps/app` yok — fikstür ve i18n var; sır şekli reddedilir), ağaç her koşuda temiz kurulur, `node_modules` lockfile özeti değişmedikçe taşınır. Dışlanan yoldan yeni dosya okuyan test yalnız orada ENOENT verir → yolu `scripts/verify/verify.mjs` `include`'una ekle.
