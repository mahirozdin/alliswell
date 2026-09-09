/**
 * Enterprise sayfasının bütün metni, Türkçe (EE-151).
 *
 * İngilizce ikizi `content.en.js`; ikisinin aynı anahtar ağacını taşıdığını bir
 * gelenek değil bir kapı garanti ediyor (`npm run check:copy`, EE-152). Neyin
 * iddia edilebileceğine dair dört kural İngilizce dosyanın başlığında yazılı ve
 * burada da geçerli — özellikle: paket bir takıma satılanı anlatır, her
 * özelliğin etrafındaki sert sınırı değil; yönlendirme bir kural motoru değil;
 * müşterinin açamadığı bir ekran özellik değildir; ve yalnız ölçülmüş rakam
 * yazılır.
 *
 * Ekran görüntüsü yolları BÜTÜN olarak saklanır (`/shots/ee/...`), asla
 * birleştirilmez: CI kapısı derlenmiş paketi bu dizgiler için tarıyor ve
 * çalışma zamanında kurulan bir yolu göremez.
 */

export const APP_URL = '/app';
export const REPO_URL = 'https://github.com/mahirozdin/alliswell';

export default {
  lang: 'tr',

  seo: {
    title: 'AllisWell Enterprise — kendi sunucunuzda servis masası, birimler ve SLA',
    description:
      "Team'ler, subdomain, izinler, birimler, SLA'lı ve sağlık izlemeli ITSM, public talep " +
      "portalı ve toplantı notu AI'ı — kendi veritabanınızda, çevrimdışı çalışan bir kurulum.",
    ogImage: '/shots/og/enterprise-tr.jpg',
  },

  nav: {
    home: '/',
    links: [
      { label: 'Servis masası', href: '#itsm' },
      { label: 'SLA', href: '#sla' },
      { label: 'Kimlik', href: '#identity' },
      { label: 'Paketler', href: '#packages' },
    ],
    cta: { label: 'İletişime geçin', href: '#contact' },
    starsLabel: 'Yıldız',
  },

  hero: {
    eyebrow: 'AllisWell Enterprise',
    title: 'Kendi sunucunuzda çalışan bir servis masası',
    lede:
      "Team'ler, birimler ve izinler. Verdiği sözü duvar saatine göre değil iş takvimine göre " +
      'ölçen bir servis kataloğu. Hesabı olmayan — ve olmasına gerek olmayan — insanlar için ' +
      'public bir talep formu. Kendi donanımınıza, kendi veritabanınıza kurulur; ve sahadaki ' +
      'Wi-Fi çalışmadığında da çalışmaya devam eder.',
    primary: { label: 'İletişime geçin', href: '#contact' },
    secondary: { label: 'Nasıl kurulur', href: '#ops' },
    shot: '/shots/ee/hero-light-tr.jpg',
    shotDark: '/shots/ee/hero-dark-tr.jpg',
    alt:
      'Yan yana iki ekran: öncelik ve SLA durumlarıyla bir birimin talep kuyruğu, ve 47 talebin ' +
      "%76,2'sinde sözün tutulduğunu birim ve servis kırılımlarıyla gösteren SLA panosu",
  },

  personas: {
    eyebrow: 'Kimin için',
    title: 'Üç farklı kurum, tek bir şekil',
    items: [
      {
        key: 'internal',
        icon: '🏭',
        title: 'Birbirine iş açan departmanlar',
        body:
          'Muhasebe, bakım, bilgi işlem, kalite, lojistik — her biri kendi işi ve kendi gelen ' +
          'kutusu olan bir birim, ve hepsi birbirine talep açıyor. Bugün bu trafik ortak bir ' +
          'mailbox ile birinin excel dosyasında yaşıyor, ve "şu an bakımda kaç açık talep var" ' +
          'sorusuna bakıma sormadan kimse cevap veremiyor.',
      },
      {
        key: 'msp',
        icon: '🤝',
        title: 'Başka firmalara destek veren firmalar',
        body:
          'Müşterilerinizin hesap açmadan size ulaşması gerekiyor, sözleşmeleriniz yanıt ' +
          'süresi yazıyor, ve kaçırmanın bir bedeli var. Müşteri başına yayınlanmış bir form, ' +
          'cevaplayan birime yönlenen bir talep, ve hatırlanan değil ölçülen bir söz.',
      },
      {
        key: 'regulated',
        icon: '🔐',
        title: 'Yaptığını belgelemek zorunda olan kurumlar',
        body:
          'Kamu kurumları, hastaneler, KVKK ya da GDPR kapsamındaki herkes: veri sizin ' +
          'kontrol ettiğiniz donanımda kalıyor, her değişikliğin karşısında bir isim var, ve ' +
          'hesaplar zaten işlettiğiniz dizinden geliyor — yani işten ayrılan biri erişimini ' +
          'aynı gün kaybediyor.',
      },
    ],
  },

  proof: {
    eyebrow: 'İddia değil, ölçüm',
    title: 'Anlatmak yerine gösterebildiklerimiz',
    items: [
      {
        value: '1.000.000',
        label: 'kayıtlık kıyaslama süiti',
        note: 'Uyum panosu CI\'da bir milyon satırlık bir masaya karşı ölçülüyor.',
      },
      {
        value: '49',
        label: 'adlı izin, üç kapıda birden zorlanıyor',
        note: 'REST, cihaz senkronu ve AI bağlayıcısı tek defteri okuyor; boşlukta CI kırmızı.',
      },
      {
        value: '2',
        label: 'dil, en alta kadar',
        note: 'Ekranlar, e-postalar ve public talep formu — her birinde 634 anahtar.',
      },
      {
        value: '6',
        label: 'platform, tek kod tabanından',
        // Six proper nouns; translating them would invent products.
        note: 'iOS, Android, web, macOS, Windows, Linux.', // i18n-same
      },
      {
        value: '0',
        label: 'bayt ağınızın dışına çıkıyor',
        note: 'Siz bir şey bağlamadıkça; bağlarsanız da yalnız bağladığınız kadar.',
      },
    ],
  },

  portal: {
    eyebrow: 'Public talep portalı',
    title: 'Şirketinizin dışından biri bir şey istiyor. Hesabı yok.',
    lede:
      'Bir tedarikçiye kullanıcı hesabı açmak genelde yanlış cevaptır, ortak bir mailbox ise ' +
      'zaten cevap değildir. Bir takım, cevaplayan birime yönlenen public bir adreste talep ' +
      'formu yayınlar — ve o noktadan sonrası, kendi personelinizin çalıştığı sistemin ta ' +
      'kendisidir.',
    steps: [
      {
        n: 1,
        title: 'Bir yönetici form yayınlar',
        body:
          'Form tek bir servise, birden fazla birim o servisi veriyorsa tek bir birime ' +
          'bağlanır. Süresi, duraklatan bir anahtarı, ne kadar kullanılabileceğine dair bir ' +
          'kotası ve kalıcı bir iptali vardır. Adres yalnız bir kez gösterilir: sunucu ondan ' +
          'yalnız bir özet saklar, yani sızan bir bağlantı öldürülebilir ama geri alınamaz.',
        shot: '/shots/ee/portal-links-light-tr.jpg',
        shotDark: '/shots/ee/portal-links-dark-tr.jpg',
        alt:
          'Portal bağlantıları ekranı: servisi, süresi ve kota kullanımıyla dört yayınlanmış ' +
          'form; iptal edilen bağlantıda kontroller tamamen kayboluyor',
        frameLabel: 'takiminiz.alanadiniz — talep formları',
      },
      {
        n: 2,
        title: 'Bir yabancı formu doldurur',
        body:
          'Hesap yok, uygulama yok, JavaScript de yok — sayfa sunucuda çiziliyor ve içerik ' +
          'politikası betiği tamamen yasaklıyor, çünkü bu ürünün kimlik istemeden açılan tek ' +
          'kapısı. Dilini tarayıcıdan seçiyor, ve bizim değil sizin adınızı, logonuzu ve ' +
          'renginizi taşıyor.',
        shot: '/shots/ee/portal-form-light-tr.jpg',
        shotDark: '/shots/ee/portal-form-dark-tr.jpg',
        alt:
          'Public talep formu: firma adı, servis, e-posta alanı, konu, açıklama ve bu servisin ' +
          'sorduğu iki özel alan',
        frameLabel: 'takiminiz.alanadiniz/p/…',
      },
      {
        n: 3,
        title: 'Talep, cevaplandığı yere düşer',
        body:
          'Servis hangi birimin cevapladığını söyler, talep de o birimin kuyruğuna gider. Bu ' +
          'zekice değil, bilinçli: yapılandırılacak bir kural motoru yok ve hiçbir şey tahmin ' +
          'edilmiyor. Kimsenin cevaplamadığı bir servis hiçbir şey alamaz, birden fazla birimin ' +
          'verdiği bir servis ise yanlış masaya gönderilmek yerine reddedilir.',
      },
      {
        n: 4,
        title: 'Saat başlar, ve birime bir kez haber verilir',
        body:
          'O servise bağlı SLA politikası bir ilk-yanıt saati ve bir çözüm saati açar. Birime ' +
          'talep başına değil toplu tek bir bildirim gider — bir öğleden sonra kırk talep alan ' +
          'bir masa, kırk e-posta değil bir liste alır.',
      },
      {
        n: 5,
        title: 'Soran kişi takip edebilir',
        body:
          'Bir onay ve bir bağlantı alır. Arkasındaki sayfa konuyu, durumu ve iki tarihi ' +
          'gösterir — ve durum sizinkinden bilerek daha kabadır: yedi durumunuz beşe iner, ' +
          'çünkü "talebinizi iptal ettik" bir insanın yapacağı konuşmadır, bir durum sayfasının ' +
          'kıracağı bir haber değil.',
        shot: '/shots/ee/portal-follow-light-tr.jpg',
        shotDark: '/shots/ee/portal-follow-dark-tr.jpg',
        alt:
          'Takip sayfası: talebin konusu, "Alındı" durumu, ve gönderildiği ile son ' +
          'güncellendiği tarihler',
        frameLabel: 'takiminiz.alanadiniz/t/…',
      },
    ],
    aside: {
      title: 'Açık kapı olduğu için öyle muamele görüyor',
      body: 'Dört katman, ve hiçbiri meşru bir ziyaretçiden bir şey istemiyor:',
      points: [
        'Gözden, klavyeden ve ekran okuyucudan aynı anda gizlenmiş bir tuzak alan.',
        'Adres başına bir tavan ve form başına ikinci bir tavan — çünkü bir botnet\'in çok adresi, tek hedefi vardır.',
        'Hiçbir iş yapılmadan önce kontrol edilen ve yalnız talep kabul edilirse harcanan aylık kota; yani reddedilen spam takıma hiçbir şeye mal olmuyor.',
        'Kapalı başarısız olan isteğe bağlı bir doğrulama, ve askıdaki bir takımın yeni kimseyi kabul etmemesi.',
        'Her ret — yanlış host, bilinmeyen bağlantı, süresi dolmuş, iptal edilmiş, duraklatılmış — aynı sayfayla cevaplanıyor, yani bir tarayıcı aradaki farktan hiçbir şey öğrenemiyor.',
      ],
    },
  },

  itsm: {
    id: 'itsm',
    eyebrow: 'Servis masası',
    title: 'Bir birimin gerçekten çalıştığı kuyruk',
    body:
      'Talep birine verilmiş bir sözdür; görev ise bir listedeki iştir. İkisini ayrı şeyler ' +
      'tutmak, bir talebin atanmış işe dönüşürken soran kişiyle bağını koparmamasını sağlar. ' +
      'Öncelik, durum ve sözün hâli her satırda — bir fabrika sahasında telefonla çekilmiş ' +
      'bir ekran fotoğrafında bile okunacak şekilde.',
    points: [
      'Sunucunun zorladığı geçiş haritasıyla yedi durum — ve kapandıktan sonra yeniden açma yok: geri gelen bir konu, eskisine bağlı YENİ bir taleptir',
      'Çevrimdışı çalışır. Kuyruk cihazdadır; ağ geri gelmeden okunur ve düzenlenir',
      'Bir talepten çok görev çıkabilir; bir görev en fazla bir talebe aittir',
    ],
    shot: '/shots/ee/ticket-queue-light-tr.jpg',
    shotDark: '/shots/ee/ticket-queue-dark-tr.jpg',
    alt:
      'Bir birimin talep kuyruğu: öncelik noktaları, durum, SLA hâli ve atanan kişilerle dört ' +
      'talep; biri SLA aşıldı, biri sözü tutulmuş olarak kapanmış',
    frameLabel: 'takiminiz.alanadiniz — talepler',
  },

  itsmTabs: {
    eyebrow: 'Ve masanın geri kalanı',
    title: 'Ne istenebilir, kim cevaplar, ve ne olmuş',
    lede:
      'Katalog, çoğu servis masasının atladığı kısımdır — ve geri kalanı çalıştıran da odur: ' +
      'bir servis adı taşıyan talep, insan okumadan yönlendirilebilir.',
    tabs: [
      {
        id: 'catalogue',
        label: 'Katalog',
        shot: '/shots/ee/services-admin-light-tr.jpg',
        shotDark: '/shots/ee/services-admin-dark-tr.jpg',
        alt: 'Servis kataloğu: cevaplayan birimleriyle servisler, biri arşivlenmiş',
        caption:
          'Her servis kendi sorularını sorabilir — küçük ve kapalı bir alan tipi kümesiyle, ' +
          'yani bir form form olarak kalıyor, bir programlama diline dönüşmüyor.',
        frameLabel: 'takiminiz.alanadiniz — servisler',
      },
      {
        id: 'routing',
        label: 'Kim cevaplıyor',
        shot: '/shots/ee/service-routing-light-tr.jpg',
        shotDark: '/shots/ee/service-routing-dark-tr.jpg',
        alt: 'Bir servisin, onu cevaplayan birimlere yönlendirilmesi',
        caption:
          'Kimseye yönlendirilmemiş bir servis, umutla bir yerde kuyruğa alınmak yerine ' +
          'reddediliyor. O ret bir özelliktir.',
        frameLabel: 'takiminiz.alanadiniz — yönlendirme',
      },
      {
        id: 'detail',
        label: 'Bir talep',
        shot: '/shots/ee/ticket-detail-light-tr.jpg',
        shotDark: '/shots/ee/ticket-detail-dark-tr.jpg',
        alt:
          'Açılmış bir talep: konuşma, ve bir renk tonu, bir kilit ve "talep sahibi bunu ' +
          'göremez" sözleriyle işaretlenmiş iç not',
        caption:
          'İç not aynı anda üç şekilde işaretleniyor: renk, renk körü bir okuyucuda; ikon, ' +
          'kirli bir ekrana şöyle bir bakışta; kelime ise en kolay atlanan.',
        frameLabel: 'takiminiz.alanadiniz — talep',
      },
    ],
  },

  sla: {
    id: 'sla',
    eyebrow: 'SLA ve servis sağlığı',
    title: 'Duvar saatine göre değil, sizin takviminize göre ölçülen bir söz',
    body:
      'Bir fabrika 18:00\'de durmaz, ve üç vardiyalı bir güne göre ölçülen hedef, dokuz-beşe ' +
      'göre ölçülenden başka bir sayıdır. Yanıt ve çözüm hedefleri çalışma saatlerine, resmî ' +
      'tatillere ve takımın kendi saat dilimine göre işler — ve bir gece vardiyası iki değil ' +
      'tek satırdır, çünkü 22:00–06:00 gece yarısından ikiye bölünmüş iki parça değil, tek ' +
      'bir aralıktır.',
    points: [
      'Saat çıkarma değil biriktirme yapıyor, yani bir talebi "beklemede"ye atıp geri almak sözü sıfırlamıyor',
      '%80\'de uyarı, talep kapandıktan sonra bile yapışkan kalan ihlal, ve geçen süreyle değil ÇALIŞMA dakikalarıyla sayılan eskalasyon',
      'Çalışma saatlerinizi düzenlemek bundan sonrasını değiştirir, olmuş olanı asla: hedef ve takvim, saat başlarken saatin üzerine donduruluyor',
    ],
    shot: '/shots/ee/sla-dashboard-light-tr.jpg',
    shotDark: '/shots/ee/sla-dashboard-dark-tr.jpg',
    alt:
      "SLA panosu: 47 talebin %76,2'sinde söz tutulmuş; birim ve servis kırılımları, ve altta " +
      'aşılan hedeflerin listesi',
    frameLabel: 'takiminiz.alanadiniz — SLA',
  },

  slaTabs: {
    eyebrow: 'Sözün parçaları',
    title: 'Hedefler, çalışma saatleri, ve zaten izlediğiniz o adres',
    lede:
      'Ve bilerek "hiçbir şey" olmasına izin verilen bir sayı: henüz hiçbir sözün vadesi ' +
      'gelmemiş bir masa, neşeli bir yüzde yüz yerine bir tire gösterir.',
    tabs: [
      {
        id: 'targets',
        label: 'Hedefler',
        shot: '/shots/ee/sla-policies-light-tr.jpg',
        shotDark: '/shots/ee/sla-policies-dark-tr.jpg',
        alt: 'Önceliğe göre ilk yanıt ve çözüm hedefleriyle SLA politikaları',
        caption:
          'Öncelik başına ilk yanıt ve çözüm. Takvimi olmayan bir politika 7/24 demektir — ' +
          'eksik bir ayar değil, gerçek bir taahhüt.',
        frameLabel: 'takiminiz.alanadiniz — SLA politikaları',
      },
      {
        id: 'calendar',
        label: 'Çalışma saatleri',
        shot: '/shots/ee/sla-calendars-light-tr.jpg',
        shotDark: '/shots/ee/sla-calendars-dark-tr.jpg',
        alt: 'Çalışma aralıkları ve resmî tatilleriyle bir iş takvimi',
        caption:
          'Takvim başına saatler, tatiller ve bir saat dilimi. Yaz saati yaklaşık olarak değil ' +
          'gerçekten ele alınıyor, ve içinde hiç saat olmayan bir takvim reddediliyor.',
        frameLabel: 'takiminiz.alanadiniz — takvimler',
      },
      {
        id: 'health',
        label: 'Servis sağlığı',
        shot: '/shots/ee/sla-monitors-light-tr.jpg',
        shotDark: '/shots/ee/sla-monitors-dark-tr.jpg',
        alt: 'Servis adreslerini izleyen sağlık kontrolleri, aralıkları ve son sonuçlarıyla',
        caption:
          'İzlenen bir adres düştüğünde tek bir olay kaydı açılıyor, bir dakika sonra ikincisi ' +
          'açılmıyor. Geri geldiğinde de düzelme aynı kaydın üzerine yazılıyor.',
        frameLabel: 'takiminiz.alanadiniz — sağlık',
      },
    ],
  },

  org: {
    id: 'org',
    eyebrow: 'Organizasyon',
    title: 'Birimler bir klasör değil, şirketin şeklidir',
    body:
      'Birim bir departman, bir atölye, bir saha — sizinkinin gerçekte hangi şekli varsa o. ' +
      'Birimler kendi içeriklerinin ve kendi gelen kutularının sahibidir, ve içerik kişiyi ' +
      'değil birimi izler; yani masası değişen biri bir yıllık talebi yanında götürmez. Her ' +
      'takımın kendi adresi vardır, ve başka bir takımın verisine yapılan istek, o takımın ' +
      'var olduğunu bile kabul etmeyen düz bir 404 ile döner.',
    points: [
      'Birimler arası paylaşım açıktır, belirli bir şey için verilir, ve geri alındığında karşı tarafta kaybolur',
      'Bir cihaz tam olarak sahibinin ait olduğu birimleri senkronlar — sınır, gizlenenle değil GELENLE korunur',
      'Bir takımın adresine kayıt yalnız davetlidir, ve akışın tamamı hiç mail sunucusu olmayan bir kurulumda tamamlanır',
    ],
    shot: '/shots/ee/units-admin-light-tr.jpg',
    shotDark: '/shots/ee/units-admin-dark-tr.jpg',
    alt:
      'Birimler ekranı: üye sayılarıyla dört birim; biri sizin yönettiğiniz olarak işaretli, ' +
      'biri arşivlenmiş',
    frameLabel: 'takiminiz.alanadiniz — birimler',
  },

  orgTabs: {
    eyebrow: 'İzinler, ve kayıt',
    title: 'Kim ne yapabilir, ve kim ne yapmış',
    lede:
      'Erişim, üç sabit rolle değil adlı izinlerle tanımlanıyor; yani "bakım şefi kendi ' +
      'biriminde yeniden atama yapabilir ama talebi kapatamaz" cümlesi bir yöneticinin ' +
      'yazdığı bir şey oluyor, bizden özellik istediği bir şey değil.',
    tabs: [
      {
        id: 'roles',
        label: 'Roller',
        shot: '/shots/ee/team-roles-light-tr.jpg',
        shotDark: '/shots/ee/team-roles-dark-tr.jpg',
        alt: 'Rol düzenleyici: roller boyunca adlı izinlerden oluşan bir yetki matrisi',
        caption:
          'Özel roller tam bir küme olarak değil, bir tabandan FARK olarak saklanıyor; yani ' +
          'daralttığınız bir rol, sonradan eklenen her izni yine de alıyor.',
        frameLabel: 'takiminiz.alanadiniz — roller',
      },
      {
        id: 'delegated',
        label: 'Devredilmiş görünüm',
        shot: '/shots/ee/units-manager-light-tr.jpg',
        shotDark: '/shots/ee/units-manager-dark-tr.jpg',
        alt: 'Aynı birimler ekranı, devredilmiş bir yöneticinin gördüğü hâliyle',
        caption:
          'Birinin yapamayacağı şey, soluklaştırılmış değil YOK. Devre dışı bir kontrol bile ' +
          'bir yeteneğin sözünü verir.',
        frameLabel: 'takiminiz.alanadiniz — birimler',
      },
      {
        id: 'history',
        label: 'Geçmiş',
        shot: '/shots/ee/ticket-history-light-tr.jpg',
        shotDark: '/shots/ee/ticket-history-dark-tr.jpg',
        alt:
          'Bir talebin geçmişi: oluşturuldu, atandı, durumu değişti, sistem bir SLA hedefini ' +
          'kaçırdı, ve güncellendi',
        caption:
          'Her kaydın kendi geçmişi var, ve "kim" sorusunun cevabı sistem de olabilir — bir ' +
          'SLA süpürgesi insan değildir ve kayıt bunu gizlemiyor. Takım geneli iz, API ' +
          'üzerinden CSV olarak dışa aktarılıyor.',
        frameLabel: 'takiminiz.alanadiniz — geçmiş',
      },
    ],
  },

  identity: {
    id: 'identity',
    eyebrow: 'Kimlik',
    title: 'Hesaplar, zaten işlettiğiniz dizinden geliyor',
    body:
      'Bağlanma için LDAP ya da Active Directory, çoklu oturum açma için SAML ve OpenID ' +
      'Connect, kullanıcı sağlama için SCIM 2.0. Gruplar birimlere eşleniyor; yani dizinde ' +
      'bir departmana katılan kişi burada da o birime katılıyor. İşten ayrılan biri erişimini ' +
      'aynı gün kaybediyor, ve oturumları sona ermeye bırakılmıyor, kapatılıyor.',
    points: [
      'Hesap ilk girişte yaratılabilir ya da yaratılmaz — yaratmasına izin verilmeyen sağlayıcı bunu söyler ve reddeder',
      'Tam yapılandırılmamış bir sağlayıcı açılamaz, ve ekran hangi ayarların eksik olduğunu adıyla söyler',
      'Her kimlik bilgisi kendi anahtarı altında şifreleniyor ve sonrasında dört karakter gösteriyor, asla bir alan değil',
    ],
    shot: '/shots/ee/team-identity-light-tr.jpg',
    shotDark: '/shots/ee/team-identity-dark-tr.jpg',
    alt:
      'Kimlik kaynakları ekranı: bir LDAP dizini ve bir OIDC sağlayıcısı açık, bir SAML ' +
      'sağlayıcısı ise açılamıyor ve hâlâ eksik olan ayarları adıyla söylüyor',
    frameLabel: 'takiminiz.alanadiniz — kimlik',
  },

  security: {
    eyebrow: 'Güvenlik ve uyum',
    title: 'Bir güvenlik incelemesinin sorduğu sorular',
    items: [
      {
        key: 'residency',
        icon: '🗄️',
        title: 'Veri nerede',
        body:
          'Sizin donanımınızda, sizin MySQL\'inizde, sizin güvenlik duvarınızın arkasında. ' +
          'Ekler, adını sizin verdiğiniz bir depoya gidiyor. Siz bağlamadıkça hiçbir yere ' +
          'hiçbir şey gitmiyor; bağlarsanız da yalnız bağladığınız kadarı.',
      },
      {
        key: 'accounts',
        icon: '🔑',
        title: 'Hesaplar nasıl tutuluyor',
        body:
          'Sizin belirlediğiniz parola politikası ve kilitleme, doğrulayıcı uygulamayla iki ' +
          'adımlı giriş, ve bir kişinin açık oturum ve cihaz listesi — yönetici bunları ' +
          'sonlandırabiliyor.',
      },
      {
        key: 'audit',
        icon: '📜',
        title: 'Kayıt ne diyor',
        body:
          'Saklama süresini sizin seçtiğiniz, filtrelenebilir bir denetim izi; API üzerinden ' +
          'CSV olarak dışa aktarılıyor. Kimse düzenleyemiyor, biz dahil: yalnız ekleme ' +
          'yapılıyor ve yalnız saklama süpürgesi bir şey siliyor.',
      },
      {
        key: 'kvkk',
        icon: '⚖️',
        title: 'Biri unutulmak istediğinde',
        body:
          'Takımın tamamı tek bir belge olarak dışa aktarılıyor, ve bir kişinin verisi ' +
          'silinebiliyor. KVKK ve GDPR bu ihracatın var olma sebebi; sonradan yapıştırılmış ' +
          'bir etiket değil.',
      },
    ],
  },

  meetings: {
    id: 'meetings',
    eyebrow: 'Toplantı notları',
    title: '"Toplantı tutanağı"nın normalde hiç yapılmayan yarısı',
    body:
      'Bir kayıt yükleyin; kimin ne dediğini ayıran ve kararları çıkaran bir not geri gelsin. ' +
      'Bir karar tek adımda talebe dönüşüyor. Deşifre, sizin seçtiğiniz bir sağlayıcıda, ' +
      'kendi yöneticinizin girdiği kendi takım anahtarınızla koşuyor — ve kullanım ' +
      'ölçülüyor, yani uzun bir kayıt sessizce büyük bir faturaya dönüşemiyor.',
    points: [
      'Sağlayıcının ne sakladığını bizim değil, sizin onunla yaptığınız sözleşme belirliyor',
      'Kendi anahtarı olmayan bir takımın deşifresi yok — başkasınınkini ödünç almıyor',
      'Not, kabul etmek zorunda olduğunuz bir deşifre değil, düzenleyebildiğiniz bir markdown',
    ],
    shot: '/shots/ee/meeting-named-light-tr.jpg',
    shotDark: '/shots/ee/meeting-named-dark-tr.jpg',
    alt: 'Bir toplantı notu: konuşmacılar adlandırılmış, özet, ve içinden çıkarılmış kararlar',
    frameLabel: 'takiminiz.alanadiniz — toplantı',
  },

  ops: {
    eyebrow: 'Kurulum ve işletme',
    title: 'Sizin sunucunuz, sizin veritabanınız, sizin yedekleriniz',
    lede:
      'Ücretsiz sürümün kullandığı konteynerlerin aynısı, üstüne ticari katman. API şemasını ' +
      'açılışta kendisi taşıyor; yani yükseltme bir pull ve bir up — ve veriniz hiç yer ' +
      'değiştirmiyor.',
    command: // i18n-same — it is a shell command, not prose
      'docker compose -f docker-compose.ee.yml pull\n' +
      'docker compose -f docker-compose.ee.yml up -d\n\n' +
      '# the schema migrates itself on start; your volumes are untouched',
    points: [
      'Sizin kontrol ettiğiniz bir makinede MySQL 8.4 ya da MariaDB 10.11+ — ekler kendi S3 uyumlu deponuzda',
      'Her takım kendi subdomain\'inde, sizin kurduğunuz bir wildcard sertifikayla',
      'Yedekleme ve geri dönüş runbook\'u, ve hiçbir zaman kilitlenmediğiniz anlamına gelen bir ihracat',
    ],
    terminalTitle: 'sunucunuz',
    copyLabel: 'Kopyala',
    copiedLabel: 'Kopyalandı',
    link: { label: 'Kurulum rehberi', href: `${REPO_URL}/blob/main/docs/SELF-HOSTING.md` },
  },

  packages: {
    anchor: 'packages',
    eyebrow: 'Paketler',
    title: 'Bir takıma satılan şey',
    lede:
      'Paket, bir operatörün düzenlediği bir şekildir; bir özelliğin etrafındaki duvar değil. ' +
      'Bu sayfadaki her şey üründe var; paketin belirlediği, bir takımın ne kadarını ' +
      'kullanabileceği ve gerçekten ayrı olan iki yeteneğin açık olup olmadığı.',
    caption: 'Paket karşılaştırması',
    featureHeading: 'Limit ya da yetenek',
    labels: { yes: 'Var', no: 'Yok', partial: 'Kısmi' },
    columns: ['Starter', 'Business', 'Enterprise'],
    rows: [
      ['Koltuk', '10', '250', 'Sınırsız'],
      ['Birim (çalışma alanı)', '5', '50', 'Sınırsız'],
      ['Yayınlanmış talep formu', 'Sayılıyor', 'Sayılıyor', 'Sayılıyor'],
      ['Portaldan gelen aylık talep', 'Sayılıyor', 'Sayılıyor', 'Sayılıyor'],
      ['Aylık deşifre dakikası', 'Sayılıyor', 'Sayılıyor', 'Sayılıyor'],
      ['Geçmiş saklama', '90 gün', '1 yıl', '7 yıl'],
      ['Servis masası, SLA, sağlık izleme', 'yes', 'yes', 'yes'],
      ['Birimler, izinler, denetim izi', 'yes', 'yes', 'yes'],
      ['Public talep portalı', 'yes', 'yes', 'yes'],
      ['Toplantı notları ve kararlar', 'no', 'yes', 'yes'],
      ['LDAP / SAML / OIDC / SCIM', 'no', 'no', 'yes'],
    ],
    footnote:
      'Bunlar, taze bir kurulumun içinden çıkan üç pakettir; operatör onları yeniden ' +
      'adlandırır, düzenler ya da kendi paketini ekler. "Sayılıyor", ürünün sözleşmenizin ' +
      'belirlediği bir sayıyı zorladığı anlamına gelir — arkasında sayaç olmayan bir tavan, ' +
      'kimsenin tutmadığı bir sözdür, o yüzden bu tabloda yalnız sayılanlar var. Burada fiyat ' +
      'yok ve bununla saklanan bir şey de yok: Enterprise sizinle birlikte kuruluyor ve ' +
      'yapılandırılıyor, ve anlaşmanın şekli kaç kişi ve kaç departman olduğuna bağlı.',
    link: { label: 'Sizinki nasıl görünürdü, soralım →', href: '#contact' },
  },

  contact: {
    eyebrow: 'İletişime geçin',
    title: 'Kurumunuzun şeklini anlatın',
    lede:
      'Kaç kişi ve kaç departman olduğunu söylemeniz başlamak için yeterli. Size neye mal ' +
      'olacağını ve kurulumun ne gerektirdiğini yazarız — otomatik bir sonraki adım yok, ' +
      'kaydolunacak bir şey de yok.',
    mailSubject: 'AllisWell Enterprise talebi',
    fields: {
      name: { label: 'Adınız' },
      company: { label: 'Kurum' },
      workEmail: { label: 'İş e-postası' },
      phone: { label: 'Telefon (isteğe bağlı)' },
      seats: { label: 'Kullanacak kişi sayısı' },
      units: { label: 'Departman ya da birim sayısı' },
      packageInterest: {
        label: 'İlgilendiğiniz paket',
        placeholder: 'Henüz emin değilim',
        options: ['Starter', 'Business', 'Enterprise'],
      },
      message: { label: 'Bilmemiz gereken başka bir şey' },
      honeypot: 'Firma web sitesi',
    },
    consent: {
      text:
        'Yukarıdaki bilgilerin bu talebi yanıtlamak için saklanmasını ve kullanılmasını kabul ' +
        'ediyorum; ayrıntısı şurada:',
      linkLabel: 'aydınlatma metni',
      // Belgenin tamamı değil, BÖLÜMÜ: üç yüz satıra inen bir rıza linki,
      // okuyucuya neyi onayladığını söylememiş olur.
      href: '/privacy/tr#kurumsal-talep-formu',
    },
    submit: 'Gönder',
    sending: 'Gönderiliyor…',
    orWrite: 'Ya da doğrudan yazın:',
    sent: 'Teşekkürler — talebiniz bize ulaştı. Bir kişi okuyup size dönecek.',
    // Her sonuç için bir mesaj (EE-161). Sunucu makine-okunur bir kod dönüyor,
    // sayfa onu okuyanın dilinde söylüyor — deponun mevcut hata-kodu deseni.
    states: {
      // Özür DEĞİL. Bu kurulumun satış masası yok; bu, bir başarısızlık değil
      // kurulum hakkında doğru bir olgu, o yüzden formun yerini adres alıyor.
      noDesk:
        'Bu kurulumda satış masası çalışmıyor. Doğrudan bize yazın, bir kişi cevap verecek:',
      // Söyleneni yapınca düzeliyor.
      stale:
        'Bu sayfa açıkken aydınlatma metnimiz değişti. Lütfen sayfayı yenileyip tekrar ' +
        'gönderin — onayladığınız metin, size gösterilen metin olsun.',
      busy:
        'Şu anda çok fazla talep alıyoruz. Birkaç dakika sonra tekrar deneyin ya da doğrudan ' +
        'bize yazın.',
      invalid: 'Formdaki bir şey kabul edilmedi. Alanları kontrol edip tekrar deneyin.',
      offline:
        'Sunucularımıza ulaşamadık. Yazdıklarınız duruyor — birazdan tekrar deneyin ya da ' +
        'doğrudan bize yazın.',
      failed:
        'Bizim tarafımızda bir şeyler ters gitti. Yazdıklarınız duruyor — tekrar deneyin ya ' +
        'da doğrudan bize yazın.',
    },
  },

  faq: {
    heading: 'İnsanların gerçekten sorduğu sorular',
    items: [
      {
        q: 'Bu bir bulut hizmeti mi?',
        a:
          'Hayır. Sizin kontrol ettiğiniz donanıma, sizin kontrol ettiğiniz bir veritabanına ' +
          'kuruluyor. Kurulumda ve yükseltmelerde yardım ediyoruz; makine ve veri sizde kalıyor.',
      },
      {
        q: 'Ücretsiz sürüme ne oluyor?',
        a:
          'Hiçbir şey. Bireysel kullanım için ücretsiz kalıyor, kaynağı açık kalıyor, ve ' +
          'Enterprise onun şartlarını hiçbir yönde değiştirmiyor. Elinizdeki bir kopya, aldığınız ' +
          'lisansla sizin kalıyor.',
      },
      {
        q: 'Verimizi dışarı alabilir miyiz?',
        a:
          'Takımın tamamı API üzerinden tek bir belge olarak, denetim izi de CSV olarak dışa ' +
          'aktarılıyor. Veritabanı zaten sizin MySQL\'iniz, yani bütün bunların altındaki asıl ' +
          'cevap şu: veri hiçbir zaman başka bir yerde değildi.',
      },
      {
        q: 'Bir şey isteyebilmek için personelimizin hesabı olmalı mı?',
        a:
          'Kendi personelinizin evet. Şirket dışından biri için hayır: public talep formu tam ' +
          'olarak bunun için var, ve talebini sonradan giriş yapmadan takip edebilmesinin sebebi ' +
          'de bu.',
      },
      {
        q: 'Kurulum ne kadar sürüyor?',
        a:
          'Konteynerler dakikalar içinde ayağa kalkıyor. Zaman alan kısım, zaman ayırmaya değer ' +
          'olan kısım: birimlerinizin ne olduğuna, hangi servisleri verdiğine ve onlar hakkında ' +
          'ne söz verdiğinize karar vermek.',
      },
      {
        q: 'Bunda ne YOK?',
        a:
          'Varlık envanteri yok, değişiklik onay akışı yok, memnuniyet anketi yok, ve pano ile ' +
          'haftalık e-posta dışında bir rapor tasarlayıcı yok. E-posta henüz talep açamıyor — ' +
          'public form ve uygulama açabiliyor. Bunu üçüncü haftada öğrenmenizdense burada ' +
          'söylemeyi tercih ederiz.',
      },
    ],
  },

  footer: {
    blurb:
      "AllisWell Enterprise, zaten ücretsiz çalıştırabildiğiniz AllisWell'in üzerine team'ler, " +
      'birimler, izinler, servis masası ve SLA ekler. Ticari lisanslı, kendi sunucunuza kurulur.',
    notes:
      'Microsoft, Apple, Google, Anthropic ya da OpenAI ile bağlantılı değildir. Ürün adları ' +
      'sahiplerine aittir.',
    privacyLabel: 'Gizlilik',
    supportLabel: 'Destek',
    columns: [
      {
        title: 'Enterprise',
        links: [
          { label: 'Servis masası', href: '#itsm' },
          { label: 'SLA ve servis sağlığı', href: '#sla' },
          { label: 'Public talep portalı', href: '#portal' },
          { label: 'Kimlik ve güvenlik', href: '#identity' },
          { label: 'Paketler', href: '#packages' },
          { label: 'İletişime geçin', href: '#contact' },
        ],
      },
      {
        title: 'Kendiniz kurun',
        links: [
          { label: 'Kurulum rehberi', href: `${REPO_URL}/blob/main/docs/SELF-HOSTING.md` },
          { label: 'Mimari', href: `${REPO_URL}/blob/main/docs/ARCHITECTURE.md` },
          { label: 'REST API referansı', href: '/docs/api' },
          { label: 'Güvenlik politikası', href: `${REPO_URL}/blob/main/SECURITY.md` },
        ],
      },
      {
        title: 'Ücretsiz sürüm',
        links: [
          { label: 'alliswell.space', href: '/' },
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
