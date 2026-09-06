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
export const CONTACT_EMAIL = 'info@bubiapps.com';

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
