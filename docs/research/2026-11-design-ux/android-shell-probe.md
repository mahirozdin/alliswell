> **Depodaki kopya (2026-11-07, E35 kaydı):** uzantıya özgü tasarım ayrıntısı çıkarıldı (uzantı bulguları uzantı deposunda); turun iç çalışma dosyalarına ve ham kanıta verilen yollar düz metne çevrildi ("ham kanıt" = turun çalışma alanında kalan dosya; depoda yok). Bulgu kimlikleri değişmedi. Özet: [README.md](README.md).

> Son güncelleme: 2026-11-07 — CEO tasarım/UX turu
> Kaynak: sahip brief'i (O-02, C-01, C-02), kök neden raporu `ux-shell-mobile.md` (R-01…R-14, §6), bu tur yazılan Android probe testi ham kanıt (gerçek router + tema + kabuk + `QuickAccessBubbleHost`, FakeApi demo tohumu, gerçek kullanıcı verisi yok), `apps/app/lib/src/**` kodu, `docs/DESIGN.md` (G4, §23 Q4/Q4a/Q4c, §24 AI1), Flutter 3.47.7 `navigation_bar.dart`, Android edge-to-edge belgesi <https://developer.android.com/develop/ui/views/layout/edge-to-edge>

# Android kabuk probe'u: 360/412 dp, dokta Hızlı Erişim balonu, 6 bölüm (uzantı), snackbar ve tanıtım kartı

## 0. Yöntem

- **Test:** ham kanıt. Önceki probe'un kopyası değil, genişletilmiş hali:
  - `debugDefaultTargetPlatformOverride = TargetPlatform.android` (iOS karşılaştırmaları için `iOS`).
  - Builder, `app.dart:83-95` ile aynı katmanları monte ediyor: `AwGlobalSearchHost(QuickAccessBubbleHost(child))`. Balon fabrika konumunda (`bubble_physics.dart:61-64`, `kBubbleFactoryPosition` = sağ, dok) çiziliyor.
  - 6 bölüm (uzantı açıkken): uygulamanın kendi listesi `visibleAppSections` (`sections.dart`), uzantı bayrakları override edilerek (`home_shell.dart:202-205`).
  - Snackbar: kabuğun `ScaffoldMessenger`'ı üzerinden, temanın kayan stiliyle demo metni "Görev tamamlandı / Geri al".
  - Tanıtım kartı: `quickBubbleHintedProvider` false iken (ilk kullanım), 6 sn zamanlayıcısı dolmadan ölçüldü.
- **Komut:** `cd apps/app && flutter test --update-goldens <test yolu>` (Flutter 3.47.7). 37 yapılandırma, 37/37 geçti. Log: ham kanıt.
- **Matris:**
  - Android 360×800 (alt inset 24 = hareket çubuğu; 48 = 3 düğmeli gezinme), 412×915 (alt 24), üst inset 24. TR (koyu) ve EN (açık). Metin ölçeği 1.0 / 1.3 / 2.0. Hepsinde balon dokta. Her cihaz için bir de balonsuz taban.
  - iOS doğrulaması (önceki R-04 yalnız hesaptı): 430×932 b34, 393×852 b34, 375×667 b0, balon dokta.
  - 6 bölüm (uzantı): Android 360 (g24, g48, 1.3×, EN), Android 375×812, iOS 375×667, dokta ve balonsuz.
  - Tanıtım kartı: 360 g24, 360 g48, 412 EN, 360 2.0×, iOS 393.
- **Çıktılar**
  - JSONL (yapılandırma başına bir satır): ham kanıt. Alanlar: her sekmenin `slot` dikdörtgeni, `g4`, M3 gösterge dikdörtgeni (`indicator`, `indicatorShrunk`, `indicatorStadiumInCapsule` = stadyum dış hattının 72 noktası kapsül RRect'inde mi), ikon, etiket kutusu + gerçek metin genişliği (`intrinsicW`), `overflowsSlot`, `cornersInCapsule` (r=32 RRect), `bottomGapToCapsule`, küre, FAB'lar, balon, `intro*`, `snack*`.
  - PNG (2×): ham kanıt (37 adet) ve snackbar'lı `<ad>_snack.png` (14 adet). Örnekler:
    - ham kanıt
    - ham kanıt
    - ham kanıt
    - ham kanıt
  - Ham kırpıntılar: ham kanıt (her yapılandırma), app bar kırpıntıları ham kanıt ve tek sayfada 14 bar kırpıntısı ham kanıt.
- **Sınırlar**
  - Ölçüler mantıksal dp/pt'dir. Yazı tipi harness'ınki (Roboto + DejaVu, `ScreenshotSans`); Android'in kendi Roboto'suna yakın, ama OEM yazı tipleri (Samsung One UI vb.) ölçülmedi.
  - Gerçek cihaz ya da emülatör çalıştırılmadı (**NOT RUN**). Sistem gezinme çubuğunun scrim'i, gerçek edge-to-edge davranışı ve OEM yazı tipleri cihazda doğrulanmalı (§5).
  - "Etiket köşeleri" Text kutusu ile ölçüldü; satır aralığı payı içerdiği için muhafazakâr bir ölçü. Görsel sonuç kırpıntılarla ayrıca kontrol edildi.

## 1. Özet

1. **G4, Android'de dokta balonla her telefonda kırılıyor.** DESIGN G4 Android için **48 dp** istiyor (`docs/DESIGN.md:50`: "Tap targets ≥ 44 px (48 dp Android)").
   - Sekme genişliği 360 dp'de **36 dp**, 412 dp'de **46,4 dp**. uzantının 6. bölümüyle 360 dp'de **30 dp**.
   - Balon olmadan 360 dp'de tam 48 dp (sınırda geçiyor), uzantıyla 40 dp (kırık).
   - Görev metnindeki hesap (dok yokken 48, uzantıyla 40) ölçüyle birebir doğrulandı.
2. **64 dp'lik M3 göstergesi kırpılmıyor, daralıyor.** `NavigationIndicator`, yuvanın gevşek kısıtıyla yuva genişliğine iniyor:
   - 360 dp'de 36×32, uzantıda 30×32 (genişliğinden uzun bir hap);
   - 412 dp'de 46,4×32.
   - Stadyum dış hattı her yapılandırmada kapsülün içinde kalıyor. Yani sorun kırpma değil, "hap" yerine yassı bir daire.
3. **Seçili etiket yuvadan taşıp komşu ikonun altına giriyor.**
   - "Ana Sayfa" 59 dp (1.3×'te 75,3 dp), yuva ise 36 dp. Etiket 23 dp (1.3×'te 39 dp) sağa taşıyor ve "Fikirler" ikonunun altında bitiyor.
   - TR'de hiçbir Android yapılandırmasında etiket köşeleri kapsül RRect'inin içinde değil. EN'de yalnız 412 dp + 1.0× içinde.
4. **Tanıtım kartı (QuickBubbleIntro) dokta iken ekranın altına, sistem gezinme alanına çiziliyor.**
   - 48 dp yüksekliğindeki kartın 360/412 g24'te yalnız **20 dp**'si ekranda, iPhone 393'te 30 dp'si.
   - 3 düğmeli gezinmede kart tamamen sistem düğmelerinin altında (756–804, ekran 800, sistem bandı 752–800).
   - Bu, önceki raporda hiç görünmeyen yeni bir **major** bulgu (A-03).
5. **Snackbar sorunsuz:** FAB satırının 16 dp üstünde, kapsülün 88 dp üstünde. Balon, küre, kapsül ya da FAB'la çakışmıyor (A-07).
6. **R-01…R-14'ün çoğu Android'de aynen ya da daha ağır geçerli.**
   - R-01 (karma etiket) her Android genişliğinde etkin; 412 dp'de dok olmadan bile (yuva 58,4 < 64).
   - R-05: 360 dp'de 1.0× ölçekte bile başlık "Ana Sa…" diye kesiliyor; iOS'ta bu yalnız SE 2.0×'te oluyordu.
   - R-10'un izleme (letterSpacing) kısmı Android'de geçersiz: M3 değerleri Roboto için.

## 2. Ölçüm tabloları

### 2.1 Sekme yuvası, gösterge ve etiket (TR, 1.0×, balon dokta, aksi yazılmadıkça)

| Yapılandırma | Sekme | Kapsül x | Yuva (dp) | G4 (48 dp Android / 44 pt iOS) | Gösterge | Etiket taşması | Etiket köşeleri RRect içinde | İkon üst farkı |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Android 360 g24 | 5 | 12–216 | **36,0** | ✗ | 36×32, kapsül içinde | "Ana Sayfa" 59 → +23 dp | ✗ | 10 |
| Android 360 g24, balonsuz | 5 | 12–276 | 48,0 | ✓ (sınırda) | 48×32 | +11 dp | ✗ | 10 |
| Android 360 g48 | 5 | 12–216 (y 688–752) | 36,0 | ✗ | 36×32 | +23 dp | ✗ | 10 |
| Android 360 g24, 1.3× / 2.0× | 5 | 12–216 | 36,0 | ✗ | 36×32 | 75,3 → +39 dp | ✗ (alt boşluk 3,5) | 12,5 |
| Android 360 g24 EN | 5 | 12–216 | 36,0 | ✗ | 36×32 | "Home" 34,1, sığıyor | ✗ (sol alt köşe eğride) | 10 |
| Android 412 g24 | 5 | 12–268 | **46,4** | ✗ (Android), ✓ (44) | 46,4×32 | +12,6 dp | ✗ | 10 |
| Android 412 g24 EN 1.0× | 5 | 12–268 | 46,4 | ✗ (Android) | 46,4×32 | yok | ✓ | 10 |
| Android 412 g24, balonsuz | 5 | 12–328 | 58,4 | ✓ | 58,4×32 | +0,6 dp | ✗ | 10 |
| iOS 430 b34 | 5 | 12–286 | 50,0 | ✓ | 50×32 | +9 | ✗ | 10 |
| iOS 393 b34 | 5 | 12–249 | **42,6** | ✗ | 42,6×32 | +16,4 | ✗ | 10 |
| iOS 375 b0 | 5 | 12–231 | **39,0** | ✗ | 39×32 | +20 | ✗ | 10 |
| **Uzantı** Android 360 g24 | 6 | 12–216 | **30,0** | ✗ | 30×32 | +29 dp | ✗ | 10 |
| **Uzantı** Android 360 g24, balonsuz | 6 | 12–276 | **40,0** | ✗ | 40×32 | +19 | ✗ | 10 |
| **Uzantı** Android 360 g48 / 1.3× / EN | 6 | 12–216 | 30,0 | ✗ | 30×32 | +29 / +45 / +4 | ✗ | 10 / 12,5 / 10 |
| **Uzantı** Android 375 g24 | 6 | 12–231 | 32,5 | ✗ | 32,5×32 | +26,5 | ✗ | 10 |
| **Uzantı** iOS 375 b0 | 6 | 12–231 | **32,5** | ✗ | 32,5×32 | +26,5 | ✗ | 10 |
| **Uzantı** iOS 375 b0, balonsuz | 6 | 12–291 | **42,5** | ✗ | 42,5×32 | +16,5 | ✗ | 10 |

Notlar:

- **Yuva = dokunma hedefi genişliği.** `NavigationBar` her hedefi `Expanded` ile yayıyor; yüksekliği 64 dp.
- **Önceki raporun hesapları ölçüyle doğrulandı.** R-04 iPhone için 50 / 42,6 / 39, uzantılı SE için 32,5 / 42,5 öngörmüştü; ölçüm birebir aynı çıktı (`probe.jsonl` satırları `ios430b34…`, `ios393b34…`, `ios375b0…`, uzantılı `ios375b0…`).
- **Bütün yapılandırmalarda etiket modu `onlyShowSelected`.** Seçili ikon 10 dp (1.3× ve üstünde 12,5 dp) yukarıda (`iconTopSpread`). Flutter etiketi 1.3'te sınırladığı için (`navigation_bar.dart:31`) 2.0× ile 1.3× aynı.
- **Hata yok:** hiçbir yapılandırma framework istisnası vermedi (`exception: null`). Taşma `overflow: visible` olduğu için sessiz kalıyor (`home_shell.dart:476-479`).
- **Görsel kanıt:**
  - ham kanıt: yassı gösterge, "Ana Sayfa" Fikirler ikonunun altına uzanıyor, sağda yarı içeri çekilmiş balon.
  - ham kanıt: 30 dp'de 6 ikon, gösterge ikondan dar.
  - ham kanıt: karşılaştırma için balonsuz hali.

### 2.2 Yüzen öğeler (TR, 1.0×, AI açık, balon dokta)

| Yapılandırma | AI FAB | + FAB | Küre | Balon (56) | Balon–bar merkezi dikey farkı | Kapsül alt kenarı → ekran altı |
| --- | --- | --- | --- | --- | --- | --- |
| Android 360 g24 | 8–64 × 640–696 | 296–352 × 640–696 | 224–288 | 296–352 × 716–772 | 0 | 24 |
| Android 360 g48 | 8–64 × 616–672 | 296–352 × 616–672 | 224–288 | 296–352 × 692–748 | 0 | 48 |
| Android 412 g24 | 8–64 × 755–811 | 348–404 × 755–811 | 276–340 | 348–404 × 831–887 | 0 | 24 |
| Android 360 g24, balonsuz | aynı | 296–352 | 284–348 | — | — | 24 |

- **Dokta balon + FAB'la aynı sütunda, doğrudan altında** (ikisi de x 296–352). Küre ise sola kayıyor ve artık FAB'ın altında değil. Balonsuzken küre (merkez 316) ile + FAB (merkez 324) arasında R-06'daki 8 dp kayma Android'de de var.
- **Dinlenmede balon yarısı ekran dışında, %40 opak** (Q4/Q4a). Bar kendisi için 72 dp'lik şerit ayırıyor, ama orada yalnız yarım, soluk bir daire görünüyor (kırpıntılarda sağ kenar). Açık temada neredeyse görünmüyor: ham kanıt.

### 2.3 Snackbar ve tanıtım kartı

| Yapılandırma | Snackbar (görünen gövde, inset 16 düşülmüş) | FAB üstüne boşluk | Kapsül üstüne boşluk | Çakışma |
| --- | --- | --- | --- | --- |
| Android 360 g24, 1.0× | 16–344 × 576–624 | 16 | 88 | yok |
| Android 360 g24, 2.0× | 16–344 × 514–624 (110 yükseklik) | 16 | 88 | yok |
| Android 360 g48 | 16–344 × 552–600 | 16 | 88 | yok |
| Android 412 g24 | 16–396 × 691–739 | 16 | 88 | yok |
| Uzantı Android 360 g24 | 16–344 × 576–624 | 16 | 88 | yok |
| iOS 393 b34 | 16–377 × 618–666 | 16 | 88 | yok |

Ham `SnackBar` dikdörtgeni 16 dp'lik `insetPadding`'i (`theme.dart:405-416`) içeriyor; JSONL'deki `snackOverlapsFab: true` bu kenar payının FAB'ın üst kenarına değmesinden geliyor, gövdenin çakışmasından değil. Görsel: ham kanıt.

| Yapılandırma | Tanıtım kartı | Ekranda görünen yükseklik | Sistem inset'inde mi |
| --- | --- | --- | --- |
| Android 360 g24 | 104–348 × **780–828** (ekran 800) | **20 / 48** | evet |
| Android 360 g48 | 104–348 × 756–804 | 44 / 48, ama tamamı 3 düğmeli gezinme bandında (752–800) | evet |
| Android 412 g24 EN | 156–400 × 895–943 (ekran 915) | 20 / 48 | evet |
| Android 360 g24 2.0× | 104–348 × 780–892 | 20 / 112 | evet |
| iOS 393 b34 | 137–381 × 822–870 (ekran 852) | 30 / 48 | evet (ev göstergesi) |

Görsel: ham kanıt (kartın yalnız ilk satırının üst yarısı görünüyor) ve ham kanıt.

## 3. Yeni bulgular (Android probe'undan)

Şiddet: blocker / major / minor. Efor: S (≤½ gün) / M (1–2 gün) / L (3+ gün).

### A-01 — Android'de dokta balonla bütün sekmeler G4'ün altında: 36 dp (360), 46,4 dp (412), uzantıda 30 dp — **blocker**, efor M

- **Kanıt**
  - `probe.jsonl` → `a360g24_tr_s10_docked.minSlotW = 36`, `a412g24_tr_s10_docked.minSlotW = 46.4`, uzantılı `a360g24_tr_s10_docked.minSlotW = 30`. Bu yapılandırmaların hepsinde `g4AllTabs: false`.
  - Balonsuz: `a360g24_tr_s10_nobubble` = 48 (Android eşiğinde), uzantılı `a360g24_tr_s10_nobubble` = 40.
  - Eşik `docs/DESIGN.md:50` (G4: 48 dp Android). Değişmez: AGENTS.md I-11 "taps ≥ 44 px".
  - Neden: kapsül + 8 + küre 64 + balon şeridi 72 (`home_shell.dart:715-722` `_barPadding`, `bubble_physics.dart:174-182` `bubbleDockLane`). Satırda üç cam nesne var.
  - Android pazarının büyük kısmı 360–412 dp genişlikte. Bu yüzden ihlal kenar durum değil, varsayılan durum: fabrika ayarı dok ve demo tohumunda tek bir kısayol yeter.
- **Önerilen düzeltme:** R-04'teki yön (bar satırında en fazla iki nesne: kapsül + küre).
  - Dokta balon ya kürenin üstüne (FAB şeridine) çıkar ya da küreyle birleşir (uzun basma → Hızlı Erişim).
  - Ek olarak bölüm sayısı ve genişlikten bağımsız bir taban: yuva < 48 dp (Android) / 44 pt (iOS) olursa kabuk küreyi app bar'a taşır ya da `alwaysHide` etiket moduna geçer (R-01 A seçeneği).
- **SAHİBE SORU:** Balonun bar satırında dok olması DESIGN §23 Q4 (OPH-362) kararı. Küreyle bar satırını paylaşmak ise ADR-0055 / DESIGN §40 P1. İkisinden birine dokunmadan 360 dp'de G4 sağlanamıyor. Hesap (ölçüyle aynı): kapsül = 360 − 12 (sol) − 72 (balon şeridi) − 64 (küre) − 8 (ara) = 204; iç dolgu 2×12 düşülünce 180; 180 / 5 = **36** (EE: 180 / 6 = 30).
- **Kilit test:** `test/features/shell/bar_alignment_test.dart` (R-01 matrisi) Android ekseniyle genişletilsin.
  - Matris: `debugDefaultTargetPlatformOverride` {android, iOS} × genişlik {360, 375, 393, 412, 430} × bölüm {5, 6} × balon {yok, dokta}.
  - Beklenti: `NavigationDestination` dikdörtgeninin genişliği ≥ 48 (android) / 44 (iOS).
  - Bu probe testinin `_measure` gövdesi doğrudan taşınabilir.

### A-02 — M3 göstergesi kırpılmıyor, yuvaya sıkışıp yassı daireye dönüyor; seçili etiket komşu sekmenin altına taşıyor — **major**, efor S

- **Kanıt**
  - `probe.jsonl` → `destinations[*].indicator.w` = yuva genişliği (36 / 30 / 46,4), `indicatorShrunk: true`, `indicatorStadiumInCapsule: true`. Flutter `NavigationIndicator` sabit 64×32 istiyor (`navigation_bar.dart:30`), ama `_NavigationDestinationLayoutDelegate` ikonu `BoxConstraints.loose(size)` ile yerleştiriyor (`navigation_bar.dart:1100-1101`), bu yüzden gösterge yuvaya iniyor. Kırpma yok, şekil bozuluyor: 30×32'de gösterge ikondan (24) yalnız 3 dp geniş.
  - Etiket: `Text` kutusu yuvaya kısıtlı ama `overflow: visible` + `softWrap: false` (`home_shell.dart:476-479`) ve `TextAlign.start`. Metin sağa doğru taşıyor (`intrinsicW` 59 → kutu 36, taşma 23 dp; 1.3×'te 39 dp).
  - Görsel: `crop_a360g24_tr_s10_docked_bar.png`'de "Ana Sayfa" Fikirler ikonunun altında bitiyor ve iki sekmenin ortak etiketi gibi okunuyor.
  - TR'de etiket köşeleri hiçbir Android yapılandırmasında kapsülün içinde değil (`cornersInCapsule: false`; `bottomGapToCapsule` 6 / 3,5). R-02 Android'de aynen geçerli.
- **Önerilen düzeltme**
  - R-01 (A) ve R-02'deki dolgu düzeltmesi.
  - Ek olarak etiket `TextOverflow.ellipsis` + `textAlign: center` olsun.
  - Yuva 56 dp'nin altına düşerse gösterge ve etiket çizilmesin (`alwaysHide`); seçili durum ikon dolgusu (`selectedIcon`) ve ince bir alt çizgi ile gösterilsin. Glass tokenları değişmez.
- **SAHİBE SORU:** "Telefonda yalnız seçili etiket" ADR-0055 / STATE kararı (R-01 ile aynı soru). Etiketi kaldırmak bu cümleyi değiştirir.
- **Kilit test:** her `NavigationIndicator` genişliği ≥ 56 ya da gösterge yok; her görünür etiketin `getMaxIntrinsicWidth` değeri ≤ yuva genişliği; köşeleri `RRect(capsule, 32).deflate(2)` içinde.

### A-03 — Dokta balonun tanıtım kartı ekranın altına, sistem gezinme alanına çiziliyor (yeni) — **major**, efor S

- **Kanıt**
  - `features/quick_access/ui/quick_access_bubble.dart:296-299`: kart her zaman balonun **altına** konuyor (`top: anchor.dy + kBubbleDiameter + AwSpace.x2`).
  - OPH-362 balonun fabrika konumunu ekranın en altına (bar satırına) taşıdı, ama kartın konumu güncellenmedi.
  - Ölçü (§2.3): kartın 48 dp'sinin 20 dp'si ekranda (Android 360/412 g24), iPhone 393'te 30 dp'si. 3 düğmeli gezinmede tamamı sistem düğmelerinin bandında. `introBelowScreen: true` ve `introInSystemInset: true` beş yapılandırmanın hepsinde.
  - Kart kapanmak için dokunma bekliyor (`GestureDetector onTap: _dismiss`). O dokunma Android'de sistem gezinme hareketi alanına düşüyor.
  - Kart ayrıca 6 sn sonra kendiliğinden kapanıp `hinted = true` yazıyor (`:279`, `:290`). Yani tanıtım bir kez, okunamadan tüketiliyor.
- **Neden önemli:** Q5'e göre balon "never the only way", ama kart balonun ne olduğunu anlatan tek ilk kullanım ipucu. Bugün hiçbir telefonda okunmuyor. Sahibin "düşünülmemiş" şikâyetinin (C-02) küçük ama ölçülebilir bir örneği.
- **Önerilen düzeltme:** `anchor.dy > viewport.height / 2` ise kartı balonun **üstüne** yerleştirin (`bottom: viewport.height − anchor.dy + AwSpace.x2`). Dokta iken bu, kürenin ve + FAB'ın sağ üstüne denk geliyor; çakışmayı önlemek için `right: AwSpace.x3` korunur ve kart 220 dp sınırını tutar. Dikeyde FAB şeridiyle çakışırsa kart FAB'ın üstüne alınır (FAB üstü = `fab.top − 8`).
- **Kilit test:** `bubble_test.dart`'a bir vaka. Fabrika konumu, 360×800, alt inset {24, 48}: `QuickBubbleIntro` içindeki `Material` dikdörtgeni `Rect.fromLTRB(0, padding.top, w, h − padding.bottom)` içinde kalmalı ve `ai-fab`/+ FAB ile kesişmemeli.

### A-04 — Dokta balon + FAB'ın tam altında, aynı kenarda (Q4c ile çelişki) — **major**, efor M (A-01 ile birlikte)

- **Kanıt**
  - §2.2: balon ve + FAB ikisi de x 296–352 (360) / 348–404 (412) aralığında, dikeyde 20 dp arayla üst üste.
  - DESIGN §23 Q4c (`docs/DESIGN.md:992-996`): bubble "must live on the opposite side of the screen" (FAB'ın karşı tarafı).
  - Fabrika dok konumu sağ (`bubble_physics.dart:61-64`), + FAB da sağ alt (DESIGN §24 AI1). Sol alt köşe AI FAB'ın. Yani karşı kenar yok, kural fabrika konumunda bile tutulmuyor.
  - Ekranın sağ alt köşesinde FAB 56 + balon 56 + küre 64 üçgen oluşturuyor (`crop_a360g24_tr_s10_docked_bar.png`).
- **Önerilen düzeltme:** A-01'deki yön, yani balonun küreyle birleşmesi ya da FAB şeridine çıkması, bu çelişkiyi de kapatır. Ayrı bir çözüm olarak balon sol dokta olursa AI FAB'ın altına düşer (aynı sorun soldan).
- **SAHİBE SORU:** §23 Q4 (dok konumu) ile Q4c (karşı kenar) birbirini tutmuyor. Hangisi kalacak sahibin kararı. §24 AI1 "two corners, forever" FAB'ların yerini sabitliyor.
- **Kilit test:** fabrika konumunda balon dikdörtgeninin x aralığı + FAB'ınkiyle kesişmemeli. Bugün kırmızı, karar sonrası yeşil olmalı.

### A-05 — Dokta balon 72 dp'lik şerit ayırtıyor ama yarısı ekran dışında, %40 opak duruyor — **minor**, efor S

- **Kanıt**
  - `quick_access_bubble.dart:135`: `receded = !dragging && (scrolling || (_idle && badge == 0))`. Dokta olup olmadığına bakılmıyor.
  - Kırpıntılarda sağ kenarda yarım daire görünüyor; açık temada neredeyse görünmez (`crop_a412g24_en_s10_docked_bar.png`).
  - Q4'teki geri çekilme gerekçesi "içeriği örtmemek". Dok ise içerik örtmeyen ayrılmış bir şerit (`docs/DESIGN.md:951-954`). Gerekçe dokta geçerli değil, ama bar 72 dp'yi yine ödüyor.
- **Önerilen düzeltme:** `position.docked` iken geri çekilme ve sönükleşme olmasın (balon kendi şeridinde tam görünür dursun). Ya da A-01'in yönüyle şerit tamamen kalksın.
- **SAHİBE SORU:** DESIGN §23 Q4/Q4b ("After 3 s idle it half-recedes") bütün konumlar için yazılmış. Dok için istisna, bu kuralı değiştiriyor.
- **Kilit test:** fabrika konumunda 4 sn bekleyince balonun `AnimatedOpacity.opacity == 1` ve `AnimatedSlide.offset == Offset.zero` olmalı.

### A-06 — Android 360 dp'de app bar başlığı 1.0×'te bile "Ana Sa…" — **major**, efor S (R-05'in parçası)

- **Kanıt**
  - ham kanıt: app bar'da 5 `IconButton` (`appBarButtons: 5` her yapılandırmada), başlık "Ana Sa…".
  - 2.0×'te "Ana …" (ham kanıt).
  - 412 dp'de başlık sığıyor (ham kanıt).
  - iOS'ta bu kesilme yalnız SE 2.0×'te görülmüştü (ux-shell-mobile R-05). Android'de app bar başlığı sola yaslı; 5 ikon 360 dp'de 240 dp yer kaplıyor.
- **Önerilen düzeltme:** R-05: telefonda app bar en fazla 3 ikon (Görünüm, Takvim, Ayarlar). Yerel "Ara" telefonda kalkar.
- **Kilit test:** R-05'in `home_app_bar_test.dart`'ına 360 genişlik ve Android platformu eklensin; başlık `didExceedMaxLines == false`.

### A-07 — Snackbar konumu doğru; ancak 2.0×'te 110 dp ve üç katmanlı yığın — **minor**, efor S

- **Kanıt:** §2.3. Snackbar her yapılandırmada FAB satırının 16 dp üstünde, kapsülün 88 dp üstünde. Balon, küre ve kapsülle çakışmıyor. `_ShellBody` (`home_shell.dart:733-751`) beklendiği gibi çalışıyor.
  - Sonuç: ekranın alt 200 dp'sinde (360 g24: 576–776) üç yatay katman var: snackbar, FAB satırı, bar satırı.
  - 2.0×'te snackbar gövdesi 110 dp; ekranın %14'ü.
- **Önerilen düzeltme:** Davranış hatası değil; bu turda değişiklik önerilmiyor. R-07 (A) uygulanırsa (FAB'lar kaydırınca saklanır) snackbar FAB yokken bara 16 dp yaklaşır; bu durum ayrıca ölçülmeli.
- **Kilit test:** `shell_snackbar_test.dart`: kayan snackbar gövdesi kapsül, küre, balon ve FAB dikdörtgenleriyle kesişmemeli (360 g24/g48, 1.0/2.0).

## 4. R-01…R-14'ün Android'de durumu

| Bulgu | Android'de | Kanıt (bu probe) | Not |
| --- | --- | --- | --- |
| R-01 karma etiket, seçili ikon 10 pt yukarı | **Geçerli, daha geniş** | Her Android yapılandırmasında `onlyShowSelected`, `iconTopSpread` 10 / 12,5 | 412 dp'de balonsuz bile (58,4 < 64). M3 Android kılavuzu da bütün hedeflerde etiket önerir; Android kullanıcısı için tanıdık olmayan mod. SAHİBE SORU (ADR-0055) aynen kalır |
| R-02 etiket kapsül eğrisinde | **Geçerli, daha ağır** | `cornersInCapsule: false` (TR hepsi), alt boşluk 6 / 3,5; ayrıca komşu sekmeye 23–45 dp taşma (A-02) | |
| R-03 bar altında içerik şeridi | **Geçerli, şerit 24 dp (hareket) / 48 dp (3 düğme)** | `barGapToScreenBottom` 24 / 48 | targetSdk 36 (`FlutterExtension.kt:34`), Android 15+'ta edge-to-edge zorunlu. Belgeye göre 3 düğmeli gezinmede sistem yarı saydam scrim çizer, hareket çubuğunda çizmez: hareket gezinmesinde şerit örtüsüz kalır. Cihazda doğrulanmadı |
| R-04 dok balonu G4 ihlali | **Geçerli ve ölçüldü** | A-01; iOS hesapları da ölçüyle doğrulandı | Android eşiği 48 dp olduğu için 412 dp de kırık |
| R-05 iki "Ara", 5–6 ikon | **Geçerli, daha ağır** | A-06 | |
| R-06 yüzen ızgara | **Kısmen geçerli** | Balonsuz: küre/FAB 8 dp kaymış (316 vs 324). Dokta: FAB balonla aynı sütunda, küre sola kayıyor (A-04) | Kenar boşlukları aynı: AI FAB 8, kapsül 12 |
| R-07 mikrofon FAB sol sütunu kapatıyor | **Geçerli** | AI FAB 8–64 (bütün Android yapılandırmaları); kırpıntılarda görev kartının sol sütununun üstünde | SAHİBE SORU (§24 AI1) aynen kalır |
| R-08 serbest balon | **Kod platformdan bağımsız, Android'de ölçülmedi** | Bu probe yalnız fabrika (dok) konumunu ölçtü | Q4c çelişkisi fabrika konumunda da var (A-04) |
| R-09 görev satırı anatomisi | **Geçerli** | 360 dp'de uzun demo başlığı 4+ satır (`a360g24_tr_s10_docked.png`) | |
| R-10 tipografi | **İzleme kısmı geçersiz, meta satırı kısmı geçerli** | M3 `englishLike` izlemesi Roboto için tasarlandı; Android'de doğru. Probe'un yazı tipi de Roboto | Öneri yalnız Apple platformları için kalmalı (R-10 zaten öyle diyor) |
| R-11 hızlı ekleme 4 kontrol | **Geçerli** | `top_*.png`: önek "+", "?", "↑" boş alanda | ✨ AI sağlayıcısı demo'da yapılandırılmadığı için görünmüyor |
| R-12 720–799 kırılımı | **Kodla geçerli, ölçülmedi** | — | 600–799 dp Android tabletler ve açık katlanabilirler bu aralığa düşer; ayrı bir probe gerekir |
| R-13 harness kör noktası | **Doğrulandı ve kapanabilir** | Bu probe `QuickAccessBubbleHost`'u, platform override'ını ve alt inset'leri sorunsuz monte etti (37/37 geçti) | Harness'a `platform` ve `viewPadding` parametreleri eklenmeli |
| R-14 küçük bulgular | **Geçerli** | İki klasör ikonu (`crop_*_bar.png`, 3. ve 5. ikon); 2.0×'te "Cu/m", "Hızlıca gö…" (`a360g24_tr_s20_docked.png`) | |

## 5. ux-shell-mobile.md §6 bilinmeyenlerinin durumu

| Bilinmeyen | Durum | Sonuç |
| --- | --- | --- |
| Dokta balonla 39–50 pt yuvada 64 pt M3 göstergesi kırpılıyor mu | **Kapandı** | Kırpılmıyor, yuva genişliğine daralıyor (36/30/46,4 × 32). Stadyum kapsülün içinde kalıyor. Etiket taşıyor (A-02) |
| Sahip cihazının modeli ve metin boyutu | **Açık** (bu probe kapsamında değil) | — |
| SF Pro izleme farkı | **Açık** (Android'de geçersiz; iOS cihazında ölçülmeli) | — |
| Snackbar konumu | **Kapandı** | FAB satırının 16 dp, kapsülün 88 dp üstünde; çakışma yok (A-07) |
| Balon tanıtım kartı dikdörtgeni | **Kapandı** | Dokta iken ekranın altında, sistem inset'inde (A-03) |
| Probe'da balon yok (R-13 sınırı) | **Kapandı** | Balon monte edildi; R-04 hesapları ölçüyle birebir doğrulandı |
| Uzantının 6 bölümlü barı çizilmedi | **Kapandı** | 360: 30 dp (dok) / 40 dp (dok yok); 375: 32,5 / 42,5 |

Yeni bilinmeyenler:

- Gerçek Android cihazda sistem gezinme scrim'i, OEM yazı tipleri ve OEM ekran boyutu ayarı (ör. Samsung "ekran yakınlaştırma", dp genişliğini 360'ın altına indirebilir). **NOT RUN.** Önerilen kontrol: 360 dp sınıfı bir emülatörde (Pixel 4a/5 profili) hareket ve 3 düğmeli gezinme ile Ana sayfa ekran görüntüsü.
- Balon serbest konumdayken Android ölçüsü alınmadı (R-08).
- AI kapalı ve + FAB'sız bölümlerde (Fikirler, Dosyalar) snackbar konumu ölçülmedi.

## 6. Önerilen sıra

1. **A-03** (tanıtım kartı, S): karar gerektirmez, hemen düzeltilebilir.
2. **A-02'nin karar gerektirmeyen kısmı** (ellipsis + ortalama, S) ve R-02 dolgusu.
3. **A-06 / R-05** (app bar ikonları, S): R-05'in ADR'siyle.
4. **SAHİBE SORU paketi.** Tek soru setinde sunulmalı, demo tohumlu 360 dp Android ve 393 pt iPhone çekimleriyle:
   - A-01 + A-04 + A-05: balonun dok konumu, §23 Q4/Q4b/Q4c;
   - R-01 / A-02: etiket modu, ADR-0055;
   - R-07: §24 AI1.
5. R-13: bu probe testinin `_measure` gövdesi ve yapılandırma matrisi `test/features/shell/` altına commit edilen kilitlere dönüştürülmeli.
