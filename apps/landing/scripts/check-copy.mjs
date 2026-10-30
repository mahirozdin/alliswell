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
import { existsSync, readFileSync } from 'node:fs';
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
    vocabulary: true,
    downloads: true,
  },
  {
    name: 'home',
    en: 'src/content.js',
    tr: 'src/content.tr.js',
    entries: { en: 'index.html', tr: 'tr/index.html' },
    shotsPerLanguage: false,
    // ADR-0061: rendered on the server, so the shell carries markers, not the h1.
    ssr: true,
    hallmark: true,
  },
];

/**
 * ── 9. Hallmark's floor, where a machine can read it (ADR-0061) ──────────
 *
 * The homepage follows Hallmark's Dusk theme, whose floor bans an eyebrow
 * over a heading, an emoji standing in for an icon, the em and en dashes of
 * generated prose, and more than about 450 words on the page. sloplint checks
 * the rendered page when someone runs it; this holds the words on every
 * commit. Visible means what a reader sees without opening anything: closed
 * answers, the film transcript, alt text, the head and the chrome are not
 * counted, and of the five tour panes only the open one's line is.
 */
const WORD_BUDGET = 450;
const HIDDEN_ROOTS = /^(seo|lang|skip|ui|nav|footer)\b/;
const HIDDEN_LEAVES = /^(alt|media|href|url|command|transcript|a|copied|id)$/;
const DASHES = /[\u2013\u2014]/;
const EMOJI = /\p{Extended_Pictographic}/u;
const words = (text) => text.split(/\s+/).filter((w) => /\p{L}{2,}/u.test(w)).length;

/**
 * ── 7. The words the sales deck does not use (OPH-388) ──────────────────
 *
 * The enterprise page speaks the language of the factory deck it follows:
 * "talep", "birim", "kurum dışı talep formu" — not the translated-sounding
 * terms a buyer hears as somebody else's product. The page had drifted into
 * "on-premise", "herkese açık talep formu" and "departman" while both files
 * stayed perfectly consistent with each other, which is exactly what checks
 * 1–5 cannot see. The list is the sales deck's language rules.
 *
 * Plurals and Turkish suffixes count: the Turkish patterns anchor only the
 * start of the word ("ticketlar", "team'i"), the English ones take an `s`.
 *
 * Prose only: a leaf whose NAME is structure (a path, an icon key, a layout)
 * is skipped — alt text is prose and is checked. A deliberate use is marked
 * `i18n-vocab-ok` on a line of the source that carries the word.
 */
const FORBIDDEN = {
  tr: [
    /\b(ticket|team|queue|dashboard|workflow|on-?prem|public portal)/i,
    /servis masası|herkese açık|departman|kuyruk/i,
  ],
  en: [/\b(tickets?|on-?prem(ise)?s?|service desks?|public portals?|departments?|queues?|workflows?)\b/i],
};
/** Leaf names that hold structure, not words a reader reads. */
const STRUCTURE = /^(lang|shot|shotDark|src|href|ogImage|icon|tone|layout|frame|accent|key|id|anchor|ratio|frameWidth|media|captions)$/;

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

/** The last name in a leaf path: `org.shots[0].alt` → `alt`. */
const leafName = (key) => key.replace(/\[\d+\]/g, '').split('.').pop();

/** The string literals written on one source line, unescaped. */
function literals(line) {
  const out = [];
  for (const m of line.matchAll(/'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)"|`((?:[^`\\]|\\.)*)`/g)) {
    out.push((m[1] ?? m[2] ?? m[3]).replace(/\\(.)/g, '$1'));
  }
  return out;
}

/**
 * Is the word marked `i18n-vocab-ok` on one of THIS leaf's own source lines?
 * The marked line must carry a string fragment that holds the word and is part
 * of the leaf's value — so one marked sentence does not exempt the same word in
 * every other leaf of the file. A line that is only a comment does not count:
 * the file header that LISTS the forbidden words and names the marker would
 * otherwise exempt all of them.
 */
function vocabExempt(lines, word, value) {
  const w = word.toLocaleLowerCase('tr');
  const v = value.toLocaleLowerCase('tr');
  return lines.some(
    (line) =>
      !/^\s*(\/\/|\/?\*)/.test(line) &&
      line.includes('i18n-vocab-ok') &&
      literals(line).some((f) => {
        const lf = f.toLocaleLowerCase('tr');
        return lf.includes(w) && v.includes(lf);
      }),
  );
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
    // `lang`, the shot paths and the addresses are structure, not prose. The
    // LEAF's name decides (OPH-388): `org.shots[0].alt` is prose under a
    // parent called `shots`, and testing the whole path skipped every caption.
    if (key === 'lang' || /shot|ogImage|href|src|media|captions|url/i.test(leafName(key))) continue;
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
        // The leaf's name, not the path: `shots[0].alt` is not a path (OPH-388).
        if (!/shot|ogImage/i.test(leafName(key)) || typeof value !== 'string' || value === '') continue;
        if (!value.startsWith('/shots/')) {
          fail(`${tag} ${file}: ${key} must be a whole path starting /shots/ (got "${value}")`);
        }
        if (!value.endsWith(`-${lang}.jpg`) && !value.includes('/og/')) {
          fail(`${tag} ${file}: ${key} is not the ${lang} capture ("${value}")`);
        }
      }
    }
  }

  // ── 7. The deck's vocabulary (see FORBIDDEN above) ──────────────────────
  if (pair.vocabulary) {
    for (const [file, map, lang] of [
      [pair.en, enLeaves, 'en'],
      [pair.tr, trLeaves, 'tr'],
    ]) {
      const lines = readFileSync(path.join(root, file), 'utf8').split('\n');
      for (const [key, value] of map) {
        if (typeof value !== 'string' || STRUCTURE.test(leafName(key))) continue;
        for (const re of FORBIDDEN[lang]) {
          const hit = value.match(re);
          if (!hit || vocabExempt(lines, hit[0], value)) continue;
          fail(
            `${tag} ${file}: ${key} says "${hit[0]}" — the deck's language rules keep it off ` +
              'this page (mark the source line `i18n-vocab-ok` if it is deliberate)',
          );
        }
      }
    }
  }

  // ── 9. Hallmark's floor (see WORD_BUDGET above) ─────────────────────────
  if (pair.hallmark) {
    for (const [file, map, content] of [
      [pair.en, enLeaves, en],
      [pair.tr, trLeaves, tr],
    ]) {
      let visible = 0;
      for (const [key, value] of map) {
        if (typeof value !== 'string') continue;
        const leaf = leafName(key);
        if (leaf === 'eyebrow') fail(`${tag} ${file}: ${key} is an eyebrow, which the Dusk homepage does not use`);
        if (STRUCTURE.test(leaf)) continue;
        if (EMOJI.test(value)) fail(`${tag} ${file}: ${key} carries an emoji ("${value.match(EMOJI)[0]}")`);
        if (DASHES.test(value)) fail(`${tag} ${file}: ${key} uses an em or en dash; Hallmark's copy floor bans them`);
        if (HIDDEN_ROOTS.test(key) || HIDDEN_LEAVES.test(leaf)) continue;
        if (/^tour\.panes\[[1-9]\]\.body$/.test(key)) continue;
        visible += words(value);
      }
      if (visible > WORD_BUDGET) {
        fail(`${tag} ${file}: ${visible} visible words, over Hallmark's ${WORD_BUDGET}-word page budget`);
      }
      void content;
    }
  }

  // ── 8. Every download the page offers is a file it ships ────────────────
  //
  // `public/` is copied to the docroot as is, and `.htaccess` answers a
  // missing path with index.html and a 200 — so a deck link to a PDF nobody
  // committed "works" in every HTTP check and hands the reader a web page
  // saved as `.pdf`. The file has to be in `public/downloads/` itself.
  if (pair.downloads) {
    for (const [file, map] of [
      [pair.en, enLeaves],
      [pair.tr, trLeaves],
    ]) {
      for (const [key, value] of map) {
        if (typeof value !== 'string' || !value.startsWith('/downloads/')) continue;
        if (!existsSync(path.join(root, 'public', value))) {
          fail(`${tag} ${file}: ${key} offers ${value}, which is not in public/downloads/`);
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
    const heads = [
      ['<title>', content.seo.title],
      ['meta description', content.seo.description],
    ];
    // A server-rendered page keeps its h1 in the component, not the shell;
    // what the shell must carry is exactly one of each marker, or the build
    // ships the empty shell again (check:home reads the rendered h1).
    if (pair.ssr) {
      for (const marker of ['<!--ssr-outlet-->', '<!--ssr-head-->']) {
        const count = html.split(marker).length - 1;
        if (count !== 1) fail(`${tag} ${entry} must carry ${marker} exactly once (found ${count})`);
      }
    } else {
      heads.push(['<h1>', content.hero.title]);
    }
    for (const [what, want] of heads) {
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

// ── 6. What the page claims comes from one list (EE-261) ─────────────────
//
// The enterprise page told buyers, in two languages, that an asset register,
// change approvals, a satisfaction survey and requests by e-mail did not exist
// — for weeks after each shipped. Checks 1–5 could not see it: both files said
// the same wrong thing, perfectly translated. So what the page says ABOUT THE
// PRODUCT is built from `src/enterprise/capabilities.js`, and this holds the
// page to it: the list is whole, the generated parts are in the page as
// generated, and no other FAQ answer may say that something is missing.
const caps = await import(path.join(root, 'src/enterprise/capabilities.js'));
{
  const tag = '[capabilities]';
  const keys = new Set();
  for (const c of caps.CAPABILITIES) {
    if (!c.key || keys.has(c.key)) fail(`${tag} missing or repeated key "${c.key}"`);
    keys.add(c.key);
    if (!caps.LEVELS.includes(c.level)) {
      fail(`${tag} ${c.key}: level "${c.level}" is not one of ${caps.LEVELS.join(', ')}`);
    }
    for (const lang of ['tr', 'en']) {
      if (typeof c[lang] !== 'string' || c[lang].trim() === '') fail(`${tag} ${c.key}: no ${lang} text`);
    }
    if (c.level === 'none' && c.packages) {
      fail(`${tag} ${c.key}: something the product does not have cannot be in a package`);
    }
    if (c.level !== 'none' && !c.packages) {
      fail(`${tag} ${c.key}: something the product has belongs in the package table`);
    }
    if (c.packages && (c.packages.length !== 3 || c.packages.some((v) => !caps.CELLS.includes(v)))) {
      fail(`${tag} ${c.key}: packages must be three of ${caps.CELLS.join('/')}`);
    }
    if (c.level === 'pilot' && !(c.note?.tr?.trim() && c.note?.en?.trim())) {
      fail(`${tag} ${c.key}: a pilot says, in both languages, what it has been proven against`);
    }
  }

  // "Something is missing", in each language — the claim only the generated
  // answer may make.
  const MISSING = {
    tr: /henüz yok|bulunmuyor|mevcut değil|desteklenmiyor|yapılamıyor/i,
    en: /not (?:in (?:it|the product) )?yet|does not exist|is not supported|not available|cannot be done/i,
  };
  const pair = PAIRS.find((x) => x.name === 'enterprise');
  for (const lang of ['tr', 'en']) {
    const content = (await import(path.join(root, pair[lang]))).default;
    const file = pair[lang];
    const notYet = content.faq.items.find((item) => item.key === 'notYet');
    if (!notYet) fail(`${tag} ${file}: the FAQ has no "notYet" item`);
    else if (notYet.a !== caps.notYetAnswer(lang)) {
      fail(`${tag} ${file}: the "not yet" answer was edited by hand — change capabilities.js instead`);
    }
    for (const item of content.faq.items) {
      if (item.key === 'notYet') continue;
      if (MISSING[lang].test(`${item.q} ${item.a}`)) {
        fail(
          `${tag} ${file}: the FAQ "${item.q}" says something is missing — only the generated ` +
            '"not yet" answer may, so that the list is the one place it can go stale',
        );
      }
    }
    const rows = new Set(content.packages.rows.map((row) => JSON.stringify(row)));
    for (const row of caps.packageRows(lang)) {
      if (!rows.has(JSON.stringify(row))) fail(`${tag} ${file}: the package table lacks "${row[0]}"`);
    }
    const offline = caps.OFFLINE[lang];
    const integrity = content.security.items.find((item) => item.key === 'integrity');
    if (!content.hero.facts.includes(offline.fact)) {
      fail(`${tag} ${file}: the hero's offline fact is not the list's`);
    }
    if (!content.itsm.points.includes(offline.queue)) {
      fail(`${tag} ${file}: the queue's offline sentence is not the list's`);
    }
    if (!integrity?.body.startsWith(offline.integrity)) {
      fail(`${tag} ${file}: the integrity paragraph does not open with the list's offline sentence`);
    }
  }
}

if (problems.length) {
  for (const p of problems) console.error(`::error::${p}`);
  console.error(`\n✗ copy: ${problems.length} problem(s).`);
  process.exit(1);
}

console.log(
  `✓ copy: ${total} strings across ${PAIRS.length} pages, both languages, and the heads agree with them; ` +
    `${caps.CAPABILITIES.length} capabilities, the page's claims built from them`,
);
