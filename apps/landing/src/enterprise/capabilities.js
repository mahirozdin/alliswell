// What AllisWell Enterprise does TODAY, in one list — the enterprise page's
// single source for what it claims.
//
// ── WHY A LIST AND NOT PROSE ──────────────────────────────────────────────
//
// The page's "What is not in it yet?" answer was written once, by hand, in two
// languages, and then the product moved underneath it: an asset register, change
// approvals, a satisfaction survey and requests by e-mail all shipped, and the
// page kept telling buyers they did not exist. Prose cannot notice that it has
// gone stale; a list the page is BUILT from can be checked. So the FAQ answer,
// the capability rows of the package table and the offline sentences are all
// produced from here, and `scripts/check-copy.mjs` refuses a page that says
// "not there" about anything this list does not say is not there.
//
// ── FOUR LEVELS, BECAUSE "IT EXISTS" IS NOT ONE ANSWER ────────────────────
//
//   app    there is a screen for it in the app (and usually the API too)
//   api    it works, and today only through the API — no screen yet; said so
//          next to its name wherever it is listed
//   pilot  built and tested, not yet proven in a customer's own environment
//   none   not in the product; listed so the page can say it plainly
//
// A capability moving between levels is a one-line change here, and every
// place the page mentions it follows.

export const LEVELS = Object.freeze(['app', 'api', 'pilot', 'none']);

/** Cell values the package table understands (ComparisonTable `cell()`). */
export const CELLS = Object.freeze(['yes', 'no', 'partial']);

const all = ['yes', 'yes', 'yes'];

export const CAPABILITIES = Object.freeze([
  {
    key: 'queues',
    level: 'app',
    packages: all,
    tr: 'Birim talep listeleri: durum, öncelik, atama, yanıt, iç not ve toplu işlem',
    en: 'Unit request queues: status, priority, assignment, replies, internal notes and bulk actions',
  },
  // EE-272: Phase C of the review (EE-266…EE-270) moved these into the app; the
  // list said "api" or "none" about three of them until the last measurement.
  {
    key: 'processType',
    level: 'app',
    packages: all,
    tr: 'Olay ile hizmet isteği ayrı: hizmetin türü, liste süzgeci ve türe göre performans',
    en: 'Incidents apart from service requests: a kind per service, a queue filter and performance by kind',
  },
  {
    key: 'crossUnit',
    level: 'app',
    packages: all,
    tr: 'Birden çok birimin açık taleplerini tek canlı listede görmek, SLA uyarısıyla',
    en: 'One live list of open requests across several units, with SLA warnings',
  },
  {
    key: 'archive',
    level: 'app',
    packages: all,
    tr: 'Arşivdeki talepler okunur: masa arar ve açar, talep sahibi kendi arşivini görür',
    en: 'Archived requests stay readable: the desk searches and opens them, requesters see their own',
  },
  {
    key: 'sla',
    level: 'app',
    packages: all,
    // EE-272: the app edits a policy's name, calendar, threshold and default,
    // and a calendar's name and zone; target durations, shifts and holidays
    // are entered through the API (measured against sla_admin_screen.dart).
    tr: 'SLA politikaları, çalışma takvimleri, eskalasyon, SLA panosu ve sistem sağlığı izleme (hedef süreler, vardiya ve tatiller şimdilik API ile)',
    en: 'SLA policies, working calendars, escalation, the SLA dashboard and system health monitoring (target durations, shifts and holidays are API only for now)',
  },
  {
    key: 'catalog',
    level: 'app',
    packages: all,
    tr: 'Hizmet kataloğu ve form tasarımcısı',
    en: 'Service catalogue and form designer',
  },
  {
    key: 'portal',
    level: 'app',
    packages: all,
    tr: 'Kurum dışı talep formu: dosya ekleme ve takip sayfası',
    en: 'Public request form, with file upload and a status page',
  },
  {
    key: 'mail',
    level: 'app',
    packages: all,
    tr: 'E-postadan talep: yanıtlar aynı talebe, ekler talebe iner',
    en: 'Requests by e-mail: replies thread onto the request, attachments land on it',
  },
  {
    key: 'approvals',
    level: 'app',
    packages: all,
    tr: 'Onay akışları: yönetici, rol ya da kişi onayı',
    en: 'Approval flows: by manager, by role or by named people',
  },
  {
    key: 'assets',
    level: 'app',
    packages: all,
    tr: 'Varlık (envanter) yönetimi, QR etiket ve toplu içe aktarma',
    en: 'Asset (inventory) register, QR labels and bulk import',
  },
  {
    key: 'kb',
    level: 'app',
    packages: all,
    tr: 'Bilgi bankası; talep yazılırken ve kurum dışı formda öneri',
    en: 'Knowledge base, suggested while a request is being written and on the public form',
  },
  {
    key: 'performance',
    level: 'app',
    packages: all,
    tr: 'Performans paneli, müşteri memnuniyet anketi ve işçilik kaydı',
    en: 'Performance panel, customer satisfaction survey and time logging',
  },
  {
    key: 'org',
    level: 'app',
    packages: all,
    tr: 'Birimler, roller ve özel yetkiler, işlem kaydı',
    en: 'Units, roles and custom permissions, activity log',
  },
  {
    key: 'absences',
    level: 'app',
    packages: all,
    tr: 'Devamsızlık takvimi: izinli kişiyi nöbet ve dengeli atama atlar',
    en: 'Absence calendar: on-call and balanced assignment skip whoever is away',
  },
  {
    key: 'webhooks',
    level: 'app',
    packages: all,
    tr: 'Başka sistemlere olay bildirimi (webhook)',
    en: 'Event notifications to other systems (webhooks)',
  },
  {
    key: 'workspace',
    level: 'app',
    packages: all,
    tr: 'Görevler, projeler, notlar, dosyalar',
    en: 'Tasks, projects, notes, files',
  },
  // EE-272: in the app since EE-269/EE-270. What still goes through the API is
  // named in the row itself, the way a level suffix would name it — a buyer who
  // reads "change management" and finds no "schedule" button was told less than
  // the truth.
  {
    key: 'changes',
    level: 'app',
    packages: all,
    tr: 'Değişiklik yönetimi: plan, onay kurulunun imzası, takvim ve dondurma çakışması (değişikliği ilerletmek şimdilik API ile)',
    en: 'Change management: the plan, the approval board’s signature, calendar and freeze clashes (moving a change along is API only for now)',
  },
  {
    key: 'problems',
    level: 'app',
    packages: all,
    tr: 'Problem ve bilinen hata kaydı: geçici çözüm çevrimdışı okunur, talepten bilinen hata kaydı açılır (kök neden ve durum şimdilik API ile)',
    en: 'Problem and known-error records: the workaround reads offline, a known-error record is raised from a request (root cause and status are API only for now)',
  },
  {
    key: 'rules',
    level: 'api',
    packages: all,
    tr: 'Otomasyon ve otomatik yönlendirme kuralları',
    en: 'Automation and automatic routing rules',
  },
  {
    key: 'oncall',
    level: 'api',
    packages: all,
    tr: 'Nöbet listesi ve izleme sistemlerinden gelen alarmlar',
    en: 'On-call rotations and alerts from monitoring systems',
  },
  {
    key: 'partners',
    level: 'api',
    packages: all,
    // EE-272: nothing — app, REST or MCP — attaches a policy to a customer
    // (only tests write `ee_customers.sla_policy_id`), so the row no longer
    // sells a per-customer SLA.
    tr: 'Kurumsal müşteri kaydı, müşteri portalı ve tedarikçi hedef süreleri (müşteriye özel SLA henüz bağlanamıyor)',
    en: 'Corporate customer records, the customer portal and supplier response targets (a per-customer SLA cannot be attached yet)',
  },
  {
    key: 'meetings',
    level: 'app',
    packages: ['no', 'yes', 'yes'],
    tr: 'Toplantı notları (yapay zekâ) ve aylık deşifre dakikası',
    en: 'Meeting notes (AI) and monthly transcription minutes',
  },
  {
    key: 'sso',
    level: 'app',
    packages: ['no', 'no', 'yes'],
    tr: 'Tek oturum açma (SAML, OpenID Connect) ve SCIM ile kullanıcı aktarımı',
    en: 'Single sign-on (SAML, OpenID Connect) and SCIM provisioning',
  },
  {
    key: 'directory',
    level: 'pilot',
    packages: ['no', 'no', 'yes'],
    tr: 'Active Directory / LDAP bağlantısı',
    en: 'Active Directory / LDAP connection',
    // A pilot says what it has been proven against and what it has not
    // (SECURITY-EE §5.1: OpenLDAP on every push, Samba AD once, no real forest).
    note: {
      tr:
        'Active Directory bağlantısı test dizinlerinde (OpenLDAP, Samba AD) doğrulandı; gerçek ' +
        'bir kurumsal dizinde ilk kurulum sizinle birlikte, pilot olarak yapılır.',
      en:
        'The Active Directory connection has been verified against test directories (OpenLDAP, ' +
        'Samba AD); the first installation against a real corporate directory is done together ' +
        'with you, as a pilot.',
    },
  },
  {
    key: 'cmdb',
    level: 'none',
    tr: 'varlıklar arasında bağımlılık grafiği ve otomatik keşif',
    en: 'a dependency graph between assets and automatic discovery',
  },
  {
    key: 'downtime',
    level: 'none',
    tr: 'makine duruş kaydı',
    en: 'a machine downtime log',
  },
  {
    key: 'designers',
    level: 'none',
    tr: 'sürükle-bırak süreç ve rapor tasarımcısı',
    en: 'drag-and-drop process and report designers',
  },
  {
    key: 'transfer',
    level: 'none',
    tr: 'masanın bir talebi başka bir hizmete ya da birime aktarması',
    en: 'the desk moving a request to another service or unit',
  },
  {
    key: 'replyFiles',
    level: 'none',
    tr: 'masanın yanıtına dosya eklemek',
    en: 'attaching a file to the desk’s reply',
  },
  {
    key: 'whatsappReplies',
    level: 'none',
    tr: 'WhatsApp’tan gelen yanıtlar (bildirim gider, yanıt alınmaz)',
    en: 'replies over WhatsApp (notifications go out, replies do not come in)',
  },
  {
    key: 'aiRequests',
    level: 'none',
    tr: 'talepleri yapay zekâyla sınıflandırmak ya da yanıtlamak (yönlendirme kurallarla yapılır)',
    en: 'AI that classifies or answers requests (routing is done by rules)',
  },
]);

/** The sentence a pilot capability carries wherever the page describes it. */
export function pilotNote(key, lang) {
  const capability = CAPABILITIES.find((c) => c.key === key);
  if (!capability || capability.level !== 'pilot' || !capability.note) {
    throw new Error(`capabilities.js: "${key}" is not a pilot with a note`);
  }
  return capability.note[lang];
}

/** What the table says next to a name that is not simply "in the app". */
const LEVEL_SUFFIX = {
  tr: { api: ' — şimdilik yalnız API ile', pilot: ' — pilot' },
  en: { api: ' — API only for now', pilot: ' — pilot' },
};

/**
 * The package table's capability rows, in the page's order. Every capability
 * with `packages` gets a row; the level rides in the label, so an API-only
 * module can never read as a screen somebody will look for and not find.
 */
export function packageRows(lang) {
  return CAPABILITIES.filter((c) => c.packages).map((c) => [
    `${c[lang]}${LEVEL_SUFFIX[lang][c.level] ?? ''}`,
    ...c.packages,
  ]);
}

/**
 * The names at one level, joined with semicolons: the items carry their own
 * commas and colons ("approval board, change calendar, freeze periods"), and a
 * comma-joined list of them would not say where one ends.
 */
function namesAt(lang, level, { lowerFirst = false } = {}) {
  return CAPABILITIES.filter((c) => c.level === level)
    .map((c) => (lowerFirst ? c[lang].charAt(0).toLocaleLowerCase(lang) + c[lang].slice(1) : c[lang]))
    .join('; ');
}

/**
 * The FAQ's "What is not in it yet?" answer — the ONLY place the page says
 * something is missing, and never written by hand. `check-copy.mjs` compares
 * the content module's answer with this function's.
 */
export function notYetAnswer(lang) {
  const none = namesAt(lang, 'none');
  const api = namesAt(lang, 'api', { lowerFirst: true });
  const pilot = namesAt(lang, 'pilot');
  if (lang === 'tr') {
    return (
      `Bugün bulunmayanlar: ${none}. ` +
      `Uygulamada ekranı olmayan, şimdilik yalnız API ile kullanılanlar: ${api}. ` +
      `Pilot aşamasında: ${pilot}. ` +
      'Var olanların tamamı paket tablosunda; bunları baştan söylemeyi tercih ederiz.'
    );
  }
  return (
    `Not in the product today: ${none}. ` +
    `Working through the API only for now, with no screen in the app yet: ${api}. ` +
    `In pilot: ${pilot}. ` +
    'Everything that is there is in the package table; we would rather say so up front.'
  );
}

/**
 * What works with the internet down — one set of sentences, because the page
 * said it in three places and two of them over-promised for requests. Tasks
 * and notes are edited offline and sync; requests are READ offline, a new one
 * waits as a draft, and writing to a request needs a connection.
 */
export const OFFLINE = Object.freeze({
  tr: {
    fact: 'İnternet kesildiğinde de açılır',
    queue:
      'İnternet kesildiğinde de talep listesi açılır ve okunur; yeni talep taslak olarak bekler, ' +
      'bağlantı gelince iletilir. Talebe yanıt, durum ve atama bağlantı ister',
    integrity:
      'Görevler ve notlar internet yokken düzenlenir, bağlantı gelince eşitlenir; hiçbir kayıt ' +
      'yarım kalmaz. Talepler çevrimdışı okunur, yeni talep taslak olarak bekler.',
  },
  en: {
    fact: 'Opens with the internet down',
    queue:
      'With the internet down the request list still opens and reads; a new request waits as a ' +
      'draft and is sent when the connection returns. Replying, changing a status and assigning ' +
      'need a connection',
    integrity:
      'Tasks and notes are edited with the internet down and synchronised when the connection ' +
      'returns; no record is left half-written. Requests read offline, and a new one waits as a ' +
      'draft.',
  },
});
