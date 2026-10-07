# DEVICE-CHECKS — cihazda bakılacaklar

> Sahibin **isteğe bağlı** gözlem listesi. Sahip kararı (2026-09-23): cihaz gözlemi bir işin
> kapanış koşulu değildir — işler derleme + testle kapanır, cihazda görülecek şey buraya yazılır.
> Bir satır gözlenince (ya da artık anlamsızsa) silinir; bir aksaklık bulunursa TASKS'a iş olur.
> Her oturumda okunmaz.

## Kabuk, gezinme, erişilebilirlik (2026-10-07)

- OPH-359 — 1440 px web'de Ayarlar › Erişilebilirlik açıkken (ya da NVDA/VoiceOver ile) Tab: sol çubukta Ana Sayfa … Talepler, Onaylar okunuyor, Enter açıyor; mikrofon düğmesi tek bir "Yapay zekâyla konuş" düğmesi, Enter/çift dokunuşla balon açılıyor. Telefonda (390 px) Talepler: "Yeni talep" çubuğun üstünde, dokununca form; alt çubukta yalnız seçili sekmenin adı, kenarda kesik etiket yok; başlığın altında takım noktası + birim adı, birim seçici 10 birimde kayıyor. Hızlı erişim balonu sağ altta FAB'ın üstünde, listeyi kaydırınca kenara çekiliyor (rozet okunur). `#/tickets/<id>`'yi yeni sekmede aç → talep açılıyor, sol üstte Ana sayfa; kuyruktan talep/KB/SLA panosu açınca adres çubuğu o ekranın adresi. Toplantılar: "Kayıt yükle", başarısız toplantıda Türkçe neden. Açık ve koyu temada.

## Talep, onay, bilgi bankası, ekipman (2026-10-07)

- OPH-358 — telefonda talep yazışması: masanın balonları sağda, talep sahibininki solda, her birinin üstünde ad · taraf · kanal (uzantının EE-302'si canlıyken); kendi talebinde kutu "Masaya yaz"; e-postayla gelen talepte "e-postayla gönderilir"; iç nota dosya ekle → notun altında. Kapalı talepte "Bu konu tekrar açıldı" → yeni talebe geçiyor, iki talepte "İlişkili talepler" satırı. `#/tickets/new`'i doğrudan aç → gönder → Taleplerim + snackbar. Ekipman kartında "Bu ekipmanı etkileyen değişiklikler" (EE-304 canlıyken), tarih/para yerel biçim. Açık ve koyu temada.

## Takım adresi (2026-10-07)

- OPH-356 — yönetici yeni davet oluşturur (uzantının EE-300'ü canlıdayken bağlantı `…/app/#/join/<token>?server=…`): bağlantıyı oturumsuz bir tarayıcıda aç → "Takım adresi: <slug>.alliswell.space" + kod/ad/parola → katıl → takım adresinde girişli Ana sayfa. Varsayılan adreste takım üyesiyle gir → Ana sayfada takım bandı, Ayarlar'da tek "Takım adresi gerekiyor" satırı, "Geç" → çıkış yapmadan takım adresinde Talepler + Onaylar. Üye `#/settings/team/roles` → kilitli durum, "+" yok. Açık ve koyu temada bant ve kilitli durum.

## Çıkışta yerel veri (2026-10-07)

- OPH-355 — web'de bir hesapla gir, talep ve bildirim görün, çıkış yap: DevTools › Application › IndexedDB'de `alliswell` bloklarında önceki metin aranınca bulunmuyor, `alliswell_alerts`'te yalnız `__fallback` kalıyor; aynı tarayıcıda ikinci hesapla gir → ilk hesabın bildirimi yok. Çevrimdışı bir değişiklik yapıp çıkışa bas → "N değişiklik" diyaloğu.

## Liste ritmi (2026-09-30)

- OPH-353 — açık ve koyu temada talep kuyruğu, Taleplerim, Bilgi bankası, Varlıklar, bildirim merkezi, denetim günlüğü ve dosyalar: kartlar arası eşit boşluk, hiçbir liste çizgiyle ayrılmıyor.

## GitHub issue'ları (2026-09-26)

- OPH-351 (#17) — Android'de hızlı erişim balonunu hızlı ve uzun sürükle: parmağın altında kalıyor, bıraktığın yarının kenarına yapışıyor.
- OPH-352 (#19) — Chrome'da siteye bildirim izni hiç verilmemişken bant → "Bildirimlere izin ver" tarayıcının istemini açıyor; izin engelliyken yeni sekme açılmıyor, adres çubuğu adımları görünüyor, izin verip "Tekrar kontrol et" bandı kaldırıyor; iPhone'da Safari sekmesinde (Ana Ekran'a eklenmemiş) buton yok, Ana Ekran yönlendirmesi var.

## Epic 32

- OPH-333 — widget "+" (iPhone large/XL başlığı + medium sütunu, Android başlığı) → sheet açık, uygulama kapalıyken de.
- OPH-334 — Android widget'ı gece yarısından önce bırak, sabah uygulamayı açmadan kovaların döndüğünü gör.
- OPH-336 — iki widget'ı iki farklı projeyle kur (iOS 17+: widget'ı düzenle → List; Android: uzun bas → yeniden yapılandır) ve her birinin yalnız kendi projesini, adıyla gösterdiğini gör; iPhone kilit ekranına iki küçük widget'ı ekle; iOS 17+ galerisinde TEK AllisWell olduğunu, iOS 16'da widget'ın eskisi gibi çalıştığını, Android 12 öncesinde yerleştirirken seçim ekranının açıldığını gör.
- OPH-337 — Ayarlar › Genel › Widget'ta "Gizli widget"ı aç: ana ekran ve kilit ekranı widget'larında başlık yerine "Gizli görev" gör; "Sıkı widget"ı aç: iPhone'da büyük widget'ın son satırı kesilmeden 11 satır, Android'de satırlar sıkı ↔ normal geçişte doğru boyuta dönüyor.
- OPH-341 — Android'de widget satırının dairesine dokun: görev uygulama açılmadan tamamlanıyor (OPH-188'in yolu ilk kez gerçekten koşuyor); altı saatlik tur bildirimleri uygulama açılmadan yeniden kuruyor; gece yarısı çizimi (OPH-334'ün satırı) — üçü de bu düzeltmeden önce Android'de hiç çalışmamıştı.
