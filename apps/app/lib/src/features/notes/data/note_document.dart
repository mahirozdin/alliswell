/// What a note is made of, and which surfaces may edit it (OPH-248, OPH-274).
///
/// ## One canonical form
///
/// ADR-0028 §1 split notes by intent: a note was either Delta-canonical (the
/// rich editor wrote it) or markdown-canonical (it came from a file, or the
/// user converted it on purpose). ADR-0033 ended that split — **a note is
/// markdown**. There is no rich editor to be the other half of it, no
/// conversion door, and no format flag to disagree about.
///
/// What that removes is not just code. Under the split, every write path
/// (saving, exporting, versioning, merging, indexing for search) had to ask
/// which field was real and had two answers. The most expensive consequence
/// was that the three-way merge REFUSED to run on Delta notes — so the
/// conflict engine Epic 25 built never ran on the app's own documents.
///
/// ## D3 is why the controllers live here
///
/// "A mode switch preserves the caret, the scroll position and the undo
/// history." The mechanism is not to restore that state — it is to never tear
/// it down. The controller is created once per document and outlives every
/// mode switch, so the caret, the selection, the scroll offset and Flutter's
/// own undo stack simply continue.
library;

import 'package:flutter/material.dart';

import 'package:markdown_forge/markdown_forge.dart';
import 'note.dart';

/// A surface the editor can show.
///
/// Two, and both of them always available — which is what DESIGN §29 D1 asked
/// for in the first place. The D1 amendment OPH-248 had to write (a note
/// offers only the editor matching its canonical form, and the third mode is
/// reached through a warned one-way conversion) exists only because there were
/// two canonical forms. There is one now, so the amendment is retired.
enum NoteMode {
  /// The rendered document.
  reading,

  /// The markdown source, with live syntax (OPH-274).
  source,
}

/// What the document managed to do with an uploaded file.
///
/// `attachedOnly` is gone with ADR-0033, and its disappearance is a fix. It
/// meant "the file is attached but the surface cannot show it" — true of the
/// rich editor, which had an image node, a video node and nothing else, so a
/// PDF or a zip vanished into the Files tab and the caller had to apologise
/// with a snackbar. Markdown has a link, so every file now leaves a mark in
/// the document you can actually click.
enum NoteInsert { embedded, linked }

/// Owns a note's content and the controller that edits it.
class NoteDocument extends ChangeNotifier {
  NoteDocument({NoteDetail? note, bool cameFromOutside = false})
    : title = TextEditingController(text: note?.title ?? ''),
      source = MdSourceController(text: note?.contentMarkdown ?? '') {
    _mode = defaultModeFor(cameFromOutside: cameFromOutside);
  }

  final TextEditingController title;

  /// The markdown source. Kept alive across mode switches (D3).
  final MdSourceController source;

  late NoteMode _mode;
  NoteMode get mode => _mode;

  /// D2: a document that arrived from outside opens in Reading — the first
  /// thing you do with someone else's file is read it. A note written here
  /// opens in its editor, because the first thing you do with yours is keep
  /// writing.
  ///
  /// This used to be computed as `format == NoteFormat.markdown`, which
  /// equated "markdown" with "came from outside". It was wrong the day it was
  /// written (a note the user converted on purpose opened read-only every
  /// time — the parked OPH-270 finding) and under ADR-0033 it would have made
  /// EVERY note open read-only. Provenance is now what it always was: a fact
  /// the caller knows and passes.
  static NoteMode defaultModeFor({required bool cameFromOutside}) =>
      cameFromOutside ? NoteMode.reading : NoteMode.source;

  /// The modes this note offers. Every note offers both.
  List<NoteMode> get availableModes => const [
    NoteMode.source,
    NoteMode.reading,
  ];

  /// Replaces the document's content with a note that arrived from the server
  /// (OPH-268 V7). Called ONLY when the editor is clean — a dirty editor keeps
  /// the user's text and lets the push-time three-way merge do the work.
  ///
  /// The controller is reused rather than rebuilt: it owns the focus node and
  /// the scroll position (OPH-270), and swapping it mid-screen is how the
  /// caret used to jump.
  void adoptRemote(NoteDetail note) {
    if (title.text != note.title) title.text = note.title;
    final markdown = note.contentMarkdown ?? '';
    if (source.text != markdown) source.text = markdown;
    notifyListeners();
  }

  void setMode(NoteMode next) {
    if (next == _mode) return;
    _mode = next;
    notifyListeners();
  }

  /// The markdown the Reading view renders — the source itself, byte for byte,
  /// which is what makes OPH-251's "save back to the file" honest.
  String get markdown => source.text;

  /// Puts an already-uploaded file into the document.
  ///
  /// Three things want to do this — the toolbar's insert buttons, a dropped
  /// file, and a pasted image — and if each decided for itself they would
  /// drift the way the toolbar and the slash menu were about to before
  /// `mdActions()` was made the single list.
  NoteInsert insertFile({
    required String fileId,
    required String name,
    required String mime,
  }) {
    final uri = 'alliswell://file/$fileId';
    final isImage = mime.startsWith('image/');
    // Markdown has no video embed, so a non-image becomes a LINK rather than
    // an `![…]()` that every renderer would draw as a broken image. The file
    // is attached either way; this is about not lying in the document.
    final text = isImage ? '![$name]($uri)' : '[$name]($uri)';

    final selection = source.selection;
    final start = selection.isValid ? selection.start : source.text.length;
    final end = selection.isValid ? selection.end : source.text.length;
    source.value = TextEditingValue(
      text: source.text.replaceRange(start, end, text),
      selection: TextSelection.collapsed(offset: start + text.length),
    );
    return isImage ? NoteInsert.embedded : NoteInsert.linked;
  }

  /// The body fields a save should send, keyed as the API names them.
  ///
  /// `contentDelta` is gone from the wire, and `contentFormat` rides along
  /// only because the server still accepts it — a saved note says what it is
  /// rather than letting a column default decide. The title is NOT prefixed
  /// onto the body: it lives in its own field, and the previous release's
  /// habit of writing `# $title` into the markdown is exactly what made
  /// migrated notes show their title twice.
  Map<String, dynamic> bodyFor(String titleText) => {
    'title': titleText,
    'contentMarkdown': source.text,
    'contentFormat': 'markdown',
  };

  @override
  void dispose() {
    title.dispose();
    source.dispose();
    super.dispose();
  }
}
