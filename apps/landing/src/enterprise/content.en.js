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
 * The page argues the 18-slide sales deck once, in five steps — problem,
 * solution, proof, pilot, demo request (OPH-413, page.js) — and offers the deck
 * itself as a PDF; its language comes from the deck (OPH-388), and this file
 * translates the Turkish one, `content.tr.js`, which leads. The
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
 * OPH-413 (landing-audit K9): this page shows only English sample data. The
 * screens come from `screenshots/ee/` (the app's English captures of the
 * English sample records); the sales set in `screenshots/sales/` keeps its
 * Turkish records and is the Turkish page's hero only. `ratio` is each
 * file's real pixel ratio (the same in all four variants).
 *
 * Screenshot paths are stored WHOLE (`/shots/...`), never composed,
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
      { label: 'The screens', href: '#tour' },
      { label: 'Before you decide', href: '#proof' },
      { label: 'Pilot', href: '#pilot' },
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
      'and person names are examples.',
    shot: '/shots/ee/hero-light-en.jpg',
    shotDark: '/shots/ee/hero-dark-en.jpg',
    alt:
      'A unit’s request list beside the SLA board: every row shows the subject, status, ' +
      'priority and time left, and the board shows promises kept on 76.2% of 47 requests',
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
      'The presentation (PDF) walks through each step with its screens: administration, ' +
      'request management, time tracking (SLA), people’s work and requests from outside.',
  },

  // The solution, screen by screen (OPH-413). One tabbed tour instead of a
  // section per deck slide; English captures of the English sample data
  // (`screenshots/ee/`), so this page shows no Turkish records (landing-audit K9).
  tour: {
    eyebrow: 'The solution',
    title: 'The screens your people will work in',
    lede: 'The real product on sample data. Choose a screen.',
    tabs: [
      {
        id: 'list',
        label: 'The unit’s request list',
        caption:
          'Every unit works from its own list: status, priority and the time left on each row. ' +
          'A missed SLA shows in red.',
        shot: '/shots/ee/ticket-queue-light-en.jpg',
        shotDark: '/shots/ee/ticket-queue-dark-en.jpg',
        alt:
          'A unit’s request list with status filters; “Line 3 filler belt sensor is ' +
          'double-counting, the shift has stopped” is urgent and has missed its SLA',
        frame: 'card',
        ratio: '900 / 1000',
      },
      {
        id: 'request',
        label: 'One request',
        caption:
          'Replies, internal notes, attachments, the time spent and every change stay on the ' +
          'request.',
        shot: '/shots/ee/ticket-detail-light-en.jpg',
        shotDark: '/shots/ee/ticket-detail-dark-en.jpg',
        alt:
          'A request, “Compressor pressure has dropped, the paint shop has stopped”: in ' +
          'progress, urgent, its response target missed, and the thread below',
        frame: 'card',
        ratio: '900 / 1300',
      },
      {
        id: 'sla',
        label: 'SLA board',
        caption:
          'Response and resolution times count on your working calendar. The board shows how ' +
          'many promises were kept, by unit and by service.',
        shot: '/shots/ee/sla-dashboard-light-en.jpg',
        shotDark: '/shots/ee/sla-dashboard-dark-en.jpg',
        alt:
          'The SLA board: promises kept on 76.2% of 47 requests, the counts by unit and by ' +
          'service, and the requests that missed their target',
        frame: 'card',
        ratio: '900 / 1820',
      },
      {
        id: 'outside',
        label: 'Requests from outside',
        caption:
          'Customers and suppliers open a request from a web form without an account, and ' +
          'follow it from a tracking link.',
        shot: '/shots/ee/portal-form-light-en.jpg',
        shotDark: '/shots/ee/portal-form-dark-en.jpg',
        alt:
          'The external request form for an electrical fault: e-mail address, subject, ' +
          'description, line number and shift',
        frame: 'card',
        ratio: '900 / 880',
      },
    ],
  },
  // Proof a buyer can check before signing (OPH-413). Only what is true today:
  // no customer names, no figures from a customer (WHAT THIS PAGE MAY CLAIM).
  proof: {
    eyebrow: 'Before you decide',
    title: 'What you can check for yourself',
    lede:
      'Every screen on this page is the real product. Ask for a live trial and look at it with ' +
      'your own units and services.',
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
        key: 'source',
        icon: 'file-text',
        accent: 'warning',
        title: 'Code your IT team can read',
        body:
          'It is built on the free AllisWell, whose source is public on GitHub with its ' +
          'security policy and a documented REST API.',
      },
    ],
  },
  // The pilot (OPH-413): the deck's advice, as the step before the demo request.
  pilot: {
    eyebrow: 'Pilot',
    title: 'Start with one unit, for a few weeks',
    lede:
      'You decide on figures from your own factory, not on a presentation. The package follows ' +
      'your number of people and units.',
    steps: [
      {
        n: 1,
        icon: 'server',
        title: 'We set it up',
        body:
          'In the cloud or on your servers, with your units, services and working calendar.',
      },
      {
        n: 2,
        icon: 'rocket',
        title: 'One unit works in it',
        body: 'Maintenance, for example, runs its requests here for a few weeks.',
      },
      {
        n: 3,
        icon: 'check',
        title: 'You look at the figures',
        body:
          'Response and resolution times and promises kept, measured. Then the other units follow.',
      },
    ],
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
      'Every step and screen, as an 18-page PDF. You can e-mail it to your IT, maintenance and ' +
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
          { label: 'The screens', href: '#tour' },
          { label: 'Before you decide', href: '#proof' },
          { label: 'Pilot', href: '#pilot' },
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
};
