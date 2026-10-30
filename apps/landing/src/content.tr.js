/**
 * Ana sayfa, Türkçe (ADR-0061). İngilizce ikizi `content.js`; ikisinin aynı
 * anahtar ağacını taşıdığını `npm run check:copy` garanti ediyor.
 *
 * Bu metin çeviri değil, Türkçe yazıldı: aynı iddialar, Türkçe okurun
 * kuracağı cümlelerle. Lisans "açık kaynak" değil; kaynak kodu herkese açık,
 * kişisel kullanım ve kendi sunucunuza kurmak ücretsiz, ticari kullanım
 * lisansa bağlı (ADR-0024). "İzleme yok" denmez (STORE-LISTING §5).
 *
 * Ekran görüntüleri ve döngüler dil taşımaz: uygulama İngilizce arayüzle
 * kaydedildi. Yalnız film iki dilde render edilir (`film-tr`).
 */

import {
  APP_STORE_URL,
  APP_URL,
  DOCS_URL,
  LINUX_DOWNLOAD_URL,
  MCP_GUIDE_URL,
  MCP_URL,
  PLAY_URL,
  REPO_URL,
  WINDOWS_DOWNLOAD_URL,
} from './site.js';

export default {
  lang: 'tr',

  seo: {
    title: 'AllisWell: kendi sunucunuzda çalışabilen görev, not ve alarm uygulaması',
    description:
      'Projelere bağlı görevler, markdown notlar, dosyalar ve sessiz modda bile çalan alarmlar; ' +
      'Google Takvim ile iki yönlü eşitleme, Claude ve ChatGPT için bağlayıcı. iPhone, Android, ' +
      'web ve masaüstünde tek uygulama. Kişisel kullanım ücretsiz; ister kendi sunucunuzda, ister bizde.',
    ogImage: '/shots/og/home-dusk-tr.jpg',
  },

  skip: 'Tura geç',

  ui: { pause: 'Animasyonu durdur', play: 'Animasyonu oynat' },

  nav: {
    home: '/tr',
    label: 'Ana menü',
    links: [
      { label: 'Tur', href: '/tr#features' },
      { label: 'Claude ve ChatGPT', href: '/tr#mcp' },
      { label: 'Kendi sunucunuz', href: '/tr#self-host' },
      { label: 'İndir', href: '/tr#get' },
      { label: 'Kurumsal', href: '/enterprise/tr' },
    ],
    cta: { label: 'Uygulamayı aç', href: APP_URL },
    menu: 'Menü',
    langLabel: 'Dil',
  },

  hero: {
    title: 'Görevler, notlar, alarmlar. Hepsi sizin.',
    sentence: 'Hatırlatıcılar sessiz modda bile çalar. İster kendi sunucunuzda, ister bizde.',
    primary: { label: 'Web uygulamasını aç', href: APP_URL },
    secondary: { label: 'Kendi sunucunuza kurun', href: '/tr#self-host' },
    also: {
      before: 'Şunlarda da var: ',
      links: [
        { label: 'iPhone', href: APP_STORE_URL },
        { label: 'Android', href: PLAY_URL },
        { label: 'Windows', href: WINDOWS_DOWNLOAD_URL },
        { label: 'Linux', href: LINUX_DOWNLOAD_URL },
      ],
      and: ' ve ',
      after: '.',
    },
    media: 'hero',
    alt: 'AllisWell’de bir gün: Ana sayfa listesi üç projeden görevlerle dolar, biri tamamlanır ve kira hatırlatıcısı alarm olarak çalar.',
    caption: 'Uygulamadan örnek verilerle kaydedildi.',
  },

  tour: {
    title: 'Her görev projesini, dosyalarını ve alarmını taşır.',
    lead: 'Beş özellik, gerçek uygulamanın üzerinde.',
    tabsLabel: 'Özellikler',
    panes: [
      {
        id: 'tasks',
        tab: 'Projelere bağlı görevler',
        body: 'Her görev projesini, etiketlerini, alt listesini ve dosyalarını taşır; Google Takvim ile iki yönlü eşitlenir.',
        media: 'tour-tasks',
        alt: 'Pano görünümü: görevler Açık sütunundan Devam ediyor sütununa geçer, her biri proje rozetini ve etiketlerini taşır.',
      },
      {
        id: 'notes',
        tab: 'Düzgün görünen markdown notlar',
        body: 'Tablolar, formüller, kod ve Mermaid diyagramları. Bilgisayarınızdaki .md dosyasını açın, aynı dosyaya kaydedin.',
        media: 'tour-notes',
        alt: 'Bir not, markdown kaynağı ile okuma görünümü arasında geçiş yapar; tablo ve yapılacaklar listesi düzgün görünür.',
      },
      {
        id: 'alarms',
        tab: 'Bildirim değil, alarm',
        body: 'Acil görevler sessiz ve odak modunda bile alarm sesiyle çalar, yarım saat boyunca siz yanıt verene kadar tekrarlar.',
        media: 'tour-alarms',
        alt: 'Android’de tam ekran alarm: Onayla düğmesi ve yeniden çalacağı saati yazan erteleme seçenekleri.',
      },
      {
        id: 'files',
        tab: 'İşin yanında duran dosyalar',
        body: 'Tahtanın fotoğrafı da sözleşmenin PDF’i de ait olduğu görevin ya da projenin içinde durur.',
        media: 'tour-files',
        alt: 'Bir projenin Dosyalar sekmesi fotoğrafları ve belgeleri klasörlerde listeler, bir resim tam boy açılır.',
      },
      {
        id: 'repeats',
        tab: 'Şaşmayan tekrarlar',
        body: 'Ayın 31’ini seçin, Şubat’ta görev 28’ine düşer. Kaydetmeden önce sonraki beş tarihi görürsünüz.',
        media: 'tour-repeats',
        alt: 'Her ayın 31’inde tekrarlanan bir görev; sonraki beş tarih listelenir ve Şubat 28’ine denk gelir.',
      },
    ],
  },

  film: {
    title: 'Bir dakikada bütün uygulama.',
    media: 'film-tr',
    alt: 'AllisWell’in bir dakikalık filmi: görevler, sessizde çalan alarm, takvim, notlar ve dosyalar, Claude ve kendi sunucunuz.',
    transcriptLabel: 'Filmin metnini okuyun',
    transcript: [
      'Gününüzü sakince kapatın.',
      'Görevler projelerinde, etiketleri, alt listeleri ve dosyalarıyla birlikte durur.',
      'Acil olanlar sessiz modda bile çalar, yarım saat boyunca yeniden sorar.',
      'Google Takvim iki yönlü eşitlenir. Ayın 31’i Şubat’ta 28’ine düşer.',
      'Notlar tabloları, formülleri ve diyagramları gösterir. Dosyalar işin yanında durur.',
      'Gününüzü Claude’a ya da ChatGPT’ye sorun. Her değişiklik sizin onayınızı bekler.',
      'Tek komutla kendi sunucunuzda çalıştırın ya da bizimkini kullanın.',
      'AllisWell. Web’de, iPhone’da, Android’de ve masaüstünde. alliswell.space',
    ],
  },

  assistant: {
    title: 'Gününüzü Claude’a sorun.',
    lead: 'AllisWell’i Claude ya da ChatGPT’ye bağlayıcı olarak ekleyin. Her değişiklik önce sizin onayınızı bekler.',
    steps: [
      'Claude ya da ChatGPT’de özel bir bağlayıcı ekleyin.',
      'Bu adresi yapıştırın.',
      'AllisWell hesabınızla giriş yapın.',
    ],
    urlLabel: 'Bağlayıcı adresi',
    url: MCP_URL,
    copy: 'Kopyala',
    copied: 'Kopyalandı',
    fact: 'Görevleriniz ve notlarınız için yirmi beş araç var, silme aracı yok.',
    link: { label: 'Kurulum rehberini okuyun', href: MCP_GUIDE_URL },
    media: 'mcp-tr',
    alt: 'Bir asistana verilen istek, onaydan sonra geciken üç görevi yarın sabaha taşır ve AllisWell listesi güncellenir.',
  },

  own: {
    title: 'Kendi sunucunuzda, tek komutla.',
    lead: 'İki Docker imajı ve kendi veritabanınız. Güncellemek için yeni imajı çekmeniz yeter.',
    commandLabel: 'Sunucunuzda',
    command: 'docker compose -f docker-compose.selfhost.yml up -d', // i18n-same
    points: [
      'Kişisel kullanım ve kendi kurulumunuz ücretsiz.',
      'MySQL 8.4 ya da MariaDB 10.11; dosyalar kendi S3 ya da R2 alanınızda.',
      'Kaynak kodu GitHub’da, PolyForm Noncommercial lisansıyla.',
    ],
    link: { label: 'Kurulum rehberini okuyun', href: `${DOCS_URL}/SELF-HOSTING.md` },
    media: 'selfhost',
    alt: 'Bir terminal AllisWell konteynerlerini başlatır, her servis sağlıklı olduğunu bildirir ve uygulama kendi alan adınızda açılır.',
  },

  compare: {
    title: 'Dürüst bir karşılaştırma.',
    lead: 'Başkalarının önde olduğu yerler: başka kişilerle paylaşım ve konuma göre hatırlatma.',
    caption: 'AllisWell ve insanların bıraktığı üç uygulama, 2026 ortası itibarıyla.',
    columns: ['AllisWell', 'Google Takvim', 'Apple Anımsatıcılar', 'Things 3'],
    rows: [
      ['Kendi sunucunuzda çalışır', 'yes', 'no', 'no', 'no'],
      ['Sessiz ve odak modunda alarm', 'yes', 'no', 'partial', 'no'],
      ['Onaylayana kadar yeniden uyarır', 'yes', 'no', 'no', 'no'],
      ['Google Takvim ile iki yönlü eşitleme', 'yes', 'native', 'no', 'no'],
      ['Ayın 31’i Şubat’a doğru taşınır', 'yes', 'no', 'yes', 'yes'],
      ['Claude ve ChatGPT için bağlayıcı', 'yes', 'no', 'no', 'no'],
    ],
    labels: { yes: 'Var', no: 'Yok', partial: 'Kısmen', native: 'Yerleşik' },
    link: { label: 'Karşılaştırmanın tamamını okuyun', href: `${DOCS_URL}/COMPARISON.md` },
  },

  get: {
    title: 'Web, telefon ve masaüstü. macOS kaynak koddan.',
    lead: 'Tek hesap, her cihazda aynı gün.',
    rows: [
      { id: 'web', name: 'Web', note: 'Kurulum gerekmez.', cta: 'Uygulamayı aç', href: APP_URL },
      { id: 'ios', name: 'iPhone ve iPad', note: 'App Store’da ücretsiz.', cta: 'App Store', href: APP_STORE_URL },
      { id: 'android', name: 'Android', note: 'Google Play’de ücretsiz.', cta: 'Google Play', href: PLAY_URL },
      { id: 'windows', name: 'Windows', note: 'Windows 10 ve 11 için .zip.', cta: 'İndir', href: WINDOWS_DOWNLOAD_URL },
      { id: 'linux', name: 'Linux', note: '64 bit masaüstleri için .tar.gz.', cta: 'İndir', href: LINUX_DOWNLOAD_URL },
      { id: 'macos', name: 'macOS', note: 'Şimdilik kaynak koddan derlenir.', cta: 'Kaynak kod', href: REPO_URL },
    ],
    media: 'get-phone',
    alt: 'iPhone’da AllisWell: ay takviminin altında bugünün görevleri.',
    caption: 'iPhone’da Ana sayfa',
    captionNote: 'Web’dekiyle aynı gün, cebinizde.',
  },

  faq: {
    title: 'Geçmeden önce sorulanlar.',
    items: [
      {
        q: 'Açık kaynak mı?',
        a: 'Kaynak kodu herkese açık; kişisel kullanım ve kendi sunucunuza kurmak ücretsiz. Bir şirket içinde çalıştırmak, yeniden satmak ya da hizmet olarak sunmak ticari lisans gerektirir, çünkü kod PolyForm Noncommercial lisansıyla yayımlanıyor. info@bubiapps.com adresine yazın.',
      },
      {
        q: 'Alarm çaldığında ne olur?',
        a: 'Acil bir görev sessiz modda ve odak modunda gerçek bir alarm sesi çalar (iOS 26’da AlarmKit, Android’de alarm kanalı) ve sonraki yarım saat boyunca siz onaylayana kadar yeniden uyarır. Sistem engellerse uygulama nedenini kaydeder.',
      },
      {
        q: 'Google Takvim eşitlemesi gerçekten iki yönlü mü?',
        a: 'Evet. Görevler seçtiğiniz takvimde etkinliğe dönüşür, Google’da yaptığınız değişiklikler geri gelir. iPhone ve Mac’te görevleriniz Apple Takvim’e de tek yönlü yansır.',
      },
      {
        q: 'Kullanmak için yapay zekâ gerekiyor mu?',
        a: 'Hayır. Her şey yapay zekâ olmadan çalışır. İsterseniz kendi Claude ya da ChatGPT hesabınızı bağlarsınız ya da kendi sağlayıcı anahtarınızı girersiniz.',
      },
      {
        q: 'Todoist ya da TickTick’teki görevlerimi getirebilir miyim?',
        a: 'Evet. Bıraktığınız uygulamadan dışa aktarın, dosyayı Ayarlar’dan içe aktarın. Hiçbir şey yazılmadan önce neyin geleceğini görürsünüz.',
      },
      {
        q: 'Neler eksik?',
        a: 'Paylaşım ve görev atama, konuma göre hatırlatma ve CalDAV üzerinden görevler. Üçü de yol haritasında yazılı.',
      },
    ],
  },

  footer: {
    line: 'Açıkta, her seferinde bir görevle geliştiriliyor.',
    columns: [
      {
        title: 'Ürün',
        links: [
          { label: 'Uygulamayı aç', href: APP_URL },
          { label: 'App Store', href: APP_STORE_URL },
          { label: 'Google Play', href: PLAY_URL },
          { label: 'Kurumsal', href: '/enterprise/tr' },
          { label: 'Değişiklik günlüğü', href: `${REPO_URL}/blob/main/CHANGELOG.md` },
          { label: 'Yol haritası', href: `${REPO_URL}/blob/main/ROADMAP.md` },
        ],
      },
      {
        title: 'Üstüne geliştirin',
        links: [
          { label: 'Bağlayıcı rehberi', href: MCP_GUIDE_URL },
          { label: 'REST API', href: '/docs/api' },
          { label: 'Sunucu kurulum rehberi', href: `${DOCS_URL}/SELF-HOSTING.md` },
          { label: 'GitHub’da kaynak kod', href: REPO_URL },
        ],
      },
      {
        title: 'Şirket',
        links: [
          { label: 'Gizlilik', href: '/privacy/tr' },
          { label: 'Destek', href: '/support/tr' },
          { label: 'Lisans', href: `${REPO_URL}/blob/main/LICENSE` },
          { label: 'Ticari lisans', href: 'mailto:info@bubiapps.com' },
        ],
      },
    ],
    notes: 'Apple, Google, Anthropic ya da OpenAI ile bağlantılı değildir.',
    photoLabel: 'Fotoğraf',
    photoChanges: 'kırpıldı ve yeniden boyutlandırıldı',
    fontLabel: 'Yazı tipi',
    fontCredit: 'Wix Madefor, SIL Open Font License',
    versionLabel: 'Sürüm',
  },
};
