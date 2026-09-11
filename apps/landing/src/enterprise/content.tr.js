/**
 * Enterprise sayfasının bütün metni, Türkçe (EE-151; EE-164'te baştan yazıldı).
 *
 * İngilizce ikizi `content.en.js`; ikisinin aynı anahtar ağacını taşıdığını bir
 * gelenek değil bir kapı garanti ediyor (`npm run check:copy`, EE-152).
 *
 * ── KİME YAZILDI ─────────────────────────────────────────────────────────
 *
 * Okuyucu bir fabrikanın genel müdürü, bilgi işlem müdürü ya da satış sonrası
 * hizmetler müdürü. Bu metin onlarla yapılan bir toplantıda kurulan cümlelerle
 * yazılır: "servis masası", "team", "public portal" gibi çeviri kokan terimler
 * yok; "talep yönetimi", "birim", "kurum dışı talep formu" var. Teknik altyapı
 * (kod tabanı, bayt, anahtar sayısı) alıcının kararını değiştirmez ve sayfada
 * yer almaz. Alıcının kararını değiştiren tek teknik olgu şudur: veri nerede
 * durur, kim erişir — o da yazılıdır.
 *
 * ── NEYİN İDDİA EDİLEBİLECEĞİ ────────────────────────────────────────────
 *
 *   • Paket yalnız BULUT için vardır. Kendi sunucusuna kurulan bir kurum üst
 *     yönetim katmanını hiç görmez; sınırları biz kurulumda tanımlarız. Bu
 *     yüzden "kurduktan sonra paketleri yönetin" cümlesi bu sayfada olamaz.
 *   • Kurulumu müşteri yapmaz, biz yaparız. "Nasıl kurulur", docker komutu,
 *     kurulum rehberi bu sayfaya ait değildir.
 *   • Yönlendirme bir kural motoru değildir: hizmet → birim, sabit ve açık.
 *   • Yalnız var olan ekran gösterilir; yalnız ölçülmüş rakam yazılır; fiyat
 *     yazılmaz.
 *
 * Ekran görüntüsü yolları BÜTÜN olarak saklanır (`/shots/ee/...`), asla
 * birleştirilmez: CI kapısı derlenmiş paketi bu dizgiler için tarıyor.
 */

export const APP_URL = '/app';
export const REPO_URL = 'https://github.com/mahirozdin/alliswell';

export default {
  lang: 'tr',

  seo: {
    title: 'AllisWell Enterprise — kurum içi ve kurum dışı iş taleplerini tek yerden yönetin',
    description:
      'Departmanlar arası iş talepleri, satış sonrası destek talepleri, SLA takibi, yetki ' +
      'yönetimi, görev ve doküman yönetimi tek sistemde. Bulutta ya da kendi sunucunuzda, ' +
      'Türkçe ve İngilizce.',
    ogImage: '/shots/og/enterprise-tr.jpg',
  },

  nav: {
    home: '/',
    links: [
      { label: 'Talep yönetimi', href: '#itsm' },
      { label: 'SLA', href: '#sla' },
      { label: 'Kurulum seçenekleri', href: '#deploy' },
      { label: 'Paketler', href: '#packages' },
    ],
    cta: { label: 'İletişime geçin', href: '#contact' },
    starsLabel: 'Yıldız',
  },

  hero: {
    eyebrow: 'AllisWell Enterprise',
    title: 'Kurumunuzdaki bütün iş taleplerini tek yerden yönetin',
    lede:
      'Bakım, bilgi işlem, insan kaynakları, muhasebe gibi birimleriniz arasındaki iş ' +
      'talepleri; müşteri, bayi ve tedarikçilerinizden gelen destek talepleri; ekiplerinizin ' +
      'günlük görevleri, notları ve dosyaları — hepsi tek bir sistemde. Bulutta ya da kendi ' +
      'sunucunuzda çalışır; veriniz sizde kalır.',
    primary: { label: 'İletişime geçin', href: '#contact' },
    secondary: { label: 'Bulut mu, kendi sunucunuz mu?', href: '#deploy' },
    facts: [
      'Bulutta ya da kendi sunucunuzda',
      'Türkçe ve İngilizce arayüz',
      'Telefon, tablet, web ve masaüstü',
      'İnternet kesildiğinde de çalışır',
    ],
    shot: '/shots/ee/hero-light-tr.jpg',
    shotDark: '/shots/ee/hero-dark-tr.jpg',
    alt:
      'Yan yana iki ekran: bir birimin öncelik ve SLA durumlarıyla talep listesi, ve birim ' +
      've hizmet kırılımıyla söz tutma oranını gösteren SLA panosu',
  },

  personas: {
    eyebrow: 'Kimin için',
    title: 'Birden fazla birimi olan ve talepleri tek yerden yönetmek isteyen kurumlar için',
    items: [
      {
        key: 'internal',
        icon: '🏭',
        title: 'Fabrikalar ve üretim tesisleri',
        body:
          'Bakım, bilgi işlem, kalite, lojistik, insan kaynakları, muhasebe: her birim bir ' +
          'diğerinden sürekli bir şey ister. Bugün bu talepler telefonla, e-postayla ya da bir ' +
          'Excel dosyasında yaşıyor. AllisWell Enterprise ile her talep doğru birime düşer; kim ' +
          'ilgileniyor, ne durumda, ne zaman bitecek her an bellidir.',
      },
      {
        key: 'afterSales',
        icon: '🤝',
        title: 'Satış sonrası hizmet veren firmalar',
        body:
          'Müşterileriniz, bayileriniz ve tedarikçileriniz size sistemde hesap açmadan talep ' +
          'iletir. Her talep ilgili ekibe gider, söz verdiğiniz yanıt süresi takip edilir, talep ' +
          'sahibi de durumu kendi bağlantısından izler. Ortak e-posta kutusunda kaybolan iş kalmaz.',
      },
      {
        key: 'regulated',
        icon: '🔐',
        title: 'Kamu, sağlık ve KVKK kapsamındaki kurumlar',
        body:
          'Veriler sizin sunucunuzda kalır, her işlemin kaydı tutulur, kullanıcı hesapları ' +
          'mevcut Active Directory yapınızdan gelir. İşten ayrılan personelin erişimi aynı gün ' +
          'kapanır; denetimde "kim, ne zaman, neyi değiştirdi" sorusunun cevabı hazırdır.',
      },
    ],
  },

  itsm: {
    id: 'itsm',
    eyebrow: 'Talep yönetimi (ITSM)',
    title: 'Her birimin kendi talep listesi',
    body:
      'Bir birime gelen bütün talepler tek listede toplanır: kim istemiş, kim ilgileniyor, ' +
      'önceliği ne, söz verilen süre ne durumda. Talep ilgili kişilere görev olarak dağıtılır; ' +
      'talebi açan kişiyle bağ kopmaz, sonuçlandığında haberi olur.',
    points: [
      'Her talebin durumu, öncelik seviyesi ve sorumlusu listede bir bakışta görünür',
      'Bir talep birden fazla kişiye görev olarak dağıtılabilir; her görevin sorumlusu bellidir',
      'İnternet kesildiğinde de liste açılır ve düzenlenir; bağlantı gelince değişiklikler eşitlenir',
    ],
    shot: '/shots/ee/ticket-queue-light-tr.jpg',
    shotDark: '/shots/ee/ticket-queue-dark-tr.jpg',
    alt:
      'Bir birimin talep listesi: öncelik, durum, SLA hâli ve sorumlu kişilerle dört talep; ' +
      'biri süresi aşılmış, biri zamanında kapatılmış',
    frameLabel: 'sirketiniz.alliswell.space — talepler',
  },

  itsmTabs: {
    eyebrow: 'Talep yönetiminin parçaları',
    title: 'Hizmet kataloğu, yönlendirme ve talep detayı',
    lede:
      'Kurumunuzun hangi hizmetleri verdiğini bir kez tanımlarsınız; sonrasında her talep ' +
      'hangi birime gideceğini kendisi bilir.',
    tabs: [
      {
        id: 'catalogue',
        label: 'Hizmet kataloğu',
        shot: '/shots/ee/services-admin-light-tr.jpg',
        shotDark: '/shots/ee/services-admin-dark-tr.jpg',
        alt: 'Hizmet kataloğu: her hizmetin yanında onu veren birimler; biri arşivlenmiş',
        caption:
          'Elektrik arızası, kalibrasyon, kartlı geçiş, yazılım kurulumu… Her hizmet için talep ' +
          'formunda sorulacak ek alanları da siz belirlersiniz.',
        frameLabel: 'sirketiniz.alliswell.space — hizmetler',
      },
      {
        id: 'routing',
        label: 'Hangi birim ilgilenir',
        shot: '/shots/ee/service-routing-light-tr.jpg',
        shotDark: '/shots/ee/service-routing-dark-tr.jpg',
        alt: 'Bir hizmetin, onu cevaplayan birimlere bağlanması',
        caption:
          'Her hizmet bir ya da birden fazla birime bağlanır; gelen talep doğrudan o birimin ' +
          'listesine düşer. Elle dağıtım yapan bir ara kademeye gerek kalmaz.',
        frameLabel: 'sirketiniz.alliswell.space — yönlendirme',
      },
      {
        id: 'detail',
        label: 'Talep detayı',
        shot: '/shots/ee/ticket-detail-light-tr.jpg',
        shotDark: '/shots/ee/ticket-detail-dark-tr.jpg',
        alt:
          'Açılmış bir talep: talep sahibiyle yazışma ve ayrıca işaretlenmiş, talep sahibine ' +
          'görünmeyen bir iç not',
        caption:
          'Talep sahibiyle yazışma ve ekibin kendi iç notları aynı ekranda, ama ayrı işaretli: ' +
          'iç not talep sahibine hiçbir zaman görünmez.',
        frameLabel: 'sirketiniz.alliswell.space — talep',
      },
    ],
  },

  sla: {
    id: 'sla',
    eyebrow: 'SLA ve hizmet takibi',
    title: 'Yanıt ve çözüm süreleri, sizin mesai saatlerinize göre',
    body:
      'Her hizmet için ilk yanıt ve çözüm süresi hedefi belirlersiniz. Süreler kurumunuzun ' +
      'çalışma saatlerine, vardiyalarına ve resmî tatillere göre işler; hafta sonu ya da gece ' +
      'boşuna sayılmaz. Hedef yaklaşınca sorumlu birim uyarılır, aşıldığında kayda geçer.',
    points: [
      'Öncelik seviyesine göre farklı hedefler: acil bir arıza ile sıradan bir talep aynı süreye tabi olmaz',
      'Beklemeye alınan talebin süresi durur; devam ettiğinde kaldığı yerden sayar',
      'Yönetim panosunda hangi birim ve hangi hizmet sözünü tutuyor, hangisi tutmuyor tek bakışta görünür',
    ],
    shot: '/shots/ee/sla-dashboard-light-tr.jpg',
    shotDark: '/shots/ee/sla-dashboard-dark-tr.jpg',
    alt:
      'SLA panosu: dönem içindeki taleplerin yüzde kaçında sözün tutulduğu; birim ve hizmet ' +
      'kırılımı; altta süresi aşılan taleplerin listesi',
    frameLabel: 'sirketiniz.alliswell.space — SLA panosu',
  },

  slaTabs: {
    eyebrow: 'SLA ayarları',
    title: 'Süre hedefleri, çalışma takvimi ve sistem sağlığı',
    lede: 'Tanımlar bir kez yapılır; sonrasında sistem ölçer, siz sonucu görürsünüz.',
    tabs: [
      {
        id: 'targets',
        label: 'Süre hedefleri',
        shot: '/shots/ee/sla-policies-light-tr.jpg',
        shotDark: '/shots/ee/sla-policies-dark-tr.jpg',
        alt: 'Öncelik seviyesine göre ilk yanıt ve çözüm hedefleriyle SLA politikaları',
        caption:
          'Her öncelik seviyesi için ayrı ilk yanıt ve çözüm süresi. İsterseniz 7/24, ' +
          'isterseniz yalnız mesai saatleri içinde sayılır.',
        frameLabel: 'sirketiniz.alliswell.space — SLA hedefleri',
      },
      {
        id: 'calendar',
        label: 'Çalışma takvimi',
        shot: '/shots/ee/sla-calendars-light-tr.jpg',
        shotDark: '/shots/ee/sla-calendars-dark-tr.jpg',
        alt: 'Çalışma saatleri ve resmî tatilleriyle bir çalışma takvimi',
        caption:
          'Mesai saatleri, vardiyalar, resmî tatiller ve saat dilimi. Üç vardiyalı bir fabrika ' +
          'ile 09:00–18:00 çalışan bir ofis farklı takvim kullanır.',
        frameLabel: 'sirketiniz.alliswell.space — takvimler',
      },
      {
        id: 'health',
        label: 'Sistem sağlığı',
        shot: '/shots/ee/sla-monitors-light-tr.jpg',
        shotDark: '/shots/ee/sla-monitors-dark-tr.jpg',
        alt: 'Kritik sistemlerin adreslerini izleyen sağlık kontrolleri, aralıkları ve son sonuçlarıyla',
        caption:
          'Kritik uygulamalarınızın adreslerini izletin: bir sistem yanıt vermediğinde ' +
          'otomatik olarak kayıt açılır, düzeldiğinde aynı kayda not düşülür.',
        frameLabel: 'sirketiniz.alliswell.space — sistem sağlığı',
      },
    ],
  },

  portal: {
    eyebrow: 'Satış sonrası hizmet ve kurum dışı talepler',
    title: 'Müşterileriniz ve bayileriniz size hesap açmadan talep iletsin',
    lede:
      'Her müşteriye kullanıcı hesabı açmak pratik değildir; ortak bir e-posta kutusu ise ' +
      'takip edilemez. AllisWell Enterprise ile her hizmet için herkese açık bir talep formu ' +
      'yayınlarsınız: formu dolduran kişi sisteme girmeden talebini iletir, talep doğru ekibe ' +
      'düşer ve durumu dışarıdan takip edilir.',
    steps: [
      {
        n: 1,
        title: 'Talep formunu yayınlarsınız',
        body:
          'Form belirli bir hizmete ve o hizmeti veren birime bağlıdır. Bağlantıya süre sınırı ' +
          've aylık talep kotası koyabilir, dilediğiniz an durdurabilir ya da iptal edebilirsiniz.',
        shot: '/shots/ee/portal-links-light-tr.jpg',
        shotDark: '/shots/ee/portal-links-dark-tr.jpg',
        alt:
          'Talep formları ekranı: hizmeti, süresi ve kota kullanımıyla dört yayınlanmış form; ' +
          'iptal edilen formda kontroller kaybolmuş',
        frameLabel: 'sirketiniz.alliswell.space — talep formları',
      },
      {
        n: 2,
        title: 'Müşteriniz formu doldurur',
        body:
          'Hesap açmaz, uygulama indirmez. Form sizin adınız, logonuz ve kurumsal renginizle ' +
          'görünür; dili ziyaretçinin tarayıcısına göre Türkçe ya da İngilizce açılır.',
        shot: '/shots/ee/portal-form-light-tr.jpg',
        shotDark: '/shots/ee/portal-form-dark-tr.jpg',
        alt:
          'Herkese açık talep formu: kurum adı, hizmet, e-posta, konu, açıklama ve bu hizmete ' +
          'özel iki ek alan',
        frameLabel: 'sirketiniz.alliswell.space/p/…',
      },
      {
        n: 3,
        title: 'Talep doğrudan ilgili birime düşer',
        body:
          'Hizmet hangi birime bağlıysa talep o birimin listesinde belirir. Arada e-postayı ' +
          'yönlendiren ya da telefonla haber veren kimseye ihtiyaç kalmaz.',
      },
      {
        n: 4,
        title: 'Süre işlemeye başlar, ekip haberdar olur',
        body:
          'Hizmete bağlı SLA hedefi devreye girer. Ekip her talep için ayrı ayrı değil, toplu ' +
          'tek bir bildirim alır: yoğun bir günde kırk e-posta yerine tek liste.',
      },
      {
        n: 5,
        title: 'Talep sahibi durumu takip eder',
        body:
          'Formu dolduran kişi bir takip bağlantısı alır. Bu sayfada talebin konusu, durumu ve ' +
          'son güncelleme tarihi görünür; sisteme giriş gerekmez.',
        shot: '/shots/ee/portal-follow-light-tr.jpg',
        shotDark: '/shots/ee/portal-follow-dark-tr.jpg',
        alt: 'Takip sayfası: talebin konusu, "Alındı" durumu, gönderilme ve son güncelleme tarihleri',
        frameLabel: 'sirketiniz.alliswell.space/t/…',
      },
    ],
    aside: {
      title: 'Herkese açık form, kötüye kullanıma karşı korumalıdır',
      body:
        'Formu gerçek müşterileriniz rahatça kullanır; otomatik gönderim yapan yazılımlara ' +
        'karşı ise dört katmanlı koruma vardır:',
      points: [
        'Robot gönderimlerini yakalayan, insanların hiç görmediği tuzak alanı.',
        'Aynı adresten ve aynı forma art arda gönderime karşı hız sınırı.',
        'Aylık talep kotası: reddedilen gönderimler kotadan düşmez, size hiçbir maliyet getirmez.',
        'İstenirse ek doğrulama adımı; süresi dolmuş ya da iptal edilmiş bağlantılar hiçbir bilgi vermeden kapanır.',
      ],
    },
  },

  org: {
    id: 'org',
    eyebrow: 'Organizasyon yapısı',
    title: 'Birimler, tıpkı organizasyon şemanızdaki gibi',
    body:
      'Her departman, atölye ya da şube sistemde bir birimdir. Görevler, talepler, notlar ve ' +
      'dosyalar kişiye değil birime aittir; biri işten ayrıldığında ya da bölüm değiştirdiğinde ' +
      'iş kaybolmaz. Birimler arası paylaşım açıkça verilir, geri alındığında kalkar.',
    points: [
      'Her çalışan yalnız üyesi olduğu birimlerin verisini görür; cihazına da yalnız o veri iner',
      'Kurumunuz sisteme kendi adresinden girer (örneğin sirketiniz.alliswell.space); başka kurumların verisiyle hiçbir temas yoktur',
      'Yeni kullanıcı yalnız davetle katılır; davet bağlantısı süreli ve iptal edilebilir',
    ],
    shot: '/shots/ee/units-admin-light-tr.jpg',
    shotDark: '/shots/ee/units-admin-dark-tr.jpg',
    alt: 'Birimler ekranı: üye sayılarıyla dört birim; biri sizin yönettiğiniz, biri arşivlenmiş',
    frameLabel: 'sirketiniz.alliswell.space — birimler',
  },

  orgTabs: {
    eyebrow: 'Yetki ve rol yönetimi',
    title: 'Kim neyi yapabilir, kim ne yapmış',
    lede:
      'Yetkiler hazır kalıplarla sınırlı değildir. "Bakım şefi kendi biriminde talep atayabilir ' +
      'ama kapatamaz" gibi bir kuralı yöneticiniz kendisi tanımlar.',
    tabs: [
      {
        id: 'roles',
        label: 'Roller ve yetkiler',
        shot: '/shots/ee/team-roles-light-tr.jpg',
        shotDark: '/shots/ee/team-roles-dark-tr.jpg',
        alt: 'Rol düzenleyici: rollere göre tek tek verilen yetkilerden oluşan bir matris',
        caption:
          'Görev oluşturma, talep kapatma, dosya paylaşma gibi onlarca yetki tek tek açılıp ' +
          'kapatılır; birimlere özel roller tanımlanır.',
        frameLabel: 'sirketiniz.alliswell.space — roller',
      },
      {
        id: 'delegated',
        label: 'Birim yöneticisi görünümü',
        shot: '/shots/ee/units-manager-light-tr.jpg',
        shotDark: '/shots/ee/units-manager-dark-tr.jpg',
        alt: 'Aynı birimler ekranı, bir birim yöneticisinin gördüğü hâliyle: yalnız kendi birimi',
        caption:
          'Birim yöneticisi yalnız kendi birimini yönetir; yetkisi olmayan işlemler ekranda ' +
          'soluk değil, hiç görünmez.',
        frameLabel: 'sirketiniz.alliswell.space — birimler',
      },
      {
        id: 'history',
        label: 'İşlem geçmişi',
        shot: '/shots/ee/ticket-history-light-tr.jpg',
        shotDark: '/shots/ee/ticket-history-dark-tr.jpg',
        alt:
          'Bir talebin geçmişi: oluşturuldu, atandı, durumu değişti, sistem bir SLA hedefinin ' +
          'aşıldığını kaydetti, güncellendi',
        caption:
          'Her talep ve görevde kimin ne zaman ne yaptığı kayıtlıdır. Kurum genelindeki işlem ' +
          'kaydı denetim için dışa aktarılabilir.',
        frameLabel: 'sirketiniz.alliswell.space — geçmiş',
      },
    ],
  },

  workspace: {
    id: 'work',
    eyebrow: 'Günlük işler',
    title: 'Görevler, projeler, notlar ve dosyalar da aynı sistemde',
    body:
      'Talep yönetiminin yanında ekipleriniz günlük işlerini de burada yürütür: kişisel ve ' +
      'ortak görev listeleri, proje bazlı iş takibi, toplantı notları ve kurumsal dokümanlar. ' +
      'Bir talep tek tıkla göreve dönüşür; görevlere dosya ve not eklenir.',
    points: [
      'Geciken, bugünkü ve bu haftaki işler tek listede; ay takvimi hemen yanında',
      'Hatırlatıcılar telefon sessizdeyken bile çalar; acil işler gözden kaçmaz',
      'Google ve Apple takvimleriyle iki yönlü eşitleme: görevler takvimde, takvim görevlerin yanında',
    ],
    shot: '/shots/ee/work-home-light-tr.jpg',
    shotDark: '/shots/ee/work-home-dark-tr.jpg',
    alt:
      'Ana sayfa: geciken, bugünkü ve bu haftaki görevler proje ve etiket rozetleriyle tek ' +
      'listede; sağda ay takvimi',
    frameLabel: 'sirketiniz.alliswell.space — görevler',
  },

  workspaceTabs: {
    eyebrow: 'Ekip çalışması',
    title: 'Pano, projeler, notlar ve dosyalar',
    lede:
      'Her ekibin alışık olduğu çalışma biçimi: kimi liste ister, kimi pano. İkisi de aynı ' +
      'verinin farklı görünümüdür.',
    tabs: [
      {
        id: 'board',
        label: 'Pano',
        shot: '/shots/ee/work-board-light-tr.jpg',
        shotDark: '/shots/ee/work-board-dark-tr.jpg',
        alt: 'Pano görünümü: açık, devam eden, bekleyen ve tamamlanan sütunlarında görev kartları',
        caption:
          'Açık, devam eden, bekleyen ve tamamlanan işler sütunlar hâlinde; kartlar ' +
          'sürüklenerek taşınır, sütunlar ekibe göre düzenlenir.',
        frameLabel: 'sirketiniz.alliswell.space — pano',
      },
      {
        id: 'projects',
        label: 'Projeler',
        shot: '/shots/ee/work-projects-light-tr.jpg',
        shotDark: '/shots/ee/work-projects-dark-tr.jpg',
        alt: 'Projeler ekranı: renk ve ilerleme bilgisiyle proje kartları',
        caption:
          'Her proje kendi görevleri, notları ve dosyalarıyla bir arada; ilerleme ve sorumlular ' +
          'tek sayfada görünür.',
        frameLabel: 'sirketiniz.alliswell.space — projeler',
      },
      {
        id: 'notes',
        label: 'Notlar',
        shot: '/shots/ee/work-notes-light-tr.jpg',
        shotDark: '/shots/ee/work-notes-dark-tr.jpg',
        alt: 'Notlar ekranı: sabitlenmiş notlar ve projelere bağlı notlar',
        caption:
          'Toplantı notları, talimatlar, prosedürler: başlıklar, tablolar ve resimlerle ' +
          'biçimlendirilmiş metin; PDF olarak dışa aktarılır.',
        frameLabel: 'sirketiniz.alliswell.space — notlar',
      },
      {
        id: 'files',
        label: 'Dosyalar',
        shot: '/shots/ee/work-files-light-tr.jpg',
        shotDark: '/shots/ee/work-files-dark-tr.jpg',
        alt: 'Dosyalar ekranı: klasörler ve yüklenmiş kurumsal dokümanlar',
        caption:
          'Klasörlerle düzenlenen kurumsal doküman arşivi; her dosya hangi göreve ya da ' +
          'projeye bağlı olduğunu gösterir.',
        frameLabel: 'sirketiniz.alliswell.space — dosyalar',
      },
    ],
  },

  identity: {
    id: 'identity',
    eyebrow: 'Kurumsal kimlik yönetimi',
    title: 'Kullanıcılar mevcut Active Directory yapınızdan gelir',
    body:
      'Ayrı bir kullanıcı listesi tutmanız gerekmez. Active Directory ya da LDAP bağlantısı, ' +
      'Microsoft Entra ID gibi sistemlerle tek oturum açma (SAML, OpenID Connect) ve otomatik ' +
      'kullanıcı aktarımı (SCIM) desteklenir. Dizindeki gruplar birimlere eşlenir: personel işe ' +
      'girdiğinde hesabı açılır, ayrıldığında aynı gün kapanır.',
    points: [
      'Tek oturum açma: çalışanlar zaten kullandıkları kurumsal şifreyle girer',
      'Grup üyelikleri birimleri belirler; elle atama gerekmez',
      'Eksik bir bağlantı ayarı varsa sistem hangisinin eksik olduğunu adıyla söyler; yarım yapılandırma devreye alınamaz',
    ],
    shot: '/shots/ee/team-identity-light-tr.jpg',
    shotDark: '/shots/ee/team-identity-dark-tr.jpg',
    alt:
      'Kimlik kaynakları ekranı: bir Active Directory bağlantısı ve bir Microsoft Entra ID ' +
      'sağlayıcısı aktif; bir SAML sağlayıcısı eksik ayarlarını adıyla söylüyor',
    frameLabel: 'sirketiniz.alliswell.space — kimlik',
  },

  security: {
    eyebrow: 'Veri güvenliği',
    title: 'Veri gizliliği ve veri bütünlüğü',
    items: [
      {
        key: 'residency',
        icon: '🗄️',
        title: 'Veriniz nerede tutulur?',
        body:
          'Kendi sunucunuzu seçtiyseniz sizin sunucunuzda, sizin veritabanınızda, sizin ' +
          'güvenlik duvarınızın arkasında. Bulutta ise yalnız size ait, diğer müşterilerden ' +
          'tamamen ayrı bir alanda. Siz bağlamadıkça hiçbir veri kurumunuzun dışına çıkmaz.',
      },
      {
        key: 'access',
        icon: '🔐',
        title: 'Verinize kim erişebilir?',
        body:
          'Her çalışan yalnız üyesi olduğu birimlerin verisini görür; ne yapabileceği rolüyle ' +
          'belirlenir. Şifre politikası ve hatalı giriş kilidi sizin elinizde, iki adımlı giriş ' +
          'doğrulayıcı uygulamayla. Açık oturumlar ve cihazlar listelenir; yönetici gerektiğinde ' +
          'bir oturumu uzaktan kapatır.',
      },
      {
        key: 'audit',
        icon: '📜',
        title: 'Her işlem kayıt altında',
        body:
          'Talep, görev, not ve dosya üzerindeki her işlem tarih, saat ve kişiyle kaydedilir. ' +
          'Kayıtlar sonradan değiştirilemez ve silinemez; saklama süresini siz belirlersiniz, ' +
          'denetim için dışa aktarırsınız. "Kim, ne zaman, neyi değiştirdi" sorusunun cevabı ' +
          'her zaman hazırdır.',
      },
      {
        key: 'integrity',
        icon: '🛡️',
        title: 'Yedekleme, taşınabilirlik ve KVKK',
        body:
          'İnternet kesildiğinde yapılan değişiklikler cihazda saklanır, bağlantı gelince ' +
          'eşitlenir; hiçbir kayıt yarım kalmaz. Bulutta düzenli yedekleme bizim ' +
          'sorumluluğumuzda; kendi sunucunuzda yedekleme ve geri yükleme rehberiyle. Kurumunuzun ' +
          'bütün verisi tek belge olarak dışa aktarılır, bir kişinin verisi talep üzerine ' +
          'silinir. KVKK ve GDPR gerekleri sistemin parçasıdır.',
      },
    ],
  },

  meetings: {
    id: 'meetings',
    eyebrow: 'Toplantı notları',
    title: 'Toplantı kaydını yükleyin, kararları iş olarak alın',
    body:
      'Toplantının ses kaydını yükleyin; kimin ne söylediği ayrılmış bir tutanak, özet ve ' +
      'alınan kararların listesi hazır gelsin. Her karar tek tıkla bir talebe ya da göreve ' +
      'dönüşür. Deşifre için kendi seçtiğiniz yapay zekâ sağlayıcısını ve kendi hesabınızı ' +
      'kullanırsınız; kullanım dakika bazında ölçülür.',
    points: [
      'Hangi sağlayıcının kullanılacağına ve verinin nerede işleneceğine siz karar verirsiniz',
      'Tutanak düzenlenebilir bir nottur; yanlış duyulan bir cümle elle düzeltilir',
      'Aylık deşifre dakikası paketle sınırlıdır; beklenmedik bir fatura çıkmaz',
    ],
    shot: '/shots/ee/meeting-named-light-tr.jpg',
    shotDark: '/shots/ee/meeting-named-dark-tr.jpg',
    alt: 'Bir toplantı notu: konuşmacılar adlandırılmış, özet, ve içinden çıkarılmış kararlar',
    frameLabel: 'sirketiniz.alliswell.space — toplantı',
  },

  deploy: {
    eyebrow: 'Kurulum seçenekleri',
    title: 'Bulut mu, kendi sunucunuz mu?',
    lede:
      'İkisinde de aynı ürün, aynı özellikler. Fark, verinin nerede durduğu ve kurulumu kimin ' +
      'işlettiğidir.',
    options: [
      {
        key: 'cloud',
        icon: '☁️',
        title: 'Bulut',
        tagline: 'Hızlı başlangıç, işletme yükü yok',
        points: [
          'Kurumunuza özel adres: sirketiniz.alliswell.space',
          'Kurulum, yedekleme, güncelleme ve izleme bizden',
          'Starter, Business ya da Enterprise paketini seçersiniz; büyüdükçe geçiş yapılır',
          'Verileriniz yalnız size ait, diğer müşterilerden ayrı bir alanda tutulur',
        ],
        cta: { label: 'Bulut paketlerini görün', href: '#packages' },
      },
      {
        key: 'self',
        icon: '🏢',
        title: 'Kendi sunucunuzda (on-premise)',
        tagline: 'Veri kurumun dışına çıkmaz',
        points: [
          'Sizin sunucunuza, sizin veritabanınıza biz kurarız; devreye alma ekibimizle birlikte yapılır',
          'Kullanıcı sayısı, birim sayısı ve modüller (talep yönetimi, kurum dışı talep formu, Active Directory bağlantısı…) ihtiyacınıza göre belirlenir',
          'Fiyat, kullanıcı ve birim sayısına göre teklif olarak sunulur',
          'Güncellemeler ve destek sözleşmeyle; verinin yeri hiçbir zaman değişmez',
        ],
        cta: { label: 'Teklif için iletişime geçin', href: '#contact' },
      },
    ],
    footnote:
      'Kararsız mısınız? Formda "henüz karar vermedim" deyin; kurumunuzun büyüklüğüne ve mevzuat ' +
      'gereklerine göre birlikte karar veririz.',
  },

  packages: {
    anchor: 'packages',
    eyebrow: 'Bulut paketleri',
    title: 'Bulutta üç hazır paket',
    lede:
      'Bu paketler alliswell.space üzerinden bulut olarak kullanan kurumlar içindir. Kendi ' +
      'sunucunuza kurulumda hazır paket yoktur; sınırlar ve modüller ihtiyacınıza göre belirlenir.',
    caption: 'Bulut paketleri karşılaştırması',
    featureHeading: 'Kapsam',
    labels: { yes: 'Var', no: 'Yok', partial: 'Kısmi' },
    columns: ['Starter', 'Business', 'Enterprise'],
    rows: [
      ['Kullanıcı sayısı', '10', '250', 'Sınırsız'],
      ['Birim (departman) sayısı', '5', '50', 'Sınırsız'],
      ['Kurum dışı talep formu: aktif form ve aylık talep sayısı', 'Paketle belirlenir', 'Paketle belirlenir', 'Paketle belirlenir'],
      ['İşlem geçmişi saklama süresi', '90 gün', '1 yıl', '7 yıl'],
      ['Talep yönetimi, SLA, sistem sağlığı izleme', 'yes', 'yes', 'yes'],
      ['Birimler, yetki yönetimi, işlem kaydı', 'yes', 'yes', 'yes'],
      ['Kurum dışı talep formu', 'yes', 'yes', 'yes'],
      ['Görevler, projeler, notlar, dosyalar', 'yes', 'yes', 'yes'],
      ['Toplantı notları (yapay zekâ) ve aylık deşifre dakikası', 'no', 'yes', 'yes'],
      ['Active Directory / tek oturum açma / SCIM', 'no', 'no', 'yes'],
    ],
    footnote:
      'Paket içeriği sözleşmenizde yazar; ihtiyaç değiştikçe paket yükseltilir. Fiyatlar ' +
      'kurumun büyüklüğüne göre teklif olarak sunulur; bu sayfada fiyat yoktur.',
    link: { label: 'Teklif isteyin →', href: '#contact' },
  },

  contact: {
    eyebrow: 'İletişime geçin',
    title: 'Kurumunuzu kısaca anlatın, size teklif hazırlayalım',
    lede:
      'Kaç kullanıcı ve kaç birim olduğunu yazmanız başlamak için yeterli. Kısa sürede dönüş ' +
      'yapar; ihtiyacınıza göre bulut ya da kendi sunucunuz için teklif ve kurulum planı sunarız.',
    mailSubject: 'AllisWell Enterprise teklif talebi',
    fields: {
      name: { label: 'Adınız soyadınız' },
      company: { label: 'Kurum adı' },
      workEmail: { label: 'Kurumsal e-posta' },
      phone: { label: 'Telefon (isteğe bağlı)' },
      seats: { label: 'Kullanıcı sayısı (tahminî)' },
      units: { label: 'Birim / departman sayısı' },
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
    sent: 'Teşekkürler, talebiniz bize ulaştı. Ekibimiz en kısa sürede sizinle iletişime geçecek.',
    // Her sonuç için bir mesaj (EE-161). Sunucu makine-okunur bir kod dönüyor,
    // sayfa onu okuyanın dilinde söylüyor.
    states: {
      // Özür DEĞİL: bu kurulumun satış masası yok; form yerini adrese bırakır.
      noDesk: 'Bu kurulumda satış formu aktif değil. Bize doğrudan yazın, size dönüş yapalım:',
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
    },
  },

  faq: {
    heading: 'Sık sorulan sorular',
    items: [
      {
        q: 'Bulut ile kendi sunucumuza kurulum arasında özellik farkı var mı?',
        a:
          'Yok; ikisi de aynı üründür. Bulutta kurulum, yedekleme ve güncellemeyi biz ' +
          'üstleniriz. Kendi sunucunuzda ise veri kurumunuzun dışına çıkmaz, sınırlar ve ' +
          'modüller ihtiyacınıza göre belirlenir.',
      },
      {
        q: 'Kurulumu kim yapar, ne kadar sürer?',
        a:
          'Bulutta hesabınız hemen açılır. Kendi sunucunuza kurulumu ekibimiz yapar; sunucu ' +
          'hazırsa kurulum bir günde tamamlanır. Asıl zaman, birimlerinizi, hizmetlerinizi ve ' +
          'süre hedeflerinizi birlikte tanımlamaya gider; o da zaman ayırmaya değen kısımdır.',
      },
      {
        q: 'Verimiz nerede tutulur, dışarı alabilir miyiz?',
        a:
          'Kendi sunucunuza kurulumda veri tamamen sizin sunucunuzdadır. Bulutta yalnız size ait ' +
          'bir alanda tutulur. Her iki durumda da kurumunuzun bütün verisi tek belge olarak, işlem ' +
          'kayıtları da tablo olarak dışa aktarılır; sisteme bağlı kalmak zorunda değilsiniz.',
      },
      {
        q: 'Mevcut Active Directory yapımızla çalışır mı?',
        a:
          'Evet. Active Directory ve LDAP bağlantısı, Microsoft Entra ID ve benzeri sistemlerle ' +
          'tek oturum açma ve otomatik kullanıcı aktarımı bulutta Enterprise paketinde, kendi ' +
          'sunucunuza kurulumda ise istediğiniz kapsamda mevcuttur.',
      },
      {
        q: 'Müşterilerimizin sistemde hesabı olması gerekir mi?',
        a:
          'Hayır. Kurum dışından talep iletenler herkese açık talep formunu kullanır; talebin ' +
          'durumunu da giriş yapmadan takip eder. Kendi çalışanlarınız hesapla girer.',
      },
      {
        q: 'Ücretsiz AllisWell ile farkı ne?',
        a:
          'Ücretsiz sürüm tek kişinin görevleri, notları ve dosyaları içindir. Enterprise buna ' +
          'birimleri, yetki yönetimini, talep yönetimini, SLA takibini, kurum dışı talep formunu ' +
          've kurumsal kimlik bağlantısını ekler; ticari lisansla kullanılır.',
      },
      {
        q: 'Neler henüz yok?',
        a:
          'Varlık (envanter) yönetimi, değişiklik onay akışı, müşteri memnuniyet anketi ve pano ' +
          'dışında özel rapor tasarımı bulunmuyor. E-posta ile talep açma henüz yok; talepler ' +
          'form ve uygulama üzerinden açılır. Bunları baştan söylemeyi tercih ederiz.',
      },
    ],
  },

  footer: {
    blurb:
      'AllisWell Enterprise; kurum içi ve kurum dışı iş taleplerini, SLA takibini, yetki ' +
      'yönetimini ve ekiplerin günlük işlerini tek sistemde toplar. Bulutta ya da kendi ' +
      'sunucunuzda.',
    notes:
      'Microsoft, Apple, Google, Anthropic ya da OpenAI ile bağlantılı değildir. Ürün adları ' +
      'sahiplerine aittir.',
    privacyLabel: 'Gizlilik',
    supportLabel: 'Destek',
    columns: [
      {
        title: 'Enterprise',
        links: [
          { label: 'Talep yönetimi', href: '#itsm' },
          { label: 'SLA ve hizmet takibi', href: '#sla' },
          { label: 'Kurum dışı talep formu', href: '#portal' },
          { label: 'Kurumsal kimlik ve güvenlik', href: '#identity' },
          { label: 'Kurulum seçenekleri', href: '#deploy' },
          { label: 'Bulut paketleri', href: '#packages' },
          { label: 'İletişime geçin', href: '#contact' },
        ],
      },
      {
        title: 'Teknik belgeler',
        links: [
          { label: 'Mimari', href: `${REPO_URL}/blob/main/docs/ARCHITECTURE.md` },
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
