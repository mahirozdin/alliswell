/// The "@" mention parser of the AI chat composer (OPH-377, ADR-0058) — PURE,
/// so the rules that decide when the attach picker opens are unit-tested
/// without a widget.
///
/// An "@" opens the picker only on a word boundary (start of text, after
/// whitespace or an opening bracket/quote), so an e-mail address never does.
/// The query may hold single spaces (titles have them), never a newline, a
/// leading space or a double space, and is at most [kAiMentionMaxQuery] long.
library;

/// The longest query the picker follows; past it the "@" is plain text.
const int kAiMentionMaxQuery = 40;

/// An active mention: `text[start]` is the "@", [end] is the cursor, and
/// [query] is what was typed between them.
class AiMentionQuery {
  const AiMentionQuery({
    required this.start,
    required this.end,
    required this.query,
  });

  final int start;
  final int end;
  final String query;

  @override
  bool operator ==(Object other) =>
      other is AiMentionQuery &&
      other.start == start &&
      other.end == end &&
      other.query == query;

  @override
  int get hashCode => Object.hash(start, end, query);

  @override
  String toString() => 'AiMentionQuery($start, $end, "$query")';
}

const _boundaryBefore = {' ', '\t', '\n', '\r', '(', '[', '"', "'"};

/// The mention the cursor is in, or null when the picker should be closed.
AiMentionQuery? activeMention(String text, int cursor) {
  if (cursor < 1 || cursor > text.length) return null;
  // Scan back at most one query's length (plus the "@") for the nearest "@".
  final floor = cursor - kAiMentionMaxQuery - 1;
  var at = -1;
  for (var i = cursor - 1; i >= 0 && i >= floor; i--) {
    final char = text[i];
    if (char == '\n' || char == '\r') return null;
    if (char == '@') {
      at = i;
      break;
    }
  }
  if (at < 0) return null;
  if (at > 0 && !_boundaryBefore.contains(text[at - 1])) return null;
  final query = text.substring(at + 1, cursor);
  if (query.length > kAiMentionMaxQuery) return null;
  if (query.startsWith(' ')) return null;
  if (query.contains('  ')) return null;
  return AiMentionQuery(start: at, end: cursor, query: query);
}

/// Removes the "@query" of [mention] (and one space right after it) once an
/// item is picked; the cursor lands where the "@" was.
({String text, int cursor}) removeMention(String text, AiMentionQuery mention) {
  var end = mention.end;
  if (end < text.length && text[end] == ' ') end += 1;
  return (
    text: text.substring(0, mention.start) + text.substring(end),
    cursor: mention.start,
  );
}
