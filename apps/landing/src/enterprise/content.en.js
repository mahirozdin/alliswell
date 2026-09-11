/**
 * Every word on the enterprise page, in English (EE-151; rewritten in EE-164).
 *
 * One file per language rather than `{en, tr}` beside every key: copy has to be
 * readable as prose to be reviewable as prose. What keeps the two honest is a
 * gate (`npm run check:copy`, EE-152) rather than a convention.
 *
 * ── WHO THIS IS WRITTEN FOR ───────────────────────────────────────────────
 *
 * A plant's general manager, its IT manager, its after-sales manager. The copy
 * uses the words they use in a meeting — "work request", "department",
 * "customer request form" — and leaves out what does not change their decision
 * (codebase, bytes, key counts). The one technical fact that DOES change it is
 * where the data lives and who can reach it, and that is written down.
 *
 * ── WHAT THIS PAGE MAY CLAIM ──────────────────────────────────────────────
 *
 *   • Packages exist for the CLOUD only. An organisation running it on its own
 *     servers never sees the operator layer; we set its limits at installation.
 *     "Manage packages after installing" cannot appear here.
 *   • The customer does not install it; we do. No "how it is installed", no
 *     docker command, no self-hosting guide on this page.
 *   • Routing is service → unit: fixed and explicit, never a rules engine.
 *   • Only screens that exist are shown; only measured numbers are written; no
 *     prices.
 *
 * Screenshot paths are stored WHOLE (`/shots/ee/...`), never composed, because
 * the CI gate greps the built bundle for those literals.
 */

export const APP_URL = '/app';
export const REPO_URL = 'https://github.com/mahirozdin/alliswell';

export default {
  lang: 'en',

  seo: {
    title: 'AllisWell Enterprise — every work request in your organisation, managed in one place',
    description:
      'Requests between departments, after-sales support requests, SLA tracking, permissions, ' +
      'tasks and documents in one system. In the cloud or on your own servers, in English and ' +
      'Turkish.',
    ogImage: '/shots/og/enterprise-en.jpg',
  },

  nav: {
    home: '/',
    links: [
      { label: 'Request management', href: '#itsm' },
      { label: 'SLAs', href: '#sla' },
      { label: 'Deployment options', href: '#deploy' },
      { label: 'Packages', href: '#packages' },
    ],
    cta: { label: 'Talk to us', href: '#contact' },
    starsLabel: 'Star',
  },

  hero: {
    eyebrow: 'AllisWell Enterprise',
    title: 'Every work request in your organisation, managed in one place',
    lede:
      'The requests your departments make of each other — maintenance, IT, HR, finance — the ' +
      'support requests that come in from customers, dealers and suppliers, and your teams’ ' +
      'day-to-day tasks, notes and files, all in one system. It runs in the cloud or on your ' +
      'own servers, and your data stays yours.',
    primary: { label: 'Talk to us', href: '#contact' },
    secondary: { label: 'Cloud or your own servers?', href: '#deploy' },
    facts: [
      'In the cloud or on your own servers',
      'English and Turkish interface',
      'Phone, tablet, web and desktop',
      'Keeps working when the internet drops',
    ],
    shot: '/shots/ee/hero-light-en.jpg',
    shotDark: '/shots/ee/hero-dark-en.jpg',
    alt:
      'Two screens side by side: a department’s request list with priorities and SLA states, ' +
      'and the SLA dashboard showing how many promises were kept, by department and by service',
  },

  personas: {
    eyebrow: 'Who it is for',
    title: 'Organisations with several departments that want every request handled in one place',
    items: [
      {
        key: 'internal',
        icon: '🏭',
        title: 'Factories and production sites',
        body:
          'Maintenance, IT, quality, logistics, HR, finance: every department is constantly ' +
          'asking another for something. Today those requests live in phone calls, e-mails and ' +
          'somebody’s spreadsheet. With AllisWell Enterprise each request lands in the right ' +
          'department, and who is on it, what state it is in and when it will be done is always ' +
          'visible.',
      },
      {
        key: 'afterSales',
        icon: '🤝',
        title: 'Companies that provide after-sales service',
        body:
          'Your customers, dealers and suppliers send you requests without an account in your ' +
          'system. Each request goes to the right team, the response time you promised is ' +
          'tracked, and the requester follows progress through their own link. Nothing gets ' +
          'lost in a shared mailbox.',
      },
      {
        key: 'regulated',
        icon: '🔐',
        title: 'Public bodies, healthcare, and anyone under KVKK or GDPR',
        body:
          'The data stays on your servers, every action is recorded, and user accounts come ' +
          'from the Active Directory you already run. Somebody who leaves loses access the same ' +
          'day, and the answer to “who changed what, and when” is ready before an audit asks.',
      },
    ],
  },

  itsm: {
    id: 'itsm',
    eyebrow: 'Request management (ITSM)',
    title: 'Each department has its own request list',
    body:
      'Everything a department is asked for is collected in one list: who asked, who is ' +
      'handling it, how urgent it is and how the promised deadline is doing. A request is ' +
      'handed out to people as tasks without losing the link to the person who asked — and ' +
      'they hear about it when it is resolved.',
    points: [
      'Every request shows its state, its priority and who owns it at a glance',
      'One request can be split into tasks for several people; each task has a clear owner',
      'The list opens and can be edited with the internet down; changes sync when the connection is back',
    ],
    shot: '/shots/ee/ticket-queue-light-en.jpg',
    shotDark: '/shots/ee/ticket-queue-dark-en.jpg',
    alt:
      'A department’s request list: four requests with priority, state, SLA status and the ' +
      'people handling them — one past its deadline, one closed on time',
    frameLabel: 'yourcompany.alliswell.space — requests',
  },

  itsmTabs: {
    eyebrow: 'The parts of request management',
    title: 'The service catalogue, routing, and the request itself',
    lede:
      'You define once which services your organisation provides; after that every request ' +
      'knows which department it belongs to.',
    tabs: [
      {
        id: 'catalogue',
        label: 'Service catalogue',
        shot: '/shots/ee/services-admin-light-en.jpg',
        shotDark: '/shots/ee/services-admin-dark-en.jpg',
        alt: 'The service catalogue: each service with the departments that provide it, one archived',
        caption:
          'Electrical faults, calibration, access cards, software installs… For each service ' +
          'you also decide which extra questions the request form asks.',
        frameLabel: 'yourcompany.alliswell.space — services',
      },
      {
        id: 'routing',
        label: 'Which department handles it',
        shot: '/shots/ee/service-routing-light-en.jpg',
        shotDark: '/shots/ee/service-routing-dark-en.jpg',
        alt: 'Connecting a service to the departments that answer it',
        caption:
          'Each service is connected to one or more departments; an incoming request lands ' +
          'directly in that department’s list. Nobody has to forward anything by hand.',
        frameLabel: 'yourcompany.alliswell.space — routing',
      },
      {
        id: 'detail',
        label: 'A request in detail',
        shot: '/shots/ee/ticket-detail-light-en.jpg',
        shotDark: '/shots/ee/ticket-detail-dark-en.jpg',
        alt:
          'One request opened: the conversation with the requester, and a separately marked ' +
          'internal note the requester never sees',
        caption:
          'The conversation with the requester and the team’s own internal notes are on the ' +
          'same screen, but marked apart: an internal note is never shown to the requester.',
        frameLabel: 'yourcompany.alliswell.space — request',
      },
    ],
  },

  sla: {
    id: 'sla',
    eyebrow: 'SLAs and service tracking',
    title: 'Response and resolution times, measured on your working hours',
    body:
      'For each service you set a target for the first response and for resolution. The clock ' +
      'follows your organisation’s working hours, shifts and public holidays, so a weekend or a ' +
      'night does not count against you. The responsible department is warned as a target ' +
      'approaches, and a miss is recorded.',
    points: [
      'Different targets per priority: an urgent breakdown and a routine request are not held to the same clock',
      'A request put on hold stops its clock; it resumes where it left off',
      'The management dashboard shows which departments and which services are keeping their promises, and which are not',
    ],
    shot: '/shots/ee/sla-dashboard-light-en.jpg',
    shotDark: '/shots/ee/sla-dashboard-dark-en.jpg',
    alt:
      'The SLA dashboard: the share of requests answered on time this period, broken down by ' +
      'department and by service, with the missed targets listed underneath',
    frameLabel: 'yourcompany.alliswell.space — SLA dashboard',
  },

  slaTabs: {
    eyebrow: 'SLA settings',
    title: 'Targets, the working calendar, and system health',
    lede: 'The definitions are made once; after that the system measures and you see the result.',
    tabs: [
      {
        id: 'targets',
        label: 'Time targets',
        shot: '/shots/ee/sla-policies-light-en.jpg',
        shotDark: '/shots/ee/sla-policies-dark-en.jpg',
        alt: 'SLA policies with first-response and resolution targets per priority',
        caption:
          'A separate first-response and resolution time for each priority level — counted ' +
          'around the clock, or only within working hours, as you choose.',
        frameLabel: 'yourcompany.alliswell.space — SLA targets',
      },
      {
        id: 'calendar',
        label: 'Working calendar',
        shot: '/shots/ee/sla-calendars-light-en.jpg',
        shotDark: '/shots/ee/sla-calendars-dark-en.jpg',
        alt: 'A working calendar with its hours and public holidays',
        caption:
          'Working hours, shifts, public holidays and a time zone. A three-shift plant and a ' +
          'nine-to-five office use different calendars.',
        frameLabel: 'yourcompany.alliswell.space — calendars',
      },
      {
        id: 'health',
        label: 'System health',
        shot: '/shots/ee/sla-monitors-light-en.jpg',
        shotDark: '/shots/ee/sla-monitors-dark-en.jpg',
        alt: 'Health checks watching the addresses of critical systems, with their intervals and last results',
        caption:
          'Have the addresses of your critical applications watched: when one stops answering, ' +
          'a record is opened automatically, and the recovery is noted on the same record.',
        frameLabel: 'yourcompany.alliswell.space — system health',
      },
    ],
  },

  portal: {
    eyebrow: 'After-sales service and external requests',
    title: 'Let your customers and dealers send requests without an account',
    lede:
      'Creating a user account for every customer is impractical, and a shared mailbox cannot ' +
      'be tracked. With AllisWell Enterprise you publish a public request form for each ' +
      'service: whoever fills it in sends a request without signing in, it lands with the right ' +
      'team, and its progress can be followed from outside.',
    steps: [
      {
        n: 1,
        title: 'You publish a request form',
        body:
          'The form is tied to one service and to the department that provides it. You can give ' +
          'the link an expiry date and a monthly quota, pause it at any time, or cancel it for ' +
          'good.',
        shot: '/shots/ee/portal-links-light-en.jpg',
        shotDark: '/shots/ee/portal-links-dark-en.jpg',
        alt:
          'The request forms screen: four published forms with their service, expiry and quota ' +
          'usage; the cancelled one has lost its controls',
        frameLabel: 'yourcompany.alliswell.space — request forms',
      },
      {
        n: 2,
        title: 'Your customer fills it in',
        body:
          'No account, no app to install. The form carries your name, your logo and your ' +
          'corporate colour, and opens in English or Turkish depending on the visitor’s browser.',
        shot: '/shots/ee/portal-form-light-en.jpg',
        shotDark: '/shots/ee/portal-form-dark-en.jpg',
        alt:
          'The public request form: the company name, the service, an e-mail field, a subject, ' +
          'a description and the two extra questions this service asks',
        frameLabel: 'yourcompany.alliswell.space/p/…',
      },
      {
        n: 3,
        title: 'The request lands directly with the right department',
        body:
          'Whichever department the service is connected to, the request appears in that ' +
          'department’s list. Nobody has to forward an e-mail or pick up the phone in between.',
      },
      {
        n: 4,
        title: 'The clock starts, and the team is told',
        body:
          'The SLA target attached to the service kicks in. The team receives one combined ' +
          'notification rather than one per request: on a busy day, one list instead of forty ' +
          'e-mails.',
      },
      {
        n: 5,
        title: 'The requester follows progress',
        body:
          'Whoever filled in the form receives a tracking link. The page behind it shows the ' +
          'subject, the current state and the date of the last update; no sign-in required.',
        shot: '/shots/ee/portal-follow-light-en.jpg',
        shotDark: '/shots/ee/portal-follow-dark-en.jpg',
        alt: 'The tracking page: the request’s subject, a status of Received, and the dates it was sent and last updated',
        frameLabel: 'yourcompany.alliswell.space/t/…',
      },
    ],
    aside: {
      title: 'A public form, protected against abuse',
      body:
        'Your real customers use the form without friction; against automated submissions ' +
        'there are four layers of protection:',
      points: [
        'A hidden trap field that catches automated submissions and that people never see.',
        'A rate limit on repeated submissions from the same address and to the same form.',
        'A monthly request quota: rejected submissions do not count against it and cost you nothing.',
        'An optional extra verification step; expired or cancelled links close without giving anything away.',
      ],
    },
  },

  org: {
    id: 'org',
    eyebrow: 'Organisation structure',
    title: 'Departments, exactly as they are on your org chart',
    body:
      'Every department, workshop or branch is a unit in the system. Tasks, requests, notes and ' +
      'files belong to the unit rather than to a person, so nothing is lost when somebody ' +
      'leaves or changes department. Sharing between units is granted explicitly, and ' +
      'disappears when it is withdrawn.',
    points: [
      'Each employee sees only the data of the units they belong to, and only that data reaches their device',
      'Your organisation signs in at its own address (for example yourcompany.alliswell.space); there is no contact with any other organisation’s data',
      'New users join by invitation only; an invitation link expires and can be cancelled',
    ],
    shot: '/shots/ee/units-admin-light-en.jpg',
    shotDark: '/shots/ee/units-admin-dark-en.jpg',
    alt: 'The units screen: four departments with member counts, one that you run and one archived',
    frameLabel: 'yourcompany.alliswell.space — units',
  },

  orgTabs: {
    eyebrow: 'Permissions and roles',
    title: 'Who may do what, and who did what',
    lede:
      'Permissions are not limited to a few preset roles. A rule such as “a maintenance ' +
      'supervisor may assign requests within their own department but may not close them” is ' +
      'something your administrator defines themselves.',
    tabs: [
      {
        id: 'roles',
        label: 'Roles and permissions',
        shot: '/shots/ee/team-roles-light-en.jpg',
        shotDark: '/shots/ee/team-roles-dark-en.jpg',
        alt: 'The role editor: a matrix of individually granted permissions across roles',
        caption:
          'Dozens of permissions — creating tasks, closing requests, sharing files — are switched ' +
          'on and off individually, and roles can be defined per department.',
        frameLabel: 'yourcompany.alliswell.space — roles',
      },
      {
        id: 'delegated',
        label: 'A department manager’s view',
        shot: '/shots/ee/units-manager-light-en.jpg',
        shotDark: '/shots/ee/units-manager-dark-en.jpg',
        alt: 'The same units screen as a department manager sees it: only their own department',
        caption:
          'A department manager manages only their own department; actions they are not ' +
          'allowed to take are not greyed out — they are simply not there.',
        frameLabel: 'yourcompany.alliswell.space — units',
      },
      {
        id: 'history',
        label: 'Activity history',
        shot: '/shots/ee/ticket-history-light-en.jpg',
        shotDark: '/shots/ee/ticket-history-dark-en.jpg',
        alt:
          'The history of one request: created, assigned, state changed, an SLA target recorded ' +
          'as missed by the system, updated',
        caption:
          'Every request and task records who did what and when. The organisation-wide ' +
          'activity log can be exported for audits.',
        frameLabel: 'yourcompany.alliswell.space — history',
      },
    ],
  },

  workspace: {
    id: 'work',
    eyebrow: 'Day-to-day work',
    title: 'Tasks, projects, notes and files, in the same system',
    body:
      'Alongside request management, your teams run their daily work here too: personal and ' +
      'shared task lists, project-based work tracking, meeting notes and company documents. A ' +
      'request becomes a task in one click; files and notes attach to any task.',
    points: [
      'Overdue, today and this week in one list, with a month calendar beside it',
      'Reminders ring even when the phone is on silent, so urgent work is not missed',
      'Two-way sync with Google and Apple calendars: tasks in the calendar, the calendar next to the tasks',
    ],
    shot: '/shots/ee/work-home-light-en.jpg',
    shotDark: '/shots/ee/work-home-dark-en.jpg',
    alt:
      'Home: overdue, today and this week’s tasks in one list with project and tag badges, and ' +
      'a month calendar on the right',
    frameLabel: 'yourcompany.alliswell.space — tasks',
  },

  workspaceTabs: {
    eyebrow: 'Teamwork',
    title: 'Board, projects, notes and files',
    lede:
      'Every team works the way it is used to: some want a list, some want a board. Both are ' +
      'views of the same data.',
    tabs: [
      {
        id: 'board',
        label: 'Board',
        shot: '/shots/ee/work-board-light-en.jpg',
        shotDark: '/shots/ee/work-board-dark-en.jpg',
        alt: 'The board view: task cards in open, in-progress, waiting and completed columns',
        caption:
          'Open, in progress, waiting and completed work as columns; cards are dragged between ' +
          'them, and the columns are arranged to suit the team.',
        frameLabel: 'yourcompany.alliswell.space — board',
      },
      {
        id: 'projects',
        label: 'Projects',
        shot: '/shots/ee/work-projects-light-en.jpg',
        shotDark: '/shots/ee/work-projects-dark-en.jpg',
        alt: 'The projects screen: project cards with their colour and progress',
        caption:
          'Each project keeps its tasks, notes and files together; progress and owners are ' +
          'visible on one page.',
        frameLabel: 'yourcompany.alliswell.space — projects',
      },
      {
        id: 'notes',
        label: 'Notes',
        shot: '/shots/ee/work-notes-light-en.jpg',
        shotDark: '/shots/ee/work-notes-dark-en.jpg',
        alt: 'The notes screen: pinned notes and notes attached to projects',
        caption:
          'Meeting notes, instructions, procedures: formatted text with headings, tables and ' +
          'images, exportable as PDF.',
        frameLabel: 'yourcompany.alliswell.space — notes',
      },
      {
        id: 'files',
        label: 'Files',
        shot: '/shots/ee/work-files-light-en.jpg',
        shotDark: '/shots/ee/work-files-dark-en.jpg',
        alt: 'The files screen: folders and uploaded company documents',
        caption:
          'A company document archive organised in folders; every file shows which task or ' +
          'project it is attached to.',
        frameLabel: 'yourcompany.alliswell.space — files',
      },
    ],
  },

  identity: {
    id: 'identity',
    eyebrow: 'Corporate identity',
    title: 'Users come from the Active Directory you already run',
    body:
      'There is no separate user list to maintain. An Active Directory or LDAP connection, ' +
      'single sign-on with systems such as Microsoft Entra ID (SAML, OpenID Connect) and ' +
      'automatic user provisioning (SCIM) are all supported. Directory groups map to ' +
      'departments: an account opens when somebody joins, and closes the day they leave.',
    points: [
      'Single sign-on: employees sign in with the corporate password they already use',
      'Group membership decides the department; nothing is assigned by hand',
      'If a connection setting is missing, the system names it; a half-configured provider cannot be switched on',
    ],
    shot: '/shots/ee/team-identity-light-en.jpg',
    shotDark: '/shots/ee/team-identity-dark-en.jpg',
    alt:
      'The identity sources screen: an Active Directory connection and a Microsoft Entra ID ' +
      'provider both live, and one SAML provider naming the settings it still needs',
    frameLabel: 'yourcompany.alliswell.space — identity',
  },

  security: {
    eyebrow: 'Data security',
    title: 'Data privacy and data integrity',
    items: [
      {
        key: 'residency',
        icon: '🗄️',
        title: 'Where is your data kept?',
        body:
          'If you chose your own servers: on your server, in your database, behind your ' +
          'firewall. In the cloud: in a space that belongs only to you, completely separate ' +
          'from other customers. Nothing leaves your organisation unless you connect it yourself.',
      },
      {
        key: 'access',
        icon: '🔐',
        title: 'Who can reach your data?',
        body:
          'Each employee sees only the data of the departments they belong to, and what they ' +
          'may do is set by their role. The password policy and lockout are yours to define, ' +
          'two-step sign-in uses an authenticator app, and every user’s open sessions and ' +
          'devices are listed — an administrator can end one remotely when needed.',
      },
      {
        key: 'audit',
        icon: '📜',
        title: 'Every action on the record',
        body:
          'Every action on a request, task, note or file is recorded with its date, time and ' +
          'person. Records cannot be altered or deleted afterwards; you set the retention ' +
          'period and export the log for audits. The answer to “who changed what, and when” ' +
          'is always ready.',
      },
      {
        key: 'integrity',
        icon: '🛡️',
        title: 'Backups, portability and KVKK/GDPR',
        body:
          'Changes made while the internet is down are kept on the device and synchronised ' +
          'when the connection returns; no record is left half-written. In the cloud, regular ' +
          'backups are our responsibility; on your own servers they follow our backup and ' +
          'restore guide. Your organisation’s entire data exports as one document, and one ' +
          'person’s data can be erased on request. KVKK and GDPR requirements are part of the ' +
          'system.',
      },
    ],
  },

  meetings: {
    id: 'meetings',
    eyebrow: 'Meeting notes',
    title: 'Upload the recording, get the decisions as work',
    body:
      'Upload the audio recording of a meeting and get back a transcript that separates who ' +
      'said what, a summary, and the list of decisions taken. Each decision becomes a request ' +
      'or a task in one click. Transcription runs through the AI provider and the account you ' +
      'choose, and usage is metered by the minute.',
    points: [
      'You decide which provider is used and where the data is processed',
      'The transcript is an editable note; a misheard sentence is corrected by hand',
      'Monthly transcription minutes are capped by the package, so there is no surprise invoice',
    ],
    shot: '/shots/ee/meeting-named-light-en.jpg',
    shotDark: '/shots/ee/meeting-named-dark-en.jpg',
    alt: 'A meeting note: speakers named, the summary, and the decisions pulled out of it',
    frameLabel: 'yourcompany.alliswell.space — meeting',
  },

  deploy: {
    eyebrow: 'Deployment options',
    title: 'Cloud, or your own servers?',
    lede:
      'The same product and the same features either way. The difference is where the data ' +
      'lives and who runs the installation.',
    options: [
      {
        key: 'cloud',
        icon: '☁️',
        title: 'Cloud',
        tagline: 'A fast start, with nothing to operate',
        points: [
          'Your own address: yourcompany.alliswell.space',
          'Installation, backups, updates and monitoring are handled by us',
          'You pick the Starter, Business or Enterprise package, and move up as you grow',
          'Your data is kept in a space that belongs only to you, separate from other customers',
        ],
        cta: { label: 'See the cloud packages', href: '#packages' },
      },
      {
        key: 'self',
        icon: '🏢',
        title: 'Your own servers (on-premise)',
        tagline: 'The data never leaves the organisation',
        points: [
          'We install it on your server, against your database; commissioning is done together with our team',
          'The number of users, the number of departments and the modules (request management, the public request form, the Active Directory connection…) are set to your needs',
          'Pricing is quoted per organisation, by the number of users and departments',
          'Updates and support are covered by the agreement; the data never moves',
        ],
        cta: { label: 'Ask for a quote', href: '#contact' },
      },
    ],
    footnote:
      'Undecided? Choose “not decided yet” on the form; we will work it out together from the ' +
      'size of your organisation and the regulations you are under.',
  },

  packages: {
    anchor: 'packages',
    eyebrow: 'Cloud packages',
    title: 'Three ready-made packages in the cloud',
    lede:
      'These packages are for organisations using AllisWell in the cloud, at alliswell.space. ' +
      'An installation on your own servers has no fixed package: the limits and modules are ' +
      'set to your needs.',
    caption: 'Cloud package comparison',
    featureHeading: 'What is included',
    labels: { yes: 'Included', no: 'Not included', partial: 'Partial' },
    columns: ['Starter', 'Business', 'Enterprise'],
    rows: [
      ['Users', '10', '250', 'Unlimited'],
      ['Units (departments)', '5', '50', 'Unlimited'],
      ['Public request form: active forms and requests per month', 'Set by the package', 'Set by the package', 'Set by the package'],
      ['Activity history retained', '90 days', '1 year', '7 years'],
      ['Request management, SLAs, system health monitoring', 'yes', 'yes', 'yes'],
      ['Units, permissions, activity log', 'yes', 'yes', 'yes'],
      ['Public request form', 'yes', 'yes', 'yes'],
      ['Tasks, projects, notes, files', 'yes', 'yes', 'yes'],
      ['Meeting notes (AI) and monthly transcription minutes', 'no', 'yes', 'yes'],
      ['Active Directory / single sign-on / SCIM', 'no', 'no', 'yes'],
    ],
    footnote:
      'What a package includes is written in your agreement, and a package is upgraded as your ' +
      'needs change. Prices are quoted per organisation; there is no price list on this page.',
    link: { label: 'Ask for a quote →', href: '#contact' },
  },

  contact: {
    eyebrow: 'Talk to us',
    title: 'Tell us briefly about your organisation, and we will prepare a quote',
    lede:
      'How many users and how many departments is enough to start. We come back to you ' +
      'shortly with a quote and an installation plan — for the cloud or for your own servers, ' +
      'whichever fits.',
    mailSubject: 'AllisWell Enterprise quote request',
    fields: {
      name: { label: 'Your name' },
      company: { label: 'Organisation' },
      workEmail: { label: 'Work e-mail' },
      phone: { label: 'Phone (optional)' },
      seats: { label: 'Number of users (estimate)' },
      units: { label: 'Number of departments' },
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
      message: { label: 'Anything else (current systems, priorities)' },
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
    sent: 'Thank you — your enquiry reached us. Our team will be in touch shortly.',
    // One message per outcome (EE-161). The server answers with a machine
    // -readable code and the page says it in the reader's language.
    states: {
      // NOT an apology: this installation has no sales desk, so the form is
      // replaced by the address.
      noDesk: 'This installation does not run a sales form. Write to us directly and we will get back to you:',
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
    },
  },

  faq: {
    heading: 'Frequently asked questions',
    items: [
      {
        q: 'Is there a difference in features between the cloud and our own servers?',
        a:
          'No; it is the same product. In the cloud we take care of installation, backups and ' +
          'updates. On your own servers the data never leaves your organisation, and the limits ' +
          'and modules are set to your needs.',
      },
      {
        q: 'Who installs it, and how long does it take?',
        a:
          'In the cloud your account is opened straight away. On your own servers our team does ' +
          'the installation; with the server ready it is done in a day. What takes time is ' +
          'defining your departments, your services and your time targets together — and that ' +
          'is the part worth taking time over.',
      },
      {
        q: 'Where is our data kept, and can we take it out?',
        a:
          'On your own servers the data is entirely on your server. In the cloud it is kept in ' +
          'a space that belongs only to you. In both cases your organisation’s entire data ' +
          'exports as one document and the activity log as a table; you are never locked in.',
      },
      {
        q: 'Does it work with the Active Directory we already have?',
        a:
          'Yes. An Active Directory or LDAP connection, single sign-on with Microsoft Entra ID ' +
          'and similar systems, and automatic user provisioning are included in the cloud ' +
          'Enterprise package, and in whatever scope you need on your own servers.',
      },
      {
        q: 'Do our customers need an account in the system?',
        a:
          'No. Somebody outside the organisation uses the public request form, and follows ' +
          'the request afterwards without signing in. Your own employees sign in with an account.',
      },
      {
        q: 'How is this different from the free AllisWell?',
        a:
          'The free edition is for one person’s tasks, notes and files. Enterprise adds ' +
          'departments, permissions, request management, SLA tracking, the public request form ' +
          'and the corporate identity connection, and is used under a commercial licence.',
      },
      {
        q: 'What is not in it yet?',
        a:
          'There is no asset (inventory) register, no change-approval workflow, no customer ' +
          'satisfaction survey, and no custom report designer beyond the dashboard. Requests ' +
          'cannot be opened by e-mail yet; they come in through the form and the app. We would ' +
          'rather say so up front.',
      },
    ],
  },

  footer: {
    blurb:
      'AllisWell Enterprise brings internal and external work requests, SLA tracking, ' +
      'permissions and your teams’ daily work together in one system. In the cloud or on your ' +
      'own servers.',
    notes:
      'Not affiliated with Microsoft, Apple, Google, Anthropic or OpenAI. Product names are ' +
      'their owners’.',
    privacyLabel: 'Privacy',
    supportLabel: 'Support',
    columns: [
      {
        title: 'Enterprise',
        links: [
          { label: 'Request management', href: '#itsm' },
          { label: 'SLAs and service tracking', href: '#sla' },
          { label: 'Public request form', href: '#portal' },
          { label: 'Corporate identity and security', href: '#identity' },
          { label: 'Deployment options', href: '#deploy' },
          { label: 'Cloud packages', href: '#packages' },
          { label: 'Talk to us', href: '#contact' },
        ],
      },
      {
        title: 'Technical documents',
        links: [
          { label: 'Architecture', href: `${REPO_URL}/blob/main/docs/ARCHITECTURE.md` },
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
