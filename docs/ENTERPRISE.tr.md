# AllisWell Enterprise

Zaten bildiğiniz AllisWell'in üzerine eklenen talep yönetimi (ITSM), yetki ve rol yönetimi
ve birim (departman) yapısı — bulutta kurumunuza özel bir adreste ya da kendi sunucunuzda,
kendi veritabanınızda çalışan, ve sahadaki Wi-Fi çalışmadığında da çalışmaya devam eden.

AllisWell'in kendisi bireysel kullanım için ücretsizdir ve öyle kalacak. **Enterprise**,
tek bir kişinin görevlerinden fazlasına ihtiyaç duyan kurumlar için ayrı, ticari lisanslı
bir sürümdür.

> **Ne yaptığı, ekran görüntüleriyle birlikte web sitesinde:**
> **[alliswell.space/enterprise/tr](https://alliswell.space/enterprise/tr)**
> · **[English](https://alliswell.space/enterprise)**

## Bu dosya neden kısaldı

Eskiden bütün anlatımı taşıyordu ve bayatladı: dört epic boyunca okuyuculara dizin
entegrasyonunun dahil olmadığını söyledi, oysa LDAP, SAML, OIDC ve SCIM'in hepsi inmişti.
Hiçbir yerde bunu söyleyen bir şey yoktu, çünkü bu dosyayı koruyan kapı onun VAR olduğunu
ve linklendiğini doğruluyor — bir kelimesinin hâlâ doğru olduğunu değil.

Anlatım, metni referans verdiği ekran görüntülerinin yanında denetlenen bir modülde duran,
bileşenlerden kurulmuş bir sayfaya taşındı; böylece kaymanın yakalanacağı bir yer oldu
(ADR-0036). Burada kalan, satış sayfasına değil depoya ait olan kısım: lisans — ücretsiz
sürümü değerlendiren birinin [LICENSE](../LICENSE) ve
[ADR-0024](adr/0024-license-polyform-noncommercial.md) ile yan yana okuduğu metin. Bu daha
küçük bir kitle değil, başka bir kitle.

## Lisans

İşin içinde iki lisans var, ve birini almak diğerini değiştirmiyor.

**Ücretsiz sürüm**, [PolyForm Noncommercial 1.0.0](../LICENSE) ile kaynağı açık
(source-available). Buradaki "ücretsiz" bir **kişi** için ücretsiz demek: kendi hayatınız,
kendi makineniz, hobi projeleri, öğrenmek, kendi kurulumunuzu kendiniz barındırmak.
Vakıflar, okullar, üniversiteler, kamu araştırma kurumları ve devlet kurumları için de
ücretsiz. **Ücretsiz olmadığı yer**: bir şirketin onu kendi ekibi için çalıştırması — kaç
kişi olursa olsun — ya da onu satması veya başkalarına hizmet olarak sunması. Bunlar ticari
lisans gerektirir.

Buraya ücretsiz sürümden geldiyseniz iki kez okunacak cümle şu: **size ücretsiz,
işvereninize değil.** Kimin kapsandığını gösteren tam tablo ve lisansın gerekçesi — AGPL
neden seçilmedi dahil — README'nin
[Licence and commercial use](../README.md#-licence--commercial-use) bölümünde ve
[ADR-0024](adr/0024-license-polyform-noncommercial.md)'te.

Bir lisans bölümüne ait olan, dipnota değil: proje v1.0.0'a kadar AGPL-3.0'dı ve
**v0.9.0 ve öncesi sürümler, onları almış olan herkes için AGPL-3.0 kalır.** Verilmiş bir
lisans geri alınamaz. Bugünkü şartlar ileriye işler, geriye değil.

Etiket konusunda açık olmak gerekirse: PolyForm Noncommercial **kaynağı açık**tır, OSI
anlamında "açık kaynak" değil — ticari kullanımı ayırt ediyor, ki Açık Kaynak Tanımı bunu
yasaklar. "Kaynağı açık" diyoruz çünkü öbür kelime doğru olmazdı.

**Enterprise** tescilli ve ayrıdır. Yalnızca BubiApps ile imzalanmış yazılı bir
**AllisWell Enterprise Sözleşmesi** kapsamında kullanılır; ona erişmek tek başına hiçbir
hak vermez. Ücretsiz sürümün şartlarını iki yönde de değiştirmez — public depo PolyForm
Noncommercial altında kalır, ve elinizde olan bir kopya, hangi lisansla aldıysanız onunla
sizindir.

Ticari lisans, ayrıca ücretsiz katmanda olmayan self-hosting desteğiyle gelir.

### Paketler

Üründe bir paket kavramı var ve taze bir kurulum üçü tanımlı olarak geliyor: **Starter**,
**Business** ve **Enterprise**. Bunlar birer **şekil**, fiyat listesi değil — kullanıcı
sayısı, birim sayısı, bir kurumun talep formunu ne kadar kullanabileceği, tarihçenin ne kadar
saklanacağı. Paketler **bulut** hizmeti içindir: alliswell.space üzerinde kurulumu işleten
operatör bunları düzenler, yeniden adlandırır ya da kendi paketini ekler; bir kurum bir pakete
konur ve ürün o paketin taşıdığı limitleri raporlar ve uygular. Kendi sunucusuna kurulan bir
kurum bu katmanı hiç görmez — sınırlar kurulumda, sözleşmeye göre tanımlanır.

Yani bu sayfa "paket" derken o mekanizmayı kastediyor — altında fiyat yazan üç kutuyu
değil. Kurumunuzun neye hak kazandığı sözleşmenizde yazar.

### Ne kadar

Bu sayfada fiyat listesi yok, ve bu bir şey gizlendiği için değil. Enterprise bir indirme
ve ödeme adımı değil. Bulutta kurumunuza özel bir adreste üç hazır paketten biriyle
başlarsınız; kendi sunucunuza kurulumu ise ekibimiz yapar ve sınırlar, modüller ve
sözleşmenin şekli kaç kişi ve kaç birim olduğuna göre belirlenir. O konuşma kısa sürüyor —
ve gerçek cevabı "kurumunuza göre değişir" olan bir soruya dürüst yanıt bu.

> **İlgileniyor musunuz?** **[info@bubiapps.com](mailto:info@bubiapps.com)** adresine kaç
> kişi ve kaç birim olduğunuzu yazın — başlamak için bu yeterli. İhtiyacınız Enterprise
> değil de ücretsiz sürüm için bir ticari lisanssa, aynı adres onu da karşılıyor.
