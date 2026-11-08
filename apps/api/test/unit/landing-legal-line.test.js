import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { afterAll, beforeAll, describe, expect, test } from 'vitest';

import { company } from '../../../landing/src/company.js';
import en from '../../../landing/src/enterprise/content.en.js';
import tr from '../../../landing/src/enterprise/content.tr.js';

/// OPH-412 (polish 3, M-1) — the company line in the enterprise footer, and the
/// cloud package names on the Turkish enterprise page.
///
/// A Turkish buyer read "© 2026 BUBIAPSS BILGI TEKNOLOJILERI ARGE LIMITED
/// SIRKETI" as the company misspelling its own name: the brand is BubiApps and
/// the line gave no hint that the capitals are the registered name. The home
/// footer already leads with the brand and labels the registered name (U-81);
/// the enterprise footer now says it the same way. The registered name itself
/// is unchanged: it is reproduced as the trade register spells it, and the
/// LICENSE's required notice is the other copy that must not drift from it.
///
/// The same reader could not say "let's take Business" to his boss: the
/// Turkish page named its packages Starter, Business and Enterprise.

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '../../../..');
const LANDING = join(ROOT, 'apps/landing');

const textOf = (html) =>
  html
    .replace(/<script[\s\S]*?<\/script>/g, ' ')
    .replace(/<style[\s\S]*?<\/style>/g, ' ')
    .replace(/<!--[\s\S]*?-->/g, '')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/\s+/g, ' ');

const ENGLISH_PACKAGE = /\b(Starter|Business|Enterprise)\b/;

describe('the registered name stays exactly what the register says', () => {
  test('company.js and the LICENSE required notice name the same entity', () => {
    const licence = readFileSync(join(ROOT, 'LICENSE'), 'utf8');
    expect(licence).toContain(`Required Notice: Copyright 2026 ${company.legalName}`);
    expect(company.tradingName).toBe('BubiApps');
  });
});

describe('the enterprise footer leads with the brand and labels the registered name', () => {
  test('both languages carry the label', () => {
    expect(en.footer.registeredAs).toBe('Registered name');
    expect(tr.footer.registeredAs).toBe('Ticaret unvanı');
  });

  describe('the rendered page', () => {
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
      test(`${lang}: "© year BubiApps · ${content.footer.registeredAs}: <registered name>"`, async () => {
        const text = textOf((await render('enterprise', lang)).app);
        expect(text).toMatch(
          new RegExp(
            `© \\d{4} ${company.tradingName} · ${content.footer.registeredAs}: ${company.legalName} ·`,
          ),
        );
        // The capitals never stand alone after the copyright sign again.
        expect(text).not.toMatch(new RegExp(`© \\d{4} ${company.legalName}`));
      }, 30_000);
    }

    test('tr: the package table heads are Turkish', async () => {
      const html = (await render('enterprise', 'tr')).app;
      const heads = [...html.matchAll(/<th scope="col"[^>]*>([\s\S]*?)<\/th>/g)].map((m) =>
        textOf(m[1]).trim(),
      );
      for (const name of tr.packages.columns) expect(heads).toContain(name);
      for (const head of heads) expect(head).not.toMatch(ENGLISH_PACKAGE);
    }, 30_000);
  });
});

describe('the Turkish page names its cloud packages in Turkish', () => {
  test('table, deploy option and contact form use Başlangıç, İşletme, Kurumsal', () => {
    expect(tr.packages.columns).toEqual(['Başlangıç', 'İşletme', 'Kurumsal']);
    const cloud = tr.deploy.options.find((o) => o.key === 'cloud');
    const packagePoint = cloud.points.find((p) => /paket/i.test(p));
    expect(packagePoint).toMatch(/Başlangıç, İşletme ya da Kurumsal/);
    expect(packagePoint).not.toMatch(ENGLISH_PACKAGE);
    const options = tr.contact.fields.packageInterest.options;
    for (const name of tr.packages.columns) {
      expect(options.some((o) => o.startsWith(`Bulut — ${name}`))).toBe(true);
    }
  });

  test('the English names appear only where they explain what the app and contract say', () => {
    // The product's own admin screens name the packages Starter, Business and
    // Enterprise; the lede says so once, so a buyer recognises them later.
    expect(tr.packages.lede).toMatch(/Starter, Business ve Enterprise/);
    expect(tr.packages.columns.join(' ')).not.toMatch(ENGLISH_PACKAGE);
    const directory = tr.faq.items.find((i) => /Active Directory/.test(i.q));
    expect(directory.a).toMatch(/Kurumsal pakette/);
    expect(directory.a).not.toMatch(/Enterprise paket/);
  });

  test('the English page keeps the English names', () => {
    expect(en.packages.columns).toEqual(['Starter', 'Business', 'Enterprise']);
  });
});
