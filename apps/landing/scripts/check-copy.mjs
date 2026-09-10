#!/usr/bin/env node
// The two content modules of every bilingual page describe the same page
// (EE-152; two pairs since EE-164).
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
//
// ── TWO PAIRS, ONE DIFFERENCE ─────────────────────────────────────────────
//
// The enterprise page's screenshots are produced per language (Flutter goldens
// with the locale in the filename, EE-145), so its paths must end in the
// language they show. The homepage's are captures off real devices and a real
// browser, in English, shared by both languages — the pipeline that makes them
// is not run per language (content.tr.js says why). So the path-per-language
// rule is a property of the PAIR, declared below, not of the gate.
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');

/** Above this many characters, two identical strings are a paste, not a noun. */
const SAME_LIMIT = 40;

const PAIRS = [
  {
    name: 'enterprise',
    en: 'src/enterprise/content.en.js',
    tr: 'src/enterprise/content.tr.js',
    entries: { en: 'enterprise/index.html', tr: 'enterprise/tr/index.html' },
    shotsPerLanguage: true,
  },
  {
    name: 'home',
    en: 'src/content.js',
    tr: 'src/content.tr.js',
    entries: { en: 'index.html', tr: 'tr/index.html' },
    shotsPerLanguage: false,
  },
];

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

/**
 * Is this key marked `i18n-same` in the Turkish file?
 *
 * The marker may sit on the line that DECLARES the key or on any line of its
 * value. Matching only the value's first line was the first attempt and it
 * fails on exactly the values that need the hatch most: a shell command or a
 * long sentence is written as several concatenated fragments, and the natural
 * place to put a comment is the last one.
 */
function exemptIn(trLines) {
  return (key) => {
    const name = key.replace(/\[\d+\]/g, '').split('.').pop();
    const decl = new RegExp(`(^|\\s)${name}\\s*:`);
    let inside = false;
    for (const line of trLines) {
      if (decl.test(line)) inside = true;
      else if (inside && /^\s*\w[\w$]*\s*:/.test(line)) inside = false;
      if (inside && line.includes('i18n-same')) return true;
    }
    return false;
  };
}

let total = 0;

for (const pair of PAIRS) {
  const [en, tr] = await Promise.all([
    import(path.join(root, pair.en)).then((m) => m.default),
    import(path.join(root, pair.tr)).then((m) => m.default),
  ]);
  const tag = `[${pair.name}]`;

  const enLeaves = leaves(en);
  const trLeaves = leaves(tr);
  total += enLeaves.size;

  // ── 1. The same shape, in both directions ───────────────────────────────
  for (const key of enLeaves.keys()) {
    if (!trLeaves.has(key)) fail(`${tag} ${pair.tr} is missing ${key}`);
  }
  for (const key of trLeaves.keys()) {
    if (!enLeaves.has(key)) fail(`${tag} ${pair.en} is missing ${key}`);
  }

  // ── 2. Nothing empty ────────────────────────────────────────────────────
  for (const [file, map] of [
    [pair.en, enLeaves],
    [pair.tr, trLeaves],
  ]) {
    for (const [key, value] of map) {
      if (typeof value === 'string' && value.trim() === '') {
        fail(`${tag} ${file}: ${key} is empty`);
      }
    }
  }

  // ── 3. Untranslated pastes ──────────────────────────────────────────────
  const exempt = exemptIn(readFileSync(path.join(root, pair.tr), 'utf8').split('\n'));
  for (const [key, value] of enLeaves) {
    const other = trLeaves.get(key);
    if (typeof value !== 'string' || value !== other) continue;
    if (value.length <= SAME_LIMIT) continue;
    // `lang`, the shot paths and the addresses are structure, not prose.
    if (key === 'lang' || /shot|ogImage|href|src/i.test(key)) continue;
    if (exempt(key)) continue;
    fail(
      `${tag} ${key} is byte-identical in both languages (${value.length} chars) — ` +
        'translate it, or mark the line `i18n-same` if it is deliberate',
    );
  }

  // ── 4. Screenshot paths are whole, and per language ─────────────────────
  //
  // ci.yml greps the BUILT bundle for `/shots/...` literals. A path assembled
  // at runtime is a path that gate cannot see, which is how a reference to a
  // screenshot nobody produced reaches production. The homepage's captures are
  // gated by ci.yml's own read of content.js and are not per language.
  if (pair.shotsPerLanguage) {
    for (const [file, map, lang] of [
      [pair.en, enLeaves, 'en'],
      [pair.tr, trLeaves, 'tr'],
    ]) {
      for (const [key, value] of map) {
        if (!/shot|ogImage/i.test(key) || typeof value !== 'string' || value === '') continue;
        if (!value.startsWith('/shots/')) {
          fail(`${tag} ${file}: ${key} must be a whole path starting /shots/ (got "${value}")`);
        }
        if (!value.endsWith(`-${lang}.jpg`) && !value.includes('/og/')) {
          fail(`${tag} ${file}: ${key} is not the ${lang} capture ("${value}")`);
        }
      }
    }
  }

  // ── 5. The head and the module agree ────────────────────────────────────
  //
  // The title, the description and the h1 exist in the hand-written HTML entry
  // AND in the content module. Two places is one more than one, and the entry
  // is what a crawler reads while the module is what a reader reads — so they
  // drift in the direction nobody notices.
  for (const [content, entry] of [
    [en, pair.entries.en],
    [tr, pair.entries.tr],
  ]) {
    // `&` is written `&amp;` in the head and `&` in the module; compare the
    // text a reader sees, not the bytes a parser does.
    const html = readFileSync(path.join(root, entry), 'utf8').replace(/&amp;/g, '&');
    for (const [what, want] of [
      ['<title>', content.seo.title],
      ['meta description', content.seo.description],
      ['<h1>', content.hero.title],
    ]) {
      if (!html.includes(want)) {
        fail(`${tag} ${entry} no longer carries the ${what} from ${content.lang}`);
      }
    }
    const ogImage = content.seo.ogImage.replace(/\.jpg$/, '');
    if (!html.includes(ogImage)) {
      fail(`${tag} ${entry} does not point at ${content.seo.ogImage}`);
    }
  }
}

if (problems.length) {
  for (const p of problems) console.error(`::error::${p}`);
  console.error(`\n✗ copy: ${problems.length} problem(s).`);
  process.exit(1);
}

console.log(
  `✓ copy: ${total} strings across ${PAIRS.length} pages, both languages, and the heads agree with them`,
);
