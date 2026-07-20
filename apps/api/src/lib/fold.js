/**
 * The search fold — the API mirror of the app's `core/fold.dart` (ADR-0013).
 * One table, two runtimes, byte-identical output: `fold_parity.json` is
 * asserted by BOTH test suites. Change one side only and a test fails.
 *
 * Why app-owned at all: neither SQLite's unicode61 tokenizer nor MySQL's
 * utf8mb4_0900_ai_ci folds dotless `ı` to `i` (DUCET gives U+0131 its own
 * primary weight) — Turkish-tolerant matching cannot be delegated to an
 * engine.
 */

/** Lowercase-input de-accent table: Latin-1 Supplement + Latin Extended-A. */
const FOLD_TABLE = new Map([
  // Turkish
  [0x00e7, 'c'], // ç
  [0x011f, 'g'], // ğ
  [0x015f, 's'], // ş
  [0x00f6, 'o'], // ö
  [0x00fc, 'u'], // ü
  // circumflex (kâğıt, îmâ)
  [0x00e2, 'a'],
  [0x00ee, 'i'],
  [0x00fb, 'u'],
  // common European accents
  [0x00e0, 'a'],
  [0x00e1, 'a'],
  [0x00e3, 'a'],
  [0x00e4, 'a'],
  [0x00e5, 'a'],
  [0x00e8, 'e'],
  [0x00e9, 'e'],
  [0x00ea, 'e'],
  [0x00eb, 'e'],
  [0x00ec, 'i'],
  [0x00ed, 'i'],
  [0x00ef, 'i'],
  [0x00f1, 'n'],
  [0x00f2, 'o'],
  [0x00f3, 'o'],
  [0x00f4, 'o'],
  [0x00f5, 'o'],
  [0x00f9, 'u'],
  [0x00fa, 'u'],
  [0x00fd, 'y'],
  [0x00ff, 'y'],
  // non-decomposables / ligatures
  [0x00df, 'ss'], // ß
  [0x00e6, 'ae'], // æ
  [0x00f8, 'o'], // ø
  [0x0111, 'd'], // đ
  [0x0142, 'l'], // ł
  [0x0153, 'oe'], // œ
  // Latin Extended-A (already-lowercased forms)
  [0x0101, 'a'],
  [0x0103, 'a'],
  [0x0105, 'a'],
  [0x0107, 'c'],
  [0x0109, 'c'],
  [0x010b, 'c'],
  [0x010d, 'c'],
  [0x010f, 'd'],
  [0x0113, 'e'],
  [0x0115, 'e'],
  [0x0117, 'e'],
  [0x0119, 'e'],
  [0x011b, 'e'],
  [0x011d, 'g'],
  [0x0121, 'g'],
  [0x0123, 'g'],
  [0x0125, 'h'],
  [0x0127, 'h'],
  [0x0129, 'i'],
  [0x012b, 'i'],
  [0x012d, 'i'],
  [0x012f, 'i'],
  [0x0135, 'j'],
  [0x0137, 'k'],
  [0x013a, 'l'],
  [0x013c, 'l'],
  [0x013e, 'l'],
  [0x0140, 'l'],
  [0x0144, 'n'],
  [0x0146, 'n'],
  [0x0148, 'n'],
  [0x014d, 'o'],
  [0x014f, 'o'],
  [0x0151, 'o'],
  [0x0155, 'r'],
  [0x0157, 'r'],
  [0x0159, 'r'],
  [0x015b, 's'],
  [0x015d, 's'],
  [0x0161, 's'],
  [0x0163, 't'],
  [0x0165, 't'],
  [0x0167, 't'],
  [0x0169, 'u'],
  [0x016b, 'u'],
  [0x016d, 'u'],
  [0x016f, 'u'],
  [0x0171, 'u'],
  [0x0173, 'u'],
  [0x0175, 'w'],
  [0x0177, 'y'],
  [0x017a, 'z'],
  [0x017c, 'z'],
  [0x017e, 'z'],
]);

/**
 * Case- and accent-insensitive normal form; see the Dart twin for the rules.
 * @param {string} input
 * @returns {string}
 */
export function foldSearchText(input) {
  const lowered = input
    .replaceAll('İ', 'i') // U+0130 lowercases to i + stray U+0307 — pin first
    .replaceAll('I', 'i')
    .replaceAll('ı', 'i')
    .toLowerCase()
    .replaceAll('̇', '');
  let out = '';
  for (const ch of lowered) {
    out += FOLD_TABLE.get(ch.codePointAt(0)) ?? ch;
  }
  return out.replace(/\s+/g, ' ').trim();
}
