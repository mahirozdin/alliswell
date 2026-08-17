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

import 'dart:convert';

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

/// What the document managed to do with an uploaded file.
///
/// The caller needs to know, because [NoteInsert.attachedOnly] is the one case
/// with nothing to see in the document — the file really is attached to the
/// note, but the surface has no way to show it, and silence there reads as a
/// failed upload.
enum NoteInsert { embedded, linked, attachedOnly }

/// Owns a note's content and the controllers that edit it.
class NoteDocument extends ChangeNotifier {
  NoteDocument({NoteDetail? note})
    : _format = NoteFormat.parse(note?.contentFormat),
      title = TextEditingController(text: note?.title ?? ''),
      quill = QuillController.basic(),
      source = MdSourceController(text: note?.contentMarkdown ?? '') {
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
  final MdSourceController source;

  /// The rich editor's focus node and scroll position (OPH-270).
  ///
  /// They live here for D3's reason — one per document, outliving every mode
  /// switch — and for a sharper one: `QuillEditor.basic` **mints a new
  /// `FocusNode` and `ScrollController` every time they are not supplied**
  /// (flutter_quill 11.5.1, `editor.dart:163-164`). Since the editor is built
  /// inside a `build()`, that meant a fresh focus node on every rebuild: the
  /// caret was thrown away mid-sentence and the title — the first focusable in
  /// the tree — caught the focus. Autosave's own `setState` (the D21 indicator)
  /// is what made it happen on almost every save.
  final FocusNode quillFocus = FocusNode(debugLabel: 'note-body');
  final ScrollController quillScroll = ScrollController();

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

  /// Replaces the document's content with a note that arrived from the server
  /// (OPH-268 V7). Called ONLY when the editor is clean — a dirty editor keeps
  /// the user's text and lets the push-time three-way merge do the work.
  ///
  /// The controllers are reused rather than rebuilt: they own the focus node
  /// and the scroll position (OPH-270), and swapping them mid-screen is how
  /// the caret used to jump.
  void adoptRemote(NoteDetail note) {
    _format = NoteFormat.parse(note.contentFormat);
    if (title.text != note.title) title.text = note.title;
    final markdown = note.contentMarkdown ?? '';
    if (_format == NoteFormat.markdown) {
      if (source.text != markdown) source.text = markdown;
    } else {
      final delta = note.contentDelta;
      final incoming = delta == null || delta.isEmpty
          ? Document()
          : Document.fromJson(delta);
      if (jsonEncode(incoming.toDelta().toJson()) !=
          jsonEncode(quill.document.toDelta().toJson())) {
        quill.document = incoming;
      }
    }
    notifyListeners();
  }

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

  /// Puts an already-uploaded file into whichever surface is currently editing.
  ///
  /// Live takes a Quill `BlockEmbed`; Source takes markdown text. Three things
  /// want to do this — the toolbar's insert buttons, a dropped file, and
  /// (once OPH-256 lands) a pasted image — and if each decided for itself,
  /// they would drift the way the toolbar and the slash menu were about to
  /// before `mdActions()` was made the single list. The document knows which
  /// surface is canonical, so the choice lives here.
  NoteInsert insertFile({
    required String fileId,
    required String name,
    required String mime,
  }) {
    final uri = 'alliswell://file/$fileId';
    final isImage = mime.startsWith('image/');

    if (editorMode == NoteMode.source) {
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

    final BlockEmbed? embed = isImage
        ? BlockEmbed.image(uri)
        : mime.startsWith('video/')
        ? BlockEmbed.video(uri)
        : null;
    if (embed == null) return NoteInsert.attachedOnly;

    final selection = quill.selection;
    final index = selection.isValid
        ? selection.start
        : quill.document.length - 1;
    final length = selection.isValid ? selection.end - selection.start : 0;
    quill.replaceText(
      index,
      length,
      embed,
      TextSelection.collapsed(offset: index + 1),
    );
    return NoteInsert.embedded;
  }

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
    quillFocus.dispose();
    quillScroll.dispose();
    super.dispose();
  }
}

/// The Source-mode text controller, with focus mode built in (DESIGN §29 D23).
///
/// A subclass rather than a second controller: D3 keeps ONE controller alive
/// for the document's whole life, so focus mode has to be a property of that
/// controller, not a swap.
///
/// "Focus mode dims, it does not hide." Everything outside the paragraph
/// holding the caret fades; nothing leaves the layout, because removing text
/// reflows the page and reflow is what makes a focus mode unusable.
class MdSourceController extends TextEditingController {
  MdSourceController({super.text});

  bool _focusMode = false;
  bool get focusMode => _focusMode;
  set focusMode(bool value) {
    if (value == _focusMode) return;
    _focusMode = value;
    notifyListeners();
  }

  /// The paragraph around [offset] — bounded by blank lines, the way markdown
  /// itself decides where a paragraph ends.
  ({int start, int end}) paragraphAt(int offset) {
    final caret = offset.clamp(0, text.length);
    var start = 0;
    var end = text.length;
    final breakRe = RegExp(r'\n[ \t]*\n');
    for (final match in breakRe.allMatches(text)) {
      if (match.end <= caret) {
        start = match.end;
      } else {
        end = match.start;
        break;
      }
    }
    return (start: start, end: end);
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (!_focusMode || text.isEmpty) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    final range = paragraphAt(
      selection.baseOffset < 0 ? 0 : selection.baseOffset,
    );
    final dim = (style ?? const TextStyle()).copyWith(
      color: (style?.color ?? Theme.of(context).colorScheme.onSurface)
          .withValues(alpha: 0.35),
    );
    return TextSpan(
      style: style,
      children: [
        if (range.start > 0)
          TextSpan(text: text.substring(0, range.start), style: dim),
        TextSpan(text: text.substring(range.start, range.end), style: style),
        if (range.end < text.length)
          TextSpan(text: text.substring(range.end), style: dim),
      ],
    );
  }
}
