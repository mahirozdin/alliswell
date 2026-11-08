> **Depodaki kopya (2026-11-07, E35 kaydı):** uzantıya özgü tasarım ayrıntısı çıkarıldı (uzantı bulguları uzantı deposunda); turun iç çalışma dosyalarına ve ham kanıta verilen yollar düz metne çevrildi ("ham kanıt" = turun çalışma alanında kalan dosya; depoda yok). Bulgu kimlikleri değişmedi. Özet: [README.md](README.md).

# Landing denetimi: alliswell.space (keşif yüzeyi)

> Son güncelleme: 2026-11-07 — CEO tasarım/UX turu
> Kaynak: sahip brief'i (O-06, O-07, O-11, C-08); kod `apps/landing/**` (sürüm 1.18.2); ADR-0061, ADR-0036; `docs/DESIGN.md` §2 G-istisnası; `docs/COMPARISON.md`; canlı site (yalnız GET, 2026-11-07): https://alliswell.space, https://alliswell.space/tr, https://alliswell.space/enterprise, https://alliswell.space/app/; GitHub API (`repos/mahirozdin/alliswell`), iTunes lookup API; rakip ana sayfaları (linear.app, plane.so, vikunja.io, todoist.com, ticktick.com, cal.com: yalnız HTML GET). Ham materyal: ham kanıt (git dışı).

Bu belgede gerçek kullanıcı verisi yoktur. Ekran görüntüleri canlı sitenin kendi örnek verisinden (sample data) alındı. ham kanıt bu turda boştu; görüntüleri bu tur kendisi çekti (headless Chromium, CDP, 1440×900 ve 390×844).

---

## 1. Hüküm

**Ana sayfa iyi yapılmış ama satmıyor.** Ana sayfa teknik açıdan sağlam: sunucuda render ediliyor, hafif (HTML 47 KB, JS yaklaşık 40 KB br), alt metinleri, duraklatma düğmeleri ve film dökümü var, TR/EN kapıyla eşitleniyor. Görsel olarak da özenli. Dönüşümü ise beş şey öldürüyor:

1. **Ürün görülmüyor.** Hero ve tur döngüleri masaüstü kaydını küçültüp gösteriyor. Masaüstünde metin okunmuyor, telefonda (390 px) hiç okunmuyor.
2. **Kanıt sıfır.** Sayfanın hiçbir yerinde yıldız, kullanıcı, puan, referans ya da "açıkta geliştiriliyor" kanıtı yok. GitHub bağlantısı yalnız footer'da.
3. **Uygulamaya geçiş kopuyor.** "Open the web app" düğmesi yaklaşık 5 MB'lık Flutter açılışına, beyaz ekrana, sonra da kayıt değil **giriş** kartına götürüyor. Kartın kimliği başka (açık Glass, Roboto); sayfanın kimliği koyu Dusk ve Wix Madefor.
4. **Konumlama Vikunja ile çakışıyor.** H1 sahiplik vaadi ("…you own." / "on your server or ours") ile açılıyor; ayrıştırıcı (sessiz modu aşan alarm) alt cümlede kalıyor.
5. **Ölçüm yok.** Sitede hiçbir analitik yok. Hangi CTA'nın çalıştığı bilinmiyor.

Kurumsal sayfa ayrı bir dünya. Fabrika talep yönetimi satıyor, ayrı bir görsel dil kullanıyor ve tarayıcıda render ediliyor (tarayıcı motoru yalnız H1'i görüyor). Masaüstünde 26.474 px, mobilde 39.043 px uzunluğunda. Referans, güvenlik sayfası ve fiyat çıpası yok.

**Öncelik:** (a) hero görselini cihaza göre okunur yapmak, CTA'yı cihaza göre seçmek ve kanıt satırı eklemek (S–M); (b) uygulamaya geçişi düzeltmek: açılış ekranı ve kayıt modu (S–M); (c) ölçüm (S, sahibe soru); (d) herkese açık demo (L); (e) kurumsal sayfayı SSR'a almak ve kısaltmak (M–L).

## 2. 5 saniye testi

| Soru | Ana sayfa (EN/TR) | Kurumsal |
| --- | --- | --- |
| Ne? | Kısmen. "Tasks, notes and alarms you own." ürün sınıfını söylüyor ama görsel okunmadığı için ne tür bir uygulama olduğunu ekran doğrulamıyor (ham kanıt, `live-root-mob-fold.png`) | Evet: "Manage every work request in your factory in one place" (ham kanıt) |
| Kimin için? | Belirsiz. "you own" ve "Host it yourself" self-host meraklısını işaret ediyor, "Open the web app" bireysel kullanıcıyı, nav'daki "Enterprise" ise ekipleri. Üç kitleye birden konuşuyor | Net: fabrika genel müdürü, IT, bakım yöneticisi (`src/enterprise/page.js:16-20` yorumu) |
| Neden şimdi / neden bu? | Yok. Ayrıştırıcı ("ring through Silent mode") alt cümlede; acı (kaçırılan acil iş) söylenmiyor | Problem bölümü var (2. bölüm) ama ekranın altında |
| Sonraki adım? | İki eşit ağırlıkta düğme, üstte üçüncü bir CTA, satır içinde dört mağaza/indirme bağlantısı. Birincil hedef net değil | Net: "Get in touch" + PDF |

## 3. Dönüşüm katilleri (sıralı)

| # | Şiddet | Bulgu | Kanıt | Önerilen düzeltme | Efor |
| --- | --- | --- | --- | --- | --- |
| K1 | major | **Hero ve tur görselleri okunmuyor.** Masaüstü kaydı 52vw genişlikte gösteriliyor, satır metni yaklaşık 6–7 px. Telefonda aynı masaüstü kaydı 350 px'e iniyor. Turdaki beş döngünün tamamı da web arayüzü | `src/home/components/HeroDusk.vue:60-66` (`sizes="(min-width: 60rem) 52vw, 100vw"`), ham kanıt | Telefon genişliğinde (<40rem) hero'da **telefon kaydı** göster (iPhone posteri `get-phone` zaten var; aynı demo tohumundan 8–10 sn'lik bir telefon döngüsü). Masaüstünde döngüyü liste sütununa yakınlaştır (punch-in), en küçük metin ekranda ≥11 px olsun. Duraklat düğmesini uygulamanın + FAB'ının üstünden al (hero'da üst üste biniyorlar) | M |
| K2 | major | **Sosyal kanıt yok.** Ana sayfada yıldız, puan, kullanıcı sayısı ya da sürüm ritmi yok. GitHub yalnız footer'da. App Store'da puan 0/0. Repo 26 yıldız, 4 fork, homepage alanı boş | `src/content.js:237-269` (GitHub yalnız footer), iTunes lookup `id6794964494` → `userRatingCount: 0`, GitHub API → `stargazers_count: 26`, `homepage: null`; brief C-08 | Dürüst kanıt satırı: "Source on GitHub · 40 releases since July · Free for personal use". 40 sürüm GitHub releases API'sinden (ilki 2026-07-26, son v1.18.2 2026-10-30). Rakam build'de API'den alınmalı, elle yazılmamalı. Header'a sayısız bir "GitHub" düğmesi; sayı 100'ü geçene kadar gösterilmemeli (sahibin zevki). Repo'nun homepage alanını `https://alliswell.space` yapmak sahibin işi (dış hesap) | S |
| K3 | major | **Uygulamaya geçiş kopuyor.** `/app/` index'inde açılış göstergesi yok: `main.dart.js` 2,6 MB ve canvaskit.wasm 2,2–2,9 MB inene kadar beyaz ekran. Headless masaüstünde 15 sn sonra hâlâ beyazdı, 30 sn'de giriş kartı geldi (GPU kapalı headless; gerçek cihaz süresi **bilinmiyor**). CTA "Open the web app" diyor; açılan ekran ise **giriş** ("Sign in to your space"), kayıt değil. Görsel dil de değişiyor: koyu Dusk ve Wix Madefor'dan açık Glass ve Roboto'ya | ham kanıt (body yalnız `flutter_bootstrap.js`), `apps/app/web/index.html` (loading/splash yok), ham kanıt (15 sn beyaz), ham kanıt | (1) `apps/app/web/index.html` içine saf HTML/CSS açılış ekranı: marka işareti, "Opening AllisWell…", Glass zemin rengi ve `prefers-color-scheme`'e göre koyu varyant. (2) Landing CTA'sı kayıt moduna götürsün (`/app/?mode=signup` gibi bir parametreyi uygulama okusun) ve etiket "Start free" olsun. (3) Kartta "Continue with Google" üstte dursun (en düşük sürtünme). Not: geçişte iki kimliğin buluşması ADR-0061'in bilinçli sonucu; burada kimliği değiştirmeyi değil, köprüyü öneriyorum | S (splash) + S (mod parametresi) |
| K4 | major | **Herkese açık demo yok.** Self-host adayı denemek için ya hesap açmak ya da Docker kurmak zorunda. Kendi karşılaştırma belgemiz bunu Vikunja'ya karşı eksik olarak yazıyor. Vikunja nav'ında "Demo · No sign-up required" var | `docs/COMPARISON.md:313` ("a public demo … Not built"), ham kanıt | Demo tohumundan (O-09) her saat sıfırlanan, salt-okur ya da yazılabilir bir demo çalışma alanı. Hero altında üçüncül bağlantı: "Try the demo, no sign-up". API'de bir reset işi ve hesap kilidi gerekir | L |
| K5 | major | **Konumlama Vikunja ile çakışıyor.** AllisWell H1: "Tasks, notes and alarms you own.", alt cümle: "Run it on your server or ours." Vikunja H1: "The task manager you actually own.", alt cümle: "Self-host it or let us run it for you." Sahiplik vaadi bu pazarda ayırt edici değil. Ayırt edici olan alarm alt cümlede, MCP bağlayıcısı dördüncü bölümde | `src/content.js:60-61`, `src/content.tr.js:58-59`, ham kanıt (title + h1) | H1'i ayrıştırıcıyla aç (bkz. §6, Yön A). Sahiplik alt cümleye insin | S |
| K6 | major | **CTA hiyerarşisi dağınık.** Üç etiket tek hedefe gidiyor: header "Open the app", hero "Open the web app", indirme satırı "Open the app". Hero'da iki eşit hap düğme var. Mağaza bağlantıları satır içi küçük metin. Telefonda birincil CTA web uygulaması, App Store/Play değil | `src/content.js:54,62-63,194`, `src/home/components/HomeHeader.vue:62`, ham kanıt | Cihaza göre birincil CTA: iOS'ta "Get it on the App Store", Android'de Google Play, masaüstünde "Start free in your browser". İkincil CTA hep "Host it yourself" (ghost). Mağaza rozetleri hero altında. Header CTA'sı hero'yla aynı etiketi taşısın. SSR'da varsayılan masaüstü etiketi, hidrasyonda UA'ya göre değişim (CLS'siz, aynı genişlikte metin) | S |
| K7 | major | **Sitede ölçüm yok.** Landing'de hiçbir analitik ya da olay sayacı yok. Hangi CTA, hangi dil ve hangi kaynak dönüştürüyor bilinmiyor | `grep plausible\|gtag\|umami\|analytics apps/landing/src` → boş. Gizlilik politikası yalnız uygulamadaki Firebase'i anlatıyor (ham kanıt) | §8'deki olay listesi. Çerezsiz bir araç ya da kendi API'mizde kimliksiz sayaç. **SAHİBE SORU:** web sitesine ölçüm eklensin mi? Gizlilik politikasına bir paragraf girmesi gerekir | S–M |
| K8 | major | **Kurumsal sayfayı tarayıcı motoru görmüyor.** Sayfa boş kaba mount ediliyor. HTML'de yalnız H1, lede ve Cloudflare'in gizlediği "[email protected]" var. 27 bölümlük içerik JS ile geliyor | `scripts/routes.js:29-37` (enterprise `ssr` yok), ADR-0061 karar 3 ("The enterprise entries still mount into an empty container"), ham kanıt (7,9 KB) | Ana sayfanın SSR hattını (`entry-server.js` + `prerender.mjs`) kurumsala da uygula. ADR-0036/0061'e ek gerekir (ADR, sahip kararı değil) | M |
| K9 | major | **Kurumsal sayfa çok uzun ve B2B güven sinyalleri eksik.** Masaüstünde 26.474 px (~29 ekran), mobilde 39.043 px (~46 ekran). Müşteri logosu, vaka çalışması ya da pilot referansı yok. Güvenlik sayfası yok (yalnız GitHub'daki SECURITY.md'ye bağlantı). Fiyat çıpası yok ("Prices are quoted by your size"). Demo ayırtma takvimi yok (form + mailto var). İngilizce sayfadaki örnek kayıtlar Türkçe | ham kanıt (yükseklik + 27 H2), ham kanıt (40 kare), `src/enterprise/content.en.js:110-112` (Türkçe örnek veri notu), `:1229-1231`, `:1421` | Bölümleri 3 kümede topla, uzun "AnnotatedShots" dizisini sekmeli bir tura çevir; hedef ≤ 12.000 px masaüstü. Yapışkan "Book a demo" çubuğu. "Security & data" alt sayfası (barındırma yeri, yedek, SSO/AD, KVKK, denetim kaydı saklama süreleri, sızma testi durumu: yalnız gerçek olanlar). EN sayfa için İngilizce demo tohumu. **SAHİBE SORU:** sıra bilinçli olarak 18 sayfalık satış sunumunu izliyor (`src/enterprise/page.js:16-20`, OPH-388); sunumdan ayrılmak kabul mü? Başlangıç fiyatı yazılsın mı? | M–L |
| K10 | major | **Kullanım koşulları yok, bilinmeyen her yol 200 dönüyor.** `/terms`, `/pricing`, `/security`, `/favicon.ico`, `/manifest.webmanifest` ana sayfanın HTML'ini 200 ile döndürüyor (soft 404). Barındırılan hizmet hesap açtırıyor ama koşullar sayfası yok | `public/.htaccess:70-71` ("Everything else → the marketing site"), curl: `/terms` 200 47029 B = ana sayfa (ham kanıt) | (1) Sahip ve hukuk tarafından yazılacak Terms of Service (EN/TR), footer'da ve kayıt kartında bağlantı. Metin sahibin işi. (2) `.htaccess` son kuralını gerçek bir 404 sayfasına çevir; ana sayfa artık SPA değil, SSR. (3) Kökte gerçek `favicon.ico` | S (404) / sahip (metin) |
| K11 | minor | **"Enterprise" etiketi beklentiyle uyuşmuyor ve ekip katmanı yok.** Ana sayfa nav'ında "Enterprise" fabrika talep yönetimine gidiyor. Bireysel uygulamada paylaşım ve atama yok ("What is missing? Sharing and assignees"). Küçük bir ekibin gidecek yeri yok | `src/content.js:52`, `:231-232`, ham kanıt | Nav etiketi "For factories" / "Fabrikalar için" olsun (beklenti eşleşir, S). **SAHİBE SORU:** fabrika dışı ekipler için bir teklif var mı, yoksa sayfa bunu açıkça "yok" mu desin? | S |
| K12 | minor | **Fiyatlandırma belirsiz.** Barındırılan sürümün ücretsiz olduğu söyleniyor ama sınırları (depolama, dosya boyutu, süre) yazmıyor. Ticari lisans FAQ'ın içinde, yalnız mailto ile. Rakiplerin hepsinde nav'da "Pricing" var | `src/content.js:164,212`; rakip HTML'lerinde "Pricing" sayısı: Linear 11, Plane 7, Vikunja 4, Todoist 18, TickTick 5, Cal.com 23 (ham kanıt) | Ana sayfaya kısa üç kolonlu bir "Pricing" bölümü: Personal (ücretsiz, bizde ya da sizde) · Business self-host lisansı (iletişim) · Enterprise (kurumsal sayfaya). **SAHİBE SORU:** barındırılan ücretsiz katmanın sınırları ve ticari lisansın çıpa fiyatı | S (metin) |
| K13 | minor | **İddia tutarsızlığı.** GitHub açıklaması "Open-source" ve "two-way Google/Apple Calendar sync" diyor. `/app/` meta açıklaması "Open source and self-hostable" diyor. Landing'in kuralı ise source-available ve Apple'ın tek yönlü olması | GitHub API `description`; ham kanıt meta; `src/content.js:5-7` (iddia kuralları) | GitHub açıklamasını "Source-available, self-hostable … two-way Google Calendar sync, Apple Calendar mirror" yap (sahibin GitHub ayarı). `apps/app/web/index.html` meta metnini düzelt | S |
| K14 | minor | **Mobil ritim.** Karşılaştırma tablosu telefonda 6×4 satırlık bloklara açılıyor ve yaklaşık 2 ekran sürüyor. Turda sekmeler bir ekranı dolduruyor, seçilen sekmenin videosu altta kalıyor. Bölüm aralıkları 72–96 px | ham kanıt, `en-mob-06.jpg`, `en-mob-01.jpg`; `src/home/styles/base.css:24` | Telefonda karşılaştırma iki sütunlu olsun (AllisWell ve "çoğu rakip") ya da ilk sütun sabit, yatay kaydırmalı. Turda seçilen sekmenin videosu sekmenin hemen altında açılsın (akordeon) | S–M |
| K15 | minor | **Karşılaştırma yanlış rakiplere bakıyor.** Tabloda Google Calendar, Apple Reminders ve Things 3 var. Self-host adayının baktığı Vikunja, Todoist ve TickTick yok. `docs/COMPARISON.md` §7 bu alanı zaten karşılaştırıyor (Vikunja 16 kez geçiyor) | `src/content.js:177`, `docs/COMPARISON.md:11,313-355` | Sütunlar: AllisWell · Todoist · TickTick · Vikunja. Her hücre COMPARISON.md'de dayanaklı olsun; `check:copy` iddia kuralları korunur | S |

## 4. Alan alan ayrıntı

### 4.1 Hero mesajı ve CTA hiyerarşisi
- Yapı: H1 → tek cümle → iki hap düğme → "Also on iPhone, Android, Windows and Linux." (`src/home/components/HeroDusk.vue:46-58`, `src/content.js:59-78`).
- GitHub, Enterprise ve demo hero'da yok. Self-host ikincil düğme olarak var; bu doğru sıra.
- Önerilen hiyerarşi: **birincil** hosted kayıt (masaüstünde web, telefonda mağaza), **ikincil** self-host, **üçüncül** metin bağlantıları ("Try the demo" ve "Star on GitHub"), **nav'da** "For factories". Kurumsal satış ana sayfa hero'suna girmemeli; kitleler ayrı.

### 4.2 Kanıt
- Mevcut: "Recorded from the app with sample data." başlığı (dürüstlük sinyali, iyi). Footer'da "Built in the open, one task at a time."
- Kullanılabilir dürüst kanıtlar: 40 sürüm (2026-07-26 → 2026-10-30), 707 commit (GitHub API `commits?per_page=1` → `page=707` last), altı platform, MCP bağlayıcısı, açık yol haritası. Kullanıcı sayısı ve puan **bilinmiyor** ya da yok (App Store 0 değerlendirme). Uydurma kanıt yazılmaz.
- Eski bileşenlerde yıldız sayacı hazır: `src/components/TheHeader.vue:39,60` (`showStars`), `src/composables/useGithubStars.js:38`. Ana sayfa izolasyonu (ADR-0061 karar 4) nedeniyle doğrudan import edilemez; `src/home/` altında küçük bir kopya gerekir.

### 4.3 Ürün görsellerinin gerçek arayüzle tutarlılığı
- Görseller gerçek uygulamadan, demo tohumundan alınmış ve bunu dürüstçe yazıyor (iyi). Hero döngüsü koyu temada, turdaki pano ve not döngüleri açık temada (ham kanıt). Koyu sayfada açık kartlar parlıyor ama tutarlılığı bozmuyor.
- **Risk:** sahip uygulamanın alt barını ve mobil düzenini beğenmiyor (brief O-02, C-01..C-07). Mobil iyileştirmeler gelince `get-phone` posteri ve önerilen telefon döngüsü yeniden üretilmeli. Aksi halde landing eski arayüzü gösterir. Bunu medya hattının (`npm run media:promote`) tetikleyicisine bağlayın.

### 4.4 Dusk ↔ Glass kopukluğu
- Durum: ana sayfa bilinçli bir istisna; koyu, Wix Madefor, fotoğraflı (`docs/DESIGN.md:56-59`, ADR-0061 karar 1–2). Kurumsal sayfa açık Glass ve sistem fontu (`src/style.css:128-137`). Uygulamanın web girişi açık Glass, Flutter web'de Roboto (ham kanıt).
- Kullanıcının yolu: koyu turuncu gün batımı → beyaz ekran → açık mavi giriş kartı. Ana sayfadan kurumsala geçen biri de iki farklı şirket görüyor (ham kanıt ve `sheet-en-desk.jpg`).
- Kimliği birleştirmeyi önermiyorum (O-03 KESİN ve ADR-0061 bağlayıcı). Köprüler:
  1. `/app/` açılış ekranı. Marka işaretini ve ana sayfanın arduvaz zeminini (`#0e1017`, `index.html:6` theme-color) koyu tercihte kullanabilir; Glass token'ı olarak eklenir (S).
  2. Kurumsal sayfanın header'ında ana sayfaya dönüş bağlantısı ("Personal app"), ana sayfa nav'ında "For factories" (S).
  3. Ana sayfa ürün görsellerinde kart çerçevesi Glass'ın "lit edge"ini taşıyor; bu ortak öğe korunmalı.
- **SAHİBE SORU (zevk):** kurumsal sayfa da Dusk'a geçsin mi, yoksa B2B için açık Glass mı kalsın? İki yön: (a) kurumsal açık kalır, yalnız tipografi ana sayfayla eşitlenir; (b) kurumsal da koyu Dusk olur. Mevcut ADR'ler (a)'nın tipografi kısmına bile ek gerektirir.

### 4.5 Tipografi
- Ana sayfa: Wix Madefor Display ve Text, kendi sunucumuzdan; Display için preload var (`index.html:93`, `public/fonts/*.woff2`). Başlıklarda `text-wrap: balance` (`src/home/styles/base.css:8`). Hiyerarşi güçlü, satır uzunlukları sınırlı (46–70ch, `home.css:500,571,850`). İyi.
- Zayıf noktalar: footer'daki dev "AllisWell" kelime işareti mobilde tek başına bir ekran kaplıyor (ham kanıt). Hero'daki "Also on…" satırında bağlantılar 16 px'lik altı çizili metin; dokunma hedefi muhtemelen 44 px'in altında (ölçülmedi, **NOT RUN**). Kurumsal sayfada H1 800 ağırlıkta ve sistem fontunda; ana sayfayla ses farkı büyük.
- Uygulama tarafı (C-04 tracking vb.) bu belgenin kapsamı dışında; ilgili raporlara bakın.

### 4.6 Mobil landing
- Hero metni ve CTA'lar ilk ekrana sığıyor; görsel okunmuyor (K1). Telefonda birincil CTA yanlış (K6).
- Header'da telefonda CTA yok, yalnız dil ve menü var (ham kanıt). Kaydırınca CTA'ya dönmek için yapışkan bir alt çubuk düşünülebilir (S). Hallmark kuralına aykırıysa vazgeçilir.
- Toplam yükseklik 9.576 px (390 px genişlik, ham kanıt). Karşılaştırma ve footer bunun yaklaşık %30'u.

### 4.7 TR/EN tutarlılığı
- Anahtar ağacı `check:copy` ile eşit tutuluyor (`src/content.js:2-3`). TR metin çeviri kokmuyor: "Görevler, notlar, alarmlar. Hepsi sizin." (`src/content.tr.js:58`).
- Dil yönlendirmesi: Türkçe tarayıcı İngilizce sayfadan `/tr`'ye yönleniyor, ters yön yok. hreflang üçlüsü doğru (`index.html:18-32,67-69`; sitemap'te de var).
- Küçük tutarsızlıklar: CTA etiketleri iki dilde de üç farklı biçimde (K6). Kurumsal EN sayfasında Türkçe örnek veri var (K9).

### 4.8 SEO
- İyi: SSR ana sayfa; canonical, hreflang, OG 1200×630 (EN/TR ayrı görsel, canlıda 200), Twitter kartı, `SoftwareApplication` ve `VideoObject` JSON-LD, sitemap, `llms.txt` (`index.html:56-134`, `src/home/head.js`).
- Eksikler:
  - Kurumsal SSR yok (K8).
  - Soft 404 (K10). Yinelenen içerik riski var; `/pricing` gibi bir arama sonuç sayfası ana sayfa olarak dizinlenebilir.
  - Sitemap'te `lastmod` yok; `/docs/api` ve `/docs/mcp` için hreflang yok (ham kanıt).
  - Gizlilik, destek ve doküman sayfalarında `og:image` yok.
  - JSON-LD `Organization` için `logo` yok. `downloadUrl` web uygulamasına işaret ediyor.
  - `FAQPage` şeması eklenebilir ama Google bu zengin sonucu 2023'ten beri sınırlı sitelere gösteriyor; düşük değer.
  - Başlık "AllisWell: tasks, notes and alarms you can host yourself". Arama niyetine ("self-hosted todo app", "todoist alternative self hosted") yakın; "Todoist alternative" ifadesi GitHub topic'lerinde var ama sayfada yok.
- robots.txt Cloudflare yönetiminde: `ClaudeBot`, `CCBot` vb. eğitim tarayıcılarını engelliyor, `Content-Signal: search=yes, ai-train=no` (ham kanıt). Bu bilinçli bir seçim gibi duruyor. Ancak AI asistanlarında keşif (ChatGPT/Claude arama) için `ai-input` sinyali açıkça belirtilmemiş. **SAHİBE SORU:** AI arama yanıtlarında görünmek isteniyor mu?

### 4.9 Performans
- Ölçülen değerler (curl, 2026-11-07):
  - HTML 47 KB, TTFB ve toplam 0,45–0,75 sn (`cf-cache-status: DYNAMIC`, `cache-control: no-cache, no-store`).
  - JS: `site-*.js` 79 KB (br 32 KB), `alternates-*.js` 25 KB (br 8 KB), `index-*.js` 9 KB (br 4 KB).
  - CSS 24 KB (br 6 KB).
  - Hero fotoğrafı AVIF 8,6 / 16,9 / 28 KB (960/1600/2400). Hero döngüsü 1,28 MB, eager.
  - Diğer döngüler 0,19–1,42 MB, lazy. Film 5,9 MB, kullanıcı oynatınca iner.
  - Ham liste: ham kanıt.
- Bütçeler kapıda (`scripts/media-budgets.js`). Ana sayfada sorun yok.
- İyileştirme: HTML'i Cloudflare kenarında kısa TTL'li önbelleğe almak (S, sahibin altyapısı). Telefonda hero döngüsünü (1,28 MB) poster + dokununca oynat yapmak ya da K1'deki daha küçük telefon döngüsüyle değiştirmek.
- Asıl darboğaz uygulamaya geçiş (K3).
- Lighthouse/CWV ölçümü bu turda **NOT RUN**. Gerçek LCP/INP bilinmiyor.

### 4.10 Erişilebilirlik
- İyi taraflar:
  - "Skip to the tour" atlama bağlantısı var.
  - Bütün görsellerde alt var (`imgsNoAlt: 0`, ham kanıt).
  - Her döngüde duraklatma var, fotoğraf kayması da aynı düğmeyle duruyor (`HeroDusk.vue` yorumu, WCAG 2.2.2).
  - Film için metin dökümü ve VTT altyazı var.
  - Tek H1 ve sıralı H2'ler. `lang` doğru.
- Riskler:
  - Hero duraklat düğmesi uygulama kaydındaki + FAB'ın üstüne biniyor; görsel karışıklık var, işlev sorunu değil (ham kanıt).
  - Satır içi bağlantılarda dokunma hedefi (4.5).
  - Kurumsal sayfada JS kapalıyken içerik yok (K8).
- Kontrast bu turda yeniden ölçülmedi; ADR-0061 sloplint render katmanına dayanıyor (**NOT RUN**).

### 4.11 Kurumsal sayfa (B2B alıcı gözüyle)
- Var olanlar: net hero; problem ve yolculuk; gerçek ekranlar; bulut ya da kendi sunucu seçeneği; üç paket (Starter, Business, Enterprise) ve kullanıcı/birim sınırları; KVKK; çevrimdışı çalışma; Active Directory; PDF sunum (EN 1,6 MB); iletişim formu (ad, kurum, iş e-postası, telefon, kişi ve birim sayısı, seçenek, mesaj) (`src/enterprise/content.en.js:92-118,1203-1282`).
- Eksikler (K9):
  - Referans ya da pilot hikâyesi.
  - Güvenlik ve uyum sayfası.
  - Başlangıç fiyatı ya da "pilot şu kadar sürer" çıpası.
  - Takvimden demo ayırtma.
  - Yanıt süresi sözü ("we reply within one working day"; gerçekse).
  - Yapışkan CTA.
  - EN alıcı için İngilizce örnek veri.
  - Satın alma sürecinin adımları (pilot → sözleşme → kurulum).
- Not: uzantının iç tasarımı bu belgeye alınmadı (I-14). Yalnız herkese açık sayfanın söyledikleri değerlendirildi.

### 4.12 Fiyatlandırma ve hukuk
- Fiyat: K12. Hukuk:
  - Gizlilik politikası EN/TR mevcut, "Last updated: 2026-10-17", GDPR ve KVKK geçiyor (ham kanıt).
  - Kullanım koşulları **yok** (K10).
  - Ticari lisans yalnız mailto ile.
  - Footer'da şirket unvanı ve "Not affiliated with…" notu var. Fotoğraf ve font lisansları kredilendirilmiş (iyi).
  - Kurumsal formda veri işleme onayı ve gizlilik bağlantısı var (ham kanıt, son satır).

## 5. Rakip desenleri (ilham; metin ve görsel kopyalanmaz)

| Rakip | Hero deseni (canlı HTML, 2026-11-07) | AllisWell için ders |
| --- | --- | --- |
| Vikunja (vikunja.io) | Sahiplik H1'i, "Self-host it or let us run it", nav'da **Demo (no sign-up)**, Pricing, Changelog | Aynı vaadi zaten söylüyor: ayrışmak için alarm ya da MCP öne alınmalı. Demo eksiğimiz burada görünür |
| Plane (plane.so) | "Get started free" + "Talk to a human", "Cloud, self-hosted and air-gapped ready" satırı, "Trusted by teams at" logoları, nav'da Self-host | Dağıtım seçeneklerini tek satırda söylemek; ekip ve kurumsal yolu ayrı bir düğmeyle açmak |
| Linear (linear.app) | Tek iddia, tek birincil CTA, ürün ekranı okunur ölçekte | Ürün ekranını okunur ölçekte göstermek (K1) |
| Todoist (todoist.com) | Kısa duygusal H1, meta açıklamada sayılı kanıt ("Trusted by 30 million…"), "Start for free" tekrarı | Kanıtı ilk ekrana koymak. Bizde sayı yoksa sürüm ritmi ve kaynak kodu açık (source-available) kanıtı: GitHub, sürüm sayısı |
| TickTick (ticktick.com) | "Start for free" + platform senkronu bölümü | Platform rozetleri hero'ya yakın |
| Cal.com (cal.com) | Açık kaynak + "Book a demo" + Pricing, GitHub vurgusu | Kendi sunucunda kullanımla B2B'yi aynı sitede iki net yolla taşımak (bizde lisans source-available) |

Kaynak dosyalar: ham kanıt. Yalnız ana sayfa HTML'i incelendi; görsel ve akış karşılaştırması **yapılmadı**.

## 6. Önerilen metinler (kelimesi kelimesine; Hallmark kuralları: tire yok, emoji yok, eyebrow yok; iddia kuralları `src/content.js:5-10`)

### Yön A: alarm önde (önerim)
| | EN | TR |
| --- | --- | --- |
| H1 | Reminders that ring through Silent mode. | Sessiz modda bile çalan hatırlatıcılar. |
| Alt başlık | Tasks, notes and files in one app. Urgent ones ring like an alarm and ask again for half an hour. Free for personal use, on our server or yours. | Görevler, notlar ve dosyalar tek uygulamada. Acil olanlar alarm gibi çalar, yarım saat boyunca yeniden sorar. Kişisel kullanım ücretsiz; bizim sunucumuzda ya da sizinkinde. |
| Birincil CTA (masaüstü) | Start free in your browser | Tarayıcıda ücretsiz başlayın |
| Birincil CTA (iOS / Android) | Get it on the App Store / Get it on Google Play | App Store'dan indirin / Google Play'den indirin |
| İkincil CTA | Host it yourself | Kendi sunucunuza kurun |
| Üçüncül bağlantılar | Try the demo, no sign-up · Star on GitHub | Hesap açmadan deneyin · GitHub'da yıldızlayın |
| Kanıt satırı | Source on GitHub · 40 releases since July · iPhone, Android, web, Windows and Linux | Kaynak kodu GitHub'da · Temmuz'dan bu yana 40 sürüm · iPhone, Android, web, Windows ve Linux |

### Yön B: sahiplik ve alarm birlikte
| | EN | TR |
| --- | --- | --- |
| H1 | Your tasks on your server. Your alarms through Silent mode. | Görevleriniz kendi sunucunuzda. Alarmlarınız sessiz modda bile. |
| Alt başlık | One app for tasks, notes and files on every device. Run it with one command, or use ours for free. | Görev, not ve dosyalar için her cihazda tek uygulama. Tek komutla kendiniz kurun ya da bizimkini ücretsiz kullanın. |
| CTA | Start free · Host it yourself | Ücretsiz başlayın · Kendi sunucunuza kurun |

### Yön C: asistan önde
| | EN | TR |
| --- | --- | --- |
| H1 | Ask Claude about your day. Keep the data on your server. | Gününüzü Claude'a sorun. Veriniz kendi sunucunuzda kalsın. |
| Alt başlık | Tasks, notes and alarms with a connector for Claude and ChatGPT. Every change waits for your approval. | Claude ve ChatGPT bağlayıcısıyla görevler, notlar ve alarmlar. Her değişiklik onayınızı bekler. |
| CTA | Start free · Connect Claude | Ücretsiz başlayın · Claude'a bağlayın |

Not: C, "AI şart" algısı yaratabilir; FAQ "Do I need AI to use it? No." ile dengelenmeli. "Ücretsiz/yerleşik AI" iddiası yok (kural).

### Diğer metinler
- Nav "Enterprise" → EN "For factories", TR "Fabrikalar için".
- Kurumsal yapışkan CTA: EN "Book a 30-minute demo", TR "30 dakikalık demo ayırtın". İkincil: EN "Download the deck (PDF)", TR "Sunumu indirin (PDF)".
- Kurumsal güven satırı (yalnız doğruysa): EN "Pilot with one unit first. Installation and migration by us. Data stays in Türkiye or on your servers." TR "Önce tek birimle pilot. Kurulum ve aktarım bizden. Veri Türkiye'de ya da sizin sunucunuzda." Veri yeri iddiası **doğrulanmadı**; sahip onaylamadan yayımlanmaz.
- `/app/` açılış ekranı: EN "Opening AllisWell…", TR "AllisWell açılıyor…".

## 7. Bölüm sırası önerisi (ana sayfa)

Mevcut sıra (`src/home/HomePage.vue:30-37`): Hero → Tour → Film → Assistant → Own it → Compare → Get it → FAQ.

Önerilen sıra:
1. **Hero:** Yön A, cihaza göre CTA, okunur ürün görüntüsü.
2. **Kanıt ve platform şeridi:** kanıt satırı ve mağaza rozetleri (yeni, ince).
3. **Tour:** beş sekme; telefonda telefon kayıtları.
4. **Compare:** Todoist, TickTick, Vikunja (K15). Yukarı alındı, çünkü geçiş yapan kullanıcının sorusu bu.
5. **Assistant:** MCP.
6. **Own it:** self-host, tek komut.
7. **Pricing:** yeni; Personal, Business lisansı, Enterprise.
8. **Get it:** indirmeler.
9. **FAQ.**
10. Film ayrı bölüm olmaktan çıkıp hero'da "Watch the 1-minute film" bağlantısı olsun (lightbox), ya da Tour'dan sonra kalsın. **SAHİBE SORU (zevk):** film bölümü ADR-0061'in parçası.

Kelime bütçesi: Hallmark tavanı yaklaşık 450 görünür kelime (`check:copy`). Pricing ve kanıt eklenirken film bölümü ve footer kısaltılarak bütçe korunmalı.

## 8. Ölçüm planı (hangi olaylar)

Kimlik ve çerez yok. Yalnız sayaç ve oturum içi huni. Araç seçimi **SAHİBE SORU** (K7). Seçenekler: (a) Cloudflare Web Analytics (çerezsiz, yalnız sayfa görüntüleme; özel olay yok); (b) kendi barındırdığımız Plausible ya da Umami; (c) API'de kimliksiz bir `POST /api/v1/metrics/landing` sayacı.

| Yüzey | Olay | Özellikler |
| --- | --- | --- |
| Landing | `page_view` | lang, path, referrer host, utm_source/medium/campaign, cihaz sınıfı |
| Landing | `cta_click` | id: `hero_primary`, `hero_secondary`, `header`, `demo`, `github`, `store_ios`, `store_android`, `download_windows`, `download_linux`, `macos_source`, `nav_factories`, `pricing_*` |
| Landing | `tour_tab` | pane id |
| Landing | `film_play`, `film_50`, `film_done` | lang |
| Landing | `copy` | `mcp_url`, `selfhost_command` |
| Landing | `faq_open` | soru id |
| Landing | `lang_switch` | from, to |
| Landing | `scroll_depth` | 25/50/75/100 |
| Web app | `app_boot_ms` | ilk kareye kadar süre (açılış ekranı K3 sonrası) |
| Web app | `auth_view` | mode: signin/signup, kaynak (`?from=landing_hero` gibi) |
| Web app | `signup_complete` | method: email/google |
| Web app | `first_task_created` | kayıttan sonraki dakika |
| Kurumsal | `deck_download` | lang |
| Kurumsal | `contact_view`, `contact_start`, `contact_submit`, `contact_error`, `mailto_click` | — |
| Kurumsal | `section_reach` | anchor (uzunluk kararı için) |
| GitHub | yıldız, fork, referrer trafiği | haftalık; GitHub Insights → Traffic (sahibin hesabı) |

Kuzey yıldızı hunisi: ziyaret → `cta_click` → `signup_complete` → 10 dakika içinde `first_task_created`. Self-host için: ziyaret → `copy:selfhost_command` / `github` tıkı → yıldız. Kurumsal için: ziyaret → `contact_submit` ya da `deck_download`. Hedefler ölçüm başladıktan sonra iki haftalık taban çizgisinden konur; şimdi rakam **bilinmiyor**.

## 9. Sahibe sorular (özet)

1. **K7.** Web sitesine çerezsiz ölçüm eklensin mi, hangi araçla? Gizlilik politikası güncellenir.
2. **K9.** Kurumsal sayfa sıra olarak satış sunumunu izlemeye devam etsin mi, yoksa kısaltılsın mı? Başlangıç fiyatı ya da pilot çıpası yazılsın mı?
3. **K11.** Fabrika dışı ekipler için bir teklif var mı?
4. **K12.** Barındırılan ücretsiz katmanın sınırları ve ticari lisans fiyat çıpası ne?
5. **4.4.** Kurumsal sayfa tipografisi ya da teması ana sayfayla eşitlensin mi (iki yön)?
6. **4.8.** AI arama yanıtlarında görünmek için `ai-input` sinyali açılsın mı?
7. **§7.** Film ayrı bölüm olarak kalsın mı?
8. Sahibin işleri: GitHub homepage alanı ve açıklaması (K2, K13); Kullanım Koşulları metni (K10); Cloudflare HTML önbelleği (4.9).

## 10. Yapılmayanlar ve bilinmeyenler

- Lighthouse/CWV, kontrast ölçümü ve dokunma hedefi ölçümü: **NOT RUN**. Ekran görüntüleri ve curl ölçümleri var.
- Web uygulamasının gerçek cihazdaki açılış süresi **bilinmiyor**. Headless ve GPU kapalı ortamda 15 sn'de beyaz, 30 sn'de render edilmişti.
- Trafik, dönüşüm ve kaynak verisi **yok**, çünkü sitede ölçüm yok.
- Rakip analizinde yalnız ana sayfa HTML'leri okundu (başlık, H1, CTA sayıları); görsel kıyas yapılmadı.
- Mobbin MCP bu turda kullanılmadı (bu alt görevin kapsamı dışında).
- Kurumsal PDF sunumu açılıp okunmadı; yalnız varlığı ve boyutu doğrulandı.

## Ek: ham dosyalar

Ekran görüntüleri, kaydırma kareleri, canlı HTML ve rakip sayfaları tur çalışma alanında kaldı (depoda yok).
