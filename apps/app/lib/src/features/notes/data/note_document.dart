/// What a note is made of, and which surfaces may edit it (OPH-248).
///
/// ADR-0028 §1 split notes by intent: a note is either **Delta-canonical**
/// (the rich editor wrote it) or **markdown-canonical** (it came from a file,
/// or the user converted it on purpose). That single fact decides everything
/// this class exposes.
///
/// ## The D1 amendment, and why
///
/// DESIGN §29 D1 asked for "exactly three modes: Reading · Live · Source".
/// Under Option C a note cannot honestly offer all three at once: Live edits a
/// Delta and Source edits markdown text, and only ONE of those is the note's
/// canonical content. Offering the other would either lie about what gets
/// saved or silently convert the document underneath the user.
///
/// So a note offers **two** modes — Reading, plus whichever editor matches its
/// canonical form — and the third is reached through a NAMED, one-way,
/// warned conversion. That is a narrowing of D1's scope, not of its intent: a
/// disabled third segment would be exactly the dead affordance §22 forbids.
///
/// ## D3 is why the controllers live here
///
/// "A mode switch preserves the caret, the scroll position and the undo
/// history." The mechanism is not to restore that state — it is to never tear
/// it down. The controllers are created once per document and outlive every
/// mode switch, so the caret, the selection, the scroll offset and Flutter's
/// own undo stack simply continue.
library;

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'delta_markdown.dart';
import 'markdown_delta.dart';
import 'note.dart';

/// The canonical-content formats, as the schema spells them.
enum NoteFormat {
  delta,
  markdown;

  static NoteFormat parse(String? raw) =>
      raw == 'markdown' ? NoteFormat.markdown : NoteFormat.delta;

  String get wire => name;
}

/// A surface the editor can show.
enum NoteMode {
  /// The rendered document. Always available, whatever the note is made of.
  reading,

  /// The rich (Quill) editor — Delta-canonical notes only.
  live,

  /// The markdown source as text — markdown-canonical notes only.
  source,
}

/// Owns a note's content and the controllers that edit it.
class NoteDocument extends ChangeNotifier {
  NoteDocument({NoteDetail? note})
    : _format = NoteFormat.parse(note?.contentFormat),
      title = TextEditingController(text: note?.title ?? ''),
      quill = QuillController.basic(),
      source = TextEditingController(text: note?.contentMarkdown ?? '') {
    final delta = note?.contentDelta;
    if (delta != null && delta.isNotEmpty) {
      quill.document = Document.fromJson(delta);
    }
    _mode = defaultModeFor(
      _format,
      cameFromOutside: _format == NoteFormat.markdown,
    );
  }

  final TextEditingController title;

  /// Live for a Delta-canonical note. Kept alive across mode switches (D3).
  final QuillController quill;

  /// Live for a markdown-canonical note. Same lifetime, same reason.
  final TextEditingController source;

  NoteFormat _format;
  NoteFormat get format => _format;

  late NoteMode _mode;
  NoteMode get mode => _mode;

  /// D2: a document that arrived from outside opens in Reading — the first
  /// thing you do with someone else's file is read it. A note written here
  /// opens in its editor, because the first thing you do with yours is keep
  /// writing.
  static NoteMode defaultModeFor(
    NoteFormat format, {
    required bool cameFromOutside,
  }) {
    if (cameFromOutside) return NoteMode.reading;
    return format == NoteFormat.markdown ? NoteMode.source : NoteMode.live;
  }

  /// The modes this note actually offers. Never contains a mode that cannot
  /// edit its canonical content — see the D1 amendment above.
  List<NoteMode> get availableModes => [
    if (_format == NoteFormat.delta) NoteMode.live else NoteMode.source,
    NoteMode.reading,
  ];

  /// The editor mode this note offers, whichever it is.
  NoteMode get editorMode =>
      _format == NoteFormat.delta ? NoteMode.live : NoteMode.source;

  void setMode(NoteMode next) {
    if (next == _mode || !availableModes.contains(next)) return;
    _mode = next;
    notifyListeners();
  }

  /// The markdown the Reading view renders.
  ///
  /// For a markdown-canonical note this is the source itself — byte for byte,
  /// which is what makes OPH-251's "save back to the file" honest. For a
  /// Delta-canonical note it is DERIVED, and derived is fine here because
  /// nothing writes it back.
  String get markdown =>
      _format == NoteFormat.markdown ? source.text : deltaToMarkdown(deltaJson);

  List<Map<String, dynamic>> get deltaJson =>
      quill.document.toDelta().toJson().cast<Map<String, dynamic>>();

  /// Whether converting would change the note's canonical form in a way the
  /// user cannot undo by switching back.
  bool get canConvert => true;

  /// The format a conversion would produce.
  NoteFormat get convertTarget =>
      _format == NoteFormat.delta ? NoteFormat.markdown : NoteFormat.delta;

  /// Converts the note's canonical form. **One-way in effect**: going
  /// delta → markdown flattens what Delta could hold, and coming back parses
  /// what markdown can express. The caller is responsible for warning first;
  /// this method does not ask.
  void convert() {
    if (_format == NoteFormat.delta) {
      source.text = deltaToMarkdown(deltaJson);
      _format = NoteFormat.markdown;
    } else {
      quill.document = Document.fromJson(markdownToDelta(source.text));
      _format = NoteFormat.delta;
    }
    _mode = editorMode;
    notifyListeners();
  }

  /// The body fields a save should send, keyed as the API names them.
  Map<String, dynamic> bodyFor(String titleText) => {
    'title': titleText,
    'contentDelta': deltaJson,
    // Always sent: Reading renders markdown for BOTH formats, and search
    // indexes it server-side. For a markdown-canonical note it is the
    // canonical text; for a Delta one it is the export it has always been.
    'contentMarkdown': _format == NoteFormat.markdown
        ? source.text
        : '# $titleText\n\n${deltaToMarkdown(deltaJson)}',
    'contentFormat': _format.wire,
  };

  @override
  void dispose() {
    title.dispose();
    quill.dispose();
    source.dispose();
    super.dispose();
  }
}
