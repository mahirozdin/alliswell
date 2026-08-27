/**
 * Every word on the site, in one file.
 *
 * The claims here are the ones docs/COMPARISON.md backs and
 * docs/STORE-LISTING.md §5 permits — if a line changes, change it there too.
 * Keeping copy out of the components means it can be reviewed as prose, and
 * translated later without touching markup.
 */

export const APP_URL = '/app';
export const REPO_URL = 'https://github.com/mahirozdin/alliswell';
export const DOCS_URL = `${REPO_URL}/blob/main/docs`;
export const PLAY_URL = 'https://play.google.com/store/apps/details?id=com.alliswell.alliswell';
export const VERSION = '1.8.3';

export const hero = {
  eyebrow: `v${VERSION} · source available · free for personal use`,
  title: 'Your whole day, in an app you actually own.',
  lede: 'Tasks, projects, notes, files and reminders loud enough to move you — with true two-way Google & Apple Calendar sync. One app on six platforms, offline-first, storing every byte in your own database.',
  primary: { label: 'Open the web app', href: APP_URL },
  store: { label: 'Get it on Google Play', href: PLAY_URL },
  secondary: { label: 'Self-host in one command', href: '#self-host' },
  note: 'Free forever. No tier, no ads, no tracking. In your browser at alliswell.space/app — and now on Google Play.',
};

export const platforms = [
  { name: 'iOS', icon: 'apple' },
  { name: 'Android', icon: 'android' },
  { name: 'Web', icon: 'globe' },
  { name: 'macOS', icon: 'apple' },
  { name: 'Windows', icon: 'windows' },
  { name: 'Linux', icon: 'linux' },
];

export const pillars = [
  {
    key: 'own',
    icon: '🔐',
    title: 'It is genuinely yours',
    body: 'One `docker compose up`, your own MySQL on your own machine at your own domain — free, forever, for personal use. No other app in this category offers that at any price.',
  },
  {
    key: 'alarm',
    icon: '⏰',
    title: 'Alarms, not notifications',
    body: 'Urgent reminders ring through Silent mode and Focus, keep re-alerting until you acknowledge them, and write a log entry explaining themselves when the OS gets in the way.',
  },
  {
    key: 'sync',
    icon: '📅',
    title: 'Calendar sync in both directions',
    body: 'Your tasks become Google events, your edits in Google come back, and your existing events show up next to today’s work. Apple Calendar through EventKit.',
  },
  {
    key: 'ai',
    icon: '🤖',
    title: 'AI on your terms — or none at all',
    body: 'Add AllisWell to the Claude or ChatGPT subscription you already pay for, or bring your own key (even a local Ollama). Every suggestion waits for your tap.',
  },
];

export const features = [
  {
    id: 'home',
    eyebrow: 'The day',
    title: 'One surface for everything that is due',
    body: 'Overdue, today, this week and the next 30 days in one chronological scroll, with a month calendar beside it. Flip the same day into a kanban Board with columns you name, hide and reorder.',
    points: [
      'Dateless captures pinned on top — nothing gets lost because it had no date',
      'Drag between columns, or use the visible status button when dragging is awkward',
      'A finished task stays on today’s list, struck through, until midnight',
    ],
    shot: 'web/home-light.jpg',
    shotDark: 'web/home-dark.jpg',
    alt: 'AllisWell Home on the web: overdue and today groups, project badges, tag chips and a month calendar',
  },
  {
    id: 'board',
    eyebrow: 'Board',
    title: 'The same tasks, as a kanban',
    body: 'Open, In progress, Waiting, Completed — or whatever set of statuses your work actually has. Columns are yours to hide and reorder, and every card keeps its project, tags, priority and repeat badge.',
    points: [
      'Your column layout is remembered per device',
      'Hidden statuses stay reachable as move targets',
      'Not a separate list: it is the same data, rearranged',
    ],
    shot: 'web/board.jpg',
    alt: 'AllisWell Board view with Open, In progress, Waiting and Completed columns',
  },
  {
    id: 'alarms',
    eyebrow: 'Reminders',
    title: 'A reminder that gets you out of the meeting',
    body: 'Ordinary reminders arrive at the exact minute. Urgent ones ring like an alarm — through Silent mode, through Focus — and keep coming back on a chain until you acknowledge them.',
    points: [
      'Snooze presets that tell you exactly when they will ring again',
      'Silence one task’s alarms without completing it',
      'Your own ringtone, or one you upload',
      'A privacy mode that hides the task’s text on the lock screen',
    ],
    shot: 'web/reminders.jpg',
    alt: 'AllisWell reminder settings: alarm profile, re-alert chain, sound library',
  },
  {
    id: 'recurrence',
    eyebrow: 'Repeats',
    title: 'Ask for the 31st and February answers',
    body: 'Every day, every weekday, the last day of the month, the 2nd Tuesday, the first Monday after the 22nd. Pick a day that a month does not have and AllisWell clamps to the nearest real one — Google Calendar drops the month entirely.',
    points: [
      'A live “next 5” preview shows the days before you commit',
      'Occurrences are real tasks — they appear in search, the calendar and the widget',
      'Editing one asks how far it reaches: this, this and future, or all',
    ],
    shot: 'web/home-dark.jpg',
    alt: 'A repeating task in AllisWell, with its repeat badge on the list row',
  },
  {
    id: 'notes',
    eyebrow: 'Notes & files',
    title: 'The document half of the job',
    body: 'Markdown notes with live syntax while you type and a real GFM reading view — tables, task lists, KaTeX, Mermaid. Inline images, linked to tasks and projects, exportable as .md or PDF. Attach any file to anything, and browse the lot in a Files section with nestable folders.',
    points: [
      'A project’s README note becomes its overview page',
      'Attachments go straight to Cloudflare R2 or any S3 — bytes never pass through the API',
      'Pin, archive, card grid or list',
    ],
    shot: 'web/notes.jpg',
    alt: 'AllisWell Notes: pinned notes, project links, README filter',
  },
  {
    id: 'markdown',
    eyebrow: 'Notes',
    title: 'A markdown workspace, not a text box',
    body: 'Notes render GitHub-flavoured markdown properly — tables with their alignment, task lists, callouts, real mathematics, syntax-coloured code, and Mermaid diagrams drawn as diagrams. One document, two ways to look at it: Reading, and the markdown source with live syntax as you type.',
    points: [
      'Open a .md file from your own computer, edit it, and save it back to that file',
      'The file is never written behind your back — and if something else changed it, you choose what happens',
      'Outline, folding, find and replace, a command palette, and slash commands everywhere',
    ],
    ratio: '1440 / 900',
    shot: 'web/project-readme.jpg',
    alt: 'A project’s README in AllisWell, with its markdown rendered as a document — headings, a table, a task list and a quote',
  },
  {
    id: 'files',
    eyebrow: 'Files',
    title: 'Folders, and everything attached anywhere',
    body: 'A workspace-wide file manager with nestable folders, plus a Files tab inside every project and an Attachments section on every task.',
    points: [
      'Presigned uploads — your storage, your bucket, your bill',
      'Sources view shows where each file is attached',
      'Works with MinIO locally and R2 in production',
    ],
    shot: 'web/files.jpg',
    alt: 'AllisWell Files section with folders and uploaded documents',
  },
  {
    id: 'search',
    eyebrow: 'Search',
    title: 'Search that ignores accents',
    body: 'Type “muller” and find Müller. Type “cafe” and find café. Ranked title → tag → body, running over the copy of your data on the device, so it answers instantly and works with the network off.',
    points: [
      'Case- and diacritic-insensitive across the Latin alphabets — ß, ñ, å, ø, ł, č and the rest',
      'Handles the letters database engines get wrong, so results do not depend on your server’s collation',
      'Offline, because the index is local',
    ],
    shot: 'web/search.jpg',
    alt: 'Searching AllisWell notes for “muller” and finding “Kickoff at Café Müller”',
  },
  {
    id: 'widget',
    eyebrow: 'Home Screen',
    title: 'Your day, without unlocking anything',
    body: 'The widget mirrors the same buckets Home does — overdue, undated, today — under a header carrying the date, the system clock and how many tasks today actually holds. It reads the same data the app does, without unlocking anything.',
    points: [
      'A clock that really ticks — not a number frozen at the last refresh',
      'The count is what is on you today: overdue plus due today, hidden at zero',
      'iPhone and Android, in light and dark, from the same task data',
    ],
    // A phone Home Screen belongs in phone chrome; the default browser frame
    // would draw a fake URL bar around an iPhone.
    frame: 'phone',
    ratio: '1320 / 2868',
    shot: 'ios/12-widget.jpg',
    shotDark: 'ios/13-widget-dark.jpg',
    alt: 'The AllisWell widget on the iPhone Home Screen: the date and the system clock in the header, today’s open count beneath it, then overdue, undated and today’s tasks',
  },
];

export const aiSection = {
  eyebrow: 'AI · entirely optional',
  title: 'Two honest ways to use a model — and zero is one of them',
  lede: 'Capture works with no AI at all. When you do want it, nothing is resold to you and nothing is trained on you.',
  tracks: [
    {
      title: 'Add AllisWell to Claude or ChatGPT',
      body: 'AllisWell is a remote MCP server. Connect it to the subscription you already pay for and ask about your day, from inside the assistant you already use.',
      points: [
        'OAuth 2.1 with PKCE and dynamic client registration — your own instance, your own consent',
        'Read-first tools; there is no delete tool, and there never will be',
        'Self-hosters get their own connector URL with no directory listing needed',
      ],
      link: { label: 'How the connector works', href: `${DOCS_URL}/MCP.md` },
    },
    {
      title: 'Bring your own key',
      body: 'Anthropic, OpenAI, Gemini, OpenRouter — or a local Ollama, where nothing leaves the machine. Chat with your tasks, press and hold to speak one into being, or share any text into the app.',
      points: [
        'Speech is transcribed on the device: your voice never leaves it, only the text does',
        'The model gets no write tools — it proposes, you confirm with one tap',
        'The consent screen states each provider’s real data policy, including the ones that train on you',
      ],
      link: { label: 'How AI works here', href: `${DOCS_URL}/AI.md` },
    },
  ],
};

export const comparison = {
  columns: ['AllisWell', 'Google Calendar', 'Google Tasks', 'Apple Reminders', 'Things 3'],
  rows: [
    ['Source available', 'yes', 'no', 'no', 'no', 'no'],
    ['Self-hosted, your database', 'yes', 'no', 'no', 'no', 'no'],
    ['Price', 'free', 'free', 'free', 'free', '~$80'],
    ['iOS + Android + Web + desktop', 'yes', 'partial', 'partial', 'no', 'no'],
    ['Works fully offline', 'yes', 'partial', 'partial', 'yes', 'yes'],
    ['Kanban board', 'yes', 'no', 'no', 'partial', 'no'],
    ['Rich notes & file attachments', 'yes', 'partial', 'no', 'partial', 'no'],
    ['Markdown files edited in place', 'yes', 'no', 'no', 'no', 'no'],
    ['Alarms through Silent + Focus', 'yes', 'no', 'no', 'partial', 'no'],
    ['Re-alert until acknowledged', 'yes', 'no', 'no', 'no', 'no'],
    ['Recurrence clamps (31st → 28 Feb)', 'yes', 'no', 'no', 'yes', 'yes'],
    ['Two-way Google Calendar sync', 'yes', 'native', 'native', 'no', 'no'],
    ['Accent-insensitive search', 'yes', 'no', 'no', 'no', 'no'],
    ['MCP connector for Claude / ChatGPT', 'yes', 'no', 'no', 'no', 'no'],
  ],
  footnote:
    'Competitor behaviour as of mid-2026. The full analysis — including the places where they beat us — is in docs/COMPARISON.md.',
};

export const selfHost = {
  eyebrow: 'Self-hosting',
  title: 'Your server, your data, one command',
  lede: 'Two published images — the API and the web app — for amd64 and arm64, tagged on every release. The API migrates its own schema on start, so an upgrade is `pull` + `up -d` and your data never moves.',
  command: `curl -O https://raw.githubusercontent.com/mahirozdin/alliswell/main/docker-compose.selfhost.yml
curl -o .env https://raw.githubusercontent.com/mahirozdin/alliswell/main/.env.selfhost.example

echo "JWT_ACCESS_SECRET=$(openssl rand -hex 32)"  >> .env
echo "JWT_REFRESH_SECRET=$(openssl rand -hex 32)" >> .env
nano .env            # your domains + database passwords

docker compose -f docker-compose.selfhost.yml up -d`,
  points: [
    'MySQL 8.4 or MariaDB 10.11+ — data in named volumes, never touched by an upgrade',
    'Attachments in your own Cloudflare R2 or S3 bucket',
    'One prebuilt web image serves any domain: the API address is read at container start',
  ],
  link: { label: 'Full self-hosting guide', href: `${DOCS_URL}/SELF-HOSTING.md` },
};

export const download = {
  eyebrow: 'Get it',
  title: 'In your browser today — and now on Google Play',
  lede: 'The web app is live and complete — sign up and it works on every device you own. The Android app is out on Google Play; the iOS build is in TestFlight and goes to the App Store next.',
  web: {
    title: 'Web app',
    status: 'Live now',
    body: 'The full app at alliswell.space/app — offline-capable, installable, nothing to download.',
    cta: { label: 'Open alliswell.space/app', href: APP_URL },
  },
  stores: [
    {
      name: 'Google Play',
      status: 'Live now',
      body: 'The Android app, on the store — alarm-grade reminders, offline-first sync and the home-screen widget included.',
      icon: 'android',
      cta: { label: 'Get it on Google Play', href: PLAY_URL },
    },
    {
      name: 'App Store',
      status: 'Internal testing',
      body: 'TestFlight internal build is running. Public release next.',
      icon: 'apple',
    },
  ],
  selfHostNote:
    'In a hurry, or want it entirely on your own metal? Self-hosting is one command away, and it is the same app.',
};

export const faq = [
  {
    q: 'Is it really free?',
    a: 'Free for you, yes: personal use and self-hosting your own instance are free forever, with no tier, no ads and no tracking. Commercial use — running it inside a business, reselling it, or offering it as a service — needs a licence, because the hosted service and the app stores are what fund the work. Write to info@bubiapps.com.',
  },
  {
    q: 'What does “alarm-grade” actually mean?',
    a: 'An urgent task rings with a real alarm sound rather than a notification chime, at full volume through Silent mode and Focus (iOS 26 AlarmKit; Android’s USAGE_ALARM insistent channel), and keeps re-alerting on a chain until you acknowledge it. Delivery still depends on the OS, which is exactly why the app keeps an alarm log you can read when something does not fire.',
  },
  {
    q: 'How is the Google Calendar sync two-way?',
    a: 'Your tasks are written into a calendar you pick as real events; edits you make in Google flow back into AllisWell through push webhooks and incremental sync with etag-based conflict resolution. Your other Google events show up on Home next to your tasks.',
  },
  {
    q: 'Do I have to use the AI features?',
    a: 'No. They are off until you turn them on, capture works with zero AI, and there is no AllisWell AI account — you either connect AllisWell to your own Claude/ChatGPT subscription over MCP, or you paste your own provider key.',
  },
  {
    q: 'Can I move my data out?',
    a: 'It is your MySQL database. Notes export as Markdown, and the whole schema is documented and open. There is no lock-in to leave.',
  },
  {
    q: 'What is missing?',
    a: 'Sharing and assignees (the workspace model exists, the UI does not), location-based reminders, and CalDAV. All three are written down in the roadmap rather than implied away.',
  },
];
