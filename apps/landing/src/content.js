/**
 * The homepage, in English (ADR-0061). The Turkish twin is `content.tr.js`;
 * `npm run check:copy` holds the two to the same key tree.
 *
 * The claims here are the ones docs/COMPARISON.md backs and
 * docs/STORE-LISTING.md §5 permits: Apple Calendar only as a one-way mirror, no "never stops",
 * no free or built-in AI, no "no tracking". If a line changes, change it there
 * too. The page follows Hallmark's Dusk rules, which check:copy enforces where
 * a machine can: no eyebrows, no emoji, no em or en dashes, about 450 visible
 * words at most.
 *
 * `media` keys name entries in `src/home/media.json`, which
 * `npm run media:promote` writes; `check:media` fails a key with no file.
 */

import {
  APP_STORE_URL,
  APP_SIGNUP_URL,
  APP_URL,
  DOCS_URL,
  LINUX_DOWNLOAD_URL,
  MCP_GUIDE_URL,
  MCP_URL,
  PLAY_URL,
  REPO_URL,
  WINDOWS_DOWNLOAD_URL,
} from './site.js';

/**
 * OPH-412 (landing-audit K6): one primary action, chosen by the device
 * (src/home/platform.js). The bar carries the same one as the hero.
 */
const primary = {
  desktop: { label: 'Start free in your browser', href: APP_SIGNUP_URL },
  ios: { label: 'Get it on the App Store', href: APP_STORE_URL },
  android: { label: 'Get it on Google Play', href: PLAY_URL },
};

export default {
  lang: 'en',

  seo: {
    title: 'AllisWell: self-hosted tasks with alarms that ring through Silent mode',
    description:
      'Tasks in projects, markdown notes, files and alarms that ring through Silent mode, with ' +
      'two-way Google Calendar sync and a connector for Claude and ChatGPT. One app for iPhone, ' +
      'Android, the web and desktop. Free for personal use, on your own server or ours.',
    ogImage: '/shots/og/home-alarm.jpg',
  },

  skip: 'Skip to the tour',

  ui: { pause: 'Pause the animation', play: 'Play the animation' },

  nav: {
    home: '/',
    label: 'Main',
    links: [
      { label: 'Tour', href: '/#features' },
      { label: 'Claude and ChatGPT', href: '/#mcp' },
      { label: 'Self-host', href: '/#self-host' },
      { label: 'Download', href: '/#get' },
      { label: 'Enterprise', href: '/enterprise' },
    ],
    github: { label: 'GitHub', href: REPO_URL },
    cta: primary,
    menu: 'Menu',
    langLabel: 'Language',
  },

  hero: {
    // Owner decision S-3 (2026-11-07): the alarm in the head, self-hosting
    // and the Claude/ChatGPT connector in the line under it.
    title: 'Reminders that ring through Silent mode.',
    sentence: 'Tasks, notes and files in one app, on your own server or ours. Connect Claude or ChatGPT and ask it about your day.',
    primary,
    secondary: { label: 'Host it yourself', href: '/#self-host' },
    also: {
      before: 'Also on ',
      links: [
        { label: 'iPhone', href: APP_STORE_URL },
        { label: 'Android', href: PLAY_URL },
        { label: 'Windows', href: WINDOWS_DOWNLOAD_URL },
        { label: 'Linux', href: LINUX_DOWNLOAD_URL },
      ],
      and: ' and ',
      after: '.',
    },
    media: 'hero',
    alt: 'A day in AllisWell: the Home list fills with tasks from three projects, one is ticked off, and the rent reminder rings as an alarm.',
    caption: 'Recorded from the app with sample data.',
  },

  // OPH-412 (landing-audit K2): counted from the GitHub API at build time;
  // without it the line drops the count (src/home/proof.js).
  proof: {
    label: 'About the project',
    source: { label: 'Source on GitHub', href: REPO_URL },
    releases: '{n} releases, the first in {month}',
    free: 'Free for personal use',
  },

  tour: {
    title: 'A task carries its project, files and alarm.',
    lead: 'Five things it does, shown on the real app.',
    tabsLabel: 'Features',
    panes: [
      {
        id: 'tasks',
        tab: 'Tasks that belong to projects',
        body: 'Each task carries its project, tags, checklist and files, and syncs both ways with Google Calendar.',
        media: 'tour-tasks',
        alt: 'The board view: tasks move from Open to In progress, each one wearing its project badge and tags.',
      },
      {
        id: 'notes',
        tab: 'Markdown notes, rendered properly',
        body: 'Tables, maths, code and Mermaid diagrams. Open a .md file from your computer and save it back.',
        media: 'tour-notes',
        alt: 'A note switches between its markdown source and the reading view, where the table and the checklist render.',
      },
      {
        id: 'alarms',
        tab: 'Alarms, not chimes',
        body: 'Urgent tasks ring like an alarm clock through Silent and Focus, and ask again for half an hour until you answer.',
        media: 'tour-alarms',
        alt: 'A full-screen alarm on Android with an Acknowledge button and snooze presets that name the time they ring again.',
      },
      {
        id: 'files',
        tab: 'Files next to the work',
        body: 'The whiteboard photo and the contract PDF live on the task or project they belong to.',
        media: 'tour-files',
        alt: 'A project’s Files tab lists photos and documents in folders, and a picture opens full size.',
      },
      {
        id: 'repeats',
        tab: 'Repeats that keep count',
        body: 'Ask for the 31st and February gets the 28th. You see the next five dates before you save.',
        media: 'tour-repeats',
        alt: 'A task repeating every month on day 31, with the next five dates listed and February falling on the 28th.',
      },
    ],
  },

  film: {
    title: 'The whole app in a minute.',
    media: 'film-en',
    alt: 'A one-minute film of AllisWell: tasks, an alarm through Silent, the calendar, notes and files, Claude, and self-hosting.',
    transcriptLabel: 'Read the film as text',
    transcript: [
      'Your day, closed calmly.',
      'Tasks live in projects, with their tags, checklists and files.',
      'Urgent ones ring through Silent mode and ask again for half an hour.',
      'Google Calendar stays in step, both ways. The 31st lands on the 28th in February.',
      'Notes render tables, maths and diagrams. Files sit next to the work.',
      'Ask Claude or ChatGPT about your day. Every change waits for you.',
      'Run it on your own server with one command, or use ours.',
      'AllisWell. On the web, iPhone, Android and desktop. alliswell.space',
    ],
  },

  assistant: {
    title: 'Ask Claude about your day.',
    lead: 'Add AllisWell to Claude or ChatGPT as a connector. Every change waits for your approval.',
    steps: [
      'In Claude or ChatGPT, add a custom connector.',
      'Paste this address.',
      'Sign in with your AllisWell account.',
    ],
    urlLabel: 'Connector address',
    url: MCP_URL,
    copy: 'Copy',
    copied: 'Copied',
    fact: 'Twenty-five tools over your tasks and notes, and no delete tool.',
    link: { label: 'Read the setup guide', href: MCP_GUIDE_URL },
    media: 'mcp-en',
    alt: 'A request to an assistant moves three overdue tasks to tomorrow morning after an approval, and the AllisWell list updates.',
  },

  own: {
    title: 'Your server, one command.',
    lead: 'Two Docker images and your own database. Upgrading is a pull.',
    commandLabel: 'On your server',
    command: 'docker compose -f docker-compose.selfhost.yml up -d', // i18n-same
    points: [
      'Free for personal use and for running your own copy.',
      'MySQL 8.4 or MariaDB 10.11, files in your own S3 or R2 bucket.',
      'The source is on GitHub under the PolyForm Noncommercial licence.',
    ],
    link: { label: 'Read the self-hosting guide', href: `${DOCS_URL}/SELF-HOSTING.md` },
    media: 'selfhost',
    alt: 'A terminal starts the AllisWell containers, every service reports healthy, and the app opens on your own domain.',
  },

  compare: {
    title: 'How it compares, honestly.',
    lead: 'Where others are ahead: sharing with other people, and a public demo.',
    caption: 'AllisWell beside Todoist, TickTick and Vikunja; Vikunja checked October 2026.',
    // OPH-412 (landing-audit K15): the apps a self-hoster compares, cell for
    // cell the README's table; "unknown" is its dash, not checked against
    // their own documentation.
    columns: ['AllisWell', 'Todoist', 'TickTick', 'Vikunja'],
    rows: [
      ['Runs on your own server', 'yes', 'no', 'no', 'yes'],
      ['Alarm through Silent, repeated until answered', 'yes', 'unknown', 'unknown', 'partial'],
      ['Two-way Google Calendar sync', 'yes', 'unknown', 'unknown', 'no'],
      ['Connector for Claude and ChatGPT', 'yes', 'unknown', 'unknown', 'yes'],
      ['Native iPhone and Android apps', 'yes', 'yes', 'yes', 'partial'],
      ['Sharing with other people', 'no', 'yes', 'unknown', 'yes'],
    ],
    labels: { yes: 'Yes', no: 'No', partial: 'Partly', unknown: 'Unchecked' },
    link: { label: 'Read the full comparison', href: `${DOCS_URL}/COMPARISON.md` },
  },

  get: {
    title: 'Web, phone and desktop. macOS from source.',
    lead: 'One account, the same day on each of them.',
    rows: [
      { id: 'web', name: 'Web', note: 'Nothing to install.', cta: 'Open the app', href: APP_URL },
      { id: 'ios', name: 'iPhone and iPad', note: 'Free on the App Store.', cta: 'App Store', href: APP_STORE_URL },
      { id: 'android', name: 'Android', note: 'Free on Google Play.', cta: 'Google Play', href: PLAY_URL },
      { id: 'windows', name: 'Windows', note: 'A .zip for Windows 10 and 11.', cta: 'Download', href: WINDOWS_DOWNLOAD_URL },
      { id: 'linux', name: 'Linux', note: 'A .tar.gz for 64-bit desktops.', cta: 'Download', href: LINUX_DOWNLOAD_URL },
      { id: 'macos', name: 'macOS', note: 'Builds from the source for now.', cta: 'Source', href: REPO_URL },
    ],
    media: 'get-phone',
    alt: 'AllisWell on an iPhone: today’s tasks under a month calendar.',
    caption: 'Home on an iPhone',
    captionNote: 'The same day as on the web, in your pocket.',
  },

  faq: {
    title: 'What people ask before they switch.',
    items: [
      {
        q: 'What is the licence?',
        a: 'Source-available, not open source: PolyForm Noncommercial. Personal use and self-hosting are free; running it inside a business, reselling it or offering it as a service needs a commercial licence. Write to info@bubiapps.com.',
      },
      {
        q: 'What happens when an alarm rings?',
        a: 'An urgent task plays a real alarm sound through Silent mode and Focus (AlarmKit on iOS 26, the alarm channel on Android) and alerts again over the next half hour until you acknowledge it. When the system blocks it, the app writes down why.',
      },
      {
        q: 'Is the Google Calendar sync really two-way?',
        a: 'Yes. Tasks become events in a calendar you choose, and the edits you make in Google come back. On iPhone and Mac your tasks are also mirrored into Apple Calendar, one way.',
      },
      {
        q: 'Do I need AI to use it?',
        a: 'No. Everything works without a model. If you want one, connect your own Claude or ChatGPT account, or paste your own provider key.',
      },
      {
        q: 'Can I bring my tasks from Todoist or TickTick?',
        a: 'Yes. Export from the app you are leaving and import the file in Settings. You see what will come in before anything is written.',
      },
      {
        q: 'What is missing?',
        a: 'Sharing and assignees, reminders by location, and tasks over CalDAV. All three are written down in the roadmap.',
      },
    ],
  },

  footer: {
    line: 'Built in the open, one task at a time.',
    columns: [
      {
        title: 'Product',
        links: [
          { label: 'Open the app', href: APP_URL },
          { label: 'App Store', href: APP_STORE_URL },
          { label: 'Google Play', href: PLAY_URL },
          { label: 'Enterprise', href: '/enterprise' },
          { label: 'Changelog', href: `${REPO_URL}/blob/main/CHANGELOG.md` },
          { label: 'Roadmap', href: `${REPO_URL}/blob/main/ROADMAP.md` },
        ],
      },
      {
        title: 'Build on it',
        links: [
          { label: 'Connector guide', href: MCP_GUIDE_URL },
          { label: 'REST API', href: '/docs/api' },
          { label: 'Self-hosting guide', href: `${DOCS_URL}/SELF-HOSTING.md` },
          { label: 'Source on GitHub', href: REPO_URL },
        ],
      },
      {
        title: 'Company',
        links: [
          { label: 'Privacy', href: '/privacy' },
          { label: 'Terms', href: '/terms' },
          { label: 'Support', href: '/support' },
          { label: 'Licence', href: `${REPO_URL}/blob/main/LICENSE` },
          { label: 'Commercial licensing', href: 'mailto:info@bubiapps.com' },
        ],
      },
    ],
    registeredAs: 'Registered name',
    notes: 'Not affiliated with Apple, Google, Anthropic or OpenAI.',
    photoLabel: 'Photograph',
    photoChanges: 'cropped and resized',
    fontLabel: 'Type',
    fontCredit: 'Wix Madefor, SIL Open Font License',
    versionLabel: 'Version',
  },
};
