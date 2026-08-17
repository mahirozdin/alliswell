/// Searchable plain text, app-owned (OPH-274, ADR-0033).
///
/// The twin of `markdownToPlainText` in `apps/api/src/lib/delta.js`. It lives
/// in `core/` for the same reason `fold.dart` does: it is a pure text
/// transform that BOTH the store and the drift v19 migration need, and the
/// value it produces has to match the server's character for character or
/// offline search and server search disagree about what a note says.
library;

const _maxPlainText = 60000;

/// Searchable plain text from MARKDOWN — mirrors `markdownToPlainText` in
/// `apps/api/src/lib/delta.js`, character for character, so offline search and
/// server search agree about what a note says.
///
/// The server grew this twin in OPH-261; the app never did, and the gap was a
/// live defect rather than a missing nicety. `plainText`/`bodyFold` were
/// derived ONLY from a delta, so a markdown-canonical note carried an empty
/// search column locally: it synced, it rendered, it exported, and offline
/// search could not find it. ADR-0033 makes every note markdown, so without
/// this the blind spot would have become total.
///
/// Deliberately not a markdown parser. The goal is the words a person would
/// search for, so this strips the syntax standing between them; anything it
/// fails to recognise stays as text, which is the safe direction for a search
/// column.
String plainTextFromMarkdown(String? markdown) {
  if (markdown == null || markdown.isEmpty) return '';
  final text = markdown
      // Fenced code: rarely what someone searches a note for, and keeping it
      // would drown the prose in punctuation.
      .replaceAll(RegExp(r'^```[\s\S]*?^```', multiLine: true), ' ')
      .replaceAll(RegExp(r'^~~~[\s\S]*?^~~~', multiLine: true), ' ')
      // Front matter, when the document opens with it.
      .replaceFirst(RegExp(r'^---\n[\s\S]*?\n---\n'), ' ')
      // Images before links: `![alt](src)` must not survive as a link label.
      .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), ' ')
      .replaceAllMapped(RegExp(r'\[([^\]]*)\]\([^)]*\)'), (m) => m[1]!)
      .replaceAll(RegExp(r'<[^>\s]+>'), ' ')
      .replaceAllMapped(RegExp(r'`([^`]*)`'), (m) => m[1]!)
      // Block markers at the start of a line.
      .replaceAll(RegExp(r'^\s{0,3}#{1,6}\s+', multiLine: true), '')
      .replaceAll(RegExp(r'^\s{0,3}>\s?', multiLine: true), '')
      .replaceAll(RegExp(r'^\s*[-*+]\s+\[[ xX]\]\s+', multiLine: true), '')
      .replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '')
      .replaceAll(RegExp(r'^\s*\d+[.)]\s+', multiLine: true), '')
      // Horizontal rules, table pipes and cell padding.
      .replaceAll(
        RegExp(r'^\s{0,3}([-*_])\s*(?:\1\s*){2,}$', multiLine: true),
        ' ',
      )
      .replaceAll('|', ' ')
      // Emphasis, strikethrough and the highlight mark.
      .replaceAllMapped(
        RegExp(r'(\*\*|__|~~|==)(.*?)\1', dotAll: false),
        (m) => m[2]!,
      )
      .replaceAllMapped(
        RegExp(r'(^|[^\w])[*_]([^*_\n]+)[*_]([^\w]|$)'),
        (m) => '${m[1]}${m[2]}${m[3]}',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return text.length > _maxPlainText ? text.substring(0, _maxPlainText) : text;
}
