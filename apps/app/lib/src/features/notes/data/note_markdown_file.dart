/// Note → Markdown file (the .md export).
///
/// The body is already markdown — the canonical format since ADR-0033 — so
/// the file is the body plus the one thing the body never stores: its title.
/// Like the API (`exportNoteMarkdown`, `GET /notes/:id/export`) the title
/// becomes a leading `# ` heading — but, unlike it, not when the body already
/// opens with a `# ` heading of its own, so the file never starts with two. Embedded pictures stay links (`alliswell://file/…` or http) — a
/// markdown file has nowhere to put the bytes.
library;

import 'dart:convert';
import 'dart:typed_data';

/// The MIME type of what [noteMarkdownBytes] returns.
const markdownMimeType = 'text/markdown';

/// A document's front matter, which has to stay the file's first lines for
/// any tool to read it — so the title heading goes below it, not above.
final _frontMatter = RegExp(r'^---[ \t]*\r?\n[\s\S]*?\r?\n---[ \t]*(\r?\n|$)');

/// The file's text.
String noteMarkdownFile(String title, String markdown) {
  final front = _frontMatter.firstMatch(markdown)?.group(0) ?? '';
  final body = markdown.substring(front.length).trimLeft();
  final heading = title.trim();
  final opensWithHeading = RegExp(r'^#\s').hasMatch(body);
  final text = heading.isEmpty || opensWithHeading
      ? markdown
      : '$front${front.isEmpty ? '' : '\n'}# $heading\n'
            '${body.isEmpty ? '' : '\n$body'}';
  return text.endsWith('\n') ? text : '$text\n';
}

/// The file's bytes, UTF-8.
Uint8List noteMarkdownBytes(String title, String markdown) =>
    Uint8List.fromList(utf8.encode(noteMarkdownFile(title, markdown)));
