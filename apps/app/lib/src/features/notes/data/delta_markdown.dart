/// Minimal Quill Delta → Markdown converter for preview/export (OPH-044).
/// Covers what our toolbar can produce: headers, bold/italic/strike/code,
/// links, bullet/ordered/checked lists, blockquote and code blocks. The
/// server-side converter (OPH-045) will be the canonical exporter; this one
/// keeps export/preview fully offline-capable in the app.
String deltaToMarkdown(List<Map<String, dynamic>> ops) {
  final lines = <String>[];
  var buffer = StringBuffer();

  void closeLine(Map<String, dynamic>? lineAttributes) {
    final text = buffer.toString();
    buffer = StringBuffer();
    final attrs = lineAttributes ?? const {};

    if (attrs['code-block'] != null && attrs['code-block'] != false) {
      // Merge consecutive code lines into one fenced block.
      if (lines.isNotEmpty && lines.last == '```') {
        lines.removeLast();
        lines.addAll([text, '```']);
      } else {
        lines.addAll(['```', text, '```']);
      }
      return;
    }

    final header = attrs['header'];
    if (header is int && header >= 1 && header <= 6) {
      lines.add('${'#' * header} $text');
      return;
    }
    if (attrs['blockquote'] == true) {
      lines.add('> $text');
      return;
    }
    switch (attrs['list']) {
      case 'bullet':
        lines.add('- $text');
        return;
      case 'ordered':
        lines.add('1. $text');
        return;
      case 'checked':
        lines.add('- [x] $text');
        return;
      case 'unchecked':
        lines.add('- [ ] $text');
        return;
    }
    lines.add(text);
  }

  String inline(String text, Map<String, dynamic>? attrs) {
    if (attrs == null || attrs.isEmpty) return text;
    var out = text;
    if (attrs['code'] == true) out = '`$out`';
    if (attrs['bold'] == true) out = '**$out**';
    if (attrs['italic'] == true) out = '_${out}_';
    if (attrs['strike'] == true) out = '~~$out~~';
    final link = attrs['link'];
    if (link is String && link.isNotEmpty) out = '[$out]($link)';
    return out;
  }

  for (final op in ops) {
    final insert = op['insert'];
    final attrs = (op['attributes'] as Map?)?.cast<String, dynamic>();
    if (insert is! String) continue; // embeds are dropped in markdown export

    var remaining = insert;
    while (remaining.contains('\n')) {
      final idx = remaining.indexOf('\n');
      buffer.write(inline(remaining.substring(0, idx), attrs));
      // In Quill deltas the newline op carries the LINE's block attributes.
      closeLine(attrs);
      remaining = remaining.substring(idx + 1);
    }
    if (remaining.isNotEmpty) buffer.write(inline(remaining, attrs));
  }
  if (buffer.isNotEmpty) closeLine(null);

  // Collapse the trailing empty line Quill documents always end with.
  while (lines.isNotEmpty && lines.last.trim().isEmpty) {
    lines.removeLast();
  }
  return lines.join('\n');
}
