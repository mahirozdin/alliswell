> **Depodaki kopya (2026-11-07, E35 kaydı):** uzantıya özgü tasarım ayrıntısı çıkarıldı (uzantı bulguları uzantı deposunda); turun iç çalışma dosyalarına ve ham kanıta verilen yollar düz metne çevrildi ("ham kanıt" = turun çalışma alanında kalan dosya; depoda yok). Bulgu kimlikleri değişmedi. Özet: [README.md](README.md).

> Son güncelleme: 2026-11-07 — CEO tasarım/UX turu
> Kaynak: sahip brief'i (O-01…O-11, C-01…C-08); kod `apps/app/lib/src/**` (core; uzantı hariç); `docs/DESIGN.md`; `docs/STATE.md` "Sahip kararları"; görüntüler `screenshots/{web,ios,android}/*.png`, `docs/screenshots/*.png` (2026-07-21 … 2026-10-16, git tarihleri); sahibin iPhone görüntüsü yalnız teşhis için (içeriği hiçbir yere kopyalanmadı).

# Çekirdek uygulama — sezgisel UX denetimi (mobil + web/masaüstü)

## 0. Yöntem ve sınırlar

- **Görüntü kaynağı:** turun çekim klasörü (depoda yok) bu sırada **boştu** (2026-11-07 itibarıyla); bu yüzden depodaki eski çekimler kullanıldı. Hepsi Temmuz–Ağustos 2026 (içe aktarma önizlemesi 2026-10-16). **Eski çekimlerde alt çubukta her sekmenin etiketi yazıyor; bugünkü kod ve sahibin görüntüsü yalnız seçili etiketi gösteriyor** (OPH-374 sonrası). Bu yüzden alt çubuk, arama ve yüzen nesneler için **kod + sahibin görüntüsü** esas alındı; eski çekimler yalnız değişmemiş ekranlar için kanıt.
- Contact sheet'ler tur çalışma alanında kaldı (depoda yok).
- **Mobbin MCP bu oturumda yetkisiz** (OAuth gerekiyor, etkileşimsiz oturum) → rakip karşılaştırması (Todoist/Things/Linear) genel ürün bilgisinden, **bu turda görselle doğrulanmadı**; yalnız desen düzeyinde, kopya yok. Doğrulama için O-04 turunda Mobbin'den bakılmalı.
- Cihazda/emülatörde canlı gezinti yapılmadı (bu görevin kapsamı dosya + görüntü). Çalışma zamanı ölçüsü gerektiren iddialar "kod gösteriyor / görüntü gösteriyor" diye ayrıldı.
- Etiketler: **B** = blocker, **M** = major, **m** = minor · Efor **S/M/L** · **SAHİBE SORU** = bağlayıcı bir sahip kararına (STATE / DESIGN / ADR) dokunuyor.

---

## 1. Kabuk: alt çubuk, yüzen nesneler, uygulama çubuğu (telefon)

### 1.1 [B · S–M · SAHİBE SORU] Alt çubuk etiketi kapsülden taşıyor, ızgara yok
- **Kanıt (kod):** `apps/app/lib/src/screens/home_shell.dart:454-462` — sekme başına genişlik `kAwBarLabelSlot = 64` px'in (`home_shell.dart:711`) altına düşünce `onlyShowSelected`. 390 pt'lik telefonda: 390 − 2×12 (dış) − 8 (boşluk) − 64 (arama küresi) − 2×12 (iç) = 270 → 5 sekmede **54 px/sekme** → her zaman tek etiket. Etiket `DefaultTextStyle.merge(maxLines: 1, softWrap: false, overflow: TextOverflow.visible)` ile çiziliyor (`home_shell.dart:476-479`): "Ana Sayfa" 54 px'e sığmayınca **kesilmek yerine kutusunun dışına taşıyor**. Etiket stili `labelMedium` w700 + M3 harf aralığı 0.5 (`theme/theme.dart:338-346`), yani TR'de daha da geniş.
- **Kanıt (görüntü):** sahibin iPhone görüntüsü — seçili etiket kapsülün altına, içerik başlığının üstüne biniyor; seçili hap sola yaslı, diğer 4 ikon eşit aralıklı değil (C-01). Eski çekimlerde (ör. `screenshots/ios/01-home.png`) 5 etiketin hepsi yazıyordu: **gerileme OPH-374'le geldi**.
- **Kural çatışması:** DESIGN §40 P1 ve STATE "Her yerden arama (ADR-0055)": "telefonda giriş alt çubuğun yanındaki yuvarlak düğme … (bu yüzden telefonda çoğunlukla yalnız seçili sekmenin etiketi yazılır)". Yani bugünkü görünüm **sahip kararının sonucu** → değiştirmek SAHİBE SORU.
- **Önerilen yönler (2–3, zevk kararı sahibin):**
  - **A — "Hep etiket, küre çubuğun içinde":** arama küresini kapsülün 6. hücresi yap (ayrı cam nesne değil), etiketleri `labelSmall` (11 pt, tracking 0) yaz; 6 × ~58 px hücre "Ana Sayfa"yı 11 pt'de taşır. Tek cam nesne, tek ızgara.
  - **B — "Yatay hap":** seçili sekme ikon + etiket yan yana genişleyen hap (iOS 26 / Android Expressive deseni), diğerleri yalnız ikon, hepsi kapsülün içinde dikey ortalı; etiket asla kapsül dışına çıkmaz. ADR-0055'in "yalnız seçili etiket" ruhunu korur, taşmayı yok eder.
  - **C — "4 sekme":** Dosyalar'ı Projeler/Notlar içine katla (ya da Fikirler'i Ana Sayfa'ya) → 4 sekme + küre, her etiket sığar. Bilgi mimarisi değişikliği → en büyük SAHİBE SORU.
  - Hangisi seçilirse seçilsin, sahip kararına dokunmayan **asgari düzeltme (S):** `overflow: TextOverflow.visible` → `ellipsis`/`fade` ve etiketi `labelSmall` + `letterSpacing: 0`; hap + etiket dikeyde kapsülün içinde ortalanmalı. Bir golden test (TR, 390 pt, "Ana Sayfa" seçili) taşmayı kilitlemeli.

### 1.2 [M · S] Projeler ve Dosyalar ikonları neredeyse aynı
- **Kanıt:** `sections.dart:31` `Icons.folder_outlined` (Projeler) ve `sections.dart:45` `Icons.folder_copy_outlined` (Dosyalar); Hızlı Erişim'de de aynı çift (`features/quick_access/ui/quick_access_row.dart:15,18`). Etiketler artık yazmadığı için (1.1) iki klasör ikonu yan yana ayırt edilemiyor (sahibin görüntüsü, alt çubuk 3. ve 5. ikon).
- **Öneri:** Projeler için hedef/katman anlamlı bir ikon (ör. `Icons.workspaces_outline` zaten kodda görev satırında kullanılıyor — `task_tile.dart:223`) ya da `Icons.view_kanban_outlined` dışında bir proje ikonu; Dosyalar klasör kalsın. Ayrıca Notlar `description` ikonu + Dosyalar klasör ikonu iyi; yalnız Projeler değişmeli.

### 1.3 [M · M · SAHİBE SORU] Telefonda 5 yüzen nesne
- **Kanıt:** alt kapsül + arama küresi (`home_shell.dart:500`), iki FAB (`home_shell.dart:113-129`: AI mikrofonu sol, + sağ, DESIGN §24 AI1), Hızlı Erişim balonu (`features/quick_access/ui/quick_access_bubble_host.dart:95-115`, kenara yarı gömülü). Sahibin görüntüsünde mikrofon FAB'ı bölüm başlığını örtüyor (C-02); eski çekimlerde (`screenshots/ios/01-home.png`) mikrofon FAB görev kartının sol yarısını örtüyor.
- **Öneri (artan cesaretle):** (a) **S:** liste altına iki FAB yüksekliği kadar boşluk zaten var (`widgets/fab_clearance.dart`) ama bölüm başlıkları üstten örtülüyor → FAB'ları kaydırınca küçült/soluklaştır (Things/Todoist'te tek FAB kaydırırken sabit ama içerik kenarında). (b) **M:** AI'yı ayrı FAB yerine `+` FAB'ının uzun basışına ya da hızlı ekleme alanındaki ✨'ya taşı (ikisi zaten var), mikrofon FAB'ı kalksın → 4 nesne. (c) Hızlı Erişim balonunu telefonda varsayılan kapalı yap (Ayarlar'da anahtar zaten var: `settings.quickBubble`) → 3 nesne. (b) ve (c) DESIGN §23/§24 kararlarına dokunur → SAHİBE SORU.

### 1.4 [M · S] Telefon uygulama çubuğunda 5 ikon; iki farklı "büyüteç"
- **Kanıt:** `features/home/home_screen.dart:229-292` — yerel arama (`AwSearchAction`), pano/liste, sırala, takvim; `home_shell.dart:793-797` her bölüme ayar dişlisi ekliyor. Sahibin görüntüsü: büyüteç, pano, sırala, takvim, dişli (C-03). Uygulama çubuğundaki büyüteç **yalnız Ana Sayfa'yı süzen yerel arama**, alttaki küre **küresel arama** — aynı ikon, iki farklı kapsam. ADR-0055 "uygulama çubuğuna ikon yok" diyor; DESIGN §40 "Per-screen search (§12) stays as it is" diyerek yereli tutmuş → kullanıcı için çift büyüteç.
- **Öneri:** telefonda yerel aramayı küresel paletin "bu ekranda süz" kısayoluna bağla ya da yerel aramayı filtre ikonuna (`filter_list`) çevir; sırala + takvim + pano tek bir "Görünüm" menüsüne (tek ikon) toplanabilir → 2 ikon (Görünüm, Ayarlar). Dişli her bölümde tekrar ediyor; telefonda yalnız Ana Sayfa'da kalabilir (masaüstünde rail'in altına: bkz. 3.3).

### 1.5 [M · S] İçerik çubuğun altından geçerken solma/örtü yok
- **Kanıt:** sahibin görüntüsü (C-07): son kart çubuğun altında keskin kesiliyor, seçili etiket metinle çakışıyor. `home_shell.dart:416` `extendBody: true` + `_ShellBody` yalnız padding veriyor (`home_shell.dart:733-750`), alt kenarda gradyan/scrim yok.
- **Öneri:** alt 96 px'te zemin rengine giden 0→%85 dikey gradyan (G1'e uygun: cam değil, zemin tonu); koyu temada da kontrol (G7).

---

## 2. Tipografi ve görev satırı (her ekranın asıl yüzü)

### 2.1 [M · S] Gövde metninde Material harf aralığı SF Pro'ya uygulanıyor
- **Kanıt:** `theme/theme.dart:103-130` — `Typography.material2021(...).englishLike` taban; yalnız headline/title'larda negatif tracking var, `bodyLarge`/`bodyMedium`/`labelMedium` M3'ün **+0.5 / +0.25 / +0.5** harf aralığını koruyor. SF Pro kendi optik tracking'ini taşıdığı için 16 pt'de Apple'ın önerisi negatif; sonuç sahibin gördüğü "geniş, gevşek" metin (C-04). DESIGN §3.3 "Weights/tracking tuned in theme.dart" diyor ama body tracking ayarlanmamış.
- **Öneri:** Apple platformlarında `bodyLarge/bodyMedium/bodySmall/labelLarge/labelMedium/labelSmall` için `letterSpacing: 0` (ya da SF tracking tablosuna yakın −0.2…−0.3); Android/Roboto'da M3 değeri kalabilir. Bir satırlık değişiklik, bütün uygulamayı "native" gösterir. Kontrast/boyut değişmez (G2 etkilenmez).

### 2.2 [M · S] Görev başlığında satır sınırı yok
- **Kanıt:** `features/tasks/ui/task_tile.dart:186-194` `Text(task.title)` — `maxLines` yok. Sahibin görüntüsünde uzun bir başlık/URL 5–7 satıra yayılıp bir ekranda yalnız 3 görev sığıyor (C-04).
- **Öneri:** listede `maxLines: 2, overflow: ellipsis` (detayda tam metin); URL'yi listede alan adına kısalt (`linkified_text.dart` zaten var). Todoist/Things listede 1–2 satır gösterir (genel bilgi, doğrulanmadı).

### 2.3 [M · S] Satır anatomisi: dikey ortalama, sağda 3–4 ikon
- **Kanıt:** `task_tile.dart:177` `ListTile` — `titleAlignment` verilmemiş, tema da vermiyor (`theme.dart:188-200`) → çok satırlı satırda onay dairesi ve sağ ikonlar ortada (C-05). Sağ küme: proje rozeti + bayrak + acil zil + **her açık görevde kum saati** (`task_tile.dart:438` `taskStatusIcon(task.status)`; "Açık" varsayılan durum olduğu için bilgi taşımıyor).
- **Öneri:** `titleAlignment: ListTileTitleAlignment.top` (onay dairesi ilk satırla hizalı); varsayılan durumların ikonu çizilmesin: "Açık" kum saati yok, yalnız Devam/Bekliyor/İptal ikon alır. Böylece sağ küme ortalama 1–2 ikona iner. G5 korunur (çizilen her renk yine ikonlu).

### 2.4 [M · S · SAHİBE SORU (yalnız varsayılan değişirse)] Her görevde zil + bayrak → işaret anlamını yitiriyor
- **Kanıt:** `features/tasks/data/task_defaults.dart` (ve `task_create_sheet.dart:148-151`): her yeni görev **orta öncelik + acil alarm açık** doğuyor (DESIGN §26 C1, sahibin "yazdığın görev çalmalı" duruşu). Sonuç: sahibin listesinde her satırda turuncu bayrak + kırmızı zil; `screenshots/ios/02-board.png`'de de aynı.
- **Öneri (karara dokunmadan):** varsayılanı değiştirmeden **satırda yalnız varsayılandan sapmayı çiz**: orta öncelik bayrağı çizilmesin (yalnız Yüksek; Düşük isteğe bağlı), acil zil yerine "alarm kapalı/sessiz" istisnası işaretlensin. Varsayılanın kendisini değiştirmek SAHİBE SORU.

### 2.5 [m · S] Gecikmiş tarih satırı kırmızı + kalın + 14 pt
- **Kanıt:** `task_tile.dart:312-322` gecikmişte `bodyMedium` + `scheme.error` + `w600`. Gecikmiş bölüm başlığı da kırmızı ("Geciken · 3"); her satır tekrar bağırıyor (C-04).
- **Öneri:** meta satırı `bodySmall` w500 kırmızı (renk + "Gecikti" metni G5 için yeter), kalınlık başlığa kalsın.

### 2.6 [m · S] Kart başına kart: yoğunluk düşük
- **Kanıt:** her satır ayrı `Card` + 6 px dikey aralık (`widgets/status_views.dart:262`, `theme.dart:178-187`), `minVerticalPadding: 10`. iPhone'da bir ekranda 5–6 görev (`screenshots/ios/01-home.png`); Things/Todoist düz liste + ince ayraçla ~9–11 satır gösterir (genel bilgi).
- **Öneri:** bölüm başına tek yüzey (grup kartı) + satır arası hairline; "Rahat/Sıkı" yoğunluk ayarı (widget'ta zaten "density" var — DESIGN §32 S2) uygulamaya da gelsin.

---

## 3. Bilgi mimarisi ve gezinti

### 3.1 [M · M] Aynı iş için çok yol: görev oluşturma
- **Kanıt:** Ana Sayfa'da tek ekranda 4 giriş: hızlı ekleme alanı (`quick_add_bar.dart:234-266`, kendi içinde +, ?, ✨, gönder), `+` FAB (tam form), AI mikrofonu FAB'ı (`ai_fab.dart:124`), panoda sütun "+ Görev ekle". Ayrıca Fikirler'de ikinci yakalama alanı (`screenshots/ios/06-inbox.png`), widget +, paylaşım, Siri.
- **Sorun:** yeni kullanıcı için "hangisi?" sorusu; hızlı ekleme alanının sol `+` ikonu ile FAB `+` aynı simge, farklı davranış.
- **Öneri:** hızlı ekleme alanının sol `+` ikonu dekoratif → kaldır ya da odakla; `?` yardımı alanın içinden çıkıp ilk odakta görünen tek satırlık ipucuna/yer tutucuya dönüşsün (C-06); ✨ yalnız AI açıkken ve metin varken görünsün → alanda tek gönder düğmesi kalır.

### 3.2 [M · S] Tamamlananlar ve İçe aktarma Ayarlar'ın içinde gömülü
- **Kanıt:** `router.dart:810` `/settings/completed`, `router.dart:798` `/settings/import`; bağlantı yalnız Ayarlar → Veri (`screens/settings_screen.dart:871-925`). DESIGN §20 C4 "Behind Settings rather than a sixth tab".
- **Sorun:** "dün ne bitirdim?" günlük bir soru, bir "ayar" değil; Things'te Logbook ana listededir (genel bilgi). İçe aktarma ise yeni kullanıcının **ilk 5 dakikasında** gereken şey (bkz. 4.1) ama 2 seviye derinde.
- **Öneri (sekme eklemeden, kararla çelişmez):** Ana Sayfa'nın "Görünüm/⋯" menüsüne "Tamamlananlar" satırı; boş Ana Sayfa'da "Todoist/TickTick'ten taşı" düğmesi. Ayarlar'daki girişler kalır.

### 3.3 [M · M] Masaüstünde görev detayı ve Ayarlar kabuğu terk ediyor
- **Kanıt:** `router.dart:1106-1110` `/tasks/:taskId` ve `router.dart:749-815` `/settings/**` kök rotalar (`_contentPage`), kabuk dalı değil → rail kayboluyor (`screenshots/web/settings.png`, `completed.png`, `ai-settings.png`: rail yok, 1440 px'te ~300 px'lik tek sütun). Projeler/Notlar ise kabuk içinde açılıyor (`router.dart:705-740`) → tutarsız.
- **Sorun:** masaüstünde bir göreve bakmak listeyi kaybettiriyor; Todoist/Linear/Things geniş ekranda detayı yan panel/modal açar (genel bilgi).
- **Öneri:** geniş (≥ `kAwWideBreakpoint`) düzende görev detayı sağ panel (liste + detay iki sütun), Ayarlar kabuk içinde (rail görünür) ya da en azından rail'in altında sabit "Ayarlar" girişi; bölüm çubuklarındaki dişli masaüstünde kalkar.
- **Çıkmaz ekran notu:** eski web çekimlerinde Ayarlar/Tamamlananlar'da geri düğmesi görünmüyor; kod bugün `widgets/route_leading.dart:21-37` ile yığında bir şey yoksa "Ana Sayfa" düğmesi koyuyor → **çıkmaz yok (kod), görselle yeniden doğrulanmalı**.

### 3.4 [m · S] "Inbox" EN'de Gelen Kutusu, TR'de "Fikirler"
- **Kanıt:** `assets/i18n/en.json` `nav.inbox = Inbox`, `tr.json` `nav.inbox = Fikirler`; boş Ana Sayfa metni TR'de "Fikirler'den bir tane yakala" (`home.allCaughtUpBody`). İki dilde iki farklı zihinsel model (biri "işleri buraya at", biri "fikir defteri").
- **Öneri:** kavramı tek seç (ürün kararı); ikon (`inbox`) ile ad uyumlu olsun.

### 3.5 [m · S] Favori yıldızı Notlar'da solda, Projeler'de sağda
- **Kanıt:** `features/notes/ui/notes_screen.dart:209,396` yıldız satırın başında; `screenshots/ios/03-projects.png` yıldız sağda, ⋯ yanında; `screenshots/ios/04-notes.png` yıldız solda.
- **Öneri:** iki listede de aynı yer (sağ, ⋯'nin solu) ya da yalnız işaretli olanlarda göster.

### 3.6 [m · S] Proje satırı bilgi taşımıyor
- **Kanıt:** `screenshots/ios/03-projects.png`, `screenshots/web/projects.png`: renk noktası + ad + yıldız + ⋯; açık görev sayısı/ilerleme yok. Things proje ilerleme halkası, Todoist sayı gösterir (genel bilgi).
- **Öneri:** sağda "12 açık · 3 gecikmiş" `bodySmall` metni (renk değil metin, G5).

---

## 4. İlk açılış, giriş/kayıt, değer anı

### 4.1 [M · M] İlk kullanıcı: tur var, etkinleştirme yok
- **Kanıt:** `features/onboarding/tour.dart` `kTourSteps` — hoş geldin + 5 sekme spot ışığı + kapanış = 7 adım, hiçbiri "ilk görevini yaz / taşı / alarmı dene" demiyor. Boş Ana Sayfa `home_screen.dart:613-618` "Her şey tamam" + plaj şemsiyesi — hiç görev girmemiş birine "her şey tamam" demek yanlış mesaj; eylem düğmesi yok. Tur spot ışığı etiketsiz ikonları gösteriyor (1.1).
- **Değer anı tahmini:** kayıt → 7 adımlık tur → boş ekran → hızlı ekleme → **tarih seçici açılır** (DESIGN §26 C3) → görev. Ürünün ayırt edici değeri (acil alarm) ilk görevde görünmüyor, izin istemi ayrı. Süre **ölçülmedi (bilinmiyor)**; adım sayısı ≥ 10 dokunuş.
- **Öneri:** turu 3 karta indir (Ana Sayfa · Hızlı ekleme · Acil alarm) ve son kart "İlk görevini yaz" alanına odaklansın; ilk-kez boş durumu ayrı: "İlk görevini ekle" + "Todoist/TickTick'ten taşı" + "Örnek verilerle dene" (demo tohumu zaten var). Boş durumu "hiç görev yok" ve "hepsi bitti" diye ikiye ayır.

### 4.2 [M · M] Şifremi unuttum yok (uygulamada da API'de de)
- **Kanıt:** `features/auth/ui/login_screen.dart:71-138` — e-posta, şifre, Giriş, Kayıt'a geç, sosyal girişler; sıfırlama bağlantısı yok. `apps/api/src/routes/auth.js` uç noktaları: `/register`, `/oauth`, `/login`, `/refresh`, `/logout`, `/mfa/totp*`, `/password` (oturum içi değiştirme), `/sessions*` — sıfırlama akışı yok. `docs/` altında bu konuda karar/ADR bulunamadı.
- **Sorun:** barındırılan `alliswell.space` kullanıcısı şifresini unutursa tek çıkış sosyal giriş ya da destek.
- **Öneri:** e-posta ile tek kullanımlık sıfırlama bağlantısı (self-host'ta SMTP yoksa "yöneticine başvur" metni + CLI komutu). Auth kritik yolu (`.claude/rules/auth.md`) → ayrı epic + ADR.

### 4.3 [m · S] Giriş ekranında sunucu seçimi yoğun
- **Kanıt:** `features/auth/ui/auth_scaffold.dart:56-59` `ServerUrlTile(dense: true)` her giriş/kayıt ekranında. Self-host için şart, barındırılan sürüm kullanıcısı için gürültü.
- **Öneri:** varsayılan sunucu metin olarak ("alliswell.space'e giriş") + "Başka sunucu" bağlantısı.

---

## 5. Ekran ekran

| Ekran | Bulgu | Şiddet · Efor | Kanıt | Öneri |
|---|---|---|---|---|
| **Görev oluştur (tam form)** | 11 kontrol tek sütunda (başlık, açıklama, etiket, dosya, proje, öncelik, bitiş, hatırlat, acil alarm, tekrar, oluştur); "Oluştur" düğmesi kaydırmanın sonunda, klavye açıkken görünmüyor | M · S | `screenshots/android/08-create-task.png`, `screenshots/ios/09-create-task.png`; `task_create_sheet.dart:650-664` | Başlık + tek satır "çip" dizisi (Bitiş · Proje · Öncelik · Alarm · Tekrar) + "Daha fazla"; Oluştur düğmesini klavyenin üstüne yapışık yap |
| | Klavyedeki "Bitti" görevi oluşturmuyor | M · S | `task_create_sheet.dart:327` `TextInputAction.done`, `onFieldSubmitted` yok | Enter/Bitti = oluştur; masaüstünde ⌘/Ctrl+Enter |
| | Aşağı kaydırınca yazılan her şey uyarısız gidiyor | m · S | `task_create_sheet.dart:42-56` `showModalBottomSheet` (dismissible, `PopScope` yok) | Başlık doluysa "Taslağı at?" onayı ya da taslağı sakla |
| | Masaüstünde alt sayfa (560 px) | m · S | aynı, `constraints: maxWidth 560` | Geniş ekranda ortalı diyalog |
| **Görev detayı** | "Acil alarm" ve "Alarm susturuldu" iki yan yana anahtar, ters anlamlı (açık=çalar / açık=susar) | M · S | `task_detail_screen.dart:383-411`; `screenshots/ios/07-task-detail-repeat.png` | Tek "Alarm" satırı: Kapalı · Normal · Acil · Sessiz (segment ya da menü) |
| | Otomatik kayıt + silmede geri al: iyi | — | `task_detail_screen.dart:194-210`, `948-965` | Koru |
| | Uygulama çubuğunda tamamla/sil/⋯ ikonları; tamamla birincil eylem ama ikon | m · S | `task_detail_screen.dart:156-215` | Tamamla'yı başlığın yanında büyük onay dairesi yap (listeyle aynı simge) |
| **Hızlı ekleme** | 4 kontrol (C-06); gönderince tarih seçici açılıyor | M · S · **SAHİBE SORU** (C3) | `quick_add_bar.dart:234-266`; DESIGN §26 C3 | `?` ve ✨'yı koşullu yap (3.1); tarih sorusu yerine satır altında "Bugün · Yarın · Tarihsiz" çipleri (dokunmazsan seçili gün) |
| **Ana Sayfa** | Telefonda ay takvimi varsayılan açık, ilk ekranın ~%40'ı | M · S | `core/persisted_prefs.dart:60-61` `fallback: true`; `screenshots/ios/01-home.png` | Telefonda varsayılan hafta şeridi, ay ızgarası dokununca açılır |
| | Tamamlananlar listede üstü çizili kalıyor, "Bugün" bölümünü uzatıyor | m · S | `screenshots/ios/02-home-today.png` (8 üstü çizili satır) | Bölüm sonunda "8 tamamlandı ▸" katlanır satır (DESIGN §20 "stays, then moves" ruhu korunur) |
| **Fikirler (Inbox)** | Her satırda 3 ikon (planla, nota çevir, sil) daima görünür; sil bir dokunuş uzakta | m · S | `screenshots/ios/06-inbox.png`; `task_list_screen.dart:95-120` (onay diyaloğu) | Kaydırma eylemleri (sağa planla, sola sil) + tek ⋯; silme Ana Sayfa gibi geri al'lı olsun (tutarlılık) |
| **Pano** | Telefonda tek sütun + yandaki sütunun kenarı; sütun başlığında sayı var — iyi | m · S | `screenshots/ios/02-board.png` | Üstte sütun sekme/nokta göstergesi (kaçıncı sütun) |
| **Projeler + README** | Detay sekmeleri (Genel/Görevler/Notlar/Dosyalar) ve README iyi | — | `screenshots/web/project-readme.png` | Koru; proje listesine sayı (3.6) |
| **Notlar / Markdown** | Kaynak/Okuma iki büyük segment + 20+ ikonlu araç çubuğu + "Odak / Bölünmüş" — üç mod seçici katmanı | m · M | `screenshots/web/note-editor.png`; DESIGN §29.1 | Mod seçiciyi tek segmentte topla (Yaz · Böl · Oku), araç çubuğunu Okuma'da gizle |
| | Not silme onay diyaloğu, görev silme geri al — iki desen | m · S | `note_editor_screen.dart:311-325` vs `task_tile.dart:455-462` | Sürüm geçmişi olduğu için not silme de geri al'lı olabilir (DESIGN §19'a göre karar) |
| **Dosyalar** | "Klasörlerim / Kaynaklar" segment + "Dosyalar" kırıntı çipi + iki metin düğmesi; FAB yok (diğer bölümlerde var) | m · S | `screenshots/ios/05-files.png`; `home_shell.dart:169` (`files => null`) | Yeni klasör/dosya'yı + FAB menüsüne taşı → bölümler arası tutarlı birincil eylem |
| **Arama** | Küresel palet iyi (⌘K, ↑/↓, Enter, Esc — `global_search_palette.dart:293-300`) ama bölüm içi aramalar aynı büyüteçle ayrı | M · S | 1.4 | 1.4 |
| **Hızlı Erişim (masaüstü rail)** | Her satırda daima görünür ⋯ + sürükleme tutamağı → 7 satırda 14 gri simge | m · S | `screenshots/web/home-light.png` (rail), `quick_access_list.dart:80` | Tutamak ve ⋯ yalnız üzerine gelince |
| **AI** | AI iki farklı simgeyle temsil ediliyor: FAB'da mikrofon, hızlı eklemede ✨ | m · S | `ai_fab.dart:124` `mic_none_outlined`; `quick_add_bar.dart:260` `auto_awesome_outlined` | Tek AI simgesi (✨); mikrofon yalnız konuşma durumunda |
| | AI ayarları 1440 px'te dar tek kart | m · S | `screenshots/web/ai-settings.png` | 3.3 ile birlikte |
| **Ayarlar** | 7 grup, alt sayfalar gerçek rota — düzenli (DESIGN §32) | — | `settings_screen.dart:51-200` | Koru |
| | Tema seçimi yok (yalnız sistem) | m · S | `app.dart:52` `ThemeMode.system` | Genel'e "Görünüm: Sistem/Açık/Koyu" |
| | Hatırlatma sistemi ekranı: her uyarıda −/+/× üç ikon, 5 uyarıda 15 ikon | m · S | `screenshots/web/reminders.png` | Satıra dokun → süre seçici; kaydırarak sil |
| **Tamamlananlar** | Satır başına "geri al" + onay ikonu; kendi içinde iyi, yeri yanlış | m · S | `screenshots/web/completed.png` | 3.2 |
| **İçe aktarma** | Önizleme (adım 3/4) açık ve dürüst — iyi | — | `docs/screenshots/import-preview-light.png` | İlk açılışa bağla (4.1) |
| **Alarm yüzeyleri** | Çalma ekranı: tek dev "Onayla", 6 erteleme çipi, Tamamla/Aç ikincil — net hiyerarşi | — | `screenshots/android/09-alarm-ring.png` | Koru; "Süresiz sustur" yıkıcı → diğer çiplerden ayrı ton |

---

## 6. Klavye ve masaüstü verimliliği

- [M · M] **Tek global kısayol ⌘K/Ctrl+K.** Kanıt: core'da `SingleActivator` yalnız `search/ui/global_search_entry.dart:32-33`, palet içi ok/Enter (`global_search_palette.dart:293-300`) ve görsel görüntüleyici (`features/files/ui/image_viewer.dart:250-258`); listede gezinme, yeni görev, tamamla, detay kapatma kısayolu yok. Linear/Todoist'in temel değerlerinden biri tek tuş eylemler (genel bilgi).
- **Öneri (S→M):** `N`/`Q` yeni görev (hızlı eklemeye odak), `J/K` ya da ↑/↓ satır, `Enter` aç, `Esc` kapat, `X`/`Space` tamamla, `G H/I/P/N/F` bölüme git, `?` kısayol listesi; ⌘/Ctrl+Enter formu kaydet. Çakışma kuralı DESIGN §40 P1'deki gibi (odaktaki alan kazanır).
- [m · S] Masaüstünde her bölüm çubuğunda yenile ⟳ ikonu (`home_shell.dart:793`, `AwRefreshAction`) — senkron canlıyken (`sync:changed` soketi) görünür gürültü; ⋯ menüsüne ya da `F5`/⌘R'ye.

---

## 7. Yıkıcı eylemler ve geri alma — özet matrisi

| Nesne | Silme | Geri alma | Kanıt |
|---|---|---|---|
| Görev | kaydır / detayda çöp | **SnackBar geri al** | `task_tile.dart:455-462`, `task_detail_screen.dart:194-210` |
| Fikir (inbox) | satırda çöp | onay diyaloğu | `task_list_screen.dart:95-120` |
| Not | editörde çöp | onay diyaloğu (+ sürümler) | `note_editor_screen.dart:311-325` |
| Proje | ⋯ / kaydır | onay diyaloğu (kaskad) | `projects_screen.dart:141-160,256` |
| Klasör | ⋯ | onay diyaloğu | `files_screen.dart:157-181` |

Sonuç: kaskadsız tek nesneler (fikir, not) de geri al'a geçirilebilir; diyalog yalnız kaskadlı silmede (DESIGN §19'un kendi ilkesine uygun). [m · S]

---

## 8. "Tasarım hastası" gözüyle en çok rahatsız eden 15 şey (sıralı)

1. Seçili sekme etiketinin kapsülden taşıp içerikle çakışması (1.1).
2. Telefonda 5 ayrı yüzen nesne; FAB'ların başlık örtmesi (1.3).
3. Gövde metnindeki gevşek Material harf aralığı — SF Pro'da "Android'den port" hissi (2.1).
4. Sınırsız satırlı görev başlıkları; bir ekranda 3 görev (2.2).
5. Her satırda bayrak + zil + kum saati: sinyal yerine gürültü (2.3, 2.4).
6. İki klasör ikonu yan yana (Projeler/Dosyalar) (1.2).
7. İki farklı büyüteç, iki farklı kapsam (1.4).
8. Uygulama çubuğunda 5 ikon (1.4).
9. Çok satırlı satırda ortalanmış onay dairesi (2.3).
10. Alt çubuğun altında solma olmadan kesilen içerik (1.5).
11. Gecikmiş meta satırının kırmızı + kalın + büyük olması (2.5).
12. Hızlı ekleme alanında 4 kontrol; iki farklı "+" (3.1).
13. Kart-kart-kart düzeni, düşük yoğunluk (2.6).
14. Masaüstünde detay/ayarların rail'i kaybettirmesi; 1440 px'te 300 px sütun (3.3).
15. AI'nın iki simgesi (mikrofon/✨) ve iki ters anlamlı alarm anahtarı (5. bölüm).

## 9. En az değişiklikle en çok kazanç (S efor, yüksek etki)

| # | Değişiklik | Dosya | Etki | Not |
|---|---|---|---|---|
| Q1 | Alt çubuk etiketi: `overflow.visible` → `ellipsis/fade`, `labelSmall` + tracking 0, etiket kapsül içinde | `home_shell.dart:476-479`, `theme.dart:338-346` | Sahibin 1 numaralı şikâyeti | Yön seçimi (A/B/C) SAHİBE SORU; bu asgari düzeltme karara dokunmaz |
| Q2 | Apple'da body/label `letterSpacing: 0` | `theme.dart:112-130` | Bütün metin "native" | Tek blok |
| Q3 | Görev başlığı `maxLines: 2` + ellipsis | `task_tile.dart:186` | Ekranda 2× görev | Detayda tam metin |
| Q4 | `titleAlignment: top` | `task_tile.dart:177` (ya da `listTileTheme`) | Satır hizası | |
| Q5 | "Açık" durum ikonu ve varsayılan "orta" bayrağı satırda çizilmesin | `task_tile.dart:410-445` | Sağ küme 3–4 → 0–2 ikon | C1 varsayılanı değişmez |
| Q6 | Projeler sekme ikonu değişsin | `sections.dart:31` | Etiketsiz çubukta ayırt edilebilirlik | |
| Q7 | Alt kenara zemin tonunda solma gradyanı | `home_shell.dart:733-750` | Çakışma hissi biter | G1 uyumlu (cam değil) |
| Q8 | Oluştur formunda Enter = oluştur, düğme klavyeye yapışık | `task_create_sheet.dart:323-331,650` | Formun ana sürtünmesi | |
| Q9 | Hızlı eklemede `?` yer tutucu ipucuna, ✨ yalnız metin varken | `quick_add_bar.dart:251-266` | 4 → 2 kontrol | |
| Q10 | Telefonda takvim varsayılan kapalı/hafta şeridi | `persisted_prefs.dart:61` | İlk ekran işe ayrılır | |
| Q11 | Gecikmiş meta `bodySmall` w500 | `task_tile.dart:319-321` | Tipografik sakinlik | |
| Q12 | İlk-kez boş durumu: "İlk görevini ekle" + "Todoist'ten taşı" | `home_screen.dart:613-618` | Etkinleştirme | i18n'e 3 anahtar |
| Q13 | Tamamlananlar'a Ana Sayfa menüsünden giriş | `home_screen.dart:229-292` | Bulunabilirlik | Sekme eklemez |
| Q14 | Tek alarm kontrolü (detayda) | `task_detail_screen.dart:383-411` | Anlam karmaşası biter | S–M |

## 10. SAHİBE SORU listesi (bağlayıcı karara dokunanlar)

1. **ADR-0055 / DESIGN §40 P1** — "telefonda çoğunlukla yalnız seçili sekmenin etiketi": A (hep etiket, arama kapsül içinde), B (yatay hap), C (4 sekme) yönlerinden hangisi? (1.1)
2. **DESIGN §24 AI1** — ayrı AI mikrofonu FAB'ı kalsın mı, yoksa AI hızlı ekleme ✨ + `+` uzun basışa mı taşınsın? (1.3)
3. **DESIGN §23** — Hızlı Erişim balonu telefonda varsayılan açık mı kalsın? (1.3)
4. **DESIGN §26 C1** — "orta + acil" varsayılanı kalsın mı? (Kalsa da satırda yalnız sapma çizilmesi önerisi karara dokunmuyor.) (2.4)
5. **DESIGN §26 C3** — hızlı eklemede her gönderişte tarih seçici açılması kalsın mı, yoksa satır altı tarih çipleri mi? (5. bölüm)
6. **DESIGN §20 C4** — Tamamlananlar yalnız Ayarlar'da mı? (Ek giriş önerisi sekme eklemiyor.) (3.2)
7. **Inbox / "Fikirler"** — tek kavram hangisi? (3.4)

## 11. Bilinmeyenler

- Turun çekim klasörü boştu; güncel (2026-11) uygulama görüntüsü yalnız sahibin tek iPhone görüntüsü. Diğer ekranların bugünkü hâli kodla çıkarıldı, piksel düzeyinde **doğrulanmadı**.
- Değer anına kadar geçen süre ölçülmedi.
- Rakip desenleri Mobbin ile doğrulanmadı (MCP yetkisiz).
- Alt çubuk etiketinin kapsül **altına** düşmesinin kesin piksel nedeni (NavigationBar yüksekliği × `GlassSurface` kırpması) çalışma zamanında ölçülmeli; kod tarafındaki iki neden (54 px slot, `overflow.visible`) kesin.
