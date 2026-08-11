/// Typing comfort, as pure text transforms (DESIGN §29 D17/D20, OPH-250).
///
/// D17 — "lists continue themselves, renumber themselves, and nest with
/// Tab / Shift-Tab" — is the single biggest typing win in the round, and it is
/// the thing the flat Delta model blocked. In Source mode it is plain text
/// arithmetic, so it lives here: no widgets, no controllers, every rule
/// testable on a string.
///
/// D20's conversions live here for the same reason. What makes smart paste
/// bearable is that ONE undo restores the raw paste, and the way to guarantee
/// that is to compute the whole new text and assign it once — which only works
/// if the computation is a function.
library;

/// A text edit: the whole new text, and where the caret lands.
class MdEdit {
  const MdEdit(this.text, this.selection);

  final String text;

  /// Caret offset after the edit. Collapsed — these transforms never leave a
  /// selection behind, because a typist's next keystroke would replace it.
  final int selection;
}

/// What kind of list item a line is, if any.
class MdListItem {
  const MdListItem({
    required this.indent,
    required this.marker,
    required this.content,
    required this.ordered,
    this.checkbox,
  });

  /// Leading spaces.
  final String indent;

  /// `-`, `*`, `+`, or `12.` — verbatim, so continuing a `*` list does not
  /// silently switch it to `-`.
  final String marker;

  /// The text after the marker (and after a task checkbox, if there is one).
  final String content;
  final bool ordered;

  /// `' '` or `'x'` when the item is a task-list entry.
  final String? checkbox;

  bool get isEmpty => content.trim().isEmpty;

  int get number =>
      ordered ? int.tryParse(marker.substring(0, marker.length - 1)) ?? 1 : 0;

  String render(String body) {
    final box = checkbox == null ? '' : '[$checkbox] ';
    return '$indent$marker $box$body';
  }
}

final _listRe = RegExp(r'^(\s*)([-*+]|\d+[.)])\s+(?:\[([ xX])\]\s+)?(.*)$');

MdListItem? parseListItem(String line) {
  final m = _listRe.firstMatch(line);
  if (m == null) return null;
  final marker = m.group(2)!;
  return MdListItem(
    indent: m.group(1)!,
    marker: marker,
    checkbox: m.group(3)?.toLowerCase(),
    content: m.group(4)!,
    ordered: RegExp(r'^\d').hasMatch(marker),
  );
}

/// Enter inside a list (D17).
///
/// Three outcomes, and the middle one is the one people notice: pressing Enter
/// on an EMPTY item leaves the list instead of adding another empty bullet.
/// Without it the only way out of a list is to delete the marker you just got.
MdEdit? continueList(String text, int caret) {
  final lineStart = text.lastIndexOf('\n', caret == 0 ? 0 : caret - 1) + 1;
  final lineEnd = text.indexOf('\n', caret);
  final line = text.substring(lineStart, lineEnd < 0 ? text.length : lineEnd);
  final item = parseListItem(line);
  if (item == null) return null;

  if (item.isEmpty) {
    // Leaving the list: the marker goes, the blank line stays.
    final before = text.substring(0, lineStart);
    final after = text.substring(lineStart + line.length);
    return MdEdit('$before\n$after', lineStart + 1);
  }

  final marker = item.ordered
      ? '${item.number + 1}${item.marker.substring(item.marker.length - 1)}'
      : item.marker;
  // A continued task item starts UNCHECKED — carrying `[x]` forward would tick
  // a box the user never ticked.
  final box = item.checkbox == null ? '' : '[ ] ';
  final inserted = '\n${item.indent}$marker $box';
  final before = text.substring(0, caret);
  final after = text.substring(caret);
  return MdEdit('$before$inserted$after', caret + inserted.length);
}

/// Tab / Shift-Tab on a list line (D17).
///
/// Two spaces per level — what every markdown renderer, ours included, reads
/// as one level of nesting.
MdEdit? indentListItem(String text, int caret, {required bool outdent}) {
  final lineStart = text.lastIndexOf('\n', caret == 0 ? 0 : caret - 1) + 1;
  final lineEnd = text.indexOf('\n', caret);
  final end = lineEnd < 0 ? text.length : lineEnd;
  final line = text.substring(lineStart, end);
  if (parseListItem(line) == null) return null;

  String next;
  int shift;
  if (outdent) {
    if (!line.startsWith('  ')) return null;
    next = line.substring(2);
    shift = -2;
  } else {
    next = '  $line';
    shift = 2;
  }
  final updated = text.replaceRange(lineStart, end, next);
  return MdEdit(updated, (caret + shift).clamp(lineStart, updated.length));
}

/// Renumbers every ordered list in [text] so it reads 1, 2, 3 (D17).
///
/// Applied to the whole document rather than one list, because inserting an
/// item renumbers the ones AFTER it too, and a half-renumbered list is worse
/// than an unnumbered one. Counters reset per indent level and whenever
/// anything interrupts the run — the same rule `deltaToMarkdown` uses.
String renumberOrderedLists(String text) {
  final lines = text.split('\n');
  final counters = <int, int>{};

  for (var i = 0; i < lines.length; i++) {
    final item = parseListItem(lines[i]);
    if (item == null || !item.ordered) {
      if (lines[i].trim().isEmpty) continue; // a blank line does not reset
      counters.clear();
      continue;
    }
    final level = item.indent.length ~/ 2;
    counters.removeWhere((k, _) => k > level);
    final next = (counters[level] ?? 0) + 1;
    counters[level] = next;
    final suffix = item.marker.substring(item.marker.length - 1);
    lines[i] = item
        .render(item.content)
        .replaceFirst(RegExp(r'\d+[.)]'), '$next$suffix');
  }
  return lines.join('\n');
}

// ── D20: smart paste ────────────────────────────────────────────────────────

final _urlRe = RegExp(r'^(https?://|mailto:)\S+$');

/// Is [text] a bare URL — the thing that becomes a link when pasted over a
/// selection?
bool isPastableUrl(String text) => _urlRe.hasMatch(text.trim());

/// Pasting a URL over selected text makes a link (D20).
///
/// Returns the WHOLE new text, so the caller assigns once and one undo puts
/// the raw paste back. "Smart" paste without one-step undo is hostile.
MdEdit pasteOverSelection(String text, int start, int end, String pasted) {
  final selected = text.substring(start, end);
  final insert = selected.isNotEmpty && isPastableUrl(pasted)
      ? '[$selected](${pasted.trim()})'
      : pasted;
  final updated = text.replaceRange(start, end, insert);
  return MdEdit(updated, start + insert.length);
}

/// A very small HTML → markdown pass for pasted rich text (D20).
///
/// Deliberately small: `flutter_quill_delta_from_html` handles the rich
/// editor's side, and Source mode wants text, not a Delta. Anything not
/// recognised keeps its tags rather than being stripped — §28 M2's rule, one
/// surface over.
String htmlToMarkdown(String html) {
  var out = html
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAllMapped(
        RegExp(
          r'<h([1-6])[^>]*>(.*?)</h\1>',
          caseSensitive: false,
          dotAll: true,
        ),
        (m) => '${'#' * int.parse(m.group(1)!)} ${m.group(2)}\n',
      )
      .replaceAllMapped(
        RegExp(
          r'<(strong|b)[^>]*>(.*?)</\1>',
          caseSensitive: false,
          dotAll: true,
        ),
        (m) => '**${m.group(2)}**',
      )
      .replaceAllMapped(
        RegExp(r'<(em|i)[^>]*>(.*?)</\1>', caseSensitive: false, dotAll: true),
        (m) => '*${m.group(2)}*',
      )
      .replaceAllMapped(
        RegExp(r'<code[^>]*>(.*?)</code>', caseSensitive: false, dotAll: true),
        (m) => '`${m.group(1)}`',
      )
      .replaceAllMapped(
        RegExp(
          '<a[^>]*href=["\']([^"\']+)["\'][^>]*>(.*?)</a>',
          caseSensitive: false,
          dotAll: true,
        ),
        (m) => '[${m.group(2)}](${m.group(1)})',
      )
      .replaceAllMapped(
        RegExp(r'<li[^>]*>(.*?)</li>', caseSensitive: false, dotAll: true),
        (m) => '- ${m.group(1)}\n',
      )
      .replaceAll(
        RegExp(r'</?(ul|ol|p|div)[^>]*>', caseSensitive: false),
        '\n',
      );

  // Entities last: doing them first would turn an escaped `&lt;b&gt;` into a
  // tag the pass above would then "convert".
  out = out
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"');

  return out.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}

// ── D22: counts ─────────────────────────────────────────────────────────────

/// Words and characters, as a reader would count them.
///
/// Markdown punctuation is text a person typed, so it counts — trying to
/// exclude "just the marks" means deciding whether a heading's `#` is a word,
/// and every answer to that is arbitrary.
({int words, int characters}) countText(String text) {
  final trimmed = text.trim();
  return (
    words: trimmed.isEmpty ? 0 : trimmed.split(RegExp(r'\s+')).length,
    characters: text.length,
  );
}
