> **Depodaki kopya (2026-11-07, E35 kaydı):** uzantıya özgü tasarım ayrıntısı çıkarıldı (uzantı bulguları uzantı deposunda); turun iç çalışma dosyalarına ve ham kanıta verilen yollar düz metne çevrildi ("ham kanıt" = turun çalışma alanında kalan dosya; depoda yok). Bulgu kimlikleri değişmedi. Özet: [README.md](README.md).

# SF Pro ile tracking doğrulaması (C-04, O-10 takip)

> Son güncelleme: 2026-11-07 — CEO tasarım/UX turu
> Kaynak: iOS 27.2 simülatörü (iPhone 18 Pro Max, Mac mini, T3 `device_open` + `agent-device`), AllisWell 1.18.2 (build 49, debug) demo tohumu (`demo@alliswell.space`, `scripts/seed-demo.mjs`; gerçek kullanıcı verisi yok), simülatör içinde çalışan CoreText/UIKit ölçüm aracı (`sfmeasure.swift`), `apps/app/lib/src/theme/theme.dart:103-130, 188-198, 336-346`, `apps/app/lib/src/features/tasks/ui/task_tile.dart:186, 305-322, 562-570`, `apps/app/lib/src/features/home/home_screen.dart:688-706`, `apps/app/lib/src/notifications/alarm_banner.dart:56-61`, `apps/app/lib/src/features/auth/ui/auth_scaffold.dart:46-51`, `typography-system.md` §1.4, §4.1, §4.2, §9, Apple HIG tracking tablosu (aynı raporun ham kanıt).

Ham materyal (3x ekran görüntüleri, mürekkep kutuları, `sfmeasure.swift`, `measure_screenshot.py`, `compare.py`, `glass_type_v1.py`, `wrap_sim.py` ve JSON çıktıları) tur çalışma alanında kaldı (depoda yok); yöntem §1'de.

---

## 0. Kısa sonuç

1. **Flutter (3.47.7, iOS 27.2 simülatörü) SF'nin dinamik tracking'ini uygulamıyor.** Ekrandaki genişlik her ölçülen dizede "SF tracking 0 + Flutter letterSpacing" modeline oturuyor (16 pt'de 12 satırın hepsi −0.74…+0.08 pt; ölçüm hatası ±0.67 pt). "SF dinamik tracking + letterSpacing" modeli 16 pt'de sistematik olarak 3–8 pt dar kalıyor (§3).
2. Bu yüzden iOS'ta bugünkü net fark **16 pt'de +0.81 pt/harf** (= +0.5 − (−0.31)), **14 pt'de +0.40**, **12 pt'de +0.4/+0.5**. Ölçümden geri hesaplanan değerler: 16 pt +0.77…+0.82, 14 pt +0.40, 12 pt +0.37…+0.44 pt/harf (`comparison.json`, `implied_extra_per_glyph_over_native`). typography-system.md §1.4'teki teşhis (+51/1000 em) **doğrulandı**. §1.4'teki "SF ile değerler alt sınır" notu artık gereksiz.
3. Satır başlıkları bugün yerel iOS'tan (UILabel, aynı boyut ve ağırlık) **%9.4–11.3 daha geniş**. Gövde (14 pt) %6.3, bar etiketi %5.7–7.4 daha geniş (`glass_type_v1.json`, `today_vs_native_pct`).
4. **letterSpacing: 0 tek başına yetmez.** 16 pt satır başlığında farkın yalnız %5.3–6.2'sini geri alır ve metin hâlâ yerelden ≈%3.6 geniş kalır. HIG değeri (−0.31) yerel UILabel genişliğini **0.02–0.15 pt** farkla birebir üretir. Flutter dinamik tracking uygulamadığı için çift sayım yok. Bu yüzden §4.1 `awTracking` tablosu Apple ailesinde **doğru düzeltme**.
5. Glass Type v1 (§4.2) SF ile yeniden hesaplandı: satır başlığı **−%10.5…−12.5**, meta **−%12…−15**, bar etiketi **−%14…−16**, bölüm başlığı yalnız **−%3** (boyutu 14'ten 15'e çıktığı için). Demo başlıklarında satır sayısı değişmiyor. Geciken satırların meta satırı ise tahmini sütun genişliğinde **2 satırdan 1 satıra** iniyor (§4.3).

---

## 1. Yöntem

| Adım | Ne yapıldı | Kanıt |
| --- | --- | --- |
| Cihaz | iPhone 18 Pro Max simülatörü (440×956 pt, 3x), iOS 27.2, Mac mini. `device_open` ile açıldı, uygulama aynı Mac'teki iPhone 18 Pro simülatöründe kurulu olan 1.18.2 (build 49) `Runner.app`'ten kuruldu. | `home-3x.png` (1320×2868) |
| Sunucu | Bu thread'in yerel API'si (`:3100`, demo hesabı tohumlu), Mac'in `localhost:3000` adresine ters SSH tüneliyle bağlandı (debug build varsayılan sunucusu). Uygulamadaki "Server" diyaloğu adresi kaydetmedi (bkz. §6). | — |
| Ekran ölçümü | Bilinen demo dizeleri için kutu içinde mürekkep (ink) genişliği bulundu: kutu medyan rengine uzaklığı, kutu içindeki en büyük uzaklığın %45'ini aşan sütunlar. Belirsizlik kenar başına ±1 px, genişlik başına ±0.67 pt. | `measure_screenshot.py`, `screenshot_ink.json`, `home-3x-ink-boxes.png` |
| SF ölçümü | Swift aracı **simülatörün içinde** (`simctl spawn`) çalıştırıldı. Bu sayede iOS 27.2'nin `.SFUI-*` sistem fontu ve `trak` tablosu kullanıldı, macOS'un SFNS'i değil. Her dize, boyut ve ağırlık için şu varyantlar ölçüldü: `dyn` (UIFont.systemFont, öznitelik yok = UILabel), `kern_X`, `tracking_X`, `at12` (font 12 pt'de yapılıp boyuta ölçeklenmiş = **tracking 0**), `at3x` (font 3× boyutta yapılıp geri ölçeklenmiş). | `sfmeasure.swift`, `sf_widths.json` |
| Kalibrasyon | "HHHH…" (20 harf) 11–34 pt arasında ölçüldü: `dyn − at12` farkı harf başına **HIG tablosunun birebir aynısı** (11 +0.064 · 12 0 · 13 −0.076 · 14 −0.150 · 15 −0.234 · 16 −0.312 · 17 −0.432). Yani iOS'ta sistem fontunun ilerlemeleri dinamik tracking'i zaten içeriyor ve `at12` geçerli bir "tracking 0" tabanı. ≥20 pt'de SF Display optik boyutuna geçtiği için bu taban kullanılamaz (ölçümler o boyutta yapılmadı). | `sf_calibration.json` |
| Model | Flutter'ın genişliği = taban mürekkep + LS × (glif − 1). Mürekkep genişliğinde son harften sonraki aralık sayılmaz. | `compare.py` |

`kern`/`tracking` öznitelikleri karar için kullanılmadı. `.kern = 0` iOS'ta çift kerning'i kapatıyor ve `.tracking = 0` "varsayılan" anlamına geliyor (`sf_widths.json`'da `tracking_0.0 == dyn`). Bu iki öznitelik "tracking 0" tabanı vermiyor. Ham değerleri JSON'da duruyor.

---

## 2. Ölçülen genişlikler (3x ekran görüntüsü, pt)

Rol eşlemesi koddan: satır başlığı `bodyLarge` 16/w500/+0.5 (`theme.dart:193-195`); ipucu ve auth alt başlığı `bodyLarge` 16/w400/+0.5 (`theme.dart:211`, `auth_scaffold.dart:49`); banner `bodyMedium` 14/w400/+0.25 (`alarm_banner.dart:58`); meta 14/w600/+0.25 (`task_tile.dart:318-322`); bölüm başlığı `labelLarge` 14/w700/+0.4 (`home_screen.dart:698-706`); etiket `bodySmall` 12/w500/+0.4 (`task_tile.dart:567-570`); bar etiketi `labelMedium` 12/w700/+0.5 (`theme.dart:338-346`).

| Dize | Rol | Ölçülen | UILabel (yerel) | SF dinamik + LS | **SF tracking 0 + LS** | 3x font + LS | En yakın |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Send Acme the | 16/500 | 120.33 | 111.14 | 117.14 | **120.89** | 111.55 | t0+LS (−0.56) |
| September invoice | 16/500 | 149.67 | 137.11 | 145.11 | **150.11** | 137.58 | t0+LS (−0.44) |
| Reply to the App | 16/500 | 133.00 | 121.02 | 128.52 | **133.21** | 121.10 | t0+LS (−0.21) |
| Store review team | 16/500 | 144.67 | 132.41 | 140.41 | **145.41** | 131.52 | t0+LS (−0.74) |
| Waiting for the counter- | 16/500 | 193.67 | 175.51 | 187.01 | **194.20** | 175.45 | t0+LS (−0.53) |
| top quote | 16/500 | 77.00 | 70.74 | 74.74 | **77.24** | 70.20 | t0+LS (−0.24) |
| Call the plumber about | 16/500 | 184.00 | 167.48 | 177.98 | **184.54** | 167.64 | t0+LS (−0.54) |
| the kitchen leak | 16/500 | 128.67 | 116.96 | 124.46 | **129.15** | 117.24 | t0+LS (−0.48) |
| Sketch the empty states | 16/500 | 196.33 | 179.09 | 190.09 | **196.97** | 178.81 | t0+LS (−0.64) |
| Quick add a task… | 16/400 | 144.00 | 131.31 | 139.31 | **144.31** | 128.60 | t0+LS (−0.31) |
| Sign in to your space | 16/400 | 166.33 | 150.00 | 160.00 | **166.25** | 149.04 | t0+LS (+0.08) |
| Password | 16/400 | 73.00 | 67.29 | 70.79 | **72.98** | 67.07 | t0+LS (+0.02) |
| Notifications are off — nothing can reach you. | 14/400 | 310.00 | 291.94 | 303.19 | **309.95** | 277.88 | t0+LS (+0.05) |
| Overdue — Nov 5, | 14/600 | 123.33 | 117.38 | 121.13 | **123.38** | 113.87 | t0+LS (−0.05) |
| Overdue — Nov 6, | 14/600 | 123.67 | 117.65 | 121.40 | **123.66** | 114.23 | t0+LS (+0.01) |
| Overdue · 2 | 14/700 +0.4 | 82.67 | 76.26 | 80.26 | **81.61** | 76.00 | t0+LS (+1.06) |
| No date · 5 | 14/700 +0.4 | 78.00 | 71.24 | 75.24 | **76.59** | 71.08 | t0+LS (+1.41) |
| #finance | 12/500 +0.4 | 52.33 | 49.65 | 52.45 | 52.45 | 49.06 | ikisi aynı (−0.12) |
| #review | 12/500 +0.4 | 47.33 | 45.05 | 47.45 | 47.45 | 44.04 | ikisi aynı (−0.12) |
| #errand | 12/500 +0.4 | 47.00 | 44.75 | 47.15 | 47.15 | 43.56 | ikisi aynı (−0.15) |
| Home (bar) | 12/700 +0.5 | 35.00 | 33.67 | 35.17 | 35.17 | 33.49 | ikisi aynı (−0.17) |

Kaynak: `comparison.json`.

Okuma:
- **16 ve 14 pt'de karar kesin.** "Dinamik + LS" ile "t0 + LS" arasındaki fark 16 pt'de 3.5–7.2 pt, ölçüm hatasının 5–10 katı. Ölçüm her satırda t0+LS'ye düşüyor.
- **12 pt'de iki model aynı.** HIG'de 12 pt tracking 0, dolayısıyla bu satırlar ayırt edici değil. Yalnız "LS tam uygulanıyor" sonucunu doğruluyorlar.
- **3x model (Skia'nın fontu cihaz pikseli boyutunda istemesi) dışlandı.** Her satırda 6–32 pt uzakta.
- **Bölüm başlıkları +1.1/+1.4 pt sapıyor** (diğerlerinden büyük). Nedeni **bilinmiyor**. w700'ün Flutter'da farklı bir örneğe eşlenmesi ya da `·` glifinin farklı çizilmesi olabilir. Sonucu değiştirmiyor, çünkü dinamik model daha da uzakta (+2.4/+2.8).

---

## 3. Bulgular

| # | Şiddet | Bulgu | Kanıt | Önerilen düzeltme | Efor |
| --- | --- | --- | --- | --- | --- |
| SF-01 | **major** | iOS'ta Flutter SF'yi dinamik tracking'siz (12 pt aralığıyla) çiziyor ve M3 letterSpacing'i bunun **üstüne** ekliyor. Net fark yerel iOS'a göre 16 pt +0.81, 14 pt +0.40, 12 pt +0.4/+0.5 pt/harf. Sahibin "geniş harf aralığı" şikâyetinin (C-04) nedeni bu ve ölçüldü. typography-system.md T-01 **doğrulandı**. | §2 tablosu; `comparison.json`; `sf_calibration.json`; `theme.dart:103-111, 128-129` | typography-system.md §4.1 `awTracking` (Apple: HIG tablosu). Flutter dinamik tracking uygulamadığı için HIG değeri **çift sayılmıyor**. | S |
| SF-02 | **major** | `letterSpacing: 0` ara çözüm olarak yetersiz. 16 pt satır başlığında genişliğin yalnız %5.3–6.2'sini geri alıyor ve metin yerelden hâlâ ≈%3.6 geniş kalıyor. HIG −0.31 ise UILabel'ı 0.02–0.15 pt farkla birebir tutturuyor. | `glass_type_v1.json` ("rowTitle w500 tracking A/B" satırları) | Apple ailesinde 0 değil, HIG değeri kullanılsın. Android/web için §4.1'in Roboto tablosu ayrı kalsın. | S |
| SF-03 | minor | Golden ekran görüntüleri Roboto ile çizildiği için bu fark hiçbir testte görünmüyor (typography-system.md T-07). Bu ölçüm, bir sonraki tipografi değişikliğinde tekrarlanabilir bir yöntem veriyor. | `measure_screenshot.py`, `sfmeasure.swift`, `compare.py` | Regresyon: (1) `awTracking` için birim testi (iOS platformunda 16 pt → −0.31); (2) tipografi işi için DEVICE-CHECKS satırı. Simülatörde "Sign in to your space" ölçülür ve beklenen değer UILabel ±1 pt, yani 150.0 pt (bugün 166.3). | S |
| SF-04 | minor | Bölüm başlığı (14/w700) modelden +1.1…+1.4 pt sapıyor, nedeni bilinmiyor. | §2 son iki 14 pt satırı | Glass Type v1'de rol zaten 15/w600 oluyor. Değişiklikten sonra aynı yöntemle yeniden ölçülsün. | S |

ADR uyumu: ADR-0005 #6 "system fonts … tuned weights/tracking" (`docs/adr/0005-alliswell-glass-design-system.md:42-43`), ADR-0012 "SF Pro on Apple hardware" ve DESIGN §3.3 (`docs/DESIGN.md:107-108`, "Weights/tracking tuned in theme.dart"). Önerilen değişiklik yalnız tracking ayarı; aile SF kalıyor ve iOS yerel görünüme yaklaşıyor. **Çelişki yok, SAHİBE SORU gerekmiyor.** Font ailesi sorusu (typography-system.md §7, T-16) bu ölçümden etkilenmiyor ve açık kalıyor.

---

## 4. Glass Type v1 (§4.2): SF ile beklenen kazanç

Model: Flutter-iOS ilerlemesi = SF tracking 0 ilerlemesi + LS × glif (son harften sonraki aralık dahil; satır kırmada bu kullanılır). Değerler ilerleme (advance) genişliği, pt cinsinden. Kaynak: `glass_type_v1.json`.

### 4.1 Rol bazında

| Rol | Bugün (boyut/ağırlık/LS) | v1 (Apple) | Örnek dize | Bugün | v1 | Δ | Bugün / yerel |
| --- | --- | --- | --- | --- | --- | --- | --- |
| rowTitle | 16/500/+0.5 | 16/400/−0.31 | 9 demo satırı | — | — | **−%10.5…−12.4** | +%9.4…+11.1 |
| rowTitle (TR) | 16/500/+0.5 | 16/400/−0.31 | "Müşteri toplantısı için sunum dosyasını hazırla ve paylaş" (örnek cümle) | 459.20 | 401.80 | −57.40 (**−%12.5**) | +%11.2 |
| rowTitle (TR) | aynı | aynı | "Haftalık bütçe tablosunu güncelle, ekibe ilet" (örnek cümle) | 361.13 | 315.88 | −45.26 (**−%12.5**) | +%11.3 |
| bodyLarge input/ipucu | 16/400/+0.5 | 16/400/−0.31 | Quick add a task… / Sign in to your space / Password | 147.16 / 168.49 / 76.26 | 133.39 / 151.48 / 69.78 | −%9.4 / −%10.1 / −%8.5 | +%9.3…+11.3 |
| bodyMedium | 14/400/+0.25 | 14/400/−0.15 | banner (EN / TR) | 312.65 / 308.61 | 294.25 / 290.21 | −%5.9 / −%6.0 | +%6.3 |
| meta | 14/600/+0.25 | 13/400/−0.08 | Overdue — Nov 5, / "Gecikti — 5 Kas, 09:47" | 125.88 / 160.75 | 108.63 / 137.24 | −%13.7 / −%14.6 | +%5.4…+5.8 |
| metaStrong | 14/600/+0.25 | 13/500/−0.08 | Overdue — Nov 5, | 125.88 | 110.52 | −%12.2 | +%5.4 |
| sectionLabel | 14/700/+0.4 | 15/600/−0.23 | Overdue · 2 / Geciken · 2 | 83.66 / 80.62 | 81.06 / 77.88 | −%3.1 / −%3.4 | +%7.6…+7.9 |
| etiket (#tag) | 12/500/+0.4 | 12/500/0 | #finance | 53.63 | 50.43 | −%6.0 | +%6.3 |
| bar etiketi | 12/700/+0.5 | 11/600/+0.06 | Home / Ana Sayfa | 37.23 / 64.94 | 31.88 / 54.59 | −%14.4 / **−%15.9** | +%5.7…+7.4 |

Not: Ağırlık değişikliği (w500→w400) satır başlığı kazancının ≈2–3 puanını veriyor. Yalnız tracking (w500 kalarak HIG −0.31) kazancı −%8.6…−10.1 (`glass_type_v1.json`, A/B satırları).

typography-system.md §1.4'teki Roboto tahmini ("Apple tracking'ine göre %12 uzun") SF'de **%9.4–11.3** çıkıyor. Yön ve büyüklük doğru, Roboto biraz abartmış. §1.4'teki "Ölçümler Roboto ile, değerler alt sınır" ifadesi SF için geçerli değil: SF farkı biraz daha küçük.

### 4.2 Bar etiketi (T-03 ile bağlantı)

"Ana Sayfa" bugün 1.0×'te 64.94 pt (SF). typography-system.md §0-3'te Roboto ile ≈59 px ölçülmüştü, SF 6 pt daha geniş. v1 ile 54.59 pt. 1.3× ölçekte kabaca ×1.3 alınırsa bugün ≈84 pt, v1 ≈71 pt olur (doğrusal tahmin, ölçülmedi). Rapordaki ≈63.6 pt yuva genişliği için v1 tek başına 1.3× taşmayı **çözmüyor**. T-03'teki `withClampedTextScaling` ve bar yerleşimi (alt bar raporu) hâlâ gerekli.

### 4.3 Satır kırılımı (tahmin)

`wrap_sim.py` demo başlıklarını açgözlü kelime kırma ile sarar. Önce sütun genişliği W, ekrandaki kırılımları üreten aralıktan bulunur, sonra v1 ile yeniden sarılır.
- 5 demo başlığının hepsi bugün 2 satır. v1'de de 2 satır kalıyor, yalnız kırılım noktası kayıyor (ör. "Waiting for the counter-top | quote"). Başlık satır sayısında kazanç bu örneklerde **yok**. Kazanç sınıra yakın başlıklarda görülür: başlık başına ≈%12 daha fazla metin sığar.
- **Meta satırı:** "Overdue — Nov 5, 9:47 AM" bugün 189.4 pt ve ekranda 2 satıra kırılıyor. v1'de (13/w400) 163.3 pt, "…Nov 6, 11:47 AM" ise 194.5 → 167.3 pt (`sf_meta_widths.json`). Sütun genişliği ekrandan ≈177–182 pt tahmin ediliyor: başlık solu x=280 px, sağdaki kümenin solu x=860/873 px, ListTile M3 varsayılanı `horizontalTitleGap` 16 (temada değiştirilmemiş, `theme.dart:188-198`). Bu tahminle iki geciken satırın meta satırı **1 satıra iniyor** ve her satır ≈20 pt kısalıyor. Yalnız `letterSpacing: 0` (14/w600) 183 pt, HIG (14/w600 −0.15) ≈179.8 pt verir; ikisi de 177 pt'lik sütunda hâlâ kırılır. Bu kazancı 13 pt **meta rolü** getiriyor. Sütun genişliği ölçülmedi, tahmindir; değişiklikten sonra cihazda doğrulanmalı.

---

## 5. typography-system.md'ye etkisi

| Yer | Durum |
| --- | --- |
| §1.4 "Flutter SF dinamik tracking'ini uyguluyor mu? … dolaylı kanıt 'hayır'" | **Ölçüldü: hayır** (bu belge §2). |
| §1.4 "+51/1000 em fazla", "14 pt'de +0.25'e karşı −0.15", "12 pt'de +0.4'e karşı 0" | **Doğrulandı.** Ölçümden geri hesaplanan değerler sırasıyla +0.77…+0.82 pt, +0.40, +0.37…+0.44. |
| §1.4 "satırı %12 uzatıyor" (Roboto) | SF'de **%9.4–11.3**. |
| §4.1 Apple tablosu | Doğru taban: Flutter + HIG değeri = UILabel (±0.15 pt). |
| §9 satır 1 ve satır 3 | Kapanabilir; kanıt bu belge. |
| ux-shell-mobile.md §6 (aynı sınır) | Tracking kısmı kapandı. Bar yerleşimi ölçümleri bu işin kapsamında değil. |

---

## 6. Bilinmeyenler ve sınırlar

- **Fiziksel cihaz:** Ölçüm simülatörde yapıldı. Simülatör, Impeller'ın iOS yolunu ve iOS 27.2 runtime fontlarını kullanıyor; fiziksel iPhone'da farklı olması beklenmez ama **ölçülmedi**.
- **Release build:** Kurulu uygulama debug build. Metin yerleşimi debug ve release'te aynı motoru kullanıyor; release ayrıca ölçülmedi.
- **≥20 pt başlıklar:** SF Display optik boyutuna geçtiği için 12 pt tabanı geçersiz, ölçülmedi. T-15 başlık tracking A/B'si ayrı bir cihaz ölçümü ister.
- **Dil:** Uygulama İngilizce açıldı (simülatör dili Japonca, uygulama metinleri EN). Türkçe dizeler yalnız CoreText ile hesaplandı, ekranda ölçülmedi. Model dilden bağımsız olduğu için sonuç geçerli.
- **Bölüm başlığı sapması** (SF-04): nedeni bilinmiyor.
- **Ayrı gözlem (kapsam dışı, doğrulanmadı):** Giriş ekranındaki "Server" diyaloğu `http://100.70.180.23:3100` adresini Kaydet'e ve klavyedeki Done'a basınca kapandı ama adresi kaydetmedi; etiket `http://localhost:3000` kaldı (`server_url_sheet.dart:45-70`). Sebep ölçülmedi. agent-device ile dokunma zamanlaması da olabilir. İnsan eliyle tekrar denenmeli; tekrarlanırsa ayrı bir hata kaydı açılmalı.

## 7. Temizlik

- Simülatör `device_close` + `shutdown: true` ile kapatıldı. Kurulan uygulama simülatörden kaldırıldı.
- Mac'teki geçici derleme klasörü (`~/sfmeasure-tmp-followup3`) silindi.
- Ters SSH tüneli (`t3-resource` r-1a306a4df1e3) durduruldu.
- Diğer thread'in iPhone 18 Pro simülatörüne ve `alliswell-ceo-api` kaynağına dokunulmadı. API'ye yalnız demo hesabıyla okuma ve giriş istekleri gitti.
