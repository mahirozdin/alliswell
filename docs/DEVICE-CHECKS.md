# DEVICE-CHECKS — cihazda bakılacaklar

> Sahibin **isteğe bağlı** gözlem listesi. Sahip kararı (2026-09-23): cihaz gözlemi bir işin
> kapanış koşulu değildir — işler derleme + testle kapanır, cihazda görülecek şey buraya yazılır.
> Bir satır gözlenince (ya da artık anlamsızsa) silinir; bir aksaklık bulunursa TASKS'a iş olur.
> Her oturumda okunmaz.

## Epic 32

- OPH-333 — widget "+" (iPhone large/XL başlığı + medium sütunu, Android başlığı) → sheet açık, uygulama kapalıyken de.
- OPH-334 — Android widget'ı gece yarısından önce bırak, sabah uygulamayı açmadan kovaların döndüğünü gör.
- OPH-336 — iki widget'ı iki farklı projeyle kur (iOS 17+: widget'ı düzenle → List; Android: uzun bas → yeniden yapılandır) ve her birinin yalnız kendi projesini, adıyla gösterdiğini gör; iPhone kilit ekranına iki küçük widget'ı ekle; iOS 17+ galerisinde TEK AllisWell olduğunu, iOS 16'da widget'ın eskisi gibi çalıştığını, Android 12 öncesinde yerleştirirken seçim ekranının açıldığını gör.
- OPH-337 — Ayarlar › Genel › Widget'ta "Gizli widget"ı aç: ana ekran ve kilit ekranı widget'larında başlık yerine "Gizli görev" gör; "Sıkı widget"ı aç: iPhone'da büyük widget'ın son satırı kesilmeden 11 satır, Android'de satırlar sıkı ↔ normal geçişte doğru boyuta dönüyor.
- OPH-341 — Android'de widget satırının dairesine dokun: görev uygulama açılmadan tamamlanıyor (OPH-188'in yolu ilk kez gerçekten koşuyor); altı saatlik tur bildirimleri uygulama açılmadan yeniden kuruyor; gece yarısı çizimi (OPH-334'ün satırı) — üçü de bu düzeltmeden önce Android'de hiç çalışmamıştı.
