# STATE — Live development state

> The pointer for "do the next task" (TR: _"sıradaki işi yap"_). Read it first; update it **in
> place** before finishing a session — overwrite the cells (never append the old value after the
> new one) and never add session blocks: `npm run check:docs` enforces both and a 16 KB budget.
> Backlog: [TASKS.md](TASKS.md) — `npm run next` prints the next task, and `check:docs` keeps the
> pointer below equal to it · traps and decisions by area: [LESSONS.md](LESSONS.md) (grep the
> area, don't read it whole) · loop contract: [../LOOP.md](../LOOP.md) · history: `git log` +
> [CHANGELOG](../CHANGELOG.md). The full text as it stood before the 2026-09-26 cleanup:
> `git show 85b6c1b:docs/STATE.md`.

**Last updated:** 2026-10-07 — OPH-360 kapandı (yönetim, portal bağlantıları ve rapor ekranları);
Epic 34'ün core yarısı bitti, backlog boş.

## Snapshot

|                          |                                                                                              |
| ------------------------ | -------------------------------------------------------------------------------------------- |
| Current phase            | **v1.15.0 canlıda** (2026-09-30, `389c8c8` + uzantı `01c2c26`). Epic 34'ün (2026-10-07 UI denetimi) core işleri OPH-355…OPH-360 kapandı; açık iş yok (yalnız sahibin ⏸️ adımları). Uzantının el kitabı `/settings/team/customers` satırını bekliyor (uzantı EE-304 — `check:docs`'u o rota için kırmızı). |
| Current epic             | — (Epic 34 kapandı; sıradaki epic sahibin kararıyla açılır) |
| ➡️ **Next task**         | **BACKLOG BOŞ** |
| Last completed           | OPH-360 — istemci: portal linkinde süre seçimli uzatma (1/2/7/30 gün, yeni bitiş önizlemesi), satırda servisler/birim/tarih, iptal "Vazgeç"/"Bağlantıyı iptal et", adlı diyaloglar, pano hatası snackbar; `/settings/team/customers` (firma ve kişiler: ekle, davet, kapat/aç, adlandır, arşivle; eski sunucuda "desteklemiyor"); SLA yönetiminde silme onayı, varsayılan politika korunur, ad `onChanged`, hedef tablosu, birim arşivi ve davet iptali onayı; SLA panosu Aşıldı/Yaklaşıyor/Tutuldu, "N değerlendirilen", varsayılan yok uyarısı, ihlal #numara + gezinme; yerel sayı/süre biçimi (pano + performans); kuyruk ve denetim günlüğünde CSV indir; denetim günlüğü tür adları, kayıt adı ve bağlantı, başlık; izin açıklamaları tr+en (`ee.permDescription.*`); devamsızlık ufku 365 gün; form tasarımcısı durumu; boş birim. |

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
8. **OPH-227** — Claude Connectors Directory + ChatGPT app dizin başvuruları
   (`docs/store/directories.md`, önkoşulları boş).
9. **Üç ayda bir AI sağlayıcı politika kontrolü** (abonelik-OAuth duruşu; `docs/AI.md` §1 son
   doğrulama 2026-07-29) — ilki **~2026-10**.
10. **Kayıtsız — ölç:** Firebase'e iOS APNs anahtarı yüklendi mi (VAPID + FCM 2026-09-19'dan beri
    canlıda; APNs yoksa iOS'a hiçbir push teslim edilmez ve hiçbir test yakalamaz) · OpenAI "Sign in
    with ChatGPT" ilgi formu kaydı · ilk dış kullanıcıya (Epic 29) kapanış maili · prod R2 (+ web
    CORS) ve prod Google OAuth redirect'i.

Cihazda bakılacaklar (isteğe bağlı gözlem): [DEVICE-CHECKS.md](DEVICE-CHECKS.md).

## Sahip kararları (bağlayıcı — yeniden tartışılmaz)

Alana özgü kararlar [LESSONS.md](LESSONS.md)'de, alan başlıkları altında. Burada her işi bağlayanlar:

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
