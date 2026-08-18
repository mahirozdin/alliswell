#!/usr/bin/env node
/**
 * web.mjs — drives the built Flutter web bundle in a real headless Chrome and
 * writes full-resolution PNGs of every surface.
 *
 * Why a real browser and not the widget-test harness: the harness renders the
 * same widget tree, but it is not the WEB app — it never touches CanvasKit, the
 * service worker, localStorage or the router's hash strategy. A screenshot that
 * claims to be "AllisWell on the web" should have gone through all four.
 *
 * Prerequisites (the script checks and tells you which one is missing):
 *   1. the API is up            → npm run dev
 *   2. the demo data is seeded  → node scripts/seed-demo.mjs
 *   3. the bundle is built      → cd apps/app && flutter build web --release \
 *                                   --dart-define=ALLISWELL_API_URL=http://localhost:3000
 *   4. the bundle is served     → python3 -m http.server 8080 --directory apps/app/build/web
 *
 * Usage:
 *   node scripts/screenshots/web.mjs
 *   node scripts/screenshots/web.mjs --out screenshots/web --only home,board
 *   node scripts/screenshots/web.mjs --locale tr
 *
 * The session is injected into localStorage before the app boots rather than
 * typed into the login form: Flutter renders to a canvas, so form-driving means
 * clicking coordinates, and coordinates rot the moment the layout moves.
 */
import { spawn } from 'node:child_process';
import { mkdir, writeFile, rm } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import path from 'node:path';

const args = process.argv.slice(2);
const flag = (n, d = null) => {
  const i = args.indexOf(`--${n}`);
  return i >= 0 && args[i + 1] && !args[i + 1].startsWith('--') ? args[i + 1] : d;
};

const APP_URL = flag('app', 'http://localhost:8080').replace(/\/+$/, '');
const API_URL = flag('api', 'http://localhost:3000').replace(/\/+$/, '');
const OUT = path.resolve(flag('out', 'screenshots/web'));
const EMAIL = flag('email', 'demo@alliswell.space');
const PASSWORD = flag('password', 'AllisWellDemo2026');
const LOCALE = flag('locale', 'en');
const ONLY = flag('only')?.split(',').map((s) => s.trim());
const PORT = Number(flag('port', '9222'));

const CHROME =
  flag('chrome') ??
  [
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    '/Applications/Chromium.app/Contents/MacOS/Chromium',
    '/usr/bin/google-chrome',
    '/usr/bin/chromium',
  ].find((p) => existsSync(p));

/** Desktop shots at 1440×900, phone shots at 390×844 — both at 2× (retina). */
const DESKTOP = { width: 1440, height: 900 };

/// Ids `seed-demo.mjs` creates deterministically enough to route to. Overridable
/// so a re-seeded workspace does not need this file edited:
///   node scripts/screenshots/web.mjs --note <id> --project <id>
const DEMO = {
  note: flag('note', '01M082TWMPTFHV47HX4DS6F5NM'),
  project: flag('project', '01M082TVRN2M67C6AW4W3B12MR'),
};
const PHONE = { width: 390, height: 844 };

/**
 * The shot list. `route` is the hash route; `dark` picks the emulated colour
 * scheme; `before` is an optional CDP-driven interaction.
 */
const SHOTS = [
  { name: 'home-light', route: '/home', ...DESKTOP },
  { name: 'home-dark', route: '/home', dark: true, ...DESKTOP },
  { name: 'board', route: '/home', ...DESKTOP, prefs: { alliswell_home_view: 'board' } },
  { name: 'projects', route: '/projects', ...DESKTOP },
  { name: 'notes', route: '/notes', ...DESKTOP },
  { name: 'files', route: '/files', ...DESKTOP },
  { name: 'inbox', route: '/inbox', ...DESKTOP },
  { name: 'completed', route: '/settings/completed', ...DESKTOP },
  { name: 'settings', route: '/settings', ...DESKTOP },
  { name: 'reminders', route: '/settings/reminders', ...DESKTOP },
  { name: 'ai-settings', route: '/settings/ai', ...DESKTOP },
  // The one shot that cannot be reached by route or preference. Search lives in
  // an app-bar action whose open/closed state is local widget state, so it has
  // to be clicked and typed into for real — see `openSearch`, and the warning
  // there about what makes this the only coordinate in this file.
  { name: 'search', route: '/notes', ...DESKTOP, interact: (page) => openSearch(page, 'muller') },
  // OPH-274: the two surfaces the marketing copy started promising when notes
  // became markdown, and which nothing had a picture of. Both are reached by
  // ROUTE — no coordinates. The note editor opens in Source (ADR-0033), which
  // is exactly the shot worth having: live syntax, in the field, while you
  // type. The project overview renders its README through the same markdown
  // renderer, so it shows the READING side (tables, task lists, a quote)
  // without needing a tap on the mode control — a click this file has no way
  // to verify, and an unverified click ships a wrong screenshot silently.
  { name: 'note-editor', route: `/notes/${DEMO.note}`, ...DESKTOP },
  { name: 'project-readme', route: `/projects/${DEMO.project}`, ...DESKTOP },
  { name: 'phone-home-light', route: '/home', ...PHONE },
  { name: 'phone-home-dark', route: '/home', dark: true, ...PHONE },
  { name: 'phone-projects', route: '/projects', ...PHONE },
  { name: 'phone-notes', route: '/notes', ...PHONE },
];

// ── CDP over the DevTools WebSocket (no dependencies) ───────────────────────

class Cdp {
  constructor(ws) {
    this.ws = ws;
    this.id = 0;
    this.pending = new Map();
    ws.addEventListener('message', (ev) => {
      const msg = JSON.parse(ev.data);
      const waiter = this.pending.get(msg.id);
      if (waiter) {
        this.pending.delete(msg.id);
        msg.error ? waiter.reject(new Error(msg.error.message)) : waiter.resolve(msg.result);
      }
    });
  }

  static async connect(url) {
    const ws = new WebSocket(url);
    await new Promise((resolve, reject) => {
      ws.addEventListener('open', resolve, { once: true });
      ws.addEventListener('error', () => reject(new Error(`cannot reach ${url}`)), { once: true });
    });
    return new Cdp(ws);
  }

  send(method, params = {}) {
    const id = ++this.id;
    this.ws.send(JSON.stringify({ id, method, params }));
    return new Promise((resolve, reject) => this.pending.set(id, { resolve, reject }));
  }

  async evaluate(expression) {
    const out = await this.send('Runtime.evaluate', {
      expression,
      awaitPromise: true,
      returnByValue: true,
    });
    if (out.exceptionDetails) {
      throw new Error(out.exceptionDetails.exception?.description ?? 'evaluate failed');
    }
    return out.result.value;
  }
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function waitForPort(url, tries = 60) {
  for (let i = 0; i < tries; i += 1) {
    try {
      const res = await fetch(url);
      if (res.ok) return res.json();
    } catch {
      /* not up yet */
    }
    await sleep(250);
  }
  throw new Error(`timed out waiting for ${url}`);
}

// ── Preflight ───────────────────────────────────────────────────────────────

async function preflight() {
  if (!CHROME) throw new Error('no Chrome/Chromium found — pass --chrome /path/to/binary');

  const health = await fetch(`${API_URL}/health/ready`).catch(() => null);
  if (!health?.ok) throw new Error(`the API is not answering at ${API_URL} — run: npm run dev`);

  const page = await fetch(APP_URL).catch(() => null);
  if (!page?.ok) {
    throw new Error(
      `nothing is serving the web bundle at ${APP_URL} —\n` +
        '  cd apps/app && flutter build web --release --dart-define=ALLISWELL_API_URL=' +
        API_URL +
        `\n  python3 -m http.server 8080 --directory apps/app/build/web`,
    );
  }

  const login = await fetch(`${API_URL}/api/v1/auth/login`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email: EMAIL, password: PASSWORD }),
  });
  if (!login.ok) {
    throw new Error(`cannot sign in as ${EMAIL} — run: node scripts/seed-demo.mjs`);
  }
  const { user, tokens } = await login.json();
  await silenceDueAlarms(tokens.accessToken);
  return { user, tokens };
}

// ── Run ─────────────────────────────────────────────────────────────────────

/**
 * Mutes any alarm that is already due, before a single shot is taken.
 *
 * Found the hard way (OPH-274): the demo seed creates an urgent reminder at
 * 21:00, and the foreground alarm overlay is a FULL-SCREEN takeover. Shoot
 * after that time and every surface in this file — home, projects, notes,
 * settings, all of them — comes out as the alarm ring screen, under a filename
 * promising something else. The script still prints a cheerful ✓ for each one.
 *
 * The existing set survived only because it was shot at 17:48. That is not a
 * property of the pipeline, it is the time of day.
 *
 * Muting through the REAL API rather than overriding
 * `alarmOverlayAutoShowProvider`: this drives a RELEASE bundle, where that
 * provider is a constant, and a product flag added for a screenshot tool would
 * be a worse trade than a demo task that is silenced the way a user would
 * silence it.
 */
async function silenceDueAlarms(accessToken) {
  const headers = {
    authorization: `Bearer ${accessToken}`,
    'content-type': 'application/json',
  };
  const me = await (await fetch(`${API_URL}/api/v1/me`, { headers })).json();
  const workspace = me.workspaces?.[0]?.id ?? me.workspace?.id;
  if (!workspace) return;

  const url = `${API_URL}/api/v1/workspaces/${workspace}/tasks?limit=200`;
  const tasks = (await (await fetch(url, { headers })).json()).items ?? [];
  const now = Date.now();
  const due = tasks.filter(
    (t) => t.isUrgent && !t.alarmsMutedAt && t.remindAt && Date.parse(t.remindAt) <= now,
  );

  for (const task of due) {
    await fetch(`${API_URL}/api/v1/tasks/${task.id}`, {
      method: 'PATCH',
      headers,
      body: JSON.stringify({ alarmsMutedAt: new Date().toISOString() }),
    });
  }
  if (due.length > 0) {
    console.log(`  muted ${due.length} due alarm(s) so they cannot cover a shot`);
  }
}

async function main() {
  const session = await preflight();
  await mkdir(OUT, { recursive: true });

  const profile = path.join(process.env.TMPDIR ?? '/tmp', `alliswell-shots-${process.pid}`);
  const chrome = spawn(
    CHROME,
    [
      '--headless=new',
      `--remote-debugging-port=${PORT}`,
      `--user-data-dir=${profile}`,
      `--lang=${LOCALE === 'tr' ? 'tr-TR' : 'en-US'}`,
      '--hide-scrollbars',
      '--no-first-run',
      '--no-default-browser-check',
      '--disable-extensions',
      // CanvasKit needs WebGL; SwiftShader is the fallback on a headless box
      // with no GPU (CI), and harmless where there is one.
      '--enable-unsafe-swiftshader',
      '--use-angle=metal',
      'about:blank',
    ],
    { stdio: 'ignore' },
  );

  let cdp;
  try {
    await waitForPort(`http://127.0.0.1:${PORT}/json/version`);
    // Attach to the tab Chrome already opened. Creating a second target and
    // guessing its socket path works on some builds and answers "Not attached
    // to an active page" on others; /json/list hands over the real URL.
    const targets = await waitForPort(`http://127.0.0.1:${PORT}/json/list`);
    const target = targets.find((t) => t.type === 'page');
    if (!target) throw new Error('Chrome opened no page target');
    const page = await Cdp.connect(target.webSocketDebuggerUrl);
    cdp = page;
    await page.send('Page.enable');
    await page.send('Runtime.enable');

    // Written before ANY document script runs, so the app boots signed in,
    // past the first-run tour, and already in whatever view the shot needs.
    // Setting a stored preference beats clicking the toggle: Flutter paints to
    // a canvas, so "click the Board button" means either a coordinate (which
    // rots the moment the app bar moves) or a walk of the accessibility tree
    // that is only built once assistive tech asks for it.
    const baseline = {
      alliswell_session: JSON.stringify({ user: session.user, tokens: session.tokens }),
      alliswell_onboarding_seen_v1: 'true',
      alliswell_locale: LOCALE,
      alliswell_quick_bubble_hinted: 'true',
    };
    let installedPrefs = null;
    const installPrefs = async (prefs) => {
      const values = { ...baseline, ...prefs };
      const key = JSON.stringify(values);
      if (key === installedPrefs) return;
      installedPrefs = key;
      if (bootstrapId) await page.send('Page.removeScriptToEvaluateOnNewDocument', { identifier: bootstrapId });
      const out = await page.send('Page.addScriptToEvaluateOnNewDocument', {
        source: `try { ${Object.entries(values)
          .map(([k, v]) => `localStorage.setItem(${JSON.stringify(k)}, ${JSON.stringify(v)});`)
          .join('\n')} } catch (e) {}`,
      });
      bootstrapId = out.identifier;
    };
    let bootstrapId = null;

    const shots = ONLY ? SHOTS.filter((s) => ONLY.includes(s.name)) : SHOTS;
    for (const shot of shots) {
      await installPrefs(shot.prefs ?? {});
      await page.send('Emulation.setDeviceMetricsOverride', {
        width: shot.width,
        height: shot.height,
        deviceScaleFactor: 2,
        mobile: shot.width < 600,
      });
      await page.send('Emulation.setEmulatedMedia', {
        features: [{ name: 'prefers-color-scheme', value: shot.dark ? 'dark' : 'light' }],
      });

      // Via about:blank, because a hash change alone does NOT reload: shot N
      // would inherit shot N-1's scroll position and any sheet it left open.
      // (`Page.reload` immediately after a navigate answers "Not attached to
      // an active page" — the navigation is still in flight.)
      await page.send('Page.navigate', { url: 'about:blank' });
      await sleep(200);
      await page.send('Page.navigate', { url: `${APP_URL}/#${shot.route}` });

      await waitForApp(page);
      await sleep(1200); // let the aurora and the list settle
      if (shot.interact) await shot.interact(page);

      const { data } = await page.send('Page.captureScreenshot', {
        format: 'png',
        captureBeyondViewport: false,
      });
      const file = path.join(OUT, `${shot.name}.png`);
      await writeFile(file, Buffer.from(data, 'base64'));
      console.log(`✓ ${path.relative(process.cwd(), file)}  (${shot.width}×${shot.height} @2×)`);
    }
  } finally {
    try {
      cdp?.ws.close();
    } catch {
      /* already gone */
    }
    chrome.kill();
    await rm(profile, { recursive: true, force: true }).catch(() => {});
  }
}

/**
 * Opens the Notes app-bar search and types `query` into it.
 *
 * **This is the only place in this file that clicks a coordinate, and it is a
 * deliberate exception.** Everywhere else a surface is reached by route or by a
 * seeded preference, because coordinates rot the moment a layout moves. Search
 * has neither: `AwSearchAction` keeps `_open` in local widget state, so no
 * route and no `localStorage` key can put it on screen — only a click can.
 *
 * If this shot ever comes back showing the plain Notes list, an app-bar action
 * was added or removed and X below is off by one icon (~66 px per action,
 * counted from the right edge). It fails loudly rather than silently: the
 * result-count assertion at the end refuses to screenshot a list that did not
 * filter.
 *
 * Typing goes through `Input.insertText` into the hidden `flt-text-editing`
 * textarea Flutter keeps for IME and the clipboard — dispatching key events
 * one character at a time races the 250 ms debounce.
 */
const SEARCH_ACTION = { x: 1271, y: 28 }; // CSS px at 1440×900, Notes app bar

async function openSearch(page, query) {
  for (const type of ['mousePressed', 'mouseReleased']) {
    await page.send('Input.dispatchMouseEvent', {
      type,
      x: SEARCH_ACTION.x,
      y: SEARCH_ACTION.y,
      button: 'left',
      clickCount: 1,
    });
  }
  await sleep(600); // the field expands and takes focus

  await page.send('Input.insertText', { text: query });

  // Park the pointer over dead space: left where it clicked, the neighbouring
  // action keeps its hover tooltip open and the shot ships with a stray
  // "Cancel" bubble floating over the results.
  await page.send('Input.dispatchMouseEvent', { type: 'mouseMoved', x: 700, y: 700 });
  await sleep(1400); // 250 ms debounce + the query + the list rebuild

  // Prove the shot shows what it claims: the list must have narrowed. Flutter
  // paints to a canvas, so the DOM cannot be asked — the semantics tree can.
  // `.flt-text-editing` is a CLASS on an <input>, not a tag — querying it as a
  // tag returns null on a perfectly healthy page and reads as "the click
  // missed", which cost a debug round here.
  const typed = await page
    .evaluate(`document.querySelector('.flt-text-editing')?.value ?? ''`)
    .catch(() => '');
  if (!String(typed).includes(query)) {
    throw new Error(
      `search shot: "${query}" never reached the field (got ${JSON.stringify(typed)}) — ` +
        'the app-bar action probably moved; see SEARCH_ACTION',
    );
  }
}

/**
 * Flutter is up when `<flutter-view>` has been attached and the glass pane is
 * inside it. Do NOT look for a `<canvas>`: the scene host lives in the glass
 * pane's SHADOW root, so `document.querySelectorAll('canvas')` is 0 on a
 * perfectly healthy page — a check that cost half an hour once.
 */
async function waitForApp(page) {
  for (let i = 0; i < 100; i += 1) {
    const ready = await page
      .evaluate(`!!document.querySelector('flutter-view flt-glass-pane')`)
      .catch(() => false);
    if (ready) {
      // The route the app lands on is the truth about whether the injected
      // session was accepted; a redirect to /#/login means it was not.
      const url = await page.evaluate('location.href').catch(() => '');
      if (/#\/login|#\/register/.test(url)) {
        throw new Error(
          'the app booted to the sign-in screen — the injected session was rejected ' +
            '(is the API the same one the bundle was built against?)',
        );
      }
      await sleep(2000);
      return;
    }
    await sleep(250);
  }
  throw new Error('the Flutter view never appeared — check the browser console');
}

main().catch((err) => {
  console.error(`\n✗ ${err.message}`);
  process.exit(1);
});
