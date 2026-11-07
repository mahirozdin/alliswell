> **Depodaki kopya (2026-11-07, E35 kaydı):** uzantıya özgü tasarım ayrıntısı çıkarıldı (uzantı bulguları uzantı deposunda); turun iç çalışma dosyalarına ve ham kanıta verilen yollar düz metne çevrildi ("ham kanıt" = turun çalışma alanında kalan dosya; depoda yok). Bulgu kimlikleri değişmedi. Özet: [README.md](README.md).

> Son güncelleme: 2026-11-07 — tasarım turu
> Kaynak: Mobbin (MCP, 26 arama: iOS ekran 17, web ekran 6, web bölüm 3; 48 referans) + sahip brief'i + sahibin iPhone ekran görüntüsü (yalnız düzen; metni kopyalanmadı) + `docs/DESIGN.md` §1–§4, §16, §22–§24, §32–§34, §40 + `apps/app/lib/src/theme/{tokens,theme}.dart` + `apps/app/lib/src/screens/home_shell.dart` + `docs/STATE.md` "Sahip kararları" + repo içi demo ekran görüntüleri (`screenshots/ios`, `screenshots/web`, `screenshots/sales`, `screenshots/ee`; Temmuz–Ekim, ham kanıt boştu)

# AllisWell — Mobbin'e dayalı iyileştirme spec'i (Glass korunur)

**Kapsam kuralı (O-03, KESİN):** Yeniden tasarım yok. AllisWell Glass'ın G1–G8 ilkeleri, token'ları,
yüzen kapsül + yuvarlak arama düğmesi (ADR-0055), aurora zemin, dairesel onay kutusu, kapsül
düğmeler ve satır başına kart kimliği kalır. Bu belge **geometriyi, tipografiyi, yoğunluğu ve yüzen
nesne sayısını** düzeltir. Bağlayıcı bir kararla çelişen her öneri **[SAHİBE SORU]** diye işaretli.

Referans görselleri ve görsel pano tur çalışma alanında kaldı (telif; depoya kopyalanmadı); bu belgede yalnız Mobbin bağlantıları var.
Mobbin'de **bulunamayanlar**: Apple Reminders ve Microsoft To Do (iki aramada da çıkmadı). **Adıyla
aranmayanlar**: Sunsama, Akiflow, Bear, Height, Linear Asks, Freshdesk, Plane, AppFlowy, Vikunja,
Cal.com, Immich. Bunların yerine aynı deseni taşıyan Mobbin uygulamaları kullanıldı.

---

## 0. Teşhis: alt bar neden "kaymış" görünüyor (koddan ölçüldü)

| # | Gözlem (sahibin ekranı, C-01…C-07) | Kök neden (kod) |
| --- | --- | --- |
| K1 | Seçili hap sola kaymış, ikonlar eşit durmuyor | Kapsülün içinde Material 3 `NavigationBar` var (`home_shell.dart:448`). M3 göstergesinin genişliği **sabit 64 pt**. 393 pt'lik telefonda bir sekme yuvası `(393 − 2·12 − 8 − 64 − 2·12) / 5 ≈ 54,6 pt`. 64 pt'lik hap 54,6 pt'lik yuvaya sığmıyor, taşıyor. Hızlı Erişim düğmesi bar satırına yerleşince (`AwBubbleDock.width` 72) yuva ~40 pt'ye iner. |
| K2 | "Ana Sayfa" etiketi kapsülün dışına, alt kenarına düşüyor | Tema bar yüksekliğini **64'e** indiriyor (`theme.dart:325`; M3 varsayılanı 80). Hap 32 + boşluk + 16 pt etiket bu yüksekliğe sığmıyor, etiket kapsülün alt kenarına kayıyor. Ayrıca etikete `overflow: TextOverflow.visible` verilmiş (`home_shell.dart:476`). |
| K3 | Etiketli sekmenin ikonu yukarıda, etiketsiz komşuları ortada: "dikey kayma" | `onlyShowSelected`: yalnız seçili sekme etiket taşıyor, bu yüzden ikonu yukarı itiliyor. Aynı satırda iki farklı ikon merkez çizgisi oluşuyor. |
| K4 | 6 bölümlü uzantı ekranında sekmeler çok sıkışık | 6 sekme + arama + yerleşik düğme: yuva ≈ `(393 − 24 − 8 − 64 − 72 − 24) / 6 ≈ 33 pt` → **G4 (≥ 44 pt) ihlali**. |
| K5 | 5 yüzen nesne; mikrofon bölüm başlığını örtüyor | Kapsül + arama düğmesi + "+" FAB (sağ) + AI FAB (sol, `centerFloat` + `spaceBetween`) + Hızlı Erişim balonu. Sol alt köşedeki AI FAB, sola hizalı bölüm başlıklarının ("Bugün · 1") tam üstüne düşüyor. |
| K6 | İçerik barın altından geçerken solmuyor | `extendBody: true` var ama alt kenarda örtü/geçiş yok. Cam yalnız kapsülün içinde; nesnelerin arasından ham içerik görünüyor. |
| K7 | Gövde metninde geniş harf aralığı | `Typography.material2021(...).englishLike` M3 aralıklarını getiriyor: bodyLarge **+0,5**, bodyMedium +0,25, titleMedium +0,15, labelMedium/Small +0,5. SF Pro'nun 16 pt'deki doğal değeri **−0,31**. Fark karakter başına ~0,8 pt. Flutter iOS sistem fontuna izlemeyi otomatik uygulamaz; Cupertino'nun kendi varsayılanı bu yüzden elle −0,41 verir. |
| K8 | Kapsül kenarı ile kart kenarı hizasız | Kapsül 12 pt'den, kartlar ~15–16 pt'den başlıyor. Ortak bir oluk (gutter) yok. |

---

## 1. Genel tasarım dili notları (Glass korunarak)

### 1.1 Izgara ve boşluk
- **Tek telefon oluğu: 16 pt** (`AwSpace.x4`); 430 pt ve üstünde 20. İçerik kartları, kapsül, arama düğmesi
  ve FAB'lar aynı dikey çizgilerden başlar ve biter (K8). Bugünkü 12 pt'lik krom kenar boşluğu 16 olur.
- 4 pt ızgarası aynen kalır. Dikey ritim: bölüm başlığı üstte 24, altta 8; satırlar arası 6
  (`kAwListRowPadding` 3+3 aynen).
- Kart iç boşluğu bugün ~24 pt. Yeni değerler: satırda **dikey 10, sağda 12**; solda onay hücresi 44 pt.

### 1.2 Tipografi ölçeği (sistem fontu kalır)
Değişiklik `theme.dart` içindeki `textTheme`'de yapılır; ekranlara tek tek `fontSize` yazılmaz (§3.3). Harf
aralığı yalnız Apple'da negatif olur. Roboto/Segoe/web için 0 (M3'ün pozitif değerleri sıfırlanır).

| Rol (textTheme) | Bugün (M3 2021) | Öneri: boyut/satır · ağırlık · aralık (Apple / diğer) | Nerede |
| --- | --- | --- | --- |
| headlineSmall | 24/32 · w700 · −0,4 | 24/30 · w700 · −0,4 / −0,2 | detay başlığı, büyük başlık |
| titleLarge | 22/28 · w700 · −0,3 | 22/28 · w700 · −0,35 / 0 | uygulama çubuğu başlığı |
| titleMedium | 16/24 · w600 · +0,15 | 16/22 · w600 · −0,3 / 0 | sayfa ve kart başlıkları |
| titleSmall | 14/20 · w600 · +0,1 | **15/20 · w700 · −0,2 / 0** | **bölüm başlıkları** (Geciken/Bugün/Yarın) |
| bodyLarge | 16/24 · +0,5 | 16/24 · w400 · **−0,3 / 0** | uzun metin (not, açıklama) |
| *AwText.rowTitle* (yeni, tema eki) | — | **16/22** · w400 · −0,3 / 0 | görev/not satırı başlığı |
| bodyMedium | 14/20 · +0,25 | 14/20 · −0,15 / 0 | ikincil metin |
| bodySmall | 12/16 · +0,4 | **13/18** · w400 · −0,08 / 0 · **tabular** | meta satırı |
| labelLarge | 14/20 · w600 · +0,1 | 15/20 · w600 · −0,2 / 0 | düğmeler |
| labelMedium | 12/16 · +0,5 | 12/16 · w600 · 0 | çipler, sekme etiketi (11/13 w600) |
| labelSmall | 11/16 · +0,5 | 11/13 · w600 · +0,06 / +0,1 | rozetler, sayaçlar |

- **Tabular rakam** (`FontFeature.tabularFigures()`): tarih, saat, sayaç, dosya
  boyutu. §3.3 bugün bunu yalnız gün numarası ve zamanlayıcı için söylüyor; kapsam genişler.
- **Türkçe**: metinler İngilizceden ortalama %20–30 uzun ("Home" 4, "Ana Sayfa" 9 karakter). Kurallar:
  sabit genişlikte metin kutusu yok; tek satırlık etiketlerde `maxLines: 1` + üç nokta + tooltip; **büyük harf
  dönüşümü yok** (`toUpperCase` dile bakmadan "i"yi "I" yapar). Bölüm başlıkları cümle düzeninde yazılır.
- Dinamik tip: 130 %'de her ekran kırılmadan çalışır. Sekme etiketleri 1,3× ile sınırlanır; daha büyük
  boyutta iOS'un "large content viewer" deseni kullanılır (uzun basınca büyük etiket balonu).

### 1.3 İkon boyutu ve optik hizalama
- Boyutlar: **24** (gezinme, uygulama çubuğu; 44 pt dokunma kutusunda), **20** (satır başı, ayar satırı),
  **16** (meta satırı), **14** (13 pt metnin yanındaki satır içi glif).
- Seçili durum = dolu ikon, seçili olmayan = çizgi ikon. Çiftler her yerde aynı aileden gelir.
- Optik kural 1: 24'lük kutuda glifin 2 pt iç boşluğu vardır. Satır başı ikonları metin kenarına göre
  −2 pt kaydırılır, böylece hiza kutuya değil glife göre olur.
- Optik kural 2: **onay dairesi ilk satıra hizalanır**, satırın dikey ortasına değil (C-05). 22 pt'lik daire
  44 pt'lik dokunma kutusunda durur; merkezi ilk satırın merkezindedir (satır yüksekliği 22 → merkez y = 11).
- Optik kural 3: kapsül, arama düğmesi ve FAB'lar **aynı merkez çizgisinde** durur, yükseklikleri eşittir (K3).
- Cam üstündeki ikonlar seçili değilken de `onSurfaceVariant` yerine `onSurface` (%80) alır: arka plan
  değiştiği için ≥ 3:1 kontrast (G2) güvenceye alınır. `contrast.py` cam tonu üstünde ölçer.

### 1.4 Hareket (G8 içinde)
- Sekme değişimi: hap 220 ms `easeOutCubic` ile kayar; ikon çizgiden dolguya 150 ms'de geçer.
- Aşağı kaydırma > 24 pt: FAB'lar 150 ms içinde 16 pt aşağı iner ve %90'a küçülür (opaklık animasyonu yok,
  §20 C3). Yukarı kaydırınca ya da 600 ms durunca geri gelir. Azaltılmış harekette anında değişir.
- Alt örtü sabittir, animasyonu yoktur.

### 1.5 Alt örtü (scrim): bütün yönlerde ortak
- Sayfa zemininin rengiyle (`veil` + aurora ortalaması) bir gradyan. Başlangıç: kapsülün üstünden 24 pt
  yukarıda %0; bitiş: ekran altında %92. Cam değildir, metnin altına girmez (G1 korunur). İçerik kroma
  çarpmak yerine solarak kaybolur (C-07; Todoist [f0a29ccb](https://mobbin.com/screens/f0a29ccb-611d-4f46-a806-f741c8489ae9)).

---

## 2. Mobil alt navigasyon + yüzen düğmeler: 3 yön

**Ortak taban (A, B ve C'de aynı): T1–T8**
- **T1** Kapsülde M3 `NavigationBar` yerine kendi `AwTabCapsule` bileşenimiz. Eşit yuvalar; hap yuvanın
  içinde kalır, asla taşmaz (K1). Semantik `NavigationBar` gibi kurulur: her sekme `selected` bildirir ve
  "sekme 2 / 5" okunur.
- **T2** Etiket hiçbir zaman kapsülün dışına çıkmaz. `TextOverflow.visible` kaldırılır (K2).
- **T3** Kapsül, arama düğmesi ve FAB satırı aynı merkez çizgisinde. **Yükseklik 56, köşe 28**; arama
  düğmesi 64'ten 56'ya iner.
- **T4** Kapsülün alt kenarı: `max(viewPadding.bottom − 10, 12)`. Face ID'li iPhone'da ~24 pt (bugün 34).
  iOS 26 sistem tab bar'ının yerine denk düşer; içerik 10 pt kazanır. *Cihazda doğrula.*
- **T5** Alt örtü (§1.5).
- **T6** Oluk 16 (§1.1). Kapsülün dış kenarı kartların dış kenarıyla aynı çizgide.
- **T7** FAB'ın alt kenarı = kapsülün üst kenarı + 12. Liste sonu dolgusu = FAB'ın üst kenarı + 8
  (`awListPadding` mantığı aynı, değerler yeni).
- **T8** Her sekme yuvası ≥ **48 pt** (G4). Telefonda **en çok 5 hedef** var; 6. bölüm (uzantı)
  gelince son yuva **"Diğer"** olur ve bir sayfa açar (HIG/M3: tab bar 3–5 hedef). [SAHİBE SORU
  #5: hangi bölüm "Diğer"e iner]

### Yön A: "Hizala" (en az değişiklik; bütün kararların içinde)
5 nesne aynı yerinde kalır, yalnız geometri düzelir.
- **Satır**: `[16][kapsül, esnek, h56][8][arama 56][16]`. Balon bar satırına yalnız her sekme ≥ 48 pt
  kalıyorsa yerleşir; kalmıyorsa (5+ bölüm, 375 pt ekran) varsayılan yeri **sol kenar, AI FAB'ın 12 pt
  üstü, yarı gizli**.
- **Sekmeler**: seçili olmayanlar yalnız ikon (24 glif, 48×48 dokunma). **Seçili sekme yatay hap**:
  h40, köşe 20, `primaryContainer`, iç boşluk 12; içinde `[ikon 20][6][etiket 13/16 w600, tek satır]`.
  Bütün glifler tek merkez çizgisinde, dikey kayma yok (K3). Bugünkü "yalnız seçili etiketli" davranışı
  korunur ama doğru çizilir.
- **Genişlik hesabı** (393 pt): kapsül 297, iç 289. Seçili hap ("Ana Sayfa") ≈ 12+20+6+58+12 = 108, kalan
  4 yuva 45,25 pt. ✔ 375 pt'de kalan yuva 40,75'e düşer; bu genişlikte hap etiketsiz çizilir (yalnız
  ikon + hap, 52×40). Kural: etiket ancak diğer her yuva ≥ 44 kalıyorsa yazılır.
- **FAB'lar**: "+" 56, birincil dolgu, sağ oluk. AI/mikrofon **48'e küçülür**; dolgusu `secondaryContainer`,
  glifi `onSecondaryContainer`. Bugünkü doygun mor ikinci bir "birincil" gibi bağırıyor. Sol oluk.
- **Uygulama çubuğu**: telefonda en çok 2 ikon (§3.2).
- **Sonuç**: kayma ve taşma biter. Yüzen nesne sayısı (5) aynı kalır; C-02'nin sol alt örtüşmesi azalır
  (FAB 48 pt) ama tamamen çözülmez.
- Mobbin: Apple News [5b5e4939](https://mobbin.com/screens/5b5e4939-74cb-4024-a6cb-b73b6c1f61c8) (kapsül + ayrı
  yuvarlak arama, seçili hap kapsülün içinde), Todoist [b41c83dc](https://mobbin.com/screens/b41c83dc-954c-41f4-ab6f-37c62f9c307b),
  GitHub [18318ff4](https://mobbin.com/screens/18318ff4-3777-41bf-8a2d-27d28e451e63),
  eBay [fe5fe0e8](https://mobbin.com/screens/fe5fe0e8-c8e8-442e-81f8-8087575c54f2) (5 sekme, hap ikon ve etiketi birlikte sarar).

### Yön B: "Topla" (dengeli; önerilen)
A'nın sekme kapsülü aynen alınır; yüzen nesneler 5'ten 4'e, gruplar 3'ten 2'ye iner.
- **Alt satır**: A ile aynı (`[kapsül][arama]`); balon bar satırına yerleşmez.
- **Sağda tek FAB kümesi**: `[mikrofon 44, secondaryContainer][8][+ 56, birincil]`, yatay, sağ oluğa hizalı,
  alt kenarı kapsülün üst kenarı + 12. **Sol alt köşe boş** kalır; bölüm başlıkları ve satır başları bir daha
  örtülmez (C-02). Basılı tutma ile kilitleme (AI2) mikrofonda aynen çalışır; yalnız konum değişir.
  [SAHİBE SORU #3: AI1 "iki FAB, iki köşe, sonsuza dek"]
- **Hızlı Erişim**: telefonda fabrika ayarı **yüzen balon kapalı**. Giriş yolları: (1) Ana Sayfa uygulama
  çubuğunda ⚡ (Q5'te zaten tanımlı yedek yol; Q10 sayacı bu ikonun üstüne taşınır), (2) arama paletinin
  boş halinde "Kısayollar" grubu (Önceki'nin üstünde), (3) Ana Sayfa sekmesine uzun basınca panel.
  Sürüklenebilir balon Ayarlar › Genel'de isteğe bağlı kalır. [SAHİBE SORU #4: Q4 fabrika = yerleşik]
- **Genişlik**: balon satırdan çıkınca kapsül 297 → 5 sekme × 48 = 240 rahat; 6 bölüm T8 ile çözülür.
- **Sonuç**: tek krom satırı + tek eylem kümesi. Gözün taradığı köşe sayısı 4'ten 2'ye iner.
- Mobbin: Numo [5654d592](https://mobbin.com/screens/5654d592-3799-4ff9-a806-cfa69a5296d0) (mikrofon ve "+" sağda yan yana),
  TickTick [f5a31490](https://mobbin.com/screens/f5a31490-a933-426d-98d2-00db05c9f458) (tek FAB + etiketsiz kapsül),
  Superlist [fd0af81a](https://mobbin.com/screens/fd0af81a-cf3f-41e5-aa09-b7b9b46ddce3) (yeni görev + ses tek kümede).

### Yön C: "Tek satır" (cesur, yine Glass)
Bütün yüzen krom tek satıra iner: üç parça, ortak merkez çizgisi, simetri.
- **Satır**: `[16][arama 52, cam][8][kapsül, esnek, h56, yalnız ikon][8][+ 52, birincil dolgu][16]`.
  Arama düğmesi barın **solunda** kalır; ADR-0055'in "alt çubuğun yanındaki yuvarlak düğme" tanımı korunur.
- **Sekmeler**: hepsi etiketsiz, eşit; seçili = hap 52×40, ikonu sarar (Linear/TickTick/Craft). Hangi
  bölümde olunduğunu uygulama çubuğu başlığı söyler. 393 pt: kapsülün içi `393−32−104−16−8 = 233` → 5 × 46,6 ✔.
  375 pt: oluk 12'ye iner → 5 × 44,6 ✔. 6. bölüm T8 ile "Diğer"e gider. [SAHİBE SORU #2: etiketsiz sekme]
- **"+" düğmesi** dokunulunca hızlı ekleme sayfasını açar (§3.4); sayfanın içinde ✨ ve mikrofon vardır.
  **Basılı tutma** = sesle ekleme (AI2'nin aynı durum makinesi bu düğmeye taşınır: tut-konuş, bırak-kilitle,
  sola sürükle-iptal). AI sohbetine girişler: hızlı ekleme sayfası ("AI'ya sor") ve arama paletindeki
  "AI'ya sor: …" satırı. Ayrı mikrofon FAB'ı **yok**.
- **Hızlı Erişim**: B ile aynı (balon kapalı, ⚡ + palet).
- **Sonuç**: yüzen nesne 2 türe, 1 satıra iner. Sayfanın gövdesinde hiçbir şey yüzmez; FAB lane'i kalkar,
  listeler kapsülün üstüne kadar iner. Things/Linear sakinliği, Glass malzemesiyle.
- Çeliştiği kararlar: AI1, Q4c ("hızlı ekleme FAB'ı yerinden oynamaz"), Q4 fabrika ayarı. [SAHİBE SORU #1]
- Mobbin: Notion [71f9dba2](https://mobbin.com/screens/71f9dba2-130f-406e-b4fe-781f227f51b8) (yuvarlak arama + orta hap +
  yuvarlak yaz), Craft [2a8b3905](https://mobbin.com/screens/2a8b3905-3057-4dba-a9c0-fa6ffb48f6c7) (kapsül + aynı satırda "+"),
  Linear Mobile [c8edee5b](https://mobbin.com/screens/c8edee5b-336d-4da6-a287-1b784d07e223) (etiketsiz kapsül + ayrı arama),
  Todoist hızlı ekleme [8bca895b](https://mobbin.com/screens/8bca895b-61a1-4602-9afc-94580cca3b00) (DİKTE düğmesi sayfanın içinde).

| | A Hizala | B Topla | C Tek satır |
| --- | --- | --- | --- |
| Yüzen nesne | 5 | 4 (2 grup) | 3 (1 satır) |
| Sol alt köşe | AI FAB 48 | boş | boş |
| Sekme etiketi | seçili hap içinde yatay | seçili hap içinde yatay | yok (başlık söyler) |
| Bağlayıcı kararla çelişki | yok | AI1, Q4 fabrika | AI1, Q4, Q4c, ADR-0055'te sol konum |
| Kod etkisi | `AwTabCapsule` + ölçüler | + FAB kümesi, Hızlı Erişim ayarı | + "+" düğmesinde jest, FAB lane'i kalkar |

**Erişilebilirlik (üç yönde de):** her sekmede `Semantics(selected, label)` + tooltip; arama düğmesinin
etiketi "Ara (⌘K)". Odak sırası: içerik → sekmeler → arama → FAB'lar. VoiceOver'da basılı tutma jestinin dokunma
yedeği her zaman var (AI2/AI10). 44/48 pt alt sınırı her genişlikte (375 / 393 / 430) golden testle ölçülür.

---

## 3. Ana Sayfa / görev listesi

### 3.1 Görev satırı anatomisi
- **Sorun**: başlık sınırsız (çıplak bir URL 5 satır kaplıyor), onay dairesi ve sağdaki ikonlar dikey ortada,
  sağda 3 ikonluk sütun (bayrak, zil, kum saati) genişliğin ~%25'ini yiyor, meta satırı kırmızı ve kalın,
  iç boşluk büyük (C-04, C-05).
- **Mobbin**: Things 3 [feadd020](https://mobbin.com/screens/feadd020-045b-477e-b54f-d4c405995a58),
  Todoist [fae19fe7](https://mobbin.com/screens/fae19fe7-6408-49a0-b854-7df1e9d73e47),
  TickTick [eee52e76](https://mobbin.com/screens/eee52e76-6fae-462d-a496-3f810471ba88),
  Attio [73d19614](https://mobbin.com/screens/73d19614-30e4-4bd6-857a-3c3b3576f923).
- **Desen**: `[onay 44][başlık + meta satırı][en çok 1 sağ öğe]`. Durum glifleri sağ sütundan meta satırına iner.
- **Ölçüler** (telefon):
  - Kart: köşe 16 (satır; §3.2'deki `m`), yatay dış boşluk 16, iç boşluk üst/alt 10, sağ 12.
  - Onay: 44×44 dokunma, 22 pt daire, 1,5 pt `outline` çizgi. Kutunun üst kenarı başlığın ilk satırıyla aynı
    hizada; daire ilk satırın merkezinde.
  - Başlık: `AwText.rowTitle` 16/22, **en çok 3 satır** + üç nokta. Detay ekranı tamamını gösterir.
  - Meta satırı: `bodySmall` 13/18 tabular, başlıktan 2 pt aşağıda, **tek satır**. Öğeler arası 8 pt; her öğe
    `[glif 14][4][metin]`. Sıra: son tarih (gecikmişse `error` w500 + "Gecikti" sözcüğü; G5 için
    sözcük kalır) · tekrar glifi · alarm/acil glifi (acil ise `error`) · öncelik bayrağı (yalnız orta ve üstü,
    renkli) · ilk etiket + "+2". Taşan kısım sondan kırpılır.
  - **Kum saati (açık durum) gösterilmez**: varsayılan durum bilgi taşımaz. Yalnız varsayılan dışı durumlar
    (sürüyor, bekliyor) glif alır.
  - Sağ öğe: proje rozeti (§4, 6 karakter + "…") **ya da** atanan avatarı (24); ikisi birden olmaz. İlk satıra
    hizalı, en fazla 72 pt.
  - Yükseklik: yalnız başlık 48; başlık + meta 62.
- **Uzun başlık / URL**: başlık çıplak bir URL ise satırda "alanadı › yol…" biçiminde tek satır gösterilir
  (`linkified_text.dart` üretir, ortadan kırpılır) ve önüne bağlantı glifi gelir. Uzun tokenlarda `/ ? & =`
  sonrasına sıfır genişlikli kırılma (`​`) eklenir, böylece satır doğal yerde kırılır. Tam URL detayda
  bir bağlantı alanında durur.
- **Durumlar ve eylemler**: kaydırma eylemleri §19'daki gibi kalır; tamamlanan satır §20'ye uyar; AI ile
  zenginleşen satır `ai-enriching-*` rozetini meta satırının sonunda taşır.
- **Erişilebilirlik**: satırın tamamı tek semantik düğüm: "Görev, başlık, gecikti 31 Ekim 09:00, yüksek
  öncelik, acil alarm". Glifler ayrı okunmaz. Onay dairesinin kendi düğümü ("Tamamla") vardır.

### 3.2 Bölüm başlıkları (Geciken / Bugün / Yarın)
- **Sorun**: başlık geniş aralıklı ve küçük; sayaç metnin parçası; daraltılamıyor.
- **Mobbin**: Attio [73d19614](https://mobbin.com/screens/73d19614-30e4-4bd6-857a-3c3b3576f923) (daraltılabilir + sayaç rozeti),
  TickTick [eee52e76](https://mobbin.com/screens/eee52e76-6fae-462d-a496-3f810471ba88) (başlıkta bölüm eylemi "Ertele").
- **Ölçüler**: yükseklik 40; `titleSmall` 15/20 w700; sayaç `onSurfaceVariant` tabular, 6 pt sonra. Geciken
  başlığı `error` rengini korur, Bugün ve Yarın `onSurface` alır. Sağda 44 pt'lik daralt oku. İsteğe bağlı
  eylem: Geciken başlığında "Ertele" metin düğmesi (hepsini yarına taşır, §19 geri alma ile).
- **Hareket**: daraltma 220 ms'de yükseklik değişimiyle; ok 180° döner.
- **Erişilebilirlik**: `Semantics(header: true)`; daralt düğmesi "Geciken bölümünü daralt, 3 görev".

### 3.3 Uygulama çubuğu
- **Sorun**: 5 ikon (ara, pano, sırala, takvim, ayarlar). Ara ikonu alttaki arama düğmesinin kopyası; ADR-0055
  telefonda uygulama çubuğuna arama ikonu koymayı yasaklıyor (C-03).
- **Desen**: telefonda **en çok 2 ikon**: `[Görünüm ⌄][Ayarlar]`. "Görünüm" menüsü Liste/Pano, takvim
  göster/gizle ve sıralamayı tek menüde toplar. §34 L2 bunu Notlar için zaten yaptı; aynı emsal Ana Sayfa'ya
  uygulanır. Ekran içi arama (§12) aşağı çekince açılan alana ya da genel palete gider. B ve C'de ⚡ eklenince
  sayı 3 olur; o durumda Ayarlar ⋯ menüsüne iner.
- **Mobbin**: Todoist [b41c83dc](https://mobbin.com/screens/b41c83dc-954c-41f4-ab6f-37c62f9c307b) (sağ üstte 2 düğmelik cam hap),
  TickTick [f5a31490](https://mobbin.com/screens/f5a31490-a933-426d-98d2-00db05c9f458).

### 3.4 Hızlı ekleme alanı
- **Sorun**: 4 kontrol (+, ?, ✨, gönder). "?" birincil girişte gürültü yapıyor (C-06).
- **Mobbin**: Todoist [8bca895b](https://mobbin.com/screens/8bca895b-61a1-4602-9afc-94580cca3b00),
  TickTick [f0060294](https://mobbin.com/screens/f0060294-0589-49c5-9505-5db0c4a2a07c),
  Linear Mobile [9b5072a4](https://mobbin.com/screens/9b5072a4-3d0a-4695-a685-752eaabb38d6).
- **Desen**: boşken **0 sağ kontrol**; yalnız alan ve ipucu yer tutucusu ("Görev ekle — yarın 9:00 #iş").
  Yazınca `[✨ 40][↑ 40]` belirir; ↑ 32 pt'lik birincil daire. Sözdizimi yardımı ("?") odaklanınca alanın altında
  tek satırlık ipucu çip şeridine dönüşür ("yarın 9:00 · #etiket · +Proje · !1"), sonunda "Daha fazla" bağlantısı;
  ilk açılışta bir kez ipucu balonu. Baştaki "+" süs glifi kalkar.
- **Ölçüler**: yükseklik 48, köşe 16, G3 dolgu + 1 pt çizgi + 2 pt odak halkası.
- **Hareket**: ✨ ve ↑ 150 ms'de ölçeklenerek gelir. Gönderince alan temizlenir, yeni satır listede 220 ms
  vurgulanır.

### 3.5 Takvim (Ana Sayfa'daki)
- **Sorun**: ay ızgarası telefon ekranının yarısını kaplıyor (`screenshots/ios/01-home.png`).
- **Mobbin**: Amie [5330247b](https://mobbin.com/screens/5330247b-2fcd-497e-9dfe-8355835bfb14).
- **Desen**: varsayılan **hafta şeridi** (7 gün, h64, bugün dolu hap, nokta = görev var). Aşağı çekince ya da
  oka basınca ay ızgarası açılır; tercih cihazda saklanır. H1 (§16) korunur: şerit kayan sliver olarak kalır.

---

## 4. Diğer çekirdek ekranlar

### 4.1 Görev detayı
- **Sorun**: Durum, Öncelik ve Proje çerçeveli açılır kutular; detay bir form gibi okunuyor. Anahtarların
  uzun alt metinleri dikey alanı yiyor (`07-task-detail-repeat.png`).
- **Mobbin**: Todoist [0f0c1a8f](https://mobbin.com/screens/0f0c1a8f-0c94-44b5-a08c-3004f047b82d),
  ClickUp [84eb5561](https://mobbin.com/screens/84eb5561-df0d-4416-94bf-f5d5ba135874),
  Linear web [f00cc4fb](https://mobbin.com/screens/f00cc4fb-4083-43fc-a0fb-703a6c4ef771).
- **Desen**: başlık (`headlineSmall`, yerinde düzenlenir) → durum çipi → **özellik kartı**: satır 48, 24 pt
  ikon sütunu, değer metni, sağda chevron. Satırlar: Proje · Tarih ve süre · Hatırlatma · Öncelik · Etiketler ·
  Tekrar · Acil alarm (anahtar). Dokunulunca §17 D5 seçici sayfası açılır. Sonra gruplar: Kontrol listesi ·
  Açıklama · Dosyalar · Etkinlik.
- **Eylemler**: uygulama çubuğunda `[✓ Tamamla][⋯]`. Sil ⋯ menüsüne iner (§19 onay + geri al).
- **Ölçüler**: kart köşe 20, iç boşluk 4/16; anahtar alt metni 1 satır + "?" bilgi ipucu.
- **Erişilebilirlik**: her satır "Öncelik, Yüksek, değiştirmek için çift dokun".

### 4.2 Görev oluşturma sayfası
- **Sorun**: 9 tam genişlikte alan alt alta (`09-create-task.png`).
- **Mobbin**: Todoist [8bca895b](https://mobbin.com/screens/8bca895b-61a1-4602-9afc-94580cca3b00),
  Attio [84b6c597](https://mobbin.com/screens/84b6c597-af35-4f6c-b7cb-acce0b9c9511),
  Tiimo [ecfa4529](https://mobbin.com/screens/ecfa4529-7907-43c6-bbb5-7202059ef8dd).
- **Desen**: klavyenin üstünde kısa sayfa: başlık, açıklama (tek satır, büyür), **çip şeridi** `[Tarih][Öncelik]
  [Proje][Hatırlat][Acil][⋯]` yatay kayar; altta `[hedef liste ⌄] … [🎙][↑]`. "Ayrıntılar" bağlantısı tam formu
  (bugünkü sayfa) açar. Acil alarm çipi açıkken `error` tonlu ve zil glifli olur.
- **Ölçüler**: çip h32, köşe 16, iç boşluk 10; şerit h44; sayfa üst köşesi 28.

### 4.3 Projeler
- **Sorun**: her satırda yıldız + ⋯ (iki sağ kontrol); meta yok.
- **Mobbin**: Linear Mobile [c8edee5b](https://mobbin.com/screens/c8edee5b-336d-4da6-a287-1b784d07e223),
  GitHub [c0ae331f](https://mobbin.com/screens/c0ae331f-c3a7-4cf3-9f99-99fba4ffb2ee).
- **Desen**: `[renk noktası 10 + halka (Q8a)][ad + meta "12 açık · sonraki 14 Kas"][⋯]`. Yıldızlılar üstte
  "Yıldızlı" başlığı altında toplanır; yıldız ⋯ menüsüne iner. Sıralama değişmez (L5).

### 4.4 Notlar / belge
- **Sorun**: satırda yıldız + 2 satır önizleme + ⋯; filtre çipleri 4'lü. Genel olarak iyi.
- **Mobbin**: Craft [2a6e4efc](https://mobbin.com/screens/2a6e4efc-8dde-4efa-ba2c-eb27267ee582).
- **Desen**: başlık 1 satır (`titleMedium` 16/22 w600), önizleme 2 satır 14/20, sağ üstte tarih (13 tabular).
  Yıldızlılar "Sabitlenenler" bölümünde; satırdaki yıldız yalnız sabitlenmişse dolu görünür, değilse hiç
  çizilmez. Belge ekranı U1–U4 (§22a) aynen kalır.

### 4.5 Dosyalar
- **Sorun**: içerikten önce 3 kontrol satırı (Klasörlerim | Kaynaklar, "Dosyalar" çipi, "Yeni klasör / Dosya
  ekle" bağlantıları).
- **Mobbin**: Bevel [6dd15563](https://mobbin.com/screens/6dd15563-f900-4f6e-8398-af32912da3bb),
  Shopify [2253dbca](https://mobbin.com/screens/2253dbca-3ee1-4203-887e-050f26930ef7).
- **Desen**: tek segment kontrolü + altında sıralama alt başlığı ("Değiştirilme: en yeni", dokununca L4 menüsü).
  "Yeni klasör / Dosya ekle" "+" sayfasına taşınır. Satır: `[tür ikonu ya da küçük önizleme 40][ad][meta
  "PDF · 1,2 MB · 3 Kas"][⋯]`.

### 4.6 Gelen kutusu (TR: Fikirler)
- **Sorun**: her satırda 3 ikon düğmesi (takvim, not, çöp): satır başına 3 hedef, görsel gürültü.
- **Ad ve ikon**: TR etiketi "Fikirler", ikon bir gelen kutusu tepsisi. Ad ve glif uyuşmuyor.
  [SAHİBE SORU #6]
- **Mobbin**: Superlist [fd0af81a](https://mobbin.com/screens/fd0af81a-cf3f-41e5-aa09-b7b9b46ddce3),
  Todoist [8caabfd4](https://mobbin.com/screens/8caabfd4-9632-4220-be7b-e8a775637429).
- **Desen**: satırda yalnız metin + tek ⋯. Kaydırma: sağa "Planla" (tarih sayfası), sola "Sil" (§19). Dokununca
  "Görev yap / Nota çevir / Sil" eylem sayfası açılır. Üstte bir kez "Fikirler Ana Sayfa'ya düşmez" açıklama
  kartı, "Kapat" ile.

### 4.7 Pano (kanban)
- **Sorun**: telefonda yatay sayfalama; sütun başlığı ve sayaç zayıf.
- **Mobbin**: GitHub [7d35dba1](https://mobbin.com/screens/7d35dba1-4695-4d82-9d6e-cc648bf9ad73),
  Notion [71f9dba2](https://mobbin.com/screens/71f9dba2-130f-406e-b4fe-781f227f51b8).
- **Desen**: telefonda varsayılan **dikey daraltılabilir durum grupları**; her grubun başlığında sayaç rozeti ve
  "+". Yatay sayfalama Görünüm menüsünde seçenek olarak kalır. Taşıma: uzun bas → "Taşı" sayfası (sürükleme tek
  yol değil, K3 dersi).

### 4.8 Arama (palet)
- Bugünkü §40 iyi. Eklemeler: boş haldeyken "Kısayollar" (B/C) ve "Önceki"; sorgu varken son satır "Görev oluştur"
  ve **"AI'ya sor: '…'"** (AI yapılandırılmışsa). Web'de altta klavye ipucu çubuğu ("↑↓ gez · ⏎ aç · esc").
- **Mobbin**: incident.io [907900ee](https://mobbin.com/screens/907900ee-1dca-4726-ae50-9e043eecfbe4).

### 4.9 Ayarlar
- §32 dizin yapısı doğru. Görsel düzeltme: grup satırı 52, ikon 20 tek renk (`onSurfaceVariant`) 28 pt'lik
  sütunda, alt başlık 13/18 tek satır. Bölüm etiketi kartın dışında 13/18 w600, büyük harf yok.
- **Mobbin**: Jomo [a2cc786d](https://mobbin.com/screens/a2cc786d-6daa-42d7-86b4-f440a5d52604).

### 4.10 AI sohbet
- **Mobbin**: Microsoft Copilot [22fc091d](https://mobbin.com/screens/22fc091d-197d-43d5-a093-a9616321ef05),
  ClickUp [131dcd89](https://mobbin.com/screens/131dcd89-8ab8-4003-99ce-5a11399da0d2).
- **Desen**: boş durumda selam başlığı (`headlineSmall`) + 3–4 öneri çipi ("Bugün neler var?", "Geciken görevleri
  özetle", "Toplantı notundan görev çıkar"). **Bileşik giriş**: `[@ ek][metin][🎙][↑]`, h52, köşe 26. Girişin üstünde
  AI7 için **bağlam çipi** ("Bağlam: 2 görev, 1 not ›"; dokununca tam liste). Akış durumunda Durdur birincil olur.
- AI3/AI4 aynen kalır (opak yüzey, her durumun bir yüzü var).

---

## 5. Web / masaüstü

- **Kenar çubuğu (ray paneli)**:
  - Satır 32, 14/20, ikon 18, sayaç sağa hizalı tabular.
  - Bölüm etiketi 12/16 w600 `onSurfaceVariant`.
  - Hızlı Erişim satırlarındaki sürükleme tutamakları ("≡≡") yalnız üzerine gelince görünür; bugün her satırda
    duruyor ve göz yoruyor. Q9 gereği menüdeki "Yukarı/Aşağı taşı" kalır.
  - Mobbin: Todoist web [52758ad6](https://mobbin.com/screens/52758ad6-7145-46d7-826b-2469b17f2ee0),
    Linear [fd1b4d88](https://mobbin.com/screens/fd1b4d88-f021-49a3-98af-4cd3a87e1d29).
- **Liste–detay**: ≥ 1160 pt'de görev detayı ayrı sayfaya gitmez, **sağda 420 pt'lik panelde** açılır. Liste
  görünür kalır, ↑/↓ ile panel sonraki görevi gösterir (Linear "2/5"). < 1160'ta bugünkü sayfa geçişi kalır.
  Mobbin: Linear [f00cc4fb](https://mobbin.com/screens/f00cc4fb-4083-43fc-a0fb-703a6c4ef771).
- **Yoğunluk**: web satırı 40 (telefon 48/62), başlık 14/20, meta 12/16. Liste içeriği en çok 760 pt, ortalı.
  Takvim paneli ≥ 1160'ta sağda kalır (H2). Mobbin: Linear [ed670cda](https://mobbin.com/screens/ed670cda-0527-4716-a1a6-0159f12c4f42).
- **Klavye**: `j/k` ya da ↑/↓ satır seçer; `x` ya da Space tamamlar; `e`/⏎ detayı açar; `t` tarih, `p` öncelik,
  `#` etiket; `⌘K`/`Ctrl+K` palet (P1); `?` kısayol listesi; Esc paneli kapatır. Fareyle görünen her satır eylemi
  (tarih, ⋯) klavyeyle ve sağ tık menüsüyle de erişilebilir.
- **Bölümler**: proje sayfasında bölümler daraltılabilir; her bölümün sonunda satır içi "+ Görev ekle". Mobbin:
  Todoist [46dab991](https://mobbin.com/screens/46dab991-e521-44bc-984a-c936e31610a8).

---

## 6. Kurumsal uzantı ekranları

Bu bölüm depodaki kopyadan çıkarıldı: uzantı bulguları uzantı deposunda (I-14).

---

## 7. Keşif yüzeyleri: landing + GitHub

- **"Açık kaynak" demeyin.** Lisans PolyForm Noncommercial (README rozeti). "Kaynak kodu açık, kendi
  sunucunuzda" denir. Supabase'in "açık kaynak X alternatifi" kalıbı, "**kendi sunucunuzda çalışan, alarmı
  sessizde çalan Todoist alternatifi**" diye uyarlanır.
- **Kanıt şeridi** (hero'nun altında, tabular rakam): "6 platform · 1.200+ test · Claude ve ChatGPT (MCP) ·
  Kendi MySQL'iniz". Yıldız sayısı (26) gösterilmez; yerine üst gezinmede "GitHub'da yıldızla" düğmesi.
  Mobbin: GitHub [47da1294](https://mobbin.com/sites/sections/47da1294-ab1a-403b-b23f-1988bba48b0d),
  Supabase [0eb5722a](https://mobbin.com/sites/sections/0eb5722a-4576-49bd-9d04-b2d9556690fc).
- **Kendi sunucunda kur** bölümü: kopyalanabilir tek komut hapı
  (`docker compose -f docker-compose.selfhost.yml up -d`) + "Belgeler" ikincil düğmesi. Sekmeler: Docker /
  elle. Süre vaadi ("n dakikada") ancak ölçülürse yazılır. Mobbin: Retool [ec886bd7](https://mobbin.com/sites/sections/ec886bd7-cfbf-4c80-861d-bb69db7fe9fb),
  Giga [a2004615](https://mobbin.com/sites/sections/a2004615-5fee-4e7d-9f84-602f3f1ab1f0).
- **Ekran görüntüsü sunumu**: hero'da telefon ve web yan yana, demo tohumuyla, aynı anın iki yüzü. Özellik
  çipleri seçilince görsel değişir. Mobbin: ClickUp [cf6bd0a1](https://mobbin.com/sites/sections/cf6bd0a1-8de8-438f-8b96-c96b17a5b47f).
  **Görseller yeni alt bar ile yeniden çekilmeden** landing'e taşınmaz.
- **GitHub sayfası**: "homepage" alanı boş (C-08), topics ve sosyal önizleme görseli (1280×640) ayarlanmalı.
  Bunlar dış hesap işi → STATE "Kullanıcıdan bekleyen". README'de "Nasıl karşılaştırılır" tablosu ilk ekrana
  yaklaştırılır; demo bağlantısı rozetlerin üstüne alınır.

---

## 8. Uygulama sırası (öneri; işlere bölünür)

1. **Tipografi düzeltmesi** (§1.2): yalnız `theme.dart`; bütün ekranlar düzelir, risk düşük. Golden'lar yenilenir.
2. **Alt bar taban T1–T8** + seçilen yön (A/B/C).
3. **Görev satırı anatomisi** (§3.1–3.2) + uygulama çubuğu 2 ikon (§3.3) + hızlı ekleme (§3.4).
4. Detay / oluşturma (§4.1–4.2), sonra kalan ekranlar.
5. Web liste–detay paneli ve klavye (§5).
6. Uzantı desenleri (uzantı deposunda, kendi işleriyle).

Her adım light **ve** dark, 375 / 393 / 430 genişliklerinde golden'la ölçülür. `contrast.py` cam tonu
üstündeki ikonları da kapsar.

---

## 9. Açık sorular (numaralı, her birine öneri)

1. **Alt bar yönü: A, B mi C mi?** Öneri: **B**. Yüzen nesneleri 5'ten 4'e indirir, sol alt çakışmayı bitirir,
   yeniden öğrenme gerektirmez. Sahip daha "kurumsal ve düşünülmüş" bir sakinlik istiyorsa C hedeftir; cihazda
   A/B/C prototipiyle karar verilmeli.
2. **Sekme etiketleri: seçili hapın içinde yatay etiket (A/B) mi, hiç etiket yok mu (C)?** Öneri: yatay etiketli
   seçili hap. Bugünkü "yalnız seçili etiketli" kararını korur ama doğru çizer.
3. **AI1 ("iki FAB, iki köşe, sonsuza dek") gevşesin mi? Mikrofon "+" yanına taşınsın mı?** Öneri: evet (B).
   Basılı tutma jesti (AI2) aynen kalır.
4. **Hızlı Erişim balonu telefonda fabrika ayarında kapalı olsun mu? Giriş ⚡ + palet + Ana Sayfa'ya uzun basma
   olsun mu?** Öneri: evet. Balon isteğe bağlı ayar olarak kalır; bugün ekranın en çok gürültü yapan nesnesi.
5. **Uzantıda 6+ bölüm: telefonda en çok 5 sekme + "Diğer" kuralı uygulansın mı? Hangi bölüm iner?** Öneri: evet.
   Hangi bölümün "Diğer"e ineceği uzantı deposunda belirlenir.
6. **"Fikirler" (TR) / "Inbox" (EN) ile tepsi ikonu uyuşmuyor.** Öneri: adlar kalsın, glif iki dilde de ampul
   (`lightbulb`) olsun.
7. **Satır başına kart mı, bölüm başına tek kart mı?** Öneri: satır başına kart kalsın (Glass kimliği); iç boşluk
   ~%30 azalsın, köşe 20 → 16.
8. **Font**: sistem fontu kalsın, yalnız harf aralığı ve ölçek düzelsin mi? Öneri: evet. Özel font (ör. landing'in
   Wix Madefor'u) uygulamaya gelmesin; çevrimdışı ve yerel his kararı (§3.3) doğru.
9. **Düşük öncelik bayrağı satırda hiç gösterilmesin mi?** Öneri: evet. Yalnız orta ve üstü; "açık" durumunun kum
   saati de gösterilmesin.
10. **Ana Sayfa takvimi telefonda varsayılan hafta şeridi olsun mu?** Öneri: evet; ay görünümü bir dokunuşla açılır.
11. **Web'de ≥ 1160 pt'de detay sağ panelde açılsın mı?** Öneri: evet.
12. **Web için yoğunluk ayarı (Rahat/Sıkı) eklensin mi?** Öneri: şimdilik hayır (S5 "uydurma satır yok"). Web
    varsayılanı sıkı, telefon rahat.
