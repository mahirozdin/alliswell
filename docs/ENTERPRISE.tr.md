# AllisWell Enterprise

Bildiğiniz AllisWell'in üzerine eklenen bir servis masası, bir izin sistemi ve bir
organizasyon şeması — kendi sunucunuzda, kendi veritabanınızda çalışan, ve sahadaki Wi-Fi
çekmediğinde de çalışmaya devam eden.

AllisWell'in kendisi bireysel kullanım için ücretsiz ve öyle kalacak. **Enterprise**, tek
bir kişinin görev listesinden fazlasına ihtiyacı olan kurumlar için ayrı ve ticari
lisanslı bir sürüm: her birimin bir diğerine iş açtığı, dışarıdaki firmaların da talep
girdiği, ve bunların ne kadar sürdüğünün birine sorulduğu şirketler için.

## Kimin için

Birkaç bin kişilik bir fabrika düşünün. Muhasebe, İK, bakım, BT, kalite, lojistik —
her biri kendi işi, kendi gelen kutusu ve "acil"in kendine göre tanımı olan bir birim.
Hem birbirlerine hem de birlikte çalıştıkları firmalara hizmet veriyorlar. Bugün bu
trafik telefon konuşmaları, ortak bir e-posta kutusu ve birinin Excel dosyası arasında
dağılmış durumda; ve *şu anda bakımda kaç açık talep var* sorusunun cevabı, bakıma
sormadan bilinmiyor.

Enterprise tam olarak bu şekil için tasarlandı: birimlerin sınırlara ihtiyaç duyacağı
kadar büyük, ama o sınırlar için üç ayrı sistem işletmek istemeyecek kadar da makul bir
kurum. Kurumun kendisi tarafından işletilmek üzere tasarlandı — bir kez kurulur, şirketin
kontrol ettiği donanımda çalışır, ve şirket öyle karar vermedikçe hiçbir talep binadan
dışarı çıkmaz.

## Neler ekliyor

### Team'ler ve subdomain

Her team'in kendi adresi olur. `acme.alanadiniz` üzerinden giren biri yalnızca acme'nin
işini görür — ve bu yalıtım arayüzde saklanmış değil, sunucuda uygulanır: başka bir
team'in verisine gelen istek düz bir 404 alır, ve o cevap o team'in var olduğunu bile
söylemez.

Bir team'in subdomain'inde kayıt **yalnızca davetle** olur. Davetler bir link ve bir kod
taşır, süresi dolar, ve kullanılmadan önce iptal edilebilir. Akışın tamamı, hiç e-posta
sunucusu tanımlanmamış bir kurulumda da tamamlanır — bunu ilk kez bir fabrika ağındaki
makineye kurarken önemsersiniz.

### İzinler

Erişim, birkaç sabit rolle değil, adı olan izinlerle tarif edilir. Roller bu izinlerden
kurulur; yani "bakım şefi kendi biriminde atama değiştirebilir ama talebi kapatamaz"
cümlesi bir yöneticinin kurabileceği bir şeydir, bizden isteyeceği bir özellik değil.
Her izin belgelenmiştir, ve belge ile kod birbirine karşı denetlenir — yalnız metinde
ya da yalnız kaynakta var olan bir izin derlemeyi kırar.

### Birimler

Birim; bir departman, bir atölye, bir saha — kurumun gerçekte hangi şekli varsa odur.
Birimler kendi içeriğinin ve kendi gelen kutusunun sahibidir. Birimler arası paylaşım
açıktır: bir birim diğerine belirli bir şeye erişim verir, karşı taraf tam olarak
verilen hakları alır, ve bu yetki sonradan geri alındığında erişim karşı tarafta
gerçekten kaybolur.

### Servis masası

Bir servis kataloğu, her birimin ne sunduğunu ve o hizmete gelen talebin nereye
düşeceğini tarif eder. Talep, o birimin gelen kutusunda bir ticket olur. Ticket ile task
ayrı şeyler kalır — ticket birine verilmiş bir sözdür, task bir listedeki iştir — ve bir
ticket, aradaki bağı koparmadan atanmış task işine dönüştürülebilir.

**Ve çevrimdışı çalışır.** Birimin gelen kutusundaki ticket, ağ geri gelmeden önce
cihazda okunabilir ve düzenlenebilir durumdadır. Sahada tek çubuk çeken, ofiste fiber
olan bir binada bu küçük bir ayrıntı değil: telefonun hiç susmamasının sebebi, yalnızca
masa başında çalışan servis masasıdır.

### SLA ve servis sağlığı

Yanıt ve çözüm hedefleri **duvar saatiyle değil, mesai takvimiyle** işler — çalışma
saatleri, tatiller, team'in saat dilimi ve vardiyalar. Çünkü fabrika 18:00'de durmaz, ve
üç vardiyalı bir güne göre ölçülen hedef, dokuz-altı mesaisine göre ölçülenden başka bir
sayıdır. Yaz saati geçişleri yaklaşık olarak değil, doğru şekilde ele alınır.

Servisler bir sağlık adresinden izlenebilir. Biri düştüğünde bir olay açılır; bir dakika
sonra hâlâ düşükse ikincisi açılmaz.

### Public talep portalı

Size bir şey sormak zorunda olan herkesin hesabı yoktur, ve bir tedarikçiye kullanıcı
hesabı vermek çoğu zaman yanlış cevaptır. Bir team, bir birime yönlenen talep formunu
public bir adreste yayımlayabilir — son kullanma tarihi, iptal düğmesi ve ne kadar
kullanılabileceğine dair bir üst sınırla birlikte. Talebi giren kişi, talebini takip
edebileceği bir link alır.

Kimlik doğrulaması olmayan bu yüzey tesadüfen değil, bilerek tasarlandı: üründe
kimliksiz açık olan tek kapı odur ve öyle muamele görür.

### Toplantı notunun işe dönüşmesi

Bir toplantı kaydını yükleyin; kimin ne söylediğini ayıran ve alınan kararları öne
çıkaran bir not alın. Bir karar, tek adımda ticket'a dönüştürülebilir — "toplantı
tutanağı"nın normalde hiç gerçekleşmeyen yarısı budur.

Deşifre, **sizin seçtiğiniz** sağlayıcıda ve **team'inizin kendi anahtarıyla** çalışır;
anahtarı kendi yöneticiniz girer. Kullanım ölçülür, böylece uzun bir kayıt sessizce büyük
bir faturaya dönüşmez. Sağlayıcının neyi ne kadar sakladığı, kurumunuzun o sağlayıcıyla
yaptığı sözleşmenin konusudur — ve ürünün bunu ayarladığınız ekranı, kontrol etmediğimiz
bir şeyi vaat etmek yerine bunu açıkça yazar.

### "Bunu kim değiştirdi" sorusunun cevabı

Her değişiklik, değişikliğin kendisiyle **aynı transaction içinde** bir tarihçe kaydı
yazar; yani işin olduğu ama kaydının olmadığı bir hâl yoktur. Kayıtlar kendi tarihçesini
taşır ve uygulamadan okunur.

## Neler aynı kalıyor

Ücretsiz sürümün yaptığı her şeyi Enterprise da yapar, aynı kod tabanında:

- **Tek uygulama, altı platform** — iOS, Android, Web, macOS, Windows, Linux.
- **Önce çevrimdışı** — yerel veritabanı uygulamanın doğruluk kaynağıdır; ağ sonradan yetişir.
- **Veriniz sizin veritabanınızda** — kendi donanımınızda ya da kendi bulut hesabınızda,
  self-hosted MySQL. Bkz. [SELF-HOSTING.md](SELF-HOSTING.md).
- **Çift yönlü takvim senkronu**, **sessiz modu ve Odak'ı delen alarmlar**, notlar,
  dosyalar, projeler ve arama — değişmeden.

## Neler yok

Dürüst liste; çünkü bunu demoda keşfeden biri, bunu şimdi yazan bir sayfadan daha kötü
bir sonuçtur:

- **Raporlama ve analitik panoları** bu sürümün parçası değil. Ürünün kendi ekranlarında
  sayılar ve kırılımlar var; bir rapor tasarlayıcısı yok.
- **Dizin entegrasyonu** — LDAP/Active Directory, tek oturum açma (SSO), otomatik
  kullanıcı sağlama — dahil değil. Hesaplar davetle açılır.
- **Paketler, bir team'e ne satıldığını tarif eder; her bir özelliğin etrafındaki sert
  bir sınırı değil.** İşletmeci bir team'i daha dar özellik listesi ve daha küçük
  limitlerle bir pakete alabilir, ve ürün bu limitleri raporlar ve uygular — ama
  Enterprise tek bir sürüm olarak satılır ve kurulur, ayrı ayrı satın alınabilen
  modüller olarak değil.

> **İlgileniyor musunuz?** Enterprise ticari lisanslıdır ve indirilerek değil, sizinle
> birlikte kurulur. **[info@bubiapps.com](mailto:info@bubiapps.com)** adresine kaç kişi ve
> kaç birim olduğunuzu yazın — başlamak için bu yeterli.

Ücretsiz sürümün lisansı [PolyForm Noncommercial](../LICENSE)'dır; Enterprise ayrı bir
sözleşmedir.
