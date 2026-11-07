> **Depodaki kopya (2026-11-07, E35 kaydı):** uzantıya özgü tasarım ayrıntısı çıkarıldı (uzantı bulguları uzantı deposunda); turun iç çalışma dosyalarına ve ham kanıta verilen yollar düz metne çevrildi ("ham kanıt" = turun çalışma alanında kalan dosya; depoda yok). Bulgu kimlikleri değişmedi. Özet: [README.md](README.md).

# GitHub büyüme denetimi: `mahirozdin/alliswell` neden büyümüyor?

> Son güncelleme: 2026-11-07 — CEO tasarım/UX turu
> Kaynak: `gh api` GET çağrıları (repo, stargazers, forks, traffic, releases, issues, contributors, community/profile), anonim GHCR registry okuması, yerel depo (`README.md`, `LICENSE`, `CONTRIBUTING.md`, `docker-compose.selfhost.yml`, `.env.selfhost.example`, `docs/STATE.md`, `docs/adr/0024-*`, `docs/COMPARISON.md`), başsız Chromium ekran görüntüleri, awesome-selfhosted / Show HN kuralları, HN Algolia araması. Sahip brief'i: sahip brief'i (O-07, O-11, C-08).
> Kapsam: yalnız okuma. Hiçbir issue, yorum, yıldız, ayar ya da dış hesap değiştirilmedi. Ham dosyalar tur çalışma alanında kaldı (depoda yok).

## 0. Hüküm (kısa)

AllisWell bir **ürün** sorunu yaşamıyor, bir **dağıtım ve ilk izlenim** sorunu yaşıyor. Depo 4 ayda 707 commit
ve 40 sürüm çıkardı, fakat (1) hiçbir kanalda lansman yapılmadı, (2) yabancı bir ziyaretçinin hesap açmadan
ya da iki alan adı + ters vekil kurmadan ürünü deneyebileceği bir yol yok, (3) GitHub'ın ilk ekranı ürün değil
ajan altyapısını (`.claude`, `AGENTS.md`, `CLAUDE.md`) ve "Open-source" yazan, lisansla çelişen bir açıklamayı
gösteriyor. Trafik zaten çok az (14 günde 124 tekil ziyaretçi) ve yıldız hızı **düşüyor**
(aylık 8 → 9 → 5 → 4). README/landing yenilemesi (2026-10-30) hızı değiştirmedi: sorun cilada değil, huninin
ağzında.

## 1. Ölçümler

### 1.1 Depo (2026-11-07)

| Ölçü | Değer | Kanıt |
| --- | --- | --- |
| Yıldız / fork / izleyen | 26 / 4 / **0** (sahip dahil kimse "watch" etmiyor) | ham kanıt, `subscribers.json` |
| Oluşturma → ilk sürüm | 2026-07-14 → v0.4.0 2026-07-26 | `repo.json`, `releases.json` |
| Yıldız zaman serisi (30 günlük dilimler) | 07-22..08-21: 8 · 08-22..09-21: 9 · 09-22..10-21: 5 · 10-22..11-07: 4 | `stargazers.json` (starred_at) |
| En yoğun gün | 2026-07-31: 3 yıldız; başka hiçbir gün 1'i geçmedi → **hiç sıçrama (lansman) yok** | `stargazers.json` |
| Trafik, 14 gün (10-24..11-06) | 264 görüntüleme / **124 tekil**; günlük tekil 4–18 | `traffic-views.json` |
| Ziyaretçi → yıldız | aynı 14 günde 3 yıldız (10-26, 11-03, 11-04) → ≈ %2,4 | `traffic-views.json`, `stargazers.json` |
| Klon, 14 gün | 209 / 78 tekil; 10-28 (67/24) ve 10-30 (51/11) sıçramaları v1.18.1/v1.18.2 sürüm günleriyle çakışıyor → büyük olasılıkla otomasyon/CI (**doğrulanmadı**) | `traffic-clones.json`, `releases.json` |
| Yönlendirenler, 14 gün | github.com 10 tekil · aocr.org 11 · Google 8 · DuckDuckGo 3 · pinterest 2 · perplexity 1. **HN, Reddit, awesome-selfhosted, Product Hunt yok.** aocr.org'un ne olduğu bilinmiyor | `traffic-popular-referrers.json` |
| Popüler yollar | Overview 79 tekil; ardından `markdown_forge` paketi 6, `/releases` 3, ekran görüntüleri 4–5 | `traffic-popular-paths.json` |
| Sürümler | 40 sürüm / 96 gün (≈ 2,4 günde bir); notlar toplam 183.646 karakter, en uzunu 21.222 (v1.14.0); tüm sürüm eklerinin toplam indirmesi **43** | `releases.json` |
| Issue/PR | #1–#37; dış yazar yalnız **1 kişi** (`Gandalf-the-Blue`, #1–#3, Temmuz–Ağustos); geri kalan 34 öğe sahibin; açık issue 1 (#32, etiketsiz) | `issues.json` |
| Katkıcılar | `mahirozdin` 703 · **`claude` 4** (kenar çubuğunda "Contributors 2: mahirozdin, claude") | `contributors.json`, `gh-repo-desktop-long.png` |
| Commit | 707 (main); 350'sinin başlığında `OPH-NNN`; Temmuz 206, Ağustos 205, Eylül 220, Ekim 76 | `git log origin/main` |
| Lisans (GitHub algısı) | `Other` / `NOASSERTION` — kenar çubuğunda yalnız "License" yazıyor, ad yok | `repo.json`, `community.json` |
| Açıklama | "**Open-source**, self-hosted productivity hub…" — LICENSE PolyForm Noncommercial, ADR-0024 "source-available" der | `repo.json`; `LICENSE:1`; `docs/adr/0024-license-polyform-noncommercial.md:72-76` |
| Homepage alanı | **boş** (README'de 30+ `alliswell.space` bağlantısı varken) | `repo.json`; `README.md:4,15` |
| Social preview | özel görsel **yok**; GitHub'ın varsayılan kartı: profil avatarı + "Open-source…" + "2 Contributors · 26 Stars" | `repo.json` (`usesCustomOpenGraphImage=false`), ham kanıt |
| Topics | 16 adet (calendar-sync, flutter, todoist-alternative…); **mcp, kanban, caldav, markdown, alarm yok** | `repo.json` |
| Discussions / Wiki | Discussions **kapalı**, Wiki açık (boş olduğu varsayımı doğrulanmadı) | `repo.json` |
| Topluluk sağlığı | %100 (README, CoC, CONTRIBUTING, SECURITY, PR şablonu, issue formları var) | `community.json`; `.github/ISSUE_TEMPLATE/*.yml` |
| `good first issue` / `help wanted` | etiket var, kullanılan **0** | GitHub search API |
| Hazır imaj | `ghcr.io/mahirozdin/alliswell-api` ve `-web` **herkese açık**, 0.4.0 → 1.18.2 her sürüm etiketli | anonim `ghcr.io/v2/.../tags/list` |
| Dış kanallarda varlık | HN'de "alliswell" hikâyesi **0** (Algolia); awesome-selfhosted README'de **yok**; AlternativeTo ve Product Hunt sayfaları 403 döndü → **bilinmiyor** | HN Algolia API; awesome-selfhosted `README.md`; curl |
| İsimle aranabilirlik | GitHub'da "alliswell" araması 127 depo; `topic:todoist-alternative` yalnız 10 depo (AllisWell 2.) | GitHub search API |

### 1.2 Rakip depolar (ilham için; kopya yok)

| | AllisWell | Vikunja | Super Productivity | Planka |
| --- | --- | --- | --- | --- |
| Yıldız | 26 | 5.983 | 23.475 | 12.665 |
| Yaş | 4 ay | ~8 yıl (2018-11) | ~10 yıl (2017-01) | ~7 yıl (2019-08) |
| Lisans (GitHub) | Other (PolyForm NC) | AGPL-3.0 | MIT | NOASSERTION (README: ücretsiz Community + ücretli Pro) |
| Homepage alanı | boş | vikunja.io | super-productivity.com?ref=github | planka.app |
| Katkıcı (yaklaşık) | 2 (biri `claude`) | ~205 | ~560 | ~162 |
| Discussions | kapalı | kapalı | açık | açık |
| Açık `good first issue` | 0 | 0 | 5 | 1 |
| Kök girdisi | 28 | 49 | 58 | 26 |
| Hesapsız deneme | yok | try.vikunja.io | web app, hesap yok | bilinmiyor |
| Son sürümler | 10-28, 10-30 | 5 sürüm/3 ay | 5 sürüm/7 hafta | 4 sürüm/1 hafta |

Kaynak: ham kanıt, `gh api repos/<r>/releases|contributors|contents`; hesapsız deneme sütunu
`docs/COMPARISON.md:446`. Katkıcı sayısı `contributors?per_page=1&anon=1` son sayfa numarasıdır (yaklaşık).

**Okuma:** Kök dosya sayısı rakiplerden fazla değil (28 vs 26–58) — sorun **sayı değil içerik** (ajan dosyaları
en üstte). Yaş farkı büyük; adil kıyas "4 ayda ne kadar" olurdu ve rakiplerin o dönemine ait veri yok
(bilinmiyor). Planka da kaynak-açık/ticari karma bir lisansa geçti ama bunu kitle oluştuktan sonra yaptı;
AllisWell kitleden önce kapalı-ticari lisansla başlıyor.

## 2. Neden büyümüyor — sıralı 10 neden

| # | Neden | Şiddet | Kanıt |
| --- | --- | --- | --- |
| N1 | **Hiç lansman yapılmadı; trafik musluğu yok.** Yıldızlar organik damla (hiçbir gün >3), yönlendirenlerde HN/Reddit/listeler yok, HN'de tek gönderi yok. Huniye giren insan sayısı küçük olduğu için her başka düzeltmenin etkisi de küçük. | blocker | §1.1 yıldız serisi, referrers, HN Algolia |
| N2 | **Hesapsız deneme yok.** Kendi karşılaştırma belgemiz rakiplerde public demo olduğunu, bizde olmadığını yazıyor. Show HN kuralı açıkça "kayıt/e-posta gibi engeller olmadan denenebilir" ister. Barındırılan uygulama kayıt ister. | blocker | `docs/COMPARISON.md:313,446,459`; https://news.ycombinator.com/showhn.html |
| N3 | **Kendin barındır yolu "dene" için fazla ağır.** 4 konteyner (MySQL, Redis, API, web); `.env` elle doldurulmadan başlamaz (`:?` zorunlu değişkenler); API ve web için **iki ayrı köken + CORS** ve TLS için ters vekil varsayılır; ekler için dış S3/R2 gerekir (self-host compose'da MinIO yok). `localhost`'ta tek komutla açılan bir yol yok. | major | `docker-compose.selfhost.yml:21,24,57,61-64,100`; `.env.selfhost.example` (ALLISWELL_API_URL, CORS_ORIGIN, STORAGE_S3_*); `README.md:161-172` |
| N4 | **Lisans–etiket çelişkisi ve hedef kitle uyumsuzluğu.** Açıklama "Open-source" diyor; LICENSE PolyForm Noncommercial; GitHub lisansı tanımıyor ("Other"). r/selfhosted ve awesome-selfhosted kitlesi FOSS bekler: awesome-selfhosted ana listesi yalnız özgür yazılım alır, bizim için yalnız **Non-Free** sayfası mümkün. Ayrıca "şirketinde ekibin için çalıştırmak ❌" satırı, işyerinde homelab kuran (en güçlü yayıcı) kitleyi dışarıda bırakıyor. | major · lisans kısmı **SAHİBE SORU** | `repo.json`; `LICENSE:1-16`; `README.md:555-562`; ADR-0024 §Consequences; awesome-selfhosted `README.md:7`, `non-free.md` |
| N5 | **GitHub ilk ekranı ürünü göstermiyor.** 1440×900'de ilk ekran yalnız dosya listesi; ilk satırlar `.claude`, `.github`… ve kökte `AGENTS.md`, `CLAUDE.md`; README ≈1.470 px aşağıda başlıyor. Homepage boş, social preview varsayılan (avatar + "Open-source" + "2 Contributors"). Mobilde ilk ekran "About" + "0 watching". | major | ham kanıt, `gh-repo-mobile.png`, `og-default.png` |
| N6 | **README ağır ve dağınık.** 626 satır / 43 KB; yaklaşık 7,8 MB animasyonlu WebP (hero 2,2 MB, tasks 2,5 MB, notes 2,3 MB); hero geniş bir masaüstü kaydı (telefonda okunmaz); karşılaştırma tablosu self-host kitlesinin rakipleriyle değil Google/Apple/Things ile; geliştirici Quickstart, 15 satırlık komut tablosu, iç belge tablosu ve "Built to be developed by AI agents" bölümü son kullanıcı README'sinde; 26 yıldızlık "Star history" grafiği negatif sosyal kanıt. | major | `README.md:1-60,205-222,410-500,499,602-609`; `docs/assets/readme/*.webp` (boyutlar §1.1 komutu) |
| N7 | **"Ajanla yazılmış" algı riski açıkta.** Katkıcılarda `claude`; CONTRIBUTING ilk paragrafı "humans **and AI agents**"; README'de ajan bölümü; commit'lerin yarısı `OPH-NNN` (yabancıya hiçbir şey anlatmıyor). 2026'da r/selfhosted yeni projeleri haftalık megathread'e topluyor ve "AI Involvement" beyanı istiyor; şeffaflık iyi, ama bunun ürün yerine vitrinin önünde durması güveni düşürür. | major (algı) | `contributors.json`; `CONTRIBUTING.md:3-4`; `README.md:499-509`; `git log` (350/707); r/selfhosted kural güncellemesi (redlib aynası, **doğrulanmalı**: https://redlib.groet-infra.nl/r/selfhosted/comments/1rmt39o/rules_update_new_project_friday_here_to_stay/) |
| N8 | **Topluluk yüzeyi yok; katkı yolu iç sürece bağlı.** Discussions kapalı; `good first issue` 0; dış yazar 1 kişi; sahibin issue'ları çoğu kendi açıp kendi kapattığı iş kayıtları. PR kontrol listesi dışarıdan gelene `TASKS/STATE/CHANGELOG` güncellemesi, `verify:batch` + `verify:smoke` ve 4 Docker servisi şart koşuyor. | major | `repo.json`; `issues.json`; `CONTRIBUTING.md:51-62` |
| N9 | **Türkçe iç belgeler yabancıya açık kapıdan görünüyor.** README "pick a task from docs/TASKS.md" diyor; TASKS'ın 186 satırının ~124'ü Türkçe, ilk bölüm "Sahibin adımını bekleyen işler…". STATE 126/168, LESSONS 247/278, BLUEPRINT ~1.036/1.827 satır Türkçe (sezgisel sayım). | minor | `README.md:589-592`; `docs/TASKS.md:22-30`; grep sayımı |
| N10 | **Konumlandırma bulanık, isim zor aranır, sürüm gürültülü.** "Productivity hub" görev+not+belge+takvim+alarm+AI+MCP+kurumsal; tek bir kanca yok (en ayırt edici ikisi — sessizde çalan alarm ve MCP — topics'te bile yok). "AllisWell" yaygın bir ifade (GitHub'da 127 depo). 40 sürüm / 96 gün ve 21 bin karakterlik notlar izleyenler için gürültü; masaüstü indirmeleri toplam 43. | minor · isim **SAHİBE SORU** | `repo.json` (description, topics); GitHub search; `releases.json` |

## 3. Sıralı 15 düzeltme

Etki: H yüksek / O orta / D düşük (tahmin; ölçüm yolu §5'te). "Sahip eylemi" = ajanın yapamayacağı ayar/dış hesap işi.

| # | Düzeltme | Çözdüğü | Efor | Beklenen etki | Not |
| --- | --- | --- | --- | --- | --- |
| D1 | **About'u düzelt:** açıklamada "Open-source" → "Source-available" (ADR-0024 zaten bunu zorunlu kılıyor) ve tek kanca cümlesi; homepage = `https://alliswell.space/?ref=github`; topics'e `mcp`, `mcp-server`, `kanban`, `caldav`, `markdown`, `alarm` ekle (20 sınırı içinde, `fastify`/`mysql` gibi zayıfları çıkar). | N4, N5, N10 | S | O | Sahip eylemi (repo ayarı). Karar değil: ADR-0024 uygulaması |
| D2 | **Özel social preview** (1280×640, demo tohumundan; telefon + masaüstü, tek cümle, "source-available · self-hosted"). | N5 | S | O | Sahip eylemi (ayardan yükleme). Gerçek veri yok |
| D3 | **Hesapsız deneme:** `scripts/seed-demo.mjs` ile her gece sıfırlanan, yazmaya açık ama kota/rate-limit'li bir demo örneği (ör. `demo.alliswell.space`), ya da tarayıcıda yerel modlu salt-deneme. | N2 | L | **H** (lansmanın ön şartı) | **SAHİBE SORU:** barındırma maliyeti, kötüye kullanım, alan adı; canlıya dağıtım sahibindir |
| D4 | **"60 saniyede dene" self-host profili:** tek köken (web konteyneri `/api`'yi vekiller → CORS ve ikinci alan adı gerekmez), sırları ilk açılışta üreten, `localhost:8080`'de `docker compose up` ile edit'siz açılan bir compose; ekler için isteğe bağlı yerel disk/MinIO. Üretim profili ayrı kalır. | N3 | M–L | **H** (r/selfhosted'in ilk sorusu) | Mimari değişiklik → ADR gerekir (I-06). Güvenlik varsayılanları SECURITY.md'ye göre |
| D5 | **README'yi iki katmana böl:** ilk ekran ≤ ~120 satır (§4 iskeleti); geliştirici Quickstart, komut tablosu, belge tablosu, ajan bölümü ve Star history → `docs/development/` ya da `CONTRIBUTING.md`. Hero'yu telefon+masaüstü bileşik, ≤ 600 KB bir görsele indir; animasyonlar katlanır bölümlerde kalsın. | N6 | M | O–H | `check:docs` bütçesine dikkat; görseller demo tohumundan (STATE "Görseller üretilir") |
| D6 | **Karşılaştırmayı self-host kitlesine çevir:** README'de ilk tablo Vikunja / Super Productivity / Planka / Tasks.org ile dürüst kıyas; Google/Apple/Things tablosu landing'e. Ayırt ediciler öne: sessizde çalan alarm, MCP, iki yönlü Google Takvim. | N6, N10 | S | O | Veri zaten `docs/COMPARISON.md §7`'de |
| D7 | **Lisans netliği (karar gerektirmeyen kısım):** README'ye 3 soruluk SSS — "evdeki homelab'ımda?", "işyerimde kendim için?", "derneğimde?" — ve GitHub'ın "Other" göstermesinin nedeni. | N4 | S | O | — |
| D8 | **Lisans tercihi** (FSL/ELv2 gibi "iç kullanım serbest" seçenekler ADR-0024'te gerekçesiyle reddedildi). Büyüme hedefi FOSS kitlesiyse bu, en büyük tek kaldıraç; ama karar sahibindir. | N4 | L | H (belirsiz) | **SAHİBE SORU** — ADR-0024 kabul edilmiş karar; ajan yeniden tartışmaz, yalnız soruyu iletir |
| D9 | **Vitrinin önünü ürüne ver:** CONTRIBUTING'in ilk paragrafını insan katkıcıya yaz; ajan şeffaflığını tek satır "How this repo is built" notuna ve `docs/development/`'a taşı; commit başlıklarında `OPH` id'sini sona al (zaten öyle) ve PR başlıklarını kullanıcı diliyle yaz. `claude` katkıcı satırı geçmişten gelir, geçmiş yeniden yazılmaz. | N7 | S | O | `.claude/`, `AGENTS.md`, `CLAUDE.md` kökte kalmak zorunda olabilir (araç keşfi) → taşımak **SAHİBE SORU** |
| D10 | **Discussions'ı aç**; "Ideas", "Q&A", "Show your setup" kategorileri; #32 gibi gerçek hatalara `bug` + uygunlarına `good first issue` etiketi; 3–5 İngilizce, iyi tanımlı başlangıç işi (ör. yeni dil çevirisi: `CONTRIBUTING.md:35-49` Dart gerektirmiyor). | N8 | S | O | Sahip eylemi (ayar + issue açma) |
| D11 | **Dış katkı yolunu iç süreçten ayır:** dışarıdan gelen PR için TASKS/STATE güncellemesi ve tam `verify:smoke` şartı yerine "test + CHANGELOG satırı; iç belgeleri bakımcı günceller". | N8 | S | O | I-04/I-05 ve "Çalışma belgeleri yalın" kararıyla temas → **SAHİBE SORU** (yalnız dış PR kapsamı) |
| D12 | **Türkçe iç belgeleri işaretle:** README/CONTRIBUTING'deki "pick a task from docs/TASKS.md" yerine Discussions/etiketli issue'lar; `docs/README.md`'de "internal (Turkish) working notes" etiketi. Taşıma gerekmez. | N9 | S | D–O | — |
| D13 | **Sürüm ritmi ve notları:** her sürüm notunun başına 3 satırlık insan özeti + bir görsel; uzun teknik not CHANGELOG'a. Ritim (ör. iki haftada bir) sahibin işi. | N10 | S | D | Sürüm/etiket sahibindir (STATE) → ritim **SAHİBE SORU** |
| D14 | **Tek kanca konumlandırması:** README/About/landing aynı tek cümleyi kullansın (öneri yönleri: "acil hatırlatıcıları sessizde çalan, kendin barındırdığın görev uygulaması" ya da "Claude/ChatGPT'ye bağlanan self-hosted görev ve not uygulaması"). | N10 | S | O | Hangi yönün seçileceği zevk/ürün kararı → **SAHİBE SORU** (2 yön) |
| D15 | **Lansman (§5) ve ölçüm:** D1–D5 bittikten sonra, sırayla awesome-selfhosted Non-Free (en erken 2026-11-26), r/selfhosted megathread, Show HN, AlternativeTo, Product Hunt. `?ref=` parametreleri ve 14 günlük trafik anlık görüntüsü (GitHub trafiği 14 günden eskisini tutmaz → haftalık kayıt). | N1 | M | **H** | **Her dış yayın yalnız sahibin onayıyla** (AGENTS "Never": dış hesap) |

İsim değişikliği ("AllisWell" aranabilirliği, N10) bu listeye alınmadı: maliyeti mağaza kayıtları ve alan adı
nedeniyle çok yüksek; yalnız **SAHİBE SORU** olarak not edilir — öneri: isim kalsın, aramada
"AllisWell tasks" / "alliswell self-hosted" gibi ikili kullanım tutarlı olsun.

## 4. README için yeni ilk ekran iskeleti

Dil İngilizce (README'nin dili). Görseller demo tohumundan üretilir; metin taslaktır, rakip metni kopyalanmamıştır.
`<…>` yer tutucudur. Demo satırı D3 gerçekleşmeden yayına girmez.

```markdown
<p align="center"><img src="docs/assets/readme/logo.svg" width="72" alt="AllisWell"></p>
<h1 align="center">AllisWell</h1>
<p align="center"><b>The self-hosted to-do app whose urgent reminders actually ring.</b><br>
Tasks, projects and Markdown notes on web, iPhone, Android, Windows and Linux — on your server or ours.</p>

<p align="center">
  <a href="<demo-url>"><b>Try the live demo</b></a> (no sign-up) ·
  <a href="#run-it-in-60-seconds">Self-host in 60 s</a> ·
  <a href="https://alliswell.space/app">Use the hosted app</a>
</p>

<p align="center">
  [release vX.Y.Z] [ghcr image: api · web, amd64/arm64] [licence: source-available · free for personal use]
  [MCP: Claude · ChatGPT] [platforms: web · iOS · Android · Win · Linux]
</p>

<p align="center"><img src="docs/assets/readme/hero-composite.webp" width="100%"
  alt="Home on a phone and on the web with sample data; an urgent reminder ringing on Silent."></p>

### Why people pick it
- **Alarms, not chimes** — urgent tasks ring through Silent and Focus until you acknowledge them.
- **Two-way Google Calendar** — tasks become events, edits come back.
- **Ask Claude or ChatGPT** — a built-in MCP server, every write needs your approval, no delete tool.
- **Markdown notes and files** next to the tasks they belong to. Offline-first sync on every device.

### Get started — pick one
| | Path | Time |
|---|---|---|
| 1 | **Live demo** — <demo-url>, resets nightly | 0 min |
| 2 | **Self-host** — `curl -fsSL <compose-url> -o compose.yml && docker compose up -d` → http://localhost:8080 | ~1 min |
| 3 | **Apps** — App Store · Google Play · Windows · Linux · hosted web | ~1 min |

<details><summary>How it compares with Vikunja, Super Productivity, Planka, Tasks.org</summary> … </details>
<details><summary>Licence in one minute (free for you, paid for companies)</summary> … </details>
<details><summary>Screenshots · Widgets · Every feature</summary> … </details>

[Self-hosting guide](docs/SELF-HOSTING.md) · [Contributing](CONTRIBUTING.md) · [Discussions](…/discussions) · [Roadmap](ROADMAP.md)
```

İlkeler: ilk ekranda tek cümle + 3 yol + tek görsel; rozetler 5'i geçmez; "Star history", test sayıları,
geliştirici Quickstart ve ajan bölümü ilk ekranda yok. Lisans rozeti "Other" yerine insanın anlayacağı metni taşır.

## 5. Lansman kontrol listesi

> ⛔ **Her dış yayın, gönderi, liste PR'ı ve hesap açma yalnız sahibin açık onayıyla yapılır.** Ajan
> taslak metin ve görsel hazırlar; gönderen sahiptir. (AGENTS.md "Never": dış hesap; STATE: sürüm/deploy sahibin.)

**Ön şartlar (lansmandan önce bitmeli)**
- [ ] D1 About: açıklama "source-available", homepage, topics — *sahip eylemi*
- [ ] D2 Social preview yüklendi — *sahip eylemi*
- [ ] D3 Hesapsız demo canlı ve sıfırlanıyor — *SAHİBE SORU + sahip deploy'u*
- [ ] D4 `localhost`'ta edit'siz açılan compose profili, temiz bir VM'de denendi
- [ ] D5 README ilk ekranı yenilendi; D6 self-host kıyası; D7 lisans SSS
- [ ] D10 Discussions açık, 3–5 `good first issue`
- [ ] Ölçüm: başlangıç anlık görüntüsü (`traffic/views`, `popular/referrers`, yıldız sayısı) kaydedildi; her kanal için `?ref=` etiketi

**Kanallar (öneri sırası)**
- [ ] **awesome-selfhosted — Non-Free sayfası, "Task Management & To-do Lists"** — ana liste yalnız özgür yazılım alır (`awesome-selfhosted/README.md:7`); ilk sürüm 2026-07-26 → "4 aydan eski ilk sürüm" kuralı en erken **2026-11-26**'da sağlanır. PolyForm-Noncommercial-1.0.0 `licenses.yml`'de yok → PR'a lisans tanımı eklenmeli (doğrulanmalı). ⛔ *sahip onayı*
- [ ] **r/selfhosted** — yeni projeler haftalık "New Project" megathread'ine; "AI Involvement" alanı dürüstçe doldurulur (kural kaynağı ayna site, **gönderim öncesi subreddit kurallarından doğrulanmalı**). Lisans sorusuna hazır cevap (D7). ⛔ *sahip onayı*
- [ ] **Show HN** — yalnız D3 (kayıtsız deneme) canlıyken; başlık "Show HN: …" + kişisel ilk yorum (neden yapıldı, lisans neden böyle); landing değil demo/depo bağlantısı (kural: https://news.ycombinator.com/showhn.html). Sahip yorumlara gün boyu cevap verebilecek olmalı. ⛔ *sahip onayı*
- [ ] **AlternativeTo** — Todoist, TickTick, Vikunja, Apple Reminders alternatifi olarak kayıt; ekran görüntüleri demo tohumundan; mevcut kayıt olup olmadığı **bilinmiyor** (403). ⛔ *sahip onayı*
- [ ] **Product Hunt** — en son; barındırılan uygulama + mobil uygulamalar ana hikâye, self-host ikincil; görseller ve ilk yorum hazır; mevcut sayfa durumu **bilinmiyor** (403). ⛔ *sahip onayı*
- [ ] Lansmandan 7 ve 14 gün sonra trafik/yıldız anlık görüntüsü; kanal başına ziyaretçi→yıldız oranı

## 6. Bilinmeyenler ve sınırlar

- GitHub trafiği yalnız son 14 günü verir; daha eski yönlendiren/ziyaret verisi **bilinmiyor**.
- `aocr.org` yönlendireninin niteliği **bilinmiyor** (incelenmedi).
- Klon sıçramalarının CI kaynaklı olduğu **doğrulanmadı**.
- AlternativeTo ve Product Hunt'ta mevcut kayıt **bilinmiyor** (otomatik istek 403).
- Yerel demo tohumunun canlı örnekle ilişkisi sahibin kontrol adımıdır (bu kopyada ayrıntı yok).
- r/selfhosted kuralları resmi kaynaktan değil ayna siteden okundu; gönderimden önce doğrulanmalı.
- Rakiplerin 4 aylıkken yıldız sayıları ölçülmedi; "4 ayda normal ne" sorusu açık.
- Yasal yorum yapılmamıştır; lisans maddeleri yalnız topluluk kabulü açısından değerlendirildi.

## 7. Ham dosyalar

Tur çalışma alanında kaldı (depoda yok).
