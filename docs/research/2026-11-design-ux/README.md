# Design and UX round, 2026-11 (Epic 35)

> Last updated: 2026-11-07 — recorded with OPH-390 · Backlog: [Epic 35 in TASKS.md](../../TASKS.md) ·
> Decisions: [ADR-0062](../../adr/0062-phone-navigation-equal-slot-labelled-capsule.md),
> [ADR-0063](../../adr/0063-platform-tracking-glass-type-v1-one-formatter.md), STATE "Sahip kararları".

**Neden:** sahip (2026-11-07) tasarımdan ve özellikle UX'ten memnun değil: telefon alt barı "kaymış",
düzensiz, kurumsal durmuyor. Kural: tasarım baştan değişmez (AllisWell Glass kalır), core'da UI, UX ve
tipografi iyileşir, landing ve GitHub ilk ekranı güçlenir, değişiklik persona ve demo tohumuyla denenir.

**Nasıl:** kod okuması ve ölçüm (Flutter probe testleri, iOS simülatöründe SF ölçümü), Mobbin
referansları (yalnız bağlantı; görsel kopyalanmadı), rakip ve GitHub/landing denetimi, dört persona
incelemesi, alt bar yönleri için kör hakem. Ekran görüntüleri demo tohumundan; gerçek kullanıcı verisi
yok. Bu klasördeki belgeler turun temizlenmiş kopyalarıdır: uzantıya özgü bölümler çıkarıldı (uzantı
bulguları uzantı deposunda), turun iç çalışma dosyalarına verilen yollar düz metne çevrildi, ham
görseller ve betikler depoya alınmadı. Bulgu kimlikleri değişmedi.

## Belgeler

| Belge | Ne | Kimlikler |
| --- | --- | --- |
| [ux-shell-mobile.md](ux-shell-mobile.md) | Telefon kabuğunun kök neden analizi: alt bar, yüzen öğeler, satır, kırılımlar (15 yapılandırmada probe) | R-01…R-14 |
| [android-shell-probe.md](android-shell-probe.md) | Android 360/412 dp ölçümü, dokta Hızlı Erişim balonu, tanıtım kartı, snackbar | A-01…A-07 |
| [typography-system.md](typography-system.md) | TextTheme çıkarımı, G6 ihlalleri, HIG/M3 karşılaştırması, Glass Type v1 önerisi, kontrast | T-01…T-16 |
| [typography-sf-verification.md](typography-sf-verification.md) | iOS simülatöründe SF genişlik ölçümü: Flutter SF'nin dinamik tracking'ini uygulamıyor | SF-01…SF-04 |
| [mobbin-design.md](mobbin-design.md) | Mobbin'e dayalı spec: ızgara, tip ölçeği, ikon, üç alt bar yönü (A/B/C), satır, ekranlar | K1–K8 (teşhis), T1…, §-numaraları |
| [ux-core-screens.md](ux-core-screens.md) | Core ekranların sezgisel UX denetimi, mobil + masaüstü | §1–§11, Q-xx |
| [competitor-teardown.md](competitor-teardown.md) | Self-hosted emsaller ve ticari referanslar: README ve landing desenleri | CT-01…CT-12 |
| [github-growth.md](github-growth.md) | Depo neden büyümüyor: ölçümler, 10 neden, 15 düzeltme, README iskeleti, lansman listesi | N1–N10, D1–D15 |
| [landing-audit.md](landing-audit.md) | alliswell.space denetimi: 5 saniye testi, dönüşüm katilleri, önerilen metinler (Yön A/B/C) | K1–K15 |

**Depoda olmayan kimlikler:** E-xx (mühendislik bulgusu), U-xx (persona maddesi), C-xx (sahip/CEO
maddesi) ve "Ek A-NN" (kelimesi kelimesine metin) turun persona birleşik raporundan gelir; o rapor
uzantı ayrıntısı taşıdığı için depoya alınmadı. Core'a ait özeti aşağıda; işin kabulü TASKS'ta.

## Persona sonuçları (core'a ait özet)

Dört persona: ürün tasarımcısı (34, Things/Linear), öğrenci (23, TickTick/Anımsatıcılar), KOBİ
operasyon/BT sorumlusu (46), homelab/self-hoster (38, Vikunja). 6 parti, 120 tekil madde (23 yüksek ·
61 orta · 36 düşük), 29 mühendislik bulgusu.

- **Ortak payda:** dördü de fikri beğendi (acil alarm, kendi sunucunda çalışma, doğal dil); hiçbiri
  bugünkü sunumla ödemiyor ya da tavsiye etmiyor. Engel eksik özellik değil, ilk ekranın güven
  kaybettirmesi. Birbirinden bağımsız üç-dört persona aynı ilk üç şeyi söyledi: alt bar, yüzen
  düğmelerin çakışması, ay takvimi.
- **Araştırmaların görmediği kırıklar:** çıkış ve sunucu değiştirmede eski oturum ve takım kromu kalıyor
  (E-01, E-02); itilen her ekranın altında ~100 pt ölü şerit (E-09); açık temada okunmayan durum
  çubuğu; iOS izin metinleri İngilizce (E-13); web'de soğuk derin bağlantı sonsuz yükleniyor (E-17);
  Ana Sayfa sayaçları listeyle uyuşmuyor (E-06); "Standar/t", "Genel bak" gibi kelime ortası kırılmalar.
- **Değer anını öldüren akışlar:** mikrofon sağlayıcı yokken çıkmaza götürüyor (U-07), hızlı eklemede
  onay yok (U-13), izin sorusu ön açıklamasız (U-05).
- **Biçim ve dil:** tarih/saat/sayı en az yedi biçimde (U-09); sen/siz karışık (U-10); "open source"
  iddiası uygulamanın içinde de (E-26); self-host'çunun soruları (ayrı hesap, yedek, MCP adresi
  localhost uyarısı E-28).
- **Tipografi algısı:** web'de başlık ve gövde tracking farkı "iki ayrı aile" gibi okunuyor (U-16).

## Kararlar (2026-11-07)

Sahip planı onayladı. Bağlayıcı olanlar STATE "Sahip kararları"nda; mimari olanlar ADR'de.

| Alan | Karar | Nerede |
| --- | --- | --- |
| Telefon alt barı | B+: eşit 5 yuva, hepsi etiketli, 64 pt kapsül, sağda mikrofon + "+" kümesi; hakem B 44 · C 41 · A 38 · bugün 23 /60 | ADR-0062, OPH-396…398 |
| Hızlı Erişim balonu | telefonda varsayılan kapalı; giriş ⚡, palet, Ana Sayfa'ya uzun basma | ADR-0062 |
| Acil alarm varsayılanı | açık kalır (DESIGN §26 C1); satır yalnız sapmayı gösterir | STATE, OPH-400 |
| Tipografi | font ailesi değişmez; Apple'da HIG tracking, diğerlerinde 0; Glass Type v1; tabular rakam; web Roboto yerel | ADR-0063, OPH-399 |
| Biçim | tek `awFormat*`, sıra ve 12/24 saat bölgeye göre | ADR-0063, OPH-408 |
| Ton | core "sen"; uzantı, portal, landing ve kurumsal sayfa "siz" | STATE, OPH-407 |
| Lisans dili | lisans değişmez; "open source" yerine "source-available" | STATE, OPH-395, OPH-411 |
| Landing | H1 alarm; alt başlık self-host + Claude/ChatGPT MCP | STATE, OPH-412 |
| Mikrofon | AI sağlayıcısı yokken dikte | OPH-402 |
| Fikirler / Inbox | adlar kalır, ikon ampul | OPH-396 |
| Sonraki tur | herkese açık demo, landing ölçümü (analytics), küresel aramada uzantı verisi | — |

## Genel kurallar (core; OPH-407/408 ve DESIGN §45 bunlardan yazılır)

- **Tarih/saat:** UI'da sayısal tarih yok. TR `13:47` · `Yarın 11:00` · `7 Kas 13:47` · `7 Kas 2026,
  13:47`; EN `1:47 PM` · `Tomorrow 11:00 AM` · `Nov 7, 1:47 PM`. Sıra ve 12/24 saat bölgeden. Tarih ile
  saat arasında bölünmez boşluk; ayırıcı `·`. Saat dilimi yalnız kullanıcınınkinden farklıysa. Süre
  `2 gün 12 saat`, `45 dk` (`g`/`sa` yok).
- **Sayı:** TR `48.500 TL`, `6,3 MB`, `%51,4`; oran cümleyle, payda 0 ise `—`; her sayının yanında ne
  saydığı; grup sayacı = görünen öğe sayısı, tamamlananlar açık sayaca girmez; dosya boyutu KB/MB tek
  ondalık, `1 KB'den küçük`.
- **Ton:** core "sen". Cihaz fiili (`dokun`, `tıkla`) yok; düğme ne olacağını söyler. Dramatik ve
  suçlayıcı dil yok; sunucu eksiği yöneticiye yönelik cümleyle. Kırmızı yalnız gecikme ve yıkıcı eylem,
  izin/kurulum uyarısı amber, bilgi azure; uyarılar kapatılabilir. Lisans: TR "kaynak kodu erişilebilir
  (source-available)", EN "source-available".
- **Sözlük (core):** Ana Sayfa/Home · Fikirler/Inbox · Planlanan gün/When · Son tarih/Due (Bitiş değil)
  · Geciken (grup), Gecikti (satır)/Overdue · Acil alarm/Urgent alarm · Hızlı erişim/Quick access ·
  Proje özeti/Overview (README değil) · not kipleri Düzenle · Oku/Edit · Read · Ekler/Attachments ·
  Sunucu/Server.
- **Kırılma:** görev başlığı listede ≤2 satır + `…`; meta tek satır; çip, sekme ve bar etiketi kelime
  ortasından kırılmaz; yatay kayan satırlar sağda 24 pt solma; hiçbir içerik yüzen öğenin altında
  kalmaz, hiçbir öğe güvenli alanın dışına taşmaz.
- **İkon ve ızgara:** tek outlined set, 16/20/24; varsayılan durum için ikon yok, yalnız sapma; Projeler
  ≠ Dosyalar silueti; taşma simgesi `⋯`; ızgara 4/8, telefon oluğu 16 pt, masaüstü 24 px.
