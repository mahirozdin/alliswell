/// Where a markdown document's title comes from (OPH-233, kept by OPH-274).
///
/// The one piece of `markdown_delta.dart` that outlived ADR-0033. That file
/// existed to turn markdown INTO a Quill Delta, and with the rich editor gone
/// nothing needs that direction — but the title question is not about Delta at
/// all: a `.md` file has no title field, so its leading H1 is the closest
/// thing, and the app has to decide once whether that heading is the title or
/// the first line of the body.
library;

/// The document's title, Apple-Notes style: its leading `# H1` if it has one,
/// otherwise the file name without its extension.
///
/// Returns the title and the body with that heading removed, so importing
/// `# Yayla planı\n\nrota…` does not repeat the title as the note's first line.
({String title, String body}) splitMarkdownTitle(
  String markdown, {
  required String fallback,
}) {
  final lines = markdown.replaceAll('\r\n', '\n').split('\n');
  var first = 0;
  while (first < lines.length && lines[first].trim().isEmpty) {
    first++;
  }
  if (first < lines.length) {
    final heading = RegExp(r'^#\s+(.+)$').firstMatch(lines[first].trim());
    if (heading != null) {
      final rest = lines.sublist(first + 1);
      while (rest.isNotEmpty && rest.first.trim().isEmpty) {
        rest.removeAt(0);
      }
      return (title: heading.group(1)!.trim(), body: rest.join('\n'));
    }
  }
  return (title: fallback, body: markdown);
}
