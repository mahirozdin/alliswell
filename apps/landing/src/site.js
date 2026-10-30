/**
 * What the whole site shares: the addresses, the version, and the defaults the
 * shared chrome components fall back to (ADR-0061).
 *
 * The homepage's own words live in `content.js` / `content.tr.js`; the
 * enterprise page's in `enterprise/content.*.js`. Five components that both
 * pages render (TheHeader, TheFooter, ComparisonTable, FaqSection, PillarGrid)
 * default their props to the lists below. The enterprise page passes its own,
 * so these defaults are what the old homepage said, kept verbatim so the
 * enterprise build stays byte for byte what it was.
 *
 * `VERSION` must stay a literal at the start of a line: check:docs reads it
 * with `^export const VERSION = '…'` and holds it to the root package.json.
 */

export const APP_URL = '/app';
export const REPO_URL = 'https://github.com/mahirozdin/alliswell';
export const DOCS_URL = `${REPO_URL}/blob/main/docs`;
export const PLAY_URL = 'https://play.google.com/store/apps/details?id=com.alliswell.alliswell';
export const APP_STORE_URL = 'https://apps.apple.com/app/alliswell-todo-and-reminders/id6794964494';
export const VERSION = '1.18.2';
// OPH-370 / ADR-0051: every release carries the desktop apps under stable,
// unversioned names, so these links always fetch the newest one.
export const RELEASES_URL = `${REPO_URL}/releases/latest`;
export const WINDOWS_DOWNLOAD_URL = `${RELEASES_URL}/download/alliswell-windows-x64.zip`;
export const LINUX_DOWNLOAD_URL = `${RELEASES_URL}/download/alliswell-linux-x64.tar.gz`;
/**
 * OPH-364 — the hosted connector URL, said once. It is on the API host, not
 * this one: an agent that guessed `alliswell.space/mcp` from the marketing
 * domain got this site's HTML back and a Claude Team owner a failed connector.
 */
export const MCP_URL = 'https://api.alliswell.space/mcp';
export const MCP_GUIDE_URL = '/docs/mcp';

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
    title: 'Google Calendar sync in both directions',
    body: 'Your tasks become Google events, your edits in Google come back, and your existing events show up next to today’s work. On iPhone and Mac, tasks are mirrored into Apple Calendar too — one way, for now.',
  },
  {
    key: 'ai',
    icon: '🤖',
    title: 'AI on your terms — or none at all',
    body: 'Add AllisWell to the Claude or ChatGPT subscription you already pay for, or bring your own key (even a local Ollama). Every suggestion waits for your tap.',
  },
];

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
    q: 'How do I connect AllisWell to Claude or ChatGPT?',
    a: 'Add a custom connector with the URL https://api.alliswell.space/mcp (self-hosted: your API address followed by /mcp) and sign in with your AllisWell account. On Claude Team and Enterprise an Owner adds the connector once and every member presses Connect. The full guide, with troubleshooting, is at alliswell.space/docs/mcp.',
  },
  {
    q: 'Can I move my data out?',
    a: 'It is your MySQL database. Notes export as Markdown, and the whole schema is documented and open. There is no lock-in to leave.',
  },
  {
    q: 'What is missing?',
    a: 'Sharing and assignees (the workspace model exists, the UI does not), location-based reminders, and tasks over CalDAV (calendar events already go to iCloud or any CalDAV calendar when the server admin turns it on). All three are written down in the roadmap rather than implied away.',
  },
];

/**
 * The site nav.
 *
 * EE-143 made every in-page anchor ROOT-ABSOLUTE. On the homepage `/#features`
 * is a same-document fragment navigation — identical behaviour, no reload — and
 * from any other page it goes home and scrolls. A bare `#features` on
 * /enterprise scrolls nowhere, silently. One list that is correct everywhere
 * beats a second list that is correct on one page.
 */
export const siteLinks = [
  { label: 'Features', href: '/#features' },
  { label: 'AI', href: '/#ai' },
  // OPH-364: the connector gets its own entry — "where do I paste the URL" is
  // the question people arrive with, and it was two clicks deep.
  { label: 'MCP', href: '/#mcp' },
  { label: 'Compare', href: '/#compare' },
  { label: 'Self-host', href: '/#self-host' },
  // The only nav entry that leaves this page. /enterprise ships in the SAME
  // bundle — as a Vite entry since EE-151, as a generated page before that —
  // so the link and its destination cannot drift apart between deploys.
  { label: 'Enterprise', href: '/enterprise' },
  // OPH-296: same reasoning as /enterprise — generated into this bundle by
  // scripts/static-pages.js, so the link cannot outlive its destination.
  { label: 'API', href: '/docs/api' },
  { label: 'Get it', href: '/#get' },
];

/** EE-143 — root-absolute anchors, for the reason TheHeader's nav gives. */
export const siteColumns = [
  {
    title: 'Product',
    links: [
      { label: 'Open the app', href: APP_URL },
      { label: 'Get it on Google Play', href: PLAY_URL },
      { label: 'Download on the App Store', href: APP_STORE_URL },
      { label: 'Features', href: '/#features' },
      { label: 'Comparison', href: '/#compare' },
      { label: 'Enterprise', href: '/enterprise' },
      { label: 'Roadmap', href: `${REPO_URL}/blob/main/ROADMAP.md` },
      { label: 'Changelog', href: `${REPO_URL}/blob/main/CHANGELOG.md` },
    ],
  },
  {
    title: 'Run it yourself',
    links: [
      { label: 'Self-hosting guide', href: `${DOCS_URL}/SELF-HOSTING.md` },
      { label: 'Architecture', href: `${DOCS_URL}/ARCHITECTURE.md` },
      { label: 'Attachments (R2/S3)', href: `${DOCS_URL}/ATTACHMENTS.md` },
      { label: 'Notifications & alarms', href: `${DOCS_URL}/NOTIFICATIONS.md` },
    ],
  },
  {
    title: 'AI',
    links: [
      { label: 'How AI works', href: `${DOCS_URL}/AI.md` },
      { label: 'MCP connector', href: MCP_GUIDE_URL },
      // OPH-296: the REST API sat in this repo undocumented on the site for
      // two releases. It belongs beside the MCP connector — they are the two
      // ways something other than the app reaches your data.
      { label: 'REST API reference', href: '/docs/api' },
      { label: 'Security policy', href: `${REPO_URL}/blob/main/SECURITY.md` },
      { label: 'Privacy policy', href: '/privacy' },
    ],
  },
  {
    title: 'Project',
    links: [
      { label: 'GitHub', href: REPO_URL },
      { label: 'Contributing', href: `${REPO_URL}/blob/main/CONTRIBUTING.md` },
      { label: 'Issues', href: `${REPO_URL}/issues` },
      { label: 'Support', href: '/support' },
      { label: 'Licence (PolyForm NC)', href: `${REPO_URL}/blob/main/LICENSE` },
      { label: 'Commercial licensing', href: 'mailto:info@bubiapps.com' },
    ],
  },
];
