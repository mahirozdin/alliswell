#!/usr/bin/env node
/**
 * `npm run check:media` — the homepage's promoted media are whole (ADR-0061).
 *
 * The content modules name media by key; `src/home/media.json` (written by
 * `npm run media:promote`) maps each key to files under `public/media/`.
 * `.htaccess` answers a missing file with index.html and a 200, so a broken
 * reference passes every HTTP check and shows an empty frame. This reads the
 * files themselves:
 *
 *   1. every `media` key in both content modules is in the manifest, and a
 *      loop or film the page plays has its MP4;
 *   2. every file the manifest names exists, and the hash in its name is the
 *      sha256 of its bytes (the immutable cache depends on it);
 *   3. no file in public/media is unnamed by the manifest;
 *   4. sizes stay inside the budgets in media-budgets.js, fonts included;
 *   5. every MP4 is H.264 with its index before its data (faststart), loops
 *      carry no sound track and the film does;
 *   6. the photograph carries a complete credit.
 *
 * Runs inside `npm run build` as well as CI: deploy.yml builds without the CI
 * checks, so a broken manifest has to fail the build itself.
 */
import { createHash } from 'node:crypto';
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { BUDGETS } from './media-budgets.js';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const pub = path.join(root, 'public');
const manifest = JSON.parse(readFileSync(path.join(root, 'src/home/media.json'), 'utf8'));
const problems = [];
const fail = (m) => problems.push(m);
const kb = (n) => `${Math.round(n / 1024)} kB`;

// ── 1. Every key the page names is promoted ─────────────────────────────
const keys = new Set();
for (const file of ['src/content.js', 'src/content.tr.js']) {
  const content = (await import(path.join(root, file))).default;
  const walk = (node, at) => {
    if (Array.isArray(node)) node.forEach((v, i) => walk(v, `${at}[${i}]`));
    else if (node && typeof node === 'object') for (const [k, v] of Object.entries(node)) walk(v, at ? `${at}.${k}` : k);
    else if (at.endsWith('.media') && typeof node === 'string') {
      keys.add(node);
      const entry = manifest[node];
      if (!entry) fail(`${file}: ${at} names "${node}", which media.json does not have (npm run media:promote)`);
      else if ((entry.kind === 'loop' || entry.kind === 'film') && !entry.mp4) {
        fail(`${file}: ${at} "${node}" has no MP4 yet; render it and run npm run media:promote`);
      }
    }
  };
  walk(content, '');
}
// The hero photograph is named by the hero component, not the content.
keys.add('photo-fog');
if (!manifest['photo-fog']) fail('media.json has no photo-fog, the hero photograph');

// ── 2. Every named file exists and its name is its hash ─────────────────
const named = new Set();
const files = [];
const collect = (entry, key) => {
  const walk = (v, where) => {
    if (typeof v === 'string' && v.startsWith('/media/')) files.push({ key, where, url: v });
    else if (Array.isArray(v)) v.forEach((x, i) => walk(x, `${where}[${i}]`));
    else if (v && typeof v === 'object') for (const [k, x] of Object.entries(v)) walk(x, `${where}.${k}`);
  };
  walk(entry, key);
};
for (const [key, entry] of Object.entries(manifest)) {
  if (key.startsWith('$')) continue;
  collect(entry, key);
}
for (const { where, url } of files) {
  named.add(url);
  const file = path.join(pub, url);
  if (!existsSync(file)) {
    fail(`media.json ${where}: ${url} does not exist in public/`);
    continue;
  }
  const hash = /\.([0-9a-f]{10})\.[a-z0-9]+$/.exec(url)?.[1];
  const actual = createHash('sha256').update(readFileSync(file)).digest('hex').slice(0, 10);
  if (hash !== actual) fail(`${url}: the name says ${hash ?? 'no hash'}, the bytes hash to ${actual}`);
}

// ── 3. No orphans ───────────────────────────────────────────────────────
let total = 0;
const walkDir = (dir) => {
  if (!existsSync(dir)) return;
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, e.name);
    if (e.isDirectory()) walkDir(full);
    else {
      total += statSync(full).size;
      const url = `/${path.relative(pub, full).split(path.sep).join('/')}`;
      if (!named.has(url)) fail(`${url} is in public/media but media.json does not name it (npm run media:promote prunes)`);
    }
  }
};
walkDir(path.join(pub, 'media'));
if (total > BUDGETS.mediaTotal) fail(`public/media holds ${kb(total)}, over the ${kb(BUDGETS.mediaTotal)} budget`);

// ── 4. Budgets ──────────────────────────────────────────────────────────
const budgetFor = (entry, url) => {
  const ext = url.split('.').pop();
  if (ext === 'mp4') return entry.kind === 'film' ? BUDGETS.film : BUDGETS.loop;
  if (ext === 'vtt') return BUDGETS.captions;
  if (entry.kind === 'photo') return ext === 'avif' ? BUDGETS.photoAvif : BUDGETS.photoJpg;
  if (entry.kind === 'still') return ext === 'avif' ? BUDGETS.stillAvif : BUDGETS.stillJpg;
  return ext === 'avif' ? BUDGETS.posterAvif : BUDGETS.posterJpg;
};
for (const { key, url } of files) {
  const file = path.join(pub, url);
  if (!existsSync(file)) continue;
  const budget = budgetFor(manifest[key], url);
  const bytes = statSync(file).size;
  if (bytes > budget) fail(`${url}: ${kb(bytes)}, over its ${kb(budget)} budget`);
}
let fonts = 0;
for (const name of readdirSync(path.join(pub, 'fonts'))) {
  if (!name.endsWith('.woff2')) continue;
  const bytes = statSync(path.join(pub, 'fonts', name)).size;
  fonts += bytes;
  if (bytes > BUDGETS.font) fail(`/fonts/${name}: ${kb(bytes)}, over the ${kb(BUDGETS.font)} font budget`);
}
if (fonts > BUDGETS.fontsTotal) fail(`fonts total ${kb(fonts)}, over ${kb(BUDGETS.fontsTotal)}`);
if (!existsSync(path.join(pub, 'fonts/OFL.txt'))) fail('public/fonts/OFL.txt is missing: the font licence travels with the fonts');

// ── 5. MP4 structure, read from the boxes ───────────────────────────────
function boxes(buf, start, end) {
  const out = [];
  let at = start;
  while (at + 8 <= end) {
    let size = buf.readUInt32BE(at);
    const type = buf.toString('latin1', at + 4, at + 8);
    let header = 8;
    if (size === 1) {
      size = Number(buf.readBigUInt64BE(at + 8));
      header = 16;
    } else if (size === 0) size = end - at;
    if (size < header) break;
    out.push({ type, start: at, body: at + header, end: at + size });
    at += size;
  }
  return out;
}
const CONTAINERS = new Set(['moov', 'trak', 'mdia', 'minf', 'stbl']);
function mp4Facts(file) {
  const buf = readFileSync(file);
  const top = boxes(buf, 0, buf.length);
  const order = top.map((b) => b.type);
  const handlers = [];
  let avc = false;
  const dive = (list) => {
    for (const b of list) {
      if (b.type === 'hdlr') handlers.push(buf.toString('latin1', b.body + 8, b.body + 12));
      if (b.type === 'stsd' && buf.includes(Buffer.from('avc1'), b.body)) avc = avc || buf.indexOf('avc1', b.body) < b.end;
      if (CONTAINERS.has(b.type)) dive(boxes(buf, b.body, b.end));
    }
  };
  dive(top);
  return { faststart: order.indexOf('moov') !== -1 && order.indexOf('moov') < order.indexOf('mdat'), handlers, avc };
}
for (const { key, url } of files) {
  if (!url.endsWith('.mp4')) continue;
  const file = path.join(pub, url);
  if (!existsSync(file)) continue;
  const { faststart, handlers, avc } = mp4Facts(file);
  if (!faststart) fail(`${url}: moov comes after mdat; encode with -movflags +faststart so it starts before it finishes loading`);
  if (!avc) fail(`${url}: not H.264 (no avc1 sample entry); every browser plays H.264, not every one plays the rest`);
  const sound = handlers.includes('soun');
  if (manifest[key].kind === 'loop' && sound) fail(`${url}: a loop with a sound track; loops are silent (-an)`);
  if (manifest[key].kind === 'film' && !sound) fail(`${url}: the film has no sound track`);
}

// ── 6. The photograph's credit ──────────────────────────────────────────
const credit = manifest['photo-fog']?.credit ?? {};
for (const field of ['author', 'licence', 'licenceUrl', 'source']) {
  if (!credit[field]) fail(`media.json photo-fog.credit.${field} is missing; the licence requires the credit`);
}

if (problems.length) {
  for (const p of problems) console.error(`::error::${p}`);
  console.error(`\n✗ media: ${problems.length} problem(s).`);
  process.exit(1);
}
console.log(`✓ media: ${files.length} files for ${keys.size} keys, hashes match, ${kb(total)} in public/media, inside every budget`);
