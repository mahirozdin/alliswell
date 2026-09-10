/**
 * Ana sayfanın bütün metni, Türkçe (EE-164).
 *
 * İngilizce ikizi `content.js`'in varsayılan dışa aktarımı; ikisinin aynı
 * anahtar ağacını taşıdığını `npm run check:copy` garanti ediyor — enterprise
 * çiftine bakan aynı kapı, artık bu çifte de bakıyor.
 *
 * Ekran görüntüleri ana sayfada dil taşımaz: `screenshots/web|ios|android`
 * gerçek bir tarayıcıdan ve gerçek cihazlardan, İngilizce arayüzle alınmış
 * kareler. Türkçe sayfa bugün aynı kareleri gösteriyor; uygulama Türkçe
 * konuşuyor, ama o hattı ikinci dilde yeniden koşturmak (Docker + API + web
 * derlemesi + iki cihaz) bu turun kapsamı dışında. Kapı bu yüzden bu çiftte
 * "yol dil taşır" kuralını uygulamıyor (`check-copy.mjs`, `shotsPerLanguage`).
 *
 * Sürüm dizgisi (`VERSION`) ve adresler İngilizce dosyadan gelir: sürüm tek
 * yerde yaşar, `check:docs` onu orada okur.
 */

import {
  APP_URL,
  DOCS_URL,
  PLAY_URL,
  REPO_URL,
  VERSION,
  comparison,
  platforms,
} from './content.js';

export default {
  lang: 'tr',

  seo: {
    title: 'AllisWell — kendi sunucunuzda barındırabileceğiniz görevler, hatırlatıcılar ve notlar',
    description:
      'Görevler, projeler, notlar, dosyalar ve sessiz moddayken bile çalan alarm gücünde ' +
      'hatırlatıcılar; Google ve Apple Takvim ile gerçek iki yönlü eşitleme. iOS, Android, ' +
      'web, macOS, Windows ve Linux için tek uygulama. Kaynağı açık, kendi sunucunuza ' +
      'kurulabilir, bireysel kullanım için ücretsiz.',
    ogImage: '/shots/og/home-tr.jpg',
  },

  skip: 'Özelliklere atla',

  nav: {
    home: '/tr',
    links: [
      { label: 'Özellikler', href: '/tr#features' },
      { label: 'Yapay zekâ', href: '/tr#ai' },
      { label: 'Karşılaştırma', href: '/tr#compare' },
      { label: 'Kendi sunucunuz', href: '/tr#self-host' },
      { label: 'Kurumsal', href: '/enterprise/tr' },
      { label: 'API', href: '/docs/api' },
      { label: 'İndir', href: '/tr#get' },
    ],
    cta: { label: 'Uygulamayı aç', href: APP_URL },
    starsLabel: 'Yıldız',
  },

  hero: {
    eyebrow: `v${VERSION} · kaynağı açık · bireysel kullanım ücretsiz`,
    title: 'Bütün gününüz, gerçekten size ait bir uygulamada.',
    lede:
      'Görevler, projeler, notlar, dosyalar ve sizi yerinizden kaldıracak kadar güçlü ' +
      'hatırlatıcılar; Google ve Apple Takvim ile gerçek iki yönlü eşitleme. Altı platformda ' +
      'tek uygulama, internet olmadan da çalışır, her veriyi kendi veritabanınızda tutar.',
    primary: { label: 'Web uygulamasını aç', href: APP_URL },
    store: { label: "Google Play'den indir", href: PLAY_URL },
    secondary: { label: 'Tek komutla kendi sunucunuza kurun', href: '/tr#self-host' },
    note:
      'Sonsuza kadar ücretsiz. Paket yok, reklam yok, takip yok. Tarayıcınızda ' +
      "alliswell.space/app adresinde, ve artık Google Play'de.",
    desktopAlt:
      'Web üzerinde AllisWell: geciken ve bugünkü gruplar, proje rozetleri, etiketler, hızlı ' +
      'erişim çubuğu ve ay takvimiyle ana sayfa',
    phoneAlt: "iPhone'da AllisWell: aynı gün, ay takvimi ve geciken görevler grubuyla",
    words: { stars: 'yıldız', github: "GitHub'da kaynak", availableOn: 'Şu platformlarda' },
  },

  // Altı özel isim; çevirmek ürün uydurmak olurdu.
  platforms, // i18n-same

  pillars: [
    {
      key: 'own',
      icon: '🔐',
      title: 'Gerçekten sizin',
      body:
        'Tek bir docker compose up, kendi makinenizde kendi MySQL veritabanınız, kendi alan ' +
        'adınız; bireysel kullanım için sonsuza kadar ücretsiz. Bu kategoride başka hiçbir ' +
        'uygulama bunu hiçbir fiyata sunmuyor.',
    },
    {
      key: 'alarm',
      icon: '⏰',
      title: 'Bildirim değil, alarm',
      body:
        'Acil hatırlatıcılar sessiz moddan ve Odak modundan geçerek çalar, siz onaylayana ' +
        'kadar yeniden uyarır, işletim sistemi engel olduğunda da nedenini açıklayan bir kayıt ' +
        'bırakır.',
    },
    {
      key: 'sync',
      icon: '📅',
      title: 'İki yönlü takvim eşitlemesi',
      body:
        'Görevleriniz Google etkinliği olur, Google’da yaptığınız düzenlemeler geri gelir, ' +
        'mevcut etkinlikleriniz bugünün işlerinin yanında görünür. Apple Takvim EventKit ile.',
    },
    {
      key: 'ai',
      icon: '🤖',
      title: 'Yapay zekâ sizin şartlarınızla; ya da hiç',
      body:
        'AllisWell’i zaten ödediğiniz Claude ya da ChatGPT aboneliğine ekleyin, ya da kendi ' +
        'anahtarınızı kullanın (yerel bir Ollama bile olur). Her öneri sizin dokunuşunuzu bekler.',
    },
  ],

  features: [
    {
      id: 'home',
      eyebrow: 'Gün',
      title: 'Vadesi gelen her şey için tek yüzey',
      body:
        'Geciken, bugün, bu hafta ve önümüzdeki 30 gün tek bir kronolojik akışta, yanında ay ' +
        'takvimi. Aynı günü, adlandırdığınız, gizlediğiniz ve sıraladığınız sütunlarla bir ' +
        'panoya çevirin.',
      points: [
        'Tarihsiz notlar en üstte sabit; hiçbir şey tarihi yok diye kaybolmaz',
        'Sütunlar arasında sürükleyin, ya da sürüklemek zorken görünür durum düğmesini kullanın',
        'Biten görev gece yarısına kadar üstü çizili olarak bugünün listesinde kalır',
      ],
      shot: 'web/home-light.jpg',
      shotDark: 'web/home-dark.jpg',
      alt:
        'Web üzerinde AllisWell ana sayfası: geciken ve bugünkü gruplar, proje rozetleri, ' +
        'etiketler ve ay takvimi',
    },
    {
      id: 'board',
      eyebrow: 'Pano',
      title: 'Aynı görevler, kanban olarak',
      body:
        'Açık, devam eden, bekleyen, tamamlanan; ya da işinizde gerçekten hangi durumlar varsa ' +
        'onlar. Sütunları gizlemek ve sıralamak size kalmış; her kart projesini, etiketlerini, ' +
        'önceliğini ve tekrar rozetini korur.',
      points: [
        'Sütun düzeniniz cihaz başına hatırlanır',
        'Gizlenen durumlar taşıma hedefi olarak erişilebilir kalır',
        'Ayrı bir liste değil: aynı veri, yeniden dizilmiş',
      ],
      shot: 'web/board.jpg',
      alt: 'AllisWell pano görünümü: açık, devam eden, bekleyen ve tamamlanan sütunları',
    },
    {
      id: 'alarms',
      eyebrow: 'Hatırlatıcılar',
      title: 'Sizi toplantıdan çıkaran bir hatırlatıcı',
      body:
        'Sıradan hatırlatıcılar tam dakikasında gelir. Acil olanlar alarm gibi çalar; sessiz ' +
        'modda da, Odak modunda da; ve siz onaylayana kadar zincirleme geri gelir.',
      points: [
        'Tam olarak ne zaman yeniden çalacağını söyleyen erteleme seçenekleri',
        'Bir görevin alarmlarını, görevi tamamlamadan susturun',
        'Kendi zil sesiniz, ya da yüklediğiniz bir ses',
        'Kilit ekranında görevin metnini gizleyen bir gizlilik modu',
      ],
      shot: 'web/reminders.jpg',
      alt: 'AllisWell hatırlatıcı ayarları: alarm profili, yeniden uyarı zinciri, ses kitaplığı',
    },
    {
      id: 'recurrence',
      eyebrow: 'Tekrarlar',
      title: "Ayın 31'ini isteyin, Şubat cevap versin",
      body:
        "Her gün, her iş günü, ayın son günü, ayın 2. salısı, 22'sinden sonraki ilk pazartesi. " +
        'Bir ayda olmayan bir gün seçin; AllisWell en yakın gerçek güne çeker, Google Takvim ' +
        'ise o ayı tamamen atlar.',
      points: [
        'Canlı "sonraki 5" önizlemesi günleri siz onaylamadan gösterir',
        'Tekrarlar gerçek görevlerdir: aramada, takvimde ve widget’ta görünür',
        'Birini düzenlemek ne kadar ileri gideceğini sorar: bu, bu ve sonrakiler, ya da hepsi',
      ],
      shot: 'web/home-dark.jpg',
      alt: 'AllisWell’de tekrarlayan bir görev, liste satırında tekrar rozetiyle',
    },
    {
      id: 'notes',
      eyebrow: 'Notlar ve dosyalar',
      title: 'İşin belge tarafı',
      body:
        'Yazarken canlı sözdizimi gösteren Markdown notlar ve gerçek bir okuma görünümü: ' +
        'tablolar, görev listeleri, KaTeX, Mermaid. Satır içi görseller, görevlere ve projelere ' +
        'bağlantılar, .md ya da PDF olarak dışa aktarma. Her şeye dosya ekleyin, hepsini iç içe ' +
        'klasörlü bir Dosyalar bölümünde gezin.',
      points: [
        'Bir projenin README notu, projenin genel bakış sayfası olur',
        'Ekler doğrudan Cloudflare R2 ya da herhangi bir S3’e gider; baytlar API’den geçmez',
        'Sabitle, arşivle, kart ızgarası ya da liste',
      ],
      shot: 'web/notes.jpg',
      alt: 'AllisWell Notlar: sabitlenmiş notlar, proje bağlantıları, README filtresi',
    },
    {
      id: 'markdown',
      eyebrow: 'Notlar',
      title: 'Bir metin kutusu değil, bir Markdown çalışma alanı',
      body:
        'Notlar GitHub tarzı Markdown’ı düzgün gösterir: hizalı tablolar, görev listeleri, ' +
        'uyarı kutuları, gerçek matematik, renkli kod, diyagram olarak çizilen Mermaid ' +
        'diyagramları. Tek belge, iki bakış: okuma görünümü ve yazarken canlı sözdizimli kaynak.',
      points: [
        'Kendi bilgisayarınızdan bir .md dosyası açın, düzenleyin, aynı dosyaya geri kaydedin',
        'Dosya asla arkanızdan yazılmaz; başka bir şey değiştirdiyse ne olacağına siz karar verirsiniz',
        'Ana hat, katlama, bul ve değiştir, komut paleti ve her yerde eğik çizgi komutları',
      ],
      ratio: '1440 / 900',
      shot: 'web/project-readme.jpg',
      alt:
        'AllisWell’de bir projenin README’si, Markdown’ı belge olarak çizilmiş: başlıklar, bir ' +
        'tablo, bir görev listesi ve bir alıntı',
    },
    {
      id: 'files',
      eyebrow: 'Dosyalar',
      title: 'Klasörler, ve her yere eklenmiş her şey',
      body:
        'İç içe klasörlü, çalışma alanı genelinde bir dosya yöneticisi; artı her projede bir ' +
        'Dosyalar sekmesi ve her görevde bir Ekler bölümü.',
      points: [
        'Ön imzalı yüklemeler: sizin depolamanız, sizin kovanız, sizin faturanız',
        'Kaynaklar görünümü her dosyanın nereye eklendiğini gösterir',
        'Yerelde MinIO, üretimde R2 ile çalışır',
      ],
      shot: 'web/files.jpg',
      alt: 'AllisWell Dosyalar bölümü: klasörler ve yüklenmiş belgeler',
    },
    {
      id: 'search',
      eyebrow: 'Arama',
      title: 'Aksanları önemsemeyen arama',
      body:
        '"muller" yazın, Müller’i bulun. "cafe" yazın, café’yi bulun. Başlık → etiket → gövde ' +
        'sırasıyla, cihazdaki veri kopyası üzerinde çalışır; anında cevap verir, internet ' +
        'olmadan da çalışır.',
      points: [
        'Latin alfabelerinde büyük-küçük harf ve aksan duyarsız: ß, ñ, å, ø, ł, č ve diğerleri',
        'Veritabanı motorlarının yanlış yaptığı harfleri doğru ele alır; sonuç sunucunuzun karşılaştırma ayarına bağlı değildir',
        'Çevrimdışı, çünkü dizin yereldir',
      ],
      shot: 'web/search.jpg',
      alt: 'AllisWell notlarında "muller" araması "Kickoff at Café Müller" notunu buluyor',
    },
    {
      id: 'widget',
      eyebrow: 'Ana ekran',
      title: 'Gününüz, hiçbir şeyin kilidini açmadan',
      body:
        'Widget, ana sayfanın gruplarını aynen yansıtır: geciken, tarihsiz, bugün; üstte tarih, ' +
        'sistem saati ve bugünün gerçekten kaç görev taşıdığı. Uygulamayla aynı veriyi okur, ' +
        'kilit açmadan.',
      points: [
        'Gerçekten işleyen bir saat; son yenilemede donmuş bir sayı değil',
        'Sayı, bugün üzerinizde olan iştir: geciken artı bugün vadesi gelen; sıfırken gizli',
        'iPhone ve Android, açık ve koyu temada, aynı görev verisinden',
      ],
      frame: 'phone',
      ratio: '1320 / 2868',
      shot: 'ios/12-widget.jpg',
      shotDark: 'ios/13-widget-dark.jpg',
      alt:
        'iPhone ana ekranında AllisWell widget’ı: başlıkta tarih ve sistem saati, altında ' +
        'bugünün açık görev sayısı, sonra geciken, tarihsiz ve bugünkü görevler',
    },
  ],

  recurrence: {
    eyebrow: 'Tekrar',
    title: '"Ayın 31’i" ay sonu demek olmalı',
    lede:
      'Aylık bir görevi ayın 31’ine kurun; RFC 5545’i harfiyen izleyen bir takvim, 31’i ' +
      'olmayan her ayı düpedüz atlar. Kiranız Şubat’ı atlamaz.',
    note:
      'AllisWell son gerçek güne geri çeker; değer değer, ve sonuç bir kümedir: 28 günlük ' +
      'Şubat’ta 23–29 gibi bir pencere 28’i iki kez üretmek yerine tek güne iner.',
    rule: 'Kural: her ay 31. gün',
    columns: { month: 'Ay', them: 'RFC 5545 / Google', us: 'AllisWell' },
    skipped: '— atlandı —',
    months: [
      { label: 'Aralık', them: '31 Ara', us: '31 Ara' },
      { label: 'Ocak', them: '31 Oca', us: '31 Oca' },
      { label: 'Şubat', them: null, us: '28 Şub' },
      { label: 'Mart', them: '31 Mar', us: '31 Mar' },
      { label: 'Nisan', them: null, us: '30 Nis' },
    ],
  },

  mobile: {
    eyebrow: 'Tek kod tabanı',
    title: 'Aynı uygulama, neredeyseniz orada',
    lede:
      'iPhone, Android, tarayıcı; macOS, Windows ve Linux için yerel derlemeler. Tek bir ' +
      'Flutter kod tabanından, her birinde yerel bir veritabanıyla.',
    shots: [
      {
        src: '/shots/ios/01-home.jpg',
        caption: 'Ana sayfa — iPhone',
        alt: 'iPhone’da AllisWell ana sayfası, ay takvimi ve geciken görevlerle',
      },
      {
        src: '/shots/ios/07-task-detail-repeat.jpg',
        caption: 'Tekrarlayan bir görev',
        alt: 'iPhone’da görev detayı: acil alarm, "her ay 31. gün" tekrar kuralı, vade 30 Eylül',
      },
      {
        src: '/shots/ios/08-repeat-dialog.jpg',
        caption: 'Sonraki beş gün',
        alt: 'iPhone’da Tekrar penceresi, sonraki beş tekrarın canlı önizlemesiyle',
      },
      {
        src: '/shots/android/01-home.jpg',
        caption: 'Ana sayfa — Android',
        alt: 'Bir Android telefonda AllisWell ana sayfası',
      },
      {
        src: '/shots/android/09-alarm-ring.jpg',
        caption: 'Android’de bir alarm',
        alt: 'Android’de AllisWell’in tam ekran acil hatırlatıcısı, Onayla düğmesi ve erteleme seçenekleriyle',
      },
      {
        src: '/shots/android/04-projects.jpg',
        caption: 'Projeler — Android',
        alt: 'Bir Android telefonda AllisWell Projeler ekranı',
      },
    ],
  },

  ai: {
    eyebrow: 'Yapay zekâ · tamamen isteğe bağlı',
    title: 'Bir modeli kullanmanın iki dürüst yolu; ve sıfır da bir seçenek',
    lede:
      'Kayıt tutmak hiç yapay zekâ olmadan çalışır. İstediğinizde de size hiçbir şey yeniden ' +
      'satılmaz, hiçbir şey sizin verinizle eğitilmez.',
    tracks: [
      {
        title: 'AllisWell’i Claude ya da ChatGPT’ye ekleyin',
        body:
          'AllisWell uzak bir MCP sunucusudur. Zaten ödediğiniz aboneliğe bağlayın ve gününüzü ' +
          'zaten kullandığınız asistanın içinden sorun.',
        points: [
          'PKCE ve dinamik istemci kaydıyla OAuth 2.1: kendi kurulumunuz, kendi onayınız',
          'Önce-oku araçları; silme aracı yok, hiç olmayacak',
          'Kendi sunucusuna kuranlar dizin listesi gerektirmeyen kendi bağlayıcı adresini alır',
        ],
        link: { label: 'Bağlayıcı nasıl çalışır', href: `${DOCS_URL}/MCP.md` },
      },
      {
        title: 'Kendi anahtarınızı getirin',
        body:
          'Anthropic, OpenAI, Gemini, OpenRouter; ya da hiçbir şeyin makineden çıkmadığı yerel ' +
          'bir Ollama. Görevlerinizle sohbet edin, basılı tutup birini sesle oluşturun, ya da ' +
          'herhangi bir metni uygulamaya paylaşın.',
        points: [
          'Ses cihazda yazıya dökülür: sesiniz cihazdan çıkmaz, yalnız metin çıkar',
          'Model yazma aracı almaz; önerir, siz tek dokunuşla onaylarsınız',
          'Onay ekranı her sağlayıcının gerçek veri politikasını söyler; sizinle eğitim yapanlar dahil',
        ],
        link: { label: 'Yapay zekâ burada nasıl çalışır', href: `${DOCS_URL}/AI.md` },
      },
    ],
    foot:
      'İlgilenmiyor musunuz? Kapalı bırakın. AllisWell’in yapay zekâ hesabı yoktur, varsayılan ' +
      'olarak hiçbir yere hiçbir şey göndermez ve her kayıt yüzeyi modelsiz çalışır.',
  },

  api: {
    eyebrow: 'REST API',
    title: 'Uygulamanın yaptığı her şeyi betikleriniz de yapabilir',
    lede:
      'Ayarlar’dan kişisel bir API anahtarı üretin; bütün yüzey açılır: görevler, notlar, ' +
      'projeler, dosyalar, hatırlatıcılar. Düz bearer kimlik doğrulama, OAuth dansı yok, ' +
      'kurulacak SDK yok. Bir cron işi üç satır.',
    command: // i18n-same — it is a shell command, not prose
      `export ALLISWELL_KEY="awk_…"     # Settings -> API access and management

curl -X POST "https://api.alliswell.space/api/v1/workspaces/$WS/tasks" \\
  -H "Authorization: Bearer $ALLISWELL_KEY" \\
  -H 'Content-Type: application/json' \\
  -d '{"title": "Pay the electricity bill", "isUrgent": true}'`,
    points: [
      'Her uç nokta parametreleri, örnek istek ve örnek yanıtıyla belgelenmiş; sunucunun kendi şemalarından üretildiği için sapamaz',
      'Bir anahtar tek bir çalışma alanına bağlıdır; hesabınızı asla silemez, yapay zekâ sağlayıcı anahtarlarınıza dokunamaz, yeni anahtar üretemez, şifrenizi değiştiremez',
      'Notlar ve görevler için toplu içe ve dışa aktarma; taşınmak bir destek talebi değil, bir betiktir',
    ],
    link: { label: 'API belgelerini okuyun', href: '/docs/api' },
    secondary: {
      label: 'Postman koleksiyonu',
      href: '/downloads/alliswell.postman_collection.json',
    },
    terminalTitle: 'cron işiniz',
    copyLabel: 'Kopyala',
    copiedLabel: 'Kopyalandı',
  },

  comparison: {
    eyebrow: 'Dürüst karşılaştırma',
    title: 'AllisWell’in gerçekten farklı olduğu yerler',
    lede:
      'Kazanılmak üzere tasarlanmış bir puan tablosu değil. Bu uygulamaların bizden daha iyi ' +
      'yaptığı altı şey dahil tam analiz depoda.',
    caption: 'Özellik karşılaştırma tablosu',
    featureHeading: 'Özellik',
    labels: { yes: 'Evet', no: 'Hayır', partial: 'Kısmi' },
    columns: comparison.columns, // i18n-same — product names
    rows: [
      ['Kaynağı açık', 'yes', 'no', 'no', 'no', 'no'],
      ['Kendi sunucunuz, kendi veritabanınız', 'yes', 'no', 'no', 'no', 'no'],
      ['Fiyat', 'ücretsiz', 'ücretsiz', 'ücretsiz', 'ücretsiz', '~80 $'],
      ['iOS + Android + Web + masaüstü', 'yes', 'partial', 'partial', 'no', 'no'],
      ['Tamamen çevrimdışı çalışır', 'yes', 'partial', 'partial', 'yes', 'yes'],
      ['Kanban panosu', 'yes', 'no', 'no', 'partial', 'no'],
      ['Zengin notlar ve dosya ekleri', 'yes', 'partial', 'no', 'partial', 'no'],
      ['Yerinde düzenlenen Markdown dosyaları', 'yes', 'no', 'no', 'no', 'no'],
      ['Sessiz mod ve Odak’tan geçen alarmlar', 'yes', 'no', 'no', 'partial', 'no'],
      ['Onaylanana kadar yeniden uyarı', 'yes', 'no', 'no', 'no', 'no'],
      ['Tekrar günü kırpma (31 → 28 Şub)', 'yes', 'no', 'no', 'yes', 'yes'],
      ['İki yönlü Google Takvim eşitlemesi', 'yes', 'yerleşik', 'yerleşik', 'no', 'no'],
      ['Aksan duyarsız arama', 'yes', 'no', 'no', 'no', 'no'],
      ['Claude / ChatGPT için MCP bağlayıcısı', 'yes', 'no', 'no', 'no', 'no'],
    ],
    footnote:
      'Rakip davranışları 2026 ortası itibarıyla. Bizi geçtikleri yerler dahil tam analiz ' +
      'docs/COMPARISON.md dosyasında.',
    link: { label: 'Okuyun →', href: `${DOCS_URL}/COMPARISON.md` },
  },

  selfHost: {
    eyebrow: 'Kendi sunucunuzda',
    title: 'Sizin sunucunuz, sizin veriniz, tek komut',
    lede:
      'amd64 ve arm64 için her sürümde etiketlenen iki yayınlanmış imaj: API ve web ' +
      'uygulaması. API açılışta kendi şemasını taşır; yükseltme bir pull ve bir up demektir, ' +
      'veriniz hiç yer değiştirmez.',
    command: // i18n-same — it is a shell command, not prose
      `curl -O https://raw.githubusercontent.com/mahirozdin/alliswell/main/docker-compose.selfhost.yml
curl -o .env https://raw.githubusercontent.com/mahirozdin/alliswell/main/.env.selfhost.example

echo "JWT_ACCESS_SECRET=$(openssl rand -hex 32)"  >> .env
echo "JWT_REFRESH_SECRET=$(openssl rand -hex 32)" >> .env
nano .env            # your domains + database passwords

docker compose -f docker-compose.selfhost.yml up -d`,
    points: [
      'MySQL 8.4 ya da MariaDB 10.11+; veri adlandırılmış birimlerde, yükseltmede asla dokunulmaz',
      'Ekler kendi Cloudflare R2 ya da S3 kovanızda',
      'Tek bir hazır web imajı her alan adına hizmet verir: API adresi konteyner açılışında okunur',
    ],
    link: { label: 'Tam kurulum rehberi', href: `${DOCS_URL}/SELF-HOSTING.md` },
    terminalTitle: 'sunucunuz',
    copyLabel: 'Kopyala',
    copiedLabel: 'Kopyalandı',
  },

  download: {
    eyebrow: 'Edinin',
    title: 'Bugün tarayıcınızda; ve artık Google Play’de',
    lede:
      'Web uygulaması yayında ve eksiksiz: kaydolun, sahip olduğunuz her cihazda çalışsın. ' +
      'Android uygulaması Google Play’de; iOS derlemesi TestFlight’ta, sırada App Store var.',
    web: {
      title: 'Web uygulaması',
      status: 'Yayında',
      body:
        'Tam uygulama alliswell.space/app adresinde; çevrimdışı çalışır, yüklenebilir, indirecek ' +
        'bir şey yok.',
      cta: { label: 'alliswell.space/app’i aç', href: APP_URL },
    },
    stores: [
      {
        name: 'Google Play',
        status: 'Yayında',
        body:
          'Android uygulaması mağazada: alarm gücünde hatırlatıcılar, çevrimdışı öncelikli ' +
          'eşitleme ve ana ekran widget’ı dahil.',
        icon: 'android',
        cta: { label: "Google Play'den indir", href: PLAY_URL },
      },
      {
        name: 'App Store',
        status: 'İç test',
        body: 'TestFlight iç derlemesi çalışıyor. Sırada herkese açık sürüm var.',
        icon: 'apple',
      },
    ],
    selfHostNote:
      'Aceleniz mi var, ya da tamamen kendi donanımınızda mı istiyorsunuz? Kendi sunucunuza ' +
      'kurulum tek komut uzağınızda, ve aynı uygulama.',
    comingSoon: 'Yakında',
  },

  faq: {
    heading: 'İnsanların gerçekten sorduğu sorular',
    items: [
      {
        q: 'Gerçekten ücretsiz mi?',
        a:
          'Sizin için evet: bireysel kullanım ve kendi kurulumunuzu kendiniz barındırmak ' +
          'sonsuza kadar ücretsiz; paket yok, reklam yok, takip yok. Ticari kullanım (bir ' +
          'şirketin içinde çalıştırmak, yeniden satmak ya da hizmet olarak sunmak) lisans ' +
          'gerektirir, çünkü barındırılan hizmet ve uygulama mağazaları işi finanse ediyor. ' +
          'info@bubiapps.com adresine yazın.',
      },
      {
        q: '"Alarm gücünde" tam olarak ne demek?',
        a:
          'Acil bir görev bildirim sesiyle değil gerçek bir alarm sesiyle, sessiz moddan ve ' +
          'Odak modundan geçerek tam seste çalar (iOS 26 AlarmKit; Android’in USAGE_ALARM ' +
          'ısrarlı kanalı) ve siz onaylayana kadar zincirleme yeniden uyarır. Teslimat yine de ' +
          'işletim sistemine bağlıdır; uygulamanın bir şey çalmadığında okuyabileceğiniz bir ' +
          'alarm günlüğü tutmasının sebebi tam olarak bu.',
      },
      {
        q: 'Google Takvim eşitlemesi nasıl iki yönlü?',
        a:
          'Görevleriniz seçtiğiniz bir takvime gerçek etkinlikler olarak yazılır; Google’da ' +
          'yaptığınız düzenlemeler push webhook’ları ve etag tabanlı çakışma çözümüyle artımlı ' +
          'eşitleme üzerinden AllisWell’e geri akar. Diğer Google etkinlikleriniz ana sayfada ' +
          'görevlerinizin yanında görünür.',
      },
      {
        q: 'Yapay zekâ özelliklerini kullanmak zorunda mıyım?',
        a:
          'Hayır. Siz açana kadar kapalıdır, kayıt tutmak sıfır yapay zekâyla çalışır ve bir ' +
          'AllisWell yapay zekâ hesabı yoktur: ya AllisWell’i MCP üzerinden kendi Claude/ChatGPT ' +
          'aboneliğinize bağlarsınız, ya da kendi sağlayıcı anahtarınızı yapıştırırsınız.',
      },
      {
        q: 'Verimi dışarı taşıyabilir miyim?',
        a:
          'Veritabanı sizin MySQL veritabanınız. Notlar Markdown olarak dışa aktarılır, şema ' +
          'baştan sona belgeli ve açık. Terk etmek için aşılacak bir kilit yok.',
      },
      {
        q: 'Neler eksik?',
        a:
          'Paylaşım ve atamalar (çalışma alanı modeli var, arayüzü yok), konuma dayalı ' +
          'hatırlatıcılar ve CalDAV. Üçü de ima edilip geçiştirilmek yerine yol haritasında ' +
          'yazılı.',
      },
    ],
  },

  footer: {
    columns: [
      {
        title: 'Ürün',
        links: [
          { label: 'Uygulamayı aç', href: APP_URL },
          { label: "Google Play'den indir", href: PLAY_URL },
          { label: 'Özellikler', href: '/tr#features' },
          { label: 'Karşılaştırma', href: '/tr#compare' },
          { label: 'Kurumsal', href: '/enterprise/tr' },
          { label: 'Yol haritası', href: `${REPO_URL}/blob/main/ROADMAP.md` },
          { label: 'Değişiklik günlüğü', href: `${REPO_URL}/blob/main/CHANGELOG.md` },
        ],
      },
      {
        title: 'Kendiniz kurun',
        links: [
          { label: 'Kurulum rehberi', href: `${DOCS_URL}/SELF-HOSTING.md` },
          { label: 'Mimari', href: `${DOCS_URL}/ARCHITECTURE.md` },
          { label: 'Ekler (R2/S3)', href: `${DOCS_URL}/ATTACHMENTS.md` },
          { label: 'Bildirimler ve alarmlar', href: `${DOCS_URL}/NOTIFICATIONS.md` },
        ],
      },
      {
        title: 'Yapay zekâ',
        links: [
          { label: 'Yapay zekâ nasıl çalışır', href: `${DOCS_URL}/AI.md` },
          { label: 'MCP bağlayıcısı', href: `${DOCS_URL}/MCP.md` },
          { label: 'REST API referansı', href: '/docs/api' },
          { label: 'Güvenlik politikası', href: `${REPO_URL}/blob/main/SECURITY.md` },
          { label: 'Gizlilik politikası', href: '/privacy/tr' },
        ],
      },
      {
        title: 'Proje',
        links: [
          { label: 'GitHub', href: REPO_URL },
          { label: 'Katkıda bulunma', href: `${REPO_URL}/blob/main/CONTRIBUTING.md` },
          { label: 'Sorunlar', href: `${REPO_URL}/issues` },
          { label: 'Destek', href: '/support/tr' },
          { label: 'Lisans (PolyForm NC)', href: `${REPO_URL}/blob/main/LICENSE` },
          { label: 'Ticari lisans', href: 'mailto:info@bubiapps.com' },
        ],
      },
    ],
    blurb:
      'Kaynağı açık, kendi sunucunuza kurulabilen görevler, notlar ve alarm gücünde ' +
      'hatırlatıcılar. Bireysel kullanım için ücretsiz. Açıkta, her seferinde bir görev ' +
      'olarak geliştiriliyor.',
    notes:
      'Apple, Google, Anthropic ya da OpenAI ile bağlantılı değildir. Ürün adları sahiplerine ' +
      'aittir.',
    privacyLabel: 'Gizlilik',
    supportLabel: 'Destek',
    starsWord: 'yıldız',
    forksWord: 'çatal',
  },

  /** `#app` içindeki JavaScript'siz blok; giriş HTML'iyle aynı kalmalı. */
  fallback: {
    lede:
      'Kaynağı açık, kendi sunucunuza kurulabilen görevler, notlar ve alarm gücünde ' +
      'hatırlatıcılar. Bu sayfa JavaScript ister; uygulamanın kendisi, gizlilik politikası ve ' +
      'destek sayfası istemez.',
    app: 'Uygulamayı aç',
    source: "GitHub'da kaynak",
    privacy: 'Gizlilik politikası',
    support: 'Destek',
    other: 'English',
  },
};
