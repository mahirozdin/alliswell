<!--
  YAYINDAN ÖNCE YAPILMASI GEREKENLER:
  1. info@bubiapps.com kutusu HENÜZ YOK. Ya bu adresi açın ya da bu dosyadaki
     ve PRIVACY.md'deki tüm geçtiği yerleri yeni adresle değiştirin.
  2. Geliştiriciler için: metinde geçen 3 günlük bekleme süresi varsayılan değerdir
     (ACCOUNT_DELETION_GRACE_DAYS, apps/api/src/config.js). Yayındaki kurulumda bu
     değer değiştirilirse her iki politika dosyası da güncellenmelidir.
-->

# Gizlilik Politikası

**Diller:** **Türkçe** · [English](PRIVACY.md)

**Son güncelleme: 31.07.2026**

Bu metin, AllisWell'in hangi verileri neden işlediğini ve bu konuda neler
yapabileceğinizi anlatır. AllisWell uygulamaları ile <https://alliswell.space>
adresindeki hizmet (API: `https://api.alliswell.space`) için geçerlidir.

## Veri sorumlusu

Hizmetin veri sorumlusu **BUBIAPSS BILGI TEKNOLOJILERI ARGE LIMITED SIRKETI**'dir (ticari adı: **BubiApps**).

| | |
| --- | --- |
| **Ünvan** | BUBIAPSS BILGI TEKNOLOJILERI ARGE LIMITED SIRKETI |
| **Adres** | Mevlana Mah. Karasu Cad. No: 14, İç Kapı No: 16 · Talas / Kayseri · Türkiye |
| **E-posta** | **info@bubiapps.com** |
| **Telefon** | +90 505 493 1041 |

Her türlü gizlilik sorusu ve KVKK başvurusu için: **info@bubiapps.com**.
Başvurulara en geç **30 gün** içinde yanıt veriyoruz (KVKK m.13).

## Hangi verileri işliyoruz

**Hesap bilgileriniz**

- E-posta adresiniz
- Parolanız — yalnızca argon2id ile özetlenmiş (hash) hâlde saklanır. Parolanızın
  açık hâlini ne saklarız ne de görebiliriz.
- Görünen adınız (isteğe bağlı)
- Saat diliminiz ve dil tercihiniz — tarihlerin ve hatırlatıcıların size göre
  doğru çalışması için

**Oluşturduğunuz içerik**

Görevler, projeler, notlar, etiketler, klasörler, hatırlatıcılar ve yüklediğiniz
dosyalar. Bunlar size aittir. Size geri gösterebilmek ve cihazlarınız arasında
eşitleyebilmek için saklarız. İçeriğinizi okumaz, ticari amaçla analiz etmez,
herhangi bir yapay zekâ modelinin eğitiminde kullanmayız.

**Cihazlarınız**

Her kurulum için bir cihaz kimliği, platform bilgisi (iOS, Android, macOS,
Windows, Linux, web) ve isteğe bağlı bir bildirim jetonu tutarız. Bunun tek
amacı, hatırlatıcıların doğru cihazlara ulaşmasıdır.

**Teknik kayıtlar**

Sunucularımız, IP adresinizi de içeren istek kayıtları (log) tutar. Bu kayıtları
hizmeti ayakta tutmak, kötüye kullanımı ve güvenlik sorunlarını incelemek için
kullanırız. Ayrıca her oturum açma işleminin IP adresini, oturum kaydıyla
birlikte tutarız; böylece bir oturumun ne zaman açıldığı belli olur.

## İşleme amaçlarımız ve hukuki sebepler

| Amaç                                             | Hukuki sebep (KVKK, 6698 s.)                                              | Hukuki sebep (GDPR)           |
| ------------------------------------------------ | ------------------------------------------------------------------------- | ----------------------------- |
| Hesabınızı işletmek, içeriğinizi eşitlemek       | Sözleşmenin kurulması/ifasıyla doğrudan doğruya ilgili olması, m. 5/2-(c) | Sözleşmenin ifası, m. 6(1)(b) |
| Hizmeti güvende tutmak, kötüye kullanımı önlemek | Meşru menfaat, m. 5/2-(f)                                                 | Meşru menfaat, m. 6(1)(f)     |
| Google Takvim bağlantısı                         | **Açık rıza**                                                             | Açık rıza, m. 6(1)(a)         |
| Hukuki yükümlülüklerimizi yerine getirmek        | Hukuki yükümlülük, m. 5/2-(ç)                                             | Hukuki yükümlülük, m. 6(1)(c) |

Google Takvim için verdiğiniz açık rızayı, bağlantıyı kaldırarak istediğiniz an
geri alabilirsiniz. Bu, geri almadan önce hukuka uygun şekilde yaptığımız
işlemleri etkilemez.

## Yüklediğiniz dosyalar

Dosyalar, S3 uyumlu bir nesne deposu olan **Cloudflare R2** üzerinde tutulur.
Kova (bucket) herkese kapalıdır.

Dosyalarınızın içeriği API sunucusundan hiç geçmez. Yükleme veya indirme
yaparken sunucu, uygulamanıza kısa ömürlü bir imzalı bağlantı verir — tek dosya
ve tek işlem için, yaklaşık **15 dakika** geçerli — ve dosya doğrudan cihazınızla
depo arasında aktarılır. Barındırdığımız hizmette dosya başına sınır **10 MB**'tır.
(Kendi sunucusunda çalıştıranlar bu iki değeri değiştirebilir.)

## Hatırlatıcılar ve bildirimler

Hatırlatıcılar ve alarmlar **cihazınızda, yerel olarak** planlanır ve çalar. Görev
başlıklarınız ve içerikleriniz Apple'ın, Google'ın veya başka birinin bildirim
servisine gönderilmez. Yukarıda anlatılan cihaz kaydı yalnızca hangi cihazların
var olduğunu bilmemizi sağlar; bugün sunucularımızdan cihazlara herhangi bir
push bildirimi gönderilmemektedir.

## Google Takvim (isteğe bağlı)

Yalnızca siz bağlarsanız devreye girer:

- Google OAuth jetonlarınızı **AES-256-GCM ile şifreleyerek** saklarız. Jetonlar
  sunucudan hiç çıkmaz, uygulamaya geri gönderilmez.
- Görevleriniz, seçtiğiniz Google takvimine etkinlik olarak yansıtılır. Yani
  görevin **başlığı ve açıklaması** Google'a aktarılır.
- O takvimdeki etkinlikler geri okunur; böylece görevlerinizle yan yana
  görebilirsiniz.

Bağlantıyı kaldırdığınızda hepsi durur: jetonu iptal eder, sileriz ve Google
etkinliklerinizin bizdeki kopyalarını sileriz. Daha önce Google takviminize
yazılmış etkinlikler orada kalır; onları Google Takvim üzerinden silebilirsiniz.

Google hesabınızdaki verilerin Google tarafından işlenmesi, Google'ın kendi
gizlilik politikasına tabidir.

## Apple Takvim (isteğe bağlı)

Tamamen cihazınızda, Apple'ın EventKit altyapısı üzerinden çalışır. Apple
takvimlerinizle ilgili hiçbir bilgi sunucularımıza gönderilmez; bu verileri
göremeyiz.

## Yapay zekâ özellikleri (isteğe bağlı)

Yapay zekâ, **siz açana kadar kapalıdır** — sağlayıcı yoksa hiçbir AI yüzeyi
görünmez. Buradaki hiçbir şey, siz bir sağlayıcı anahtarı eklemeden ya da bir
paylaşım/ses eylemi başlatmadan gerçekleşmez.

- **Kendi anahtarını getir.** Bir sağlayıcı (Anthropic, OpenAI, Gemini,
  OpenRouter veya kendi Ollama'nız) bağladığınızda, API anahtarınız sunucuda
  **AES-256-GCM ile şifreli** saklanır; size yalnızca son 4 karakteri gösterilir
  ve anahtar ne uygulamaya geri döner ne de o sağlayıcı dışında bir yere gider.
- **Ne gönderilir, kime.** Bir AI eylemi çalıştırdığınızda — sohbet, "bunu göreve
  çevir", özetle — ilgili metin (yazdığınız mesaj, asistanın bağlam olarak
  ihtiyaç duyduğu görev başlıkları ve notlar, paylaşılan metin veya bir ses
  **dökümü**) **seçtiğiniz sağlayıcıya**, yalnızca o anda gönderilir. O metnin
  işlenmesi **o sağlayıcının** gizlilik politikasına tabidir. Yerel bir
  **Ollama**'ya yönlendirirseniz metin kendi makinenizden hiç çıkmaz.
- **Ses cihazda kalır.** Konuşma **cihazınızda** metne çevrilir; yalnızca ortaya
  çıkan metin — ses kaydı asla — ve yalnızca siz gönderince iletilir.
- **Onay hep sizde.** Asistan yalnızca *önerebilir*; her görev veya not sizin
  dokunuşunuzla oluşur, hiçbir zaman kendiliğinden değil.
- **Claude veya ChatGPT'ye bağlama (MCP).** AllisWell'i bir Claude ya da ChatGPT
  aboneliğine bağlarsanız, o asistan görevlerinizi AllisWell'in sunucusu
  üzerinden, iptal edebileceğiniz yetkili bir bağlantıyla okur; okuyabilir ve
  oluşturabilir ama **asla silemez**. Okuduğuyla ne yaptığı, o sağlayıcının kendi
  politikasına tabidir.

Yapay zekâyı kapatmak veya bir bağlantıyı kaldırmak, saklanan anahtarı siler ve
yukarıdakilerin tümünü durdurur. Seçmediğiniz bir sağlayıcıya verinizi asla
göndermeyiz. Kendi sunucunuzda çalıştırıyorsanız, sağlayıcı anahtarlarını
işletmeci sağlamış olabilir — neyi yapılandırdığını işletmecinize sorun.

## Verilerinizi kimlerle paylaşıyoruz

Hizmeti çalıştırmak için gereken altyapı dışında kimseyle. Açıkça belirtelim:

- **Hiçbir üçüncü taraf analitik, reklam veya takip (tracking) SDK'sı
  kullanmıyoruz.** Uygulamada da API'de de Firebase, Crashlytics, Sentry, reklam
  ağı, atıf (attribution) veya parmak izi çıkarma aracı yok.
- **Verilerinizi satmıyor, kiralamıyoruz**; reklam amacıyla kimseyle paylaşmıyoruz.
- Hakkınızda profil çıkarmıyoruz ve sizin için hukuki sonuç doğuran ya da benzer
  ölçüde etkili otomatik kararlar almıyoruz.

Çalıştığımız veri işleyenler: sunucu ve veritabanı barındırma hizmetimiz,
yüklediğiniz dosyalar için Cloudflare R2 ve — yalnızca bağlarsanız — takvim
eşitlemesi için Google ile **seçtiğiniz yapay zekâ sağlayıcısı** (Anthropic,
OpenAI, Google Gemini, OpenRouter veya yerel kalan kendi Ollama'nız). Cloudflare,
Google ve bulut yapay zekâ sağlayıcıları uluslararası olduğundan, bu verilerin
**yurt dışında** saklanması veya işlenmesi mümkündür. Bu aktarım, sözleşmenin
ifası için gerekli olduğu ölçüde; Google Takvim ve yapay zekâ özellikleri
bakımından ise açık rızanıza dayanılarak yapılır.

## Verileri ne kadar süre saklıyoruz

- **İçeriğiniz** — siz silene veya hesabınızı kapatana kadar.
- **Oturumlar** — yenileme jetonları verildikten 30 gün sonra geçerliliğini
  yitirir; onlarla birlikte saklanan oturum açma IP'si de o anda gider.
- **İstek kayıtları** — hizmeti işletmek ve güvenliğini sağlamak için gerekli
  olduğu süre boyunca.
- **Google jetonları** — bağlantıyı kaldırdığınızda silinir.

## Hesabınızı silmek

Hesabınızı uygulama içinden kendiniz silebilirsiniz: **Ayarlar → hesabı sil**.

Süreç tam olarak şöyle işler:

1. Silme işlemi **3 günlük bekleme süresiyle** planlanır. O ana kadar hiçbir şey
   silinmez.
2. Fikrinizi değiştirirseniz bu 3 gün içinde giriş yapıp silme talebini iptal
   edin; her şey kaldığı yerden devam eder. Tekrar silme talebi göndermek ilk
   tarihi ileri atmaz.
3. 3 gün dolduğunda hesabınız ve içeriği **kalıcı ve geri döndürülemez biçimde**
   silinir: görevler, projeler, notlar, etiketler, klasörler, hatırlatıcılar ve
   nesne deposundaki dosyalarınız. Geri yükleyebileceğimiz bir yedek kalmaz.

Uygulama içindeki seçeneğe ulaşamıyorsanız **info@bubiapps.com** adresine
yazın; silme işlemini sizin adınıza yürütelim.

Bilmenizde fayda olan bir sınır: sahibi olduğunuz çalışma alanları silinir. Bir
dosyayı başkasının çalışma alanına yüklediyseniz, o dosya ilgili çalışma alanına
bağlıdır ve onunla birlikte kalır.

## Haklarınız

**KVKK m. 11 uyarınca** şu haklara sahipsiniz:

- kişisel verinizin işlenip işlenmediğini öğrenme;
- işlenmişse buna ilişkin bilgi talep etme;
- işlenme amacını ve amacına uygun kullanılıp kullanılmadığını öğrenme;
- yurt içinde veya yurt dışında verilerin aktarıldığı üçüncü kişileri bilme;
- eksik veya yanlış işlenmişse düzeltilmesini isteme;
- KVKK m. 7'deki şartlar çerçevesinde silinmesini veya yok edilmesini isteme;
- düzeltme ve silme işlemlerinin, verilerin aktarıldığı üçüncü kişilere
  bildirilmesini isteme;
- münhasıran otomatik sistemlerle yapılan analiz sonucu aleyhinize bir sonuç
  doğmasına itiraz etme;
- verilerinizin hukuka aykırı işlenmesi nedeniyle zarara uğrarsanız zararın
  giderilmesini talep etme.

**GDPR kapsamındaysanız** ayrıca verilerinize erişme, düzeltilmesini, silinmesini
veya işlenmesinin kısıtlanmasını isteme, meşru menfaate dayanan işlemeye itiraz
etme ve verilerinizi taşınabilir bir biçimde alma haklarınız vardır.

Başvurularınızı **info@bubiapps.com** adresine iletebilirsiniz. İşlem
yapmadan önce, hesabın e-posta adresinin sizde olduğunu doğrulamanızı
isteyebiliriz. Türkiye'de bulunanlar, ayrıca **Kişisel Verileri Koruma Kurumu**'na
şikâyette bulunabilir; GDPR kapsamındakiler ise kendi ülkelerindeki denetim
makamına başvurabilir.

## Güvenlik

Parolalar argon2id ile özetlenir. Oturumlarda kısa ömürlü jetonlar ve dönüşümlü
yenileme jetonları kullanılır; yenileme jetonları da özetlenmiş hâlde saklanır ve
biri yeniden kullanılırsa tüm oturum ailesi iptal edilir. Google OAuth jetonları
AES-256-GCM ile şifrelenir. Dosyalar, yalnızca süresi dolan tek dosyalık imzalı
bağlantılarla erişilebilen kapalı bir kovada durur. Tüm trafik HTTPS üzerinden
akar.

Hiçbir sistem yüzde yüz güvenli değildir; aksini iddia etmiyoruz. Bir güvenlik
açığı bulursanız bildirim yolu için [SECURITY.md](../SECURITY.md) dosyasına
bakın.

## Çocuklar

AllisWell 13 yaşın altındaki çocuklara yönelik bir hizmet değildir ve bu yaş
grubundan bilerek kişisel veri toplamayız. 13 yaşın altında birinin hesap
açtığını düşünüyorsanız **info@bubiapps.com** adresine yazın; hesabı
silelim.

## Kendi sunucunuzda çalıştırma

AllisWell'in kaynak kodu **PolyForm Noncommercial 1.0.0** lisansıyla herkese açıktır; dileyen kendi
sunucusunda çalıştırabilir. **Bu politika yalnızca BUBIAPSS BILGI TEKNOLOJILERI ARGE LIMITED SIRKETI
tarafından alliswell.space üzerinde işletilen hizmeti kapsar.** Başka birinin
kurduğu bir örneği kullanıyorsanız, veri sorumlusu o işletmecidir: bizim
kurallarımız değil onunkiler geçerlidir ve biz o verilere erişemeyiz.

## Bu politikadaki değişiklikler

Politikayı güncellersek "Son güncelleme" tarihini değiştirir, yeni sürümü
uygulamada ve bu depoda yayımlarız. Sizi önemli ölçüde etkileyen değişiklikleri,
yürürlüğe girmeden önce uygulama içinde duyururuz. Her değişikliğin geçmişi,
projenin Git kayıtlarında herkese açıktır.

## İletişim

**BUBIAPSS BILGI TEKNOLOJILERI ARGE LIMITED SIRKETI** — **info@bubiapps.com**
