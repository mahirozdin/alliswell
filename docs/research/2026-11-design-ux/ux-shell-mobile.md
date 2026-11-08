> **Depodaki kopya (2026-11-07, E35 kaydı):** uzantıya özgü tasarım ayrıntısı çıkarıldı (uzantı bulguları uzantı deposunda); turun iç çalışma dosyalarına ve ham kanıta verilen yollar düz metne çevrildi ("ham kanıt" = turun çalışma alanında kalan dosya; depoda yok). Bulgu kimlikleri değişmedi. Özet: [README.md](README.md).

> Son güncelleme: 2026-11-07 — CEO tasarım/UX turu
> Kaynak: sahip brief'i (O-02, C-01…C-07), sahibin iPhone ekran görüntüsü (yalnız ölçü için; içindeki metin bu belgeye alınmadı), `apps/app/lib/src/**` kodu, `docs/DESIGN.md`, `docs/adr/0055-global-search-palette.md`, `docs/STATE.md` "Sahip kararları", Flutter 3.47.7 SDK kaynağı (`<flutter-sdk>/packages/flutter/lib/src/material/navigation_bar.dart`, `typography.dart`) ve bu tur için yazılan probe testi (gerçek kabuk, demo tohumu) → ham kanıt

# Mobil kabuk: alt bar, yüzen öğeler ve Ana sayfa satırı — kök neden analizi

## 0. Yöntem ve kanıt türleri

- **Kod**: `dosya:satır` (yollar `apps/app/lib/src/` altına göredir, aksi yazılmadıkça).
- **Probe**: gerçek router + tema + kabuk, demo tohumu (AI açık, uzun demo başlıkları, demo Hızlı Erişim kısayolu), 15 yapılandırma (iPhone Pro Max 430×932, iPhone 15 393×852, SE 375×667, metin ölçeği 1.0/1.3/2.0, TR/EN, iPad mini 744, iPad 820/1180, masaüstü 1280/1440). Ölçüler mantıksal pt.
  - Test: ham kanıt
  - Ölçü dökümü: ham kanıt
  - Görseller: ham kanıt (ör. `promax_tr_dark_undocked.png`, `se_tr_dark_scale20.png`, `ipadmini_portrait_tr_light.png`, `desktop_tr_dark.png`); bar kırpıntıları `exp/crop_*_bar.png`.
  - Sınır: screenshot harness'ı `QuickAccessBubbleHost`'u monte etmiyor (bkz. R-13), bu yüzden **Hızlı Erişim balonu probe'da çizilmedi**; balonla ilgili sayılar koddan hesaplandı ve "hesap" diye işaretlendi.
- **Sahip görüntüsü**: 923×2000 px; 430 pt genişlikli (Pro Max sınıfı) cihaz varsayımıyla 1 pt ≈ 2,147 px. Ölçüler ±1 pt. Probe aynı düzeni birebir üretti (capsule 12–346, orb 354–418, FAB'lar 762–818) — varsayım tutarlı.

## 1. Özet: neden "kaymış ve düşünülmemiş" görünüyor

1. Alt bar **karma bir durumda** çalışıyor: yalnız seçili sekmenin etiketi var (`onlyShowSelected`) ve Material 3 bu modda seçili ikonu etiket yüksekliğinin yarısı kadar **yukarı kaydırıyor**. Bu yüzden seçili ikon diğerlerinden 10 pt yukarıda duruyor ve etiket, kırpılan hap köşesine 3,5–6 pt kalıyor. Bunun tetikleyicisi, ADR-0055'te sekme genişliğinden pay alan arama küresi.
2. Bar ekranın dibinde değil: `extendBody` + `SafeArea` yüzünden bar ile ev göstergesi arasında **34 pt'lik bir şerit** kalıyor ve içerik bu şeritten örtüsüz akıyor. "Yarın · 4" gibi başlıklar etiketin hemen altında okunuyor (C-01 + C-07).
3. Yüzen öğeler **dört farklı kenar boşluğu** (8 / 12 / 16 pt ve kenara gömülü balon) ve iki farklı çapla (56 / 64) konumlanıyor. Ortak bir ızgara yok. Ekranın iki alt köşesinde 2+2 daire üst üste duruyor.
4. Tipografi M3 "englishLike" izlemesini (bodyLarge +0,5, labelMedium +0,5) SF Pro'ya olduğu gibi uyguluyor. Görev başlığında satır sınırı yok. Satırın leading/trailing öğeleri ListTile varsayılanıyla dikeyde ortalanıyor.
5. Bu hatalar hiçbir testte görünmüyor: tasarım goldens'ı güvenli alan olmadan, AI kapalı, balonsuz ve 1.0 ölçekte çekiliyor ve commit edilmiyor. Uygulama testlerinde metin ölçeği testi yok (`grep textScaleFactorTestValue apps/app/test` → 0).

## 2. Bulgular (kök neden → düzeltme → kilit test)

Şiddet: blocker / major / minor. Efor: S (≤½ gün) / M (1–2 gün) / L (3+ gün).

### R-01 — Seçili sekme ikonu 10 pt yukarı kayıyor, ikonlar tek hizada değil (C-01) — **blocker**, efor M

- **Kanıt**
  - `screens/home_shell.dart:454-460`: `labelBehavior` genişliğe göre seçiliyor. `(bar.maxWidth − 24) / sekme sayısı < kAwBarLabelSlot (64, :711)` olunca `onlyShowSelected` devreye giriyor.
  - Probe: sekme yuvası Pro Max'te 62 pt, iPhone 15'te 54,6 pt, SE'de 51 pt. Yani **her iPhone'da** yalnız seçili etiket çiziliyor.
  - Flutter `navigation_bar.dart` `_NavigationDestinationLayoutDelegate.performLayout`: seçiliyken ikon `halfHeight(labelSize)` kadar yukarı alınıyor, seçili olmayanlar ortada kalıyor.
  - Probe `promax_tr_dark_*`: seçili ikonun üstü y=844, diğerleri y=854 (**10 pt fark**). 1.3× ölçekte 841,5 / 854 (12,5 pt).
  - Sahip görüntüsü: seçili hap merkezi ≈ 855 pt, diğer ikonlar ≈ 865 pt.
- **Neden kırık:** Aynı satırdaki beş ikonun dört taban çizgisi aynı, biri farklı. Göz bunu "kaymış" diye okuyor. Etiket yalnız bir sekmede olduğu için grup sola yaslı görünüyor. Gerçekte ikonlar eşit aralıklı (62 pt adım), sorun dikey.
- **Önerilen düzeltme (Glass korunur)**
  - Karma modu kaldırın. Ya **hepsi etiketli** ya **hiçbiri etiketsiz** olsun.
  - (A, önerilen) Bütün etiketler `labelSmall` 11 pt, `letterSpacing: 0`, seçiliyken w600, gösterge 56×32. TR'nin en uzun etiketi "Ana Sayfa" (`assets/i18n/tr.json:97`) bu stille yaklaşık 50 pt; ≥52 pt yuvaya sığar (SE'de dok yokken 51 pt, sınırda).
  - Yuva 52 pt'nin altına inerse `alwaysHide` kullanın: yalnız ikon + tooltip + Semantics, seçili hap. `onlyShowSelected` hiçbir genişlikte kullanılmasın.
  - DESIGN §4 hâlâ "labels always visible" diyor (`docs/DESIGN.md` §4 "Navigation floats" maddesi). ADR-0055 ise karma modu getirdi; belge bayat, aynı işte düzeltilmeli.
- **SAHİBE SORU:** STATE "Sahip kararları" (ADR-0055) açıkça "telefonda çoğunlukla yalnız seçili sekmenin etiketi yazılır" diyor. `onlyShowSelected`'ı kaldırmak bu cümleyi değiştiriyor. `docs/DEVICE-CHECKS.md:26` zaten "Sahip incelemesi: tercih uygulama çubuğunda altıncı ikonsa ADR-0055'i değiştir" diye açık bir soru taşıyor. Üç yön:
  - (1) Hepsi etiketli, 11 pt, küre aynı satırda kalır.
  - (2) Hepsi etiketsiz, iOS 26 benzeri ikon barı.
  - (3) Küre bardan çıkar, arama Ana sayfa uygulama çubuğundaki mevcut "Ara"nın yerini alır (R-05 ile birlikte; app bar ikon sayısı değişmez).
- **Kilit test:** `test/features/shell/bar_alignment_test.dart` (yeni widget testi).
  - Matris: genişlik {375, 393, 430} × ölçek {1.0, 1.3, 2.0} × dil {tr, en} × bölüm {5, 6 (uzantı)} × balon {yok, dokta}.
  - (a) Bütün hedef ikonlarının `top` değeri eşit olmalı (±0,5).
  - (b) Etiket ya her hedefte ya hiçbirinde bulunmalı.
  - (c) Testteki `fab_inset_test.dart:58-61`'deki `onlyShowSelected` beklentisi yeni kurala çevrilmeli.

### R-02 — Etiket hap köşesine değiyor, eğriden taşıyor (C-01) — **major**, efor S

- **Kanıt**
  - `theme/theme.dart:325`: bar yüksekliği `64`; M3 varsayılanı 80 (`navigation_bar.dart` `_NavigationBarDefaultsM3` `height: 80.0`). Etiket bloğu 32 gösterge + 4 + 16 = 52 pt, alta 6 pt kalıyor.
  - Probe: etiket alt kenarı 892, kapsül alt kenarı 898. 1.3×'te 894,5, yani 3,5 pt. Flutter etiketi 1.3'te kısıtlıyor (`navigation_bar.dart:31` `_kMaxLabelTextScaleFactor = 1.3`), bu yüzden 2.0× de 1.3 gibi davranıyor.
  - Kapsül `ClipRRect(radius 32)` ile kırpılıyor (`widgets/glass.dart:130`).
  - Hesap: 32 pt yarıçaplı eğri alttan 6 pt yukarıda kenardan ~13,3 pt içeride, 4 pt yukarıda ~16,5 pt içeride. Etiketin sol kenarı x=25,5 (1×) ve x=24 (1.3×); kapsül sol kenarı x=12. Yani "A"nın sol altı eğrinin üstüne ya da dışına düşüyor ve kırpılıyor.
  - `screens/home_shell.dart:476-479`: `softWrap: false, overflow: TextOverflow.visible`. 1.3×'te "Ana Sayfa" 62 pt'lik yuvayı tam dolduruyor.
- **Neden kırık:** Etiket hap içinde değil, hapın kırpma eğrisinin üstünde duruyor. Kötü hizalı ilk sekmede bu "yazı kapsülden taşmış" gibi okunuyor.
- **Önerilen düzeltme**
  - Etiketli seçenekte etiket bloğunu dikeyde ortalayın: gösterge 32 + 2 + etiket 14 = 48 pt, 64 pt'lik barda üst ve alt 8 pt.
  - Kapsülün iç yatay dolgusunu `AwSpace.x3`'ten yarıçapa göre hesaplanan değere çıkarın (ör. `AwRadius.pill/2 = 16`).
  - `overflow: TextOverflow.ellipsis` kullanın. Glass tokenları değişmez.
- **Kilit test:** R-01 dosyasında (d): her görünür etiketin dört köşesi `RRect.fromRectAndRadius(capsule, 32).deflate(2)` içinde kalmalı (`contains`). Mevcut `fab_inset_test.dart:50-70` yalnız `NavigationBar` kutusunun içeride olduğunu ölçüyor, eğriyi ölçmüyor.

### R-03 — Bar ile ev göstergesi arasında içerik örtüsüz akıyor (C-07, C-01'in "Yarın · 4" çakışması) — **major**, efor S–M

- **Kanıt**
  - `screens/home_shell.dart:414-428`: `extendBody: true` ve `SafeArea(top: false, minimum: bottom 12)`. iPhone'da `viewPadding.bottom = 34` olduğundan kapsül ekran altından 34 pt yukarıda bitiyor.
  - Probe Pro Max: bar alt kenarı 898, ekran 932. Aradaki **34 pt şeridi** liste satırları dolduruyor (`promax_tr_dark_undocked.png`, alt kenar). Sahip görüntüsünde aynı şeritte bir bölüm başlığı, seçili etiketin hemen altında duruyor.
  - DESIGN §4 "content scrolls and peeks beneath it" diyor ama kenar efekti tanımlamıyor.
- **Neden kırık:** Cam yalnız kapsülün kendisi. Kapsül yüzdüğü için altında ve yanlarında içerik tam kontrastla kalıyor. Bar bir katman gibi değil, içeriğin üstüne yapıştırılmış gibi okunuyor.
- **Önerilen düzeltme**
  - Kabuğa, `bottomNavigationBar`'ın arkasında, ekranın altından barın üstüne +24 pt'ye kadar uzanan `IgnorePointer` bir **kenar solması** ekleyin: sayfa yıkamasının (`AwTokens.veil`/aurora alt rengi) `transparent → opak` doğrusal geçişi.
  - Bu cam değil, düz bir boya. G1 ihlal edilmez ve metin bu bölgede kalmaz (liste sonu zaten `awListPadding` ile temizleniyor).
  - iOS 26 "scroll edge effect" ile aynı fikir; kopya değil.
- **Kilit test**
  - Widget testi `shell_scroll_edge_test.dart`: `tester.view.padding = FakeViewPadding(bottom: 34)` ile `Key('shell-bottom-scrim')` dikdörtgeni `[bar.top − 24, ekran altı]` aralığını kapsamalı.
  - Golden harness'a güvenli alan eklenmeli (R-13).

### R-04 — Docktaki Hızlı Erişim balonu sekmeleri 39–50 pt'ye sıkıştırıyor, G4 ihlali — **major**, efor M

- **Kanıt (hesap, balon probe'da çizilmedi)**
  - `features/quick_access/ui/bubble_physics.dart:61-64`: fabrika konumu dok, sağ kenar.
  - Şerit genişliği `bubbleDockLane` (:174) = 8 + 56 + 8 = 72. `screens/home_shell.dart:715-722` `_barPadding` sağ boşluğu 72 yapıyor. Aynı satıra 8 + 64 küre ekleniyor (:499-500).
  - Kapsül genişliği: 430 → 274, 393 → 237, 375 → 219. Sekme yuvası (−24, 5 bölüm): **50 / 42,6 / 39 pt**. Uzantının 6. bölümüyle SE'de 32,5 pt.
  - Dok olmadan da uzantı + SE: (375 − 12 − 12 − 8 − 64 − 24) / 6 = **42,5 pt**.
  - G4 (`docs/DESIGN.md` §2): dokunma hedefi ≥ 44 pt. M3 göstergesi 64 pt; bu yuvalara sığmıyor (kırpılıyor mu taşıyor mu: **bilinmiyor**, ölçülmedi).
  - Ayrıca `bubble_physics.dart:34-39` yorumu barı "80 px" diye anlatıyor; tema 64. Sabitin yorumu bayat.
- **Neden kırık:** Tek satıra kapsül + küre + balon olmak üzere üç cam nesne sığdırılmaya çalışılıyor ve bedeli sekme genişliği ödüyor.
- **Önerilen düzeltme**
  - Balon dokta iken bar satırına değil, **kürenin üstüne, FAB şeridine** otursun; ya da dok kürenin içine birleşsin (uzun basma → Hızlı Erişim).
  - Bar satırında en fazla iki nesne kalsın (kapsül + küre).
  - Sekme yuvasının alt sınırını 44 pt'ye bağlayan bir `assert`/test ekleyin.
- **SAHİBE SORU:** Balonun bar satırında dok olması OPH-362 / DESIGN §23 Q4 kararı. Q4'ün kendisi de sahibin "iPhone'un beyaz noktası gibi" isteğinden doğdu. Konumunu değiştirmek bu kararı açıyor.
- **Kilit test:** R-01 matrisinde (e): "her hedefin genişliği ≥ 44". Harness'ın balonu monte etmesi şart (R-13).

### R-05 — Uygulama çubuğunda iki farklı anlamlı "Ara", telefonda 5–6 ikon (C-03) — **major**, efor S

- **Kanıt**
  - `features/home/home_screen.dart:232-237`: `AwSearchAction`, yani Ana sayfanın **yerel** araması (OPH-167, DESIGN §12).
  - `search/ui/global_search_entry.dart:224-251`: alt bardaki küre, aynı `Icons.search` ile **her yerde arama**.
  - Probe: telefonda app bar düğmeleri "Ara, Pano, Sırala, Takvimi gizle, Ayarlar" (5 düğme, x=186…426). Hızlı Erişim balonu kapalıyken `QuickAccessAppBarButton` eklenip 6'ya çıkıyor (`home_screen.dart:309`, DESIGN §23 Q5).
  - Masaüstünde de aynı çift var: raydaki "Her yerde ara" ile app bar'daki "Ara" (`desktop_tr_dark.png`).
  - SE 2.0×'te başlık "Ana S…" diye kesiliyor (`se_tr_dark_scale20.png`).
- **Brief'teki iddianın düzeltmesi:** STATE/ADR-0055 yalnız **her yerde aramanın** app bar ikonunu yasaklıyor. Mevcut ikon yerel arama, yani kararı harfiyen ihlal etmiyor. Ama ADR-0055'in reddettiği alternatifin gerekçesi ("repeats per-screen search's icon with a different meaning", `docs/adr/0055-global-search-palette.md` Alternatives) bugün tam olarak yaşanıyor: aynı glif iki farklı kapsamla iki yerde.
- **Önerilen düzeltme**
  - Telefonda Ana sayfa app bar'ından yerel "Ara"yı kaldırın. Palet görevleri zaten buluyor (ADR-0055 §1); etiket sonucu Ana sayfayı süzüyor.
  - "Pano" ve "Sırala"yı tek bir "Görünüm" menüsünde birleştirin (liste/pano + sıralama).
  - Telefonda app bar en fazla 3 ikon olsun: Görünüm, Takvim, Ayarlar.
  - DESIGN §40 "Per-screen search (§12) stays as it is" cümlesi değişeceği için bu iş bir ADR ister. Sahip kararı değil, ama ADR-0055'i tamamlar.
- **Kilit test:** `home_app_bar_test.dart`. 375/393/430 × 1.0/1.3/2.0 matrisinde:
  - app bar'daki `IconButton` sayısı ≤ 3;
  - başlık `Text`'inin `didExceedMaxLines` değeri false;
  - aynı ekranda `Icons.search` en fazla bir kez görünmeli.

### R-06 — Yüzen öğelerin ızgarası yok: 8/12/16 pt kenar, 56/64 çap, kaymış sütun (C-02) — **major**, efor S

- **Kanıt**
  - `screens/home_shell.dart:119-129`: AI açıkken iki FAB, `centerFloat` + `Padding(horizontal: AwSpace.x2)` ile tam genişlikte bir `Row` içinde. Kenar boşluğu **8 pt**.
  - AI kapalıyken `endFloat` (:418-420): kenar boşluğu **16 pt**. Probe: + FAB sağ kenarı AI açıkken 422, kapalıyken 414. Yani AI açılıp kapanınca **+ düğmesi 8 pt yer değiştiriyor**.
  - Kapsül ve küre kenar boşluğu **12 pt** (`_barPadding`, :716).
  - Küre 64 pt, FAB 56 pt. Pro Max'te küre merkezi x=386, + FAB merkezi x=394: üst üste iki daire **8 pt kaymış**. Sahip görüntüsünde de aynı (küre 355–417, FAB 366–421).
  - FAB ile bar arası 16 pt (818 → 834).
- **Neden kırık:** Sağ alt köşede biri büyük biri küçük, merkezleri hizasız iki daire üst üste duruyor. Bir tasarım ilkesinden çok bir kaza gibi okunuyor.
- **Önerilen düzeltme**
  - Tek bir "yüzen kenar" tokenı tanımlayın: `kAwFloatGutter = 16`.
  - + FAB'ı kürenin merkez sütununa oturtun: kenar 16 + 28 = 44 → merkez 386 (kürenin merkezi). AI FAB'ı aynı kenar boşluğuyla sola yerleştirin.
  - Özel bir `FloatingActionButtonLocation` (`AwFabLocation`) yazın; `centerFloat` + `Row` hilesini kaldırın.
  - İsteğe bağlı: küreyi 56 pt'ye indirin (bar 64; "kapsülle aynı satır" kuralı merkez hizasıyla korunur). Bu DESIGN §40 P1'deki "64 px" ölçüsünü değiştirir; ADR-0055'in kararı değil, ölçüsü.
- **Kilit test:** `floating_grid_test.dart`. AI açık ve kapalı durumda + FAB'ın sağ kenarı aynı olmalı; + FAB merkezi x = küre merkezi x (±0,5); bütün yüzen öğelerin dış kenarı `kAwFloatGutter` olmalı.

### R-07 — Mikrofon FAB'ı sol sütunu kapatıyor: bölüm başlıkları ve onay daireleri (C-02) — **major**, efor S (A) / M (B)

- **Kanıt**
  - DESIGN §24 AI1 "Two FABs, two corners, forever".
  - `features/ai/ui/ai_fab.dart:118-125`: 56 pt FAB.
  - Probe: x 8–64, y 762–818. Görev onay daireleri x 28–76 (probe `checkboxes`), bölüm başlıkları x=20'den başlıyor. Kaydırırken her başlık ve onay dairesi bu bölgeden geçiyor.
  - Sahip görüntüsünde FAB "Bugün · 1" başlığını örtüyor. SE 2.0×'te iki FAB takvimin son satırını kapatıyor (`se_tr_dark_scale20.png`).
  - `ai_fab.dart:133`: AI sunucuda açıksa, sağlayıcı yapılandırılmamış olsa bile FAB görünüyor.
- **Neden kırık:** Sol alt köşe listenin tarama sütunu (onay dairesi + başlık). Sağ alt köşe ise yalnız trailing ikonları kapatıyor. Asimetri sol FAB'ı daha pahalı yapıyor.
- **Önerilen düzeltme**
  - (A, AI1'e uyar) İki FAB da aşağı kaydırınca saklansın, yukarı kaydırınca dönsün (`AwMotion.base`). AI FAB 40 pt'lik "small" FAB olsun (hedef ≥44 için 48 pt dokunma kutusu).
  - (B) Mikrofon hızlı ekleme alanına ya da + FAB'ın uzun basmasına taşınsın.
- **SAHİBE SORU:** B, DESIGN §24 AI1'i ("neither moves") değiştirir. AI1, sahibin "parmağımı kaldırınca açık kalsın" kuralıyla birlikte doğdu. A bile "neither moves" ifadesine dokunuyor: saklanmak hareket sayılır mı? Bu bir zevk ve karar sorusu.
- **Kilit test:** `fab_scroll_test.dart`. Liste 200 pt aşağı kaydırılınca FAB'ların `Offstage`/`opacity == 0` olması, yukarı kaydırılınca geri gelmesi. Golden: AI açık phone_home (R-13).

### R-08 — Hızlı Erişim balonu serbest konumda içeriği kapatıyor, AI FAB'la aynı kenarı paylaşabiliyor (C-02) — **minor**, efor M

- **Kanıt**
  - Sahip görüntüsü: balon sol kenarda, y ≈ 151–207 pt aralığında, yarısı ekran dışında ve soluk (DESIGN §23 Q4, Q4a, Q4b: 3 sn sonra %50 içeri çekilir, %40 opaklık). Hızlı ekleme alanının sol kenarının üstünde duruyor.
  - `quick_access_bubble_host.dart:142-146`: serbest konumda yalnız liste **sonu** temizleniyor (`AwBubbleClearance`). Ekranın üstündeki içerik kapalı kalıyor; kodun kendi yorumu da bunu söylüyor (`widgets/fab_clearance.dart:104-118`).
  - Q4c "bubble must live on the opposite side" diyor, ama sol kenar AI FAB'ın köşesi.
- **Önerilen düzeltme**
  - Serbest dikey konum yerine 2–3 mıknatıs noktası: dok, kürenin üstü, sağ orta.
  - AI FAB'ın kenarına bırakılınca karşı kenara yapışsın.
  - Bu §23 Q4'ü değiştirir → **SAHİBE SORU** (R-04 ile aynı soru).
- **Kilit test:** `bubble_test.dart`'a bir vaka: sol kenara, AI açıkken bırakılan balon sağa yapışmalı; dinlenme konumu `home-quick-add` dikdörtgeniyle kesişmemeli.

### R-09 — Görev satırı: onay dairesi ve sağ ikonlar ortada, satır sınırı yok, sağ küme %20–25 (C-04, C-05) — **major**, efor M

- **Kanıt**
  - `features/tasks/ui/task_tile.dart:177-195`: `ListTile`, `titleAlignment` verilmemiş. M3 varsayılanı `threeLine` ve `isThreeLine` false olduğu için leading/trailing ortalanıyor. Probe: kart 599–765 (merkez 682), onay dairesi 658–706 (merkez 682), yani tam ortada.
  - `task_tile.dart:186`: başlık `Text`'inde `maxLines` yok. Probe:
    - uzun demo başlığı Pro Max 1×'te 166 pt;
    - 2.0×'te **588 pt**;
    - SE 2.0×'te **780 pt**, ekrandan (667) uzun tek bir satır.
  - Sağ küme `task_tile.dart:382-445`: bayrak 18 + 8 + acil zil 18 + 8 + durum ikonu 18, artı ListTile boşluğu.
    - `features/tasks/ui/task_visuals.dart:20`: varsayılan `open` durumu için **her açık satıra kum saati** çiziliyor; bilgi değeri sıfır.
    - Proje rozeti eklenince iPad mini (744, iki sütunlu Ana sayfa) başlığı neredeyse kelime başına bir satıra kırıyor (`ipadmini_portrait_tr_light.png`, üçüncü kart).
  - Sol tarafta 48 pt padded onay kutusu (`theme.dart:145` `MaterialTapTargetSize.padded`), 12 contentPadding ve 16 başlık boşluğu var. Başlık kartın 76 pt içinden başlıyor (sahip görüntüsünde de ≈77 pt).
- **Önerilen düzeltme (anatomi korunur)**
  - `titleAlignment: ListTileTitleAlignment.top`, böylece onay dairesi ilk satırla hizalanır.
  - Başlıkta `maxLines: 2` ve `ellipsis` (1.3×'ten itibaren 3). Başlık yalnız URL'den oluşuyorsa satırda `host/…/son-parça` gösterilsin; tam hali detayda kalsın.
  - Durum ikonu yalnız varsayılan dışı durumlarda çizilsin (open → yok).
  - Öncelik bayrağı meta satırına geçsin (G5: renk + ikon kalır); sağda en fazla bir ikon (acil) + rozet kalsın.
  - Onay dairesinin görsel boyutu 22 pt; dokunma kutusu 44, sola taşan negatif boşlukla. Başlık girintisi 76 → ~56 pt.
- **Kilit test**
  - `task_tile_anatomy_test.dart`: üç satırlı başlıkta checkbox `top` ile başlık ilk satır `top` farkı ≤ 4 pt; trailing kümenin genişliği ≤ kart genişliğinin %15'i (375 pt'de); 2.0×'te kart yüksekliği ≤ 240 pt.
  - Golden: `phone_home_long_titles_{light,dark}` (uzun URL ve uzun TR başlık, demo tohumu).

### R-10 — Gövde metninde geniş harf aralığı, meta satırı kırmızı ve kalın (C-04) — **major**, efor S

- **Kanıt**
  - `theme/theme.dart:103-130`: `Typography.material2021(...).englishLike` alınıyor; yalnız headline/title izlemesi daraltılıyor. M3 değerleri (Flutter `typography.dart:2104-2111`): `bodyLarge +0.5`, `bodyMedium +0.25`, `bodySmall +0.4`, `labelMedium +0.5`, `titleMedium +0.15`. Bunlar Roboto için ayarlanmış; SF Pro kendi optik izlemesini zaten taşıyor.
  - Ek olarak bölüm başlığında elle `letterSpacing: 0.4` var (`features/home/home_screen.dart:705`).
  - DESIGN §3.3 "Apple-like tightening" diyor ama gövde rolleri için değer vermiyor.
  - Meta satırı `task_tile.dart:318-322`: gecikmişte `bodyMedium` w600 `error`. Bölüm başlığı zaten kırmızı "Geciken · N" (`home_screen.dart:700`); her satırda aynı sinyal ikinci kez, kalın olarak tekrarlanıyor.
- **Önerilen düzeltme**
  - Apple platformlarında (ve SF ile render edilen web/macOS'ta) body/label rollerinin `letterSpacing` değerini 0 yapın. Headline'lardaki negatif izleme kalsın.
  - Meta satırı: `bodySmall` (13 pt eşdeğeri), `error` rengi + ⏰ ikonu + "Gecikti" kelimesi (G5 korunur), w500.
  - DESIGN §4 "Overdue … w600" maddesi güncellenmeli (bu bir DESIGN kuralı, sahip kararı değil).
  - Tipografi yönleri sahibin zevkine bırakılmalı (bkz. ayrı tipografi araştırması varsa).
- **Kilit test:** `theme_typography_test.dart`. `buildAwTheme(...)` iOS/macOS platformunda `bodyLarge/bodyMedium/labelMedium.letterSpacing == 0`. Gecikmiş meta stili `fontWeight <= w500` ve yanında bir ikon olmalı.

### R-11 — Hızlı ekleme alanında 4 kontrol, ikisi boşken işlevsiz (C-06) — **minor**, efor S

- **Kanıt**
  - `features/tasks/ui/quick_add_bar.dart:234`: `prefixIcon: Icon(Icons.add)` yalnız süs, ama + FAB'la aynı glif ve düğme gibi görünüyor.
  - `:250-268`: alan boşken `?` + (AI yapılandırılmışsa) ✨ + ↑ gösteriliyor. `_parse` boşken hiçbir şey yapmıyor (`:180`), `_submit` de öyle (`:153`).
  - Sahip görüntüsünde boş alanda 4 kontrol var. DESIGN §39 Q3'ün amacı "a phone bar never carries three suffix icons over the text", ama bu boş durumda zaten üç sonek çiziliyor.
- **Önerilen düzeltme**
  - Önek `+` kaldırılsın (ya da düğme olmadığı belli olan, `onSurfaceVariant` %60 bir kalem/işaret yapılsın).
  - Boşken yalnız `?` görünsün. Yazmaya başlayınca `?` çip satırına geçsin (mevcut davranış) ve ✨ ile ↑ `AnimatedSwitcher` ile girsin.
- **Kilit test:** `quick_add_bar_test.dart`. Boş durumda `quick-add-parse` ve gönder düğmesi `findsNothing`, `quick-add-help` `findsOneWidget`; metin yazılınca tersi.

### R-12 — Kırılımlar: 720–799 aralığında karma yerleşim, masaüstünde AI FAB rayın üstünde — **major** (iPad mini) / **minor** (masaüstü), efor S

- **Kanıt**
  - Ana sayfa geniş düzene 720'de geçiyor (`features/home/home_screen.dart:398`), kabuk 800'de (`theme/tokens.dart:38`).
  - Probe `ipadmini_portrait_tr_light.png` (744):
    - iki sütunlu Ana sayfa (takvim paneli) + telefon kapsülü + iki FAB bir arada;
    - kapsül 24–648, ikonlar 125 pt aralıklı (çok seyrek);
    - mikrofon FAB'ı satırların üstünde.
  - Masaüstü: AI FAB 8–64 × 728–784, ray paneli 12–268 × 12–788. **Düz FAB, cam rayın sol alt köşesinin üstünde** (`desktop_tr_dark.png`).
  - Bunun sebebi `screens/home_shell.dart:305-308`: geniş düzende de `centerFloat` + tam genişlik `Row`. DESIGN §24 AI1 ise "On rail layouts the AI entry sits at the rail's bottom" diyor; FAB olarak değil, rayın içinde.
  - DESIGN §4 "glass is never stacked on glass" (burada düz FAB camın üstünde).
- **Önerilen düzeltme**
  - Tek kırılım kaynağı: Ana sayfa `kAwWideBreakpoint`'i kullansın. Ya da 600–799 aralığında telefon kapsülünü en fazla 480 pt genişliğe sınırlayıp ortalayın.
  - Geniş düzende AI girişi `NavigationRail.trailing` içine taşınsın (`EeApprovalsRailEntry` gibi); pencerede yalnız + FAB `endFloat` kalsın.
- **Kilit test:** `breakpoints_test.dart`. 744 pt'te Ana sayfa ve kabuk aynı düzende olmalı. 1280 pt'te `ai-fab` dikdörtgeni `NavigationRail` atasının `GlassSurface` dikdörtgeniyle kesişmemeli.

### R-13 — Kabuk hatalarını görebilecek tek araç onları görmüyor — **major**, efor S

- **Kanıt**
  - `apps/app/test/design_screenshots_test.dart:119-127`: `_ScreenshotApp` builder'ında `QuickAccessBubbleHost` yok. Uygulamada var (`app.dart:90-94`).
  - `_shoot` (`:398-414`) yalnız boyut, DPR ve parlaklık ayarlıyor; `padding/viewPadding` 0. Ev göstergesi şeridi (R-03) hiçbir çekimde yok.
  - Varsayılan tohumda `aiEnabled = false` (`apps/app/test/features/projects/fake_api.dart:496`): AI FAB hiçbir phone_home çekiminde yok.
  - Goldens commit edilmiyor (`design_screenshots_test.dart:9-10`), yani regresyon kilidi değil.
  - Uygulama testlerinde metin ölçeği testi yok (`grep -rn textScaleFactorTestValue apps/app/test` → 0 sonuç).
- **Önerilen düzeltme**
  - Harness builder'ı `app.dart` ile aynı katmanları monte etsin.
  - `_shoot`'a `viewPadding` ve `textScale` parametreleri eklensin.
  - `phone_home_full_{light,dark}` çekimi: AI açık, bir Hızlı Erişim kısayolu, 393×852, alt boşluk 34.
  - R-01…R-12'nin geometrik widget testleri commit edilen gerçek kilitler olsun. Goldens inceleme amaçlı kalabilir.
  - Probe testi bunun taslağı olarak kullanılabilir: ham kanıt.
- **Kilit test:** Yukarıdaki widget test matrisleri. `verify:task` kapsamına `test/features/shell/` girmeli.

### R-14 — Küçük bulgular — **minor**, efor S

- **İki klasör ikonu:** Projeler `Icons.folder_outlined`, Dosyalar `Icons.folder_copy_outlined` (`sections.dart:31,45`). Etiketsiz barda ayırt edilmiyor (sahip görüntüsünde 3. ve 5. ikon). Öneri: Dosyalar için `Icons.attach_file`/belge yığını, Projeler için `Icons.folder_outlined` kalsın. Kilit: `sections_test.dart`'ta ikon kod noktalarının benzersizliği.
- **Bayat sabit yorumu:** `kBubbleBottomReserve` yorumu bar yüksekliğini 80 sayıyor (`bubble_physics.dart:34-39`), tema 64. Rezerv 16 pt fazla. Davranış hatası değil, ama dok hesabı ayrı sabitlerle (`kBubbleBarHeight = 64`, :44) yapılıyor ve iki kaynak birbirinden kopuk.
- **2.0× metin ölçeği:** Takvimde "Cum" iki satıra kırılıyor ("Cu/m", `se_tr_dark_scale20.png`; `features/home/month_calendar.dart`), hızlı ekleme ipucu "Hızlıca gör…" diye kesiliyor. Hafta günü başlıkları `maxLines: 1` + `FittedBox` olmalı.

## 3. Kırılım davranışı özeti (probe'dan)

| Durum | Gezinme | Etiketler | Yüzen öğeler | Not |
| --- | --- | --- | --- | --- |
| SE 375×667, alt boşluk 0 | Kapsül 12–291 + küre 299–363 | Yalnız seçili (yuva 51) | AI FAB 8–64, + FAB 311–367, y 519–575 | 2.0×: başlık "Ana S…", tek kart 780 pt |
| iPhone 15 393×852, alt 34 | Kapsül 12–309 + küre 317–381, bar 754–818 | Yalnız seçili (54,6) | FAB'lar y 682–738 | Bar altında 34 pt içerik şeridi |
| Pro Max 430×932, alt 34 | Kapsül 12–346 + küre 354–418, bar 834–898 | Yalnız seçili (62) | AI 8–64, + 366–422 | Sahip görüntüsüyle birebir |
| Dokta balon (hesap) | Kapsül 274 / 237 / 219 | Yuva 50 / 42,6 / 39 | Balon bar satırında, sağda | G4 < 44 (393 ve 375) |
| Uzantı 6 bölüm, SE | Yuva 42,5 (dok yok), 32,5 (dok) | Yalnız seçili | — | G4 ihlali |
| 1.3× / 2.0× | Etiket 1.3'te kısıtlı | Etiket kapsül eğrisinde (alt 3,5 pt) | Değişmez | Seçili ikon 12,5 pt yukarıda |
| iPad mini 744 | Telefon kapsülü 612 pt genişlik | Hepsi | 2 FAB | Ana sayfa geniş düzende (720 kırılımı) |
| iPad 820 / 1180, masaüstü | Cam ray (12–96 / 12–268) | Ray etiketleri | AI FAB rayın sol alt köşesinin üstünde | Raydaki arama + app bar "Ara" |
| EN 393 | Aynı | "Home" 34 pt; kural TR'ye göre işliyor | Aynı | TR, genişliği belirleyen dil |

## 4. Yüzen öğe envanteri

| Öğe | Ekran | Konum (Pro Max 430 pt, alt 34) | Boyut | Çakıştığı şey |
| --- | --- | --- | --- | --- |
| Cam kapsül alt bar (`home_shell.dart:422-504`) | Kabuktaki bütün bölümler, telefon (<800) | x 12–346, y 834–898; ekran altından 34 pt yukarıda | 334×64 (dok yok) / 274×64 (dok) | Alttaki 34 pt içerik şeridi (R-03); etiket hap eğrisinde (R-02); dok balonu sekmeleri daraltıyor (R-04) |
| Her yerde arama küresi (`global_search_entry.dart:224`) | Kabuktaki bütün bölümler, telefon | Bar satırının sağı, x 354–418 | 64×64 | + FAB'la üst üste, 8 pt kaymış (R-06); app bar "Ara" ile aynı glif (R-05); sekme genişliğinden pay alıyor (R-01) |
| + oluştur FAB (`home_shell.dart:141-171`) | Ana sayfa, Projeler, Notlar (Fikirler, Dosyalar ve uzantı bölümünde yok) | Sağ alt, x 366–422 (AI açık) / 358–414 (AI kapalı), y 762–818 | 56 | Satırların sağ ikon sütunu; hızlı ekleme alanındaki önek "+" ile glif çifti (R-11); kenar boşluğu AI durumuna göre değişiyor (R-06) |
| AI mikrofon FAB (`ai_fab.dart`) | AI sunucuda açıksa kabuktaki bütün bölümler (not ekranı hariç, §22a) | Sol alt, x 8–64, y 762–818; masaüstünde 8–64 × 728–784 | 56 | Bölüm başlıkları ve onay daireleri (R-07); masaüstünde cam ray (R-12) |
| Hızlı Erişim balonu (`quick_access_bubble.dart`) | Router'ın üstünde, bütün telefon rotaları (modal ve belge hariç) | Fabrika: bar satırında sağ dok (hesap); sahipte: sol kenar, y ≈ 151–207 pt, yarısı içeride, %40 opak | 56 dokunma, yarısı görünür | Dokta: sekmeler 39–50 pt (R-04). Serbestte: hızlı ekleme alanının sol kenarı, AI FAB'la aynı kenar (R-08) |
| Balon tanıtım kartı (`QuickBubbleIntro`, `quick_access_bubble_host.dart:184-185`) | İlk kullanım | Balonun yanı | **Bilinmiyor** (ölçülmedi) | Bilinmiyor |
| Cam ray paneli (`home_shell.dart:311-391`) | ≥800 pt | 12–96 (iPad dikey) / 12–268 (≥1160) | Tam yükseklik −24 | AI FAB rayın alt köşesinin üstünde (R-12) |
| Kayan snackbar (`theme.dart:405-416`, `_ShellBody`) | Bütün kabuk | Barın üstü (`viewPadding` kopyası, `home_shell.dart:733-751`) | — | Bu turda ölçülmedi |

Sayı: Pro Max'te sahip ekranında **5 yüzen nesne** (kapsül, küre, + FAB, AI FAB, balon) ve bunlara ek olarak bar altındaki içerik şeridi. DESIGN §24 AI1'in "no screen shows a third floating action" ilkesi biçimsel olarak korunuyor (küre ve balon "gezinme" sayılıyor), ama görsel olarak ekranda dört daire var.

## 5. Önerilen sıra (UX > UI > cila)

1. R-03 (alt şerit solması) + R-02 (etiket dolgusu) + R-06 (tek yüzen kenar). Hepsi S, kararlara dokunmuyor ve sahibin ekranındaki "kaymış" görüntünün yarısını tek başına giderir.
2. R-09 + R-10 + R-11 (satır anatomisi, tipografi, hızlı ekleme). M ve S, karar gerekmiyor (DESIGN maddeleri güncellenir).
3. R-13 (harness ve testler), 1–2 ile aynı fazda, kilit olarak.
4. **SAHİBE SORU paketi:** R-01 (etiket modu / ADR-0055), R-04 + R-08 (balon konumu / §23 Q4), R-07 (AI FAB / §24 AI1). Her biri için 2–3 yön, demo tohumlu çekimle gösterilmeli.
5. R-05 (yerel aramanın telefondan kalkması, ADR), R-12 (kırılımlar), R-14.

## 6. Bilinmeyenler

- Docktaki balonla 39–50 pt yuvada 64 pt'lik M3 göstergesinin kırpılıp kırpılmadığı ölçülmedi (harness balonu çizmiyor).
- Sahip cihazının gerçek modeli ve metin boyutu ayarı bilinmiyor. Ölçüler 430 pt ve 1.0 ölçek varsayımıyla probe'la tutarlı.
- Gerçek iOS'ta SF Pro ile render edilen izleme farkı probe'da Roboto ile ölçüldü. SF Pro'daki görsel etki sahip görüntüsünden gözlemdir, ölçü değildir.
- Snackbar ve balon tanıtım kartının konumu ölçülmedi.
