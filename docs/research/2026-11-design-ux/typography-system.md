> **Depodaki kopya (2026-11-07, E35 kaydı):** uzantıya özgü tasarım ayrıntısı çıkarıldı (uzantı bulguları uzantı deposunda); turun iç çalışma dosyalarına ve ham kanıta verilen yollar düz metne çevrildi ("ham kanıt" = turun çalışma alanında kalan dosya; depoda yok). Bulgu kimlikleri değişmedi. Özet: [README.md](README.md).

# Görsel sistem denetimi: tipografi, ızgara, ikon, yoğunluk

> Son güncelleme: 2026-11-07 — CEO tasarım/UX turu
> Kaynak: `apps/app/lib/src/theme/theme.dart`, `apps/app/lib/src/theme/tokens.dart`, `apps/app/lib/**` (505 Dart dosyası, grep/AST taraması), Flutter SDK 3.47.7 kaynağı (`<flutter-sdk>/packages/flutter/lib/src/material/typography.dart`, `…/cupertino/text_theme.dart`, `…/material/list_tile.dart`, `…/flutter_web_sdk/lib/_engine/engine/canvaskit/fonts.dart`), `docs/DESIGN.md`, `docs/adr/0005`, `docs/adr/0012`, sahibin brief'i (sahip brief'i) ve ekran görüntüsü (ham kanıt; içindeki metinler bu belgeye alınmadı), Apple HIG Typography (JSON dökümü: ham kanıt), Material 3 tip ölçeği (Flutter'ın üretilmiş M3 tokenları).

Ham materyal: ham kanıt (`offgrid.txt`: ızgara dışı tüm yerler, `icon-sizes.txt`: her Icon boyutu ve yeri, `hig-typography.txt`: HIG tabloları).

---

## 0. Kısa sonuç

1. **Gövde metnindeki geniş harf aralığının kök nedeni** `theme.dart:103-111`. Tema, Material 3'ün "englishLike 2021" geometrisini olduğu gibi alıyor. Bu geometride `bodyLarge` için `letterSpacing: 0.5`, `bodyMedium` için 0.25, `bodySmall` için 0.4, `labelMedium` ve `labelSmall` için 0.5 var (`typography.dart:2104-2111`). `theme.dart:128-129` gövde rollerinde yalnız `height` değerini değiştiriyor ve tracking'e dokunmuyor. iOS'ta font SF Pro Text (`CupertinoSystemText`) olduğu için Roboto'ya göre ayarlanmış +0.5 değeri SF'ye de uygulanıyor. Apple'ın 16 pt için önerdiği tracking **−0.31 pt** (HIG tablosu), yani fark **0.81 pt/harf**. Görev başlığı ListTile teması üzerinden `bodyLarge w500` alıyor (`theme.dart:193-195`).
2. Bu açık tasarım incelemesinde görülmedi, çünkü golden ekran görüntüleri Roboto ile üretiliyor (`test/design_screenshots_test.dart:34-44`, `ScreenshotSans`). Roboto ile +0.5 doğal görünüyor; SF ile geniş görünüyor. **SF metrikleri hiçbir otomatik kontrolden geçmiyor.**
3. Alt bar etiketi `labelMedium` 12 / w700 / +0.5 değerleriyle çiziliyor (`theme.dart:338-346`). Etiket tek satıra zorlanıyor ve `overflow: visible` (`home_shell.dart:470-476`). Roboto ile ölçtüğüm "Ana Sayfa" 1.0× ölçekte ≈59 px, 1.3× ölçekte ≈75 px tutuyor. 430 pt ekranda sekme yuvası ≈63.6 px olduğu için etiket 1.3× ölçekte kapsülden taşıyor (C-01'in tipografik payı).
4. Yeni spesifikasyonun özü şu: **boyutlar korunur; tracking font ailesinden türetilir** (Apple tablosu ve Roboto/Segoe tablosu), satır yükseklikleri sıkılaştırılır, tabular rakamlar ve 16/20/24/32/48 ikon ölçeği gelir, liste satırı 52/64 olur. Glass kimliğine (renk, cam, yarıçap, hareket) dokunulmuyor.
5. Web'de "ağ indirmesi yok" kuralı bugün sağlanmıyor. CanvasKit, Roboto'yu `fonts.gstatic.com` adresinden indiriyor (`canvaskit/fonts.dart:14-15, 128-133`). Uygulama zaten Roboto TTF taşıyor (`apps/app/assets/fonts/`, PDF için). Bu dosyayı `Roboto` ailesi olarak kaydetmek indirmeyi kapatıyor.
6. Kontrast: koyu temada geciken meta satırı (`#FF5147` / `#151F3C`) **5.04:1** ölçülüyor ve eşiği geçiyor. Kırmızı bölüm başlığı en kötü aurora noktasında **4.32–4.34:1** kalıyor ve eşiğin altına düşüyor. Ayrıca proje detayındaki `Colors.amber` yıldızı açık temada **1.55:1** veriyor (G2 ve G6 ihlali).

---

## 1. TextTheme'in tam çıkarımı (bugünkü durum)

### 1.1 Zincir

| Adım | Dosya:satır | Etki |
| --- | --- | --- |
| `Typography.material2021(platform: defaultTargetPlatform).englishLike` | `theme.dart:103-107` | Yalnız geometri gelir: boyut, ağırlık, satır yüksekliği ve **letterSpacing** (M3 tokenları, `typography.dart:2097-2111`). Font ailesi bu adımda yok. |
| `.apply(fontFamily: fontFamilyOverride)` | `theme.dart:107-111` | Üretimde null. Yalnız test kancası. |
| `copyWith`: headline/title ağırlık ve negatif tracking, body yalnız `height` | `theme.dart:112-130` | Gövde ve label rollerinin pozitif tracking'i olduğu gibi kalır. |
| `ThemeData(textTheme:)` → `defaultTextTheme.merge(textTheme)` | Flutter `theme_data.dart:508,524` | Font ailesi `typography.black/white` içinden gelir: iOS'ta `blackCupertino` (`typography.dart:219, 995-1090`). |
| `ThemeData.localize` → `localTextGeometry.merge(...)` | Flutter `theme_data.dart:1743-1762` | Geometri aynıdır; tr ve en ikisi de "englishLike" sınıfında. |

### 1.2 Platforma göre font ailesi (gerçekte yüklenen)

| Platform | Display/Headline/titleLarge | title M/S, body, label | Kaynak |
| --- | --- | --- | --- |
| iOS | `CupertinoSystemDisplay` → SF Pro Display | `CupertinoSystemText` → SF Pro Text | `typography.dart:998-1052`; proxy açıklaması `painting/text_style.dart:473-479` |
| macOS | `.AppleSystemUIFont` (SF) | aynı | `typography.dart:1194+` |
| Android | Roboto | Roboto | `typography.dart:379+` |
| Windows | Segoe UI | Segoe UI | `typography.dart:571+` |
| Linux | Roboto + yedek (Ubuntu, Adwaita Sans, Cantarell…) | aynı | `typography.dart:757-760, 774-781` |
| Web (her işletim sistemi) | Apple proxy adları web'de çözülmez, sonuç **Roboto** olur. Roboto `fonts.gstatic.com` adresinden indirilir. | aynı | `text_style.dart:478-479`; `flutter_web_sdk/.../canvaskit/fonts.dart:14-15, 128-133`; `configuration.dart:365` |

- `pubspec.yaml` içinde UI için `fonts:` tanımı yok. Satır 272'deki blok yorum, satır 245-255 yalnız PDF içindir. Hiçbir yerde `fontFamilyFallback` yok (yalnız monospace alanlarında: `api_keys_screen.dart:200`, `markdown_forge_adapters.dart:74`).
- **Sonuç:** iOS'ta gerçekten SF Pro yükleniyor. Ekran görüntüsündeki glif biçimleri de SF ile tutarlı. Sorun font ailesi değil, tracking.

### 1.3 Rol bazında etkin değerler (1.0× metin ölçeği)

| Rol | Boyut | Satır yüksekliği (oran → px) | Ağırlık | letterSpacing | Değiştiren satır | Kullanım sayısı* |
| --- | --- | --- | --- | --- | --- | --- |
| displayLarge | 57 | 1.12 → 64 | 400 | −0.25 | — | 0 |
| displayMedium | 45 | 1.16 → 52 | 400 | 0 | — | 0 |
| displaySmall | 36 | 1.22 → 44 | 400 | 0 | — | 1 |
| headlineLarge | 32 | 1.25 → 40 | 400 | 0 | — | 0 |
| headlineMedium | 28 | 1.29 → 36 | **700** | **−0.5** | `theme.dart:113-116` | 3 |
| headlineSmall | 24 | 1.33 → 32 | **700** | **−0.4** | `theme.dart:117-120` | 7 |
| titleLarge | 22 | 1.27 → 28 | **700** | **−0.3** | `theme.dart:121-124` | 22 |
| titleMedium | 16 | 1.50 → 24 | **600** | +0.15 | `theme.dart:125` | 57 |
| titleSmall | 14 | 1.43 → 20 | **600** | +0.1 | `theme.dart:126` | 90 |
| labelLarge | 14 | 1.43 → 20 | **600** | +0.1 | `theme.dart:127` | 40 |
| labelMedium | 12 | 1.33 → 16 | 500 | **+0.5** | — | 24 |
| labelSmall | 11 | 1.45 → 16 | 500 | **+0.5** | — | 25 |
| bodyLarge | 16 | **1.5** → 24 | 400 | **+0.5** | `theme.dart:128` (yalnız height) | 22 (+ her ListTile başlığı, input hint/label) |
| bodyMedium | 14 | **1.45** → 20.3 | 400 | **+0.25** | `theme.dart:129` (yalnız height) | 119 (+ ListTile alt başlığı) |
| bodySmall | 12 | 1.33 → 16 | 400 | **+0.4** | — | **235** |

\* `grep -rhoE 'textTheme\.(…)'` sayımı, `apps/app/lib`. Bunlara ek olarak **230** adet `textTheme.X?.copyWith(` çağrısı var, yani roller yerel olarak sık sık bükülüyor. Ad hoc ağırlıklar: w500 ×5, w600 ×33, w700 ×21, w800 ×1.

Bileşen temalarının seçtikleri:

- ListTile başlığı `bodyLarge` w500, alt başlığı `bodyMedium` (`theme.dart:193-198`).
- Input hint/label `bodyLarge` (`theme.dart:211-212`). Bu, "Hızlıca görev ekle" alanının da +0.5 almasının nedeni.
- Butonlar `labelLarge` w600 (`theme.dart:230-258`).
- NavigationBar etiketi `labelMedium` (seçili w700, diğerleri w500) (`theme.dart:338-346`).
- Rail etiketi `labelLarge` (`theme.dart:355-361`).
- Sekmeler `titleSmall` (`theme.dart:366-368`).

### 1.4 Ekran görüntüsündeki geniş tracking'in teşhisi

- Görev başlığı: `task_tile.dart:186-195` stil vermiyor (`style: null`, yalnız tamamlanmışsa `bodyLarge`). Böylece ListTile teması devreye giriyor: `bodyLarge` (16 pt, **+0.5**) + w500 (`theme.dart:193-195`).
- Meta satırı ("Gecikti — …"): `bodyMedium` (14 pt, **+0.25**) + w600 + `scheme.error` (`task_tile.dart:318-322`).
- Bölüm başlığı ("Geciken · N"): `labelLarge` + w700 + elle eklenmiş **+0.4** (`home_screen.dart:698-706`).
- Apple'ın SF Pro tracking tablosu (HIG, ham kanıt): 12 pt 0 · 13 pt −0.08 · 14 pt −0.15 · 15 pt −0.23 · **16 pt −0.31** · 17 pt −0.43 · 22 pt −0.26 · 24 pt +0.07 · 28 pt +0.38 · 34 pt +0.40.
  - 16 pt'de uygulama +0.5 kullanıyor, sistem −0.31 öneriyor: **+51/1000 em** fazla.
  - 14 pt'de +0.25'e karşı −0.15.
  - 12 pt'de +0.4'e karşı 0.
- Flutter, SF'nin dinamik tracking'ini motor seviyesinde uyguluyor mu? Bu **dolaylı kanıtla "hayır" görünüyor**. Flutter'ın kendi Cupertino teması HIG değerlerini elle veriyor: `cupertino/text_theme.dart:23` → 17 pt −0.41, `:86` → 34 pt +0.38, `:97` "iOS 14 simülatör ekran görüntülerinden alındı". Motor uygulasaydı bu değerler çift sayılırdı. İki durumda da +0.5 net pozitif kalır (uygulansa bile −0.31 + 0.5 = +0.19). Kesin ölçüm için §9'daki cihaz kontrolü gerekli.
- Ölçüm (yaklaşık): ekran görüntüsü 923×2000 px. 430 pt genişlik varsayımıyla 1 pt = 2.147 px. Başlık satır aralığı ≈51 px ≈ **23.8 pt**, bu da 16 × 1.5 = 24 ile uyuşuyor. Yani metin ölçeği 1.0× ve sorun büyük Dynamic Type değil. Başlık sütunu ≈466 px ≈ **217 pt**. Sağdaki üç ikon ve aralıkları ≈78 pt yiyor.
- Etkinin büyüklüğü (Roboto proxy'siyle ölçüldü, 47 karakterlik bir Türkçe cümle, 16 pt): +0.5 ile 349.9 px, 0 ile 326.4 px, −0.31 ile 311.9 px. Bugünkü değer, Apple tracking'ine göre satırı **%12 uzatıyor** ve uzun başlıkları fazladan satıra kaydırıyor.

---

## 2. Kod genelinde DESIGN G6 / §3.3 ihlalleri

### 2.1 Sayımlar (`apps/app/lib`, 505 dosya)

| Ölçüt | Sayı | Not |
| --- | --- | --- |
| `fontSize:` | 18 | 15'i PDF dışa aktarıcısında (`note_pdf.dart`, `asset_label_pdf.dart`; izinli, DESIGN E4/E5). **UI'da 3 tane:** `month_calendar.dart:234`, `swipe_actions.dart:92`, uzantının bir ekranı |
| Ham `TextStyle(` (tema ve `pw.` hariç) | 42 | Çoğu `TextStyle(color: scheme.error)`. Rolü atlayıp `DefaultTextStyle`'a yaslanıyor. |
| `letterSpacing` (tema dışı, UI) | 8 | +0.4 ×5 (bölüm etiketi deseni), +1.2 (`alarm_ring_screen.dart:281`, BÜYÜK HARF, bu kabul edilebilir), +4 (uzantının bir ekranı) |
| `Colors.*` (transparent hariç, tema dışı) | 11 | En kötüsü `project_detail_screen.dart:238` `Colors.amber` (bkz. §5). `color_swatch_dot.dart:33-34`, `brand_mark.dart:30`, `image_viewer.dart:270`, `tour_overlay.dart:77` gerekçeli olabilir. |
| Ham `Color(0x…)` (tema dışı) | 21 | 12'si `note_colors.dart` (kullanıcı verisi paleti, G6 istisnası) |
| Ham sayılı `EdgeInsets` çağrısı | 164 | **26'sı ızgara dışı** (değerler: 2 ×12, 6 ×10, 3 ×4, 14, 10, 57) |
| `SizedBox(width/height: <sayı>)` | 126 sayı / 645 `AwSpace` | **22'si ızgara dışı** (2 ×7, 18 ×5, 6 ×4, 22 ×2, 10, 14, 3, 46) |
| `Icon(` | 671 | Boyut verilmemiş (24 / IconTheme) 490 · 18 ×97 · 20 ×38 · 16 ×29 · 22 ×6 · 14 ×4 · 34 ×2 · 28 · 52 · 5. **Toplam 9 ayrı sabit boyut.** |
| İkon stili | 1010 `Icons.*` referansı | 464 `_outlined`, 4 `_rounded`, geri kalanı dolu. Aynı satırda karışıyor: dolu bayrak, dolu zil ve outline kum saati (`task_tile.dart:410-441`, `task_visuals.dart:20`). |
| `FontFeature.tabularFigures` | **1** | Yalnız `month_calendar.dart:235`. DESIGN §3.3 ve §9 L3 bunu sayaç ve zamanlar için de istiyor. |
| Metin ölçeği kısıtı | 1 | Yalnız `note_figure_raster.dart:156` (bilerek `noScaling`). Uygulama OS ölçeğini sınırsız izliyor; bu erişilebilirlik için iyi, ama uyarlanmış yerleşim yok. |
| Tipografi kapısı | yok | `package.json` içinde `check:fab` ve `check:opacity` var; `fontSize`, `letterSpacing`, ızgara ya da ikon ölçeği kapısı yok. |

### 2.2 En kötü 25 yer (önem sırasıyla)

| # | Yer | Sorun |
| --- | --- | --- |
| 1 | `theme/theme.dart:103-111` | M3 englishLike tracking'i (+0.5/+0.25/+0.4) SF'ye de uygulanıyor. Kök neden. |
| 2 | `theme/theme.dart:128-129` | body rollerinde yalnız `height` değişiyor; tracking ve satır yüksekliği liste için gevşek (24 / 20.3). |
| 3 | `theme/theme.dart:188-200` | ListTile temasında `titleAlignment` yok. M3 varsayılanı `threeLine` (Flutter `list_tile.dart:975-978`, `:138`) ve `isThreeLine` false olduğu için onay dairesi ve sağ ikonlar çok satırlı satırda **dikey ortada** kalıyor (C-05). |
| 4 | `theme/theme.dart:193-195` | Satır başlığı w500: SF + geniş tracking ile "kalın ve dağınık" duruyor. |
| 5 | `features/tasks/ui/task_tile.dart:186-195` | Başlıkta `maxLines` yok: uzun URL 5 satır. HIG kısaltmaya izin veriyor, çünkü ayrıntı görünümü var (`hig-typography.txt`, "Keep text truncation to a minimum… unless people can open a separate view"). |
| 6 | `features/tasks/ui/task_tile.dart:318-322` | Meta satırının tamamı error rengi ve w600. Kırmızı + kalın + geniş tracking bir arada. |
| 7 | `features/tasks/ui/task_tile.dart:410-441` | Sağ kümede 3 × 18 px ikon + 3 × 8 aralık ≈ 78 pt (+ proje rozeti). Başlık sütunu ≈217 pt'ye iniyor. |
| 8 | `features/tasks/ui/task_tile.dart:224, 246, 257, 289, 341` | Aynı meta satırında 14 ve 16 px ikonlar karışık. |
| 9 | `theme/theme.dart:338-346` | Bar etiketi 12/+0.5. Seçili w700, diğerleri w500 olduğu için seçim değişince etiket genişliği zıplıyor. |
| 10 | `screens/home_shell.dart:466-476` | `maxLines: 1, softWrap: false, overflow: visible`: etiket kapsülün dışına taşıyor (C-01). |
| 11 | `screens/home_shell.dart:709-711` | `kAwBarLabelSlot = 64` "Ana Sayfa sığar" varsayımıyla konmuş, 1.3×'te sığmıyor (§3.3). |
| 12 | `features/home/home_screen.dart:698-706` | Bölüm başlığı labelLarge w700 +0.4; sayı tabular değil; kırmızı varyantı aurora üstünde eşik altı (§5). |
| 13 | `features/tasks/ui/completed_screen.dart:202-206` | Aynı "bölüm etiketi" deseni kopyalanmış (+0.4). |
| 14 | `features/tasks/ui/task_detail_screen.dart:624-629` | Aynı desen (+0.4). |
| 15 | `features/projects/ui/project_edit_sheet.dart:157-162` | Aynı desen (+0.4) ve ham `SizedBox(height: 16)`. |
| 16 | `features/home/month_calendar.dart:229-236` | Ham `TextStyle(fontSize: 13)`; rol yok. |
| 17 | `features/home/month_calendar.dart:119` | Hafta günü etiketinde +0.4. |
| 18 | `widgets/swipe_actions.dart:91-93` | Ham `TextStyle(fontSize: 12, w600)`. |
| 19 | uzantının bir ekranı | ham renk ve ham boyut (uzantı deposunda izlenir). |
| 20 | `features/projects/ui/project_detail_screen.dart:238` | `Colors.amber` yıldız: açık temada **1.55:1** (G2 ve G6, DESIGN §4 "Stars… never `Colors.amber`"). |
| 21 | `theme/theme.dart:199, 219, 322` | Tema seviyesinde ızgara dışı değerler: `minVerticalPadding: 10`, input `vertical: 14`, chip `horizontal: 10`. |
| 22 | `widgets/status_views.dart:262` | `kAwListRowPadding = vertical: 3` (6 px ritim, DESIGN §4'te belgelenmiş ama 4-pt ızgara dışı). |
| 23 | `widgets/count_badge.dart:58-62` | `minWidth: 22`, padding 6/2, yarıçap 11: ızgara dışı rozet geometrisi. |
| 24 | `widgets/status_views.dart:66, 142` · `notifications/alarm_ring_screen.dart:267` · `features/home/month_calendar.dart:244` | Ölçek dışı ikon boyutları: 34, 52, 5. |
| 25 | `sections.dart:31-32, 45-46` | Projeler `folder` ve Dosyalar `folder_copy` 24 px'te neredeyse aynı siluet (ekran görüntüsünde iki klasör yan yana). |

Izgara dışı yerlerin tam listesi: ham kanıt. İkon yerleri: ham kanıt.

---

## 3. Apple HIG ve Material 3 karşılaştırması

### 3.1 Ölçek eşlemesi

| Bizim rol (bugün) | Material 3 temel | Apple iOS (Large, varsayılan) | Gözlem |
| --- | --- | --- | --- |
| titleLarge 22/28 w700 −0.3 | 22/28 w400 0 | Title 2 22/28 (vurgulu: Bold), −0.26 | Uyumlu. |
| headlineMedium 28/36 w700 −0.5 | 28/36 w400 0 | Title 1 28/34, **+0.38** | Apple'a göre ~0.9 pt daha sıkı. Bu bir zevk tercihi (§6.1). |
| headlineSmall 24/32 w700 −0.4 | 24/32 w400 0 | (24 pt) +0.07 | Biraz sıkı. |
| titleMedium 16/24 w600 +0.15 | 16/24 w500 +0.15 | Callout 16/21 (vurgulu Semibold), −0.31 | Satır yüksekliği ve tracking gevşek. |
| bodyLarge 16/24 w400 +0.5 | 16/24 w400 +0.5 | Body 17/22 −0.43 · Callout 16/21 −0.31 | **En büyük sapma.** |
| bodyMedium 14/20 w400 +0.25 | 14/20 w400 +0.25 | Subhead 15/20 −0.23 · (14 pt −0.15) | Gevşek. |
| bodySmall 12/16 w400 +0.4 | 12/16 w400 +0.4 | Caption 1 12/16, 0 · Footnote 13/18 −0.08 | En çok kullanılan rol (235), gevşek. |
| labelLarge 14/20 w600 +0.1 | 14/20 w500 +0.1 | (14 pt) −0.15 | Hafif. |
| labelMedium 12/16 w500 +0.5 | 12/16 w500 +0.5 | Caption 1 12/16, 0 | Bar etiketi. Gevşek. |
| labelSmall 11/16 w500 +0.5 | 11/16 w500 +0.5 | Caption 2 11/13, +0.06 | Gevşek. |

Kaynaklar: HIG tabloları ham kanıt (https://developer.apple.com/design/human-interface-guidelines/typography). M3 değerleri `typography.dart:2097-2111` (Flutter'ın M3 token üretimi; https://m3.material.io/styles/typography/type-scale-tokens). HIG asgari boyutu iOS'ta 11 pt, varsayılanı 17 pt. Hafif ağırlıklar önerilmiyor; uygulamada w300 yok, iyi.

**Yorum:** Tema Material ölçeğini kullanırken Apple görünümünü hedefliyor (DESIGN §1 "Apple-2026 Liquid Glass"). Boyutlar iki sistemde de makul; uyumsuzluk **tracking ve satır yüksekliğinde**. Material'ın Roboto için koyduğu pozitif tracking, SF'nin kendi optik aralığının üstüne biniyor.

### 3.2 Türkçe metin uzunluğu

- `assets/i18n/tr.json` ile `en.json` karşılaştırıldı (3425 anahtar, ≥4 karakter). TR/EN uzunluk oranının medyanı **1.00**, p90'ı **1.44**. Kısa etiketlerde (4-20 karakter) p90 **1.60**. Yani etiketlerin %10'u İngilizcenin 1.6 katı.
- Türkçe glifler (ı İ ğ ş ç ö ü): SF, Roboto ve Segoe'de tam destek var, risk yok. Risk satır uzunluğunda: büyük harf İ/ı ayrımı ve Türkçenin uzun ekli kelimeleri 217 pt sütunda kaydırmayı artırıyor.

### 3.3 1.3× metin ölçeğinde taşma riski

Roboto ile ölçüldü (SF biraz daha geniş; değerler alt sınır):

| Etiket (bar) | 12 pt w700 +0.5 (bugün) | 1.3× | Önerilen: 11 pt w600, ~0 tracking | 1.3× |
| --- | --- | --- | --- | --- |
| TR "Ana Sayfa" | 59.0 | **75.3** | 50.0 | 64.9 |
| TR "Dosyalar" | 51.1 | 65.3 | 43.2 | 56.1 |
| EN "Requests" | 54.5 | 69.7 | 46.3 | 60.2 |

Yuva hesabı (430 pt telefon): kapsül = 430 − 2×12 kenar − 64 arama küresi (`global_search_entry.dart:225`) − 8 boşluk = 334. Bundan 2×12 iç dolgu düşünce 310, 5 sekmeye bölünce ≈ **62–64 px**. 1.0×'te sınırda, 1.3×'te **taşıyor**. Öneri HIG'in kendi ilkesi: "sekme başlıkları metin ölçeğiyle büyümek zorunda değil". Bar etiketi `MediaQuery.withClampedTextScaling(maxScaleFactor: 1.2)` ile sınırlanır, ağırlık sabit w600 olur, tracking 0'a iner.

Diğer riskler:

| Yüzey | 1.3× davranışı | Risk |
| --- | --- | --- |
| Görev satırı (`task_tile.dart`) | Başlık sütunu 217 pt sabit, ikonlar ölçeklenmiyor (18 px). 20.8 pt'de satır başına ≈20 karakter kalıyor. | **Yüksek.** ≥1.3×'te sağ küme meta satırına inmeli (HIG "stacked layout"). |
| Bölüm başlığı | Tek satır, sayı tabular değil. | Düşük |
| Proje rozeti (`project_badge.dart:77`, labelSmall, min 22 yükseklik) | 6 karakter + "…" kısaltma kuralı var (DESIGN §4). | Düşük |
| Sayaç rozeti (`count_badge.dart:58`, minWidth 22, yarıçap 11) | Yükseklik metinle büyür, yarıçap sabit kalır: yatık hap ya da oval. | Orta |
| Ay takvimi hücresi (`month_calendar.dart:209-219`, 46 yükseklik, 32 daire, 13 pt) | 17 pt iki haneli gün 32 dairede sığıyor. | Düşük |
| Hızlı ekleme alanı (`bodyLarge` hint +0.5, 4 kontrol) | Hint kısalır ama kontroller sabit. | Orta (C-06) |

---

## 4. Önerilen spesifikasyon: "Glass Type v1"

İlke: **boyutları koru, aralığı ve ritmi düzelt.** Font ailesi değişmez (ADR-0005 #6). Renk, cam, yarıçap ve hareket tokenları değişmez (O-03 KESİN). Değişiklik çoğunlukla `theme.dart` içinde tek yerde yapılır.

### 4.1 Tracking kuralı: ailesinden türetilir, elle seçilmez

```text
awTracking(size, family):
  Apple ailesi (iOS, macOS; CupertinoSystem*, .AppleSystemUIFont):
      HIG SF Pro tablosu, en yakın 0.01 pt'ye yuvarlanmış:
      11 +0.06 · 12 0 · 13 −0.08 · 14 −0.15 · 15 −0.23 · 16 −0.31 · 17 −0.43
      20 −0.45 · 22 −0.26 · 24 +0.07 · 28 +0.38 · 34 +0.40
  Roboto / Segoe / Linux / web:
      ≤12 pt +0.2 · 13–16 pt +0.1 · ≥17 pt 0 · ≥28 pt −0.25
  BÜYÜK HARF metin (yalnız alarm etiketi): +0.06 em
```

Roboto değerleri M3'ün yarısı kadar. Bu bir tasarım kararı: Roboto'yu cam kimliğiyle sıkılaştırmak. Android'de M3 değerine dönmek istenirse tablo tek satırla değişir.

### 4.2 Rol tablosu (1.0× ölçek, mantıksal px)

| Rol (Flutter slotu) | Kullanım | Boyut / satır yüksekliği | Ağırlık | Tracking (Apple · diğer) | Bugünle fark |
| --- | --- | --- | --- | --- | --- |
| displaySmall | büyük sayı (pano) | 36 / 44 | 700, **tabular** | +0.37 · −0.25 | ağırlık ve tabular |
| headlineMedium | auth başlığı, markdown h1 | 28 / 34 | 700 | +0.38 · −0.25 *(zevk, §6.1)* | satır 36→34, tracking |
| headlineSmall | sayfa veya sheet başlığı, h2 | 24 / 30 | 700 | +0.07 · 0 | satır 32→30 |
| titleLarge | uygulama çubuğu başlığı | 22 / 28 | 700 | −0.26 · 0 | ≈ aynı |
| titleMedium | kart, bölüm ve dialog liste başlığı | 16 / 22 | 600 | −0.31 · +0.1 | satır 24→22, tracking |
| titleSmall | sekme, alt başlık | 14 / 20 | 600 | −0.15 · +0.1 | tracking |
| bodyLarge | **satır başlığı**, input | 16 / **22** | **400** | **−0.31 · +0.1** | satır 24→22, +0.5→−0.31, liste w500→w400 |
| bodyMedium | alt başlık, paragraf (kısa) | 14 / 20 | 400 | −0.15 · +0.1 | +0.25→−0.15 |
| bodySmall | yardım ve açıklama | 12 / 16 | 400 | 0 · +0.2 | +0.4→0 |
| labelLarge | buton | 14 / 20 | 600 | −0.15 · +0.1 | tracking |
| labelMedium | **alt bar etiketi**, chip | 11 / 14 | 600 sabit | +0.06 · +0.2 | 12→11, w700/w500→w600 |
| labelSmall | rozet, takvim hafta günü | 11 / 14 | 500 | +0.06 · +0.2 | satır 16→14 |

Uzun okuma metni (notlar) zaten kendi satır yüksekliğini veriyor (`markdown_forge_adapters.dart:67`, 1.55), bu yüzden bodyLarge'ı 22'ye çekmek notları etkilemez.

Yeni anlamsal roller (`AwTextRoles` ThemeExtension ya da `context.awText.*`). Kopyalanmış `copyWith` desenleri bunlarla değişir:

| Rol | Değer | Bugün nerede kopyalanıyor |
| --- | --- | --- |
| `sectionLabel` | 15/20 w600, cümle biçimi, Apple −0.23 · diğer 0, sayı **tabular**. Renk: onSurfaceVariant / error / link. | `home_screen.dart:698-706`, `completed_screen.dart:202-206`, `task_detail_screen.dart:624-629`, `project_edit_sheet.dart:157-162` |
| `meta` | 13/18 w400, **tabular**, Apple −0.08 · diğer +0.1 | `task_tile.dart` içinde 7 kez `bodySmall.copyWith` |
| `metaStrong` | `meta` + w500 (w600 değil) | overdue, snooze ve muted vurguları |
| `rowTitle` | bodyLarge 16/22 w400, `maxLines: 3`, ellipsis | `task_tile.dart:186` |
| `numeric` | herhangi bir rol + `FontFeature.tabularFigures()` | sayaçlar, saatler, içe aktarma sayıları |

Ağırlık kuralı: UI'da yalnız **400 / 500 / 600 / 700**. w800 yalnız alarm etiketinde (`alarm_ring_screen.dart:280`). Satır içi vurgu w600'ü geçmez. Durum (seçili ya da değil) ağırlıkla değil renkle anlatılır, böylece genişlik zıplamaz.

### 4.3 Tabular rakamlar

Zorunlu yerler:

- tarih ve saat metası (`task.dueOn` / `task.overdueDue`)
- bölüm sayaçları ("· N")
- `CountBadge`
- takvim günü (mevcut)
- alarm saati
- toplantı ve zaman sayaçları
- Uzantının sayı panoları (uzantı deposunda)
- içe aktarma sayaçları (`import_wizard_screen.dart:366`)

`alarm_log_screen.dart:126` içindeki `fontFeatures: const []` tabular olmalı ("veri, düzyazı değil" yorumuyla da tutarlı).

### 4.4 İkon ölçeği

| Token | px | Kullanım | Bugünkü değer |
| --- | --- | --- | --- |
| `AwIcon.xs` | 16 | meta satırı içinde, 13 pt metinle | 14 ve 16 (33 yer) |
| `AwIcon.s` | 20 | satır sağ kümesi, 16 pt metinle, chip avatarı | 18 (97), 20 (38) |
| `AwIcon.m` | 24 | uygulama çubuğu, alt bar, FAB, buton | varsayılan (490), 22 (6) |
| `AwIcon.l` | 32 | boş durum rozeti | 34 (2), 28 (1) |
| `AwIcon.xl` | 48 | alarm kahramanı | 52 (1) |
| (nokta) | 6 | takvim görev noktası; ikon değil, `Container` | 5 |

Kurallar:

1. Satır içi ikon ≈ yanındaki metnin satır yüksekliği − 2 (13/18 → 16, 16/22 → 20).
2. Anlamlı ikonlar metin ölçeğiyle büyür (`textScaler.scale(size)`, en çok 1.5×), çünkü HIG "Increase the size of meaningful interface icons as font size increases" diyor. Bar ikonları sabit kalır.
3. Bir satırda tek stil kullanılır: durum ve meta ikonları outline. Dolgu yalnız "seçili" ya da "aktif" anlamı taşır. Bayrak ve aciliyet istisnası **renkle değil şekille** ayrışır (G5).
4. Alt barda ayırt edilebilir siluet: Dosyalar için `folder_copy` yerine farklı bir metafor (örneğin `attach_file` / `perm_media`). Kesin seçim UI turunda yapılır.

### 4.5 Yoğunluk: liste satırları ve 4-pt ızgara

| Öğe | Öneri | Bugün |
| --- | --- | --- |
| Tek satırlı satır | min **52** (checkbox dokunma alanı 48 + 2×2) | 56 (M3 varsayılanı, `list_tile.dart:1503-1510`) |
| İki satırlı satır (başlık + meta) | min **64** | 72 |
| Satır iç dikey dolgusu | **8** (`AwSpace.x2`) | `minVerticalPadding: 10` (`theme.dart:199`) |
| Satırlar arası | **8** (4 + 4) | 6 (3 + 3, `status_views.dart:262`; DESIGN §4 ve `test/support/list_rhythm.dart` birlikte güncellenmeli) |
| Satır yatay dolgusu | 12 (mevcut `AwSpace.x3`) | aynı |
| Input dikey dolgusu | 12 ya da 16 | 14 (`theme.dart:219`) |
| Chip dolgusu | 12×8 | 10×8 (`theme.dart:322`) |
| Rozet | yükseklik 20, padding 8×2, yarıçap = yükseklik/2 | 22, 6×2, 11 |
| Yarım adım | `AwSpace.x0_5 = 2` **yalnız** chip, rozet ve hairline komşuluğunda | 2 değeri 19 yerde gelişigüzel kullanılıyor |
| Yasak değerler | 3, 6, 10, 14, 18, 22, 46, 57 | 48 yer (`offgrid.txt`) |

Satır yükseklikleri çift sayıdır; `leadingDistribution: even` korunur.

### 4.6 Optik hizalama kuralları

1. **Ön ve arka kontroller ilk satıra hizalanır.** `ListTileThemeData(titleAlignment: ListTileTitleAlignment.titleHeight)` kullanılır. Onay dairesi ilk başlık satırının ortasında durur; satır uzadıkça aşağı kaymaz.
2. **Tek içerik çizgisi:** başlık, meta ve bölüm başlığı aynı sol kenardan başlar. Bölüm başlığı kart iç dolgusuna (16 + 12) hizalanır, kart kenarına değil.
3. **İkon + metin:** tek satırlı metinde merkez hizalama. Çok satırlı metinde ikon ilk satırın ortasına konur (`CrossAxisAlignment.start` + üstten `(lineHeight − icon)/2`).
4. **Daire ve kare telafisi:** dairesel glif (checkbox, kayıt noktası) aynı kutudaki kare glife göre +1 px büyük çizilir ya da merkezlenir. Ölçek bunu 20/24 ile karşılıyor.
5. **Sağ küme en çok 1 ikon + rozet.** Öncelik bayrağı, aciliyet ve durum meta satırına `AwIcon.xs` olarak iner. Başlık sütunu ≈217 pt'den ≈275 pt'ye çıkar (+%27). Bu düzen değişikliği C-05'in UX turuyla birlikte karara bağlanmalı.
6. **1.3× ve üstü:** satır "yığılmış" düzene geçer (meta alt satıra, ikonlar başlığın altına). 1.5× ve üstünde rozetler tooltip'e iner.

### 4.7 Uygulama taslağı (öneri; kod değiştirilmedi)

```dart
// theme.dart — textTheme kurulumunda (öneri)
final apple = switch (defaultTargetPlatform) {
  TargetPlatform.iOS || TargetPlatform.macOS => !kIsWeb,
  _ => false,
};
TextStyle? t(TextStyle? s, {double? size, double? lh, FontWeight? w}) {
  final fs = size ?? s!.fontSize!;
  return s?.copyWith(fontSize: fs, height: lh == null ? null : lh / fs,
      fontWeight: w, letterSpacing: awTracking(fs, apple: apple));
}
// bodyLarge: t(base.bodyLarge, lh: 22), labelMedium: t(base.labelMedium, size: 11, lh: 14, w: FontWeight.w600) …
// listTileTheme: titleAlignment: ListTileTitleAlignment.titleHeight, minVerticalPadding: AwSpace.x2,
//                titleTextStyle: textTheme.bodyLarge  (w500 kalkar)
```

Kapı (öneri, `check:type`):

- `apps/app/lib` içinde, tema, `*_pdf.dart` ve `note_docx.dart` hariç:
  - `fontSize:` ve `letterSpacing:` yasak
  - `Colors.(?!transparent)` yasak (izin listesi: `brand_mark`, `color_swatch_dot`, `image_viewer`)
  - 4'ün katı olmayan `EdgeInsets` / `SizedBox` sayıları yasak (`AwSpace.x0_5` hariç)
  - `Icon(size:)` yalnız `AwIcon.*` olabilir
- Regresyon testi: `buildAwTheme` ile `TargetPlatform.iOS` için `bodyLarge.letterSpacing ≤ 0` ve `bodySmall.letterSpacing == 0` assert edilir.

---

## 5. Kontrast (sahibin ekranındaki renkler ve token değerleri)

WCAG göreli parlaklıkla hesaplandı (`contrast.py` ile aynı formül). Sayfa arka planı = `veil` + `aurora`; leke tepe noktası = blob merkezi (en kötü durum; gerçek maruziyet kaydırma konumuna bağlı ve **ölçülmedi**).

| Çift | Değer | Eşik | Durum |
| --- | --- | --- | --- |
| D meta "Gecikti …": error `#FF5147` / kart `#151F3C` | **5.04** | 4.5 | Geçiyor (sınıra yakın) |
| D başlık onSurface `#EAF0FD` / kart | 14.21 | 4.5 | Geçiyor |
| D onSurfaceVariant `#AAB6D6` / kart | 8.02 | 4.5 | Geçiyor |
| D bölüm başlığı error / düz sayfa (`#0B112F`) | 5.74 | 4.5 | Geçiyor |
| D bölüm başlığı error / blobA tepesi (`#15295C`) | **4.34** | 4.5 | **Eşik altı** (14 pt w700 "büyük metin" sayılmaz) |
| D bölüm başlığı error / blobC tepesi (`#0D2A3B`) | 4.62 | 4.5 | Sınırda |
| L bölüm başlığı error `#D70015` / blobA tepesi (`#DAE7FF`) | **4.32** | 4.5 | **Eşik altı** |
| L bölüm başlığı error / blobB tepesi (`#E6E6FF`) | **4.39** | 4.5 | **Eşik altı** |
| D link `#3E9BFF` / blobA tepesi | 4.88 | 4.5 | Sınırda |
| D prioUrgent bayrak `#FF453A` / kart | 4.77 | 3 (ikon) | Geçiyor |
| D prioMedium `#FFC400` / kart | 10.17 | 3 | Geçiyor |
| D checkbox halkası outline `#7186B5` / kart | 4.47 | 3 | Geçiyor |
| L warning / prioMedium `#C77700` / beyaz | 3.46 | 3 ikon, **4.5 metin** | Yalnız ikon olarak geçiyor; metin olarak kullanılmamalı |
| L `Colors.amber` yıldız / chip `#F6F9FF` (`project_detail_screen.dart:238`) | **1.55** | 3 | **Kalıyor** |
| D error ↔ prioUrgent (aynı satırda iki kırmızı) | 1.06 | — | Ayırt edilemez |

Ek gözlemler:

- Görev satırında üç farklı anlam tek kırmızıda toplanıyor: geciken meta (`scheme.error`), acil zili (`scheme.error`, `task_tile.dart:428`) ve acil öncelik bayrağı (`prioUrgent`). G5 sağlanıyor (kelime ve ikon var), ama ekran bir "alarm duvarı"na dönüşüyor (C-04).
  - Öneri: meta satırında yalnız "Gecikti" kelimesi `error` rengi ve w500 olsun, tarih `onSurfaceVariant` kalsın. Bunun için `task.overdueDue` `Text.rich` olarak ikiye bölünür (i18n anahtarı ikiye ayrılır).
- `contrast.py` sayfa arka planı üzerindeki çiftleri modellemiyor (kart ve yüzey çiftleri var, aurora tepesi yok). Bölüm başlıkları ve kart dışı link metni bu yüzden kapı dışında kalıyor.

---

## 6. Bulgular

| ID | Şiddet | Bulgu | Kanıt | Önerilen düzeltme | Efor |
| --- | --- | --- | --- | --- | --- |
| T-01 | **major** | iOS'ta gövde, label ve caption rollerine Roboto için ayarlanmış pozitif tracking (+0.25…+0.5) uygulanıyor. Ekran görüntüsündeki geniş harf aralığının nedeni bu. | `theme.dart:103-111, 128-129`; `typography.dart:2104-2111`; HIG tablosu `hig-typography.txt:425-460` | §4.1 `awTracking` ve §4.2 tablosu; iOS regresyon testi | S |
| T-02 | **major** | Satır başlığı w500, `maxLines` yok ve ön/arka kontroller ortalı. Çok satırlı satırlar dağınık duruyor (C-04, C-05). | `theme.dart:188-200`; `task_tile.dart:186-195`; `list_tile.dart:975-978` | `titleAlignment: titleHeight`, w400, `maxLines: 3`; sağ küme meta satırına (§4.6-5) | S (tema) / M (küme) |
| T-03 | **major** | Bar etiketi 12/w700/+0.5 ve `overflow: visible`. "Ana Sayfa" 1.3×'te ≈75 px, yuva ≈63 px; etiket kapsül dışına taşıyor (C-01'in tipografik payı). | `theme.dart:338-346`; `home_shell.dart:466-476, 709-711`; §3.3 ölçümü | 11/14 w600 sabit, tracking ~0, bar için `withClampedTextScaling(max 1.2)`. Bar yerleşimi alt bar raporuyla birlikte ele alınmalı. | S |
| T-04 | **major** | Web, Roboto'yu `fonts.gstatic.com` adresinden indiriyor. ADR-0005 #6 ve DESIGN §3.3'teki "sıfır ağ indirmesi, tamamen çevrimdışı" iddiası web'de doğru değil. Self-host kurulumlarında kullanıcı tarayıcısı Google'a istek atıyor. | `canvaskit/fonts.dart:14-15, 116-133`; `configuration.dart:365`; `deploy.yml:169-171` ve `apps/app/Dockerfile:20` (CDN bayrağı yok) | `assets/fonts/Roboto-*.ttf` dosyalarını `fonts: - family: Roboto` olarak kaydet; motor `loadedRoboto` bayrağıyla indirmeyi atlar. Medium ve SemiBold ağırlıklarını ekle; yoksa w500/w600 sentetik çizilir (**doğrulanmalı**). `fontFallbackBaseUrl` ile `--no-web-resources-cdn` ayrıca değerlendirilsin. | S–M |
| T-05 | **major** | Kırmızı bölüm başlığı aurora tepelerinde 4.32–4.39:1 veriyor (G2 eşiği altı). Kontrast kapısı sayfa arka planını ölçmüyor. | §5 tablosu; `glass.dart:38-40, 61` (radyal blob); `home_screen.dart:699-704` | `contrast.py`'ye "metin / aurora tepesi" çiftlerini ekle. Bölüm başlığı error tonu sayfa için koyulaştırılsın (açık temada `onErrorContainer` `#99000F` ya da sayfa için ayrı `errorOnPage` tokenı) ya da başlık 15 pt'de kalırken renk yerine ikon ve kelime kullanılsın. | S |
| T-06 | **major** | `Colors.amber` favori yıldızı açık temada 1.55:1 (G2 ve G6; DESIGN §4 bunu açıkça yasaklıyor). | `project_detail_screen.dart:238` | `context.awTokens.warning` | S |
| T-07 | minor | Golden ekran görüntüleri Roboto ile çiziliyor; SF metrikleri hiçbir incelemede görünmüyor. T-01 bu yüzden kaçtı. | `test/design_screenshots_test.dart:34-44, 112-113` | iOS cihaz ya da simülatör ekran görüntüsünü tipografi değişiklikleri için DEVICE-CHECKS satırı yap. Tracking için birim testi (§4.7). | S |
| T-08 | minor | "Bölüm etiketi" (labelLarge w700 +0.4) 4 dosyada kopyalanmış; sayılar tabular değil. | §2.2 #12-15 | `sectionLabel` rolü (§4.2) | S |
| T-09 | minor | UI'da 3 ham `fontSize`, 42 ham `TextStyle(`, 230 rol `copyWith`'i var. Tip sistemi yerel olarak bükülüyor ve kapı yok. | §2.1 | `AwTextRoles` ve `check:type` kapısı | M |
| T-10 | minor | 48 ızgara dışı boşluk değeri; temanın kendisinde 3 tane (10, 14, 10). | `offgrid.txt`; `theme.dart:199, 219, 322`; `status_views.dart:262` | §4.5 tablosu; `AwSpace.x0_5`; DESIGN §4 ve `list_rhythm` testi birlikte güncellenir | M |
| T-11 | minor | 9 ayrı ikon boyutu; aynı satırda 14 ve 16 karışık; dolu ve outline karışık; Projeler ve Dosyalar siluetleri benzer. | `icon-sizes.txt`; `task_tile.dart:224-441`; `task_visuals.dart:16-28`; `sections.dart:31-46` | `AwIcon` ölçeği ve stil kuralı (§4.4) | M |
| T-12 | minor | Tabular rakam yalnız 1 yerde; DESIGN §3.3 ve L3 sayaç ve zaman için istiyor. | `month_calendar.dart:235`; `alarm_log_screen.dart:126` | §4.3 listesi | S |
| T-13 | minor | Liste yoğunluğu M3 varsayılanında (56/72) ve üstüne 6 px ritim ekleniyor; telefonda ekran başına az satır sığıyor. | `list_tile.dart:1503-1510`; `theme.dart:199` | 52/64 min yükseklik, 8 dolgu (§4.5) | S |
| T-14 | minor | Durum değişince ağırlık değişiyor (bar w500→w700); meta vurgusu w600. Ağırlık enflasyonu (w600 ×33, w700 ×21 ad hoc). | `theme.dart:340-342`; §1.3 | Ağırlık kuralı (§4.2) | S |
| T-15 | minor | Başlık tracking'i (28 pt −0.5, 24 pt −0.4) Apple'dan ~0.9 pt daha sıkı. Bu bir zevk konusu. | `theme.dart:113-120`; HIG 24/28 pt satırları | Cihazda A/B: HIG değeri, 0 ve bugünkü değer; sahip seçer | S |
| T-16 | **SAHİBE SORU** | Font ailesi değişikliği (§7). ADR-0005 #6 ve ADR-0012 "SF Pro on Apple hardware is the Liquid Glass typography" kararlarına dokunuyor. | `docs/adr/0005-alliswell-glass-design-system.md:42-43`; `docs/adr/0012-liquid-glass-v2-visual-refresh.md:74-75` | Öneri: önce T-01 (aile aynı kalır); aile değişikliği yalnız sahip isterse ve ADR ile | — |

### 6.1 Zevk konuları (2–3 yön, sahibin onayına)

- **Başlık sıkılığı:**
  - (a) HIG: 28 pt +0.38, Apple'ın kendi uygulamaları gibi ferah.
  - (b) Nötr: 0.
  - (c) Bugünkü −0.5: marka sıkılığı, landing "Dusk" ile akraba.
  - Önerim (b). Ekran görüntüsüyle karşılaştırma iOS simülatöründe yapılmalı.
- **Satır başlığı boyutu:**
  - (a) 16/22 (öneri): sütun genişliği aynı kalır.
  - (b) iOS'ta 17/22 −0.43 (HIG Body). Harf başına genişlik bugünküyle hemen hemen aynı (17×~0.5 − 0.43 ≈ 8.07 px; bugün 16×~0.5 + 0.5 ≈ 8.5 px). Daha "native" görünür ama Android ile boyut farkı oluşur.

---

## 7. SAHİBE SORU: Font ailesi değişmeli mi?

Bağlam: ADR-0005 #6 "System fonts, no webfonts… zero payload" ve ADR-0012 §74-75 "SF Pro on Apple hardware is the Liquid Glass typography". Landing ise Hallmark Dusk için Wix Madefor'u kendi sunucusundan sunuyor (`apps/landing/src/home/styles/tokens.css:23`, `fonts.css`; 4 woff2 alt kümesi toplam **65.6 KB**, latin ve latin-ext, Türkçe ı/İ/ğ/ş kapsamda).

| Seçenek | Artı | Eksi | Ağ indirmesi yok kuralı | Boyut (uygulama) | Türkçe |
| --- | --- | --- | --- | --- | --- |
| **A. Sistem fontları + T-01 (önerilen)** | ADR'lere uyar; iOS'ta Dynamic Type, Bold Text ve optik boyutlar yerel çalışır; sıfır ek yük; asıl sorunu (tracking) çözer | Landing ile app arasında tipografik süreklilik yok | Uyumlu (T-04 ile web de uyumlu hale gelir) | 0 (web: Roboto zaten bundle'da; Medium ve SemiBold için +~2×170 KB, **tahmin**) | Tam |
| B. Inter (OFL) tüm platformlarda | Platformlar arası aynı görünüm; tnum, ss ve cv özellikleri; küçük boyutta okunaklı | SF'nin yerel hissini kaybeder (ADR-0012 ile çelişir); iOS "Bold Text" erişilebilirliği elle ele alınmalı; Flutter'da değişken font ağırlık eşlemesi **doğrulanmalı** | Bundle'a gömülürse uyumlu | Statik 4 ağırlık **yaklaşık 1+ MB** (doğrulanmadı) | Tam (Latin Extended-A) |
| C. Wix Madefor (landing uyumu) tüm UI'da | Marka sürekliliği landing ↔ app | Küçük UI boyutlarında (11–13 pt) test edilmemiş; Flutter TTF/OTF ister (landing woff2 kullanıyor); değişken ağırlık davranışı **bilinmiyor**; ADR değişikliği gerekir | Gömülürse uyumlu | Bilinmiyor (TTF alt kümeleri gerekir) | Var (latin-ext) |
| D. Hibrit: Wix Madefor **Display** yalnız ≥22 pt başlıklarda, gövde sistem fontu | Marka anı yalnız başlıkta; düşük risk; landing ile ses birliği | İki aile yönetimi; ADR-0005 #6'ya kısmi istisna | Gömülürse uyumlu | Tek Display ailesi (TTF, latin + latin-ext, 2 ağırlık): **bilinmiyor, ölçülmeli** | Var |

Önerim önce **A**. Sahip landing ile süreklilik isterse **D**, ADR olarak eklenir. B ve C, O-03 KESİN ("komple değişmesin") ruhuna en uzak seçenekler.

---

## 8. Kapsam dışı ama komşu (başka raporlara)

- Alt barın yerleşimi, yüzen nesne kalabalığı ve arama ikonunun tekrarı (C-01…C-03, C-07) alt bar / UX raporunda. Burada yalnız etiket tipografisi ele alındı.
- Uzantıya ait dosya yolları bu kopyadan çıkarıldı; uzantının tasarımı anlatılmaz (I-14).

## 9. Doğrulama planı ve bilinmeyenler

| Konu | Durum | Nasıl doğrulanır |
| --- | --- | --- |
| Flutter iOS'ta SF dinamik tracking'ini motor seviyesinde uyguluyor mu? | **Bilinmiyor**; dolaylı kanıt "hayır" (`cupertino/text_theme.dart:23, 86, 97`) | Simülatörde aynı metni `UILabel` ve Flutter `Text` (letterSpacing 0) ile çizip piksel genişliği karşılaştır |
| Ekran görüntüsü cihaz genişliği | **Varsayım**: 430 pt (923×2000 oranı Pro Max ile uyuşuyor) | Gerekirse sahibe sorulmaz; demo tohumuyla simülatörde yeniden ölçülür |
| Ölçümlerde SF yerine Roboto kullanıldı | Değerler alt sınır (SF biraz daha geniş) | Simülatör ekran görüntüsü |
| Aurora tepelerinin metinle çakışma sıklığı | Ölçülmedi | Demo tohumu ile açık ve koyu temada her bölüm başlığının arkasını örnekle |
| Roboto'nun `fonts:` olarak kaydı bundle'ı ikiye katlar mı? Sentetik ağırlık? | **Bilinmiyor** | `flutter build web` → `FontManifest.json` ve `assets/` boyutu; w500/w600 görsel kontrolü |
| Inter ve Wix Madefor TTF boyutları | **Bilinmiyor / tahmin** | Yalnız sahip B, C ya da D'yi seçerse ölç |

## 10. Kaynaklar

- Apple HIG Typography: https://developer.apple.com/design/human-interface-guidelines/typography (JSON: https://developer.apple.com/tutorials/data/design/human-interface-guidelines/typography.json, yerel kopya ham kanıt)
- Material 3 tip ölçeği: https://m3.material.io/styles/typography/type-scale-tokens (değerler Flutter 3.47.7 `typography.dart:2087-2147` üretilmiş tokenlarından)
- Flutter `TextStyle` Cupertino proxy aileleri: https://api.flutter.dev/flutter/painting/TextStyle/TextStyle.html
- Flutter web yazı tipi yedeği ve CDN: SDK `bin/cache/flutter_web_sdk/lib/_engine/engine/configuration.dart:363-365`, `canvaskit/fonts.dart:12-15, 113-133`
