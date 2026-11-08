import { existsSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { afterAll, beforeAll, describe, expect, test } from 'vitest';

import en from '../../../landing/src/enterprise/content.en.js';
import tr from '../../../landing/src/enterprise/content.tr.js';
import { SECTIONS } from '../../../landing/src/enterprise/page.js';
import homeEn from '../../../landing/src/content.js';
import homeTr from '../../../landing/src/content.tr.js';
import { APP_SIGNUP_URL } from '../../../landing/src/site.js';
import { SSR_PAGES, VUE_PAGES } from '../../../landing/scripts/routes.js';

/// OPH-413 — the way into /app, and the enterprise page rendered on the server.
///
/// K3: /app showed a white page until 5 MB of engine had loaded, and the
/// "Start free" button opened a sign-in form. K8: the enterprise page shipped
/// an empty container, so a crawler, a link preview or a reader without
/// scripts saw one heading. K9 / E-15: it was 26 000 px long, its sections
/// stayed invisible until an observer saw them (a full-page capture, print and
/// reader mode showed blank space), and the English page showed Turkish
/// sample records.

const LANDING = join(dirname(fileURLToPath(import.meta.url)), '../../../landing');
const APP_WEB = join(dirname(fileURLToPath(import.meta.url)), '../../../app/web');
const read = (rel) => readFileSync(join(LANDING, rel), 'utf8');

/** Turkish-only letters: an English page that shows one is showing Turkish words. */
const TURKISH = /[ğĞıİşŞçÇöÖüÜ]/;
/** The language switch and the link to the Turkish deck name Turkish on purpose. */
const ALLOWED_TURKISH = ['Türkçe'];

const textOf = (html) =>
  html
    .replace(/<script[\s\S]*?<\/script>/g, ' ')
    .replace(/<style[\s\S]*?<\/style>/g, ' ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&#39;/g, "'")
    .replace(/&quot;/g, '"')
    .replace(/&amp;/g, '&')
    .replace(/\s+/g, ' ');

/** The heading each rendered section carries, in page order. */
const sectionHeadings = (content) =>
  SECTIONS.filter((s) => content[s.key])
    .map((s) => content[s.key].title ?? content[s.key].heading)
    .filter(Boolean);

describe('the enterprise page tells one story (K9)', () => {
  test('problem, solution, proof, pilot, then the demo request', () => {
    const keys = SECTIONS.map((s) => s.key);
    const at = (k) => {
      const i = keys.indexOf(k);
      expect(i, `${k} is on the page`).toBeGreaterThanOrEqual(0);
      return i;
    };
    expect(at('hero')).toBe(0);
    expect(at('problem')).toBeLessThan(at('journey'));
    expect(at('journey')).toBeLessThan(at('tour'));
    expect(at('tour')).toBeLessThan(at('proof'));
    expect(at('proof')).toBeLessThan(at('pilot'));
    expect(at('pilot')).toBeLessThan(at('contact'));
    expect(keys.at(-1)).toBe('contact');
  });

  test('the long run of annotated sections is gone: one tabbed tour shows the screens', () => {
    expect(SECTIONS.length).toBeLessThanOrEqual(12);
    for (const gone of [
      'AnnotatedShots',
      'StatusFlow',
      'ChannelList',
      'GroupHeading',
      'FeatureSection',
    ]) {
      expect(
        SECTIONS.some((s) => s.component === gone),
        gone,
      ).toBe(false);
    }
    expect(SECTIONS.find((s) => s.key === 'tour')?.component).toBe('ShotTabs');
    for (const c of [en, tr]) expect(c.tour.tabs.length).toBeGreaterThanOrEqual(4);
  });

  test('both languages carry the same sections', () => {
    for (const s of SECTIONS) {
      expect(Boolean(en[s.key]), `en ${s.key}`).toBe(true);
      expect(Boolean(tr[s.key]), `tr ${s.key}`).toBe(true);
    }
  });

  test('every nav and footer anchor lands on a section that exists', () => {
    const anchors = new Set(SECTIONS.map((s) => s.anchor).filter(Boolean));
    for (const c of [en, tr]) {
      const links = [...c.nav.links, c.nav.cta, ...c.footer.columns[0].links];
      for (const l of links) {
        if (!l.href.startsWith('#')) continue;
        expect(anchors.has(l.href.slice(1)), `${c.lang} ${l.href}`).toBe(true);
      }
    }
  });
});

describe('the English page shows English sample data (K9)', () => {
  test('no English screen is a capture of the Turkish sample factory', () => {
    const shots = JSON.stringify(en).match(/\/shots\/[^"]+/g) ?? [];
    expect(shots.length).toBeGreaterThan(0);
    for (const s of shots) {
      // The English deck's cover is an English slide, not a screen of records.
      if (s.includes('deck-cover-en')) continue;
      expect(s, s).not.toMatch(/\/shots\/sales\//);
      expect(s).toMatch(/-en\.jpg$/);
    }
  });

  test('no English sentence names a Turkish record', () => {
    const strings = [];
    const walk = (v) => {
      if (typeof v === 'string') strings.push(v);
      else if (Array.isArray(v)) v.forEach(walk);
      else if (v && typeof v === 'object') Object.values(v).forEach(walk);
    };
    walk(en);
    for (const s of strings) {
      const rest = ALLOWED_TURKISH.reduce((acc, w) => acc.replaceAll(w, ''), s);
      expect(rest, s).not.toMatch(TURKISH);
    }
    expect(en.hero.note).not.toMatch(/Turkish/);
  });
});

describe('a section is never invisible until something watches it (E-15)', () => {
  test('no scroll-reveal state is left in the stylesheet or the components', () => {
    expect(read('src/style.css')).not.toMatch(/aw-reveal/);
    expect(existsSync(join(LANDING, 'src/composables/useReveal.js'))).toBe(false);
    for (const f of ['main.en.js', 'main.tr.js'])
      expect(read(`src/enterprise/${f}`)).not.toMatch(/reveal/);
  });
});

describe('the enterprise pages are rendered on the server (K8)', () => {
  test('routes.js renders and hydrates all four Vue pages', () => {
    expect(SSR_PAGES.map((p) => p.route).sort()).toEqual(['', 'enterprise', 'enterprise/tr', 'tr']);
    for (const p of VUE_PAGES) expect(['home', 'enterprise']).toContain(p.page);
  });

  test('the entry HTML carries the two SSR markers and hydrates', () => {
    for (const [entry, main] of [
      ['enterprise/index.html', 'src/enterprise/main.en.js'],
      ['enterprise/tr/index.html', 'src/enterprise/main.tr.js'],
    ]) {
      const html = read(entry);
      expect(html.split('<!--ssr-outlet-->').length - 1).toBe(1);
      expect(html.split('<!--ssr-head-->').length - 1).toBe(1);
      expect(read(main)).toMatch(/createSSRApp/);
    }
  });

  describe('the rendered HTML', () => {
    /** @type {import('vite').ViteDevServer} */
    let server;
    let render;

    beforeAll(async () => {
      const { createServer } = await import('vite');
      const vue = (await import('@vitejs/plugin-vue')).default;
      server = await createServer({
        root: LANDING,
        configFile: false,
        logLevel: 'silent',
        appType: 'custom',
        plugins: [vue()],
        server: { middlewareMode: true, hmr: false, ws: false },
        optimizeDeps: { noDiscovery: true, include: [] },
      });
      ({ render } = await server.ssrLoadModule('/src/entry-server.js'));
    }, 60_000);

    afterAll(async () => {
      await server?.close();
    });

    for (const [lang, content] of [
      ['en', en],
      ['tr', tr],
    ]) {
      test(`${lang}: every section's heading is in the HTML, in order, under one h1`, async () => {
        const out = await render('enterprise', lang);
        const html = out.app;
        expect(html.match(/<h1[\s>]/g)?.length).toBe(1);
        expect(out.title).toBe(content.hero.title);
        const text = textOf(html);
        let from = 0;
        for (const heading of sectionHeadings(content)) {
          const at = text.indexOf(heading, from);
          expect(at, `"${heading}" in order`).toBeGreaterThanOrEqual(0);
          from = at + heading.length;
        }
        // The tour's captions are text, not pictures: all of them are in the HTML.
        for (const tab of content.tour.tabs) expect(text).toContain(tab.caption);
        expect(out.sections).toEqual(sectionHeadings(content));
        expect(html).not.toMatch(/aw-reveal/);
      }, 30_000);
    }

    test('en: the rendered page shows no Turkish words', async () => {
      const text = textOf((await render('enterprise', 'en')).app);
      const rest = ALLOWED_TURKISH.reduce((acc, w) => acc.replaceAll(w, ''), text);
      const hit = rest.match(TURKISH);
      expect(hit ? rest.slice(Math.max(0, hit.index - 40), hit.index + 40) : null).toBeNull();
    }, 30_000);

    test('the homepage still renders through the same entry', async () => {
      const out = await render('home', 'en');
      expect(out.title).toBe(homeEn.hero.title);
      expect(out.app).toContain(homeEn.hero.title);
    }, 30_000);
  });
});

describe('the way into /app (K3)', () => {
  test('"Start free" opens the app in sign-up mode, in both languages', () => {
    expect(APP_SIGNUP_URL).toBe('/app/?signup=1');
    for (const c of [homeEn, homeTr]) expect(c.hero.primary.desktop.href).toBe(APP_SIGNUP_URL);
  });

  test('/app paints a branded opening screen before the engine loads, and removes it on the first frame', () => {
    const html = readFileSync(join(APP_WEB, 'index.html'), 'utf8');
    const body = html.slice(html.indexOf('<body'));
    // In the body, before the bootstrap script: it paints while that loads.
    const splash = body.indexOf('id="aw-splash"');
    expect(splash).toBeGreaterThan(-1);
    expect(splash).toBeLessThan(body.indexOf('flutter_bootstrap.js'));
    expect(body).toMatch(/Opening AllisWell/);
    expect(body).toMatch(/role="progressbar"|role="status"/);
    // Dark variant, and no motion for a reader who asked for none.
    expect(html).toMatch(/prefers-color-scheme:\s*dark/);
    expect(html).toMatch(/prefers-reduced-motion:\s*reduce/);
    // Gone on Flutter's first frame — the engine dispatches this on window.
    expect(html).toMatch(/flutter-first-frame/);
  });
});
