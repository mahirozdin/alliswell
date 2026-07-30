#!/usr/bin/env node
/**
 * store.mjs — turns the raw device captures in `screenshots/` into the exact
 * canvases the App Store and Google Play accept, plus the feature graphic, the
 * store icons and the social cover.
 *
 * The compositor is headless Chrome rendering HTML: no image library to install,
 * real typography, and the caption band is CSS rather than something baked into
 * a PNG that has to be redone per language. Every output is written at its
 * store-required pixel size, verified after the fact.
 *
 * Prerequisite: the device captures exist (see docs/SCREENSHOTS.md §2–3).
 *
 *   node scripts/screenshots/store.mjs
 *   node scripts/screenshots/store.mjs --only feature-graphic,icons
 */
import { spawn } from 'node:child_process';
import { mkdir, writeFile, rm, readFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, '../..');
const SHOTS = path.join(repo, 'screenshots');
const OUT = path.join(repo, 'store');

const args = process.argv.slice(2);
const flag = (n, d = null) => {
  const i = args.indexOf(`--${n}`);
  return i >= 0 && args[i + 1] && !args[i + 1].startsWith('--') ? args[i + 1] : d;
};
const ONLY = flag('only')?.split(',').map((s) => s.trim());
const PORT = Number(flag('port', '9223'));

const CHROME =
  flag('chrome') ??
  [
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    '/Applications/Chromium.app/Contents/MacOS/Chromium',
    '/usr/bin/google-chrome',
    '/usr/bin/chromium',
  ].find((p) => existsSync(p));

// ── What the stores actually require ────────────────────────────────────────
//
// Apple: 6.9" iPhone 1290×2796 or 1320×2868 (required); 13" iPad 2064×2752 or
// 2048×2732; app icon 1024×1024 with NO alpha and NO rounded corners.
// Google Play: phone screenshots 1080×1920 and up, 2–8 of them; feature graphic
// exactly 1024×500 with no alpha; app icon exactly 512×512, 32-bit with alpha.

/** Caption + source capture for each store slide, in the order they appear. */
const SLIDES = [
  {
    src: 'ios/01-home.png',
    android: 'android/01-home.png',
    title: 'Your whole day, in one place',
    sub: 'Overdue, today, this week and the month ahead',
  },
  {
    src: 'ios/02-board.png',
    android: 'android/03-board.png',
    title: 'Or the same day as a board',
    sub: 'Columns you name, hide and reorder',
  },
  {
    src: 'ios/07-task-detail-repeat.png',
    android: 'android/09-alarm-ring.png',
    title: 'Repeats that never skip a month',
    sub: 'Ask for the 31st — February answers with the 28th',
    androidTitle: 'Reminders that actually ring',
    androidSub: 'Through Silent mode, until you acknowledge',
  },
  {
    src: 'ios/08-repeat-dialog.png',
    android: 'android/11-alarm-permission.png',
    title: 'See the next five days first',
    sub: 'Before you commit to a schedule',
    androidTitle: 'Built on real alarms',
    androidSub: 'Not a louder notification',
  },
  {
    src: 'ios/03-projects.png',
    android: 'android/04-projects.png',
    title: 'Projects, tags and priorities',
    sub: 'Colour-coded, favourited, archivable',
  },
  {
    src: 'ios/04-notes.png',
    android: 'android/05-notes.png',
    title: 'Notes that belong to the work',
    sub: 'Rich text, pinned, linked to a project',
  },
  {
    src: 'ios/05-files.png',
    android: 'android/06-files.png',
    title: 'Every file, one place',
    sub: 'Folders, attachments, your own storage',
  },
  {
    src: 'ios/10-home-dark.png',
    android: 'android/10-home-dark.png',
    title: 'Light and dark, both first-class',
    sub: 'Contrast-checked on every change',
  },
];

/** Output canvases. `deviceHeightPct` tunes how much room the caption takes. */
const CANVASES = [
  { key: 'ios-6.9', dir: 'ios/iphone-6.9', width: 1320, height: 2868, source: 'src' },
  { key: 'ios-6.5', dir: 'ios/iphone-6.5', width: 1242, height: 2688, source: 'src' },
  { key: 'android-phone', dir: 'android/phone', width: 1344, height: 2992, source: 'android' },
];

const BRAND = {
  bgLight: 'linear-gradient(165deg, #E9F2FF 0%, #EEF0FF 45%, #F1EBFF 100%)',
  blobs: `radial-gradient(60% 40% at 8% 4%, rgba(61,125,255,.34), transparent 62%),
          radial-gradient(55% 38% at 92% 10%, rgba(142,92,255,.30), transparent 60%),
          radial-gradient(60% 40% at 50% 96%, rgba(0,199,176,.24), transparent 62%)`,
  text: '#0F1B2E',
  dim: '#44536F',
  font: `-apple-system, BlinkMacSystemFont, 'SF Pro Display', 'Segoe UI', Roboto, sans-serif`,
};

// ── CDP plumbing (same shape as web.mjs) ────────────────────────────────────

class Cdp {
  constructor(ws) {
    this.ws = ws;
    this.id = 0;
    this.pending = new Map();
    ws.addEventListener('message', (ev) => {
      const msg = JSON.parse(ev.data);
      const w = this.pending.get(msg.id);
      if (w) {
        this.pending.delete(msg.id);
        msg.error ? w.reject(new Error(msg.error.message)) : w.resolve(msg.result);
      }
    });
  }
  static async connect(url) {
    const ws = new WebSocket(url);
    await new Promise((res, rej) => {
      ws.addEventListener('open', res, { once: true });
      ws.addEventListener('error', () => rej(new Error(`cannot reach ${url}`)), { once: true });
    });
    return new Cdp(ws);
  }
  send(method, params = {}) {
    const id = ++this.id;
    this.ws.send(JSON.stringify({ id, method, params }));
    return new Promise((res, rej) => this.pending.set(id, { resolve: res, reject: rej }));
  }
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function waitJson(url, tries = 60) {
  for (let i = 0; i < tries; i += 1) {
    try {
      const r = await fetch(url);
      if (r.ok) return r.json();
    } catch {
      /* not up */
    }
    await sleep(250);
  }
  throw new Error(`timed out waiting for ${url}`);
}

/** Reads a PNG off disk as a data: URI — the page never touches the filesystem. */
async function dataUri(rel) {
  const file = path.join(SHOTS, rel);
  if (!existsSync(file)) return null;
  return `data:image/png;base64,${(await readFile(file)).toString('base64')}`;
}

// ── The pages ───────────────────────────────────────────────────────────────

function slidePage({ width, height, image, title, sub }) {
  // Device shell sized as a share of the canvas so one template serves every
  // size; the capture keeps its own aspect ratio inside it.
  return `<!doctype html><html><head><meta charset="utf-8"><style>
    *{box-sizing:border-box;margin:0;padding:0}
    html,body{width:${width}px;height:${height}px;overflow:hidden}
    body{font-family:${BRAND.font};background:${BRAND.bgLight};position:relative;
         display:flex;flex-direction:column;align-items:center}
    body::before{content:'';position:absolute;inset:0;background:${BRAND.blobs}}
    .cap{position:relative;z-index:1;text-align:center;padding:${height * 0.052}px ${width * 0.075}px 0}
    h1{font-size:${Math.round(width * 0.062)}px;line-height:1.12;letter-spacing:-.028em;
       color:${BRAND.text};font-weight:700;text-wrap:balance}
    p{margin-top:${Math.round(height * 0.013)}px;font-size:${Math.round(width * 0.034)}px;
      line-height:1.35;color:${BRAND.dim};font-weight:500;text-wrap:balance}
    .device{position:relative;z-index:1;margin-top:${Math.round(height * 0.042)}px;
      width:${Math.round(width * 0.78)}px;border-radius:${Math.round(width * 0.062)}px;
      border:${Math.round(width * 0.008)}px solid rgba(15,27,46,.86);overflow:hidden;
      box-shadow:0 ${Math.round(height * 0.02)}px ${Math.round(height * 0.045)}px -${Math.round(height * 0.012)}px rgba(32,58,102,.42)}
    .device img{display:block;width:100%}
  </style></head><body>
    <div class="cap"><h1>${title}</h1><p>${sub}</p></div>
    <div class="device"><img src="${image}"></div>
  </body></html>`;
}

function featureGraphicPage(mark) {
  // Play's feature graphic is 1024×500 and gets cropped on some surfaces —
  // nothing load-bearing goes near the edges.
  return `<!doctype html><html><head><meta charset="utf-8"><style>
    *{box-sizing:border-box;margin:0;padding:0}
    html,body{width:1024px;height:500px;overflow:hidden}
    body{font-family:${BRAND.font};background:linear-gradient(120deg,#0B1233 0%,#131C4A 52%,#241A5C 100%);
         position:relative;display:flex;align-items:center;padding:0 64px;color:#fff}
    body::before{content:'';position:absolute;inset:0;
      background:radial-gradient(46% 90% at 12% 20%, rgba(61,125,255,.55), transparent 62%),
                 radial-gradient(44% 92% at 84% 82%, rgba(139,92,246,.5), transparent 60%),
                 radial-gradient(38% 70% at 62% 6%, rgba(34,201,180,.34), transparent 64%)}
    .l{position:relative;z-index:1;max-width:620px}
    .brand{display:flex;align-items:center;gap:14px;margin-bottom:20px}
    .brand span{font-size:30px;font-weight:700;letter-spacing:-.02em}
    h1{font-size:44px;line-height:1.1;letter-spacing:-.03em;font-weight:700}
    p{margin-top:14px;font-size:19px;line-height:1.45;color:rgba(234,240,253,.82)}
    ul{display:flex;gap:10px;margin-top:24px;list-style:none;flex-wrap:wrap}
    li{padding:7px 15px;border-radius:999px;border:1px solid rgba(255,255,255,.24);
       background:rgba(255,255,255,.09);font-size:14px;font-weight:600}
    .r{position:absolute;right:-30px;top:50%;translate:0 -50%;z-index:1;opacity:.95}
  </style></head><body>
    <div class="l">
      <div class="brand">${mark}<span>AllisWell</span></div>
      <h1>Tasks, reminders &amp; notes — that you own</h1>
      <p>Alarms that ring through Silent mode. Two-way calendar sync. Open source, self-hosted, free.</p>
      <ul><li>Offline-first</li><li>6 platforms</li><li>No ads · no tracking</li><li>AGPL-3.0</li></ul>
    </div>
    <div class="r">${mark.replace('width="44" height="44"', 'width="300" height="300"')}</div>
  </body></html>`;
}

function iconPage(size, mark, { rounded }) {
  // Apple's 1024 icon must be square with no transparency and no pre-applied
  // corner radius (iOS masks it); Play's 512 keeps alpha and its own rounding.
  return `<!doctype html><html><head><meta charset="utf-8"><style>
    *{margin:0;padding:0}
    html,body{width:${size}px;height:${size}px;overflow:hidden;background:transparent}
    .t{width:${size}px;height:${size}px;display:grid;place-items:center;
       border-radius:${rounded ? Math.round(size * 0.2237) : 0}px;
       background:linear-gradient(135deg,#2563EB 0%,#6D3DEB 100%)}
    svg{width:${Math.round(size * 0.58)}px;height:${Math.round(size * 0.58)}px}
  </style></head><body><div class="t">
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <path d="M14 33.5 26.5 46 50 18" fill="none" stroke="#fff" stroke-width="7.5"
            stroke-linecap="round" stroke-linejoin="round"/>
    </svg>
  </div></body></html>`;
}

function ogPage(mark, hero) {
  return `<!doctype html><html><head><meta charset="utf-8"><style>
    *{box-sizing:border-box;margin:0;padding:0}
    html,body{width:1200px;height:630px;overflow:hidden}
    body{font-family:${BRAND.font};background:${BRAND.bgLight};position:relative;
         padding:60px 64px;display:flex;flex-direction:column}
    body::before{content:'';position:absolute;inset:0;background:${BRAND.blobs}}
    .top{position:relative;z-index:1}
    .brand{display:flex;align-items:center;gap:12px;margin-bottom:18px}
    .brand span{font-size:26px;font-weight:700;color:${BRAND.text};letter-spacing:-.02em}
    h1{font-size:52px;line-height:1.08;letter-spacing:-.032em;color:${BRAND.text};max-width:18ch}
    p{margin-top:14px;font-size:21px;color:${BRAND.dim};max-width:52ch}
    .shot{position:absolute;right:-90px;bottom:-140px;width:720px;z-index:1;
      border-radius:20px;overflow:hidden;border:1px solid rgba(15,27,46,.12);
      box-shadow:0 40px 80px -30px rgba(32,58,102,.45);rotate:-4deg}
    .shot img{display:block;width:100%}
  </style></head><body>
    <div class="top">
      <div class="brand">${mark}<span>AllisWell</span></div>
      <h1>Your whole day, in an app you actually own</h1>
      <p>Open-source tasks, notes and alarm-grade reminders · alliswell.space</p>
    </div>
    ${hero ? `<div class="shot"><img src="${hero}"></div>` : ''}
  </body></html>`;
}

const MARK = `<svg width="44" height="44" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
  <defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0%" stop-color="#2563EB"/><stop offset="100%" stop-color="#6D3DEB"/>
  </linearGradient></defs>
  <rect width="64" height="64" rx="16" fill="url(#g)"/>
  <path d="M18 33.5 27.5 43 46 22" fill="none" stroke="#fff" stroke-width="6.5"
        stroke-linecap="round" stroke-linejoin="round"/></svg>`;

// ── Runner ──────────────────────────────────────────────────────────────────

async function main() {
  if (!CHROME) throw new Error('no Chrome/Chromium found — pass --chrome /path/to/binary');
  if (!existsSync(SHOTS)) throw new Error(`no captures at ${SHOTS} — see docs/SCREENSHOTS.md`);

  const profile = path.join(process.env.TMPDIR ?? '/tmp', `alliswell-store-${process.pid}`);
  const chrome = spawn(
    CHROME,
    [
      '--headless=new',
      `--remote-debugging-port=${PORT}`,
      `--user-data-dir=${profile}`,
      '--hide-scrollbars',
      '--no-first-run',
      '--no-default-browser-check',
      '--force-color-profile=srgb',
      'about:blank',
    ],
    { stdio: 'ignore' },
  );

  let page;
  try {
    await waitJson(`http://127.0.0.1:${PORT}/json/version`);
    const targets = await waitJson(`http://127.0.0.1:${PORT}/json/list`);
    const target = targets.find((t) => t.type === 'page');
    page = await Cdp.connect(target.webSocketDebuggerUrl);
    await page.send('Page.enable');

    /** Render an HTML string at an exact size and write the PNG. */
    const shoot = async (html, { width, height, file, transparent = false }) => {
      await page.send('Emulation.setDeviceMetricsOverride', {
        width,
        height,
        deviceScaleFactor: 1,
        mobile: false,
      });
      if (transparent) {
        await page.send('Emulation.setDefaultBackgroundColorOverride', {
          color: { r: 0, g: 0, b: 0, a: 0 },
        });
      } else {
        await page.send('Emulation.setDefaultBackgroundColorOverride');
      }
      // `Page.setDocumentContent`, not a data: URL. A slide embeds a full
      // device capture as base64 — several megabytes — and navigating to a
      // data: URL that long fails with "Not attached to an active page" once
      // the navigation is refused. Setting the document's content has no
      // length limit and never leaves the frame.
      const { frameTree } = await page.send('Page.getFrameTree');
      await page.send('Page.setDocumentContent', { frameId: frameTree.frame.id, html });
      await sleep(500);
      const { data } = await page.send('Page.captureScreenshot', {
        format: 'png',
        captureBeyondViewport: false,
      });
      await mkdir(path.dirname(file), { recursive: true });
      await writeFile(file, Buffer.from(data, 'base64'));
      console.log(`✓ ${path.relative(repo, file)}  (${width}×${height})`);
    };

    const want = (name) => !ONLY || ONLY.includes(name);

    // Store slides
    for (const canvas of CANVASES) {
      if (!want(canvas.key)) continue;
      let n = 0;
      for (const slide of SLIDES) {
        const rel = slide[canvas.source];
        const image = rel ? await dataUri(rel) : null;
        if (!image) {
          console.log(`· ${canvas.key}: skipped “${slide.title}” — no ${rel}`);
          continue;
        }
        n += 1;
        await shoot(
          slidePage({
            width: canvas.width,
            height: canvas.height,
            image,
            // A slide's Android capture is sometimes a different screen from
            // its iOS one, so the caption follows the image, not the row.
            title: (canvas.source === 'android' && slide.androidTitle) || slide.title,
            sub: (canvas.source === 'android' && slide.androidSub) || slide.sub,
          }),
          {
            width: canvas.width,
            height: canvas.height,
            file: path.join(OUT, canvas.dir, `${String(n).padStart(2, '0')}.png`),
          },
        );
        if (n >= 8) break; // Play accepts at most 8; Apple 10 — 8 satisfies both
      }
    }

    if (want('feature-graphic')) {
      await shoot(featureGraphicPage(MARK), {
        width: 1024,
        height: 500,
        file: path.join(OUT, 'android', 'feature-graphic.png'),
      });
    }

    if (want('icons')) {
      await shoot(iconPage(1024, MARK, { rounded: false }), {
        width: 1024,
        height: 1024,
        file: path.join(OUT, 'icons', 'app-store-1024.png'),
      });
      await shoot(iconPage(512, MARK, { rounded: true }), {
        width: 512,
        height: 512,
        file: path.join(OUT, 'icons', 'play-512.png'),
        transparent: true,
      });
    }

    if (want('og')) {
      await shoot(ogPage(MARK, await dataUri('web/home-light.png')), {
        width: 1200,
        height: 630,
        file: path.join(repo, 'apps', 'landing', 'public', 'og-cover.png'),
      });
    }
  } finally {
    try {
      page?.ws.close();
    } catch {
      /* already gone */
    }
    chrome.kill();
    await rm(profile, { recursive: true, force: true }).catch(() => {});
  }
}

main().catch((err) => {
  console.error(`\n✗ ${err.message}`);
  process.exit(1);
});
