/**
 * Enterprise sayfasının bütün metni, Türkçe (EE-151; EE-164'te ve OPH-388'de
 * baştan yazıldı).
 *
 * İngilizce ikizi `content.en.js`; ikisinin aynı anahtar ağacını taşıdığını bir
 * gelenek değil bir kapı garanti ediyor (`npm run check:copy`, EE-152).
 *
 * ── KİME YAZILDI ─────────────────────────────────────────────────────────
 *
 * Sayfa, fabrikalara gönderilen 18 slaytlık satış sunumunu tek seferde, beş
 * adımda anlatır: sorun, çözüm, kanıt, pilot, demo talebi (OPH-413, page.js);
 * sunumun kendisi PDF olarak indirilir. Dili sunumdan gelir (OPH-388). Okuyucu
 * bir fabrikanın genel müdürü, bilgi işlem müdürü, bakım/üretim müdürü ya da
 * satış sonrası hizmetler müdürü.
 *
 * Dil: düz, kurumsal ama konuşur gibi Türkçe; bir bölümde tek fikir, kısa
 * cümle. Kullanılır: talep, birim, hizmet kataloğu, onay, değişiklik, bilinen
 * hata, makine, bilgi bankası, kurum dışı talep formu, firma portalı, nöbet,
 * devamsızlık. İngilizce kalabilir: SLA ve ITSM (bir kez açıklanır), e-posta,
 * KVKK, Active Directory. Kullanılmaz — ve `check-copy.mjs` reddeder: ticket,
 * team, queue/kuyruk, servis masası, herkese açık, public portal, workflow,
 * dashboard, on-premise, departman. Kaçış işareti satırda `i18n-vocab-ok`.
 *
 * ── NEYİN İDDİA EDİLEBİLECEĞİ ────────────────────────────────────────────
 *
 *   • Yalnız var olan ekran gösterilir. Bugün yalnız API ile yapılanlar
 *     (capabilities.js'te `api`: nöbet listesi tanımı, tedarikçi, vardiya ve
 *     tatil girişi, toplu içe aktarma) "kurulumda biz tanımlarız / aktarırız"
 *     diye anlatılır, ekran gibi gösterilmez.
 *   • Ölçülmemiş rakam yazılmaz; ekrandaki demo rakamları "örnek veri" diye
 *     etiketlenir. Fiyat yazılmaz. Active Directory pilottur (`pilotNote`).
 *   • Paket yalnız BULUT için vardır; kendi sunucusuna kurulan kurumun
 *     sınırlarını kurulumda biz tanımlarız. Kurulumu müşteri yapmaz, biz yaparız.
 *   • Otomasyon ve yönlendirme kuralları uygulamada vardır (capabilities.js
 *     `rules: app`) ve "kaydetmeden önce bir talepte dene" ile anlatılır.
 *   • Bir şeyin "henüz olmadığını" yalnız SSS'nin üretilen `notYet` cevabı
 *     söyler; başka hiçbir metin eksik ilan etmez (`check-copy.mjs`).
 *
 * ── EKRANLAR VE İŞARETLER ────────────────────────────────────────────────
 *
 * Kahraman görseli `screenshots/sales/`'tan gelir ("Demir Çelik" demo verisiyle
 * çalışan gerçek ürün). Turdaki ekranlar `screenshots/ee/`'den gelir; İngilizce
 * sayfa aynı ekranların İngilizce örnek verili hâlini gösterir (OPH-413,
 * landing-audit K9). Her görselde `ratio` dosyanın gerçek piksel oranıdır.
 *
 * Ekran görüntüsü yolları BÜTÜN olarak saklanır (`/shots/...`), asla
 * birleştirilmez: CI kapısı derlenmiş paketi bu dizgiler için tarıyor.
 */

export const APP_URL = '/app';
export const REPO_URL = 'https://github.com/mahirozdin/alliswell';

// EE-261: what the page claims about the product comes from one list —
// the FAQ's "not yet", the package table's capability rows and every offline
// sentence. `scripts/check-copy.mjs` holds the page to it.
import { OFFLINE, notYetAnswer, packageRows, pilotNote } from './capabilities.js';

export default {
  lang: 'tr',

  seo: {
    title: 'AllisWell Enterprise — fabrikanızdaki bütün iş taleplerini tek yerden yönetin',
    description:
      'Fabrikalar için talep yönetimi: arıza, bakım, satın alma, kalite ve müşteri talepleri ' +
      'tek sistemde; SLA takibi, onaylar ve firma portalı. Bulutta ya da kendi sunucunuzda.',
    ogImage: '/shots/og/enterprise-tr.jpg',
  },

  nav: {
    home: '/',
    links: [
      { label: 'Ekranlar', href: '#tour' },
      { label: 'Karar vermeden önce', href: '#proof' },
      { label: 'Pilot', href: '#pilot' },
      { label: 'Kurulum', href: '#deploy' },
      { label: 'Sunum (PDF)', href: '#deck' },
    ],
    cta: { label: 'İletişime geçin', href: '#contact' },
    starsLabel: 'Yıldız',
  },

  // Slayt 1
  hero: {
    eyebrow: 'AllisWell Enterprise',
    title: 'Fabrikanızdaki bütün iş taleplerini tek yerden yönetin',
    lede:
      'Arıza, bakım, satın alma, kalite ve müşteri talepleri; kimin aldığı, ne kadar sürdüğü ' +
      've nasıl bittiği tek bir sistemde.',
    primary: { label: 'İletişime geçin', href: '#contact' },
    secondary: {
      label: 'Sunumu indirin (PDF)',
      href: '/downloads/alliswell-enterprise-sunum-2026-10.pdf',
      download: true,
    },
    facts: [
      'Bulutta ya da kendi sunucunuzda',
      'Türkçe ve İngilizce arayüz',
      'Telefon, tablet, web ve masaüstü',
      OFFLINE.tr.fact,
    ],
    note:
      'Sayfadaki ekranlar, örnek verilerle çalışan gerçek üründen alınmıştır. Firma ve kişi ' +
      'adları örnektir.',
    shot: '/shots/sales/hero-light-tr.jpg',
    shotDark: '/shots/sales/hero-dark-tr.jpg',
    alt:
      'Üretim biriminin talep listesi masaüstünde, Bakım biriminin listesi telefonda: her ' +
      'satırda talep numarası, konu, durum, öncelik ve kalan süre',
  },

  // Slayt 2
  problem: {
    eyebrow: 'Başlangıç noktası',
    title: 'Bugün çoğu fabrikada talepler böyle yürüyor',
    lede:
      'İş yapılıyor ama kayıt tutulmuyor. Sorun çıktığında kimin, ne zaman, neyi beklediği ' +
      'sonradan bulunamıyor.',
    items: [
      {
        icon: 'phone-call',
        title: 'Telefon, WhatsApp, koridor',
        body: 'Arıza kime söylendiyse onda kalıyor. Ortada bir kayıt yok.',
      },
      {
        icon: 'user-x',
        title: 'Kimin aldığı belli değil',
        body: 'Aynı iş iki kişiye gidiyor ya da hiç kimseye gitmiyor.',
      },
      {
        icon: 'timer',
        title: 'Süre ölçülmüyor',
        body: 'Hattın ne kadar beklediği, arızanın kaç saatte çözüldüğü bilinmiyor.',
      },
      {
        icon: 'mail',
        title: 'Şikâyet e-postada kalıyor',
        body: 'Müşterinin e-postasını takip eden yok, müşteri ikinci kez arıyor.',
      },
      {
        icon: 'repeat',
        title: 'Vardiya devrinde bilgi düşüyor',
        body: 'Gece vardiyasının bildirdiği sorun sabah unutuluyor.',
      },
    ],
    conclusion: {
      label: 'Sonuç:',
      body:
        '“Geçen ay kaç arıza oldu, ortalama kaç saatte çözüldü, en çok hangi makine durdu?” ' +
        'sorularının güvenilir bir cevabı yok. Ölçülmeyen şey de iyileştirilemiyor.',
    },
  },

  // Slayt 3
  journey: {
    eyebrow: 'AllisWell Enterprise nedir?',
    title: 'Her talep, açıldığı andan kapandığı ana kadar tek bir kayıtta',
    lede:
      'AllisWell Enterprise; kurum içinden ve dışından gelen talepleri doğru birime ' +
      'yönlendiren, süresini ölçen ve sonucunu kayıt altına alan bir talep yönetim sistemidir. ' +
      'Web, masaüstü, tablet ve telefonda aynı uygulamadır.',
    steps: [
      {
        n: 1,
        icon: 'inbox',
        title: 'Talep açılır',
        body:
          'Uygulamadan, e-postayla, web formundan ya da çöken bir sistemden kendiliğinden.',
      },
      {
        n: 2,
        icon: 'git-branch',
        title: 'Doğru birime düşer',
        body: 'Hizmet kataloğu ve kurallar talebi ilgili birimin listesine gönderir.',
      },
      {
        n: 3,
        icon: 'clock',
        title: 'Süre işlemeye başlar',
        body: 'Yanıt ve çözüm süresi fabrikanın mesai takvimine göre sayılır.',
      },
      {
        n: 4,
        icon: 'user-check',
        title: 'Bir kişiye atanır',
        body: 'Talep, kişinin kendi iş listesine görev olarak düşer.',
      },
      {
        n: 5,
        icon: 'wrench',
        title: 'Çözülür',
        body: 'Yazışma, iç notlar, ekler ve harcanan süre talepte kalır.',
      },
      {
        n: 6,
        icon: 'thumbs-up',
        title: 'Talep sahibi onaylar',
        body: '“Çözüldü” der ya da yeniden açar, memnuniyetini puanlar.',
      },
    ],
    footnote:
      'Sunum (PDF) her adımı ekranlarıyla anlatıyor: yönetim ayarları, talep yönetimi, süre ' +
      'takibi (SLA), kişilerin işleri ve dışarıdan gelen talepler.',
  },

  // Çözüm, ekran ekran (OPH-413): her sunum slaytına bir bölüm yerine tek bir
  // sekmeli tur. İngilizce sayfa aynı ekranların İngilizce örnek verili hâlini
  // gösterir (`screenshots/ee/`).
  tour: {
    eyebrow: 'Çözüm',
    title: 'Ekibinizin çalışacağı ekranlar',
    lede: 'Örnek verilerle çalışan gerçek ürün. Bir ekran seçin.',
    tabs: [
      {
        id: 'list',
        label: 'Birimin talep listesi',
        caption:
          'Her birim kendi listesinden çalışır: her satırda durum, öncelik ve kalan süre. SLA’sı ' +
          'aşılan talep kırmızıyla görünür.',
        shot: '/shots/ee/ticket-queue-light-tr.jpg',
        shotDark: '/shots/ee/ticket-queue-dark-tr.jpg',
        alt:
          'Bir birimin talep listesi ve durum süzgeçleri; acil bir arıza talebi SLA süresini ' +
          'aşmış',
        frame: 'card',
        ratio: '900 / 1000',
      },
      {
        id: 'request',
        label: 'Tek bir talep',
        caption:
          'Yazışma, iç notlar, ekler, harcanan süre ve her değişiklik talebin üzerinde kalır.',
        shot: '/shots/ee/ticket-detail-light-tr.jpg',
        shotDark: '/shots/ee/ticket-detail-dark-tr.jpg',
        alt:
          'Bir talep: işlemde, acil, yanıt hedefi aşılmış; altında talebin yazışması',
        frame: 'card',
        ratio: '900 / 1300',
      },
      {
        id: 'sla',
        label: 'SLA panosu',
        caption:
          'Yanıt ve çözüm süresi mesai takviminize göre sayılır. Pano, sözlerin ne kadarının ' +
          'tutulduğunu birime ve hizmete göre gösterir.',
        shot: '/shots/ee/sla-dashboard-light-tr.jpg',
        shotDark: '/shots/ee/sla-dashboard-dark-tr.jpg',
        alt:
          'SLA panosu: tutulan sözlerin oranı, birime ve hizmete göre sayılar ve hedefini ' +
          'aşan talepler',
        frame: 'card',
        ratio: '900 / 1820',
      },
      {
        id: 'outside',
        label: 'Dışarıdan talep',
        caption:
          'Müşteri ve tedarikçi, hesap açmadan web formundan talep açar ve takip bağlantısından ' +
          'izler.',
        shot: '/shots/ee/portal-form-light-tr.jpg',
        shotDark: '/shots/ee/portal-form-dark-tr.jpg',
        alt:
          'Elektrik arızası için dış talep formu: e-posta adresi, konu, açıklama, hat numarası ' +
          've vardiya',
        frame: 'card',
        ratio: '900 / 880',
      },
    ],
  },
  // Karar vermeden bakılabilecek kanıt (OPH-413). Yalnız bugün doğru olan:
  // müşteri adı yok, müşteriden rakam yok.
  proof: {
    eyebrow: 'Karar vermeden önce',
    title: 'Kendiniz bakabileceğiniz şeyler',
    lede:
      'Bu sayfadaki her ekran gerçek üründür. Canlı deneme isteyin, kendi birimleriniz ve ' +
      'hizmetlerinizle bakın.',
    items: [
      {
        key: 'integrity',
        icon: 'wifi-off',
        accent: 'primary',
        title: 'İnternet yokken de çalışır',
        body: OFFLINE.tr.integrity,
      },
      {
        key: 'kvkk',
        icon: 'shield-check',
        accent: 'tertiary',
        title: 'KVKK: verileriniz sizde kalır',
        body:
          'Kendi sunucunuzda, kendi veritabanınızda ya da bulutta kurumunuza ayrılmış bir ' +
          'adreste çalışır. Bütün veri tek dosya hâlinde dışa alınabilir; her değişiklik ' +
          'denetim kaydına yazılır.',
      },
      {
        key: 'setup',
        icon: 'server',
        accent: 'secondary',
        title: 'Kurulum ve geçiş bizden',
        body:
          'Kurulumu ekibimiz yapar. Mevcut sistemden (ServiceDesk Plus, Jira ya da Excel) hizmet ' +
          'listesini, kişileri ve geçmiş talepleri kurulumda biz aktarırız.',
      },
      {
        key: 'source',
        icon: 'file-text',
        accent: 'warning',
        title: 'Bilgi işleminizin okuyabileceği kod',
        body:
          'Ücretsiz AllisWell’in üzerine kuruludur; onun kaynağı, güvenlik politikası ve ' +
          'belgelenmiş REST API’si GitHub’da herkese görünür.',
      },
    ],
  },
  // Pilot (OPH-413): sunumun önerisi, demo talebinden önceki adım olarak.
  pilot: {
    eyebrow: 'Pilot',
    title: 'Önce tek bir birimle, birkaç hafta',
    lede:
      'Kararı bir sunuma göre değil, kendi fabrikanızın rakamlarına göre verirsiniz. Paket, ' +
      'kişi ve birim sayınıza göre belirlenir.',
    steps: [
      {
        n: 1,
        icon: 'server',
        title: 'Biz kurarız',
        body: 'Bulutta ya da sunucunuzda; birimleriniz, hizmetleriniz ve mesai takviminizle.',
      },
      {
        n: 2,
        icon: 'rocket',
        title: 'Bir birim kullanır',
        body: 'Örneğin Bakım, taleplerini birkaç hafta burada yürütür.',
      },
      {
        n: 3,
        icon: 'check',
        title: 'Rakamlara bakarsınız',
        body: 'Yanıt ve çözüm süreleri, tutulan sözler ölçülür. Ardından diğer birimler gelir.',
      },
    ],
  },
  deploy: {
    eyebrow: 'Kurulum seçenekleri',
    title: 'Bulut mu, kendi sunucunuz mu?',
    lede: 'İkisinde de aynı ürün. Fark, verinin nerede durduğu ve sistemi kimin işlettiğidir.',
    options: [
      {
        key: 'cloud',
        icon: 'cloud',
        title: 'Bulut',
        tagline: 'Hızlı başlangıç, işletme yükü yok',
        points: [
          'Kurumunuza özel adres: sirketiniz.alliswell.space',
          'Kurulum, yedekleme, güncelleme ve izleme bizden',
          'Starter, Business ya da Enterprise paketi; büyüdükçe geçiş yapılır',
          'Verileriniz yalnız size ait, diğer müşterilerden ayrı bir alanda tutulur',
        ],
        cta: { label: 'Bulut paketlerini görün', href: '#packages' },
      },
      {
        key: 'self',
        icon: 'server',
        title: 'Kendi sunucunuzda',
        tagline: 'Veri fabrikanın dışına çıkmaz',
        points: [
          'Sizin sunucunuza, sizin veritabanınıza biz kurarız',
          'Kullanıcı sayısı, birim sayısı ve modüller ihtiyacınıza göre belirlenir',
          'Fiyat, kullanıcı ve birim sayısına göre teklif olarak sunulur',
          'Güncellemeler ve destek sözleşmeyle; verinin yeri hiçbir zaman değişmez',
        ],
        cta: { label: 'Teklif için iletişime geçin', href: '#contact' },
      },
    ],
    footnote:
      'Kararsız mısınız? Formda “henüz karar vermedim” deyin; büyüklüğünüze ve mevzuat ' +
      'gereklerinize göre birlikte karar veririz.',
  },

  packages: {
    anchor: 'packages',
    eyebrow: 'Bulut paketleri',
    title: 'Bulutta üç hazır paket',
    lede:
      'Bu paketler bulutta kullanan kurumlar içindir. Kendi sunucunuza kurulumda hazır paket ' +
      'yoktur; sınırlar ve modüller ihtiyacınıza göre belirlenir.',
    caption: 'Bulut paketleri karşılaştırması',
    featureHeading: 'Kapsam',
    labels: { yes: 'Var', no: 'Yok', partial: 'Kısmi' },
    columns: ['Starter', 'Business', 'Enterprise'],
    pinnedRows: 3,
    moreLabel: 'Ayrıntılı kapsam',
    rows: [
      ['Kullanıcı sayısı', '10', '250', 'Sınırsız'],
      ['Birim sayısı', '5', '50', 'Sınırsız'],
      ['Denetim kaydı saklama süresi', '90 gün', '1 yıl', '7 yıl'],
      [
        'Kurum dışı talep formu: etkin form ve aylık talep sayısı',
        'Paketle belirlenir',
        'Paketle belirlenir',
        'Paketle belirlenir',
      ],
      // EE-261: every capability row, with its level in the label.
      ...packageRows('tr'),
    ],
    footnote:
      'Paket içeriği sözleşmenizde yazar; ihtiyaç değiştikçe paket yükseltilir. Fiyat, ' +
      'büyüklüğünüze göre teklif olarak sunulur.',
    link: { label: 'Teklif isteyin →', href: '#contact' },
  },

  deck: {
    eyebrow: 'Sunum',
    title: 'Sunumu indirin, ekibinizle paylaşın',
    lede:
      'Her adım ve ekran, 18 sayfalık bir PDF olarak. Bilgi işlem, bakım ve üretim ' +
      'müdürlerinize e-postayla iletebilirsiniz.',
    cover: {
      shot: '/shots/sales/deck-cover-tr.jpg',
      alt: 'Sunumun kapağı: “Fabrikanızdaki bütün iş taleplerini tek yerden yönetin”',
    },
    pdf: {
      href: '/downloads/alliswell-enterprise-sunum-2026-10.pdf',
      label: 'Sunumu indirin (PDF)',
      meta: 'PDF · 18 sayfa · Türkçe',
    },
    secondary: {
      label: 'İngilizce sunum (PDF)',
      href: '/downloads/alliswell-enterprise-presentation-2026-10.pdf',
    },
  },

  // Slayt 18
  contact: {
    eyebrow: 'İletişim',
    title: 'Sorularınız, canlı deneme ve görüşme talebiniz için bize yazın',
    lede:
      'Kaç kişi ve kaç birimle başlamak istediğinizi yazmanız yeterli. Size dönüş yapar; ' +
      'bulut ya da kendi sunucunuz için teklif ve kurulum planı hazırlarız.',
    mailSubject: 'AllisWell Enterprise teklif talebi',
    fields: {
      name: { label: 'Adınız soyadınız' },
      company: { label: 'Kurum adı' },
      workEmail: { label: 'Kurumsal e-posta' },
      phone: { label: 'Telefon (isteğe bağlı)' },
      seats: { label: 'Kullanıcı sayısı (tahminî)' },
      units: { label: 'Birim sayısı' },
      packageInterest: {
        label: 'İlgilendiğiniz seçenek',
        placeholder: 'Henüz karar vermedim',
        options: [
          'Bulut — Starter',
          'Bulut — Business',
          'Bulut — Enterprise',
          'Kendi sunucumuza kurulum',
        ],
      },
      message: { label: 'Eklemek istedikleriniz (mevcut sistemleriniz, öncelikli ihtiyaçlarınız)' },
      honeypot: 'Firma web sitesi',
    },
    consent: {
      text:
        'Bu formdaki bilgilerin talebimi yanıtlamak amacıyla saklanmasını ve kullanılmasını ' +
        'kabul ediyorum. Ayrıntılar:',
      linkLabel: 'aydınlatma metni',
      // Belgenin tamamı değil, BÖLÜMÜ: üç yüz satıra inen bir rıza linki,
      // okuyucuya neyi onayladığını söylememiş olur.
      href: '/privacy/tr#kurumsal-talep-formu',
    },
    submit: 'Gönder',
    sending: 'Gönderiliyor…',
    orWrite: 'Ya da doğrudan yazın:',
    sent: 'Teşekkürler, talebiniz bize ulaştı. En kısa sürede sizinle iletişime geçeceğiz.',
    // Her sonuç için bir mesaj (EE-161). Sunucu makine-okunur bir kod dönüyor,
    // sayfa onu okuyanın dilinde söylüyor.
    states: {
      // Özür DEĞİL: bu kurulumda satış formu yok; form yerini adrese bırakır.
      noDesk: 'Bu kurulumda satış formu etkin değil. Bize doğrudan yazın, size dönüş yapalım:',
      stale:
        'Aydınlatma metnimiz bu sayfa açıkken güncellendi. Lütfen sayfayı yenileyip tekrar ' +
        'gönderin; onayladığınız metin, size gösterilen metin olsun.',
      busy:
        'Şu anda çok sayıda talep alıyoruz. Birkaç dakika sonra tekrar deneyin ya da doğrudan ' +
        'bize yazın.',
      invalid: 'Formdaki bir alan kabul edilmedi. Lütfen alanları kontrol edip tekrar deneyin.',
      offline:
        'Sunucumuza ulaşılamadı. Yazdıklarınız duruyor; biraz sonra tekrar deneyin ya da ' +
        'doğrudan bize yazın.',
      failed:
        'Bizim tarafımızda bir sorun oluştu. Yazdıklarınız duruyor; tekrar deneyin ya da ' +
        'doğrudan bize yazın.',
      // EE-232 — yalnız doğrulama kutusu olan bir derlemede görünür.
      challenge:
        'Doğrulama tamamlanmadı ya da süresi doldu. Kutuyu yeniden işaretleyip tekrar ' +
        'gönderin; yazdıklarınız duruyor.',
      challengeUnavailable:
        'Doğrulama kutusu yüklenemedi; bir içerik engelleyici ya da bağlantı sorunu olabilir. ' +
        'Form gönderilemiyorsa bize doğrudan yazın.',
    },
  },

  faq: {
    heading: 'Sık sorulan sorular',
    items: [
      {
        q: 'Kurulum ne kadar sürer, kim yapar?',
        a:
          'Kurulumu ekibimiz yapar: bulutta kurumunuza ayrılmış adresi açarız, kendi ' +
          'sunucunuzda ise sistemi sunucunuza biz kurarız. Asıl zaman birimlerinizi, hizmet ' +
          'kataloğunuzu, mesai takviminizi ve sürelerinizi birlikte tanımlamaya gider. ' +
          'Önerimiz tek bir birimle birkaç haftalık bir denemedir.',
      },
      {
        q: 'Mevcut sistemimizdeki talepleri aktarabilir miyiz?',
        a:
          'Evet. ServiceDesk Plus, Jira ya da Excel’deki hizmet listesini, kişileri ve geçmiş ' +
          'talepleri kurulumda biz aktarırız. Vardiyaları, tatilleri ve nöbet listelerini de ' +
          'kurulumda biz tanımlarız.',
      },
      {
        q: 'Bulut ile kendi sunucumuza kurulum arasında özellik farkı var mı?',
        a:
          'Yok; ikisi de aynı üründür. Bulutta kurulum, yedekleme ve güncellemeyi biz ' +
          'üstleniriz. Kendi sunucunuzda veri fabrikanızın dışına çıkmaz.',
      },
      {
        q: 'Verimiz nerede tutulur, dışarı alabilir miyiz?',
        a:
          'Kendi sunucunuza kurulumda veri tamamen sizdedir; bulutta yalnız size ait bir alanda ' +
          'tutulur. İki durumda da bütün veri tek dosya olarak, denetim kayıtları da tablo ' +
          'olarak dışa alınır.',
      },
      {
        q: 'Active Directory ve tek oturum açma ile çalışır mı?',
        a:
          'Evet. Active Directory ve LDAP bağlantısı, Microsoft Entra ID gibi sistemlerle tek ' +
          'oturum açma (SAML, OpenID Connect) ve otomatik kullanıcı aktarımı (SCIM) bulutta ' +
          'Enterprise paketinde, kendi sunucunuzda ise istediğiniz kapsamda vardır. ' +
          pilotNote('directory', 'tr'),
      },
      {
        q: 'Müşterilerimizin sistemde hesabı olması gerekir mi?',
        a:
          'Hayır. Kurum dışından talep iletenler kurum dışı talep formunu kullanır ve durumu ' +
          'takip bağlantısından izler. Sözleşmeli firmaların kişileri isterseniz firma ' +
          'portalına kendi şifreleriyle girer.',
      },
      {
        q: 'Ücretsiz AllisWell ile farkı ne?',
        a:
          'Ücretsiz sürüm tek kişinin görevleri, notları ve dosyaları içindir. Enterprise buna ' +
          'birimleri, rolleri, talep yönetimini, SLA takibini, kurum dışı talep formunu ve ' +
          'kurumsal kimlik bağlantısını ekler; ticari lisansla kullanılır.',
      },
      {
        // EE-261: generated, never hand-written — see capabilities.js.
        key: 'notYet',
        q: 'Neler henüz yok?',
        a: notYetAnswer('tr'),
      },
    ],
  },

  footer: {
    blurb:
      'AllisWell Enterprise; fabrikanızın iç ve dış taleplerini, SLA takibini ve ekiplerin ' +
      'günlük işlerini tek sistemde toplar. Bir BubiApps ürünüdür.',
    notes:
      'Microsoft, Apple, Google, Anthropic ya da OpenAI ile bağlantılı değildir. Ürün adları ' +
      'sahiplerine aittir.',
    privacyLabel: 'Gizlilik',
    supportLabel: 'Destek',
    starsWord: 'yıldız',
    forksWord: 'çatal',
    columns: [
      {
        title: 'Enterprise',
        links: [
          { label: 'Ekranlar', href: '#tour' },
          { label: 'Karar vermeden önce', href: '#proof' },
          { label: 'Pilot', href: '#pilot' },
          { label: 'Kurulum seçenekleri', href: '#deploy' },
          { label: 'Bulut paketleri', href: '#packages' },
          { label: 'Sunum (PDF)', href: '#deck' },
          { label: 'İletişime geçin', href: '#contact' },
        ],
      },
      {
        title: 'Teknik belgeler',
        links: [
          { label: 'REST API referansı', href: '/docs/api' },
          { label: 'Güvenlik politikası', href: `${REPO_URL}/blob/main/SECURITY.md` },
          { label: 'Gizlilik politikası', href: '/privacy/tr' },
        ],
      },
      {
        title: 'Ücretsiz sürüm',
        links: [
          { label: 'alliswell.space', href: '/tr' },
          { label: 'Uygulamayı aç', href: APP_URL },
          { label: "GitHub'da kaynak", href: REPO_URL },
          { label: 'Lisans (PolyForm NC)', href: `${REPO_URL}/blob/main/LICENSE` },
        ],
      },
    ],
  },

  /** `#app` içindeki JavaScript'siz blok; giriş HTML'iyle aynı kalmalı. */
};
