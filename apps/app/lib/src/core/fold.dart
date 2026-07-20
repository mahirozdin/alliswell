/// The search/matching fold (ADR-0013, round 8). One function, app-owned,
/// applied to BOTH stored text and queries — never ship a second matcher.
///
/// Verified during design (ADR-0013): neither SQLite's unicode61 tokenizer nor
/// MySQL's `utf8mb4_0900_ai_ci` folds dotless `ı` to `i` (DUCET gives U+0131
/// its own primary weight), so Turkish-tolerant matching cannot be delegated
/// to an engine. The API mirrors this exact table in `src/lib/fold.js`;
/// `fold_parity.json` keeps the two byte-identical.
library;

/// Lowercase-input de-accent table: Latin-1 Supplement + Latin Extended-A
/// (plus a few common non-decomposables). Input is lowercased first, so only
/// lowercase forms appear here. Dart has no built-in Unicode normalization —
/// an explicit table keeps the fold deterministic and dependency-free
/// (ADR-0009 philosophy).
const Map<int, String> _foldTable = {
  // Turkish
  0x00E7: 'c', // ç
  0x011F: 'g', // ğ
  0x015F: 's', // ş
  0x00F6: 'o', // ö
  0x00FC: 'u', // ü
  // circumflex (kâğıt, îmâ)
  0x00E2: 'a', 0x00EE: 'i', 0x00FB: 'u',
  // common European accents
  0x00E0: 'a', 0x00E1: 'a', 0x00E3: 'a', 0x00E4: 'a', 0x00E5: 'a',
  0x00E8: 'e', 0x00E9: 'e', 0x00EA: 'e', 0x00EB: 'e',
  0x00EC: 'i', 0x00ED: 'i', 0x00EF: 'i',
  0x00F1: 'n',
  0x00F2: 'o', 0x00F3: 'o', 0x00F4: 'o', 0x00F5: 'o',
  0x00F9: 'u', 0x00FA: 'u',
  0x00FD: 'y', 0x00FF: 'y',
  // non-decomposables / ligatures
  0x00DF: 'ss', // ß
  0x00E6: 'ae', // æ
  0x00F8: 'o', // ø
  0x0111: 'd', // đ
  0x0142: 'l', // ł
  0x0153: 'oe', // œ
  // Latin Extended-A (already-lowercased forms)
  0x0101: 'a', 0x0103: 'a', 0x0105: 'a',
  0x0107: 'c', 0x0109: 'c', 0x010B: 'c', 0x010D: 'c',
  0x010F: 'd',
  0x0113: 'e', 0x0115: 'e', 0x0117: 'e', 0x0119: 'e', 0x011B: 'e',
  0x011D: 'g', 0x0121: 'g', 0x0123: 'g',
  0x0125: 'h', 0x0127: 'h',
  0x0129: 'i', 0x012B: 'i', 0x012D: 'i', 0x012F: 'i',
  0x0135: 'j',
  0x0137: 'k',
  0x013A: 'l', 0x013C: 'l', 0x013E: 'l', 0x0140: 'l',
  0x0144: 'n', 0x0146: 'n', 0x0148: 'n',
  0x014D: 'o', 0x014F: 'o', 0x0151: 'o',
  0x0155: 'r', 0x0157: 'r', 0x0159: 'r',
  0x015B: 's', 0x015D: 's', 0x0161: 's',
  0x0163: 't', 0x0165: 't', 0x0167: 't',
  0x0169: 'u', 0x016B: 'u', 0x016D: 'u', 0x016F: 'u', 0x0171: 'u',
  0x0173: 'u',
  0x0175: 'w',
  0x0177: 'y',
  0x017A: 'z', 0x017C: 'z', 0x017E: 'z',
};

/// Case- and accent-insensitive normal form: `foldSearchText('Çay İÇ ISI')`
/// == `foldSearchText('cay ic isi')`. Whitespace runs collapse to one space;
/// the result is trimmed. Non-Latin scripts pass through casefolded (they
/// match exactly — de-accenting them is out of scope, ADR-0013).
String foldSearchText(String input) {
  // Dotted/dotless i FIRST: 'İ'.toLowerCase() leaves 'i'+U+0307 and 'ı' has
  // no case/decomposition mapping anywhere — both must be pinned by hand.
  final lowered = input
      .replaceAll('İ', 'i')
      .replaceAll('I', 'i')
      .replaceAll('ı', 'i')
      .toLowerCase()
      // A stray combining-dot-above can still arrive from pre-composed input.
      .replaceAll('̇', '');
  final out = StringBuffer();
  for (final rune in lowered.runes) {
    out.write(_foldTable[rune] ?? String.fromCharCode(rune));
  }
  return out.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}
