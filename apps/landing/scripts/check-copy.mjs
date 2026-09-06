#!/usr/bin/env node
// The two enterprise content modules describe the same page (EE-152).
//
// ── WHY A GATE AND NOT A CONVENTION ───────────────────────────────────────
//
// The copy lives one file per language rather than `{en, tr}` beside every key,
// because prose has to be readable as prose to be reviewable as prose — the
// same argument `src/content.js` makes for existing. The cost of that choice is
// that nothing about the shape of one file forces the other to match, and a
// missing key is invisible: Vue renders `undefined` as an empty string, so a
// section quietly loses its heading and the page still builds, still passes the
// screenshot gate, and still says it is indexable.
//
// This repository already answers that class of problem with a gate rather than
// a habit — `check:i18n` for the app, `check:docs` for version claims. This is
// the same move for the page's own words.
//
// ── AND THE THIRD CHECK IS THE ONE THAT WILL ACTUALLY FIRE ────────────────
//
// Missing keys are the obvious failure. The likely one is a key that exists in
// both files with the SAME English text in each, because somebody added a
// section, copied the file and translated the parts they could see. That
// produces a Turkish page with English paragraphs in it, which is worse than a
// missing one: it looks finished.
//
// Proper nouns and short shared labels ("SLA", "OIDC", "AllisWell Enterprise")
// legitimately match, so the check only fires above a length where an accident
// is implausible, and `i18n-same` on the line is the escape hatch — the same
// shape as `docs-check-ignore` and `i18n-ignore`.
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');

/** Above this many characters, two identical strings are a paste, not a noun. */
const SAME_LIMIT = 40;

const problems = [];
const fail = (m) => problems.push(m);

/** Every leaf in an object tree, as `a.b[0].c` → value. */
function leaves(node, prefix = '', out = new Map()) {
  if (Array.isArray(node)) {
    node.forEach((v, i) => leaves(v, `${prefix}[${i}]`, out));
  } else if (node && typeof node === 'object') {
    for (const [k, v] of Object.entries(node)) {
      leaves(v, prefix ? `${prefix}.${k}` : k, out);
    }
  } else {
    out.set(prefix, node);
  }
  return out;
}

const [en, tr] = await Promise.all([
  import('../src/enterprise/content.en.js').then((m) => m.default),
  import('../src/enterprise/content.tr.js').then((m) => m.default),
]);

const enLeaves = leaves(en);
const trLeaves = leaves(tr);

// ── 1. The same shape, in both directions ─────────────────────────────────
for (const key of enLeaves.keys()) {
  if (!trLeaves.has(key)) fail(`content.tr.js is missing ${key}`);
}
for (const key of trLeaves.keys()) {
  if (!enLeaves.has(key)) fail(`content.en.js is missing ${key}`);
}

// ── 2. Nothing empty ──────────────────────────────────────────────────────
for (const [file, map] of [
  ['content.en.js', enLeaves],
  ['content.tr.js', trLeaves],
]) {
  for (const [key, value] of map) {
    if (typeof value === 'string' && value.trim() === '') {
      fail(`${file}: ${key} is empty`);
    }
  }
}

// ── 3. Untranslated pastes ────────────────────────────────────────────────
const trSource = readFileSync(path.join(root, 'src/enterprise/content.tr.js'), 'utf8');
const exempt = new Set(
  trSource
    .split('\n')
    .filter((line) => line.includes('i18n-same'))
    .map((line) => line.trim()),
);
for (const [key, value] of enLeaves) {
  const other = trLeaves.get(key);
  if (typeof value !== 'string' || value !== other) continue;
  if (value.length <= SAME_LIMIT) continue;
  // `lang` and the shot paths are structure, not prose; they are checked below.
  if (key === 'lang' || /shot|ogImage|href/i.test(key)) continue;
  const line = trSource
    .split('\n')
    .find((l) => l.includes(value.slice(0, 30)));
  if (line && exempt.has(line.trim())) continue;
  fail(
    `${key} is byte-identical in both languages (${value.length} chars) — ` +
      'translate it, or mark the line `i18n-same` if it is deliberate',
  );
}

// ── 4. Screenshot paths are whole, and per language ───────────────────────
//
// ci.yml greps the BUILT bundle for `/shots/...` literals. A path assembled at
// runtime is a path that gate cannot see, which is how a reference to a
// screenshot nobody produced reaches production.
for (const [file, map, lang] of [
  ['content.en.js', enLeaves, 'en'],
  ['content.tr.js', trLeaves, 'tr'],
]) {
  for (const [key, value] of map) {
    if (!/shot|ogImage/i.test(key) || typeof value !== 'string' || value === '') continue;
    if (!value.startsWith('/shots/')) {
      fail(`${file}: ${key} must be a whole path starting /shots/ (got "${value}")`);
    }
    if (!value.endsWith(`-${lang}.jpg`) && !value.includes('/og/')) {
      fail(`${file}: ${key} is not the ${lang} capture ("${value}")`);
    }
  }
}

// ── 5. The head and the module agree ──────────────────────────────────────
//
// The title, the description and the h1 exist in the hand-written HTML entry
// AND in the content module. Two places is one more than one, and the entry is
// what a crawler reads while the module is what a reader reads — so they drift
// in the direction nobody notices.
for (const [content, entry] of [
  [en, 'enterprise/index.html'],
  [tr, 'enterprise/tr/index.html'],
]) {
  const html = readFileSync(path.join(root, entry), 'utf8');
  for (const [what, want] of [
    ['<title>', content.seo.title],
    ['meta description', content.seo.description],
    ['<h1>', content.hero.title],
  ]) {
    if (!html.includes(want)) {
      fail(`${entry} no longer carries the ${what} from content.${content.lang}.js`);
    }
  }
  const ogImage = content.seo.ogImage.replace(/\.jpg$/, '');
  if (!html.includes(ogImage)) {
    fail(`${entry} does not point at ${content.seo.ogImage}`);
  }
}

if (problems.length) {
  for (const p of problems) console.error(`::error::${p}`);
  console.error(`\n✗ copy: ${problems.length} problem(s).`);
  process.exit(1);
}

console.log(
  `✓ copy: ${enLeaves.size} strings, both languages, and the heads agree with them`,
);
