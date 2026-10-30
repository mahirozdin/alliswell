#!/usr/bin/env node
/**
 * `npm run check:home` — the built homepage is what ADR-0061 says it is.
 * Reads `dist/` after `npm run landing:build`.
 *
 * 1. Rendered on the server: exactly one <h1> per language, and it is the
 *    hero title from the content module (the old page shipped an empty
 *    container a crawler could not read).
 * 2. The MCP address and the connector guide are in the HTML itself, for the
 *    agents and crawlers that read this page without running it (OPH-364).
 * 3. Videos never autoplay and never preload; every <img> has alt, width and
 *    height (no layout shift); every /media, /shots and /fonts reference in
 *    the HTML is a file in dist.
 * 4. The homepage links the enterprise page and the API reference itself
 *    (the bundle-wide greps in ci.yml pass on the enterprise chunk alone).
 * 5. The two stylesheets stay apart: the homepage's CSS carries none of the
 *    enterprise page's `--aw-` tokens and the enterprise page's CSS none of
 *    the Dusk ones, so neither page restyles the other.
 * 6. The Floor in the homepage's own CSS source: no colour literal outside
 *    tokens.css, no `transition: all`, no uppercase, and overflow-x: clip,
 *    :focus-visible and a reduced-motion block present.
 */
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { SSR_PAGES, distPath } from './routes.js';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const dist = path.join(root, 'dist');
const problems = [];
const fail = (m) => problems.push(m);
const MCP_URL = 'https://api.alliswell.space/mcp';
const unescape = (s) => s.replace(/&#39;/g, "'").replace(/&quot;/g, '"').replace(/&amp;/g, '&');

if (!existsSync(dist)) {
  console.error('✗ home: no dist/ — run `npm run landing:build` first');
  process.exit(1);
}

const cssOf = (html) =>
  [...html.matchAll(/<link[^>]+rel="stylesheet"[^>]+href="([^"]+)"/g)]
    .map((m) => m[1])
    .filter((href) => href.startsWith('/assets/'))
    .map((href) => readFileSync(path.join(dist, href), 'utf8'))
    .join('\n');

for (const page of SSR_PAGES) {
  const route = `/${page.route}`;
  const html = readFileSync(path.join(dist, distPath(page.route)), 'utf8');
  const content = (await import(path.join(root, page.lang === 'tr' ? 'src/content.tr.js' : 'src/content.js'))).default;

  // ── 1 ──
  const h1s = [...html.matchAll(/<h1[^>]*>([\s\S]*?)<\/h1>/g)];
  if (h1s.length !== 1) fail(`${route}: ${h1s.length} <h1> elements, expected one`);
  else if (unescape(h1s[0][1].replace(/<[^>]+>/g, '').trim()) !== content.hero.title) {
    fail(`${route}: the <h1> is not the hero title from the content module`);
  }
  if (html.includes('<!--ssr-outlet-->')) fail(`${route}: the SSR outlet marker survived; prerender did not run`);

  // ── 2 ──
  if (!html.includes(MCP_URL)) fail(`${route}: the MCP address ${MCP_URL} is not in the HTML`);
  if (!html.includes('href="/docs/mcp"')) fail(`${route}: no link to /docs/mcp in the HTML`);

  // ── 3 ──
  for (const [tag] of html.matchAll(/<video\b[^>]*>/g)) {
    if (/\sautoplay\b/.test(tag)) fail(`${route}: a <video> autoplays (${tag.slice(0, 80)}…)`);
    if (!/preload="none"/.test(tag)) fail(`${route}: a <video> without preload="none"`);
    if (!/\scontrols\b/.test(tag) && !(/\smuted\b/.test(tag) && /\splaysinline\b/.test(tag))) {
      fail(`${route}: a loop <video> without muted and playsinline`);
    }
  }
  for (const [tag] of html.matchAll(/<img\b[^>]*>/g)) {
    for (const attr of ['alt', 'width', 'height']) {
      if (!new RegExp(`\\s${attr}=`).test(tag)) fail(`${route}: an <img> without ${attr} (${tag.slice(0, 90)}…)`);
    }
  }
  for (const [, ref] of html.matchAll(/(?:src|href|poster|srcset|imagesrcset)="([^"]+)"/g)) {
    for (const part of ref.split(',')) {
      const url = part.trim().split(/\s+/)[0];
      if (!/^\/(media|shots|fonts)\//.test(url)) continue;
      if (!existsSync(path.join(dist, url))) fail(`${route}: ${url} is referenced but not in dist`);
    }
  }

  // ── 4 ──
  const enterprise = page.lang === 'tr' ? '/enterprise/tr' : '/enterprise';
  if (!html.includes(`href="${enterprise}"`)) fail(`${route}: no link to ${enterprise}`);
  if (!html.includes('href="/docs/api"')) fail(`${route}: no link to /docs/api`);

  // ── 5 ──
  const css = cssOf(html);
  if (!css) fail(`${route}: no stylesheet linked`);
  if (/--aw-[a-z]/.test(css)) fail(`${route}: the homepage CSS carries the enterprise page's --aw- tokens`);
}

for (const entry of ['enterprise/index.html', 'enterprise/tr/index.html']) {
  const css = cssOf(readFileSync(path.join(dist, entry), 'utf8'));
  if (/Wix Madefor|--color-day-ink/.test(css)) fail(`/${entry}: the enterprise CSS carries the Dusk homepage's tokens or faces`);
}

// ── 6 ──
const source = [];
const walk = (dir) => {
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, e.name);
    if (e.isDirectory()) walk(full);
    else if (/\.(css|vue)$/.test(e.name)) source.push(full);
  }
};
walk(path.join(root, 'src/home'));
const COLOUR = /#[0-9a-f]{3,8}\b|\b(rgb|rgba|hsl|hsla|oklch|oklab)\(/i;
let homeCss = '';
for (const file of source) {
  const text = readFileSync(file, 'utf8');
  const css = file.endsWith('.vue') ? (text.match(/<style[^>]*>([\s\S]*?)<\/style>/)?.[1] ?? '') : text;
  homeCss += css;
  if (file.endsWith('tokens.css')) continue;
  css.split('\n').forEach((line, i) => {
    if (/^\s*(\/\*|\*)/.test(line)) return;
    if (COLOUR.test(line)) fail(`${path.relative(root, file)}:${i + 1}: a colour literal outside tokens.css (${line.trim().slice(0, 60)})`);
    if (/transition:\s*all\b/.test(line)) fail(`${path.relative(root, file)}:${i + 1}: transition: all`);
    if (/text-transform:\s*uppercase/.test(line)) fail(`${path.relative(root, file)}:${i + 1}: uppercase text`);
  });
}
for (const [what, re] of [
  ['overflow-x: clip', /overflow-x:\s*clip/],
  [':focus-visible', /:focus-visible/],
  ['a prefers-reduced-motion block', /prefers-reduced-motion:\s*reduce/],
]) {
  if (!re.test(homeCss)) fail(`src/home/styles: ${what} is missing`);
}

if (problems.length) {
  for (const p of problems) console.error(`::error::${p}`);
  console.error(`\n✗ home: ${problems.length} problem(s).`);
  process.exit(1);
}
console.log(`✓ home: ${SSR_PAGES.length} pages rendered on the server, media whole, stylesheets apart, the Floor in the CSS`);
