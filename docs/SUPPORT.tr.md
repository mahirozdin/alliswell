# Destek

**Diller:** [English](SUPPORT.md) · **Türkçe**

Bir şey çalışmıyor, bir sorunuz veya bir talebiniz mi var? Bize ulaşmanın tüm
yolları ve her birinden ne bekleyebileceğiniz aşağıda.

## Bize ulaşın

| | |
| --- | --- |
| **E-posta** | **info@bubiapps.com** — en hızlısı; mağaza sayfalarında da bu adres yazıyor |
| **Hata bildirimi ve özellik isteği** | [GitHub Issues](https://github.com/mahirozdin/alliswell/issues) — herkese açık, aranabilir ve işin gerçekten takip edildiği yer |
| **Güvenlik açığı** | [SECURITY.md](../SECURITY.md) — bunlar için lütfen **herkese açık issue açmayın** |
| **Ticari lisans** | **info@bubiapps.com** — bkz. [Lisans ve ticari kullanım](../README.md#-licence--commercial-use) |
| **Telefon** | +90 505 493 1041 |

**Yanıt süresi:** e-postalara **iki iş günü** içinde dönmeyi hedefliyoruz. Hesap
ve veri silme talepleri, kanunun gerektirdiği şekilde **30 gün** içinde
sonuçlandırılır.

**İşletmeci:** BUBIAPSS BILGI TEKNOLOJILERI ARGE LIMITED SIRKETI (ticari adı:
BubiApps) · Mevlana Mah. Karasu Cad. No: 14, İç Kapı No: 16 · Talas / Kayseri ·
Türkiye

## Hata bildirirken nelere ihtiyacımız var

Bunlardan ne kadarını verebilirseniz, o kadar hızlı çözülür:

1. **Ne bekliyordunuz, bunun yerine ne oldu.**
2. **Nerede** — Ana Sayfa, Pano, görev detayı, widget vb.
3. **Hangi cihaz ve sürüm** — Ayarlar ▸ Hakkında uygulama sürümünü gösterir;
   platform ve işletim sistemi sürümü de yardımcı olur.
4. **Her seferinde mi oluyor**, yoksa bir kez mi oldu.
5. Konu **çalmayan bir hatırlatıcıysa**, lütfen **Ayarlar ▸ Hatırlatıcılar ▸
   Alarm günlüğü**'nü açıp içeriğini de gönderin. O günlük tam olarak bu sorunun
   cevaplanabilmesi için var.

## Sık sorulanlar

### Hatırlatıcı çalmadı

Sırasıyla üç şeye bakın:

1. **Bildirimlere izin verilmiş mi** — verilmediğinde uygulama Ana Sayfa'da
   kırmızı bir şerit ve "Düzelt" düğmesi gösterir.
2. **Tam zamanlı alarmlara izin verilmiş mi** (Android) — Ayarlar ▸ Uygulamalar ▸
   AllisWell ▸ Alarmlar ve hatırlatıcılar. Bazı üretici sürümlerinde Android bu
   izni sessizce geri alır.
3. **Alarm günlüğü** — Ayarlar ▸ Hatırlatıcılar ▸ Alarm günlüğü, planlanan ve
   teslim edilen her alarmı kaydeder. Günlük "teslim edildi" diyorsa ama siz
   duymadıysanız alarmı işletim sistemi bastırmıştır; kaydı bize gönderin,
   genelde nedenini söyleyebiliriz.

Samsung, Xiaomi, Huawei ve OnePlus cihazlarda en sık neden **pil
optimizasyonudur**. AllisWell'i pil optimizasyonundan çıkarmak sorunu çözer.

### Şifremi unuttum

Giriş e-posta + şifre ile yapılır. Giremiyorsanız, hesabın e-posta adresinden
**info@bubiapps.com** adresine yazın.

### Hesabımı ve içindeki her şeyi nasıl silerim?

Uygulamada: **Ayarlar ▸ Hesap ▸ Hesabı sil**. Silme, yanlışlıkla dokunmayı geri
alabilmeniz için kısa bir bekleme süresiyle planlanır; sonra her şey kaldırılır —
görevler, notlar, dosyalar, takvim bağlantıları, hepsi. Dilerseniz
**info@bubiapps.com** adresine yazın, sizin için yapalım.

Ayrıntı: [Gizlilik Politikası — Hesabınızı silmek](PRIVACY.tr.md).

### Verimi başka bir yere taşıyabilir miyim?

Evet. Notlar, not menüsünden Markdown olarak dışa aktarılır; kendi sunucunuzda
çalıştırıyorsanız veritabanı zaten sizin — şema belgeli, hiçbir şey gizlenmiyor.

### AllisWell verimi yapay zekâ eğitmek için kullanıyor mu?

Hayır. Yapay zekâ özellikleri **siz açana kadar kapalıdır**, bir AllisWell AI
hesabı yoktur ve açtığınızda **kendi** sağlayıcı anahtarınızı ya da kendi
Claude/ChatGPT aboneliğinizi kullanırsınız. Onam ekranı, bağlanmadan önce her
sağlayıcının gerçek veri politikasını yazar — ücretsiz katmanda verinizle eğitim
yapanlar dahil. Bkz. [docs/AI.md](AI.md).

### Ücretsiz mi?

Kişisel kullanım ve kendi sunucunuzda çalıştırmak için evet — kalıcı olarak,
katman yok, reklam yok. Ticari kullanım lisans gerektirir:
[Lisans ve ticari kullanım](../README.md#-licence--commercial-use).

### Kendi sunucumda çalıştırmak istiyorum

İhtiyacınız olan her şey [docs/SELF-HOSTING.md](SELF-HOSTING.md) içinde: tek
`docker compose up`, TLS, yedekleme, güncelleme ve nesne depolama. Kendi
sunucunuzda çalıştırmak kişisel kullanım için ücretsizdir; desteği GitHub Issues
üzerinden elimizden geldiğince veriyoruz.

## Bilinen sınırlar

Bunları keşfetmenizdense burada okumanızı tercih ederiz:

- **Henüz paylaşım/işbirliği yok.** Çalışma alanları veri modelinde var; davet
  arayüzü yok. AllisWell bugün tek kullanıcılıdır.
- **Konum bazlı hatırlatıcı yok.** Apple Reminders'ta var, bizde yok.
- **Apple Takvim tek yönlü** — seçtiğiniz görevler seçtiğiniz takvime yazılır,
  ama Apple Takvim'de yaptığınız değişiklikler geri gelmez. Google Takvim çift
  yönlüdür.
- **Alarm teslimi işletim sistemine bağlıdır.** Platformun izin verdiği her şeyi
  yapıyoruz (iOS 26 AlarmKit, Android alarm kanalı) ve olan biteni günlüğe
  yazıyoruz; yine de agresif bir pil yöneticisi bildirimi geciktirebilir.

Bunların güncel durumu [ROADMAP.md](../ROADMAP.md) içinde takip edilir.
