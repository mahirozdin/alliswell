import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, test } from 'vitest';

import en from '../../../landing/src/content.js';
import tr from '../../../landing/src/content.tr.js';
import { platformOf, primaryFor } from '../../../landing/src/home/platform.js';
import { proofParts, starsLabel } from '../../../landing/src/home/proof.js';
import { summariseReleases, loadProof } from '../../../landing/scripts/proof.js';
import { STATIC_PAGES } from '../../../landing/scripts/static-pages.js';
import { renderSitemap } from '../../../landing/scripts/sitemap.js';

/// OPH-412 — the homepage's first screen, the terms pages and the real 404.
///
/// The landing has no test runner of its own; its logic is plain JavaScript,
/// read here the way `landing-enquiry.test.js` reads the enquiry module.

const LANDING = join(dirname(fileURLToPath(import.meta.url)), '../../../landing');
const read = (rel) => readFileSync(join(LANDING, rel), 'utf8');

const IPHONE =
  'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1';
const IPAD_DESKTOP_UA =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15';
const ANDROID =
  'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Mobile Safari/537.36';
const WINDOWS =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36';

describe('the hero says the alarm first (owner decision S-3, K5)', () => {
  test('the H1 is the alarm, in both languages', () => {
    expect(en.hero.title).toBe('Reminders that ring through Silent mode.');
    expect(tr.hero.title).toBe('Sessiz modda bile çalan hatırlatıcılar.');
  });

  test('the line under it says self-hosting and Claude or ChatGPT', () => {
    for (const c of [en, tr]) {
      expect(c.hero.sentence).toMatch(/sunucu|server/i);
      expect(c.hero.sentence).toMatch(/Claude/);
      expect(c.hero.sentence).toMatch(/ChatGPT/);
    }
  });
});

describe('the primary button follows the device (K6)', () => {
  test('iPhone, iPad, Android and a desktop each get their own way in', () => {
    expect(platformOf(IPHONE)).toBe('ios');
    // iPadOS asks for the desktop site and says "Macintosh"; the touch points give it away.
    expect(platformOf(IPAD_DESKTOP_UA, 5)).toBe('ios');
    expect(platformOf(IPAD_DESKTOP_UA, 0)).toBe('desktop');
    expect(platformOf(ANDROID)).toBe('android');
    expect(platformOf(WINDOWS)).toBe('desktop');
    expect(platformOf('')).toBe('desktop');
    expect(platformOf(undefined)).toBe('desktop');
  });

  test('a phone gets its store, a desktop the browser, in both languages', () => {
    for (const c of [en, tr]) {
      expect(primaryFor(c.hero.primary, 'ios').href).toMatch(/^https:\/\/apps\.apple\.com\//);
      expect(primaryFor(c.hero.primary, 'android').href).toMatch(/^https:\/\/play\.google\.com\//);
      expect(primaryFor(c.hero.primary, 'desktop').href).toBe('/app/?signup=1');
      expect(primaryFor(c.hero.primary, 'something else')).toEqual(c.hero.primary.desktop);
    }
    expect(en.hero.primary.desktop.label).toBe('Start free in your browser');
    expect(tr.hero.primary.desktop.label).toBe('Tarayıcıda ücretsiz başlayın');
  });

  test('the bar carries the same action as the hero, not a third label', () => {
    for (const c of [en, tr]) expect(c.nav.cta).toEqual(c.hero.primary);
  });
});

describe('the proof line is counted at build time, never typed (K2)', () => {
  const release = (published_at, extra = {}) => ({
    published_at,
    draft: false,
    prerelease: false,
    ...extra,
  });

  test('releases are counted from the API, drafts and pre-releases left out', () => {
    expect(
      summariseReleases([
        release('2026-10-30T10:00:00Z'),
        release('2026-07-26T09:00:00Z'),
        release('2026-08-01T09:00:00Z'),
        release('2026-11-01T09:00:00Z', { draft: true }),
        release('2026-11-02T09:00:00Z', { prerelease: true }),
        release(null),
      ]),
    ).toEqual({ releases: 3, first: '2026-07' });
    expect(summariseReleases([])).toBeNull();
    expect(summariseReleases(undefined)).toBeNull();
  });

  test('with a count, the line says it; the month is written in the page language', () => {
    const proof = { releases: 40, first: '2026-07', stars: 26 };
    expect(proofParts(en.proof, proof, 'en')).toEqual([
      'Source on GitHub',
      '40 releases, the first in July 2026',
      'Free for personal use',
    ]);
    expect(proofParts(tr.proof, proof, 'tr')[1]).toBe('40 sürüm, ilki Temmuz 2026');
  });

  test('without the API the line is the fixed text, with no number in it', () => {
    for (const [c, lang] of [
      [en, 'en'],
      [tr, 'tr'],
    ]) {
      const parts = proofParts(c.proof, null, lang);
      expect(parts).toHaveLength(2);
      expect(parts.join(' ')).not.toMatch(/\d/);
    }
  });

  test('the GitHub button shows stars only past a hundred', () => {
    expect(starsLabel(null, 'en')).toBeNull();
    expect(starsLabel({ stars: 26 }, 'en')).toBeNull();
    expect(starsLabel({ stars: 99 }, 'en')).toBeNull();
    expect(starsLabel({ stars: 1234 }, 'en')).toBe('1,234');
    expect(starsLabel({ stars: 1234 }, 'tr')).toBe('1.234');
  });

  test('a failing or offline API is the fixed text, not a failed build', async () => {
    expect(await loadProof({ env: { AW_PROOF: 'off' } })).toBeNull();
    const broken = async () => {
      throw new Error('offline');
    };
    expect(await loadProof({ env: {}, fetch: broken, cache: null })).toBeNull();
    const refused = async () => ({ ok: false, status: 403, json: async () => ({}) });
    expect(await loadProof({ env: {}, fetch: refused, cache: null })).toBeNull();
  });

  test('a working API gives the count, the first month and the stars', async () => {
    const answers = {
      'https://api.github.com/repos/mahirozdin/alliswell': { stargazers_count: 26 },
      'https://api.github.com/repos/mahirozdin/alliswell/releases?per_page=100&page=1': [
        release('2026-10-30T10:00:00Z'),
        release('2026-07-26T09:00:00Z'),
      ],
    };
    const seen = [];
    const fetch = async (url, init) => {
      seen.push(init?.headers?.authorization ?? null);
      return { ok: true, status: 200, json: async () => answers[url] ?? [] };
    };
    expect(await loadProof({ env: { GITHUB_TOKEN: 't0k' }, fetch, cache: null })).toEqual({
      releases: 2,
      first: '2026-07',
      stars: 26,
    });
    expect(seen.every((h) => h === 'Bearer t0k')).toBe(true);
  });
});

describe('the nav links the source (U-80)', () => {
  test('both languages carry a GitHub button to the repository', () => {
    for (const c of [en, tr]) {
      expect(c.nav.github).toEqual({
        label: 'GitHub',
        href: 'https://github.com/mahirozdin/alliswell',
      });
    }
  });
});

describe('the licence is said plainly (U-17, A-72)', () => {
  test('the FAQ asks "what is the licence", word for word', () => {
    expect(en.faq.items[0]).toEqual({
      q: 'What is the licence?',
      a: 'Source-available, not open source: PolyForm Noncommercial. Personal use and self-hosting are free; running it inside a business, reselling it or offering it as a service needs a commercial licence. Write to info@bubiapps.com.',
    });
    expect(tr.faq.items[0]).toEqual({
      q: 'Lisans ne?',
      a: 'Kaynak kodu erişilebilir, ama açık kaynak değil: PolyForm Noncommercial. Kişisel kullanım ve kendi sunucunuza kurmak ücretsiz; bir şirket içinde çalıştırmak, yeniden satmak ya da hizmet olarak sunmak ticari lisans gerektirir. info@bubiapps.com adresine yazın.',
    });
  });

  test('nothing on the page claims to be open source', () => {
    const claims = (c) =>
      JSON.stringify(c)
        .replace(c.faq.items[0].a, '')
        .match(/open[ -]source|açık kaynak/gi);
    expect(claims(en)).toBeNull();
    expect(claims(tr)).toBeNull();
  });
});

describe('the comparison looks at the apps people move from (K15)', () => {
  test('Todoist, TickTick and Vikunja, with a dash where nothing was checked', () => {
    for (const c of [en, tr]) {
      expect(c.compare.columns).toEqual(['AllisWell', 'Todoist', 'TickTick', 'Vikunja']);
      const cells = new Set(c.compare.rows.flatMap((row) => row.slice(1)));
      for (const cell of cells) expect(Object.keys(c.compare.labels)).toContain(cell);
      expect(cells.has('unknown')).toBe(true);
    }
    // The rows say the same thing in both languages.
    expect(tr.compare.rows.map((r) => r.slice(1))).toEqual(en.compare.rows.map((r) => r.slice(1)));
  });

  test('the cells agree with the README table they come from', () => {
    const row = (label) => en.compare.rows.find((r) => r[0] === label).slice(1);
    expect(row('Runs on your own server')).toEqual(['yes', 'no', 'no', 'yes']);
    expect(row('Two-way Google Calendar sync')).toEqual(['yes', 'unknown', 'unknown', 'no']);
    expect(row('Sharing with other people')).toEqual(['no', 'yes', 'unknown', 'yes']);
  });
});

describe('the footer names the company the way the register does (U-81)', () => {
  test('the trading name leads, the registered name is labelled as such', () => {
    const footer = read('src/home/components/HomeFooter.vue');
    expect(footer).toContain('company.tradingName');
    expect(footer).toContain('footer.registeredAs');
    expect(en.footer.registeredAs).toBe('Registered name');
    expect(tr.footer.registeredAs).toBe('Ticaret unvanı');
  });

  test('the company column links the terms in each language', () => {
    const links = (c) => c.footer.columns.flatMap((col) => col.links.map((l) => l.href));
    expect(links(en)).toContain('/terms');
    expect(links(tr)).toContain('/terms/tr');
  });
});

describe('terms of service exist on the domain (K10)', () => {
  test('/terms and /terms/tr are generated pages with each other as twins', () => {
    const terms = STATIC_PAGES.filter((p) => p.route.startsWith('terms'));
    expect(terms.map((p) => [p.route, p.file, p.lang])).toEqual([
      ['terms', 'docs/TERMS.md', 'en'],
      ['terms/tr', 'docs/TERMS.tr.md', 'tr'],
    ]);
    const sitemap = renderSitemap();
    expect(sitemap).toContain('<loc>https://alliswell.space/terms</loc>');
    expect(sitemap).toContain('hreflang="tr" href="https://alliswell.space/terms/tr"');
  });

  test('the address in the task, /tr/terms, lands on the Turkish terms', () => {
    expect(read('public/.htaccess')).toMatch(
      /^\s*RewriteRule \^tr\/terms\/\?\$ \/terms\/tr \[R=301,L\]$/m,
    );
  });
});

describe('an unknown address is a real 404 (K10)', () => {
  const htaccess = read('public/.htaccess');
  const rules = htaccess
    .split('\n')
    .map((l) => l.trim())
    .filter((l) => l.startsWith('RewriteRule'));

  test('the last rule answers 404 instead of serving the homepage', () => {
    // The soft 404: `/terms`, `/pricing` and `/favicon.ico` all answered 200
    // with the homepage's HTML (landing-audit K10).
    expect(rules).not.toContain('RewriteRule ^ /index.html [L]');
    expect(rules.at(-1)).toBe('RewriteRule ^ - [R=404,L]');
    expect(htaccess).toMatch(/^\s*ErrorDocument 404 \/404\.html$/m);
  });

  test('the app keeps its own fallback, before the 404', () => {
    const app = rules.indexOf('RewriteRule ^app(/.*)?$ /app/index.html [L]');
    expect(app).toBeGreaterThan(-1);
    expect(app).toBeLessThan(rules.length - 1);
  });

  test('the 404 page is in both languages, links home, and is never indexed', () => {
    const page = read('public/404.html');
    expect(page).toContain('<meta name="robots" content="noindex">');
    expect(page).toContain('href="/"');
    expect(page).toContain('href="/tr"');
    expect(page).toMatch(/Page not found/);
    expect(page).toMatch(/Sayfa bulunamadı/);
  });
});
