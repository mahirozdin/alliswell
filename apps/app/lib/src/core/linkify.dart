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
Uri? linkUriOf(String url) => Uri.tryParse(
  url.startsWith(RegExp('https?://', caseSensitive: false))
      ? url
      : 'https://$url',
);

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

/// What a task ROW shows for its title (OPH-400, DESIGN §46 R4).
typedef RowTitle = ({String text, bool isLink});

const String _zwsp = '​';

/// A title that is nothing but a URL reads as `host › path` — no scheme, no
/// `www.`, no query or fragment — and says it is a link, so the row can put a
/// link glyph before it and keep it to one line. The detail screen keeps the
/// whole string.
///
/// Any other title is returned as it is, except that a URL inside it gets a
/// zero-width break after its `/ ? & =`, so a long link wraps where a reader
/// would break it instead of in the middle of a word (U-12).
RowTitle awRowTitle(String title) {
  final trimmed = title.trim();
  final whole = _urlPattern.matchAsPrefix(trimmed);
  if (whole != null &&
      whole.end == trimmed.length &&
      _trimUrl(trimmed) == trimmed) {
    // String surgery rather than `Uri`: a malformed escape makes `Uri.parse`
    // throw, and the row still has to show something sensible.
    final rest = trimmed.replaceFirst(
      RegExp('^https?://', caseSensitive: false),
      '',
    );
    final cut = rest.indexOf(RegExp('[/?#]'));
    var host = (cut < 0 ? rest : rest.substring(0, cut)).toLowerCase();
    if (host.startsWith('www.')) host = host.substring(4);
    var path = cut < 0 ? '' : rest.substring(cut).split(RegExp('[?#]')).first;
    while (path.startsWith('/')) {
      path = path.substring(1);
    }
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    try {
      path = Uri.decodeFull(path);
    } on Object {
      // A malformed escape: show what was typed.
    }
    return (text: path.isEmpty ? host : '$host › $path', isLink: true);
  }
  final segments = linkifySegments(title);
  if (!segments.any((s) => s.uri != null)) {
    return (text: title, isLink: false);
  }
  final out = StringBuffer();
  for (final segment in segments) {
    if (segment.uri == null) {
      out.write(segment.text);
      continue;
    }
    final url = segment.text;
    for (var i = 0; i < url.length; i++) {
      final char = url[i];
      out.write(char);
      final next = i + 1 < url.length ? url[i + 1] : '';
      if ('/?&='.contains(char) && next.isNotEmpty && next != '/') {
        out.write(_zwsp);
      }
    }
  }
  return (text: out.toString(), isLink: false);
}
