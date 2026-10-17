# STATE — Live development state

> The pointer for "do the next task" (TR: _"sıradaki işi yap"_). Read it first; update it **in
> place** before finishing a session — overwrite the cells (never append the old value after the
> new one) and never add session blocks: `npm run check:docs` enforces both and a 16 KB budget.
> Backlog: [TASKS.md](TASKS.md) — `npm run next` prints the next task, and `check:docs` keeps the
> pointer below equal to it · traps and decisions by area: [LESSONS.md](LESSONS.md) (grep the
> area, don't read it whole) · loop contract: [../LOOP.md](../LOOP.md) · history: `git log` +
> [CHANGELOG](../CHANGELOG.md). The full text as it stood before the 2026-09-26 cleanup:
> `git show 85b6c1b:docs/STATE.md`.

**Last updated:** 2026-10-17 — OPH-381: Google/Apple ile giriş ikinci faktörü (TOTP) ve uzantı politikasını soruyor; uygulamada kod istemi.

## Snapshot

|                          |                                                                                              |
| ------------------------ | -------------------------------------------------------------------------------------------- |
| Current phase            | **v1.15.0 canlıda** (2026-09-30, `389c8c8` + uzantı `01c2c26`). Epic 34'ün (2026-10-07 UI denetimi) core işleri OPH-355…OPH-363 ve sahip isteğiyle OPH-364 (MCP bulunabilirliği) kapandı; açık iş yok (yalnız sahibin ⏸️ adımları). Uzantının el kitabı `/settings/team/customers` satırını bekliyor (uzantı EE-304 — `check:docs`'u o rota için kırmızı). |
| Current epic             | — (Epic 34 kapandı; sıradaki epic sahibin kararıyla açılır) |
| ➡️ **Next task**         | **BACKLOG BOŞ** |
| Last completed           | OPH-381 (güvenlik, sahip onaylı): `POST /auth/oauth` bilinen/bağlanacak hesapta TOTP + `signInRequirements`'ı `/auth/login` ile aynı ortak yardımcıdan (`lib/sign-in-factors.js`, MCP onay sayfası da kullanıyor) ve HİÇBİR yazmadan önce çalıştırıyor; yeni hesapta politika hesabı açan transaction içinde. Uygulama `AUTH_MFA_REQUIRED`'da kod istemi gösterip aynı isteği (sosyalde aynı ID token'la) tekrar gönderiyor (ADR-0049 ek). |

## Kullanıcıdan bekleyen (sahibin adımları)

1. **Sunum** — v1.15.0 canlıda; kalan sıra uzantı deposunun `docs/DEMO.md` §A.3'ünde
   (demo tohumu → hazır olma → senaryo).
2. **Dağıtım runner'da (ADR-0043):** uzantıda `DEPLOY_OVERLAY_REF` v1.15.0'ın overlay'ine (`01c2c26`)
   sabit, `DEPLOY_NODE_PATH` sunucunun Node 18'i (kutudaki `/opt/node24` argon2'yi derleyemez). Bir sürüm
   etiketten tam otomatik çıktıktan sonra: eski deploy anahtarı + bu depodaki `DEPLOY_SSH_*`
   secret'ları emekliye, `diagnose.yml` runner'a.
3. **`main` için branch protection** — Settings › Branches, public depoda ücretsiz tek kural
   (2026-09-26: korumasız).
4. **OPH-142** — critical-alerts başvurusunun sonucu (onaylanırsa tek entitlement satırı).
5. **OPH-304** — Play Console `USE_EXACT_ALARM` beyanı (form + video; malzeme
   `docs/store/exact-alarm-declaration.md`). GitHub #11 kod tamam diye kapandı (2026-09-26);
   Galaxy A12 bildireni Android sürümü, alarm günlüğü ve cihaz bilgisiyle dönerse yeni issue.
6. **OPH-335** — macOS widget hedefi: `cd apps/app/macos && ruby scripts/add_widget_extension.rb`
   → Xcode'da AllisWellWidgetMac hedefine takımı seç → `flutter build macos` → pbxproj farkını
   commit'le (`macos/AllisWellWidgetMac/SETUP.md`).
7. **Landing captcha (isteğe bağlı)** — derlemede `VITE_SALES_CAPTCHA_PROVIDER` +
   `VITE_SALES_CAPTCHA_SITE_KEY`, sunucu yarısıyla birlikte (uzantının belgeleri); tek yarı her
   gönderimi reddeder.
8. **OPH-366** — Google redirect URI, Apple Services ID ve prod `.env`'deki `SIGN_IN_APPLE_SERVICE_ID`
   tamam (2026-10-17). Kalan: deploy'dan sonra DEVICE-CHECKS "MCP onayında Google/Apple" satırı.
9. **OPH-227** — Claude Connectors Directory + ChatGPT app dizin başvuruları
   (`docs/store/directories.md`, önkoşulları boş).
10. **Üç ayda bir AI sağlayıcı politika kontrolü** (abonelik-OAuth duruşu; `docs/AI.md` §1 son
   doğrulama 2026-07-29) — ilki **~2026-10**.
11. **OPH-365 mağaza** — App Store Connect › Promotional Text'e STORE-LISTING §1.3'ün yeni EN/TR
    satırlarını yapıştır (build gerekmez).
12. **Kayıtsız — ölç:** Firebase'e iOS APNs anahtarı yüklendi mi (VAPID + FCM 2026-09-19'dan beri
    canlıda; APNs yoksa iOS'a hiçbir push teslim edilmez ve hiçbir test yakalamaz) · OpenAI "Sign in
    with ChatGPT" ilgi formu kaydı · ilk dış kullanıcıya (Epic 29) kapanış maili · prod R2 (+ web
    CORS) ve prod Google OAuth redirect'i.

13. **OPH-369 Apple geri okuma** — Swift Mac'te derlendi (2026-10-17); kalan
    DEVICE-CHECKS "Apple Takvim geri okuma" bölümü (iPhone + Mac). Geçerse "iki yönlü Apple"
    metnine dönüş SAHİBİN kararı; dönülürse aynı değişiklikte: README, COMPARISON, SUPPORT(.tr),
    STORE-LISTING, landing `content*.js` + index sayfaları, `llms.txt`, web `index.html`/manifest ve
    `scripts/docs/check.mjs` APPLE_CLAIMS kapısı.

14. **OPH-370 masaüstü indirmeleri** — sonraki etiketten sonra Actions › Release'de "Desktop build
    (linux)", "Desktop build (windows)" ve "Attach desktop downloads" yeşil; sürümde
    `alliswell-linux-x64.tar.gz`, `alliswell-windows-x64.zip`, `alliswell-desktop-SHA256SUMS.txt`
    var ve README'nin `releases/latest/download/…` bağlantıları iniyor (o zamana kadar 404).
    Sonra DEVICE-CHECKS "Masaüstü indirmeleri". İsteğe bağlı: Authenticode sertifikası (ya da Azure
    Trusted Signing) + Windows işine signtool adımı → SmartScreen uyarısı kalkar.

15. **OPH-376 Siri** — Swift Mac'te derlendi (2026-10-17); kalan DEVICE-CHECKS "Siri ve kısayollar"
    (EN ve TR Siri cümleleri, Kestirmeler/Spotlight görünürlüğü, Mac, Android uzun basma).

16. **OPH-380 CalDAV** — sahip prod `.env`'de `CALDAV_ENABLED=true` yaptı (2026-10-17, alliswell.space'te açık); kalan
    DEVICE-CHECKS "CalDAV (iCloud / Nextcloud)": gerçek iCloud (uygulamaya özel parola, X-prop
    sağ kalıyor mu → CALDAV.md §4.4) ve gerçek Nextcloud; Apple cihazda çift ayna koruması.
    Onay/bağlantı kesme metinlerini (EN+TR `calendar.caldav.*`) ve PRIVACY(.tr) bölümünü ürün/hukuk
    metni olarak gözden geçir. alliswell.space'te açmak SAHİBİN kararı; açılana dek kamu metni
    "sunucu yöneticisi açtığında" der. VTODO yönü (CALDAV.md §9: A bağlayıcı / B AllisWell CalDAV
    sunucusu) sahibin kararı.

Cihazda bakılacaklar (isteğe bağlı gözlem): [DEVICE-CHECKS.md](DEVICE-CHECKS.md).

## Sahip kararları (bağlayıcı — yeniden tartışılmaz)

Alana özgü kararlar [LESSONS.md](LESSONS.md)'de, alan başlıkları altında. Burada her işi bağlayanlar:

- **İçe aktarma gerçek dosyayla denenmeden yayında (2026-10-17, OPH-371):** sahibin test verisi yok;
  gerçek bir Todoist/TickTick dosyasında sorun yaşayan kullanıcı GitHub issue açar, iş oradan doğar.
- **Çalışma belgeleri yalın (2026-09-26):** STATE işaretçidir, TASKS yalnız açık iştir; kapanan iş
  silinir; kalıcı tuzak LESSONS'a, doğrulama kanıtı commit mesajına. Hedef: her oturumun okuduğu
  belge küçük kalsın (`check:docs`).
- **Kontroller en sonda (2026-09-25; katmanları ADR-0042):** çok işli döngüde iş başına push/CI
  yok — iş `npm run verify:task` (K1: dokunulanın en dar testi) + belge + yerel commit ile kapanır;
  ağır süitler, kapılar, enjeksiyon ve push öbeğin sonunda tek turda (`npm run verify:batch`, K2);
  CI beklenmez, sonraki turun başında bir kez okunur (K3). Tur sözleşmesi [LOOP.md](../LOOP.md).
- **Cihaz gözlemi kapanış koşulu değil (2026-09-23):** iş derleme + testle kapanır; cihazda bakılacak
  şey işin "Cihazda bakılacak" satırına ya da DEVICE-CHECKS.md'ye yazılır. O güne kadar açık kalan
  cihaz/elle turları yapıldı sayıldı.
- **Etiket, sürüm, deploy ve release sahibindir:** döngü sürüm numarası değiştirmez, etiket itmez
  (etiket push'u bir deploy'dur), `gh workflow run` koşmaz, canlıya yazan komut çalıştırmaz (okuyan
  `curl` serbest). Kapanışın kelimesi "KOD TAMAM"dır.
- **Erteleme meşru, sessiz atlama değil:** yapılmayacak kutu `[~]` + tek cümle gerekçe; kutu,
  doğrulaması koşmadan `[x]` olmaz; ölçümle doğan boşluk ya aynı turda yeni id'li iş olur ya `[~]`.
- **İkiz işler** (`⚠️ Çift kapanış ↔`) iki depoda birlikte kapanır ve birlikte silinir
  (`check:twin-tasks`, uzantı deposunda).
- **Uzantının tasarımı public belgeye ve commit'e girmez;** core ondan yalnız "uzantı" diye söz eder,
  core'a yalnız nötr bir dikiş iner.
- **Dış kullanıcı raporu:** önce koddan doğrula → TEK epic → STATE/ROADMAP → push → issue → cevap
  maili; bir tester/inceleme listesinin tamamı kuyruğun önüne, sıra sorulmadan.
- **Commit ve CHANGELOG:** co-author satırı yok; mesaj ters tırnaksız ve dosyadan (`-F`) verilir.
  CHANGELOG'a yalnız kullanıcının göreceği değişiklik girer.
- **Masaüstü indirmeleri (2026-10-16, ADR-0051):** yalnız Windows zip + Linux tar.gz, imzasız;
  macOS yok, kurulum paketi/AppImage/deb yok. Dosya adları sürümsüz (`latest/download` bağlantısı
  kalıcı), sürüm klasör adında ve ikilide.
- **İçe aktarma (2026-10-16, ADR-0052):** yalnız Todoist + TickTick (Apple Anımsatıcılar'ın dosyası
  yok, vaat edilmez); sunucu ayrıştırır; alt görev → kontrol listesi, bölüm/sütun → etiket, p1 →
  yüksek; içe aktarılan görev asla acil alarm değil; tamamlananlar isteğe bağlı; tekrar içe aktarma
  atlar, güncellemez, silineni geri getirmez; MCP'ye araç yok.
- **Her yerden arama (2026-10-16, ADR-0055):** ⌘K (Apple) / Ctrl+K, ikisi birden asla; telefonda
  giriş alt çubuğun yanındaki yuvarlak düğme, uygulama çubuğuna ikon yok (bu yüzden telefonda
  çoğunlukla yalnız seçili sekmenin etiketi yazılır); tamamlanan görev bulunur, iptal bulunmaz;
  arşivli not bulunmaz; masa eki dosyası bulunmaz; etiket sonucu Ana sayfayı süzer.
- **Tamamlanınca tekrar (2026-10-17, ADR-0056):** gün/hafta/ay (yıl yok, 12 ay); tamamlama anından
  sayılır (erken/geç), saat aynı; sıradakini yalnız sunucu üretir — çevrimdışı tamamlamada sıradaki ve
  alarmı ilk sync'te gelir; yalnız `completed` ilerletir, `cancelled` değil; sıradaki tamamlanan
  satırdan kopyalanır (kapsam sorusu yok); açık olanı silmek tekrarı durdurur; tekrarı kapatmak açık
  görevi sıradan görev olarak bırakır; MCP durduramaz.
- **Sesle ekleme (2026-10-17, ADR-0057):** iOS/macOS niyetleri uygulamayı öne getirir, arka planda
  görev oluşturmaz (alarm Dart'ta kurulur; başsız Flutter çöktü); metin URL'de taşınmaz; sese
  Fikirler hızlı ekleme kuralı uygulanır (tarihsiz → Fikirler); "Bugün" Ana sayfayı bugünle açar,
  Siri sesli özet okumaz. Android'de yalnız iki statik başlatıcı kısayolu; App Actions, AppFunctions,
  AUTO_SEND, CREATE_NOTE yok (2026'da işleyen bir asistan yolu yok).
- **AI'ya ek (2026-10-17, ADR-0058):** yalnız "@" ile seçilen gönderilir (otomatik bağlamda not ve
  dosya yok); not/metin dosyası/görev/proje; PDF/görsel/Office eklenmez (çıkarım yolu yok); ekler
  sohbet boyunca kalır; ekli turda görev kapısı atlanır (ekten görev çıkarılmaz).
- **CalDAV (2026-10-17, ADR-0059):** iCloud + genel CalDAV birlikte; hepsi `apple_caldav` +
  `caldav_kind` (API `caldav` der); varsayılan kapalı, özel/LAN adres ve http yalnız
  `CALDAV_ALLOW_PRIVATE_HOSTS` ile; iCloud seçeneği yalnız Apple olmayan cihazda, genel her yerde;
  kullanıcı başına çalışma alanında tek hesap; sunucu iCloud'a yazarken cihazdaki EventKit aynası
  kendi etkinliklerini siler ve durur; yoklama 300 sn; kendi etkinlikleri tekrarlılar dahil
  önbellekte (seri başına ≤500); bağlanma yalnız oturum, MCP aracı yok; VTODO yok (sahip seçer).
- **Görseller üretilir, çekilmez:** belge ve mağaza görüntüleri golden testlerden ve demo tohumundan;
  gerçek kullanıcı verisi hiçbir belgeye girmez.

## Blocked / notes

- Uzantı deposunda branch koruması mevcut GitHub planında mümkün değil (403); telafisi OPH-345'in
  dağıtım kapısı — kırmızı bir commit `main`'e girebilir ama sunucuya çıkamaz.
- `docs/adr/0002-*` bu depoda AGPL ADR'sidir (ADR-0024 onu geçersiz kıldı); uzantı dikişinin
  "ADR-0002"si uzantı deposundadır.

## Environment assumptions

- Node ≥ 22; CI'da Flutter 3.44 / Dart 3.12 — yerel araç zinciri daha yeni olabilir, biçimleme CI'ın
  sürümüyle yapılır (LESSONS `ci-release`).
- Ağır iş (Docker, süitler, veritabanı, dev sunucuları) sandbox'ta (`sbx`); yerelde düzenleme, git,
  arama ve native derleme.
- iOS/macOS imza takımı APILLON `WWRZ5CG3DW`.

## How to continue (for agents)

1. [../AGENTS.md](../AGENTS.md) §2: işi `npm run next` basar (döngüde `-- --batch 4`,
   [../LOOP.md](../LOOP.md)); TASKS'ı bütün okuma.
2. Dokunacağın alanı [LESSONS.md](LESSONS.md)'de grep'le; bağlayıcı metin ilgili ADR'lerde.
3. İş başına `npm run verify:task` + yerel commit; öbek sonunda `npm run verify:batch`, yeşilse
   tek push. Bitişte: biten işi TASKS'tan sil, bu dosyanın hücrelerini yerinde güncelle, tek
   CHANGELOG girdisi, Conventional Commit.
