#!/usr/bin/env node
// OPH-407 (U-10, DESIGN §45) — one form of address per surface, and no "open source".
//
// The Turkish catalogue mixed "sen" and "siz": the personal app said "sen" while its alarm
// strips, the quick-access setting and the alarm test said "siz"; one extension form asked
// "Ne istiyorsun?" above a "Seçin". The rule (DESIGN §45):
//
//   - the personal app (every key outside the extension's) speaks "sen";
//   - the extension's screens speak "siz": `ee.*`, plus the core-named keys listed in
//     scripts/i18n/surfaces.json (the error codes only the extension sends);
//   - no single string mixes the two.
//
// And the licence (ADR-0024) is source-available: "open source" / "açık kaynak" appears in
// neither catalogue.
//
// Turkish address is read from the words themselves, so this is a lexicon, not a parser.
// It looks only for markers that cannot mean anything else in this catalogue:
//   siz  the pronoun (siz, size, sizin…), the -(ı)nız family (hesabınız, değilsiniz,
//        isterseniz) and plural imperatives (ekleyin, seçin, gönderin…);
//   sen  the pronoun (sen, sana, senin…, kendin) and second-person verb endings
//        (istiyorsun, yapabilirsin, değilsin, istersen).
// A bare singular imperative ("Seç", "Kaydet") is how Turkish buttons read in either tone,
// so it is never a marker. Quoted text (“…”, "…") and {placeholders} are skipped: a quote
// is someone else's words.
//
//   node scripts/i18n/tone.mjs          check apps/app/assets/i18n/{tr,en}.json
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "../..");

/** `{a: {b: 'x'}}` → `{'a.b': 'x'}`. */
export function flatten(tree, prefix = "", out = {}) {
  for (const [key, value] of Object.entries(tree)) {
    const path = prefix ? `${prefix}.${key}` : key;
    if (typeof value === "string") out[path] = value;
    else if (value && typeof value === "object") flatten(value, path, out);
  }
  return out;
}

// ── The lexicon ──

const SIZ_PRONOUN = /^siz(?:e|i|in|de|den|le|inle|ce)?$/;
// The -(ı)nız family: possessive (hesabınız), copula (değilsiniz), conditional
// (isterseniz), ability (seçebilirsiniz). Words that merely contain the letters are listed.
const SIZ_SUFFIX = /n[ıiuü]z/;
const NOT_SIZ_SUFFIX = /^(?:henüz|yalnız|önizle|deniz|ikiz)/;
// Plural imperatives after a vowel stem: ekleyin, deneyin, kopyalayın, unutmayın.
const SIZ_IMPERATIVE_Y = /y[ıiuü]n$/;
const NOT_IMPERATIVE_Y = new Set([
  "ayın",
  "şeyin",
  "neyin",
  "köyün",
  "huyun",
  "suyun",
  "beyin",
  "oyun",
  "boyun",
  "koyun",
  "giyin",
  "kayın",
  "tüyün",
]);
// Plural imperatives after a consonant stem look like a genitive (seçin / görevin), so only
// these verbs count.
const SIZ_IMPERATIVE = new Set([
  "seçin",
  "açın",
  "yazın",
  "girin",
  "gönderin",
  "bırakın",
  "edin",
  "kaydedin",
  "iletin",
  "daraltın",
  "düzeltin",
  "yapın",
  "düşünün",
  "yapıştırın",
  "üretin",
  "verin",
  "bakın",
  "gidin",
  "silin",
  "basın",
  "kurun",
  "getirin",
  "indirin",
  "yönlendirin",
  "çalıştırın",
  "değiştirin",
  "kapatın",
  "dokunun",
  "dönün",
  "tutun",
  "çıkarın",
  "ekleyiniz",
  "tamamlayın",
  "paylaşın",
  "kopyalayın",
  "yükleyin",
  "bekleyin",
  "okuyun",
  "dinleyin",
]);

const SEN_PRONOUN =
  /^(?:sen|seni|sana|senin|sende|senden|seninle|sence|kendin)$/;
// Second person singular after a tense: istiyorsun, yapabilirsin, değilsin, kaydedeceksin,
// eklemişsin, girmelisin; and the conditional: istersen, ediyorsan.
const SEN_VERB = /(?:[aeıiuü]r|yor|m[ıiuü]ş|mal[ı]|meli|cak|cek|ğil)s[ıiuü]n$/;
const SEN_CONDITIONAL = /(?:[aeıiuü]r|yor|m[ıiuü]ş|cak|cek)s[ae]n$/;
// Third-person wishes on an r-final stem ("bırak, o versin") read like an aorist second person.
const NOT_SEN_VERB = new Set([
  "versin",
  "görsün",
  "dursun",
  "sorsun",
  "girsin",
  "kırsın",
  "otursun",
  "getirsin",
  "bitirsin",
  "çevirsin",
  "korsan",
  "yarsın",
]);

const QUOTED = /“[^”]*”|"[^"]*"|«[^»]*»/g;
const PLACEHOLDER = /\{[^}]*\}/g;

/** The words in `text` that mark "sen" and "siz". */
export function addressOf(text) {
  const plain = text
    .replace(QUOTED, " ")
    .replace(PLACEHOLDER, " ")
    .toLocaleLowerCase("tr");
  const sen = [];
  const siz = [];
  // A token with an underscore, a digit or a path character is code (client_max_body_size,
  // docs/ATTACHMENTS.md), not Turkish.
  const words = plain
    .split(/\s+/)
    .filter((token) => !/[_\d/\\=@]/.test(token))
    .flatMap((token) => token.split(/[^\p{L}]+/u));
  for (const word of words) {
    if (!word) continue;
    if (
      SIZ_PRONOUN.test(word) ||
      (SIZ_SUFFIX.test(word) && !NOT_SIZ_SUFFIX.test(word)) ||
      (SIZ_IMPERATIVE_Y.test(word) && !NOT_IMPERATIVE_Y.has(word)) ||
      SIZ_IMPERATIVE.has(word)
    ) {
      siz.push(word);
    } else if (
      SEN_PRONOUN.test(word) ||
      ((SEN_VERB.test(word) || SEN_CONDITIONAL.test(word)) &&
        !NOT_SEN_VERB.has(word))
    ) {
      sen.push(word);
    }
  }
  return { sen, siz };
}

// ── Surfaces ──

const EXTENSION = "ee.*";

/** The extension surface's patterns: `ee.*` plus the listed core-named keys. */
export function loadSurfaces(
  file = resolve(ROOT, "scripts/i18n/surfaces.json"),
) {
  const { siz = [] } = JSON.parse(readFileSync(file, "utf8"));
  return [EXTENSION, ...siz];
}

const matches = (key, pattern) =>
  pattern.endsWith("*")
    ? key.startsWith(pattern.slice(0, -1))
    : key === pattern;

/** `siz` on the extension's screens, `sen` everywhere else. */
export function surfaceOf(key, patterns) {
  return patterns.some((p) => matches(key, p)) ? "siz" : "sen";
}

/** Every Turkish string whose address does not fit its surface, or mixes the two. */
export function toneProblems(trFlat, patterns) {
  const problems = [];
  for (const [key, text] of Object.entries(trFlat)) {
    const { sen, siz } = addressOf(text);
    if (sen.length && siz.length) {
      problems.push({ key, kind: "mixed", words: [...sen, ...siz] });
      continue;
    }
    const surface = surfaceOf(key, patterns);
    if (surface === "sen" && siz.length)
      problems.push({ key, kind: "siz-in-sen", words: siz });
    if (surface === "siz" && sen.length)
      problems.push({ key, kind: "sen-in-siz", words: sen });
  }
  // A listed key that no longer exists hides a rename: the new key would silently be "sen".
  for (const pattern of patterns) {
    if (pattern === EXTENSION) continue;
    if (!Object.keys(trFlat).some((key) => matches(key, pattern))) {
      problems.push({ key: pattern, kind: "stale-surface", words: [] });
    }
  }
  return problems;
}

const OPEN_SOURCE = /open[\s-]source|açık\s+kaynak/i;

/** Every string, in any language, that calls the app open source. */
export function licenceProblems(flatByLang) {
  const problems = [];
  for (const [lang, flat] of Object.entries(flatByLang)) {
    for (const [key, text] of Object.entries(flat)) {
      if (OPEN_SOURCE.test(text))
        problems.push({
          key: `${lang}:${key}`,
          kind: "open-source",
          words: [],
        });
    }
  }
  return problems;
}

const WHY = {
  mixed: 'mixes "sen" and "siz"',
  "siz-in-sen": 'says "siz" on a "sen" surface',
  "sen-in-siz": 'says "sen" on an extension ("siz") surface',
  "stale-surface": "is listed in scripts/i18n/surfaces.json but matches no key",
  "open-source": 'says "open source" — the licence is source-available',
};

export function main() {
  const load = (lang) =>
    flatten(
      JSON.parse(
        readFileSync(
          resolve(ROOT, `apps/app/assets/i18n/${lang}.json`),
          "utf8",
        ),
      ),
    );
  const tr = load("tr");
  const en = load("en");
  const problems = [
    ...toneProblems(tr, loadSurfaces()),
    ...licenceProblems({ tr, en }),
  ];
  if (problems.length > 0) {
    console.error(
      `✗ i18n tone: ${problems.length} string(s) break DESIGN §45:`,
    );
    for (const p of problems) {
      console.error(
        `  ${p.key} ${WHY[p.kind]}${p.words.length ? ` (${p.words.join(", ")})` : ""}`,
      );
    }
    return 1;
  }
  console.log(
    `✓ i18n tone: ${Object.keys(tr).length} Turkish strings, one address per surface; no "open source"`,
  );
  return 0;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href)
  process.exitCode = main();
