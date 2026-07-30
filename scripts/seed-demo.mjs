#!/usr/bin/env node
/**
 * seed-demo.mjs — fills a running AllisWell instance with the demo workspace
 * every screenshot, the landing page and the store listings are shot from.
 *
 * It talks to the PUBLIC REST API, so the same script seeds a local dev server,
 * a self-hosted instance or the hosted demo — and every row it writes has gone
 * through the same validation a real user's would. That is the point: a demo
 * dataset produced by a back door can show a state the product cannot reach.
 *
 * ONE exception, and it is deliberate: `completed_at` is server-owned and always
 * stamped `now` (db/tasks.js, routes/sync.js), so a workspace seeded purely
 * through the API has every completion happening today — which buries Home under
 * struck-through rows (OPH-185 keeps today's completions visible) and leaves
 * Settings ▸ Completed with a single day in a timeline built for scrolling back
 * through months. The `--backdate` step (default on, skipped without a reachable
 * database) writes those timestamps directly. Nothing else bypasses the API.
 *
 * Usage:
 *   node scripts/seed-demo.mjs                          # localhost:3000, demo@alliswell.space
 *   node scripts/seed-demo.mjs --api https://api.alliswell.space
 *   node scripts/seed-demo.mjs --email me@example.com --password 'hunter2hunter2'
 *   node scripts/seed-demo.mjs --no-files               # skip attachments (no S3/MinIO configured)
 *   node scripts/seed-demo.mjs --no-backdate            # leave every completion stamped today
 *
 * Dates are computed relative to the moment it runs, so the Home screen always
 * shows a believable "today" — overdue debts, a busy afternoon, a full month
 * ahead — no matter when the screenshots are taken.
 */

const args = process.argv.slice(2);
const flag = (name, fallback = null) => {
  const i = args.indexOf(`--${name}`);
  return i >= 0 && args[i + 1] && !args[i + 1].startsWith('--') ? args[i + 1] : fallback;
};
const has = (name) => args.includes(`--${name}`);

const API = (flag('api', process.env.ALLISWELL_API_URL) ?? 'http://localhost:3000').replace(
  /\/+$/,
  '',
);
const EMAIL = flag('email', process.env.SEED_EMAIL) ?? 'demo@alliswell.space';
const PASSWORD = flag('password', process.env.SEED_PASSWORD) ?? 'AllisWellDemo2026';
const DISPLAY_NAME = flag('name', 'Alex Rivera');
const WANT_FILES = !has('no-files');
const WANT_BACKDATE = !has('no-backdate');
const TZ = flag('tz', 'Europe/Istanbul');

/** Title → the instant its completion should claim, filled in as tasks are made. */
const backdated = new Map();

let token = null;
let workspaceId = null;

// ── HTTP ────────────────────────────────────────────────────────────────────

/** Every REST route lives under this prefix (apps/api/src/app.js). */
const V1 = '/api/v1';

async function call(method, path, body, { raw = false } = {}) {
  const res = await fetch(`${API}${V1}${path}`, {
    method,
    headers: {
      'content-type': 'application/json',
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  if (!res.ok) {
    const text = await res.text();
    const err = new Error(`${method} ${path} → ${res.status} ${text.slice(0, 400)}`);
    err.status = res.status;
    err.body = text;
    throw err;
  }
  if (raw) return res;
  return res.status === 204 ? null : res.json();
}

const post = (p, b) => call('POST', p, b);
const patch = (p, b) => call('PATCH', p, b);
const get = (p) => call('GET', p);

// ── Dates ───────────────────────────────────────────────────────────────────

const now = new Date();
/** An instant at wall-clock `h:m` on today+`days`, as ISO. */
const at = (days, h, m = 0) =>
  new Date(now.getFullYear(), now.getMonth(), now.getDate() + days, h, m, 0, 0).toISOString();
/** `days`/`hours` before now — for things that are already late. */
const ago = ({ days = 0, hours = 0, minutes = 0 }) =>
  new Date(now.getTime() - ((days * 24 + hours) * 60 + minutes) * 60_000).toISOString();

// ── Content ─────────────────────────────────────────────────────────────────
// One place, deliberately: everything a screenshot can show is authored here,
// so the dataset can be reviewed as prose rather than read out of API calls.

const PROJECTS = [
  {
    key: 'launch',
    name: 'Launch v1.0',
    colorRgb: '#8E44EC',
    isFavorite: true,
    description: 'Ship the public release: store listings, press kit, launch-day comms.',
  },
  {
    key: 'design',
    name: 'Design System',
    colorRgb: '#2563EB',
    isFavorite: true,
    description: 'Tokens, components and the contrast budget that keeps them honest.',
  },
  {
    key: 'acme',
    name: 'Acme — retainer',
    colorRgb: '#0D7A33',
    description: 'Monthly retainer client. Invoices go out on the last day of the month.',
  },
  {
    key: 'home',
    name: 'Home renovation',
    colorRgb: '#0C7D6C',
    description: 'Kitchen first, then the hallway. Everything else can wait.',
  },
  {
    key: 'personal',
    name: 'Personal',
    colorRgb: '#E8500A',
    isFavorite: true,
    description: 'Health, family, money, and the things that only I can do.',
  },
  {
    key: 'reading',
    name: 'Reading list',
    colorRgb: '#C77700',
    description: 'Books and long-form worth finishing.',
  },
  {
    key: 'y2025',
    name: 'Q4 2025 — closed',
    colorRgb: '#64748B',
    status: 'archived',
    description: 'Kept for reference. Archived, not deleted.',
  },
];

const TAGS = [
  'design',
  'deep-work',
  'errand',
  'health',
  'writing',
  'finance',
  'family',
  'review',
  'blocked',
];

/**
 * Tasks. `due` is `[daysFromToday, hour, minute]`, or `overdue: {...}`.
 * Anything with no date is a captured thought — it sits on top of Home, or in
 * the Inbox when its status says so.
 */
const TASKS = [
  // ── Inbox: caught, not yet planned ────────────────────────────────────────
  { title: 'Look into a Linear-style command palette', status: 'inbox', project: 'design' },
  { title: 'Ask Deniz about the Berlin office visit', status: 'inbox' },
  { title: 'Compare S3 egress pricing vs R2', status: 'inbox', project: 'launch' },
  { title: 'Idea: weekly review template as a note', status: 'inbox', tags: ['writing'] },

  // ── Undated, but planned ─────────────────────────────────────────────────
  { title: 'Sketch the empty states for Files', project: 'design', tags: ['design'] },
  { title: 'Call the plumber about the kitchen leak', project: 'home', tags: ['errand'] },

  // ── Overdue: a debt that must never look disabled ─────────────────────────
  {
    title: 'Send Acme the September invoice',
    project: 'acme',
    priority: 'urgent',
    urgent: true,
    overdue: { days: 2, hours: 4 },
    tags: ['finance'],
    description: 'Net-30. Attach the timesheet export and CC accounting@acme.example.',
  },
  {
    title: 'Reply to the App Store review team',
    project: 'launch',
    priority: 'high',
    overdue: { days: 1, hours: 2 },
    tags: ['review'],
  },
  {
    title: 'Renew the domain before it lapses',
    project: 'personal',
    priority: 'medium',
    overdue: { hours: 6 },
    tags: ['finance', 'errand'],
  },

  // ── Today ────────────────────────────────────────────────────────────────
  {
    title: 'Design review — Board columns',
    project: 'design',
    priority: 'high',
    due: [0, 10, 30],
    tags: ['design', 'deep-work'],
    description: 'Walk through K1–K6 in DESIGN §14 and decide the drag affordance.',
    mirror: true,
  },
  {
    title: 'Stand-up',
    project: 'launch',
    due: [0, 9, 15],
    completed: true,
    completedAt: at(0, 9, 22),
  },
  {
    title: 'Take the medication',
    project: 'personal',
    priority: 'urgent',
    urgent: true,
    due: [0, 21, 0],
    tags: ['health'],
    description: 'Rings through Silent and Focus. Re-alerts until acknowledged.',
  },
  {
    title: 'Write the release notes for 1.0',
    project: 'launch',
    priority: 'high',
    due: [0, 17, 0],
    tags: ['writing', 'deep-work'],
    checklist: [
      { title: 'Skim the CHANGELOG since 0.9.0', done: true },
      { title: 'Pull the three headline features', done: true },
      { title: 'Screenshot the recurring-task dialog' },
      { title: 'Ask Mert to proofread' },
    ],
  },
  { title: 'Evening 5 km', project: 'personal', priority: 'low', due: [0, 19, 30], tags: ['health'] },
  {
    title: 'Pick up the dry cleaning',
    project: 'personal',
    due: [0, 18, 15],
    tags: ['errand'],
    completed: true,
    completedAt: at(0, 18, 40),
  },

  // ── This week ────────────────────────────────────────────────────────────
  {
    title: 'Kitchen: measure for the new counter',
    project: 'home',
    due: [1, 11, 0],
    tags: ['errand'],
    color: '#0C7D6C',
  },
  {
    title: 'Acme sprint planning',
    project: 'acme',
    priority: 'medium',
    due: [1, 14, 0],
    mirror: true,
  },
  {
    title: 'Dentist — 6-month check-up',
    project: 'personal',
    priority: 'medium',
    due: [2, 9, 30],
    tags: ['health'],
    mirror: true,
  },
  {
    title: 'Ship the Turkish store screenshots',
    project: 'launch',
    priority: 'high',
    due: [3, 16, 0],
    tags: ['design'],
  },
  {
    title: 'Pay the quarterly VAT',
    project: 'personal',
    priority: 'high',
    urgent: true,
    due: [4, 10, 0],
    tags: ['finance'],
  },
  { title: 'Read “Shape Up”, part two', project: 'reading', due: [5, 20, 0], tags: ['writing'] },

  // ── The next 30 days ─────────────────────────────────────────────────────
  {
    title: 'Q1 planning offsite',
    project: 'launch',
    priority: 'medium',
    due: [9, 10, 0],
    tags: ['deep-work'],
    description: 'Two days. Agenda note is linked from the project README.',
    mirror: true,
  },
  {
    title: 'Renew the Apple Developer membership',
    project: 'launch',
    priority: 'high',
    due: [12, 12, 0],
    tags: ['finance'],
  },
  { title: 'Mum’s birthday', project: 'personal', priority: 'high', due: [16, 9, 0], tags: ['family'] },
  {
    title: 'Hand over the design tokens package',
    project: 'design',
    priority: 'medium',
    due: [19, 15, 0],
    tags: ['design'],
  },
  { title: 'Finish “The Making of Prince of Persia”', project: 'reading', due: [24, 21, 0] },
  {
    title: 'Kitchen install — day one',
    project: 'home',
    priority: 'high',
    due: [27, 8, 0],
    tags: ['errand'],
  },

  // ── Board columns: in progress / waiting ─────────────────────────────────
  // Most of these carry a date. Work that is genuinely under way usually has a
  // target day, and — the reason it matters here — Home puts dateless tasks
  // ABOVE the dated groups (OPH-108), so a demo with a dozen undated rows
  // pushes today's actual plan off the first screen.
  {
    title: 'Wire the presigned upload flow',
    project: 'launch',
    status: 'in_progress',
    priority: 'high',
    due: [0, 15, 0],
    tags: ['deep-work'],
  },
  {
    title: 'Rewrite the landing page hero',
    project: 'launch',
    status: 'in_progress',
    due: [1, 13, 0],
    tags: ['writing'],
  },
  {
    title: 'Dark-mode pass on the Board',
    project: 'design',
    status: 'in_progress',
    due: [2, 14, 0],
    tags: ['design'],
  },
  {
    title: 'Waiting on Acme’s brand assets',
    project: 'acme',
    status: 'waiting',
    due: [3, 12, 0],
    tags: ['blocked'],
  },
  {
    title: 'Blocked: App Store review in progress',
    project: 'launch',
    status: 'waiting',
    due: [6, 12, 0],
    tags: ['blocked', 'review'],
  },
  { title: 'Waiting for the counter-top quote', project: 'home', status: 'waiting' },

  // ── History: what Settings ▸ Completed scrolls back through ──────────────
  { title: 'Tag v0.9.0', project: 'launch', completed: true, completedAt: ago({ days: 1, hours: 3 }) },
  {
    title: 'Migrate the docs site to the new domain',
    project: 'launch',
    completed: true,
    completedAt: ago({ days: 1, hours: 9 }),
  },
  {
    title: 'Contrast audit — light + dark',
    project: 'design',
    completed: true,
    completedAt: ago({ days: 2, hours: 5 }),
  },
  {
    title: 'Send the August invoice',
    project: 'acme',
    completed: true,
    completedAt: ago({ days: 3, hours: 6 }),
  },
  {
    title: 'Book the flights',
    project: 'personal',
    completed: true,
    completedAt: ago({ days: 4, hours: 2 }),
  },
  {
    title: 'Order the kitchen tiles',
    project: 'home',
    completed: true,
    completedAt: ago({ days: 5, hours: 7 }),
  },
  {
    title: 'Finish the Q4 retro write-up',
    project: 'y2025',
    completed: true,
    completedAt: ago({ days: 8, hours: 4 }),
  },
  {
    title: 'Close the 2025 books',
    project: 'y2025',
    completed: true,
    completedAt: ago({ days: 11, hours: 2 }),
  },
];

/** Subtasks: `parent` is the title of a task above. */
const SUBTASKS = [
  { parent: 'Kitchen install — day one', title: 'Clear the worktops the night before', due: [26, 20, 0] },
  { parent: 'Kitchen install — day one', title: 'Confirm the delivery window', due: [25, 12, 0] },
  { parent: 'Kitchen install — day one', title: 'Book the lift for 08:00', completed: true },
  { parent: 'Q1 planning offsite', title: 'Book the room', completed: true },
  { parent: 'Q1 planning offsite', title: 'Send the pre-read', due: [7, 12, 0] },
  { parent: 'Q1 planning offsite', title: 'Draft the agenda', due: [8, 15, 0] },
];

/**
 * Recurring series. These are the demo's argument against Google Calendar's
 * recurrence: the rent rule asks for the 31st, and February gets the 28th
 * instead of being skipped (ADR-0020 §2).
 */
const SERIES = [
  // Weekdays, but with an END: an unbounded daily series materialises a year
  // of rows and buries every other task in the 30-day window. Ten occurrences
  // still show the "every weekday" sentence and the repeat badge, without the
  // demo's Home turning into a column of stand-ups.
  {
    label: 'Stand-up, every weekday (ends after 10)',
    template: { title: 'Stand-up', project: 'launch', priority: 'none' },
    rule: {
      freq: 'weekly',
      interval: 1,
      byWeekday: [{ day: 'MO' }, { day: 'TU' }, { day: 'WE' }, { day: 'TH' }, { day: 'FR' }],
      end: { type: 'count', count: 6 },
    },
    anchor: [1, 9, 15],
  },
  {
    label: 'Weekly review, Friday afternoon',
    template: { title: 'Weekly review', project: 'personal', priority: 'medium', tags: ['deep-work'] },
    rule: { freq: 'weekly', interval: 1, byWeekday: [{ day: 'FR' }], end: { type: 'count', count: 5 } },
    anchor: [1, 16, 0],
  },
  // The clamping demo: ask for the 31st and February hands back the 28th
  // rather than dropping the month (ADR-0020 §2 — Google Calendar drops it).
  {
    label: 'Rent, on the 31st — clamps to month end',
    template: {
      title: 'Pay the rent',
      project: 'personal',
      priority: 'high',
      urgent: true,
      tags: ['finance'],
    },
    rule: { freq: 'monthly', interval: 1, byMonthDay: [31], end: { type: 'count', count: 3 } },
    anchor: [1, 10, 0],
  },
  {
    label: 'Retainer invoice — 2nd Tuesday of the month',
    template: { title: 'Invoice Acme', project: 'acme', priority: 'high', tags: ['finance'] },
    rule: {
      freq: 'monthly',
      interval: 1,
      byWeekday: [{ day: 'TU', ordinal: 2 }],
      end: { type: 'count', count: 3 },
    },
    anchor: [2, 11, 0],
  },
];

const NOTES = [
  {
    title: 'Launch v1.0 — overview',
    project: 'launch',
    readmeFor: 'launch',
    pinned: true,
    body: [
      'Everything the 1.0 release needs, in the order it needs it.',
      '',
      'Scope: the app is feature-complete. What is left is store review, the landing page and the launch-day comms. Nothing new ships before the tag.',
      '',
      'Owner: Alex · Target: end of the month · Risk: App Store review turnaround.',
    ],
  },
  {
    title: 'Design System — overview',
    project: 'design',
    readmeFor: 'design',
    body: [
      'Three token layers: primitive → semantic → component. Nothing in a widget reads a primitive directly.',
      '',
      'Every colour pair is contrast-checked in light and dark before it lands. The check is a script, not a habit.',
    ],
  },
  {
    title: 'Launch checklist',
    project: 'launch',
    pinned: true,
    body: [
      'Store copy, screenshots (6.9", 6.5", iPad 13", Android phone + tablet), feature graphic, press kit, changelog, landing page, the announcement post.',
      '',
      'Everything below the line is done: privacy policy, support address, the demo account for reviewers.',
    ],
  },
  {
    title: 'Meeting — Acme kickoff',
    project: 'acme',
    body: [
      'Deniz wants the reporting view first; the import can wait until the second sprint.',
      '',
      'Invoices on the last working day of the month. Net-30. Timesheet export attached to each one.',
    ],
  },
  {
    title: 'Renovation measurements',
    project: 'home',
    body: ['Kitchen 3.20 × 4.10 m · hallway 1.10 m wide · counter run 2.60 m.', '', 'Ceiling height 2.74 m — the wall units fit with 6 cm to spare.'],
  },
  {
    title: 'Reading notes — Shape Up',
    project: 'reading',
    body: [
      'Appetite, not estimate: decide how much time something is worth and shape the work to fit it.',
      '',
      'Circuit breaker: a project that runs over does not get an extension by default.',
    ],
  },
  {
    title: 'Weekly review template',
    pinned: true,
    body: [
      'What moved? What did not, and why?',
      'What is overdue, and is it still real?',
      'One thing to drop. One thing to finish before anything new starts.',
    ],
  },
  {
    title: 'Interview questions — design hire',
    project: 'design',
    body: ['Show me something you shipped that you would now build differently.', '', 'Walk me through a decision you lost.'],
  },
];

const FOLDERS = [
  { key: 'docs', name: 'Documents' },
  { key: 'invoices', name: 'Invoices' },
  { key: 'brand', name: 'Brand', parent: 'docs' },
  { key: 'photos', name: 'Photos' },
];

const FILES = [
  { name: 'brand-guidelines.pdf', folder: 'brand', mime: 'application/pdf', kb: 2400 },
  { name: 'logo-master.svg', folder: 'brand', mime: 'image/svg+xml', kb: 46 },
  { name: 'floor-plan.png', folder: 'docs', mime: 'image/png', kb: 840 },
  { name: 'kitchen-quote.pdf', folder: 'docs', mime: 'application/pdf', kb: 320 },
  { name: 'acme-invoice-09.pdf', folder: 'invoices', mime: 'application/pdf', kb: 118 },
  { name: 'acme-invoice-08.pdf', folder: 'invoices', mime: 'application/pdf', kb: 116 },
  { name: 'counter-samples.jpg', folder: 'photos', mime: 'image/jpeg', kb: 1650 },
];

const QUICK_LINKS = [
  { kind: 'project', target: 'launch', title: 'Launch v1.0', emoji: '🚀', colorRgb: '#8E44EC' },
  { kind: 'project', target: 'design', title: 'Design System', emoji: '🎨', colorRgb: '#2563EB' },
  { kind: 'note', targetNote: 'Weekly review template', title: 'Weekly review', emoji: '🧭' },
  { kind: 'note', targetNote: 'Launch checklist', title: 'Launch checklist', emoji: '✅' },
  { kind: 'folder', targetFolder: 'invoices', title: 'Invoices', emoji: '🧾' },
  { kind: 'task', targetTask: 'Write the release notes for 1.0', title: 'Release notes', emoji: '📝' },
  { kind: 'url', url: 'https://github.com/mahirozdin/alliswell', title: 'GitHub repo', emoji: '⭐' },
];

// ── Seeding ─────────────────────────────────────────────────────────────────

const log = (...a) => console.log(...a);

async function authenticate() {
  try {
    const out = await post('/auth/register', {
      email: EMAIL,
      password: PASSWORD,
      displayName: DISPLAY_NAME,
    });
    token = out.tokens.accessToken;
    workspaceId = out.workspace.id;
    log(`✓ registered ${EMAIL}`);
  } catch (err) {
    if (err.status !== 409) throw err;
    const out = await post('/auth/login', { email: EMAIL, password: PASSWORD });
    token = out.tokens.accessToken;
    const me = await get('/me');
    workspaceId = me.workspaces?.[0]?.id ?? me.workspace?.id;
    if (!workspaceId) throw new Error('logged in but found no workspace on /me');
    log(`✓ signed in as ${EMAIL} (existing account)`);
  }
}

/** Everything the account already has, so a re-run tops up instead of doubling. */
async function existingTitles() {
  const seen = new Set();
  let cursor = null;
  do {
    const q = new URLSearchParams({ limit: '200' });
    for (const s of ['inbox', 'open', 'scheduled', 'in_progress', 'waiting', 'completed']) {
      q.append('status', s);
    }
    if (cursor) q.set('cursor', cursor);
    const page = await get(`/workspaces/${workspaceId}/tasks?${q}`);
    for (const t of page.items) seen.add(t.title);
    cursor = page.nextCursor;
  } while (cursor);
  return seen;
}

async function main() {
  log(`AllisWell demo seed → ${API}`);
  await authenticate();

  const already = await existingTitles();
  if (already.size > 0) {
    log(`  (workspace already holds ${already.size} tasks — only missing rows are created)`);
  }

  // Projects
  const projectId = {};
  const liveProjects = (await get(`/workspaces/${workspaceId}/projects`)).items;
  for (const p of PROJECTS) {
    const hit = liveProjects.find((x) => x.name === p.name);
    if (hit) {
      projectId[p.key] = hit.id;
      continue;
    }
    const { key, ...body } = p;
    const created = await post(`/workspaces/${workspaceId}/projects`, body);
    projectId[key] = created.id;
  }
  log(`✓ ${PROJECTS.length} projects`);

  // Tags
  const tagId = {};
  const liveTags = (await get(`/workspaces/${workspaceId}/tags`)).items;
  for (const name of TAGS) {
    const hit = liveTags.find((x) => x.name === name);
    tagId[name] = hit ? hit.id : (await post(`/workspaces/${workspaceId}/tags`, { name })).id;
  }
  log(`✓ ${TAGS.length} tags`);

  // Tasks
  const taskId = {};
  const dueOf = (t) => (t.overdue ? ago(t.overdue) : t.due ? at(...t.due) : null);

  async function createTask(t, parentTaskId = null) {
    if (already.has(t.title) && !parentTaskId) return null;
    const due = dueOf(t);
    const body = {
      title: t.title,
      timezone: TZ,
      ...(t.description ? { description: t.description } : {}),
      ...(t.project ? { projectId: projectId[t.project] } : {}),
      ...(t.status ? { status: t.status } : {}),
      ...(t.priority ? { priority: t.priority } : {}),
      ...(t.color ? { colorRgb: t.color } : {}),
      // `isUrgent` is the ALARM switch, not the red flag — the flag comes from
      // `priority: 'urgent'`. Since OPH-138 an urgent task synthesises an alarm
      // at its own due time even with no explicit reminder, so an overdue
      // urgent row opens the app straight into the full-screen ring. Correct
      // behaviour; wrong for a workspace people sign into to look around. So
      // the alarm switch is only thrown for tasks whose time has not passed;
      // overdue rows keep the urgent priority and its red flag.
      ...(t.urgent && (!due || Date.parse(due) > Date.now())
        ? { isUrgent: true, requiresAcknowledgement: true }
        : {}),
      ...(t.mirror ? { calendarMirrorEnabled: true } : {}),
      ...(due ? { dueAt: due, ...(Date.parse(due) > Date.now() ? { remindAt: due } : {}) } : {}),
      ...(parentTaskId ? { parentTaskId } : {}),
      ...(t.tags?.length ? { tagIds: t.tags.map((n) => tagId[n]) } : {}),
    };
    const created = await post(`/workspaces/${workspaceId}/tasks`, body);
    taskId[t.title] = created.id;

    for (const item of t.checklist ?? []) {
      const row = await post(`/tasks/${created.id}/checklist`, { title: item.title });
      if (item.done) await patch(`/tasks/${created.id}/checklist/${row.id}`, { isDone: true });
    }
    if (t.completed) {
      await post(`/tasks/${created.id}/complete`, {});
      // The server stamps `completed_at` at transition time and offers no way
      // to say otherwise — see the file header. Remember what this row's
      // completion should claim; `backdateCompletions()` applies it at the end.
      if (t.completedAt) backdated.set(created.id, t.completedAt);
    }
    return created.id;
  }

  let made = 0;
  for (const t of TASKS) if (await createTask(t)) made += 1;
  log(`✓ ${made} tasks (${TASKS.length - made} already there)`);

  let subs = 0;
  for (const s of SUBTASKS) {
    const parent = taskId[s.parent];
    if (!parent) continue;
    if (await createTask({ ...s, project: TASKS.find((t) => t.title === s.parent)?.project }, parent))
      subs += 1;
  }
  log(`✓ ${subs} subtasks`);

  // Recurring series
  const liveSeries = (await get(`/workspaces/${workspaceId}/task-series`)).series;
  let series = 0;
  for (const s of SERIES) {
    if (liveSeries.some((x) => x.template?.title === s.template.title)) continue;
    const anchorAt = at(...s.anchor);
    const template = {
      title: s.template.title,
      ...(s.template.project ? { projectId: projectId[s.template.project] } : {}),
      ...(s.template.priority ? { priority: s.template.priority } : {}),
      ...(s.template.urgent ? { isUrgent: true, requiresAcknowledgement: true } : {}),
      ...(s.template.tags?.length ? { tagIds: s.template.tags.map((n) => tagId[n]) } : {}),
    };
    try {
      const out = await post(`/workspaces/${workspaceId}/task-series`, {
        rule: s.rule,
        template,
        timezone: TZ,
        anchorAt,
      });
      series += 1;
      log(`  · ${s.label} → ${out.created} occurrences materialised`);
    } catch (err) {
      log(`  ! ${s.label} skipped: ${err.message.split('\n')[0]}`);
    }
  }
  log(`✓ ${series} recurring series`);

  // Notes
  const noteId = {};
  const liveNotes = (await get(`/workspaces/${workspaceId}/notes?limit=200`)).items;
  for (const n of NOTES) {
    const hit = liveNotes.find((x) => x.title === n.title);
    if (hit) {
      noteId[n.title] = hit.id;
      continue;
    }
    // Quill Delta: the first line carries the H1 the editor shows as a title.
    const delta = [];
    n.body.forEach((line, i) => {
      delta.push({ insert: `${line}\n` });
      if (i === 0) delta[delta.length - 1] = { insert: `${line}\n`, attributes: undefined };
    });
    const created = await post(`/workspaces/${workspaceId}/notes`, {
      title: n.title,
      contentDelta: n.body.flatMap((line) => [{ insert: `${line}\n` }]),
      ...(n.project ? { projectId: projectId[n.project] } : {}),
      ...(n.pinned ? { isPinned: true } : {}),
    });
    noteId[n.title] = created.id;
    if (n.readmeFor) {
      await patch(`/projects/${projectId[n.readmeFor]}`, { readmeNoteId: created.id });
    }
  }
  log(`✓ ${NOTES.length} notes`);

  // Folders + files
  const folderId = {};
  const liveFolders = (await get(`/workspaces/${workspaceId}/folders`)).items;
  for (const f of FOLDERS) {
    const hit = liveFolders.find((x) => x.name === f.name);
    folderId[f.key] = hit
      ? hit.id
      : (
          await post(`/workspaces/${workspaceId}/folders`, {
            name: f.name,
            ...(f.parent ? { parentId: folderId[f.parent] } : {}),
          })
        ).id;
  }
  log(`✓ ${FOLDERS.length} folders`);

  if (WANT_FILES) {
    const storage = await get('/storage').catch(() => ({ configured: false }));
    if (!storage.configured) {
      log('· files skipped — no object storage configured on this instance');
    } else {
      const liveFiles =
        (await get(`/workspaces/${workspaceId}/files?targetType=workspace&targetId=${workspaceId}`))
          .items ?? [];
      let uploaded = 0;
      for (const f of FILES) {
        if (liveFiles.some((x) => x.name === f.name)) continue;
        const bytes = Buffer.alloc(f.kb * 1024, 0x20);
        // A recognisable header so a downloaded demo file is not a mystery.
        Buffer.from(`AllisWell demo file — ${f.name}\n`).copy(bytes);
        try {
          const init = await post(`/workspaces/${workspaceId}/files`, {
            targetType: 'workspace',
            targetId: workspaceId,
            name: f.name,
            mime: f.mime,
            sizeBytes: bytes.length,
            folderId: folderId[f.folder],
          });
          // Bare PUT: the presigned URL is already the authorization — adding
          // our own Authorization header makes S3 reject the signature.
          const put = await fetch(init.upload.url, {
            method: init.upload.method ?? 'PUT',
            headers: init.upload.headers ?? {},
            body: bytes,
          });
          if (!put.ok) throw new Error(`storage PUT ${put.status}`);
          await post(`/files/${init.file.id}/complete`, {});
          uploaded += 1;
        } catch (err) {
          log(`  ! ${f.name}: ${err.message.split('\n')[0]}`);
        }
      }
      log(`✓ ${uploaded} files uploaded`);
    }
  }

  // Quick access
  const liveLinks = (await get(`/workspaces/${workspaceId}/quick-links`)).items;
  let links = 0;
  for (const q of QUICK_LINKS) {
    if (liveLinks.some((x) => x.title === q.title)) continue;
    const target =
      q.kind === 'project'
        ? projectId[q.target]
        : q.kind === 'note'
          ? noteId[q.targetNote]
          : q.kind === 'folder'
            ? folderId[q.targetFolder]
            : q.kind === 'task'
              ? taskId[q.targetTask]
              : null;
    if (q.kind !== 'url' && !target) continue;
    try {
      await post(`/workspaces/${workspaceId}/quick-links`, {
        kind: q.kind,
        title: q.title,
        ...(target ? { targetId: target } : {}),
        ...(q.url ? { url: q.url } : {}),
        ...(q.emoji ? { emoji: q.emoji } : {}),
        ...(q.colorRgb ? { colorRgb: q.colorRgb } : {}),
      });
      links += 1;
    } catch (err) {
      log(`  ! quick link ${q.title}: ${err.message.split('\n')[0]}`);
    }
  }
  log(`✓ ${links} quick-access shortcuts`);

  if (WANT_BACKDATE) await backdateCompletions();

  log('');
  log('Demo workspace ready.');
  log(`  sign in: ${EMAIL} / ${PASSWORD}`);
  log(`  workspace: ${workspaceId}`);
}

/**
 * Rewrites `completed_at` on the history rows, straight in the database.
 *
 * This is the script's ONE bypass of the API and it is here because there is no
 * API to bypass: `completed_at` is stamped by the server on the transition and
 * is not writable through REST or through the sync push path — correctly, since
 * a client that could backdate its own completions could rewrite anybody's
 * history. A demo workspace still needs a Completed timeline with more than one
 * day in it, so the seeder reaches past the fence once, loudly, and only for
 * rows it created seconds earlier.
 *
 * Silently skipped when no database is reachable (seeding a remote instance),
 * which just means every completion reads as "today".
 */
async function backdateCompletions() {
  if (backdated.size === 0) return;
  let db;
  try {
    const { default: knex } = await import('knex');
    const { loadConfig } = await import('../apps/api/src/config.js');
    const { buildKnexConfig } = await import('../apps/api/src/db/knexconfig.js');
    db = knex(buildKnexConfig(loadConfig()));
    await db.raw('select 1');
  } catch (err) {
    await db?.destroy().catch(() => {});
    log(`· completion history left at today — no database reachable (${err.message.split('\n')[0]})`);
    return;
  }

  try {
    for (const [id, iso] of backdated) {
      await db('tasks')
        .where({ id })
        .update({ completed_at: new Date(iso), updated_at: new Date(iso) });
    }
    log(`✓ ${backdated.size} completions backdated (Settings ▸ Completed now has a history)`);
  } finally {
    await db.destroy().catch(() => {});
  }
}

main().catch((err) => {
  console.error(`\n✗ seed failed: ${err.message}`);
  process.exit(1);
});
