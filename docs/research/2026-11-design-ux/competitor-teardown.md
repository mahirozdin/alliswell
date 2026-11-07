> **Depodaki kopya (2026-11-07, E35 kaydı):** uzantıya özgü tasarım ayrıntısı çıkarıldı (uzantı bulguları uzantı deposunda); turun iç çalışma dosyalarına ve ham kanıta verilen yollar düz metne çevrildi ("ham kanıt" = turun çalışma alanında kalan dosya; depoda yok). Bulgu kimlikleri değişmedi. Özet: [README.md](README.md).

# Rakip ve emsal analizi: keşif yüzeyleri ve ürün sunumu

> Son güncelleme: 2026-11-07 — CEO tasarım/UX turu
> Kaynak: sahip brief'i (O-06, O-07, O-11, C-08) · GitHub REST/GraphQL (`gh api`, salt okunur) · Wayback Machine anlık görüntüleri · awesome-selfhosted, YunoHost ve Coolify katalogları · HN Algolia araması · iTunes Lookup API · rakip landing sayfaları (curl + WebFetch) · depo dosyaları (`README.md`, `docs/COMPARISON.md`, `docs/STATE.md`, `apps/landing/src/content.js`)

Ham materyal (README kopyaları, JSON'lar, landing HTML'leri ve App Store görselleri) tur çalışma alanında kaldı (depoda yok); aşağıda "ham kanıt" diye geçer. Rakiplerin metni ve görseli kopyalanmadı; yalnız desenleri tarif ediliyor. Kısa alıntılar sadece kanıt için ve tırnak içinde verildi.

---

## 1. Yöntem ve sınırlar

| Ölçüm | Nasıl alındı | Ham dosya | Sınır |
| --- | --- | --- | --- |
| Yıldız, lisans, homepage, özel social preview, sürümler, Discussions | GraphQL `repository{…usesCustomOpenGraphImage releases(first:100)…}` | ham kanıt | "12 ayda sürüm" son 100 sürümden sayıldı; Twenty'de bu sayı tavana dayanıyor, gerçek değer ≥95. |
| **Yıldız ivmesi** | GitHub artık başka depoların stargazer listesini vermiyor (REST 404, GraphQL boş liste döndü). Bu yüzden yaklaşık 12 ay önceki yıldız sayısı Wayback Machine anlık görüntüsündeki `repo-stars-counter-star` değerinden okundu. | ham kanıt | Anlık görüntü tarihleri 2025-10-27 ile 2025-11-13 arasında; Δ/ay değeri bu aralıktan hesaplandı. Ad değiştiren depolar eski adlarıyla arandı (`calcom/cal.com`, `johannesjo/super-productivity`). |
| README ilk ekranı | README ham olarak indirildi, ilk 60 satır okundu | ham kanıt | GitHub'ın README'yi nasıl çizdiği görülmedi, yalnız kaynak okundu. |
| awesome-selfhosted | `README.md` ve `non-free.md` içinde ad arandı; katılım kuralları da okundu | ham kanıt | — |
| Tek tıkla kurulum katalogları | YunoHost `apps.json` ve Coolify `templates/compose` | ham kanıt | Unraid, TrueNAS, CasaOS, PikaPods ve Railway şablon dizinleri **bakılmadı**. |
| Lansman izleri | HN Algolia, yalnız `story` etiketi | ham kanıt | **Reddit doğrulanamadı**: reddit.com JSON isteği engellendi (ham kanıt boş HTML döndü), web aramasında da yalnız ikincil arşivler çıktı. Planka ve Twenty aramaları başka sonuçlarla karıştı, değerlendirilmedi. Product Hunt'a bakılmadı. |
| Ticari landing'ler | `curl` ile `<title>`, meta, `og:image`, `h1`; WebFetch ile bölüm sırası | ham kanıt | WebFetch özeti küçük bir modelin yorumu; görsel yerleşim gözle doğrulanmadı. |
| iOS mağaza setleri | `itunes.apple.com/lookup?id=…&country=us`; her uygulamanın ilk 3 görseli | ham kanıt | Yalnız ABD mağazası ve iPhone görselleri. |
| AllisWell trafiği | `gh api …/traffic/{views,clones,popular/*}`, son 14 gün | ham kanıt | 14 günlük pencere; örneklem küçük. |

**Taiga** için tek bir ana depo yok: kod `kaleidos-ventures/taiga` (576★), `taigaio/taiga-back` (859★) ve `taigaio/taiga-docker` (2,174★) arasında dağılmış. Tabloda en çok yıldızı olan `taiga-docker` kullanıldı. **Cal.com** ise genel deposunu `calcom/cal.diy` olarak yeniden adlandırmış. Bu depo MIT lisanslı ve EE kodu çıkarılmış (ham kanıt). Aynı dönemde HN'de "Cal.com is going closed source" başlıklı bir konu var (391 puan, 2026-04-15, ham kanıt).

---

## 2. Tablo A: Açık kaynak / self-hosted emsaller

Yıldız sayıları 2026-11-07 tarihli. "12 ay Δ", Wayback'teki değer ile bugünkü değerin farkı. Lisans sütununda ● OSI onaylı, ◐ karma / open-core, ○ source-available ya da özel lisans demek.

| Proje | Yıldız | 12 ay Δ (≈/ay, %) | Lisans | Homepage | Özel social preview | 12 ayda sürüm (son) | awesome-selfhosted | YunoHost / Coolify | En güçlü HN izi |
| --- | --: | --- | --- | --- | :-: | --- | --- | --- | --- |
| Immich | 118,435 | +34,660 (≈2,888, +41%) | ● AGPL-3.0 | immich.app | ✓ | 33 (2026-11-04) | ana liste, Demo bağlantısıyla | ✓ / ✓ | 1,464 puan (2025-10-22) · 662 · 650 ("Immich 3.0", 2026-07-02) |
| AppFlowy | 78,362 | +11,902 (≈992, +18%) | ● AGPL-3.0 | appflowy.com | ✓ | 36 (2026-11-02) | ana | – / ✓ | 304 (2021-11-16) |
| Memos | 64,334 | +18,653 (≈1,554, +41%) | ● MIT | usememos.com | ✓ | 13 (2026-11-01) | ana, Demo bağlantısıyla | ✓ / ✓ | 129 (2023-07-11) |
| Plane | 62,108 | +22,349 (≈1,862, +56%) | ● AGPL-3.0 | plane.so | ✓ | 10 (2026-10-28) | ana, Demo bağlantısıyla | – / ✓ | 638 (2023-05-30) · 437 |
| Twenty | 60,587 | +23,984 (≈1,999, +66%) | ◐ AGPL ve `/ee` dosyalarında ticari lisans (LICENSE) | twenty.com | ✓ | ≥95 (2026-11-05) | ana (AGPL-3.0) | – / ✓ | 378 (2024-06-11) |
| Cal.diy (eski cal.com) | 49,760 | +11,045 (≈920, +29%) | ● MIT (EE kodu çıkarıldı) | cal.diy | – | 52 (son sürüm 2026-03-01) | ana ("Cal.diy") | ✓ / ✓ | 576 (2023) · 391 "going closed source" · 259 Cal.diy |
| Focalboard | 26,549 | +1,171 (≈98, +5%) | ◐ MIT derlenmiş + karma | focalboard.com | – | 0 (2024-06-13); README "not maintained" | yok | ✓ / – | 694 (2021-03-18) |
| Super Productivity | 23,475 | +7,594 (≈633, +48%) | ● MIT | super-productivity.com | ✓ | 71 (2026-11-06) | ana | – / – | 28 (2023-12-16) |
| Planka | 12,665 | +1,694 (≈141, +15%) | ○ PLANKA Community License 1.1 | planka.app | ✓ | 19 (2026-11-05) | **non-free.md** | ✓ / – | (arama sonuçları karışık) |
| Leantime | 12,012 | +3,436 (≈286, +40%) | ● AGPL-3.0 | leantime.io | ✓ | 27 (2026-10-31) | ana | ✓ / ✓ | 181 (2023-10-09) |
| Kanboard | 9,944 | +675 (≈56, +7%) | ● MIT | kanboard.org | – | 9 (2026-10-31); README "maintenance mode" | ana | ✓ / – | 513 (2023-05-23) |
| Vikunja | 5,983 | +3,345 (≈279, +127%) | ● AGPL-3.0 | vikunja.io | – | 13 (2026-11-05) | ana, Demo bağlantısıyla | ✓ / ✓ | 322 (2023-01-21) |
| Taiga (`taiga-docker`) | 2,174 | +332 (≈28, +18%) | ● MPL-2.0 | — | – | 0 GitHub sürümü | ana | – / – | 14 (2014) |
| Nextcloud Deck | 1,438 | +113 (≈9, +9%) | ● AGPL | apps.nextcloud.com | – | 46 | Nextcloud altında | – / – | — |
| Nextcloud Tasks | 709 | +70 (≈6, +11%) | ● AGPL | apps.nextcloud.com | – | 3 (2026-06-29) | Nextcloud altında | – / – | — |
| **AllisWell** | **26** | depo 2026-07-14'te açıldı; aylık yıldız: Tem 7 · Ağu 3 · Eyl 8 · Eki 5 · Kas 3 (≈5/ay, yatay) | ○ PolyForm NC 1.0.0 (GitHub'da NOASSERTION) | **boş** | **–** | 30 sürüm (v1.0.0: 2026-07-30; son 2026-10-30) | **yok** | – / – | **iz yok** |

Kaynaklar: ham kanıt (her satırın Wayback URL'si dosyada), ham kanıt (ör. satır 2126 Vikunja, 1624 Memos, 1738 Immich, 2057 Plane), ham kanıt (Planka), ham kanıt. AllisWell'in aylık yıldız sayısı `gh api repos/mahirozdin/alliswell/stargazers` (star+json) ile alındı.

### README ilk ekranı: kim ne gösteriyor

| Proje | Logo / kilit | Tek cümle | Rozetler | İlk görsel | Demo / dene | Tek satır kurulum | Özellik listesi | Karşılaştırma | Topluluk bağlantıları (ilk ekranda) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Immich | yığılmış logo | performans ve self-host vurgusu | lisans + Discord (büyük) | tam genişlikte ekran kolajı | Demo bölümü var | docs'ta | uzun liste | – | Discord; README'nin 21 dilde çevirisi var |
| Memos | açık/koyu tema `<picture>` kilidi | ürünü kategori olarak anlatan bir cümle | Docker pulls + sürüm | açık/koyu tema ekran görüntüsü | **Demo · Install · Docs · Discord** satırı | **`docker run` tek komut** ve "yedeğiniz tek klasör" notu | 4 madde | – | Discord |
| Plane | logo | "tüm ekipler için" iddiası | – | geniş ürün görüntüsü | Cloud = ücretsiz deneme | Docker/K8s tablosu | başlıklı liste | – | Website · Forum · X · Docs |
| AppFlowy | ad | "X'in açık kaynak alternatifi" | Discord, yıldız, fork, lisans | **8 ardışık ekran görüntüsü** (masaüstü ve mobil) | – | indirme bağlantıları | – | – | Forum · Discord · Reddit · X |
| Super Productivity | banner | tek cümle, değerleri sayıyor (özel, çevrimdışı, açık kaynak) | MIT + Discussions | **GIF reel** (yakala → planla → odaklan) | **Web uygulamasını aç** (hesap gerekmiyor) | mağaza ve Flathub rozetleri | – | – | Reddit · Mastodon · X |
| Planka | logo | kısa slogan | sürüm + "Docker pulls 8M+" | demo GIF | **Install · Demo · Docs · API** satırı | docs | **Community ve Pro tablosu** | – | – |
| Leantime | logo | hedef kitleyi ve erişilebilirliği söyleyen cümle | lisans, Docker, Discord, Crowdin, sponsorlar, trendshift | "my work" ekranı | – | `docker run` | **4 sütunlu özellik tablosu** | "X'e alternatif" satırları | Discord |
| Twenty | logo | "#1 açık kaynak X" iddiası | – | açık/koyu banner | Cloud | CLI | – | – | Website · Docs · … |
| Vikunja | logo | "sahip olduğun görev yöneticisi" sözü | CI, lisans, indir, Docker, OpenAPI | **görsel yok** | try.vikunja.io (Features bölümünde) | docs | site bağlantısı | – | – |
| Cal.diy | logo | topluluk sürümü olduğunu söylüyor | lisans, yıldız, commit, Docker | rezervasyon ekranı | – | – | "Cal.com'dan farkı" listesi | dolaylı | – |
| Kanboard, Nextcloud Tasks/Deck, Taiga, Focalboard | yok ya da düz başlık | düz açıklama | CI / kod kalitesi | tek ekran ya da yok | – | – | düz liste | – | – (Focalboard ve Kanboard README'si bakım uyarısıyla açılıyor) |
| **AllisWell** | tam genişlik **animasyonlu hero WebP (2.2 MB)**, sonra `<h1>` | "…you own" sözü ve uzun bir alt cümle | CI, yıldız, lisans, self-host, Claude/ChatGPT | animasyon + "film" posteri | "Open the web app" (hesap gerekip gerekmediği belirtilmiyor) | **4 komut**, `.env` düzenleme ve iki gizli anahtar | 2×2 animasyonlu tablo | **evet, dürüst** ("Where they beat us") | **yok** |

Kaynaklar: ham kanıt satır 1–60; AllisWell için `README.md:1-31`, `README.md:155-180`, `README.md:205-240`; dosya boyutları `docs/assets/readme/` (hero.webp 2,215,586 B; tasks.webp 2,462,038 B; notes.webp 2,322,602 B).

---

## 3. Tablo B: Ticari referanslar (landing ve iOS mağaza seti)

| Ürün | Hero deseni (`h1` ve yapı) | Kanıt (social proof) | Ürün görseli | iOS: puan (adet) · fiyat · görsel sayısı | iOS ilk 3 görselin mesajı (tarif) |
| --- | --- | --- | --- | --- | --- |
| Todoist | 2 kelimelik duygusal bir söz ve altında fayda cümlesi; birincil CTA ücretsiz başlangıç, ikincil CTA yükseltme | Meta açıklamasında kullanıcı sayısı; 5 yıldızlı yorum sayısı, basın logoları, dönen basın alıntıları; SOC 2 rozeti | Çerçevesiz, düz gerçek arayüz; video ayrı bölümde | 4.80 (130,557) · ücretsiz · 7 | 1) Sesle yakalama hızı ve iki ödül defnesi; 2) doğal dille yazılmış görev kartları; 3) projeyi takvim görünümünde izlemek. Her karede tek fiil + tek fayda. |
| TickTick | Ritmik 2 parçalı slogan; CTA "başla" ve "indir" | "Milyonlarca kişi", basın videosu ve logoları, kullanıcı yorum kartları | Özellik kartları, görünüm sekmeleri | 4.86 (46,830) · ücretsiz · 10 | 1) Kategori iddiası ve iki App Store ödülü; 2) takvim ve Google/Outlook logoları; 3) yapay zekâ ile sesle ekleme. |
| Things 3 | Başlık yerine marka adı ve tek cümle; CTA tanıtım videosu | "Ödüllü" ifadesi, Apple Design Award, basın alıntıları | Mac, iPhone, iPad ve Watch kolajı; platform kartları | 4.82 (28,075) · $9.99 · 8 | Mavi zemin, kalın + ince başlık: 1) ürünü tanıt; 2) bugüne odaklan (takvim ve görevler birlikte); 3) sürükle-bırak ile ileriyi planla. |
| Linear | Kitle ve kategoriyi söyleyen bir cümle; hero'da CTA yok, yalnız duyuru şeridi | Ekip sayısı, isimli iki referans, müşteri hikâyeleri | Düz, gerçek arayüz parçaları; "Fig" numaralı açıklamalar | 4.83 (2,329) · ücretsiz · 6 | Koyu zemin, ince başlık: 1) proje ilerlemesi; 2) dikkat isteyen gelen kutusu; 3) ajanla sohbet. Masaüstü ile aynı kimlik. |
| Sunsama | 3 vuruşlu ritim ve büyük bir sonuç cümlesi; CTA ücretsiz deneme, altında "kart gerekmez" güvencesi | Wirecutter ödülü, portre sırası, logo şeridi, isimli referanslar; sayfanın sonunda **Slack topluluğu** | Düz arayüz; problem ✗ / çözüm ✓ blokları | 4.51 (522) · ücretsiz · 4 | Mor zemin: 1) masaüstünün yoldaşı; 2) hızlı ekleme; 3) günün planını gözden geçirme. |
| **AllisWell** | Sahiplik sözü ("…you own", `apps/landing/src/content.js:60`); CTA "Open the web app" ve "Host it yourself" | **Yok**: sayı, puan ya da yorum gösterilmiyor (WebFetch, alliswell.space) | Örnek veriyle kaydedilmiş döngüler ve poster | **0 puan (0)** · ücretsiz · 7 | 1) Ana sayfa + takvim ("tüm gün tek yerde"); 2) projeler; 3) notlar. **Alarm, takvim senkronu, kendi sunucunda çalıştırma ve Claude/ChatGPT bağlantısı 7 görselin hiçbirinde yok**; 6. görsel "açık/koyu, kontrast kontrollü" mesajı taşıyor. |

Kaynaklar: ham kanıt, `ticktick_com.html`, `culturedcode_com_things.html`, `linear_app.html`, `sunsama_com.html`, `alliswell_space.html` (title/meta/h1 bu dosyalardan); bölüm sıraları WebFetch ile https://www.todoist.com, https://ticktick.com, https://culturedcode.com/things/, https://linear.app, https://www.sunsama.com ve https://alliswell.space adreslerinden; mağaza verisi ham kanıt, görseller ham kanıt ve AllisWell'in 4–7. görselleri ham kanıt. Linear sayfasında AI ajanlarına yönelik bir talimat metni vardı; veri olarak kaydedildi, uygulanmadı.

---

## 4. README ve landing'de ortak desenler: büyüyenler ne yapıyor

"Büyüyenler" son 12 ayda en çok yıldız alanlar: Immich, Twenty, Plane, Memos, AppFlowy, Cal, Super Productivity, Leantime ve oransal olarak Vikunja.

1. **İlk ekranda dört şey var: logo, tek cümle, tek bir dene yolu, tek bir ürün görseli.** Memos'ta Demo · Install · Docs · Discord satırı, Planka'da Install · Demo · Docs · API satırı bulunuyor. Super Productivity'de "web uygulamasını aç" bağlantısı hesap gerektirmiyor. Hızlı büyüyen dokuz projenin altısı ya ilk ekranda ya da awesome-selfhosted kaydında bir **demo ya da hesapsız deneme** sunuyor: Immich, Memos, Plane, Vikunja, Super Productivity, Planka (kaynak: ham kanıt Demo bağlantıları; README'ler).
2. **Kategori dilini kullanıyorlar.** Ya bir kategori iddiası (#1 X, X için modern ...) ya da "X'e alternatif" kalıbı (AppFlowy, Leantime, Focalboard, Plane'in awesome-selfhosted kaydı). Arama ve liste görünürlüğü bu kalıptan geliyor. AllisWell'in GitHub konularında `todoist-alternative` zaten var.
3. **Kurulum tek blok ve kopyalanabilir.** Memos tek bir `docker run` satırı ve "yedek tek klasör" notu kullanıyor; Leantime, Focalboard ve Deck'te de `docker run` var. Plane bir Docker/K8s tablosu veriyor. Bunlara ek olarak **katalog dağıtımı** var: Vikunja, Memos, Immich, Leantime ve Cal YunoHost'ta da Coolify'da da bulunuyor (ham kanıt). README'de tek tıkla kurulum düğmesi nadir, örneklemde yalnız Cal.diy'de var. Dağıtım düğmeyle değil, kataloglar üzerinden yapılıyor.
4. **Her büyüyen projenin bir "an"ı var.** HN'de 300 puanı geçen bir lansman ya da haber: Plane 638, AppFlowy 304, Vikunja 322, Cal 576, Twenty 378, Immich 1,464. Memos 129 puanda kalmış ama awesome-selfhosted ve Docker pulls ile büyümüş. Lansman bir kez yapılıyor ve sonra README'de kanıt olarak kullanılıyor (Plane'in "100K+ Docker" başlığı, Planka'nın "8M+ pulls" rozeti).
5. **Görünür bir topluluk kanalı var.** Discord, Forum, Reddit, Mastodon ya da Discussions. Örneklemdeki 9 büyüyenden 8'inde Discussions açık (ham kanıt `discussions`). Ticari tarafta Sunsama da sayfanın sonunda Slack topluluğunu gösteriyor.
6. **Kendi sosyal paylaşım kartları var.** 9 büyüyenden 8'inde özel social preview tanımlı (`usesCustomOpenGraphImage`); yalnız Cal.diy ve Vikunja'da yok. HN, Reddit ya da X'te paylaşılan bağlantının görünüşü bu karta bağlı.
7. **Kısa README, dışarı taşınmış geliştirici belgeleri.** Memos 83, Immich 126, Plane 165, Twenty 176 satır. Geliştirici kurulumu docs'ta ya da CONTRIBUTING'de duruyor. Uzun README'ler ya bakım modundaki projelerde (Taiga 530) ya da hukuki ayrım taşıyanlarda (Cal.diy 837) görülüyor.
8. **Ücretli katman açıkça ve erken gösteriliyor, kimseyi kızdırmadan.** Planka README'si ikinci blokta Community ve Pro tablosu veriyor; Planka kaynağı açık, OSI dışı bir lisansla dağıtılıyor ve awesome-selfhosted'ın non-free listesinde (ham kanıt). Vikunja ve Plane Cloud/Pro'yu ilk paragrafta adıyla söylüyor. Ters örnek: Cal.com'un kapalı kaynağa geçişi HN'de 391 puanlık bir tartışma açtı (ham kanıt). Lisans etiketinin her yüzeyde tutarlı olması güven konusu.
9. **Ticari landing'lerde kanıt hep hero'nun yanında.** Todoist yorum sayısı ve basın logoları, Sunsama ödül ve "kart gerekmez" güvencesi, Linear isimli referanslar kullanıyor. **Mağaza setlerinde** her karede tek fiil + tek fayda var; ilk karede ödül defnesi ya da marka tanıtımı bulunuyor. İlk 3 karede ürünün "neden bu uygulama" cevabı veriliyor; sıradan liste ekranı ilk 3 karede yer almıyor.

---

## 5. AllisWell'in eksikleri (bulgular)

Biçim: **CT-NN · şiddet · efor** · kanıt → önerilen düzeltme. "Sahip işi" etiketi, ayarın GitHub, mağaza ya da dış bir hesapta yapılması gerektiğini söylüyor; ajan bunları yapmaz (AGENTS.md "Never": dış hesaba yazma).

**CT-01 · major · S · sahip işi.** GitHub "About" metni **"Open-source"** diye başlıyor (`gh api repos/mahirozdin/alliswell` → `description`). Oysa lisans PolyForm Noncommercial ve README bu etiketin doğru olmadığını açıkça yazıyor (`README.md:580` "Being straight about the label"; ADR-0024; landing SSS `apps/landing/src/content.js:211-212`). Self-hosted topluluğu bu ayrıma hassas (Cal.com/Cal.diy olayı, HN 391 puan). Listeye ilk girişte de non-free olarak değerlendirilecek.
→ About metnini "Source-available, self-hosted productivity hub…" diye düzelt. İsteğe bağlı olarak `source-available` konusu eklenebilir. Lisans değişikliği önerilmiyor: ADR-0024 bağlayıcı.

**CT-02 · major · S · sahip işi.** **Homepage alanı boş** (`repos.json` → `homepage: null`, brief C-08) ve **özel social preview yok** (`custom_og: false`). Landing'in kendi OG kartı ise hazır: `https://alliswell.space/shots/og/home-dusk.jpg` (ham kanıt). Büyüyenlerin 8/9'unda özel kart var (§4.6).
→ Homepage alanına `https://alliswell.space` yazılmalı. Settings › Social preview'a OG kartından türetilen 1280×640 bir görsel yüklenmeli (koyu Dusk ve logo; G-ilkeleri korunarak).

**CT-03 · major · M–L · ürün kararı.** **Kurmadan deneme yolu yok.** Bunu projenin kendi belgesi de yazıyor: `docs/COMPARISON.md:446` (Public demo ○) ve `docs/COMPARISON.md:459-460` ("We have neither"). Landing'deki "Open the web app" bağlantısı hesap gerekip gerekmediğini söylemiyor (WebFetch alliswell.space). Büyüyenlerin 6/9'unda demo ya da hesapsız deneme var (§4.1). Altyapı hazır: `scripts/seed-demo.mjs` (`README.md:406`).
→ Üç yol var: (a) her gece sıfırlanan, demo tohumlu, paylaşılan, salt okunur ya da yazılabilir bir **demo çalışma alanı**; (b) uygulamayı açınca "örnek veriyle dene" seçeneğiyle cihazda yerel, misafir bir çalışma alanı; (c) en ucuzu, CTA'nın yanına "ücretsiz hesap, kart yok, X saniye" güvencesini yazmak. Barındırma maliyeti ve kötüye kullanım nedeniyle seçim sahibin.

**CT-04 · major · M · sahip işi (dış iletişim).** **Hiçbir dağıtım kanalında yer yok:** awesome-selfhosted'da yok, YunoHost ya da Coolify kataloğunda yok, HN'de iz yok, Reddit doğrulanamadı (§2). Son 14 günde 124 tekil ziyaretçi gelmiş; yönlendirenler github.com (10), Google (8), DuckDuckGo (3) (ham kanıt). Yıldızlar ayda ≈5'te yatay seyrediyor. Yani sorun README dönüşümünden önce **trafiğin hiç gelmemesi**.
→ Sahibin kendisinin yürüteceği tek seferlik bir lansman paketi:
1. **awesome-selfhosted `non-free.md`**: kural "ilk sürüm 4 aydan eski" olmasını istiyor (ham kanıt). v1.0.0 2026-07-30'da çıktı, yani **en erken 2026-11-30**. Aynı dosya başvurunun AI tarafından hazırlanmamasını da istiyor; metni sahip yazmalı.
2. Show HN ve r/selfhosted gönderisi, demo hazır olduktan sonra (CT-03).
3. Coolify şablonu için PR. YunoHost paketi ancak lisans politikası uygun çıkarsa: YunoHost'un non-free uygulama politikası **bilinmiyor**, önce doğrulanmalı.
4. selfh.st haftalık bültenine bildirim.

**CT-05 · major · S · zevk (2–3 yön).** **Konumlandırma çakışıyor.** Landing H1 "Tasks, notes and alarms you own." (`apps/landing/src/content.js:60`, `README.md:10`), Vikunja H1 ise "The task manager you actually own." (ham kanıt). "Sahip olduğun" sözü self-hosted kategorisinin varsayılanı, ayırt edici değil. AllisWell'i ayıran şeyler alt cümlede kalıyor: sessiz modu delen alarm, iki yönlü Google Takvim, Claude/ChatGPT MCP.
→ Hero için yönler (metin önerisi değil, odak önerisi): **(a) alarm** önde ("kaçırılmayan hatırlatma"), sahiplik alt satırda; **(b) takvim** önde (görevler takvimde, iki yönlü); **(c) AI/MCP** önde (asistanın yönettiği görev listesi). Sahip birini seçer. GitHub About ve mağaza alt başlığı aynı odağı izler.

**CT-06 · major · M · sahip işi (mağaza formu).** **iOS mağaza setinin ilk 3 karesi kategoriyle aynı mesajı veriyor:** Ana sayfa, projeler, notlar. 7 karenin hiçbirinde tam ekran alarm, takvim senkronu, self-host ya da MCP yok. 6. kare "açık/koyu, kontrast kontrollü" diyerek iç kaliteyi anlatıyor, kullanıcıya faydayı değil (ham kanıt). ABD mağazasında **0 puan** var (`itunes_lookup.json`). Görsellerde sahibin şikâyet ettiği yüzen nesneler de görünüyor: sol ya da sağ kenarda yarısı ekran dışında kalan şimşek balonu ve mikrofon FAB (brief C-02). Mağaza açıklamasındaki "no paid tier" ifadesi README'deki ticari lisans ve Enterprise bölümüyle (`README.md:512`, `README.md:545`) yan yana okununca belirsiz kalıyor.
→ Önerilen kare sırası: 1) tam ekran alarm (sessiz modda çalıyor); 2) takvimdeki görev, iki yönlü; 3) "kendi sunucunda ya da bizde"; ardından Ana sayfa ve notlar. Her karede tek fiil + tek fayda olsun (§4.9). Görseller UI düzeltmeleri bittikten sonra demo tohumundan yeniden üretilmeli (STATE "Görseller üretilir, çekilmez"). "No paid tier" ifadesi "kişisel kullanım ücretsiz" diye netleştirilmeli.

**CT-07 · minor · M.** **Self-host ilk adımı ağır.** 4 komut, `.env` düzenleme ve iki gizli anahtar gerekiyor (`README.md:164-173`). Memos aynı işi tek `docker run` satırıyla yapıyor (ham kanıt). MySQL + Redis değişmez kural (I-02), yani tek konteyner **önerilmiyor**.
→ Gizli anahtarları ilk açılışta kendisi üreten ve yalnız alan adını soran bir compose, ya da `docker compose up` tek bloğu ile "localhost'ta dene" profili (TLS yok, varsayılan şifreler, açık uyarıyla). Katalog şablonları (CT-04) da aynı işi görür.

**CT-08 · minor · S · sahip işi.** **Topluluk kanalı yok.** Discussions kapalı (`has_discussions: false`), Discord ya da Matrix yok, issue şablonu yok (`community/profile` → `issue_template=false`). Büyüyenlerin 8/9'unda Discussions açık (§4.5).
→ Discussions'ı aç (Q&A ve Show-and-tell kategorileri). Bağlantıyı README'nin üst gezinmesine ve landing alt bilgisine ekle. Hata ve özellik isteği için iki şablon yeterli.

**CT-09 · minor · S.** **README kaynağı uzun ve ilk ekranı ağır.** Kaynak 626 satır. Geliştirici ve ajan bölümleri (Architecture, Quickstart, Documentation, "Built to be developed by AI agents") katlanmış `<details>` içinde duruyor (`README.md:379-510`), bu yüzden ziyaretçinin gördüğü sayfa daha kısa; yine de bu bölümler ziyaretçi README'sinde yer alıyor. İlk iki ekranda yaklaşık 7 MB animasyonlu WebP var. Büyüyenler 83–176 satırda kalıyor (§4.7).
→ Geliştirici ve ajan bölümleri `CONTRIBUTING.md` ile `docs/development/`'a taşınmalı. İlk ekranda tek bir animasyon kalmalı ya da animasyonlar küçültülmeli. Karşılaştırma bölümü korunmalı: dürüst "Where they beat us" anlatımı rakiplerde yok, AllisWell'in güçlü yanı.

**CT-10 · minor · S · zevk.** **Kanıt yok ya da ters kanıt veriyor.** Landing'de hiçbir sosyal kanıt yok (WebFetch). README'de 26 yıldızlık bir yıldız-geçmişi grafiği var (`README.md:602-609`); bu grafiği Memos 64k yıldızla kullanıyor.
→ Grafik anlamlı bir eşiğe kadar kaldırılmalı. Yerine bu ölçekte dürüst kanıtlar konabilir: sürüm temposu (2026-07-30'dan beri 30 sürüm), test sayıları (README'de zaten var), herkese açık değişiklik günlüğü. İlk mağaza puanları gelince ekle.

**CT-11 · minor · S.** **Ücretli katman geç ve iki dilde anlatılıyor.** Enterprise bölümü README'nin sonunda (`README.md:512`), lisans tablosu hemen altında; ilk ekranda yalnız lisans rozeti var. Planka "Community ve Pro" tablosunu ikinci blokta veriyor (§4.8).
→ İlk ekrana tek satır eklenebilir: "Kişisel kullanım ve self-host ücretsiz · işletmeler için lisans ve Enterprise →". Yetenek düzeyinin ötesinde uzantı ayrıntısı public belgeye girmemeli (I-14). Bu yalnız konumlandırma önerisi.

**CT-12 · minor · S.** GitHub trafiğinde `apps/app/packages/markdown_forge` yolu 6 tekil ziyaret almış (`alliswell_traffic_14d.json`), ama bu klasör artık depoda yok. Paket pub.dev'de `BubiApps-LTD/markdown_forge` olarak yayında (0.1.0) ve kendi README'sinde AllisWell'i bir kez anıyor.
→ Eski yoldan gelenler için README'ye "markdown_forge'u ayrı paket olarak kullan" bağlantısı eklenebilir. Ayrı bir kütüphane, ürüne ikinci bir keşif kapısı açar.

**SAHİBE SORU yok.** Önerilerin hiçbiri bağlayıcı kararlarla çelişmiyor: lisans (ADR-0024), MySQL/Redis (I-02), uzantı gizliliği (I-14), görsellerin tohumdan üretilmesi. Lisansı OSI'ye çevirmek bilinçli olarak önerilmedi.

---

## 6. Hakemler için girdi

- **Ölçülebilir hedefler.** Şu anki referans: ≈5 yıldız/ay, 124 tekil ziyaretçi/14 gün, mağazada 0 puan. Vikunja'nın tek kişilik ölçekte bile ≈279 yıldız/ay toplaması, ilk kaldıracın UI'dan önce dağıtım (CT-04) ve deneme yolu (CT-03) olduğunu düşündürüyor. Bu bir çıkarım, ölçülmüş bir neden-sonuç değil.
- **Kimlik korunuyor (O-03 KESİN).** Önerilerin hepsi metin, sıralama ve kanal düzeyinde. AllisWell Glass'a ve Dusk landing'e görsel değişiklik getiren tek öneri social preview kartı (CT-02); o da mevcut OG kartından türetiliyor.
- **Persona incelemesi için sorular** (O-06, O-07): (1) Bir self-hoster README'nin ilk ekranında 10 saniyede "neden Vikunja değil de bu?" sorusunun cevabını bulabiliyor mu? (2) "Open the web app"e tıklayan biri hesap açmadan bir şey görebiliyor mu? (3) Mağazanın ilk 3 karesinden alarmın varlığı anlaşılıyor mu? (4) Lisansın "kişisel kullanım ücretsiz" olduğu ilk ekranda anlaşılıyor mu?
- **UI turuyla bağlantı.** Mağaza görselleri brief'teki C-02 kalabalığını (yüzen şimşek, mikrofon FAB) belgeliyor. Uygulama çubuğunda arama ikonunun görünmesi brief C-03'ü ve ADR-0055'i destekliyor. Mağaza seti UI düzeltmesinden **sonra** yeniden üretilmeli; sıra: UI → görseller → lansman.
- **Bilinmeyenler.** Reddit'teki izler; Product Hunt; Unraid, TrueNAS ve PikaPods katalogları; YunoHost'un non-free politikası; landing'deki web uygulamasının kayıt akışının adım sayısı (bu belge için ölçülmedi).
