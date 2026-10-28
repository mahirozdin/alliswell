/**
 * Enterprise sayfasının bütün metni, Türkçe (EE-151; EE-164'te ve OPH-388'de
 * baştan yazıldı).
 *
 * İngilizce ikizi `content.en.js`; ikisinin aynı anahtar ağacını taşıdığını bir
 * gelenek değil bir kapı garanti ediyor (`npm run check:copy`, EE-152).
 *
 * ── KİME YAZILDI ─────────────────────────────────────────────────────────
 *
 * Sayfa, fabrikalara gönderilen 18 slaytlık satış sunumunun web hâlidir; akışı,
 * dili ve ekranları ondan gelir (OPH-388). Okuyucu bir fabrikanın genel müdürü,
 * bilgi işlem müdürü, bakım/üretim müdürü ya da satış sonrası hizmetler müdürü.
 * Satış sonrası hizmet veren firmalar ikinci kitledir ve "Dışarıdan talep"
 * bölümünde konuşulur.
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
 * Ekranlar `screenshots/sales/`'tan gelir: "Demir Çelik" demo verisiyle çalışan
 * gerçek ürün, satış sunumunun çekim hattından sunumla aynı kesimler. Her
 * görselde `ratio` dosyanın gerçek piksel oranıdır. İşaretlerin (`marks`) x/y
 * değerleri görselin kendi kutusunda yüzdedir; açık-tr çekime bakılarak, sunumun
 * kendi işaret yerleri esas alınarak konmuştur. Koyu ve
 * İngilizce çekimler aynı yerleşimi taşır. Bir maddenin işareti yoksa o madde
 * listenin sonundadır ve numara yerine düz bir nokta alır (AnnotatedShots);
 * işaret yalnız süs, söylenen her şey listededir.
 *
 * Ekran görüntüsü yolları BÜTÜN olarak saklanır (`/shots/sales/...`), asla
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
      { label: 'Talep yönetimi', href: '#itsm' },
      { label: 'SLA', href: '#sla' },
      { label: 'Dışarıdan talep', href: '#intake' },
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
      'Aşağıdaki bölümler bu adımları sırayla gösteriyor: yönetim ayarları, talep yönetimi, ' +
      'süre takibi (SLA), kişilerin işleri ve dışarıdan gelen talepler.',
  },

  // Slayt 4
  org: {
    eyebrow: 'Yönetim arayüzü',
    title: 'Organizasyon şemanız sisteme birebir taşınır',
    lede:
      'Kurulum birimlerle başlar. Talepler birime düşer, raporlar birime göre toplanır, ' +
      'yetkiler rollerle verilir.',
    layout: 'grid',
    shots: [
      {
        shot: '/shots/sales/birimler-light-tr.jpg',
        shotDark: '/shots/sales/birimler-dark-tr.jpg',
        alt:
          'Birimler ekranı: Bilgi İşlem, Bakım, Üretim, Kalite, İnsan Kaynakları, Satın Alma ve ' +
          'İSG, her birinin kişi sayısıyla',
        frame: 'card',
        ratio: '1600 / 1000',
        marks: [{ n: 1, x: 62, y: 26 }],
      },
      {
        shot: '/shots/sales/roller-light-tr.jpg',
        shotDark: '/shots/sales/roller-dark-tr.jpg',
        alt: 'Roller ekranı: Sahip, Yönetici, Üye, Birim yöneticisi ve Vardiya amiri rolleri',
        frame: 'card',
        ratio: '1600 / 875',
        marks: [{ n: 2, x: 55, y: 89 }],
      },
    ],
    items: [
      {
        n: 1,
        title: 'Her birim',
        body:
          'kendi talep listesine, raporlarına ve ekibine sahiptir. Bir kişi birden çok birimde ' +
          'çalışabilir.',
      },
      {
        n: 2,
        title: 'Roller.',
        body:
          'Sahip, yönetici ve üyeye ek olarak “Vardiya amiri” gibi özel roller tanımlanır. Kimin ' +
          'talep atayabileceği, kapatabileceği, onay verebileceği rolde yazılıdır. Kurumun ' +
          'adresine dışarıdan kayıt açılamaz.',
      },
    ],
  },

  // Slayt 5
  catalog: {
    eyebrow: 'Yönetim arayüzü',
    title: 'Çalışan ne isteyebileceğini bir menüden seçer',
    lede:
      'Hizmet kataloğu, talep açan kişinin gördüğü listedir. Her hizmetin hangi birime ' +
      'düşeceği, ne soracağı ve onay isteyip istemediği burada belirlenir.',
    layout: 'side',
    shots: [
      {
        shot: '/shots/sales/servis-kurulum-light-tr.jpg',
        shotDark: '/shots/sales/servis-kurulum-dark-tr.jpg',
        alt:
          '“Yatırım ve demirbaş alımı” hizmetinin ayarları: raf, ikon, işin türü (olay ya da ' +
          'hizmet isteği) ve hizmete bakan birim olarak Satın Alma',
        frame: 'card',
        ratio: '1575 / 1600',
        marks: [
          { n: 2, x: 62, y: 12.5 },
          { n: 3, x: 90, y: 31 },
          { n: 4, x: 60, y: 51 },
        ],
      },
      {
        shot: '/shots/sales/katalog-light-tr.jpg',
        shotDark: '/shots/sales/katalog-dark-tr.jpg',
        alt:
          'Hizmet kataloğunun “Üretim ve bakım” rafı: elektrik arızası, hat duruşu, hidrolik ' +
          'kaçak, kalıp değişimi, mekanik arıza, periyodik bakım talebi',
        frame: 'card',
        ratio: '1000 / 1320',
        marks: [{ n: 1, x: 62, y: 9.5 }],
      },
    ],
    items: [
      {
        n: 1,
        title: 'Raflar.',
        body:
          'Hizmetler “Üretim ve bakım”, “Bilgi işlem”, “Kalite” gibi raflarda durur; aranarak ' +
          'da bulunur.',
      },
      { n: 2, title: 'Raf ve ikon.', body: 'Talep açan kişi hizmeti bu işaretle tanır.' },
      {
        n: 3,
        title: 'Arıza mı, ihtiyaç mı?',
        body:
          'Hizmet “olay” ya da “hizmet isteği” olarak işaretlenir; raporlar ikisini ayrı ölçer.',
      },
      {
        n: 4,
        title: 'Bakan birim ve onay.',
        body:
          'Talep seçilen birime düşer. Satın alma gibi hizmetlerde önce yöneticinin ya da ' +
          'belirli kişilerin imzası beklenir.',
      },
    ],
    note:
      'Hizmete özel sorular da sorulur (“Hat numarası”, “Tahmini tutar”). Formdaki her ' +
      'değişiklik yeni bir sürümdür; eski talepler bozulmaz.',
  },

  // Slayt 6
  rules: {
    eyebrow: 'Yönetim arayüzü',
    title: 'Kurallar talebi kimse elle taşımadan doğru yere götürür',
    lede:
      'Yönlendirme kuralı yeni talebin nereye gideceğini, otomasyon kuralı bir şey olunca ne ' +
      'yapılacağını söyler.',
    layout: 'grid',
    cols: 2,
    shots: [
      {
        shot: '/shots/sales/yonlendirme-light-tr.jpg',
        shotDark: '/shots/sales/yonlendirme-dark-tr.jpg',
        alt:
          'Yönlendirme kuralları: hidrolik ve yağ kaçağı Bakım’a, müşteri e-postaları Kalite’ye, ' +
          'forklift geçen talepler Lojistik’e, hat duruşu kelimeleri Üretim’e acil olarak',
        frame: 'card',
        ratio: '1600 / 750',
        title: 'Yönlendirme: yeni talep nereye gidecek?',
        caption:
          '“Konuda hidrolik ya da yağ kaçağı geçiyorsa Bakım’a, öncelik yüksek.” Eşleşen ilk ' +
          'kural karar verir.',
      },
      {
        shot: '/shots/sales/kurallar-light-tr.jpg',
        shotDark: '/shots/sales/kurallar-dark-tr.jpg',
        alt:
          'Otomasyon kuralları: hat duruşu her zaman acil, bakım talepleri en az yüklü ' +
          'teknisyene, süresi aşılan acil talep için üretim müdürüne e-posta, ERP yanıt vermezse ' +
          'talep aç',
        frame: 'card',
        ratio: '1600 / 958',
        title: 'Otomasyon: bir şey olunca ne yapılacak?',
        caption:
          '“Hat duruşu her zaman acil.” “Süresi aşılan acil talep için üretim müdürüne ' +
          'e-posta.” “ERP yanıt vermezse talep aç.”',
      },
      {
        shot: '/shots/sales/kural-dene-light-tr.jpg',
        shotDark: '/shots/sales/kural-dene-dark-tr.jpg',
        alt:
          'Bir talepte dene: kural #205 numaralı talepte denendi; hizmet, kuralın açık olması ve ' +
          'günlük sınır koşulları sağlanıyor, kural önceliği yüksekten acile çevirirdi',
        frame: 'card',
        ratio: '1600 / 583',
        marks: [{ n: 1, x: 27, y: 40 }],
      },
    ],
    items: [
      {
        n: 1,
        title: 'Kaydetmeden önce dene.',
        body:
          'Kural, yazılan gerçek bir talep numarasında adım adım denenir: hangi koşulun ' +
          'sağlandığı ve kuralın ne yapacağı gösterilir. Hiçbir şey değişmez.',
      },
      {
        n: 2,
        title: 'Kendini tekrarlayan kural durur.',
        body: 'Bir kural kendi kendini tekrarlamaya başlarsa sistem onu durdurur ve nedenini yazar.',
      },
    ],
  },

  // Slayt 7
  itsm: {
    eyebrow: 'Talep yönetimi (ITSM)',
    title: 'Her birim kendi talep listesiyle çalışır',
    lede:
      'ITSM (talep yönetimi), “kim neyi ne zaman istedi, kim aldı, ne kadar sürdü, nasıl bitti” ' +
      'sorularının tek kayıtta cevaplanmasıdır. Günlük iş bu listede döner.',
    layout: 'side',
    shots: [
      {
        shot: '/shots/sales/kuyruk-light-tr.jpg',
        shotDark: '/shots/sales/kuyruk-dark-tr.jpg',
        alt:
          'Üretim biriminin talep listesi: üstte diğer birimlerdeki SLA uyarıları, altında hazır ' +
          'süzgeçler ve talepler; #205 “Hat 3 sunucusu yine yanıt vermiyor” talebinde SLA aşıldı',
        frame: 'card',
        ratio: '1600 / 1000',
        marks: [
          { n: 1, x: 60, y: 18 },
          { n: 2, x: 11.5, y: 41 },
          { n: 3, x: 80, y: 55 },
          { n: 4, x: 60, y: 73, tone: 'alert' },
        ],
      },
    ],
    items: [
      {
        n: 1,
        title: 'Diğer birimlerdeki uyarılar.',
        body:
          'Birden çok birimde çalışan kişi, öteki birimlerinde süresi aşılan talepleri en üstte görür.',
      },
      {
        n: 2,
        title: 'Hazır süzgeçler.',
        body:
          'Yeni, devam eden, beklemede, acil, bende, kimsede değil, süresi aşılan, arızalar…',
      },
      {
        n: 3,
        title: 'Her satır bir talep.',
        body: 'Numara, konu, durum, öncelik, talep sahibi, kalan süre ve talebi alan kişi.',
      },
      {
        n: 4,
        title: 'Süresi aşılan talep',
        body: 'kırmızıyla işaretlenir; listeyi açan kişi önce onu görür.',
      },
    ],
    points: [OFFLINE.tr.queue],
    note: '100 talebe kadar durum, öncelik ya da atama tek seferde değiştirilebilir.',
  },

  // Slayt 8
  ticket: {
    eyebrow: 'Talep yönetimi (ITSM)',
    title: 'Bir talebin bütün hikâyesi tek ekranda',
    lede:
      'Örnek: Anadolu Otomotiv’in e-postayla bildirdiği ölçü sapması. Talep Kalite birimine ' +
      'düşmüş, yazışma sürüyor.',
    layout: 'grid',
    shots: [
      {
        shot: '/shots/sales/talep-ust-light-tr.jpg',
        shotDark: '/shots/sales/talep-ust-dark-tr.jpg',
        alt:
          'Talep #206, “Parti 24-118 flanşlarda ölçü sapması”: durum, öncelik ve Aktar düğmesi; ' +
          'e-postayla gelen talebin sahibi, yanıt için kalan süre ve bağlı firma Anadolu Otomotiv',
        frame: 'card',
        ratio: '1600 / 954',
        marks: [
          { n: 1, x: 45, y: 31 },
          { n: 2, x: 56, y: 21 },
          { n: 3, x: 80, y: 62.5 },
        ],
      },
      {
        shot: '/shots/sales/talep-yazisma-light-tr.jpg',
        shotDark: '/shots/sales/talep-yazisma-dark-tr.jpg',
        alt:
          'Aynı talebin yazışması: talep sahibinin e-postası, birimin yanıtı ve en üstte kilit ' +
          'işaretli bir iç not; altta Yanıt ve İç not seçimi',
        frame: 'card',
        ratio: '1600 / 758',
        marks: [{ n: 4, x: 86, y: 10 }],
      },
    ],
    items: [
      {
        n: 1,
        title: 'Talep sahibi ve kaynağı:',
        body: 'kim yazdı, e-postayla mı, formdan mı geldi.',
      },
      {
        n: 2,
        title: 'Durum, öncelik, aktar:',
        body: 'talep tek adımda başka bir birime aktarılır.',
      },
      { n: 3, title: 'Kalan süre ve firma:', body: 'yanıt için kalan süre, bağlı müşteri firması.' },
      {
        n: 4,
        title: 'Yanıt ile iç not ayrıdır.',
        body: 'İç not kilit işaretiyle gösterilir; talep sahibi hiçbir ekranda görmez.',
      },
    ],
    note:
      'Harcanan süre talebe yazılır. Aynı ekrandan değişiklik, bilinen hata kaydı ya da bilgi ' +
      'bankası makalesi açılır.',
  },

  // Slayt 9
  approvals: {
    eyebrow: 'Talep yönetimi (ITSM)',
    title: 'İmza bekleyen işler, planlı değişiklikler, tekrar eden arızalar',
    lede: 'Üçü de aynı hikâyeden: Hat 3 sunucusundaki arızalı RAID kartı.',
    layout: 'phones',
    shots: [
      {
        shot: '/shots/sales/onay-telefon-light-tr.jpg',
        shotDark: '/shots/sales/onay-telefon-dark-tr.jpg',
        alt:
          'Telefonda onay ekranı: #201 satın alma talebi, tahmini tutar, gerekçe, önerilen ' +
          'tedarikçi; Reddet ve Onayla düğmeleri',
        frame: 'phone',
        ratio: '780 / 1688',
        title: 'Onay',
        caption:
          '#201 satın alma talebi: iki disk ve RAID kartı. Onaylayan; tutarı, gerekçeyi, ' +
          'tedarikçiyi ve teklif dosyasını telefonda görür, gerekçesini yazarak onaylar ya da reddeder.',
      },
      {
        shot: '/shots/sales/degisiklik-telefon-light-tr.jpg',
        shotDark: '/shots/sales/degisiklik-telefon-dark-tr.jpg',
        alt:
          'Telefonda değişiklik ekranı: Hat 3 sunucusunda disk ve RAID kartı değişimi, yüksek ' +
          'risk, etkisi, geri dönüş planı ve beklenen imza',
        frame: 'phone',
        ratio: '780 / 1688',
        title: 'Planlı değişiklik',
        caption:
          'Disk değişiminin penceresi, riski, etkisi ve geri dönüş planı. Pencere ay sonu ' +
          'sayımıyla çakışınca sistem uyarır; kurul imzası beklenir.',
      },
      {
        shot: '/shots/sales/problem-telefon-light-tr.jpg',
        shotDark: '/shots/sales/problem-telefon-dark-tr.jpg',
        alt:
          'Telefonda bilinen hata: Hat 3 SCADA bağlantısında aralıklı kopma, düzelene kadar ' +
          'yapılacak olan ve bu hataya bağlı talepler',
        frame: 'phone',
        ratio: '780 / 1688',
        title: 'Bilinen hata',
        caption:
          '“Hat 3 SCADA bağlantısı kopuyor.” Aynı nedene bağlı talepler tek kayıtta; düzelene ' +
          'kadar ne yapılacağı en üstte yazılı.',
      },
    ],
  },

  // Slayt 10
  assets: {
    eyebrow: 'Talep yönetimi (ITSM)',
    title: 'Makineler ve hazır çözümler de taleplere bağlıdır',
    lede: 'Her makinenin bir kaydı vardır; o makine için açılan her talep bu kayda bağlanır.',
    layout: 'phones',
    shots: [
      {
        shot: '/shots/sales/ekipman-telefon-light-tr.jpg',
        shotDark: '/shots/sales/ekipman-telefon-dark-tr.jpg',
        alt:
          'Telefonda makine kartı BT-SRV-003, Hat 3 sunucusu: seri no, üretici, model, garanti ' +
          'bitişi, tedarikçi, satın alma tarihi ve fiyatı; “Bu varlık için talep aç” düğmesi',
        frame: 'phone',
        ratio: '780 / 1688',
        marks: [
          { n: 1, x: 85, y: 30 },
          { n: 2, x: 62, y: 57 },
        ],
      },
      {
        shot: '/shots/sales/ekipman-talepler-telefon-light-tr.jpg',
        shotDark: '/shots/sales/ekipman-talepler-telefon-dark-tr.jpg',
        alt:
          'Aynı makine kartının devamı: son 12 ayda açılan talepler, kayıtlı işçilik ve bu ' +
          'makineye bağlı talepler',
        frame: 'phone',
        ratio: '780 / 1688',
        marks: [{ n: 3, x: 88, y: 43 }],
      },
      {
        shot: '/shots/sales/makale-light-tr.jpg',
        shotDark: '/shots/sales/makale-dark-tr.jpg',
        alt:
          'Bilgi bankası makalesi “VPN bağlantısı kopuyorsa”: belirti, çözüm; 5 kez önerildi, 3 ' +
          'talep önlendi',
        frame: 'card',
        ratio: '1250 / 445',
        title: 'Bilgi bankası',
        caption:
          'Talep yazılırken sistem ilgili çözümü önerir. Örnekteki “VPN bağlantısı kopuyorsa” ' +
          'makalesi 5 kez önerildi ve 3 talebi daha açılmadan önledi (örnek veri).',
      },
    ],
    items: [
      {
        n: 1,
        title: 'Makine kartı.',
        body:
          'Seri no, üretici, garanti bitişi, tedarikçi, satın alma bedeli. Etiketi okutmak kartı açar.',
      },
      { n: 2, title: 'Talep aç.', body: '“Bu varlık için talep aç” formu makine seçili açar.' },
      {
        n: 3,
        title: 'Bağlı talepler.',
        body: 'Son 12 ayda kaç talep açıldı, kaçı hâlâ açık, ne kadar işçilik harcandı.',
      },
      {
        n: 4,
        title: 'Planlı değişiklikler.',
        body: 'Makineyi etkileyen değişiklikler ve pencereleri aynı kartta.',
      },
    ],
  },

  // Slayt 11
  sla: {
    eyebrow: 'SLA (hizmet sözü)',
    title: 'Her talep için verilen söz: kaç dakikada yanıt, kaç saatte çözüm',
    lede:
      'SLA, bir talebe ne kadar sürede yanıt verileceğinin ve ne kadar sürede çözüleceğinin ' +
      'sözüdür. Süre yalnız fabrikanın mesai saatlerinde işler.',
    layout: 'side',
    shots: [
      {
        shot: '/shots/sales/sla-hedef-light-tr.jpg',
        shotDark: '/shots/sales/sla-hedef-dark-tr.jpg',
        alt:
          'SLA politikası “Standart”: Fabrika mesaisi takvimi, %80 uyarı eşiği ve acil, yüksek, ' +
          'normal, düşük öncelik için ilk yanıt ve çözüm süreleri',
        frame: 'card',
        ratio: '1143 / 1600',
        tall: true,
        marks: [
          { n: 1, x: 30, y: 41.5 },
          { n: 3, x: 72, y: 22 },
        ],
      },
      {
        shot: '/shots/sales/sla-takvim-light-tr.jpg',
        shotDark: '/shots/sales/sla-takvim-dark-tr.jpg',
        alt:
          'Fabrika mesaisi takvimi: hafta içi 08:00–18:00, cumartesi 08:00–13:00 ve resmî tatiller',
        frame: 'card',
        ratio: '1000 / 1010',
        marks: [{ n: 2, x: 80, y: 30 }],
      },
      {
        shot: '/shots/sales/sla-izleyici-light-tr.jpg',
        shotDark: '/shots/sales/sla-izleyici-dark-tr.jpg',
        alt:
          'Sistem izleyicileri: barkod sunucusu ve ERP arayüzü yanıt veriyor, depo terminali ' +
          'yanıt vermiyor',
        frame: 'card',
        ratio: '1300 / 470',
        marks: [{ n: 4, x: 85, y: 50 }],
      },
    ],
    items: [
      {
        n: 1,
        title: 'Öncelik başına iki süre.',
        body:
          'Örnek: acil talebe 30 dakikada yanıt, 4 saatte çözüm; normal talebe 4 saatte yanıt, ' +
          '1 günde çözüm.',
      },
      {
        n: 2,
        title: 'Fabrika mesaisi.',
        body:
          'Hafta içi 08:00–18:00, cumartesi 08:00–13:00; resmî tatiller düşülür. Gece 03:00’te ' +
          'açılan talep sabah 08:00’de saymaya başlar.',
      },
      {
        n: 3,
        title: 'Uyarı ve eskalasyon.',
        body:
          'Sürenin %80’inde uyarı, aşılınca yöneticiye ve nöbetçiye bildirim: uygulama, e-posta ' +
          've telefon bildirimi.',
      },
      {
        n: 4,
        title: 'Sistem izleyicileri.',
        body:
          'ERP, barkod sunucusu, depo terminali düzenli yoklanır; yanıt vermezse talep ' +
          'kendiliğinden açılır.',
      },
    ],
    note:
      'Saati yalnız ekibin talep sahibine yazdığı yanıt durdurur. Bekleme nedeni (tedarikçi, ' +
      'yedek parça, onay…) yazıldığında saat durur; kimse geriye çekemez. Vardiyaları ve tatil ' +
      'günlerini kurulumda biz tanımlarız.',
  },

  // Slayt 12
  slaReport: {
    eyebrow: 'SLA (hizmet sözü)',
    title: 'Sözün ne kadarının tutulduğu, birim birim',
    lede:
      'Panolar canlıdır; ayrıca rapor hazırlamak gerekmez. Herkes kendi birimlerinin ' +
      'rakamlarını görür, yöneticiler bütün fabrikayı.',
    layout: 'grid',
    shots: [
      {
        shot: '/shots/sales/sla-pano-light-tr.jpg',
        shotDark: '/shots/sales/sla-pano-dark-tr.jpg',
        alt:
          'SLA panosu (örnek veri): tutulan sözlerin oranı, aşılan, yaklaşan ve tutulan talep ' +
          'sayıları, birime göre talep çubukları',
        frame: 'card',
        ratio: '1600 / 875',
        marks: [
          { n: 1, x: 35, y: 10 },
          { n: 2, x: 35, y: 47 },
        ],
      },
      {
        shot: '/shots/sales/performans-light-tr.jpg',
        shotDark: '/shots/sales/performans-dark-tr.jpg',
        alt:
          'Performans paneli (örnek veri): olaylar ve hizmet istekleri ayrı; birime göre açılan, ' +
          'biten, ilk yanıt, çözüm süresi, memnuniyet ve SLA uyumu',
        frame: 'card',
        ratio: '1100 / 1480',
        marks: [{ n: 3, x: 66, y: 5.5 }],
      },
    ],
    items: [
      {
        n: 1,
        title: 'Tutulan sözlerin oranı',
        body: 've birime göre talep sayıları. Ekrandaki rakamlar örnek veridir.',
      },
      {
        n: 2,
        title: 'Birime ve hizmete göre',
        body: 'yoğunluk: en çok hangi hizmetten talep geliyor?',
      },
      {
        n: 3,
        title: 'Arızalar ve hizmet istekleri ayrı.',
        body:
          'Son 7, 30 ya da 90 gün: açılan, biten, ilk yanıt ve çözüm süresi, SLA uyumu, memnuniyet.',
      },
    ],
    note: '“Arızaları ne kadar sürede çözüyoruz?” sorusunun cevabı burada.',
  },

  // Slayt 13
  people: {
    eyebrow: 'Kişiler ve iş yükü',
    title: 'Herkes kendi iş listesini, yöneticiler kimde ne olduğunu görür',
    lede:
      'Bir talebe atanmak, kişinin Ana sayfasında bir görev demektir. Görevi tamamlamak talebi çözer.',
    layout: 'phones',
    shots: [
      {
        shot: '/shots/sales/ana-sayfa-telefon-light-tr.jpg',
        shotDark: '/shots/sales/ana-sayfa-telefon-dark-tr.jpg',
        alt:
          'Telefonda Ana sayfa: ay takvimi ve altında geciken görevler; ilki #101 numaralı ' +
          'talepten gelen görev',
        frame: 'phone',
        ratio: '780 / 1688',
        marks: [{ n: 1, x: 72, y: 70 }],
      },
      {
        shot: '/shots/sales/devamsizlik-light-tr.jpg',
        shotDark: '/shots/sales/devamsizlik-dark-tr.jpg',
        alt:
          'Devamsızlıklar ekranı: Bakım ve Bilgi İşlem nöbet kartları, Bakım’da Kerem Bakım ' +
          'izinde ve nöbette Barış Saha; altında önümüzdeki 90 günün devamsızlıkları',
        frame: 'card',
        ratio: '1600 / 1000',
        marks: [
          { n: 2, x: 40, y: 56 },
          { n: 3, x: 62, y: 23 },
        ],
        title: 'Devamsızlık ve nöbet',
        caption:
          'Bakım biriminde nöbet sırası Kerem Bakım’daydı; izinde olduğu için nöbeti Barış Saha ' +
          'tutuyor. Bu sırada Kerem’e otomatik iş atanmaz.',
      },
    ],
    items: [
      {
        n: 1,
        title: 'Kendi iş listesi.',
        body:
          'Atanan talep Ana sayfada numarası ve konusuyla belirir; son tarihi talebin süresinden ' +
          'gelir, gecikenler en üstte.',
      },
      {
        n: 2,
        title: 'Dengeli atama.',
        body:
          'İş sırayla ya da en az işi olan kişiye verilir. Devamsızlık yazan kişiye otomatik iş gitmez.',
      },
      {
        n: 3,
        title: 'Nöbet.',
        body:
          'Birimin nöbet listesi kurulumda tanımlanır; nöbetçi izindeyse sıradaki kişi devralır.',
      },
      {
        n: 4,
        title: 'Birimlerim.',
        body:
          'Birden çok birimde çalışan kişi, bütün birimlerinin açık taleplerini tek listede görür; ' +
          'süresi aşılanlar önce.',
      },
    ],
  },

  // Slayt 14
  statuses: {
    eyebrow: 'Kişiler ve iş yükü',
    title: 'Bir talebin durumları ve talep sahibinin gördüğü',
    lede:
      'Ekip ayrıntılı durumu görür; talep sahibine sade bir karşılığı gösterilir. İç ayrıntılar ' +
      '(kimin onayı beklendiği gibi) dışarı çıkmaz.',
    teamLabel: 'Ekibin gördüğü',
    requesterLabel: 'Talep sahibinin gördüğü',
    states: [
      { team: 'Yeni', requester: 'Alındı', tone: 'progress' },
      { team: 'İnceleniyor', requester: 'İşleme alındı', tone: 'progress' },
      { team: 'Devam ediyor', requester: 'İşleme alındı', tone: 'progress' },
      { team: 'Çözüldü', requester: 'Çözüldü', tone: 'done' },
      { team: 'Kapandı', requester: 'Kapandı', tone: 'done' },
    ],
    waiting: {
      title: 'Beklemede',
      hint: '(neden yazmak zorunludur; beklerken SLA saati durur)',
      reasons: ['Talep sahibinden bilgi', 'Tedarikçi', 'Yedek parça', 'Onay', 'Planlı pencere'],
      body:
        'Talep sahibi bilgi beklendiğinde “Sizden bilgi bekleniyor”, onay beklendiğinde “Onay ' +
        'bekleniyor”, diğerlerinde “İşleme alındı” görür. Cevabı yazdığı anda talep ' +
        'kendiliğinden “Devam ediyor”a döner ve saat yeniden işler.',
    },
    after: {
      title: 'Çözüldükten sonra',
      body:
        'Talep sahibi “Çözüldü, onaylıyorum” der ya da “Hâlâ sorun var” diyerek yeniden açar. ' +
        'Talep kapanınca memnuniyet anketi gelir. Gereksiz talep “İptal” edilir; iptal ve ' +
        'kapatma geri alınamaz.',
    },
  },

  // Slayt 15
  intake: {
    eyebrow: 'Dışarıdan talep',
    title: 'Müşteri, bayi ya da tedarikçi hesap açmadan talep iletebilir',
    lede:
      'Satış sonrası hizmet veren fabrikalar için: dışarıdan gelen talep de içeridekiyle aynı ' +
      'listeye, aynı süre takibine girer.',
    channels: [
      {
        icon: 'link',
        title: 'Kurum dışı talep formu',
        body:
          'Bir hizmet için süreli bir bağlantı paylaşırsınız. Hesap gerekmez; fotoğraf ya da PDF eklenebilir.',
      },
      {
        icon: 'mail',
        title: 'E-posta',
        body:
          'Destek adresine gelen e-posta talebe dönüşür. Yanıtlar, konu değişse bile aynı talebe eklenir.',
      },
      {
        icon: 'building',
        title: 'Firma portalı',
        body: 'Sözleşmeli firmaların kişileri kendi şifreleriyle girer, firmanın bütün taleplerini görür.',
      },
      {
        icon: 'phone-call',
        title: 'Telefon',
        body: 'Arayan kişinin adına talebi ekip açar; kişiye takip bağlantısı e-postayla gider.',
      },
    ],
    shot: {
      shot: '/shots/sales/portal-form-light-tr.jpg',
      shotDark: '/shots/sales/portal-form-dark-tr.jpg',
      alt:
        'Demir Çelik Fabrikası’nın bilgisayar arızası formu: e-posta, konu, açıklama, fotoğraf ' +
        'veya belge ve Gönder düğmesi',
      ratio: '1420 / 1600',
      caption: 'Müşterinin gördüğü form',
    },
    note:
      'Bağlantının süresi dolar ya da istendiğinde durdurulur. Dışarıdan gelen dosya “dışarıdan ' +
      'geldi” işaretiyle gelir; sunucuda virüs taraması açılabilir.',
  },

  // Slayt 16
  portal: {
    eyebrow: 'Dışarıdan talep',
    title: 'Talep sahibi, talebinin nerede olduğunu kendisi görür',
    lede: 'Müşteri “talebim ne oldu?” diye aramak zorunda kalmaz.',
    layout: 'phones',
    shots: [
      {
        shot: '/shots/sales/firma-portali-telefon-light-tr.jpg',
        shotDark: '/shots/sales/firma-portali-telefon-dark-tr.jpg',
        alt:
          'Telefonda firma portalı: #206 numaralı talebin durumu “İşleme alındı” ve yazışması; ' +
          'yanıtlar “Destek ekibi” adıyla görünür',
        frame: 'phone',
        ratio: '780 / 1688',
        title: 'Firma portalı',
        marks: [
          { n: 1, x: 88, y: 30 },
          { n: 3, x: 88, y: 58 },
        ],
      },
      {
        shot: '/shots/sales/portal-takip-telefon-light-tr.jpg',
        shotDark: '/shots/sales/portal-takip-telefon-dark-tr.jpg',
        alt:
          'Telefonda takip sayfası: “Vardiya amiri dizüstü ekranı kırık” talebinin numarası, ' +
          'durumu ve son güncellemesi',
        frame: 'phone',
        ratio: '780 / 1688',
        title: 'Takip bağlantısı',
        marks: [{ n: 2, x: 88, y: 31 }],
      },
      {
        shot: '/shots/sales/firmalar-light-tr.jpg',
        shotDark: '/shots/sales/firmalar-dark-tr.jpg',
        alt:
          'Firmalar ekranı: Anadolu Otomotiv, Ege Döküm, Kuzey Makine, Marmara Lojistik ve ' +
          'Trakya Otomotiv Yan Sanayi',
        frame: 'card',
        ratio: '1600 / 667',
        title: 'Firmalar ekranı',
        marks: [{ n: 4, x: 85, y: 23 }],
      },
    ],
    items: [
      {
        n: 1,
        title: 'Firma portalı.',
        body:
          'Anadolu Otomotiv’in kişileri firmanın bütün taleplerini görür, yanıt yazar, dosya ekler ' +
          've yeni talep açar.',
      },
      {
        n: 2,
        title: 'Hesabı olmayan kişi',
        body: 'kendisine gelen takip bağlantısından durumu ve son güncellemeyi görür.',
      },
      {
        n: 3,
        title: 'İç bilgi içeride kalır.',
        body:
          'İç notlar, ekibin kendi aralarındaki yazışma ve onaylayanın kim olduğu dışarıya hiç görünmez.',
      },
      {
        n: 4,
        title: 'Firmalar ekranı.',
        body:
          'Firma eklenir, kişileri davet edilir; firmadan ayrılan kişinin erişimi tek dokunuşla kapatılır.',
      },
      {
        n: 5,
        title: 'Kapanışı talep sahibi onaylar.',
        body:
          '“Çözüldü, onaylıyorum” ya da “Hâlâ sorun var” der; talep kapanınca memnuniyet anketi gelir.',
      },
    ],
  },

  // Slayt 17
  security: {
    eyebrow: 'Fabrika için',
    title: 'Sahada, sizin kurallarınızla ve sizin verinizle çalışır',
    shot: {
      shot: '/shots/sales/kuyruk-telefon-light-tr.jpg',
      shotDark: '/shots/sales/kuyruk-telefon-dark-tr.jpg',
      alt: 'Telefonda Bakım biriminin talep listesi: diğer birimlerdeki SLA uyarısı ve Bakım’ın talepleri',
      ratio: '780 / 1688',
    },
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
        key: 'pilot',
        icon: 'rocket',
        accent: 'warning',
        title: 'Önce bir birimle başlayın',
        body:
          'Önerimiz: Bakım gibi tek bir birimle birkaç haftalık deneme, ardından diğer birimler. ' +
          'Paket, kişi ve birim sayınıza göre belirlenir.',
      },
    ],
  },

  // ── Ayrıca ──────────────────────────────────────────────────────────────
  extras: {
    eyebrow: 'Ayrıca',
    title: 'Talep yönetiminin yanında, aynı sistemde',
    lede: 'Günlük işler, Active Directory ile giriş (pilot) ve toplantı notları da aynı uygulamada.',
  },

  workspace: {
    eyebrow: 'Günlük işler',
    title: 'Görevler, projeler, notlar ve dosyalar',
    body:
      'Birimler günlük işlerini de burada yürütür. Talepten gelen görev ile kişinin kendi ' +
      'görevi aynı listededir; göreve dosya ve not eklenir.',
    points: [
      'Geciken, bugünkü ve bu haftaki işler tek listede; ay takvimi hemen yanında',
      'Hatırlatıcılar telefon sessizdeyken bile çalar',
      'Google Takvim ile iki yönlü eşitleme; iPhone ve Mac’te Apple Takvim’e de yazılır',
    ],
    shot: '/shots/ee/work-home-light-tr.jpg',
    shotDark: '/shots/ee/work-home-dark-tr.jpg',
    alt:
      'Ana sayfa: geciken, bugünkü ve bu haftaki görevler proje ve etiket rozetleriyle tek ' +
      'listede; sağda ay takvimi',
    frameLabel: 'sirketiniz.alliswell.space — görevler',
  },

  workspaceTabs: {
    eyebrow: 'Birlikte çalışma',
    title: 'Pano, projeler, notlar ve dosyalar',
    lede: 'Kimi liste ister, kimi pano. İkisi de aynı işin farklı görünümüdür.',
    tabs: [
      {
        id: 'board',
        label: 'Pano',
        shot: '/shots/ee/work-board-light-tr.jpg',
        shotDark: '/shots/ee/work-board-dark-tr.jpg',
        alt: 'Pano görünümü: açık, devam eden, bekleyen ve tamamlanan sütunlarında görev kartları',
        caption: 'İşler sütunlar hâlinde; kartlar sürüklenerek taşınır.',
        frameLabel: 'sirketiniz.alliswell.space — pano',
      },
      {
        id: 'projects',
        label: 'Projeler',
        shot: '/shots/ee/work-projects-light-tr.jpg',
        shotDark: '/shots/ee/work-projects-dark-tr.jpg',
        alt: 'Projeler ekranı: renk ve ilerleme bilgisiyle proje kartları',
        caption: 'Her proje kendi görevleri, notları ve dosyalarıyla bir arada.',
        frameLabel: 'sirketiniz.alliswell.space — projeler',
      },
      {
        id: 'notes',
        label: 'Notlar',
        shot: '/shots/ee/work-notes-light-tr.jpg',
        shotDark: '/shots/ee/work-notes-dark-tr.jpg',
        alt: 'Notlar ekranı: sabitlenmiş notlar ve projelere bağlı notlar',
        caption: 'Talimatlar ve prosedürler; başlık, tablo ve resimle yazılır, PDF olarak dışa aktarılır.',
        frameLabel: 'sirketiniz.alliswell.space — notlar',
      },
      {
        id: 'files',
        label: 'Dosyalar',
        shot: '/shots/ee/work-files-light-tr.jpg',
        shotDark: '/shots/ee/work-files-dark-tr.jpg',
        alt: 'Dosyalar ekranı: klasörler ve yüklenmiş kurumsal belgeler',
        caption: 'Klasörlerle düzenlenen belge arşivi; her dosya bağlı olduğu işi gösterir.',
        frameLabel: 'sirketiniz.alliswell.space — dosyalar',
      },
    ],
  },

  identity: {
    eyebrow: 'Active Directory ile giriş',
    title: 'Kullanıcılar mevcut Active Directory yapınızdan gelir',
    body:
      'Ayrı bir kullanıcı listesi tutmazsınız. Dizindeki gruplar birimlere eşlenir; işe giren ' +
      `kişinin hesabı açılır, ayrılanınki aynı gün kapanır. ${pilotNote('directory', 'tr')}`,
    points: [
      'Çalışanlar zaten kullandıkları kurumsal şifreyle girer',
      'Grup üyelikleri birimleri belirler; elle atama gerekmez',
    ],
    shot: '/shots/ee/team-identity-light-tr.jpg',
    shotDark: '/shots/ee/team-identity-dark-tr.jpg',
    alt:
      'Kimlik kaynakları ekranı: bir Active Directory bağlantısı ve bir Microsoft Entra ID ' +
      'sağlayıcısı etkin; bir sağlayıcı eksik ayarlarını adıyla söylüyor',
    frameWidth: '30rem',
    frameLabel: 'sirketiniz.alliswell.space — kimlik',
  },

  meetings: {
    eyebrow: 'Toplantı notları',
    title: 'Toplantı kaydını yükleyin, kararları talep olarak alın',
    body:
      'Ses kaydından konuşmacıları ayrılmış bir tutanak, özet ve kararlar listesi çıkar. Her ' +
      'karar tek dokunuşla bir talebe ya da göreve dönüşür.',
    points: [
      'Deşifre için sizin seçtiğiniz yapay zekâ sağlayıcısı ve sizin hesabınız kullanılır',
      'Tutanak düzenlenebilir bir nottur; yanlış duyulan cümle elle düzeltilir',
      'Bulutta Business ve Enterprise paketlerinde; aylık deşifre dakikası paketle belirlenir',
    ],
    shot: '/shots/ee/meeting-named-light-tr.jpg',
    shotDark: '/shots/ee/meeting-named-dark-tr.jpg',
    alt: 'Bir toplantı notu: konuşmacılar adlandırılmış, özet ve içinden çıkarılmış kararlar',
    frameLabel: 'sirketiniz.alliswell.space — toplantı',
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
      'Bu sayfadaki anlatım, 18 sayfalık bir PDF olarak. Bilgi işlem, bakım ve üretim ' +
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
          { label: 'Talep yönetimi', href: '#itsm' },
          { label: 'SLA (hizmet sözü)', href: '#sla' },
          { label: 'Dışarıdan talep', href: '#intake' },
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
  fallback: {
    contact: 'Bize yazın:',
    other: 'English',
    home: 'alliswell.space',
  },
};
