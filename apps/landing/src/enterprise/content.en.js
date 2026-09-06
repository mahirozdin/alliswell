/**
 * Every word on the enterprise page, in English (EE-151).
 *
 * One file per language rather than `{en, tr}` beside every key: copy has to be
 * readable as prose to be reviewable as prose, which is the same reason
 * `src/content.js` gives for existing at all. What keeps the two honest is a
 * gate (`npm run check:copy`, EE-152) rather than a convention.
 *
 * ── WHAT THIS PAGE MAY CLAIM ──────────────────────────────────────────────
 *
 * The page it replaces went stale: it told readers for four epics that
 * directory integration was not included, while LDAP, SAML, OIDC and SCIM had
 * shipped. So the copy here is derived from the code, and four rules bind it:
 *
 *   • Packages describe what a team is SOLD, not a hard boundary around each
 *     feature. Six of the ten entitlement keys are declared and read by
 *     nothing; selling them as modules would be selling a promise nobody keeps.
 *   • Routing is service → unit → workspace: static, deterministic, and it
 *     refuses rather than guesses. It is not a rules engine and must never be
 *     written as one.
 *   • A screen a customer cannot open is not a feature. The team-wide audit
 *     screen exists in the source and in no router.
 *   • Numbers are the ones that were measured. "Tested at a million requests"
 *     is true; a millisecond figure is not, because the same query moved 23×
 *     between machines.
 *
 * Screenshot paths are stored WHOLE (`/shots/ee/...`), never composed, because
 * the CI gate greps the built bundle for those literals — a path assembled at
 * runtime is a path it cannot see.
 */

export const APP_URL = '/app';
export const REPO_URL = 'https://github.com/mahirozdin/alliswell';

export default {
  lang: 'en',

  seo: {
    title: 'AllisWell Enterprise — service desk, units and SLAs on your own servers',
    description:
      'Teams, subdomains, permissions, units, ITSM with SLAs and service health, a public ' +
      'request portal and meeting-note AI — self-hosted, offline-first, on your own database.',
    ogImage: '/shots/og/enterprise-en.jpg',
  },

  nav: {
    home: '/',
    links: [
      { label: 'The service desk', href: '#itsm' },
      { label: 'SLAs', href: '#sla' },
      { label: 'Identity', href: '#identity' },
      { label: 'Packages', href: '#packages' },
    ],
    cta: { label: 'Talk to us', href: '#contact' },
    starsLabel: 'Star',
  },

  hero: {
    eyebrow: 'AllisWell Enterprise',
    title: 'A service desk your organisation runs, on your own servers',
    lede:
      'Teams, units and permissions. A service catalogue whose promises are measured on a ' +
      'business calendar rather than a wall clock. A public request form for the people who ' +
      'have no account and should not need one. Installed on your hardware, against your own ' +
      'database — and still working when the Wi-Fi on the shop floor is not.',
    primary: { label: 'Talk to us', href: '#contact' },
    secondary: { label: 'How it is installed', href: '#ops' },
    shot: '/shots/ee/hero-light-en.jpg',
    shotDark: '/shots/ee/hero-dark-en.jpg',
    alt:
      'Two screens side by side: a unit’s request queue with priorities and SLA states, and ' +
      'the SLA dashboard showing 76.2% of promises kept across 47 requests, broken down by ' +
      'desk and by service',
  },

  personas: {
    eyebrow: 'Who it is for',
    title: 'Three organisations, one shape',
    items: [
      {
        key: 'internal',
        icon: '🏭',
        title: 'Departments that serve each other',
        body:
          'Accounting, maintenance, IT, quality, logistics — every one of them a unit with ' +
          'its own work and its own inbox, all filing requests on each other. Today that ' +
          'traffic is a shared mailbox and somebody’s spreadsheet, and nobody can answer ' +
          '“how many are open in maintenance right now” without asking maintenance.',
      },
      {
        key: 'msp',
        icon: '🤝',
        title: 'Firms that support other firms',
        body:
          'Your customers need to reach you without an account, your contracts name response ' +
          'times, and missing one has a price. A published form per customer, routed to the ' +
          'team that answers it, with the promise measured rather than remembered.',
      },
      {
        key: 'regulated',
        icon: '🔐',
        title: 'Organisations that must show their work',
        body:
          'Public bodies, hospitals, anyone under KVKK or GDPR: the data stays on hardware ' +
          'you control, every change has a name against it, and accounts come from the ' +
          'directory you already run — so somebody who leaves loses access the same day.',
      },
    ],
  },

  proof: {
    eyebrow: 'Measured, not claimed',
    title: 'What we can show you rather than tell you',
    items: [
      {
        value: '1,000,000',
        label: 'requests in the benchmark suite',
        note: 'The compliance dashboard is measured against a million-row desk in CI.',
      },
      {
        value: '49',
        label: 'named permissions, enforced at three doors',
        note: 'REST, device sync and the AI connector read one ledger; CI fails on a gap.',
      },
      {
        value: '2',
        label: 'languages, all the way down',
        note: 'Screens, e-mail and the public request form — 634 keys in each.',
      },
      {
        value: '6',
        label: 'platforms from one codebase',
        note: 'iOS, Android, web, macOS, Windows, Linux.',
      },
      {
        value: '0',
        label: 'bytes that leave your network',
        note: 'Unless you connect something yourself, and then only what you connect.',
      },
    ],
  },

  portal: {
    eyebrow: 'The public request portal',
    title: 'Someone outside your company needs something. They have no account.',
    lede:
      'Giving a supplier a login is usually the wrong answer, and a shared mailbox is not an ' +
      'answer at all. A team publishes a request form at a public address that routes into ' +
      'the unit which answers it — and everything after that is the same system your own ' +
      'people work in.',
    steps: [
      {
        n: 1,
        title: 'An administrator publishes a form',
        body:
          'It is bound to one service and, when several units offer it, to one unit. It ' +
          'carries an expiry, a switch that pauses it, a cap on how much it can be used, and ' +
          'a revoke that is permanent. The address is shown once: the server keeps only a ' +
          'hash of it, so a link that leaks can be killed but not recovered.',
        shot: '/shots/ee/portal-links-light-en.jpg',
        shotDark: '/shots/ee/portal-links-dark-en.jpg',
        alt:
          'The portal links screen: four published forms with their service, expiry, usage ' +
          'against quota, and controls that disappear once a link is revoked',
        frameLabel: 'yourteam.yourdomain — request forms',
      },
      {
        n: 2,
        title: 'A stranger fills it in',
        body:
          'No account, no app, and no JavaScript — the page is rendered by the server and its ' +
          'content policy forbids scripts outright, because it is the one door in this ' +
          'product that opens without a credential. It picks its language from the browser, ' +
          'and it carries your name, your logo and your colour rather than ours.',
        shot: '/shots/ee/portal-form-light-en.jpg',
        shotDark: '/shots/ee/portal-form-dark-en.jpg',
        alt:
          'The public request form: the company name, the service, an e-mail field, a subject, ' +
          'a description and the two custom fields this service asks for',
        frameLabel: 'yourteam.yourdomain/p/…',
      },
      {
        n: 3,
        title: 'It lands where it is answered',
        body:
          'The service says which unit answers it, and the request goes to that unit’s queue. ' +
          'This is deliberate rather than clever: there is no rule engine to configure and ' +
          'nothing is guessed. A service nobody answers cannot receive anything, and a ' +
          'service several units offer is refused rather than sent to the wrong desk.',
      },
      {
        n: 4,
        title: 'The clock starts, and the unit is told once',
        body:
          'The SLA policy attached to that service opens a first-response clock and a ' +
          'resolution clock. The unit gets one notification for the batch rather than one per ' +
          'request — a desk that receives forty in an afternoon gets a list, not forty ' +
          'e-mails.',
      },
      {
        n: 5,
        title: 'The person who asked can follow it',
        body:
          'They get an acknowledgement and a link. The page behind it shows the subject, the ' +
          'status and two dates — and the status is deliberately coarser than yours: your ' +
          'seven states become five, because “we cancelled your request” is a conversation ' +
          'for a person to have, not a word for a status page to break to them.',
        shot: '/shots/ee/portal-follow-light-en.jpg',
        shotDark: '/shots/ee/portal-follow-dark-en.jpg',
        alt:
          'The follow page: the request’s subject, a status of Received, and the dates it was ' +
          'submitted and last updated',
        frameLabel: 'yourteam.yourdomain/t/…',
      },
    ],
    aside: {
      title: 'It is the open door, so it is treated like one',
      body:
        'Four layers, none of which asks a legitimate visitor for anything:',
      points: [
        'A trap field hidden from the eye, the keyboard and the screen reader alike.',
        'A ceiling per address and a second one per form, because a botnet has many addresses and one target.',
        'A monthly quota checked before any work is done and spent only if the request is accepted, so refused spam costs the team nothing.',
        'An optional challenge that fails closed, and a suspended team that accepts nobody new.',
        'Every refusal — wrong host, unknown link, expired, revoked, paused — answers with the same page, so a scanner learns nothing from the difference.',
      ],
    },
  },

  itsm: {
    id: 'itsm',
    eyebrow: 'The service desk',
    title: 'A queue a unit actually works from',
    body:
      'A request is a promise to someone; a task is work on a list. Keeping them different ' +
      'things is what lets a request become assigned work without losing the thread back to ' +
      'the person who asked. Priority, status and the state of the promise are on every row, ' +
      'legible in a photograph of a screen taken across a plant floor.',
    points: [
      'Seven states with a transition map the server enforces — and no reopen after close: a matter that comes back is a new request, linked to the old one',
      'Works offline. The queue is on the device, readable and editable, before the network comes back',
      'One request becomes many tasks; a task belongs to at most one request',
    ],
    shot: '/shots/ee/ticket-queue-light-en.jpg',
    shotDark: '/shots/ee/ticket-queue-dark-en.jpg',
    alt:
      'A unit’s request queue: four requests with priority dots, status, SLA state and ' +
      'assignee avatars, one marked SLA missed and one closed with the promise kept',
    frameLabel: 'yourteam.yourdomain — requests',
  },

  itsmTabs: {
    eyebrow: 'And the rest of the desk',
    title: 'What can be asked for, who answers it, and what happened',
    lede:
      'The catalogue is the part most service desks skip, and it is the part that makes the ' +
      'rest work: a request that names a service can be routed without a human reading it.',
    tabs: [
      {
        id: 'catalogue',
        label: 'The catalogue',
        shot: '/shots/ee/services-admin-light-en.jpg',
        shotDark: '/shots/ee/services-admin-dark-en.jpg',
        alt: 'The service catalogue: services with the units that answer them, one archived',
        caption:
          'Each service can ask its own questions — a small closed set of field types, so a ' +
          'form stays a form and not a programming language.',
        frameLabel: 'yourteam.yourdomain — services',
      },
      {
        id: 'routing',
        label: 'Who answers',
        shot: '/shots/ee/service-routing-light-en.jpg',
        shotDark: '/shots/ee/service-routing-dark-en.jpg',
        alt: 'Routing a service to the units that answer it',
        caption:
          'A service routed to nobody is refused rather than queued somewhere hopeful. That ' +
          'refusal is the feature.',
        frameLabel: 'yourteam.yourdomain — routing',
      },
      {
        id: 'detail',
        label: 'One request',
        shot: '/shots/ee/ticket-detail-light-en.jpg',
        shotDark: '/shots/ee/ticket-detail-dark-en.jpg',
        alt:
          'One request opened: the conversation, with an internal note marked by a tint, a ' +
          'lock and the words “the requester cannot see this”',
        caption:
          'An internal note is marked three ways at once, because colour fails a colour-blind ' +
          'reader, an icon fails at a glance on a dirty screen, and the word is the easiest to ' +
          'skim past.',
        frameLabel: 'yourteam.yourdomain — request',
      },
    ],
  },

  sla: {
    id: 'sla',
    eyebrow: 'SLAs and service health',
    title: 'A promise measured on your calendar, not a wall clock',
    body:
      'A factory does not stop at 18:00, and a target measured against a three-shift day is a ' +
      'different number from one measured against nine-to-five. Response and resolution ' +
      'targets run on working hours, holidays and the team’s own time zone — and a night ' +
      'shift is one row rather than two, because 22:00 to 06:00 is one interval and not two ' +
      'halves split at midnight.',
    points: [
      'The clock accumulates rather than subtracts, so a request bounced to “waiting” and back does not reset the promise',
      'A warning at 80 %, a breach that sticks even after the request is closed, and an escalation counted in working minutes rather than elapsed ones',
      'Editing your hours moves what happens next, never what already happened: the target and the calendar are frozen onto the clock when it starts',
    ],
    shot: '/shots/ee/sla-dashboard-light-en.jpg',
    shotDark: '/shots/ee/sla-dashboard-dark-en.jpg',
    alt:
      'The SLA dashboard: 76.2% of promises kept across 47 requests, broken down by desk and ' +
      'by service, with the missed targets listed underneath',
    frameLabel: 'yourteam.yourdomain — SLA',
  },

  slaTabs: {
    eyebrow: 'The parts of the promise',
    title: 'Targets, hours, and the URL you are already watching',
    lede:
      'And one number that is deliberately allowed to be nothing: a desk where no promise has ' +
      'come due yet shows a dash rather than a cheerful hundred per cent.',
    tabs: [
      {
        id: 'targets',
        label: 'Targets',
        shot: '/shots/ee/sla-policies-light-en.jpg',
        shotDark: '/shots/ee/sla-policies-dark-en.jpg',
        alt: 'SLA policies with first-response and resolution targets per priority',
        caption:
          'First response and resolution, per priority. A policy with no calendar is 24/7 — a ' +
          'real contract, not a missing setting.',
        frameLabel: 'yourteam.yourdomain — SLA policies',
      },
      {
        id: 'calendar',
        label: 'Working hours',
        shot: '/shots/ee/sla-calendars-light-en.jpg',
        shotDark: '/shots/ee/sla-calendars-dark-en.jpg',
        alt: 'A business calendar with working intervals and holidays',
        caption:
          'Hours, holidays and a time zone per calendar. Daylight saving is handled rather ' +
          'than approximated, and a calendar with no hours in it is refused.',
        frameLabel: 'yourteam.yourdomain — calendars',
      },
      {
        id: 'health',
        label: 'Service health',
        shot: '/shots/ee/sla-monitors-light-en.jpg',
        shotDark: '/shots/ee/sla-monitors-dark-en.jpg',
        alt: 'Health checks watching service URLs, with their intervals and last results',
        caption:
          'A watched URL that goes down opens one incident, and does not open another a ' +
          'minute later. When it recovers, the recovery is written onto the same one.',
        frameLabel: 'yourteam.yourdomain — health',
      },
    ],
  },

  org: {
    id: 'org',
    eyebrow: 'The organisation',
    title: 'Units are the shape of the company, not a folder',
    body:
      'A unit is a department, a workshop, a site — whatever shape yours actually has. Units ' +
      'own their content and their inbox, and content follows the unit rather than the ' +
      'person, so somebody moving desks does not take a year of requests with them. Each team ' +
      'gets its own address, and a request for another team’s data comes back as a plain 404 ' +
      'that does not even admit the team exists.',
    points: [
      'Sharing across units is explicit, granted for something specific, and disappears on the other side when it is withdrawn',
      'A device syncs exactly the units its owner belongs to — the boundary is enforced by what arrives, not by what is hidden',
      'Registration on a team’s address is invitation only, and the whole flow completes on an instance with no mail server at all',
    ],
    shot: '/shots/ee/units-admin-light-en.jpg',
    shotDark: '/shots/ee/units-admin-dark-en.jpg',
    alt:
      'The units screen: four units with member counts, one marked as the one you run and one ' +
      'archived',
    frameLabel: 'yourteam.yourdomain — units',
  },

  orgTabs: {
    eyebrow: 'Permissions, and the record',
    title: 'Who may do what, and who did what',
    lede:
      'Access is described by named permissions rather than three fixed roles, so “a ' +
      'maintenance supervisor may reassign within their unit but may not close a request” is ' +
      'something an administrator writes rather than something they file a feature request ' +
      'about.',
    tabs: [
      {
        id: 'roles',
        label: 'Roles',
        shot: '/shots/ee/team-roles-light-en.jpg',
        shotDark: '/shots/ee/team-roles-dark-en.jpg',
        alt: 'The role editor: a grant matrix of named permissions across roles',
        caption:
          'Custom roles are stored as differences from a base rather than as a full set, so a ' +
          'role you narrowed still receives every permission added later.',
        frameLabel: 'yourteam.yourdomain — roles',
      },
      {
        id: 'delegated',
        label: 'A delegated view',
        shot: '/shots/ee/units-manager-light-en.jpg',
        shotDark: '/shots/ee/units-manager-dark-en.jpg',
        alt: 'The same units screen as a delegated manager sees it: only the unit they run',
        caption:
          'What somebody may not do is missing rather than greyed out. A disabled control ' +
          'still promises a capability.',
        frameLabel: 'yourteam.yourdomain — units',
      },
      {
        id: 'history',
        label: 'History',
        shot: '/shots/ee/ticket-history-light-en.jpg',
        shotDark: '/shots/ee/ticket-history-dark-en.jpg',
        alt:
          'The history of one request: created, assigned, status changed, an SLA target missed ' +
          'by the system, and updated',
        caption:
          'Every entity carries its own history, and the answer to “who” can be the system — ' +
          'an SLA sweep is not a person and the record does not pretend otherwise. The ' +
          'team-wide trail is exportable as CSV through the API.',
        frameLabel: 'yourteam.yourdomain — history',
      },
    ],
  },

  identity: {
    id: 'identity',
    eyebrow: 'Identity',
    title: 'Accounts come from the directory you already run',
    body:
      'LDAP or Active Directory for the bind, SAML and OpenID Connect for single sign-on, and ' +
      'SCIM 2.0 for provisioning. Groups map to units, so a person joining a department in ' +
      'the directory joins the unit here. Somebody who leaves loses access the same day, and ' +
      'their sessions are ended rather than left to expire.',
    points: [
      'An account can be created on first sign-in, or not — the provider that may not create one says so and refuses',
      'A provider that is not fully configured cannot be switched on, and the screen names the settings it is still missing',
      'Every credential is encrypted under its own key and shows four characters afterwards, never a field',
    ],
    shot: '/shots/ee/team-identity-light-en.jpg',
    shotDark: '/shots/ee/team-identity-dark-en.jpg',
    alt:
      'The identity sources screen: an LDAP directory and an OIDC provider both live, one SAML ' +
      'provider that cannot be enabled and names the settings it still needs',
    frameLabel: 'yourteam.yourdomain — identity',
  },

  security: {
    eyebrow: 'Security and compliance',
    title: 'The questions a security review asks',
    items: [
      {
        key: 'residency',
        icon: '🗄️',
        title: 'Where the data is',
        body:
          'On your hardware, in your MySQL, behind your firewall. Attachments go to a bucket ' +
          'you name. Nothing is sent anywhere unless you connect it yourself, and then only ' +
          'what you connected.',
      },
      {
        key: 'accounts',
        icon: '🔑',
        title: 'How accounts are held',
        body:
          'A password policy and lockout you set, two-factor by authenticator app, and a list ' +
          'of a person’s active sessions and devices that an administrator can end.',
      },
      {
        key: 'audit',
        icon: '📜',
        title: 'What the record says',
        body:
          'A filtered audit trail with a retention you choose, exportable as CSV through the ' +
          'API. Nobody can edit it, including us: it is append-only and only the retention ' +
          'sweep removes anything.',
      },
      {
        key: 'kvkk',
        icon: '⚖️',
        title: 'When somebody asks to be forgotten',
        body:
          'The whole team exports as one document, and a person’s data can be removed. KVKK ' +
          'and GDPR are the reason the export exists, not a label added afterwards.',
      },
    ],
  },

  meetings: {
    id: 'meetings',
    eyebrow: 'Meeting notes',
    title: 'The half of “minutes” that normally never happens',
    body:
      'Upload a recording and get a note that separates who said what and pulls out the ' +
      'decisions. A decision becomes a request in one step. Transcription runs through a ' +
      'provider you choose, on your team’s own key, entered by your own administrator — and ' +
      'usage is metered, so a long recording cannot quietly become a large invoice.',
    points: [
      'What the vendor keeps is governed by your contract with them, not by ours',
      'A team with no key of its own has no transcription, rather than borrowing somebody else’s',
      'The note is markdown you can edit, not a transcript you have to accept',
    ],
    shot: '/shots/ee/meeting-named-light-en.jpg',
    shotDark: '/shots/ee/meeting-named-dark-en.jpg',
    alt: 'A meeting note: speakers named, the summary, and the decisions pulled out of it',
    frameLabel: 'yourteam.yourdomain — meeting',
  },

  ops: {
    eyebrow: 'Installing and running it',
    title: 'Your server, your database, your backups',
    lede:
      'The same containers the free edition uses, plus the commercial overlay. The API ' +
      'migrates its own schema on start, so an upgrade is a pull and an up — and your data ' +
      'never moves.',
    command:
      'docker compose -f docker-compose.ee.yml pull\n' +
      'docker compose -f docker-compose.ee.yml up -d\n\n' +
      '# the schema migrates itself on start; your volumes are untouched',
    points: [
      'MySQL 8.4 or MariaDB 10.11+, on a machine you control — attachments in your own S3-compatible bucket',
      'Each team on its own subdomain, with a wildcard certificate you install',
      'A backup and restore runbook, and an export that means you are never locked in',
    ],
    terminalTitle: 'your server',
    copyLabel: 'Copy',
    copiedLabel: 'Copied',
    link: { label: 'Self-hosting guide', href: `${REPO_URL}/blob/main/docs/SELF-HOSTING.md` },
  },

  packages: {
    anchor: 'packages',
    eyebrow: 'Packages',
    title: 'What a team is sold',
    lede:
      'A package is a shape an operator edits, not a wall around a feature. Everything on ' +
      'this page is in the product; what a package sets is how much of it a team may use, ' +
      'and which of the two capabilities that are genuinely separate are switched on.',
    caption: 'Package comparison',
    featureHeading: 'Limit or capability',
    labels: { yes: 'Included', no: 'Not included', partial: 'Partial' },
    columns: ['Starter', 'Business', 'Enterprise'],
    rows: [
      ['Seats', '10', '250', 'Unlimited'],
      ['Units (workspaces)', '5', '50', 'Unlimited'],
      ['Published request forms', 'Counted', 'Counted', 'Counted'],
      ['Requests through the portal, monthly', 'Counted', 'Counted', 'Counted'],
      ['Transcription minutes, monthly', 'Counted', 'Counted', 'Counted'],
      ['History retained', '90 days', '1 year', '7 years'],
      ['Service desk, SLAs, health monitors', 'yes', 'yes', 'yes'],
      ['Units, permissions, audit trail', 'yes', 'yes', 'yes'],
      ['Public request portal', 'yes', 'yes', 'yes'],
      ['Meeting notes and decisions', 'no', 'yes', 'yes'],
      ['LDAP / SAML / OIDC / SCIM', 'no', 'no', 'yes'],
    ],
    footnote:
      'These are the three a fresh installation ships with, and an operator renames them, ' +
      'edits them or adds their own. "Counted" means the product enforces a number your ' +
      'agreement sets — a ceiling with no counter behind it is a promise nobody keeps, so ' +
      'this table lists only the ones that are counted. There is no price here and nothing ' +
      'is being hidden by that: Enterprise is installed and configured with you, and the ' +
      'shape of the agreement depends on how many people and how many departments are in it.',
    link: { label: 'Ask what yours would look like →', href: '#contact' },
  },

  contact: {
    eyebrow: 'Talk to us',
    title: 'Tell us the shape of your organisation',
    lede:
      'How many people and how many departments is enough to start. We will come back with ' +
      'what it would cost and what installing it would involve — there is no automated next ' +
      'step and nothing to sign up for.',
    mailSubject: 'AllisWell Enterprise enquiry',
    fields: {
      name: { label: 'Your name' },
      company: { label: 'Organisation' },
      workEmail: { label: 'Work e-mail' },
      phone: { label: 'Phone (optional)' },
      seats: { label: 'People who would use it' },
      units: { label: 'Departments or units' },
      packageInterest: {
        label: 'Package you are looking at',
        placeholder: 'Not sure yet',
        options: ['Starter', 'Business', 'Enterprise'],
      },
      message: { label: 'Anything else we should know' },
      honeypot: 'Company website',
    },
    consent: {
      text:
        'I agree that the details above may be stored and used to answer this enquiry, as ' +
        'described in the',
      linkLabel: 'privacy notice',
      href: '/privacy',
    },
    submit: 'Send',
    orWrite: 'Or write to',
    sent: 'Thank you — your message is on its way. A person will read it and write back.',
  },

  faq: {
    heading: 'Questions people actually ask',
    items: [
      {
        q: 'Is this a hosted service?',
        a:
          'No. It installs on hardware you control, against a database you control. We help ' +
          'with the installation and the upgrades; the machine and the data stay yours.',
      },
      {
        q: 'What happens to the free edition?',
        a:
          'Nothing. It stays free for personal use, stays source-available, and Enterprise ' +
          'does not change its terms in either direction. A copy you already hold stays yours ' +
          'under the licence you received it under.',
      },
      {
        q: 'Can we get our data out?',
        a:
          'The whole team exports as one document through the API, and the audit trail exports ' +
          'as CSV. The database is your own MySQL, so the answer underneath all of that is ' +
          'that the data was never anywhere else.',
      },
      {
        q: 'Do our people need accounts before they can ask for something?',
        a:
          'Your own people do. Somebody outside the company does not: that is what the public ' +
          'request form is for, and it is why they can follow the request afterwards without ' +
          'signing in.',
      },
      {
        q: 'How long does it take to install?',
        a:
          'The containers come up in minutes. What takes the time is the part worth taking ' +
          'time over — deciding what your units are, what services they offer and what you ' +
          'are promising about them.',
      },
      {
        q: 'What is not in it?',
        a:
          'There is no asset register, no change-approval workflow, no satisfaction survey and ' +
          'no report builder beyond the dashboard and a weekly e-mail. E-mail cannot open a ' +
          'request yet — the public form and the app can. We would rather say so here than ' +
          'have you find out in week three.',
      },
    ],
  },

  footer: {
    blurb:
      'AllisWell Enterprise adds teams, units, permissions, a service desk and SLAs to the ' +
      'AllisWell you can already run for free. Commercially licensed, installed on your own ' +
      'servers.',
    notes:
      'Not affiliated with Microsoft, Apple, Google, Anthropic or OpenAI. Product names are ' +
      'their owners’.',
    privacyLabel: 'Privacy',
    supportLabel: 'Support',
    columns: [
      {
        title: 'Enterprise',
        links: [
          { label: 'The service desk', href: '#itsm' },
          { label: 'SLAs and service health', href: '#sla' },
          { label: 'The public request portal', href: '#portal' },
          { label: 'Identity and security', href: '#identity' },
          { label: 'Packages', href: '#packages' },
          { label: 'Talk to us', href: '#contact' },
        ],
      },
      {
        title: 'Run it yourself',
        links: [
          { label: 'Self-hosting guide', href: `${REPO_URL}/blob/main/docs/SELF-HOSTING.md` },
          { label: 'Architecture', href: `${REPO_URL}/blob/main/docs/ARCHITECTURE.md` },
          { label: 'REST API reference', href: '/docs/api' },
          { label: 'Security policy', href: `${REPO_URL}/blob/main/SECURITY.md` },
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
