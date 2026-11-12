# DEVICE-CHECKS — cihazda bakılacaklar

> Sahibin **isteğe bağlı** gözlem listesi. Sahip kararı (2026-09-23): cihaz gözlemi bir işin
> kapanış koşulu değildir — işler derleme + testle kapanır, cihazda görülecek şey buraya yazılır.
> Bir satır gözlenince (ya da artık anlamsızsa) silinir; bir aksaklık bulunursa TASKS'a iş olur.
> Her oturumda okunmaz.

## Widget kendi verisini çekiyor (2026-11-12, Epic 37, #50)

Hepsi **NOT RUN**: işler Vitest, `flutter test` ve Mac'te iOS 27.2 simülatöründe XCTest ile kapandı;
fiziksel iPhone turu sahiple yapılır. Ayarlar ▸ Geliştirici ▸ WidgetKit Developer Mode **kapalı**
olmalı, yoksa iOS'un yenileme bütçesi atlanır ve süre ölçümü anlamsızlaşır. #50, D8 geçince ya da
sahip S-50'yi onaylayınca kapanır (STATE "Kullanıcıdan bekleyen").

- OPH-462 #50 D8/D-W1 — **iPhone, uygulama kaydırılıp kapatılmış, widget ana ekranda** (NOT RUN): Mac'ten görev ekle ve tamamla; widget'ta görünene dek geçen dakikayı kaydet (beklenen: bir WidgetKit yenilemesi, genelde 15–60 dk; ilk günlerde daha sık olabilir).
- OPH-462/464 #50 D-W2 — **iPhone, yeniden başlatma** (NOT RUN): ilk kilit açılışından sonra D-W1 tekrar: çekim oluyor; yeniden başlatıp kilidi açmadan: çekim yok, son liste görünüyor. Uzantı, uygulamanın yazdığı token'ı okuyor (erişim grubu takım öneki olmadan, servis `flutter_secure_storage_service`, hesap `aw_widget_token`).
- OPH-460 #50 D-W3 — **iPhone, Gizli widget açık** (NOT RUN): sunucu ya da proxy günlüğünde `GET /widget/snapshot` yanıtında görev ya da etkinlik başlığı yok; widget satırlarında "Gizli görev" yazıyor.
- OPH-462 #50 D-W4 — **iPhone, uygulama kapalı, gece yarısı** (NOT RUN): 00:01–00:06 arasında Bugün listesi, sayaç ve kilit ekranının "sıradaki"si yeni günün.
- OPH-462 #50 D-W5 — **iPhone, Türkçe ve İngilizce** (NOT RUN): sunucudan gelen satırlardaki saat ve tarih metni uygulamadakiyle aynı; fark varsa Dart/ICU farkı olarak kaydet.
- OPH-462 #50 D-W8 — **iPhone, sunucu kapalı ya da uçak modu** (NOT RUN): widget 8 sn içinde son listeyi gösteriyor, çökme yok; bir sonraki deneme geri çekilmeden sonra.
- OPH-458 #50 D-W9 — **iPhone** (NOT RUN): oturumu kapat ya da Ayarlar ▸ Cihazlar'dan telefonu kaldır: widget sonraki yenilemede 401 alıp çekmeyi bırakıyor, başlık sızmıyor; yeniden girişten sonra uygulama açılınca çekim geri geliyor.

## Üçüncü cila turu: cevapsız istek, web flush'ı, ekran okuyucu, widget "+N" (2026-11-12, #46–#50)

Hepsi **NOT RUN**: işler birim/widget testleriyle, widget işi Mac'te XCTest ile kapandı.

- OPH-427 — **web** (NOT RUN): API'yi bir dakika durdurup yeniden başlat: eşitleme sayfa yenilenmeden sürüyor, Cihazlar listesi sonraki yenilemede geliyor; erişim token'ı o arada dolsa da oturum kapanmıyor.
- OPH-480 — **web** (NOT RUN): çevrimdışıyken bir görevi düzenle, sayfayı yenile: düzenleme duruyor ve bağlanınca eşitleniyor.
- OPH-443 — **iPhone VoiceOver; web klavye** (NOT RUN): liste modunda satır düğmeleri "<başlık>: Ertele" / "<başlık>: Onayla" okunuyor; satırın erteleme sayfasındaki her seçenek bir düğme; sayfa kapanınca Enter ve rakam tuşları yine çalışıyor.
- OPH-466 — **iPhone VoiceOver; masaüstü tarayıcı** (NOT RUN): tek zil ekranında başlık bir kez okunuyor; tam görünen başlığın üzerine gelince ipucu çıkmıyor, kesik başlıkta çıkıyor.
- OPH-451 — **iPhone/simülatör, orta boy widget** (NOT RUN): biri bugün tamamlanmış, 7 açık görevde "+4"; 3 açık görev kalana dek tamamlayınca "+N" satırı yok.

## İkinci cila turu: zil ekranı, cihaz devri, izin şeridi, widget (2026-11-12, #46–#50)

Hepsi **NOT RUN**: işler birim/widget testleriyle, widget işi Mac'te iOS 27.2 simülatöründe XCTest ile kapandı.

- OPH-466 — **web 360×640, sessiz satırla; iPhone VoiceOver** (NOT RUN): tek zil ekranında sessiz cümle ve "Sesi başlat" tam görünüyor, sığmayınca bütün sayfa kayıyor; VoiceOver ekranı sırayla okuyor, her erteleme karosu tek düğme ("5 dakika ertele, 09:05’te çalar").
- OPH-443 — **web liste modu, iki dakikaya yayılan alarmlar; iPhone VoiceOver** (NOT RUN): başlık yalnız sayıyı söylüyor, her kart kendi saatini; satırın erteleme sayfasında başka alarmın dakikası "başka alarmla birlikte" diyor; VoiceOver listeyi sırayla okuyor.
- OPH-446 — **web sekmesi açık + telefon kaydı** (NOT RUN): bir dakika içinde sekme kartı gösteriyor ve sonraki acil alarm zil ekranını açmıyor.
- OPH-449 — **Ana Sayfa, acil alarm çalmayan telefon, açık ve koyu** (NOT RUN): kartın kenar boşlukları diğer uyarılarla aynı; "Tamam" metin düğmesi, sonra dolu "Bu cihazda da çal" (D7/D8).
- OPH-448 — **Ayarlar ▸ Cihazlar, iki çalan cihaz, 360 ve 430 genişlik, açık ve koyu** (NOT RUN): çoklu cihaz notu bir kez, girişin altında; her satırda en çok bir kısa not.
- OPH-428 — **iPhone/simülatör** (NOT RUN): alarm iznini reddet, uygulamayı aç, Ayarlar'dan izin ver, geri dön: şerit kayboluyor, sonraki acil alarm AlarmKit alarmı.
- OPH-451 — **iPhone widget'ları** (NOT RUN): widget dairesine dokun: satır hemen tamamlanmış, BUGÜN sayısı düşüyor; orta boy widget yalnız tam satır çiziyor; VoiceOver "Tamamla: <başlık>" diyor; widget galerisinin açıklaması Türkçe.

## Web turu cilası: zil ekranları, Cihazlar, saat seçici (2026-11-12, #46–#48)

Hepsi **NOT RUN**: işler birim/widget testleriyle kapandı; web turunun ikinci geçişinde ve telefonda bakılır.

- OPH-427 — **web release derlemesi** (NOT RUN): 2+ alarmlı listede bir eylem yap, sonra yeni acil alarm ekle: zamanında çalıyor, düzenlemeler yenilemeden eşitleniyor.
- OPH-441 — **web** (NOT RUN): hh:mm:11 ve hh:mm:32'de iki acil alarm :11'de tek liste açıyor; alarmdan 3 dk sonra açılan uygulama "· 3 dk önce" diyor. Aynı acil görevde :11 hatırlatıcı + :32 deadline: tek Onayla ikisini kapatıyor, :32'de ekran geri gelmiyor; iki dakikalık listede Tümünü onayla sonrası hiçbiri yeniden çalmıyor.
- OPH-466 — **web 360×640 ve 430×932, açık ve koyu; 2.0× metin** (NOT RUN): tek zil ekranında sessiz satır + "Sesi başlat" varken Onayla, Tamamla ve Aç ekranda; dakika değişince erteleme karoları güncelleniyor; saat kullanıcının 12/24 biçiminde; Onayla/Tamamla "Onaylandı"/"Tamamlandı" diyor.
- OPH-443 — **web 360×640, 430×932 ve 1280×800, açık ve koyu** (NOT RUN): üç alarmlı listede başlık sayı + saat, kenar 24 pt, geniş ekranda ortada; satırın erteleme sayfası dakika değişince güncelleniyor; kesik kartta solma.
- OPH-448/449 — **web, açık ve koyu** (NOT RUN): `/settings/devices`'ı yenile, çalan cihazı kaldır, seç, kaydet: geri düğmesi duruyor; başka cihaz kaydolduktan sonra Cihazlar'ı yeniden aç: liste güncel; kapalı web satırında tek not; son çalan cihazı kapatma ve kaldırma diyaloglarında "Vazgeç", "Yine de kapat" kırmızı.
- OPH-471 — **web (+ telefon, sistem 24 saat kapalı)** (NOT RUN): yeni görevde Son tarih metin girişiyle 05:25 ve 17:05 yazılan saatle kaydoluyor; Ayarlar varsayılan görev saati ve özel erteleme de öyle.

## Alarmlar ve widget gün görünümleri (2026-11-12, Epic 36, #46–#50)

Hepsi **NOT RUN**: işler birim/widget testleriyle ve Mac'te iOS 27.2 simülatöründe XCTest ile kapandı;
fiziksel iPhone (iOS 26+) ve Android turu sahiple yapılır (kilit ekranı adımı). Bir satır gözlenince silinir.

- OPH-423 D-46a — **iPhone + Android, uygulama önde** (NOT RUN): aynı dakikada iki acil alarm; her düğme sesi 1 sn içinde kesip ekranı kapatıyor, ikinci alarmın ekranı tam dokunulabilir.
- OPH-466/467 D-46c — **zil ekranı 320/393/430 pt, 360×640 ve 375×667, açık ve koyu, AX5** (NOT RUN): ızgara hizalı, her eylem görünür, etiketler okunur, basılı geri bildirim görünür, "Acil hatırlatma" etiketi okunuyor.
- OPH-422 — **Türkçe arayüz** (NOT RUN): erteleme karoları "09:05’te çalar", onay "09:30’da tekrar çalacak" ekiyle.
- OPH-428 — **iPhone iOS 26/27, uygulama önde, AlarmKit çalarken** (NOT RUN): tek ses; ekran alarmın kilit ekranında da çaldığını söylüyor; uygulamada 5 dk sistem uyarısını da susturuyor.
- OPH-426 D3 — **iPhone** (NOT RUN): native ertelenen alarm preset sonunda bir kez çalıyor; o çalarken uygulamayı aç: üzerine bir şey yapılana dek çalmaya devam ediyor, ikinci alarm doğmuyor.
- OPH-427/431 #49 D1/D4 — **iPhone, uygulama öldürülmüş / arka planda / önde × kilitli / açık** (NOT RUN): uyarıdaki Ertele sesi anında kesip uyarıyı kapatıyor, preset sonunda tek çalma; arka arkaya iki erteleme tek alarm bırakıyor; uygulama açılınca görev basış anına göre "Ertelendi · HH:MM", alarm günlüğünde tek alarmkit satırı; Mac'te erteleme ancak iPhone'da uygulama açıldıktan sonra görünüyor (S-49, beklenen); yeniden başlatıp ilk kilit açılmadan önce Ertele'nin ne yaptığını kaydet; Durdur (düğme ve donanım tuşu) hâlâ durduruyor ve onayı uygulamaya ulaşıyor. Ertelemeden sonra bir görevi düzenle: değişiklik yeniden başlatmadan sunucuya gidiyor (OPH-427).
- OPH-430 — **iPhone iOS 26+, uygulama kapalı; iPhone + Mac widget'ı** (NOT RUN): uyarıdaki Onayla bir sonraki açılışta bir kez uygulanıyor ve görevde görünüyor; widget'taki tamamla dairesi iOS ve macOS'ta hâlâ tamamlıyor.
- OPH-440 — **iPhone iOS 26 + Android** (NOT RUN): 09:00'da üç acil alarm (biri başka cihazda oluşturulmuş): iPhone'da tek ses ve tek "3 acil alarm" uyarısı, Android'de tek tam ekran bildirim; uygulamayı zorla kapatınca uyarının kendi düğmeleri çalışıyor. Uyarı çalarken uygulamayı aç: ikinci uyarı doğmuyor; ikinci satırı önce onayla: sistem alarmı susuyor (OPH-441); Android'de bir satırı onaylamak grubun bildirim sesini kesiyor, diğer satır listede kalıyor.
- OPH-443 D-47a — **telefon, uygulama önde, açık ve koyu, 360×640** (NOT RUN): 09:00'da üç acil alarm tek ekran, tek ses; "Tümünü ertele 5 dk" üçünü 09:05'e taşıyor, 09:05'te tek uyarı çalıyor. Bir satırın erteleme sayfasını açıp birkaç dakika bekle, 5 dk seç: seçimden 5 dk sonra çalıyor; "Saat seç"te saati iptal etmek hiçbir şey ertelemiyor.
- OPH-444 D-47b — **telefon, açık ve koyu** (NOT RUN): 09:00'a ikinci acil görev: bilgi satırı ve "Saati değiştir" çıkıyor, kaydetmek çalışıyor.
- OPH-450 — **iPhone, uygulama öldürülmüş** (NOT RUN): 09:00'da üç acil alarm, 09:05'te başka görevin acil alarmı; uyarıda Ertele (5 dk) üçünü 09:06'ya taşıyor ve orada tek uyarı çalıyor.
- OPH-445/423 — **Android + herhangi bir platform** (NOT RUN): çevrimdışı acil görev oluştur, çalarken bağlan: eşitleme sırasında çalmaya devam ediyor; hatırlatıcısı ve vadesi aynı anda çalan görevi onayla: tekrar çalmıyor.
- OPH-452 — **Android, uygulama kaydırılıp kapatılmış** (NOT RUN): bu cihazın çalma anahtarını değiştir, uyandırma push'u gelsin: alarmlar yeni ayara uyuyor.
- OPH-433/452 D-48a — **iPhone + Android + web, tek hesap** (NOT RUN): önce web sonra iPhone girişi: 09:00'da yalnız iPhone çalıyor; Android (uygulama açık ve kaydırılıp kapatılmış) ve web normal bildirim gösteriyor; Ayarlar ▸ Cihazlar'dan Android açılınca uygulamayı yeniden başlatmadan sonraki alarmı çalıyor.
- OPH-436/445 D-48c/D2 — **iki Android (A, B)** (NOT RUN): B çalarken A'da onayla: B'nin sesi ve tam ekran alarmı uyandırma + eşitleme süresinde kesiliyor; Doze'da bir kez daha (`adb shell dumpsys deviceidle force-idle`); bir kez de alarm oluşturulmadan önce uygulama açılmış (uyandırma önceden koşmuş) B ile.
- OPH-435/447/449 D-48d — **iPhone + Android (+ web sekmesi)** (NOT RUN): iPhone'da Cihazlar'dan Android'i kaldır: 15 dk içinde Android giriş ekranında, listeleri boş, o hesabın hiçbir alarmı çalmıyor; açık web sekmesinin soketinin token süresi bitince ne yaptığını kaydet. Android'den çalan iPhone'u kaldır: seçim sayfası Android'i seçili getiriyor, iPhone sonraki yenilemede çıkış yapıyor, kurulmuş AlarmKit alarmları açılana dek çalabilir. Android çalarken kaldırılınca alarm susuyor; uygulama arka plandayken kaldırılınca sonraki arka plan eşitlemesinde alarmları düşüyor.
- OPH-432/453 D-48e — **mevcut kurulumun yerinde güncellenmesi, iki cihaz** (NOT RUN): hesabın ilk eklenen ve yakın zamanda görülen cihazı çalmaya devam ediyor; diğeri kartı bir kez gösteriyor, "Bu cihazda da çal" onu açıyor; son çalan cihaz kapatılınca alarm bandında "Acil alarm çalan cihaz yok" çıkıyor, bir cihaz yeniden çalınca kayboluyor.
- OPH-448 — **iPhone, Android ve web, açık ve koyu, 2.0× metin** (NOT RUN): Cihazlar ekranında okunur adlar, "Bu cihaz" rozeti, ≥ 48 pt anahtar satırları, web satırında sekme notu; Android'den geçiş iPhone'u kapatıp Android'i açıyor.
- OPH-436 D-50a — **Android, uygulama arka planda** (NOT RUN): web'de eklenen görev birkaç dakika içinde widget'ta.
- OPH-451 #50 D10 — **iPhone widget'ları, uygulama açılmadan** (NOT RUN): 23:58 → 00:02 (ya da saati ileri al): Bugün listesi, sayaç ve kilit ekranının "sıradaki"si yeni günü gösteriyor; üç gün sonra eski liste değil "Liste güncel değil" satırı; gece yarısından sonra widget dairesine dokunmak hâlâ dolduruyor.
- OPH-438 #50 D11 — **iPhone + Android** (NOT RUN): uygulamayı arka plana gönder: iOS widget'ı en yeni listeyi gösteriyor, konsolda home_widget -7 yok; Android'de widget'taki tamamla hâlâ çalışıyor.

## Kontrol listesi öğesini yeniden adlandırma (2026-11-08)

- OPH-420 — **telefon + web, açık ve koyu** (NOT RUN): Türkçe arayüzde hızlı eklemede "Bu ayda bir toplantı" ve "daily toplantısı" tam başlıkla tekrarsız ekleniyor (tarih seçici açılıyor); "her pazar yürüyüş" eklenince alttaki "Eklendi" mesajı "Tekrar: …" diyor.
- OPH-417 — **telefon + web, açık ve koyu** (NOT RUN): hızlı eklemede "Buy a weekly planner" ve "Read Daily Mail tomorrow" tekrarsız görev oluşturuyor, "daily standup" hâlâ günlük; günlük bir görevin detayında Tekrar anahtarını kapat → onayla: görev kalıyor, anahtar kapalı, sonraki günlerin tekrarları gidiyor.
- OPH-416 — **web/masaüstü + telefon, açık ve koyu** (NOT RUN): görev detayında bir kontrol listesi öğesinin metnine dokun/tıkla: imleçli bir alan açılıyor, öğe işaretlenmiyor; Enter ya da dışarı tıklamak kaydediyor, Esc (web/masaüstü) eski adı geri getiriyor, boş bırakmak eski adı koruyor; yalnız kutucuk işaretliyor.

## Cila turu 4 (2026-11-08)

- OPH-397 — **telefon**: Ana Sayfa ve Talepler'i aşağı ve yukarı kaydır, hızlı eklemeye odaklan: mikrofon ve "+" 150 ms'de küçülüp çekiliyor (azaltılmış harekette anında), yukarı kaydırınca ya da kısa bir duraklamadan sonra dönüyor, klavye açıkken gizli kalıyor.
- OPH-392 — **telefon + web**: telefonda bir not aç, webden sil; eşitlemeden sonra "Bu not silindi" uyarısı çıkıyor, not salt okunur, Kapat listeye dönüyor. Silinmiş bir notun bağlantısı "Not bulunamadı" diyor.
- OPH-404 — **iPhone ilk açılış**: adım 3 yaklaşan acil bir görev satırını (boş hesapta hızlı ekleme alanını) çerçeveliyor, kart onu örtmüyor; adım 4 arama düğmesine dokunmayı söylüyor, Ctrl+K yok.
- OPH-402 — **iPhone, AI sağlayıcılı, açık ve koyu**: mikrofona dokun: sayfa kısa rehberi ve üç çipi gösteriyor, bir çip alanı dolduruyor; sağ üstteki Kapat, tutamağa dokunma ve VoiceOver'ın "Kapat"ı sayfayı kapatıyor.
- OPH-400 — **Android 2.0× / iOS AX3**: alt görev tarihi, Ayarlar'daki e-posta, görev detayında Durum/Öncelik alanları, Ana Sayfa başlığı altındaki birim adı ve uzun bir talep konusu tam okunuyor.
- OPH-407 — **iOS AX3, VoiceOver**: görev satırı "Proje: X"i bir kez söylüyor, "Sesi aç" öyle okunuyor, Görünüm menüsü geçerli görünüm ve sırada "seçili" diyor, Bölümler sayfasında her satır tek adlı düğme.
- OPH-405 — **masaüstü/web 1440 px**: "Design System" gibi Hızlı Erişim adları kesilmiyor; satırın üstüne gelince sürükleme tutamacı menünün solunda çıkıyor, menü yer değiştirmiyor.
- OPH-409 — **masa üyesi, telefon ve masaüstü**: Talepler > Tüm birimler satırlarında birim listesindeki gibi "Açan: … · Alan: …" görünüyor.

## Cila turu 3 (2026-11-08)

- OPH-396 — **en büyük metin (iOS AX3, Android 2.0×)**: alt bar açık bölümün tam adını taşıyan tek düğme; dokununca bütün bölümler büyük yazıyla listeleniyor, açık olan işaretli, birini seçince açılıyor; 1.3×'te beş sekme değişmiyor; VoiceOver/TalkBack "Gezinme, Ana Sayfa" ve her satırın seçili durumunu okuyor.
- OPH-398 — **iPhone AX3 ve AX5**: Ana Sayfa haftalık takviminde ay ve yıl tam, oklar altında; başlıkta şimşek, Görünüm ve Ayarlar görünür. **iOS simülatörü, VoiceOver**: görev detayında Durum açılır listesinde "Menüyü kapat" odağı listenin yanında, etkinleştirince durum değişmeden kapanıyor.
- OPH-400 — **telefon, varsayılan ve en büyük metin, açık ve koyu**: Ana Sayfa ve görev listelerinde "Launch AllisWell", "Home renovation", "Personal" "…" olmadan tam, öğeler birbirine yapışmıyor; sesi kapatılmış görevin satırında "Sesi aç" düğmesi normal ve AX3'te tam, dokununca alarm açılıyor; görev detayında (telefon ve masaüstü yan panel) Acil alarm, Sessize al ve Tekrar satırları aynı ikon sütununda.
- OPH-401 — **Ana Sayfa, açık ve koyu, varsayılan ve en büyük metin**: bölüm okları görev rozetleriyle aynı sağ çizgide; başlığın herhangi bir yerine dokununca bölüm katlanıyor.
- OPH-405 — **masaüstü/web 1440 px**: Hızlı Erişim satırlarında fareyle ve Tab ile gezinince menü ile sürükleme tutamacı hiç birbirine değmiyor, sürükleme yine sıralıyor.
- OPH-397 — **iOS/Android Ana Sayfa, açık ve koyu**: mikrofonda ince gri halka, "+"dan yumuşak gölge, kaydırılmış kartların üstünde okunuyor. **Telefon, Talepler**: ikinci ve üçüncü sekmede mikrofon yok; ilk sekmede tam "Yeni talep"in solunda.
- OPH-403 — **telefon ve masaüstü, açık ve koyu**: + ile yeni görev: başlık, açıklama ve etiketler aynı çizgide başlıyor; Proje ve Öncelik satırları mevcut seçimi işaretli bir sayfa açıyor.
- OPH-409 — **web 1440, uzantılı takım**: Ana Sayfa'nın "SLA aşıldı" ve "dolmak üzere" rakamları SLA panosunun "Şu an açık" çiftine eşit, bir eşitlemeden sonra da; 100'den fazla açık talepte "Tüm birimler"in ilk satırı en büyük talep numarası, "Daha fazla" yok; başka birimin talebine dokunup hemen Ana Sayfa'ya geçince Ana Sayfa önceki birimi gösteriyor.
- OPH-412 — **tarayıcı, telefon ve masaüstü genişliği**: `/` ve `/tr` kendi sunucunda bölümünün başlığı, girişi ve "Son adım" etiketi; `/enterprise/tr` alt bilgi satırı ve paket tablosu başlıkları açık ve koyu temada.

## Cila turu 2 (2026-11-08)

- OPH-404 — **iPhone + web, yeni girişte (AI açık ama sağlayıcı yok, ayrıca takım üyesi)**: Ana Sayfa çizildikten sonra tur kırmızı ekran olmadan açılıyor, her koşuda 4 adım; adım 1 alarm şeridinin altındaki hızlı ekleme alanını çerçeveliyor.
- OPH-397 — **iOS simülatörü + 393 px web, 1× ve 2× metin, ajan ve üye**: Talepler'de mikrofon, tam okunan "Yeni talep" düğmesinin solunda; üst üste binme yok.
- OPH-398 — **iOS simülatörü, VoiceOver**: Ana Sayfa Görünüm menüsünde ve bir sayfada "Menüyü kapat" / "Kapat" odağı menünün ya da sayfanın dışında; etkinleştirince sıralama değişmeden kapanıyor.
- OPH-401 — **telefon**: hızlı eklemede tarih sorusunun düğmesi "Tarihsiz ekle"; ekledikten sonra klavye kapanıyor, alan dışına dokununca da; "Geri al" ~5 sn duruyor.
- OPH-392 — **web ve telefon**: `/#/notes/<silinmiş id>` uygulama çubuğu ve "Bulunamadı" gösteriyor; "Ana sayfaya dön" Ana Sayfa'yı açıyor.
- OPH-394 — **web ve iOS, temiz kurulum, çok görevli hesap**: Ana Sayfa iskelet satırlardan doğrudan görevlere geçiyor, "Henüz görev yok" hiç görünmüyor.
- OPH-390 — **web ve iOS**: Ayarlar'dan çıkıp başka hesapla girince Ana Sayfa açılıyor; aynı hesap oturum süresi dolunca kendi sayfasına dönüyor.
- OPH-413 — **telefon tarayıcısı (ya da 393 px öykünme), yavaş ağ**: `/app` açılış ekranında simge, yazı ve çubuk tam boy; uygulama gelince zıplama yok.
- OPH-400 — **iPhone AX3 ve AX5, TR, açık ve koyu**: Ayarlar'da "Entegrasyonlar" ve e-posta kelime ortasında kırılmıyor; takvimde "Kasım 2026" tam; yeni görev sayfasında "Yeni görev" ve "Başlık" etiketi kırpılmıyor.
- OPH-409 — **uzantılı takım, telefon ve masaüstü**: "Tüm birimler" listesinin ilk satırları en yeni talepler, "Yalnız SLA uyarıları" çipi en çok gecikeni öne alıyor; başka birimin talebini açıp geri dönünce (telefon) ya da paneli kapatınca (masaüstü) Ana Sayfa önceki birimi gösteriyor; birimsiz üye /kb'de yanıtların talep formunda önerildiğini ve "Yeni talep açın" düğmesini görüyor.
- OPH-407 — **uzantılı takım, EN ve TR**: İngilizcede iş yükü notu İngilizce; birimsiz üyenin telefonunda Ana Sayfa başlığı altında takım adı; masaüstünde "Tüm birimler" seçiliyken çubukta birim çipi yok.

## Mikrofonsuz cihazda dikte (2026-11-08)

- OPH-402 — **iPhone simülatörü, mikrofonu olmayan bir Mac'te (ses girişi yok), AI açık, TR ve EN**: mikrofona dokununca ve basılı tutunca uygulama çökmüyor (6 sn sonra da); sayfa "Bu cihazda mikrofon kullanılamıyor. Görevini yazarak ekleyebilirsin." / "No microphone is available on this device. You can type your task instead." diyor ve yazma alanıyla açılıyor; sohbet balonunun bas-konuş düğmesi yazı moduna düşüyor. Mikrofonlu Mac'te ve gerçek iPhone'da dikte eskisi gibi dinliyor. Neden cihazda: eski çökme speech_to_text'in AVAudioEngine inputNode okumasında AudioToolbox'ın `abort()` çağrısı (SIGABRT); istisna değil, Dart'tan da Swift'ten de yakalanamıyor; koruma yalnız `AVAudioSession.isInputAvailable` önyoklaması ve bu değerin mikrofonsuz simülatörde `false` döndüğü Linux'ta doğrulanamadı. `true` dönerse çökme yalnız o simülatörde sürer: TASKS'a iş açılır.

## /app açılış ekranı ve kurumsal sayfa (2026-11-08)

- OPH-414 — **iPhone 17 Pro Max simülatörü (Mac) + Pixel 9 Pro XL emülatörü, yeni tohumlanmış demo hesabı, EN**: `screenshots/ios/` ve `screenshots/android/` setlerini docs/SCREENSHOTS.md §2–§3 ile yeni arayüzden yeniden çek (Linux makinede yapılamadı), sonra `npm run shots:store -- --only ios-6.9,ios-6.5,android-phone`; Dosyalar ekranında `floor-plan.png` ve `counter-samples.png` küçük resim, PDF'ler önizlemede açılıyor; "Launch checklist" notunun geçmişinde üç sürüm (oluşturma, düzenleme, MCP). Mağazaya yükleme yok.
- OPH-413 — **deploy sonrası, iPhone Safari + Android Chrome + masaüstü Chrome/Firefox/Safari; açık ve koyu sistem teması; TR ve EN tarayıcı dili**: `alliswell.space/app` açılırken beyaz sayfa yerine uygulama simgesi, "Opening AllisWell…" / "AllisWell açılıyor…" ve kayan ilerleme çubuğu (koyu temada koyu zemin), uygulamanın ilk karesi gelince yumuşakça kayboluyor ve ardında titreme yok; hareket azaltma açıkken çubuk kaymıyor. Ana sayfada masaüstündeki "Tarayıcıda ücretsiz başlayın" → oturum yokken kayıt formu açılıyor; formdan "Giriş yap"a geçince giriş formu kalıyor; aynı sekmede çıkış yapınca giriş formuna dönüyor. `alliswell.space/enterprise` ve `/enterprise/tr`: hızlı kaydırınca ve tam sayfa ekran görüntüsünde boş bölüm yok, yazdırma önizlemesinde bütün bölümler var; sıra sorun → talebin yolu → ekran turu (sekmeler çalışıyor, koyu temada koyu çekim) → "Karar vermeden önce" → pilot → kurulum/paketler/sunum → SSS → iletişim formu; İngilizce sayfada Türkçe kayıt görünmüyor; form gönderimi eskisi gibi.

## Landing ilk ekranı (2026-11-08)

- OPH-412 — **deploy sonrası alliswell.space, iPhone Safari + Android Chrome + masaüstü; EN ve TR**: başlık "Reminders that ring through Silent mode." / "Sessiz modda bile çalan hatırlatıcılar."; birincil düğme iPhone'da (iPad dahil) "App Store'dan indirin", Android'de "Google Play'den indirin", masaüstünde "Tarayıcıda ücretsiz başlayın" ve sayfa açılırken zıplamıyor; altında "Kaynak kodu GitHub'da · N sürüm, ilki Temmuz 2026 · Kişisel kullanım ücretsiz" (N GitHub Releases ile aynı); çubukta GitHub düğmesi (1280 px altında yalnız simge, telefonda menüde). `alliswell.space/olmayan-bir-sayfa` gerçek 404 ve iki dilli sayfa, `/terms`, `/terms/tr` ve `/tr/terms` açılıyor. Bir sohbete `alliswell.space` bağlantısı yapıştırınca kart yeni başlığı gösteriyor.

## Uzantı geniş ekran (2026-11-08)

- OPH-410 — **1440 px web ve macOS (geniş pencere) + 1000 px pencere, uzantılı takım, bir birimde ajan; açık ve koyu tema**: Talepler kuyruğu "Talep · Durum · Öncelik · Açan · Alan · SLA" başlıklı, satır başına tek satır (~56 px), sütunlar hizalı; satıra tıklayınca talep sağda 480 px panelde açılıyor, liste kaymıyor, açık satır mavi çerçeveli; ↑/↓ önceki/sonraki talep, Esc ve sol üstteki ✕ kapatıyor; panel açıkken "Yeni talep" düğmesi listenin üstünde kalıyor; "Tüm birimler" listesinden de panel açılıyor ve orada ↓/↑ satır satır başka birimin talebine geçerken açık birim de her talebi izliyor. İş yükü sekmesi birim/kişi/tür için tek tablo, rakamlar sağa yaslı ve hizalı, başlığa tıklayınca ok ve sıra değişiyor, ikinci tıklama ters çeviriyor. Yeni talep, Yeni değişiklik, Bilinen arıza, Takım ayarları, Takım kimliği, Bildirim tercihleri ve adresle açılan talep içerik olarak en çok 720 px, ortada. 1000 px'te kart görünümü ve itilen detay sayfası aynen eski hâli; telefonda hiçbir şey değişmemiş.

## Uzantı listeleri (2026-11-08)

- OPH-409 — **iPhone + Android + 1440 px web, uzantılı takım, iki birimli yönetici ve birimsiz üye; açık ve koyu tema, 2.0× metin**: Talepler takımın genel alanında "Tüm birimler" seçili açılıyor, satırlarda birim adı, süzgeç çipleri yok; bir birim çipine dokununca o birimin kuyruğu ve çipler geliyor, "Tüm birimler" geri getiriyor. Satırda "Açan: … · Alan: …", atanmamışta turuncu simge + "Alan: atanmadı". Başlıkta Talepler | SLA | İş yükü sekmeleri 360 px'te kesilmeden; SLA'da "Şu an açık talepler" ayrı, "Hedef: %90", kapsam satırı; İş yükünde uyum "—" ya da "%51,4 / 144 talepten". Ana Sayfa'da üyeye "Yeni talep açın" + "Açık taleplerim (N)", yöneticiye "Birimleriniz: N talep gecikti · Onayınızı bekleyen N" (dokununca listesi). Takım üyesi olmayan Taleplerim'de "Yeni talep" görmüyor; `#/settings/team/assignments` "Atamalar Ana Sayfa'ya taşındı" diyor. "Tüm birimler"den bir talep açıp geri dönünce liste yine "Tüm birimler"; bir birim seçip "Tüm birimler"e dönünce indirilen CSV'de her birimin satırları var. Talepler'de arama yazıp Ana Sayfa'ya geçince atanmamış rakamına dokununca arama alanı kapalı ve boş. Başka birimlerde uyarı varken bir birimin içindeki şerit "BT hariç" satırını SLA çipinin altına sığdırıyor; SLA ve İş yükü sekmelerinin kapsam satırları açık ve koyu temada okunuyor.

## Hizmet ayarı: firmalara açık (2026-11-08)

- OPH-415 — **telefon 360 dp, uzantılı takım yöneticisi, TR ve EN, açık ve koyu**: bir hizmetin ayarlarında "Firmalara açık" / "Open to customer companies" anahtarı ve altındaki uyarı cümlesi kesilmeden okunuyor, varsayılan kapalı; açıp kaydedince kayıt durumu doğru, açıp geri kapatınca değişiklik sayılmıyor. Alanı göndermeyen eski bir sunucuda anahtar hiç görünmüyor.

## Tek biçimlendirici (2026-11-08)

- OPH-408 — **iPhone + Android + web; cihaz dili/bölgesi Türkçe-Türkiye, İngilizce-ABD ve İngilizce-Almanya (uygulama İngilizce)**: Ana Sayfa satırlarında bugün yalnız saat, yarın "Yarın 11:00"/"Tomorrow 11:00 AM", sonrası "7 Kas, 13:47"/"Nov 7, 1:47 PM"/"7 Nov, 13:47"; görev detayında "Bugün 13:47"; Almanya bölgesinde 24 saat, ABD'de 12 saat; hiçbir ekranda "07.11.2026" ya da "11/7/2026" yok (Ayarlar'da sayısal biçim seçilmediyse). Ek boyutları "6,3 MB" (TR/DE) ve "6.3 MB" (ABD), 1 KB altı "1 KB'den küçük"; süre "1 saat 30 dk". Ana ekran widget'ının saati bölgeye göre 12/24. Uzantılı takımda tutar "48.500 TL" (ABD bölgesinde USD "$100", CAD/AUD "CAD 100"/"AUD 100"), yüzde "%51,4", form sayısı "48.500" ve "0.001" cevabı "0,001" (0 değil). Satır sonu tarih ile saati ayırmıyor; 2.0× metinde meta satırı taşmıyor.

## Metin geçişi (2026-11-08)

- OPH-407 — **iPhone (en dar), Türkçe, 1.0× ve en büyük metin, açık ve koyu**: Ayarlar › Bildirimler › Hatırlatıcılar'da "Sakin · Standart · Israrcı · Özel" tek satırda, kelime ortasında kırılmıyor; bir projenin sekmeleri ("Özet · Görevler · Notlar · Dosyalar") kesilmeden kayıyor; Dosyalar'da "Klasörlerim · Görev ve not ekleri" ve notta "Düzenle · Oku" tek satır; büyük metinde Ana Sayfa'nın hızlı ekleme ipucu "Görev ekle". Uzantılı bir takımda uzantı ekranları baştan sona "siz", kişisel ekranlar "sen" diye konuşuyor; üye olmayan hesapla takım adresinde e-posta adresi ve "Hesap değiştir" görünüyor. Bildirim merkezi ve bildirim tercihleri TR ve EN'de SLA satırlarında "SLA aşıldı" / "SLA missed" diyor; hiçbir yerde "ihlal" ya da "breached" yok.

## Parola sıfırlama (2026-11-08)

- OPH-406 — **SMTP'li bir sunucuda (örn. Mailpit), iPhone + Android + web, TR ve EN, açık ve koyu**: girişte "Parolamı unuttum" parola alanının altında, yazılı e-posta formda hazır; "Bağlantıyı gönder" → "E-postanı kontrol et"; gelen e-posta seçili dilde, bağlantı web uygulamasında "Yeni parola belirle"yi token'la açıyor (oturum geri yüklenirken bile — yeni sekmede yapıştır); yeni parola kaydedilince "Parolan değişti", diğer cihazdaki oturum ilk yenilemede kapanıyor; aynı bağlantı ikinci kez "artık çalışmıyor" + "Yeni bağlantı iste". SMTP'siz sunucuda "Bu sunucu e-posta göndermiyor" + kopyalanabilir komut; `docker compose exec api node apps/api/src/cli/password-reset-link.js <e-posta>` bağlantı basıyor; telefonda "Bağlantım var"a yapıştırınca parola değişiyor. 1.3× ve 2.0× metinde kartta taşma yok, düğmeler ≥44 pt.

## Masaüstü: ray, görev paneli, kısayollar (2026-11-07)

- OPH-405 — **Web (Chrome, Safari) ve macOS/Windows uygulaması, 1440 ve 1280 px, TR, açık ve koyu**: Ana Sayfa'da bir göreve tıklayınca liste yerinde kalıyor, görev sağda 480 px panelde açılıyor (takvim paneli o sırada gizli), "+" ve mikrofon panelin solunda; ↓/↑ sıradaki/önceki görevi açıyor ve liste o satıra kayıyor; başlık alanındayken oklar imleci oynatıyor, ilk Esc alandan çıkarıyor, ikincisi paneli kapatıyor; panelde "Sil" paneli kapatıyor, geri al çalışıyor. Ayarlar ve bir görev bağlantısı (yeni sekmede `/tasks/…`) solda rayla açılıyor, raydan bir bölüme gidiliyor. Pano dört sütunu kesmeden gösteriyor; "Görünümü düzenle"den beşinci sütun açılınca altta kaydırma çubuğu ve sağ kenarda solma çıkıyor, fareyle çubuktan ve trackpad'le yana kayıyor. Bir alana odaklı değilken N yeni görev penceresini, / aramayı açıyor; Türkçe Q klavyede Shift+7 ile de. Panelde açılan ve ↓ ile geçilen görevler, panel kapandıktan sonra boş "/" aramasında son öğeler olarak en yenisi üstte görünüyor. 1199 px'e daraltınca panel kapanıyor ve görev eskisi gibi kendi sayfasında açılıyor. VoiceOver/NVDA açık satırı "seçili" okuyor.

## İlk açılış: tur ve boş Ana Sayfa (2026-11-07)

- OPH-404 — **iPhone 393 ve Android 360, TR, açık ve koyu; ayrıca masaüstü ≥1200 px**: yeni hesapla ilk girişte (ya da Ayarlar → Uygulama turu) tur 4 adım: "Hızlı yaz" kartı hızlı ekleme alanının altında ve alan aydınlık; "Sesle ekle" mikrofonu, "Her yerde ara" alttaki büyüteci (masaüstünde raydaki arama kutusunu) çerçeveliyor; "Acil alarm" ortada. "Atla" kartın içinde "İleri"nin solunda, "İleri" adımlar arasında yer değiştirmiyor; kart hiçbir adımda ekran dışına taşmıyor. Turu bitirince boş Ana Sayfa'da "Henüz görev yok" + "İlk görevini ekle" (dokununca klavye hızlı ekleme alanında açılıyor) + "Todoist ya da TickTick'ten taşı" (içe aktarma sihirbazını açıyor); metin yüzen düğmelerin altında kalmıyor. Bir görevi tamamlayınca "Bugünlük bu kadar / Açık görevin kalmadı." ve onay dairesi. VoiceOver/TalkBack kartı "Uygulama turu, adım 1/4" diye okuyor.

## Yeni görev sayfası (2026-11-07)

- OPH-403 — **iPhone 393 ve Android 360, TR, açık ve koyu**: Ana Sayfa'daki + ile sayfa açılınca klavye açıkken başlık satırında solda "Vazgeç", sağda mavi "Ekle" görünüyor; başlık boşken "Ekle" soluk ve basılmıyor; klavyedeki "Bitti"/✓ görevi oluşturup sayfayı kapatıyor. Bir şey yazıp tutamaktan aşağı kaydırınca sayfa geri yukarı çıkıp "Yazdıkların silinsin mi?" soruyor, "Yazmaya devam et" metni koruyor; boş sayfa soru sormadan kapanıyor. Android'de Geri tuşu da soruyor. **Masaüstü (macOS/Windows/web ≥800 px)**: form ortada iletişim kutusu, Ctrl/⌘+Enter oluşturuyor, Esc yazılmışsa soruyor. VoiceOver/TalkBack "Ekle" düğmesini başlık boşken devre dışı okuyor.

## Sağlayıcısız mikrofon (2026-11-07)

- OPH-402 — **iPhone, AI açık ama sağlayıcı bağlı değil, TR, açık ve koyu**: mikrofona ilk dokunuşta iOS izin soruları açıkken sayfada "Mikrofon izni bekleniyor" yazıyor (arkada "Dinliyorum…" yok); izin verilince "Söylediğin görev olarak eklenecek" ve söylenen canlı görünüyor; "Bitir"e basınca metin hızlı ekleme alanında, ↑ ile "Fikirler'e eklendi: …" çıkıyor ve görev Fikirler'de; "yarın 9'da …" denince tarihli görev Ana Sayfa'da. Basılı tutunca da aynı sayfa açılıp dinliyor. İzin reddedilince sayfa yazma alanıyla açılıyor. VoiceOver düğmeyi "Sesle görev ekle" diye okuyor. **Android'de** aynı akış (TalkBack).

## Ana Sayfa ilk ekranı (2026-11-07)

- OPH-401 — **iPhone 393 ve Android 360, demo tohumu, açık ve koyu, TR**: Ana Sayfa hafta şeridiyle açılıyor (bugün dolu mavi daire, görev noktası), "Ayı göster" ayı açıyor ve uygulama yeniden açılınca seçim kalıyor; ilk ekranda Geciken satırı ve altındaki bölümler görünüyor. Bölüm başlığına dokununca bölüm katlanıp açılıyor, ok dönüyor; VoiceOver/TalkBack "Geciken bölümünü daralt, N görev" okuyor. Hızlı eklemeye dokununca altta örnek şeridi + "Daha fazla", yazınca ✨ (AI varsa) ve mavi ↑ geliyor; gönderince "Eklendi: … · Geri al" 3 sn görünüyor, satır kısa süre vurgulanıyor, tarihsiz görevde liste ona kayıyor, liste sonuna kaydırılmışken yarına eklenen görevde (geniş pencerede de) liste yukarı dönüp onu gösteriyor ve klavye açıkken hızlı ekleme alanı yazmaya devam edilince geri geliyor. **Metin boyutu en büyük**: şeritte rakamlar dairenin içinde.

## Görev satırı (2026-11-07)

- OPH-400 — **iPhone 393 ve Android 360, demo tohumu, açık ve koyu, TR**: Ana Sayfa'da uzun başlık en çok 2 satır + "…", onay dairesi ilk satırın ortasında; açık/orta öncelikli/acil alarmlı görevde sağda ve meta satırında simge yok, "Gecikti" yalnız sözcük kırmızı; proje rozeti ilk satır hizasında; yapıştırılmış URL tek satır "alanadı › yol". Pano kartında "Taşı" düğmesi başlığın ilk satırında, başlığın üstüne binmiyor. **Metin boyutu en büyük (iOS AX5 / Android 2.0)**: satır dikey, kelime ortasından kırılma yok, meta öğeleri başlığın altına sarıyor; EN + 12 saatte ertelenmiş alarmlı görevde "Snoozed — 11:50 PM" kart içinde kalıyor (gerekirse iki satır).

## Tipografi: Glass Type v1 (2026-11-07)

- OPH-399 — **iOS simülatörü (iPhone 393 ve 440), demo tohumu, açık ve koyu**: satır başlığı, meta ve bar etiketi genişliği yerel UILabel ile aynı (±0.2 pt; yöntem `research/2026-11-design-ux/typography-sf-verification.md` §1: 3x ekran görüntüsü + simülatör içinde `sfmeasure.swift`); beklenen satır başlığında −%10…−12, geciken meta tek satır. Ana Sayfa'da "Geciken · N" kırmızısı aurora lekesinin üstünde rahat okunuyor; sayaçlar, tarih ve saatler değişirken yanındaki metin kaymıyor (tabular). **Android 360 ve web (Chrome)**: harf aralığı 0, metin önceki hâlinden belirgin dar değil; web'de w600 başlıklar (SemiBold dosyası yok) kalın çiziliyor mu bak.

## Telefon alt barı: AwTabCapsule (2026-11-07)

- OPH-398 — **iPhone 393 ve Android 360, açık ve koyu, TR**: Ana Sayfa çubuğunda yalnız ⚡, Görünüm (ikon + ⌄) ve Ayarlar; "Ana Sayfa" başlığı tam. Görünüm menüsü: Liste/Pano, Takvimi gizle/göster, Sıralama; panoda "Görünümü düzenle". Açılışta süzme alanı görünmüyor, listeyi biraz aşağı çekince huni ikonlu alan çıkıyor; çekmeye devam edince yenileme dönüyor (iOS'ta tek hareket, Android'de de). Kısa listede (1–2 görev) de alan saklı başlıyor. **Metin boyutu en büyük**: başlık kesilmiyor, alan yazıyı kesmiyor.
- OPH-397 — **Android 360 dp (3 düğmeli ve hareketli gezinme) ve iPhone 393, açık ve koyu**: AI açıkken mikrofon "+"nın solunda, ikisi aynı hizada, sol alt boş; aşağı kaydırınca ikisi biraz iniyor, yukarı ya da durunca dönüyor; listenin sonu "+"nın üstünde bitiyor, bar altındaki içerik sayfa rengine soluyor (cam değil). **Ayarlar ▸ Hızlı Erişim balonu açık**: balon "+"nın üstünde, ekran kenarına taşmıyor, bekleyince yalnız soluyor; görev detayı/Ayarlar'da yok; ilk gösterimdeki tanıtım kartı balonun üstünde ve sistem çubuğunun üstünde. Ana Sayfa sekmesine uzun basınca Hızlı Erişim açılıyor; arama boşken "Kısayollar". **iPad mini dikey (744)**: Ana Sayfa tek sütun, alt kapsül.
- OPH-396 — **iPhone 393 ve 430, Android 360 ve 412, açık ve koyu tema, TR**: alt barda beş sekme eşit genişlikte, hepsinin etiketi kapsülün içinde ve tek satırda ("Ana Sayfa" 360'ta küçülerek sığıyor, kesilmiyor); sekme değiştirince ikonlar ve etiketler yerinde kalıyor, yalnız seçim hapı ve dolu ikon değişiyor; Fikirler ampul, Dosyalar ataş. **Ayarlar ▸ metin boyutu en büyük (2.0×)**: etiketler 1.3'te kalıyor; bir sekmeye uzun basınca kapsülün üstünde büyük ad balonu, parmak kayınca balon izliyor, bırakınca o sekme açılıyor. **Altı bölümlü bir adreste**: 5. yuva "Diğer", dokununca Dosyalar ve altıncı bölümün sayfası; birini açınca "Diğer" seçili. VoiceOver/TalkBack: "Ana Sayfa, sekme 1 / 5, seçili". **Temiz kurulumda**: Hızlı Erişim balonu yok, Ana Sayfa çubuğunda ⚡ var.

## Küçük kırıklar ve source-available (2026-11-07)

- OPH-395 — **Web (yerel `flutter build web` + Chrome DevTools ▸ Network)**: ilk açılışta ve bir görev listesi açıkken `gstatic.com`/`fonts.googleapis.com` isteği yok, Roboto ve CanvasKit kendi sunucudan; Türkçe ı/ğ/ş ve w500 satır başlıkları doğru çiziliyor. P-01: `dart run tool/mirror_noto_fallback.dart` ile doldurulmuş derlemede bir görev başlığına “会议 😀” yaz → karakterler kutu değil gerçek glif, istekler yalnız `…/fonts/noto/…` adresine. **Android**: satır başlıkları ve etiketler (w500/w600) önceki gibi görünüyor (artık paketteki Roboto). **iPhone**: yeni görev → klavye açıkken sayfanın üstündeki karartılmış şeride dokun → sayfa kapanıyor; VoiceOver "Kapat" ile de. Ayarlar ▸ Alarm günlüğü: satırlar sözcüklerle, "Ayrıntı" ham satırı açıp kapatıyor. **Web 1440, yerel compose (localhost)**: Ayarlar ▸ Entegrasyonlar ▸ "Claude / ChatGPT'ye ekle" kartında A-77 uyarısı, açık ve koyu temada okunur.

## Ana Sayfa sayıları, alt görevler, Pano tekrarları, arama (2026-11-07)

- OPH-394 — **iPhone ve web 1440**: demo verisinde Ana Sayfa "Geciken · N" kırmızı "Gecikti" satır sayısına eşit, üstü çizili satırlar başlık sayısına girmiyor; alt görevi olan görevin detayında "Alt görevler" kartı, alt görev Ana Sayfa'da ayrı satır değil; Pano "Açık" sütununda "Invoice Acme" bir kez ve altında "+2 sonraki"; arama "invoice": "N sonuç" alanın hemen altında, "Notlar · 9" altında 3 not + "6 sonuç daha göster" dokununca açılıyor; açık ve koyu tema.

## İzin ve alarm şeritleri (2026-11-07)

- OPH-393 — **iPhone, temiz kurulum**: giriş yap → bildirim izni penceresi açıkken arkada şerit yok; "İzin ver" → Ana Sayfa'da şerit kalmıyor; "İzin verme" → pencere kapanınca amber şerit "Bildirimler kapalı. Hatırlatıcılar sana ulaşamaz." + "Aç" düğmesi, "×" basınca kayboluyor ve uygulama yeniden açılınca da gelmiyor. Ayarlar ▸ Erişilebilirlik ▸ Daha Büyük Metin en büyükte düğme metnin altında, tam genişlikte; açık ve koyu temada okunur. **Web, VAPID anahtarı olmayan sunucu (yerel compose)**: izin verilmiş tarayıcıda "Bu sunucuda tarayıcı bildirimleri kurulu değil. Sunucu yöneticine haber ver." şeridi, düğmesiz, yalnız "×". **Web, Sessiz'e hiç dokunulmamış tarayıcı**: acil alarm kaplaması "varsayılan olarak sessiz" der, "bilerek sessiz" demez; Ayarlar'da Sessiz seçilince "Bilerek sessiz" der. VoiceOver / ekran okuyucu kaplama açıkken alttaki Ana Sayfa'ya geçmiyor.

## Web soğuk bağlantı, Google düğmesi, çevrimdışı şeridi (2026-11-07)

- OPH-392 — **Web, telefon genişliği (393) ve 1440**, oturum açıkken: bir görevin adresini (`/#/tasks/<id>`) yeni sekmede aç → kısa splash'ten sonra görev detayı açılıyor; silinmiş bir görevin adresi ve bozuk bir adres (`/#/tasks/typo`) → "Bulunamadı" + "Ana sayfaya dön". Oturum kapalıyken aynı bağlantı → giriş → giriş sonrası görev açılıyor. **Google istemcisi olmayan sunucu** (yerel compose) → giriş ekranında "Google ile devam et" yok, "veya" çizgisi de yok; hosted sunucuda düğme (iOS'ta Apple ile birlikte) duruyor. **Telefon genişliği**, Ana sayfa açıkken ağı kes (DevTools offline / uçak modu) → bir sonraki çekmede durum çubuğunun altında "Sunucuya ulaşılamıyor — son eşitlenen veriyi görüyorsun." şeridi, uygulama çubuğu şeridin altında ve iki kez boşluk yok; açık ve koyu temada okunur; ağ gelince şerit kendiliğinden kalkıyor. **iPhone ve Android** aynı şerit.

## İtilen ekranlar, durum çubuğu, iOS izin metinleri (2026-11-07)

- OPH-391 — **iPhone, iOS dili Türkçe**, temiz kurulum: Ana sayfada mikrofona dokun → mikrofon ve konuşma tanıma izin pencereleri Türkçe (Ek A-65 metni); bir göreve fotoğraf ekle → kamera/fotoğraflar metni Türkçe; takvim ve (iOS 26) alarm izni de Türkçe. iOS dili İngilizce → aynı pencereler İngilizce. **iPhone, açık tema**: Ana sayfada, görev detayında ve Ayarlar'da saat, sinyal ve pil koyu ve okunur; koyu temada beyaz. Hızlı Erişim balonu bar satırına yerleşikken görev detayı, Ayarlar ve bir not ekranın altına kadar iniyor (altta boş şerit yok), balon orada görünmüyor; geri dönünce bar satırında yine duruyor. Balon yukarı taşınmışsa itilen ekranlarda da görünüyor. **Android telefon**, açık/koyu tema: durum çubuğu simgeleri aynı kurala uyuyor, gezinme çubuğu değişmemiş.

## Çıkış ve sunucu değiştirme (2026-11-07)

- OPH-390 — **iPhone ve Android telefon**, bir takım hesabıyla giriş yapılmış ve sync dönmüşken: Ayarlar › Çıkış yap → giriş ekranı geliyor (dokunuş boşa gitmiyor). Tekrar gir, Ayarlar › Hesap › Sunucu → başka bir sunucunun adresini kaydet → dialog kapanıyor, giriş ekranı, hata yok; o sunucuda başka bir hesapla gir → Ana sayfada eski hesabın görevleri, ve "Takım: …" kromu YOK. Giriş ekranında sunucu satırına dokunup adres kaydet → dialog kapanıyor, giriş ekranında kalıyor, yeni adres yazıyor. Bir **release** derlemesinde de aynı tur (debug'daki hata release'te görünmüyordu; sıra hatası görünüyordu).

## CalDAV (iCloud / Nextcloud) (2026-10-17)

- OPH-380 / ADR-0059 — test sunucusunda `CALDAV_ENABLED=true` ve gerçek bir `CALENDAR_TOKEN_KEY`. **Gerçek iCloud** (2FA'lı Apple hesabı): appleid.apple.com › Giriş ve Güvenlik › Uygulamaya Özel Parolalar'da parola oluştur → web'de (ya da Android/Windows/Linux) Ayarlar › Entegrasyonlar › "iCloud ya da CalDAV takvimi" › iCloud: önce NORMAL Apple parolasıyla dene → "uygulamaya özel parola kullan" hatası, hesap oluşmuyor; sonra uygulamaya özel parolayla bağlan, takvim seç (birden fazlaysa seçici hemen açılıyor). ~5 dk içinde görevler iCloud.com Takvim'de ve iPhone'da. Apple Takvim'de bir etkinliği sürükle → sonraki yoklamadan sonra görevin bloğu taşınıyor, bitiş saati değişmiyor. Bir etkinliği sil → görev duruyor, yeniden aynalanmıyor. Görevi tamamla → etkinlik "✓". Görevi iptal et → etkinlik kalkıyor. Bir etkinliği .ics olarak dışa aktar ya da iCloud.com'da incele: `X-ALLISWELL-TASK-ID` duruyor mu → sonucu CALDAV.md §4.4'e yaz. Kendi bir toplantın ve haftalık tekrarlayan bir etkinliğin Ana sayfada/Takvim'de görünüyor. Bağlantıyı kes → onay metni appleid.apple.com'da iptali söylüyor; sonra parolayı orada iptal et. **Gerçek Nextcloud**: "Başka sunucu" › `https://<nextcloud>` (well-known keşfi) + Nextcloud uygulama parolası (Ayarlar › Güvenlik › Cihazlar ve oturumlar) → aynı sürükle/sil/tamamla turu Nextcloud Takvim'de ve DAVx⁵'li bir telefonda. LAN'daki http Nextcloud için `CALDAV_ALLOW_PRIVATE_HOSTS=true` ile bağlanıyor, kapalıyken "bu adres kullanılamaz". **Apple cihazda çift ayna koruması** (iPhone + Mac): Apple Takvim aynası açıkken web'den iCloud CalDAV bağla, uygulamayı aç → EventKit'in oluşturduğu etkinlikler siliniyor, Apple kartında "Sunucun görevlerini zaten iCloud takvimine yazıyor…" notu, her görev bir kez görünüyor; CalDAV'ı kes → cihaz aynası geri dönüyor. Bu cihazlarda bağlanma sayfasında iCloud seçeneği yok. Açık ve koyu temada, TR'de 390 px'te bağlanma sayfası taşmıyor.

## AI sohbetinde "@" ile ek (2026-10-17)

- OPH-377 / ADR-0058 — **iPhone ve Android telefon**, AI bağlantısı kurulu: AI balonunu aç, "Özetle @" yaz ve bir not başlığının bir kısmını gir → panel notu gösteriyor, dokun → çip çıkıyor, "@…" metni alandan siliniyor → "burada ne karar verdik?" diye sor → cevap notun içeriğinden, gönderilen mesajın altında not çipi. Dosyalar ekranından yüklenmiş bir .md/.txt dosyasını ekle → içeriği kullanılıyor. Bir PDF ya da görsel satırı soluk, "Yalnız metin dosyaları eklenebilir" yazıyor, dokununca eklenmiyor. Uzun (>12.000 karakter) bir metin dosyası → çipte "kısaltıldı", mesajın altında "… yalnız ilk 12.000 karakteri gönderildi". Bir e-posta adresi yazmak paneli açmıyor. Gboard Türkçe ve iOS Türkçe klavyede "@çalış" yazarken panel titremiyor, harf kaybolmuyor. Açık ve koyu temada, 390 px'te çipler ve panel taşmıyor. **Web (app.alliswell.space)**: bir metin dosyası ekle → yükleniyor; "Yüklenemedi" diyorsa prod R2 kovasının CORS kuralı eksik (ATTACHMENTS.md §8, STATE "Kullanıcıdan bekleyen" #12). **Masaüstü (macOS/Windows/Linux)**: yalnız klavye — "@" → ↑/↓ satırı taşıyor (dolgu + ⏎), Enter ekliyor, Esc paneli kapatıyor ama balonu KAPATMIYOR. İsteğe bağlı: Ollama bağlantısıyla uzun bir not ekle; model içeriğin sonunu görmüyorsa Ollama sunucusunda `num_ctx`'i büyüt.

## Siri ve kısayollar (2026-10-17)

- OPH-376 / ADR-0057 — Swift Mac'te derlendi (2026-10-17). **iPhone, iOS dili İngilizce**: uygulamayı bir kez açıp giriş yap → "Hey Siri, add a task in AllisWell" → Siri "What's the task?" → "pay rent tomorrow at 9" → uygulama öne geliyor, SnackBar "Added: pay rent · …", görev yarın 09:00 bitişli, 08:00 alarmı Sessiz modda çalıyor. Aynısı uçak modunda: görev oluşuyor, çevrimiçi olunca sync'leniyor. "Hey Siri, show today in AllisWell" → Ana sayfa bugün seçili. Kestirmeler › Uygulama Kestirmeleri'nde AllisWell "Add task" ve "Today" kutuları (mavi), Spotlight'ta "AllisWell" aramasında ikisi de; açık ve koyu temada. Kestirmeler'de Metin "süt al" → AllisWell Add task → Fikirler'de görev. Uygulama kapalıyken (soğuk açılış) ve oturum kapalıyken: istek kaybolmuyor, giriş yapılınca görev oluşuyor. **iPhone, iOS ve Siri dili Türkçe**: "Hey Siri, AllisWell'e görev ekle" → "Görev ne?" → "yarın saat 9'da kira" → "kira" yarın 09:00; "AllisWell'de bugünü göster"; diğer varyantları da dene ("AllisWell ile görev ekle", "AllisWell'de yeni görev", "AllisWell'e ekle"), Siri'nin hangilerini tanıdığını not et. iOS 16 cihaz varsa açılışta çökme yok. Ayarlar › AllisWell'de artık dil seçici görünüyor; Flutter arayüzü kendi dil ayarını izliyor. **Mac (macOS 14+)**: Kestirmeler'de AllisWell Add task ve Today; metinle çalıştır → AllisWell penceresi öne geliyor, görev oluşuyor; Mac'te Siri "Add a task in AllisWell". **Android telefon**: AllisWell simgesine uzun bas → "New task" / "Yeni görev" ve "Today" / "Bugün" (sistem dili EN ve TR), açık ve koyu başlatıcı temasında simgeler okunuyor; "New task" oluşturma sayfasını, "Today" Ana sayfayı açıyor; bir kısayolu ana ekrana sabitle → çalışıyor. Google Assistant/Gemini ile sesle görev eklemek 2026'da yok (ADR-0057); "Hey Google, open AllisWell" sonra dokunuş.

## Tamamlanınca tekrar (2026-10-17)

- OPH-375 / ADR-0056 — **iPhone** ve **Android telefon**, canlı sunucuya bağlı: yarın 09:00 bitişli, 08:00 hatırlatıcılı görev oluştur → detay › Tekrarla → "Tamamlanınca", 2, gün → Kaydet; özet "Tamamlanınca 2 gün sonra · bitiş yok". Uçak modunu aç, görevi tamamla, birkaç dakika bekle, uçak modunu kapat → ilk sync'ten sonra yeni görev BUGÜN + 2 gün 09:00 bitişli (yarın + 2 değil) ve 08:00 alarmı Sessiz modda da çalıyor. Tamamlanan görevi geri aç → yeni görev kayboluyor, alarmı gelmiyor. Açık görevi sil → Geri Al süresi geçince tekrar duruyor (anahtar kapalı), süpürme ertesi gün yeni görev üretmiyor. Başlığı değiştir, tamamla → sıradaki görev yeni başlıkla. Dialog açık ve koyu temada, TR ve EN, 390 px'te: "Takvime göre / Tamamlanınca" tek satır (EN "After completion" iki satır, ortalı), gün/hafta/ay taşmıyor, "Bugün tamamlarsan" tarihi bugün + aralık.

## Her yerden arama (2026-10-16)

- OPH-374 / ADR-0055 — **Web, Chrome + Firefox (Windows/Linux, Ctrl+K) ve Safari + Chrome (Mac, ⌘K)**: Ana sayfada, bir görev detayında ve Ayarlar'da kısayola bas → AllisWell paleti açılıyor, tarayıcının adres/arama çubuğu ODAKLANMIYOR. "fatura" yaz → Görevler/Projeler/Dosyalar grupları; ↓ ↓ Enter → ikinci satır açılıyor; Esc kapatıyor; açıkken tekrar kısayol kapatıyor. Bir notun kaynak modunda imleç metindeyken ⌘K/Ctrl+K → notun KENDİ komut paleti açılıyor, arama değil. **macOS uygulaması** (⌘K) ve **Windows/Linux masaüstü** (Ctrl+K) aynı turu geçiyor; macOS'ta bir metin alanında Ctrl+K satır sonunu silmeye devam ediyor. **iPad, donanım klavyesi** ⌘K ve **Android tablet, klavye** Ctrl+K paleti açıyor. **iPhone ve Android telefon, 390 px**: arama düğmesi cam alt çubuğun sağında, açık ve koyu temada; Hızlı Erişim balonu sola ve sağa yerleşikken ve + düğmesi görünürken çakışma yok; dokununca tam ekran palet klavye açık geliyor, sonuç dokunuşla açılıyor. **VoiceOver (iOS/macOS) ve TalkBack**: alan, grup başlıkları ("Görevler"), sonuç sayısı ve seçili satır okunuyor. **Sahip incelemesi**: telefonda çubuk artık çoğunlukla yalnız seçili sekmenin etiketini yazıyor (arama düğmesi bir sekme genişliği alıyor); tercih uygulama çubuğunda altıncı ikonsa ADR-0055'i değiştir.

## Doğal dille hızlı ekleme (2026-10-16)

- OPH-373 / ADR-0054 — **Android telefon, Gboard Türkçe** ve **iPhone, Türkçe klavye**: Ana sayfa hızlı ekleme çubuğuna "Yarın 9'da kira #ev" harf harf yaz (otomatik düzeltme ve öneri dokunuşları dahil). Beklenen: yazarken harf kaybolmuyor/çiftlenmiyor, sözcük tamamlanınca vurgu geliyor, çubuğun altında Bitiş ve #ev çipleri çıkıyor, Enter tarih sorusu açmadan "kira" görevini yarın 09:00, #ev etiketli oluşturuyor. Bir çipin ✕'ine dokun → sözcükleri başlığa dönüyor. **iPhone**: boş çubuktaki ?'e dokun → yardım sayfası cam alt çubuğun ÜSTÜNDE açılıyor, açık ve koyu temada okunuyor. Masaüstünde (Windows/Linux/web) Enter zinciri bozulmuyor: yaz → Enter → yaz → Enter.

## Ne zaman ve Süre (2026-10-16)

- OPH-372 / ADR-0053 — **iPhone ve Mac**, Apple Takvim aynası açık: bugün 14:00'te bitişi olan göreve Süre 90 dk → Apple Takvim'de etkinlik 14:00–15:30; süreyi temizle → 14:00–14:30; Ne zaman'ı yarın yap → etkinlik YERİNDEN OYNAMIYOR. **Google Takvim** bağlı canlı sunucuda: tarihli göreve Süre 45 dk → Google etkinliği 45 dk; etkinliği Google'da sürükle → görevin Ne zaman'ı ve Süre'si değişmiyor, detayda "Takvimde taşındı" görünüyor. **iOS ve Android widget'ı**: Ne zaman = dün, bitiş 3 gün sonra olan görev Bugün altında, saat yerine bitiş günüyle ("20 Eki"), Bugün sayısı onu sayıyor. **Claude/ChatGPT MCP bağlayıcısı**: `create_task` (startAt + estimatedMinutes) → `list_tasks today` görevi listeliyor, iki alan dönüyor. Açık ve koyu temada, 390 px telefonda Ne zaman/Süre satırlarında taşma yok.

## Masaüstü indirmeleri (2026-10-16)

- OPH-370 / ADR-0051 — sonraki etiketten sonra. **Windows 10/11** (tercihen Visual Studio/VC++ yüklü olmayan bir PC): landing'in "Windows için indir (.zip)" kartından indir, zip'i aç → `alliswell.exe` → SmartScreen "Windows bilgisayarınızı korudu" → Daha fazla bilgi › Yine de çalıştır; "MSVCP140.dll bulunamadı" hatası yok. Pencere başlığı "AllisWell", görev çubuğunda AllisWell simgesi. Giriş ekranında Google/Apple düğmesi ve "veya" çizgisi yok; e-postayla giriş. 2 dakika sonrasına hatırlatıcılı görev → Windows bildirimi geliyor; hatırlatıcıdan önce tamamlanan görevde bildirim yok. `alliswell.exe` › Özellikler › Ayrıntılar: ürün sürümü etiketin sürümü, ürün adı AllisWell. **Ubuntu 24.04** (ya da Fedora) masaüstü: `tar xzf alliswell-linux-x64.tar.gz && ./alliswell-*/alliswell` → başlık "AllisWell"; giriş yap, kapat, yeniden aç → oturum duruyor (GNOME Keyring); hatırlatıcı masaüstü bildirimi veriyor, uygulama açıkken alarm sesi çalıyor (GStreamer). İkisinde de açık ve koyu temada; giriş ekranında sunucu seçici kendi sunucuna bağlanıyor.

## Apple Takvim geri okuma (2026-10-16)

- OPH-369 / ADR-0050 — Swift Mac'te derlendi (2026-10-17). **iPhone** (iOS 17+, takvime tam erişim, Ayarlar › Takvim › Apple'da bir takvim seçili): (1) bugün 14:00'e görev → Apple Takvim'de 14:00–14:30. (2) Etkinliği 16:00'ya sürükle, sonunu 17:00'ye uzat, AllisWell'e dön → görev detayında "Takvimde taşındı" 16:00–17:00; Google bağlıysa senkrondan sonra Google'daki kopya da taşınıyor. (3) Etkinliğin adını değiştir → görevin adı değişmiyor. (4) Etkinliği haftalık tekrara çevir → görev değişmiyor. (5) Etkinliği sil → görev duruyor, görev adını düzenlesen de etkinlik geri gelmiyor. (6) Ayarlar'da başka takvim seç → etkinlik orada yeniden oluşuyor. (7) Görevin saatini AllisWell'de değiştir → etkinlik taşınıyor ve geri sekmiyor. (8) Etkinliği tüm gün yap → görev o günün 00:00–24:00 bloğu, etkinlik tüm gün kalıyor. **Mac**: 2, 5 ve 7'yi tekrarla — Calendar.app'te sürükle, sonra AllisWell penceresine tıkla; ayrıca AllisWell arkadayken Calendar.app'te bir etkinliği sil ve iPhone'dan o görevin saatini değiştir → Mac'te etkinlik geri gelmiyor, çift etkinlik oluşmuyor. Açık ve koyu temada. Hepsi geçerse STATE "Kullanıcıdan bekleyen" 13: "iki yönlü Apple" metnine dönüş sahibin kararı.

## Google/Apple girişinde ikinci faktör (2026-10-17)

- OPH-381 / ADR-0049 ek — deploy'dan sonra, 2FA (doğrulama uygulaması) açık bir hesapla. **iPhone**: Apple ile devam et → Apple sayfası bir kez açılıyor → "Doğrulama kodunu gir" istemi; yanlış kod → istem açık kalıyor, "Kod doğru değil"; doğru kod → Ana sayfa (Apple sayfası ikinci kez açılmıyor). Aynısı Google ile. **Android**: Google ile devam et → aynı akış; kurtarma kodu (ABCDE-12345 biçimi, küçük harfle de) bir kez çalışıyor, ikinci kez "Kod doğru değil". E-posta + parolayla girişte de aynı istem; İptal → giriş ekranı, hata yok. Klavye istemde açılıyor, iOS "kodu otomatik doldur" önerisi çıkıyor. 2FA'sız hesapta istem hiç görünmüyor. Açık ve koyu temada, 390 px telefonda istem taşmıyor.

## MCP onayında Google/Apple (2026-10-16)

- OPH-366 — STATE "Kullanıcıdan bekleyen" 8'deki konsol adımlarından sonra: Claude › Settings › Connectors › `https://api.alliswell.space/mcp` ekle → Connect → AllisWell sayfasında "Continue with Google" → uygulamada Google ile açılmış hesap → "Signed in as …" → Approve → Claude bağlı, araçlar listeleniyor. Aynısını "Continue with Apple" ile iPhone'da Apple ile açılmış hesapla (paylaşılan ve gizli e-posta). 2FA açık hesapta kod soruluyor; yanlış kodda "That code is not right". AllisWell hesabı olmayan Google hesabıyla "Sign up in the app first", hesap açılmıyor. Apple sayfasında İptal → onay sayfası "Sign-in was cancelled". 390 px telefonda düğmeler tam genişlik, parola alanında Enter Approve'u gönderiyor.

## Widget'ta takvim etkinlikleri (2026-10-15)

- Snapshot v5 — Google Takvim bağlı hesapta bugüne bir etkinlik ve tüm gün etkinliği koy. **iOS** (systemMedium/Large) ve **Android** widget'ında etkinlik satırı: daire yok, takvim ikonu var, saat "14:00–15:00" / "Tüm gün"; görevlerle saat sırasına göre karışık. Etkinlik satırına dokun → uygulama açılıyor, Ana sayfada o gün seçili (ay ızgarası o ayda). Android'de satırın sol ucuna dokunmak hiçbir şeyi tamamlamıyor. Ayarlar › Genel › Widget › Gizli widget açıkken etkinlik başlığı "Gizli görev". Bir proje listesine ayarlı widget'ta etkinlik yok. Açık ve koyu temada.

## Notu Markdown / Word olarak dışa aktarma (2026-10-15)

- ADR-0048 — iOS ve Android'de bir notun ⋮ menüsü → "Word (DOCX) olarak dışa aktar" ve "Markdown olarak dışa aktar" → paylaşım sayfası doğru dosya adıyla açılıyor (.docx / .md), Dosyalar'a kaydedilebiliyor. .docx Microsoft Word'de (masaüstü ya da mobil) onarım uyarısı vermeden açılıyor; başlıklar, listeler, onay kutuları, callout, tablo ve görseller PDF'teki gibi. Web'de üçü de doğrudan indiriliyor.

## Kabuk, gezinme, erişilebilirlik (2026-10-07)

- OPH-363 — telefonda (390 px) Ayarlar › Takım › Birimler'de sona kaydır → son birimin ⋮'si "+ Yeni birim"in üstünde, dokununca menü açılıyor (birim kadrosu, Webhook'lar, Herkese açık bağlantılar, Roller, Davetler'de aynı). TalkBack/VoiceOver ya da web'de ekran okuyucuyla Hızlı erişim düğmesine odaklan → odak çerçevesi yalnız 56 px'lik düğme. Çevrimdışı taslak gönderilince "İletildi — talebin aşağıda" liste o talebi gösterince kayboluyor; "Kapat" da kapatıyor. Açık ve koyu temada.
- OPH-362 — telefonda (390 px) Hızlı erişim balonu sağ altta, alt çubuğun satırında; kapsül balondan önce bitiyor, FAB balonun üstünde. Ayarlar › Takım: Üyeler'de son satırın ⋮'si, Birimler'de İSG'nin ⋮'si, Onaylar'da ikinci kartın "Onayla"sı, Takım ayarları'nda "Kaydet"in sağ ucu açılışta, kaydırmadan dokunulabiliyor; sayfanın altında balonun şeridi sayfanın kendi zemininde, dikiş yok. Balonu ekranın ortasına sürükle → sayfa yeniden tam boy; aşağı sürükle → yeniden yuvada. Klavye açılınca balon kayboluyor. Çevrimdışı taslak bağlantı gelince Taleplerim'de "İletildi — talebin aşağıda" oluyor, "Masaya ulaştı…" kalmıyor. Denetim günlüğünde davet iptali "bir daveti iptal etti"; SLA politikası düzenlemede öncelik başlıkları alanların üstünde (1440 px ve telefonda). Açık ve koyu temada.

- OPH-360 — Ayarlar › Herkese açık bağlantılar: 30 günlük bir linkte ⋮ → "Süreyi uzat…" → 2 gün → yeni bitiş eskisinden sonra; satırda birim ve oluşturma tarihi; iptal diyaloğunda "Vazgeç" / kırmızı "Bağlantıyı iptal et"; ekran okuyucu diyaloğu adıyla okuyor. Ayarlar › Firmalar: kişi ekle → davet bağlantısı bir kez; kişiyi kapat → firma portalındaki oturumu düşüyor. SLA panosu Aşıldı/Yaklaşıyor/Tutuldu ve "N değerlendirilen"; ihlal satırı talebi açıyor. Kuyruk ⋮ → "CSV indir" → Excel'de Türkçe karakterler doğru. Denetim günlüğü başlığı "Denetim günlüğü", satır talebi açıyor. Açık ve koyu temada.
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
