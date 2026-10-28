/**
 * Every word on the enterprise page, in English (EE-151; rewritten in EE-164
 * and again in OPH-388).
 *
 * One file per language rather than `{en, tr}` beside every key: copy has to be
 * readable as prose to be reviewable as prose. What keeps the two honest is a
 * gate (`npm run check:copy`, EE-152) rather than a convention.
 *
 * ── WHO THIS IS WRITTEN FOR ───────────────────────────────────────────────
 *
 * The page is the web version of the 18-slide sales deck sent to factories;
 * its order, its language and its screens come from the deck (OPH-388), and
 * this file translates the Turkish one, `content.tr.js`, which leads. The
 * reader is a factory's general manager, IT manager, maintenance or
 * production manager, or after-sales manager; companies that provide
 * after-sales service are the second audience and are spoken to in
 * "Requests from outside".
 *
 * Language: plain, corporate English; one idea per section, short sentences.
 * Used: request, unit, service catalogue, approval, change, known error,
 * machine/asset, knowledge base, external request form, company portal,
 * on-call, absence. Not used — and `check-copy.mjs` refuses some of them:
 * ticket, service desk, public portal, on-premise ("on your own servers"),
 * department or team for the organisational unit. The escape hatch is
 * `i18n-vocab-ok` on the line. Status and button names are quoted as the
 * product's English interface says them.
 *
 * ── WHAT THIS PAGE MAY CLAIM ──────────────────────────────────────────────
 *
 *   • Only screens that exist are shown. What works through the API only
 *     today (capabilities.js `api`: defining on-call rotas, suppliers, shifts
 *     and holidays, bulk import) is told as "we set it up at installation",
 *     never shown as a screen.
 *   • Only measured numbers; the demo's numbers are labelled "sample data". No
 *     prices. Active Directory is a pilot (`pilotNote`).
 *   • Packages exist for the CLOUD only; for an installation on the
 *     customer's servers we set the limits at installation. The customer does
 *     not install it; we do.
 *   • Automation and routing rules are in the app (capabilities.js
 *     `rules: app`) and are told with "try it on a request before saving".
 *   • Only the FAQ's generated `notYet` answer says something is not there
 *     yet; no other text declares anything missing (`check-copy.mjs`).
 *
 * ── SCREENS AND MARKS ─────────────────────────────────────────────────────
 *
 * The screens come from `screenshots/sales/`: the real product on the
 * "Demir Çelik" sample data with the English interface; the records (units,
 * companies, people, request subjects) keep their Turkish names, which is
 * why the alt texts name them as written and gloss them where it helps.
 * `ratio` is each file's real pixel ratio (the same in all four variants).
 * The marks are the Turkish file's, checked on the light-en capture and
 * moved where the English interface's longer words pushed a label under them.
 *
 * Screenshot paths are stored WHOLE (`/shots/sales/...`), never composed,
 * because the CI gate greps the built bundle for those literals.
 */

export const APP_URL = '/app';
export const REPO_URL = 'https://github.com/mahirozdin/alliswell';

// EE-261: what the page claims about the product comes from one list —
// the FAQ's "not yet", the package table's capability rows and every offline
// sentence. `scripts/check-copy.mjs` holds the page to it.
import { OFFLINE, notYetAnswer, packageRows, pilotNote } from './capabilities.js';

export default {
  lang: 'en',

  seo: {
    title: 'AllisWell Enterprise — manage every work request in your factory in one place',
    description:
      'Request management for factories: breakdown, maintenance, purchasing, quality and ' +
      'customer requests in one system; SLA tracking, approvals and a company portal. In the ' +
      'cloud or on your own servers.',
    ogImage: '/shots/og/enterprise-en.jpg',
  },

  nav: {
    home: '/',
    links: [
      { label: 'Request management', href: '#itsm' },
      { label: 'SLA', href: '#sla' },
      { label: 'Requests from outside', href: '#intake' },
      { label: 'Deployment', href: '#deploy' },
      { label: 'Presentation (PDF)', href: '#deck' },
    ],
    cta: { label: 'Get in touch', href: '#contact' },
    starsLabel: 'Star',
  },

  // Slide 1
  hero: {
    eyebrow: 'AllisWell Enterprise',
    title: 'Manage every work request in your factory in one place',
    lede:
      'Breakdowns, maintenance, purchasing, quality and customer requests: who took them, how ' +
      'long they took and how they ended, in one system.',
    primary: { label: 'Get in touch', href: '#contact' },
    secondary: {
      label: 'Download the presentation (PDF)',
      href: '/downloads/alliswell-enterprise-presentation-2026-10.pdf',
      download: true,
    },
    facts: [
      'In the cloud or on your own servers',
      'English and Turkish interface',
      'Phone, tablet, web and desktop',
      OFFLINE.en.fact,
    ],
    note:
      'The screens on this page come from the real product running on sample data. Company ' +
      'and person names are examples; the sample records are in Turkish.',
    shot: '/shots/sales/hero-light-en.jpg',
    shotDark: '/shots/sales/hero-dark-en.jpg',
    alt:
      'The Production unit’s request list on a desktop and the Maintenance unit’s list on a ' +
      'phone: every row shows the request number, subject, status, priority and time left',
  },

  // Slide 2
  problem: {
    eyebrow: 'The starting point',
    title: 'This is how requests travel in most factories today',
    lede:
      'The work gets done, but nothing is recorded. When something goes wrong, nobody can find ' +
      'out afterwards who was waiting for what, and since when.',
    items: [
      {
        icon: 'phone-call',
        title: 'Phone, WhatsApp, the corridor',
        body: 'A breakdown stays with whoever was told. There is no record.',
      },
      {
        icon: 'user-x',
        title: 'Nobody knows who took it',
        body: 'The same job goes to two people, or to nobody.',
      },
      {
        icon: 'timer',
        title: 'Time is not measured',
        body: 'How long the line waited and how many hours the fix took: nobody knows.',
      },
      {
        icon: 'mail',
        title: 'Complaints stay in an inbox',
        body: 'Nobody follows the customer’s e-mail, so the customer calls a second time.',
      },
      {
        icon: 'repeat',
        title: 'Shift handover loses things',
        body: 'The problem the night shift reported is forgotten by morning.',
      },
    ],
    conclusion: {
      label: 'The result:',
      body:
        '“How many breakdowns did we have last month, how long did they take on average, which ' +
        'machine stopped most?” has no reliable answer. What is not measured cannot be improved.',
    },
  },

  // Slide 3
  journey: {
    eyebrow: 'What is AllisWell Enterprise?',
    title: 'Every request, from the moment it is opened until it is closed, in one record',
    lede:
      'AllisWell Enterprise is a request management system that routes requests from inside ' +
      'and outside the company to the right unit, measures how long they take and records how ' +
      'they ended. It is the same app on the web, desktop, tablet and phone.',
    steps: [
      {
        n: 1,
        icon: 'inbox',
        title: 'A request is opened',
        body: 'From the app, by e-mail, from a web form, or by itself when a system goes down.',
      },
      {
        n: 2,
        icon: 'git-branch',
        title: 'It reaches the right unit',
        body: 'The service catalogue and the rules send it to that unit’s request list.',
      },
      {
        n: 3,
        icon: 'clock',
        title: 'The clock starts',
        body: 'Response and resolution times count on the factory’s working calendar.',
      },
      {
        n: 4,
        icon: 'user-check',
        title: 'Someone is assigned',
        body: 'The request lands on that person’s own work list as a task.',
      },
      {
        n: 5,
        icon: 'wrench',
        title: 'It is solved',
        body: 'Replies, internal notes, attachments and the time spent stay on the request.',
      },
      {
        n: 6,
        icon: 'thumbs-up',
        title: 'The requester confirms',
        body: 'They confirm it is solved or reopen it, and rate their satisfaction.',
      },
    ],
    footnote:
      'The sections below show these steps in order: administration, request management, time ' +
      'tracking (SLA), people’s work and requests from outside.',
  },

  // Slide 4
  org: {
    eyebrow: 'Administration',
    title: 'Your organisation chart, carried over one to one',
    lede:
      'Setting up starts with units. Requests land in a unit, reports add up by unit, and ' +
      'permissions come with roles.',
    layout: 'grid',
    shots: [
      {
        shot: '/shots/sales/birimler-light-en.jpg',
        shotDark: '/shots/sales/birimler-dark-en.jpg',
        alt:
          'The Units screen with the sample factory’s units: Bilgi İşlem (IT), Bakım ' +
          '(Maintenance), Üretim (Production), Kalite (Quality), İnsan Kaynakları (HR), Satın ' +
          'Alma (Purchasing) and İSG (OHS), each with its number of people',
        frame: 'card',
        ratio: '1600 / 1000',
        marks: [{ n: 1, x: 62, y: 26 }],
      },
      {
        shot: '/shots/sales/roller-light-en.jpg',
        shotDark: '/shots/sales/roller-dark-en.jpg',
        alt:
          'The Roles screen: Owner, Admin and Member, and two roles of the factory’s own, ' +
          '“Birim yöneticisi” (unit manager) and “Vardiya amiri” (shift supervisor)',
        frame: 'card',
        ratio: '1600 / 875',
        marks: [{ n: 2, x: 55, y: 89 }],
      },
    ],
    items: [
      {
        n: 1,
        title: 'Every unit',
        body:
          'has its own request list, reports and people. One person can work in several units.',
      },
      {
        n: 2,
        title: 'Roles.',
        body:
          'Besides owner, admin and member, you define roles of your own such as “Shift ' +
          'supervisor”. Who may assign, close or approve a request is written in the role. ' +
          'Nobody can sign up to your organisation’s address from outside.',
      },
    ],
  },

  // Slide 5
  catalog: {
    eyebrow: 'Administration',
    title: 'Employees pick what they need from a menu',
    lede:
      'The service catalogue is the list a requester sees. Which unit each service goes to, ' +
      'what it asks and whether it needs an approval are set here.',
    layout: 'side',
    shots: [
      {
        shot: '/shots/sales/servis-kurulum-light-en.jpg',
        shotDark: '/shots/sales/servis-kurulum-dark-en.jpg',
        alt:
          'The settings of the “Yatırım ve demirbaş alımı” (capital and fixed-asset purchase) ' +
          'service: shelf, icon, kind of work (incident or service request) and Satın Alma ' +
          '(Purchasing) as the unit that answers it',
        frame: 'card',
        ratio: '1575 / 1600',
        marks: [
          { n: 2, x: 62, y: 12.5 },
          { n: 3, x: 90, y: 31 },
          { n: 4, x: 60, y: 51 },
        ],
      },
      {
        shot: '/shots/sales/katalog-light-en.jpg',
        shotDark: '/shots/sales/katalog-dark-en.jpg',
        alt:
          'The production and maintenance shelf of the service catalogue: electrical fault, line ' +
          'stoppage, hydraulic leak, die change, mechanical fault, periodic maintenance request',
        frame: 'card',
        ratio: '1000 / 1320',
        marks: [{ n: 1, x: 62, y: 9.5 }],
      },
    ],
    items: [
      {
        n: 1,
        title: 'Shelves.',
        body:
          'Services sit on shelves such as production and maintenance, IT and quality; they can ' +
          'be searched too.',
      },
      {
        n: 2,
        title: 'Shelf and icon.',
        body: 'The requester recognises the service by this mark.',
      },
      {
        n: 3,
        title: 'A breakdown or a need?',
        body:
          'A service is marked “incident” or “service request”; the reports measure the two apart.',
      },
      {
        n: 4,
        title: 'Answering unit and approval.',
        body:
          'The request lands in the chosen unit. For services such as purchasing, a manager’s or ' +
          'named people’s signature comes first.',
      },
    ],
    note:
      'A service asks its own questions too (“Line number”, “Estimated amount”). Every change ' +
      'to a form is a new version; older requests are not broken.',
  },

  // Slide 6
  rules: {
    eyebrow: 'Administration',
    title: 'Rules take a request to the right place without anyone moving it by hand',
    lede:
      'A routing rule says where a new request goes; an automation rule says what to do when ' +
      'something happens.',
    layout: 'grid',
    cols: 2,
    shots: [
      {
        shot: '/shots/sales/yonlendirme-light-en.jpg',
        shotDark: '/shots/sales/yonlendirme-dark-en.jpg',
        alt:
          'Routing rules: hydraulic and oil leaks to Maintenance, customer e-mails to Quality, ' +
          'requests that mention a forklift to Logistics, line stoppage words to Production as ' +
          'urgent',
        frame: 'card',
        ratio: '1600 / 750',
        title: 'Routing: where does a new request go?',
        caption:
          '“If the subject mentions a hydraulic or oil leak, send it to Maintenance at high ' +
          'priority.” The first rule that matches decides.',
      },
      {
        shot: '/shots/sales/kurallar-light-en.jpg',
        shotDark: '/shots/sales/kurallar-dark-en.jpg',
        alt:
          'Automation rules: a line stoppage is always urgent, maintenance requests go to the ' +
          'least busy technician, an e-mail to the production manager when an urgent request is ' +
          'overdue, open a request when the ERP stops answering',
        frame: 'card',
        ratio: '1600 / 958',
        title: 'Automation: what happens when something occurs?',
        caption:
          '“A line stoppage is always urgent.” “E-mail the production manager when an urgent ' +
          'request is overdue.” “Open a request when the ERP stops answering.”',
      },
      {
        shot: '/shots/sales/kural-dene-light-en.jpg',
        shotDark: '/shots/sales/kural-dene-dark-en.jpg',
        alt:
          'Test on a request: the rule is tried on request #205; the service, rule-on and daily ' +
          'limit conditions match, and the rule would raise the priority from high to urgent',
        frame: 'card',
        ratio: '1600 / 583',
        marks: [{ n: 1, x: 27, y: 40 }],
      },
    ],
    items: [
      {
        n: 1,
        title: 'Try it before you save it.',
        body:
          'A rule is tried step by step on a real request number you type in: it shows which ' +
          'condition matched and what the rule would do. Nothing changes.',
      },
      {
        n: 2,
        title: 'A rule that repeats itself stops.',
        body: 'If a rule starts triggering itself over and over, the system stops it and says why.',
      },
    ],
  },

  // Slide 7
  itsm: {
    eyebrow: 'Request management (ITSM)',
    title: 'Every unit works from its own request list',
    lede:
      'ITSM (request management) means answering “who asked for what and when, who took it, ' +
      'how long it took, how it ended” in one record. The day’s work happens in this list.',
    layout: 'side',
    shots: [
      {
        shot: '/shots/sales/kuyruk-light-en.jpg',
        shotDark: '/shots/sales/kuyruk-dark-en.jpg',
        alt:
          'The Production unit’s request list: SLA warnings from other units at the top, ready ' +
          'filters and the requests below; request #205, “Hat 3 sunucusu yine yanıt vermiyor” ' +
          '(the Line 3 server is not answering again), has missed its SLA',
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
        title: 'Warnings from other units.',
        body:
          'Someone who works in several units sees their other units’ overdue requests at the top.',
      },
      {
        n: 2,
        title: 'Ready filters.',
        body: 'New, in progress, waiting, urgent, mine, unassigned, overdue, breakdowns…',
      },
      {
        n: 3,
        title: 'One row, one request.',
        body: 'Number, subject, status, priority, requester, time left and who took it.',
      },
      {
        n: 4,
        title: 'An overdue request',
        body: 'is marked in red; whoever opens the list sees it first.',
      },
    ],
    points: [OFFLINE.en.queue],
    note: 'Status, priority or assignee can be changed for up to 100 requests at once.',
  },

  // Slide 8
  ticket: {
    eyebrow: 'Request management (ITSM)',
    title: 'A request’s whole story on one screen',
    lede:
      'Example: a dimensional deviation Anadolu Otomotiv reported by e-mail. The request landed ' +
      'in Quality, and the conversation is going on.',
    layout: 'grid',
    shots: [
      {
        shot: '/shots/sales/talep-ust-light-en.jpg',
        shotDark: '/shots/sales/talep-ust-dark-en.jpg',
        alt:
          'Request #206, a dimensional deviation on the flanges of batch 24-118: status, ' +
          'priority and the Transfer button; the requester of a request that came by e-mail, the ' +
          'time left to respond and the linked company, Anadolu Otomotiv',
        frame: 'card',
        ratio: '1600 / 954',
        marks: [
          { n: 1, x: 45, y: 31 },
          { n: 2, x: 56, y: 21 },
          { n: 3, x: 80, y: 62.5 },
        ],
      },
      {
        shot: '/shots/sales/talep-yazisma-light-en.jpg',
        shotDark: '/shots/sales/talep-yazisma-dark-en.jpg',
        alt:
          'The same request’s conversation: the requester’s e-mail, the unit’s reply and, at the ' +
          'top, an internal note with a lock; below, the choice between Reply and Internal note',
        frame: 'card',
        ratio: '1600 / 758',
        marks: [{ n: 4, x: 86, y: 10 }],
      },
    ],
    items: [
      {
        n: 1,
        title: 'Requester and source:',
        body: 'who wrote, and whether it came by e-mail or through a form.',
      },
      {
        n: 2,
        title: 'Status, priority, transfer:',
        body: 'the request moves to another unit in one step.',
      },
      {
        n: 3,
        title: 'Time left and company:',
        body: 'the time left to respond, and the customer company it belongs to.',
      },
      {
        n: 4,
        title: 'A reply and an internal note are kept apart.',
        body: 'The internal note carries a lock; the requester never sees it on any screen.',
      },
    ],
    note:
      'The time spent is written on the request. A change, a known error or a knowledge base ' +
      'article is opened from the same screen.',
  },

  // Slide 9
  approvals: {
    eyebrow: 'Request management (ITSM)',
    title: 'Work waiting for a signature, planned changes, recurring breakdowns',
    lede: 'All three come from one story: the failing RAID card in the Line 3 server.',
    layout: 'phones',
    shots: [
      {
        shot: '/shots/sales/onay-telefon-light-en.jpg',
        shotDark: '/shots/sales/onay-telefon-dark-en.jpg',
        alt:
          'An approval on a phone: purchase request #201, the estimated amount, the reason, the ' +
          'proposed supplier; Reject and Approve buttons',
        frame: 'phone',
        ratio: '780 / 1688',
        title: 'Approval',
        caption:
          'Purchase request #201: two disks and a RAID card. The approver sees the amount, the ' +
          'reason, the supplier and the quote file on the phone, and approves or rejects with a ' +
          'reason.',
      },
      {
        shot: '/shots/sales/degisiklik-telefon-light-en.jpg',
        shotDark: '/shots/sales/degisiklik-telefon-dark-en.jpg',
        alt:
          'A change on a phone: replacing the disk and RAID card in the Line 3 server, high risk, ' +
          'what it affects, the way back and the signature it is waiting for',
        frame: 'phone',
        ratio: '780 / 1688',
        title: 'Planned change',
        caption:
          'The disk swap’s window, risk, impact and rollback plan. When the window clashes with ' +
          'the month-end stock count the system warns; the board’s signature is awaited.',
      },
      {
        shot: '/shots/sales/problem-telefon-light-en.jpg',
        shotDark: '/shots/sales/problem-telefon-dark-en.jpg',
        alt:
          'A known error on a phone: the Line 3 SCADA connection drops now and then; what to do ' +
          'until it is fixed, and the requests it explains',
        frame: 'phone',
        ratio: '780 / 1688',
        title: 'Known error',
        caption:
          '“The Line 3 SCADA connection keeps dropping.” Requests with the same cause sit in one ' +
          'record; what to do until it is fixed is written at the top.',
      },
    ],
  },

  // Slide 10
  assets: {
    eyebrow: 'Request management (ITSM)',
    title: 'Machines and ready answers are linked to requests too',
    lede: 'Every machine has a record, and every request opened for it is linked to that record.',
    layout: 'phones',
    shots: [
      {
        shot: '/shots/sales/ekipman-telefon-light-en.jpg',
        shotDark: '/shots/sales/ekipman-telefon-dark-en.jpg',
        alt:
          'A machine card on a phone, BT-SRV-003, the Line 3 server: serial number, ' +
          'manufacturer, model, warranty end, supplier, purchase date and price; the “Open a ' +
          'request for this asset” button',
        frame: 'phone',
        ratio: '780 / 1688',
        marks: [
          { n: 1, x: 85, y: 30 },
          { n: 2, x: 79, y: 57 },
        ],
      },
      {
        shot: '/shots/sales/ekipman-talepler-telefon-light-en.jpg',
        shotDark: '/shots/sales/ekipman-talepler-telefon-dark-en.jpg',
        alt:
          'The same machine card further down: requests in the last 12 months, recorded work ' +
          'and the requests linked to this machine',
        frame: 'phone',
        ratio: '780 / 1688',
        marks: [{ n: 3, x: 88, y: 43 }],
      },
      {
        shot: '/shots/sales/makale-light-en.jpg',
        shotDark: '/shots/sales/makale-dark-en.jpg',
        alt:
          'The knowledge base article “VPN bağlantısı kopuyorsa” (if the VPN connection drops): ' +
          'symptom and solution; suggested 5 times, 3 requests prevented',
        frame: 'card',
        ratio: '1250 / 445',
        title: 'Knowledge base',
        caption:
          'While a request is being written, the system suggests the matching answer. The ' +
          'article in the example, on a dropping VPN connection, was suggested 5 times and kept ' +
          '3 requests from being opened (sample data).',
      },
    ],
    items: [
      {
        n: 1,
        title: 'Machine card.',
        body:
          'Serial number, manufacturer, warranty end, supplier, purchase price. Scanning the ' +
          'label opens the card.',
      },
      {
        n: 2,
        title: 'Open a request.',
        body: 'The “Open a request for this asset” button opens the form with the machine chosen.',
      },
      {
        n: 3,
        title: 'Linked requests.',
        body: 'How many requests in the last 12 months, how many are still open, how much labour.',
      },
      {
        n: 4,
        title: 'Planned changes.',
        body: 'The changes that affect the machine, and their windows, on the same card.',
      },
    ],
  },

  // Slide 11
  sla: {
    eyebrow: 'SLA (service promise)',
    title: 'The promise on every request: a response in minutes, a fix in hours',
    lede:
      'An SLA is the promise of how soon a request is answered and how soon it is solved. The ' +
      'clock only runs during the factory’s working hours.',
    layout: 'side',
    shots: [
      {
        shot: '/shots/sales/sla-hedef-light-en.jpg',
        shotDark: '/shots/sales/sla-hedef-dark-en.jpg',
        alt:
          'The “Standart” SLA policy: the factory hours calendar, an 80% warning threshold and ' +
          'first reply and resolution times for urgent, high, normal and low priority',
        frame: 'card',
        ratio: '1143 / 1600',
        tall: true,
        marks: [
          { n: 1, x: 20, y: 41.5 },
          { n: 3, x: 72, y: 22 },
        ],
      },
      {
        shot: '/shots/sales/sla-takvim-light-en.jpg',
        shotDark: '/shots/sales/sla-takvim-dark-en.jpg',
        alt:
          'The factory hours calendar: weekdays 08:00–18:00, Saturday 08:00–13:00 and public ' +
          'holidays',
        frame: 'card',
        ratio: '1000 / 1010',
        marks: [{ n: 2, x: 80, y: 30 }],
      },
      {
        shot: '/shots/sales/sla-izleyici-light-en.jpg',
        shotDark: '/shots/sales/sla-izleyici-dark-en.jpg',
        alt:
          'System monitors: the barcode server and the ERP interface are answering, the ' +
          'warehouse terminal is not',
        frame: 'card',
        ratio: '1300 / 470',
        marks: [{ n: 4, x: 85, y: 50 }],
      },
    ],
    items: [
      {
        n: 1,
        title: 'Two times per priority.',
        body:
          'For example: an urgent request is answered in 30 minutes and solved in 4 hours; a ' +
          'normal one is answered in 4 hours and solved in 1 day.',
      },
      {
        n: 2,
        title: 'Factory hours.',
        body:
          'Weekdays 08:00–18:00, Saturday 08:00–13:00; public holidays are left out. A request ' +
          'opened at 03:00 starts counting at 08:00.',
      },
      {
        n: 3,
        title: 'Warning and escalation.',
        body:
          'A warning at 80% of the time; once it is exceeded, the manager and whoever is on call ' +
          'are told in the app, by e-mail and by phone notification.',
      },
      {
        n: 4,
        title: 'System monitors.',
        body:
          'The ERP, the barcode server and the warehouse terminal are checked regularly; if one ' +
          'stops answering, a request opens by itself.',
      },
    ],
    note:
      'Only a reply written to the requester stops the response clock. When a reason for ' +
      'waiting is given (a supplier, a spare part, an approval…) the clock stops; nobody can ' +
      'wind it back. We set up your shifts and holidays at installation.',
  },

  // Slide 12
  slaReport: {
    eyebrow: 'SLA (service promise)',
    title: 'How much of the promise was kept, unit by unit',
    lede:
      'The dashboards are live; nobody has to prepare a report. Everyone sees their own units’ ' +
      'numbers, and managers see the whole factory.',
    layout: 'grid',
    shots: [
      {
        shot: '/shots/sales/sla-pano-light-en.jpg',
        shotDark: '/shots/sales/sla-pano-dark-en.jpg',
        alt:
          'The SLA dashboard (sample data): the share of promises kept, the number missed, close ' +
          'to the limit and kept, and requests per unit as bars',
        frame: 'card',
        ratio: '1600 / 875',
        marks: [
          { n: 1, x: 35, y: 10 },
          { n: 2, x: 35, y: 47 },
        ],
      },
      {
        shot: '/shots/sales/performans-light-en.jpg',
        shotDark: '/shots/sales/performans-dark-en.jpg',
        alt:
          'The performance dashboard (sample data): incidents and service requests apart; per ' +
          'unit opened, finished, first reply, resolution time, satisfaction and SLA met',
        frame: 'card',
        ratio: '1100 / 1480',
        marks: [{ n: 3, x: 66, y: 5.5 }],
      },
    ],
    items: [
      {
        n: 1,
        title: 'The share of promises kept',
        body: 'and the number of requests per unit. The numbers on screen are sample data.',
      },
      {
        n: 2,
        title: 'By unit and by service:',
        body: 'which service do most requests come from?',
      },
      {
        n: 3,
        title: 'Breakdowns and service requests apart.',
        body:
          'Last 7, 30 or 90 days: opened, finished, first response and resolution time, SLA ' +
          'met, satisfaction.',
      },
    ],
    note: '“How long do we take to fix breakdowns?” The answer is here.',
  },

  // Slide 13
  people: {
    eyebrow: 'People and workload',
    title: 'Everyone sees their own work list; managers see who has what',
    lede:
      'Being assigned to a request means a task on that person’s Home screen. Completing the ' +
      'task solves the request.',
    layout: 'phones',
    shots: [
      {
        shot: '/shots/sales/ana-sayfa-telefon-light-en.jpg',
        shotDark: '/shots/sales/ana-sayfa-telefon-dark-en.jpg',
        alt:
          'Home on a phone: a month calendar and, under it, overdue tasks; the first is a task ' +
          'that came from request #101',
        frame: 'phone',
        ratio: '780 / 1688',
        marks: [{ n: 1, x: 72, y: 70 }],
      },
      {
        shot: '/shots/sales/devamsizlik-light-en.jpg',
        shotDark: '/shots/sales/devamsizlik-dark-en.jpg',
        alt:
          'The Absences screen: on-call cards for Bakım (Maintenance) and Bilgi İşlem (IT); in ' +
          'Maintenance, Barış Saha is on call covering for Kerem Bakım, who is on leave; below, ' +
          'the absences of the next 90 days',
        frame: 'card',
        ratio: '1600 / 1000',
        marks: [
          { n: 2, x: 40, y: 56 },
          { n: 3, x: 68, y: 23 },
        ],
        title: 'Absence and on-call',
        caption:
          'In Maintenance it was Kerem Bakım’s turn on call; he is on leave, so Barış Saha holds ' +
          'it. Meanwhile no work is assigned to Kerem automatically.',
      },
    ],
    items: [
      {
        n: 1,
        title: 'Your own work list.',
        body:
          'An assigned request appears on Home with its number and subject; its due date comes ' +
          'from the request’s time limit, and overdue work comes first.',
      },
      {
        n: 2,
        title: 'Balanced assignment.',
        body:
          'Work goes round in turn, or to whoever has the least. Nobody with an absence entered ' +
          'gets work automatically.',
      },
      {
        n: 3,
        title: 'On-call.',
        body:
          'The unit’s on-call rota is set up at installation; if the person on call is on leave, ' +
          'the next one takes over.',
      },
      {
        n: 4,
        title: 'My units.',
        body:
          'Someone who works in several units sees the open requests of all of them in one ' +
          'list, overdue first.',
      },
    ],
  },

  // Slide 14
  statuses: {
    eyebrow: 'People and workload',
    title: 'A request’s states, and what the requester sees',
    lede:
      'The unit sees the detailed state; the requester sees a plain word for it. Internal ' +
      'details (such as whose approval is awaited) never go outside.',
    teamLabel: 'What the unit sees',
    requesterLabel: 'What the requester sees',
    states: [
      { team: 'New', requester: 'Received', tone: 'progress' },
      { team: 'Triage', requester: 'In progress', tone: 'progress' },
      { team: 'In progress', requester: 'In progress', tone: 'progress' },
      { team: 'Resolved', requester: 'Resolved', tone: 'done' },
      { team: 'Closed', requester: 'Closed', tone: 'done' },
    ],
    waiting: {
      title: 'Waiting',
      hint: '(a reason is required; the SLA clock stops while it waits)',
      reasons: [
        'Information from the requester',
        'Supplier',
        'Spare part',
        'Approval',
        'Planned window',
      ],
      body:
        'When information is awaited the requester sees “Waiting for your reply”, when an ' +
        'approval is awaited “Waiting for approval”, otherwise “In progress”. The moment they ' +
        'reply, the request goes back to “In progress” by itself and the clock runs again.',
    },
    after: {
      title: 'After it is resolved',
      body:
        'The requester says “Yes, it is solved” or reopens it with “There is still a problem”. ' +
        'When the request closes, a satisfaction survey follows. An unnecessary request is ' +
        '“Cancelled”; cancelling and closing cannot be undone.',
    },
  },

  // Slide 15
  intake: {
    eyebrow: 'Requests from outside',
    title: 'Customers, dealers and suppliers can send a request without an account',
    lede:
      'For factories that provide after-sales service: a request from outside joins the same ' +
      'list, and the same time tracking, as one from inside.',
    channels: [
      {
        icon: 'link',
        title: 'External request form',
        body:
          'You share a time-limited link for a service. No account is needed; a photo or a PDF ' +
          'can be attached.',
      },
      {
        icon: 'mail',
        title: 'E-mail',
        body:
          'An e-mail to the support address becomes a request. Replies join the same request, ' +
          'even if the subject changes.',
      },
      {
        icon: 'building',
        title: 'Company portal',
        body:
          'People at contracted companies sign in with their own password and see all of their ' +
          'company’s requests.',
      },
      {
        icon: 'phone-call',
        title: 'Phone',
        body:
          'The unit opens the request on the caller’s behalf; a tracking link goes to them by ' +
          'e-mail.',
      },
    ],
    shot: {
      shot: '/shots/sales/portal-form-light-en.jpg',
      shotDark: '/shots/sales/portal-form-dark-en.jpg',
      alt:
        'Demir Çelik Fabrikası’s computer fault form: e-mail, subject, description, a photo or ' +
        'document, and a Send button',
      ratio: '1420 / 1600',
      caption: 'The form the customer sees',
    },
    note:
      'The link expires, or is stopped whenever you want. A file from outside arrives marked ' +
      'as coming from outside; virus scanning can be switched on on the server.',
  },

  // Slide 16
  portal: {
    eyebrow: 'Requests from outside',
    title: 'Requesters see for themselves where their request is',
    lede: 'Customers do not have to call to ask “what happened to my request?”.',
    layout: 'phones',
    shots: [
      {
        shot: '/shots/sales/firma-portali-telefon-light-en.jpg',
        shotDark: '/shots/sales/firma-portali-telefon-dark-en.jpg',
        alt:
          'The company portal on a phone: request #206 with its status, “In progress”, and its ' +
          'conversation; replies appear under the name “The desk”',
        frame: 'phone',
        ratio: '780 / 1688',
        title: 'Company portal',
        marks: [
          { n: 1, x: 88, y: 30 },
          { n: 3, x: 88, y: 58 },
        ],
      },
      {
        shot: '/shots/sales/portal-takip-telefon-light-en.jpg',
        shotDark: '/shots/sales/portal-takip-telefon-dark-en.jpg',
        alt:
          'The tracking page on a phone: the number, status and last update of the request ' +
          '“Vardiya amiri dizüstü ekranı kırık” (the shift supervisor’s laptop screen is broken)',
        frame: 'phone',
        ratio: '780 / 1688',
        title: 'Tracking link',
        marks: [{ n: 2, x: 88, y: 31 }],
      },
      {
        shot: '/shots/sales/firmalar-light-en.jpg',
        shotDark: '/shots/sales/firmalar-dark-en.jpg',
        alt:
          'The Companies screen: Anadolu Otomotiv, Ege Döküm, Kuzey Makine, Marmara Lojistik and ' +
          'Trakya Otomotiv Yan Sanayi',
        frame: 'card',
        ratio: '1600 / 667',
        title: 'Companies screen',
        marks: [{ n: 4, x: 85, y: 23 }],
      },
    ],
    items: [
      {
        n: 1,
        title: 'Company portal.',
        body:
          'Anadolu Otomotiv’s people see all of the company’s requests, reply, attach files and ' +
          'open new requests.',
      },
      {
        n: 2,
        title: 'Someone without an account',
        body: 'sees the status and the last update from the tracking link they were sent.',
      },
      {
        n: 3,
        title: 'Internal information stays inside.',
        body:
          'Internal notes, the unit’s own conversation and who the approver is never show outside.',
      },
      {
        n: 4,
        title: 'Companies screen.',
        body:
          'Add a company and invite its people; someone who leaves that company loses access in ' +
          'one tap.',
      },
      {
        n: 5,
        title: 'The requester confirms the close.',
        body:
          'They say “Yes, it is solved” or “There is still a problem”; once the request closes, ' +
          'a satisfaction survey follows.',
      },
    ],
  },

  // Slide 17
  security: {
    eyebrow: 'For the factory',
    title: 'On the shop floor, with your rules and your data',
    shot: {
      shot: '/shots/sales/kuyruk-telefon-light-en.jpg',
      shotDark: '/shots/sales/kuyruk-telefon-dark-en.jpg',
      alt:
        'The Maintenance unit’s request list on a phone: an SLA warning from other units and ' +
        'Maintenance’s requests',
      ratio: '780 / 1688',
    },
    items: [
      {
        key: 'integrity',
        icon: 'wifi-off',
        accent: 'primary',
        title: 'Works without the internet',
        body: OFFLINE.en.integrity,
      },
      {
        key: 'kvkk',
        icon: 'shield-check',
        accent: 'tertiary',
        title: 'Data protection (KVKK): your data stays with you',
        body:
          'It runs on your own server and your own database, or in the cloud at an address set ' +
          'aside for your organisation. All data can be exported as one file; every change is ' +
          'written to the audit log.',
      },
      {
        key: 'setup',
        icon: 'server',
        accent: 'secondary',
        title: 'We install it and move you over',
        body:
          'Our team does the installation. From your current system (ServiceDesk Plus, Jira or ' +
          'Excel) we carry over the service list, the people and past requests at installation.',
      },
      {
        key: 'pilot',
        icon: 'rocket',
        accent: 'warning',
        title: 'Start with one unit',
        body:
          'Our advice: a trial of a few weeks with one unit such as Maintenance, then the other ' +
          'units. The package follows your number of people and units.',
      },
    ],
  },

  // ── Also ────────────────────────────────────────────────────────────────
  extras: {
    eyebrow: 'Also',
    title: 'Beside request management, in the same system',
    lede: 'Daily work, sign-in with Active Directory (pilot) and meeting notes are in the same app too.',
  },

  workspace: {
    eyebrow: 'Daily work',
    title: 'Tasks, projects, notes and files',
    body:
      'Units run their daily work here too. A task that came from a request and a person’s own ' +
      'task sit in the same list; files and notes attach to the task.',
    points: [
      'Overdue, today and this week in one list, with the month calendar beside it',
      'Reminders ring even when the phone is on silent',
      'Two-way sync with Google Calendar; on iPhone and Mac, Apple Calendar too',
    ],
    shot: '/shots/ee/work-home-light-en.jpg',
    shotDark: '/shots/ee/work-home-dark-en.jpg',
    alt:
      'Home: overdue, today and this week’s tasks in one list with project and tag badges, and ' +
      'a month calendar on the right',
    frameLabel: 'yourcompany.alliswell.space — tasks',
  },

  workspaceTabs: {
    eyebrow: 'Working together',
    title: 'Board, projects, notes and files',
    lede: 'Some want a list, some want a board. Both are views of the same work.',
    tabs: [
      {
        id: 'board',
        label: 'Board',
        shot: '/shots/ee/work-board-light-en.jpg',
        shotDark: '/shots/ee/work-board-dark-en.jpg',
        alt: 'Board view: task cards in open, in progress, waiting and done columns',
        caption: 'Work in columns; cards move by dragging.',
        frameLabel: 'yourcompany.alliswell.space — board',
      },
      {
        id: 'projects',
        label: 'Projects',
        shot: '/shots/ee/work-projects-light-en.jpg',
        shotDark: '/shots/ee/work-projects-dark-en.jpg',
        alt: 'Projects screen: project cards with colour and progress',
        caption: 'Each project together with its own tasks, notes and files.',
        frameLabel: 'yourcompany.alliswell.space — projects',
      },
      {
        id: 'notes',
        label: 'Notes',
        shot: '/shots/ee/work-notes-light-en.jpg',
        shotDark: '/shots/ee/work-notes-dark-en.jpg',
        alt: 'Notes screen: pinned notes and notes linked to projects',
        caption:
          'Instructions and procedures, written with headings, tables and images; exported as PDF.',
        frameLabel: 'yourcompany.alliswell.space — notes',
      },
      {
        id: 'files',
        label: 'Files',
        shot: '/shots/ee/work-files-light-en.jpg',
        shotDark: '/shots/ee/work-files-dark-en.jpg',
        alt: 'Files screen: folders and uploaded company documents',
        caption: 'A document archive in folders; every file shows the work it belongs to.',
        frameLabel: 'yourcompany.alliswell.space — files',
      },
    ],
  },

  identity: {
    eyebrow: 'Sign-in with Active Directory',
    title: 'Users come from your existing Active Directory',
    body:
      'You do not keep a second user list. Directory groups map to units; a new hire’s account ' +
      `opens, and a leaver’s closes the same day. ${pilotNote('directory', 'en')}`,
    points: [
      'People sign in with the company password they already use',
      'Group membership decides the units; no assigning by hand',
    ],
    shot: '/shots/ee/team-identity-light-en.jpg',
    shotDark: '/shots/ee/team-identity-dark-en.jpg',
    alt:
      'Identity sources screen: an Active Directory connection and a Microsoft Entra ID ' +
      'provider are active; one provider names the settings it is missing',
    frameWidth: '30rem',
    frameLabel: 'yourcompany.alliswell.space — identity',
  },

  meetings: {
    eyebrow: 'Meeting notes',
    title: 'Upload the meeting recording, take the decisions as requests',
    body:
      'A recording becomes minutes with the speakers separated, a summary and a list of ' +
      'decisions. Each decision turns into a request or a task in one tap.',
    points: [
      'Transcription uses the AI provider you choose, on your own account',
      'The minutes are an editable note; a misheard sentence is corrected by hand',
      'In the cloud Business and Enterprise packages; the monthly transcription minutes are ' +
        'set by the package',
    ],
    shot: '/shots/ee/meeting-named-light-en.jpg',
    shotDark: '/shots/ee/meeting-named-dark-en.jpg',
    alt: 'A meeting note: speakers named, a summary, and the decisions taken from it',
    frameLabel: 'yourcompany.alliswell.space — meeting',
  },

  deploy: {
    eyebrow: 'Deployment options',
    title: 'The cloud, or your own servers?',
    lede: 'The same product either way. The difference is where the data lives and who runs it.',
    options: [
      {
        key: 'cloud',
        icon: 'cloud',
        title: 'Cloud',
        tagline: 'A quick start, nothing to operate',
        points: [
          'An address of your own: yourcompany.alliswell.space',
          'Installation, backups, updates and monitoring are on us',
          'Starter, Business or Enterprise package; move up as you grow',
          'Your data is yours alone, kept apart from every other customer',
        ],
        cta: { label: 'See the cloud packages', href: '#packages' },
      },
      {
        key: 'self',
        icon: 'server',
        title: 'On your own servers',
        tagline: 'The data never leaves the factory',
        points: [
          'We install it on your server, with your database',
          'Users, units and modules are set to what you need',
          'Priced as a quote, by the number of users and units',
          'Updates and support by contract; where the data lives never changes',
        ],
        cta: { label: 'Ask for a quote', href: '#contact' },
      },
    ],
    footnote:
      'Not sure yet? Choose “Not decided yet” in the form; we decide together, by your size and ' +
      'the regulations you work under.',
  },

  packages: {
    anchor: 'packages',
    eyebrow: 'Cloud packages',
    title: 'Three ready packages in the cloud',
    lede:
      'These packages are for organisations that use the cloud. An installation on your own ' +
      'servers has no ready package; limits and modules are set to what you need.',
    caption: 'Cloud package comparison',
    featureHeading: 'Scope',
    labels: { yes: 'Yes', no: 'No', partial: 'Partial' },
    columns: ['Starter', 'Business', 'Enterprise'],
    pinnedRows: 3,
    moreLabel: 'Detailed scope',
    rows: [
      ['Users', '10', '250', 'Unlimited'],
      ['Units', '5', '50', 'Unlimited'],
      ['Audit log retention', '90 days', '1 year', '7 years'],
      [
        'External request form: active forms and requests per month',
        'Set by package',
        'Set by package',
        'Set by package',
      ],
      // EE-261: every capability row, with its level in the label.
      ...packageRows('en'),
    ],
    footnote:
      'What a package holds is written in your contract, and a package is upgraded as needs ' +
      'change. Prices are quoted by your size.',
    link: { label: 'Ask for a quote →', href: '#contact' },
  },

  deck: {
    eyebrow: 'Presentation',
    title: 'Download the presentation and share it with your colleagues',
    lede:
      'What this page tells, as an 18-page PDF. You can e-mail it to your IT, maintenance and ' +
      'production managers.',
    cover: {
      shot: '/shots/sales/deck-cover-en.jpg',
      alt: 'The presentation’s cover: “Manage every work request in your factory in one place”',
    },
    pdf: {
      href: '/downloads/alliswell-enterprise-presentation-2026-10.pdf',
      label: 'Download the presentation (PDF)',
      meta: 'PDF · 18 pages · English',
    },
    secondary: {
      label: 'Turkish presentation (PDF)',
      href: '/downloads/alliswell-enterprise-sunum-2026-10.pdf',
    },
  },

  // Slide 18
  contact: {
    eyebrow: 'Contact',
    title: 'Write to us with your questions, or to ask for a live trial or a meeting',
    lede:
      'Just tell us how many people and how many units you want to start with. We will get ' +
      'back to you and prepare a quote and an installation plan, for the cloud or for your own ' +
      'servers.',
    mailSubject: 'AllisWell Enterprise quote request',
    fields: {
      name: { label: 'Your name' },
      company: { label: 'Organisation' },
      workEmail: { label: 'Work e-mail' },
      phone: { label: 'Phone (optional)' },
      seats: { label: 'Number of users (estimate)' },
      units: { label: 'Number of units' },
      packageInterest: {
        label: 'The option you are considering',
        placeholder: 'Not decided yet',
        options: [
          'Cloud — Starter',
          'Cloud — Business',
          'Cloud — Enterprise',
          'Installation on our own servers',
        ],
      },
      message: { label: 'Anything else (your current systems, your priorities)' },
      honeypot: 'Company website',
    },
    consent: {
      text:
        'I agree that the details in this form may be stored and used to answer my enquiry, ' +
        'as described in the',
      linkLabel: 'privacy notice',
      // The SECTION, not the document: a consent link that lands on three
      // hundred lines has told the reader nothing about what they are agreeing
      // to.
      href: '/privacy#enterprise-enquiries',
    },
    submit: 'Send',
    sending: 'Sending…',
    orWrite: 'Or write to us directly:',
    sent: 'Thank you — your enquiry reached us. We will be in touch shortly.',
    // One message per outcome (EE-161). The server answers with a machine
    // -readable code and the page says it in the reader's language.
    states: {
      // NOT an apology: this installation has no sales form, so the form is
      // replaced by the address.
      noDesk:
        'This installation does not run a sales form. Write to us directly and we will get back ' +
        'to you:',
      stale:
        'Our privacy notice changed while this page was open. Please reload and send again, ' +
        'so what you agree to is what you were shown.',
      busy:
        'We are receiving a lot of enquiries right now. Please try again in a few minutes, or ' +
        'write to us directly.',
      invalid: 'Something in the form was not accepted. Please check the fields and try again.',
      offline:
        'We could not reach our servers. Your answers are still here — please try again in a ' +
        'moment, or write to us directly.',
      failed:
        'Something went wrong on our side. Your answers are still here — please try again, or ' +
        'write to us directly.',
      // EE-232 — shown only on a build that draws the verification box.
      challenge:
        'The verification was not completed, or it expired. Tick the box again and send; ' +
        'your answers are still here.',
      challengeUnavailable:
        'The verification box could not load; a content blocker or a connection problem may ' +
        'be the cause. If the form will not send, write to us directly.',
    },
  },

  faq: {
    heading: 'Frequently asked questions',
    items: [
      {
        q: 'How long does installation take, and who does it?',
        a:
          'Our team does the installation: in the cloud we open the address set aside for your ' +
          'organisation, and on your own servers we install the system on them. The real time ' +
          'goes into defining your units, service catalogue, working calendar and times ' +
          'together. We suggest a trial of a few weeks with one unit.',
      },
      {
        q: 'Can we bring over the requests in our current system?',
        a:
          'Yes. We carry over the service list, the people and past requests from ServiceDesk ' +
          'Plus, Jira or Excel at installation. We also set up your shifts, holidays and ' +
          'on-call rotas at installation.',
      },
      {
        q: 'Is there a feature difference between the cloud and our own servers?',
        a:
          'No; it is the same product. In the cloud we take care of installation, backups and ' +
          'updates. On your own servers the data never leaves your factory.',
      },
      {
        q: 'Where is our data kept, and can we take it out?',
        a:
          'On your own servers the data is entirely yours; in the cloud it is kept in an area ' +
          'that is yours alone. Either way, all data exports as one file, and the audit log as ' +
          'a table.',
      },
      {
        q: 'Does it work with Active Directory and single sign-on?',
        a:
          'Yes. An Active Directory and LDAP connection, single sign-on with systems such as ' +
          'Microsoft Entra ID (SAML, OpenID Connect) and automatic user provisioning (SCIM) come ' +
          'with the cloud Enterprise package, and in whatever scope you need on your own ' +
          'servers. ' +
          pilotNote('directory', 'en'),
      },
      {
        q: 'Do our customers need an account?',
        a:
          'No. People outside the company use the external request form and follow the status ' +
          'from a tracking link. People at contracted companies can, if you wish, sign in to ' +
          'the company portal with their own password.',
      },
      {
        q: 'How is it different from the free AllisWell?',
        a:
          'The free edition is for one person’s tasks, notes and files. Enterprise adds units, ' +
          'roles, request management, SLA tracking, the external request form and the corporate ' +
          'sign-in connection, under a commercial licence.',
      },
      {
        // EE-261: generated, never hand-written — see capabilities.js.
        key: 'notYet',
        q: 'What is not in it yet?',
        a: notYetAnswer('en'),
      },
    ],
  },

  footer: {
    blurb:
      'AllisWell Enterprise brings your factory’s internal and external requests, SLA tracking ' +
      'and your people’s daily work together in one system. A BubiApps product.',
    notes:
      'Not affiliated with Microsoft, Apple, Google, Anthropic or OpenAI. Product names belong ' +
      'to their owners.',
    privacyLabel: 'Privacy',
    supportLabel: 'Support',
    starsWord: 'stars',
    forksWord: 'forks',
    columns: [
      {
        title: 'Enterprise',
        links: [
          { label: 'Request management', href: '#itsm' },
          { label: 'SLA (service promise)', href: '#sla' },
          { label: 'Requests from outside', href: '#intake' },
          { label: 'Deployment options', href: '#deploy' },
          { label: 'Cloud packages', href: '#packages' },
          { label: 'Presentation (PDF)', href: '#deck' },
          { label: 'Get in touch', href: '#contact' },
        ],
      },
      {
        title: 'Technical documents',
        links: [
          { label: 'REST API reference', href: '/docs/api' },
          { label: 'Security policy', href: `${REPO_URL}/blob/main/SECURITY.md` },
          { label: 'Privacy policy', href: '/privacy' },
        ],
      },
      {
        title: 'The free edition',
        links: [
          { label: 'alliswell.space', href: '/' },
          { label: 'Open the app', href: APP_URL },
          { label: 'Source on GitHub', href: REPO_URL },
          { label: 'Licence (PolyForm NC)', href: `${REPO_URL}/blob/main/LICENSE` },
        ],
      },
    ],
  },

  /** The JavaScript-off block inside `#app`, kept in step with the entry HTML. */
  fallback: {
    contact: 'Write to',
    other: 'Türkçe',
    home: 'alliswell.space',
  },
};
