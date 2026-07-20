/// URL detection for free text (round 8, OPH-164 — task descriptions).
///
/// Pure string → segments so it unit-tests without Flutter; the widget layer
/// (`widgets/linkified_text.dart`) turns segments into tappable spans. OG-style
/// link previews are a deliberate v2 (they need a server-side unfurl proxy).
library;

/// One run of text: [uri] is null for plain text, set for a link.
typedef LinkSegment = ({String text, Uri? uri});

/// `http(s)://…` or a bare `www.…` host. Whitespace and `<>` end a URL;
/// trailing sentence punctuation is trimmed after the match (see below) so
/// "bak: https://x.dev." links to `x.dev`, not `x.dev.`.
final RegExp _urlPattern = RegExp(
  r'(https?://[^\s<>]+|www\.[^\s<>]+)',
  caseSensitive: false,
);

const String _trailing = '.,;:!?\'"”’»';

/// Strips sentence punctuation from the end of a matched URL. A `)` is kept
/// only while the URL has an unmatched `(` — Wikipedia-style
/// `…/Task_(project)` survives, `(see https://x.dev)` does not eat the paren.
String _trimUrl(String url) {
  var out = url;
  while (out.isNotEmpty) {
    final last = out[out.length - 1];
    if (_trailing.contains(last)) {
      out = out.substring(0, out.length - 1);
      continue;
    }
    if (last == ')') {
      final opens = '('.allMatches(out).length;
      final closes = ')'.allMatches(out).length;
      if (closes > opens) {
        out = out.substring(0, out.length - 1);
        continue;
      }
    }
    break;
  }
  return out;
}

/// The launchable form of a detected URL (`www.` gets an https scheme).
Uri? linkUriOf(String url) =>
    Uri.tryParse(url.startsWith(RegExp('https?://', caseSensitive: false))
        ? url
        : 'https://$url');

/// Splits [text] into plain and link segments, in order, losslessly —
/// concatenating every segment's `text` reproduces [text] exactly.
List<LinkSegment> linkifySegments(String text) {
  final segments = <LinkSegment>[];
  var cursor = 0;
  for (final match in _urlPattern.allMatches(text)) {
    final url = _trimUrl(match.group(0)!);
    if (url.isEmpty) continue;
    final start = match.start;
    final end = start + url.length;
    if (start > cursor) {
      segments.add((text: text.substring(cursor, start), uri: null));
    }
    final uri = linkUriOf(url);
    segments.add((text: url, uri: uri));
    cursor = end;
  }
  if (cursor < text.length) {
    segments.add((text: text.substring(cursor), uri: null));
  }
  return segments;
}
