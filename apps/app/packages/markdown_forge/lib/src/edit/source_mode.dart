/// Editing the markdown as text (DESIGN §29 D1/D5, OPH-248).
///
/// Before this there was no way to edit raw markdown at ALL — the old
/// "preview" was a read-only monospace sheet. This is the surface a person
/// reaches for when the rich editor is in the way.
///
/// The split view lives here rather than being a fourth mode (D5): it is a
/// toggle INSIDE Source, shown only at ≥ 900 px, because on a phone two
/// columns are two useless columns.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'find_replace_bar.dart';
import 'md_command_palette.dart';
import 'md_highlight.dart';
import 'md_toolbar.dart';

import 'md_actions.dart';
import 'md_bottom_room.dart';
import 'md_editing.dart';
import '../render/markdown_view.dart';
import '../render/md_parse.dart';
import '../seams.dart';

/// Below this the split view is not offered at all (D5).
const double kNoteSplitBreakpoint = 900;

class SourceMode extends StatefulWidget {
  const SourceMode({
    super.key,
    required this.controller,
    this.onChanged,
    this.onPasteImage,
  });

  /// The controller, not a host's document object. `SourceMode` only ever
  /// reached through `document.source`, so taking the document meant the
  /// package knew a type it had no use for — the single line that would have
  /// made this widget unpublishable.
  final MdSourceController controller;
  final VoidCallback? onChanged;

  /// Uploads a pasted image and returns the markdown to insert. Absent = a
  /// pasted image falls back to whatever text came with it.
  final MarkdownImagePasteHandler? onPasteImage;

  @override
  State<SourceMode> createState() => _SourceModeState();
}

class _SourceModeState extends State<SourceMode> {
  final ScrollController _sourceScroll = ScrollController();
  final FocusNode _fieldFocus = FocusNode();
  final ScrollController _previewScroll = ScrollController();
  bool _split = false;
  bool _syncing = false;
  bool _finding = false;
  bool _replacing = false;
  bool _focusMode = false;
  List<MdAction> _slashMatches = const [];

  /// D17: Enter, Tab and Shift-Tab, applied to the TEXT rather than intercepted
  /// as key events on the field — one assignment per edit, so one undo.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final controller = widget.controller;
    final caret = controller.selection.baseOffset;
    if (caret < 0) return KeyEventResult.ignored;

    MdEdit? edit;
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      edit = continueList(controller.text, caret);
      if (edit != null) {
        edit = MdEdit(renumberOrderedLists(edit.text), edit.selection);
      }
    } else if (event.logicalKey == LogicalKeyboardKey.keyV &&
        (HardwareKeyboard.instance.isMetaPressed ||
            HardwareKeyboard.instance.isControlPressed)) {
      // D20. Scoped to THIS field's focus node rather than a global shortcut:
      // hijacking paste everywhere would reach the find bar and the title too.
      unawaited(_smartPaste());
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.tab) {
      final shift = HardwareKeyboard.instance.isShiftPressed;
      edit = indentListItem(controller.text, caret, outdent: shift);
    }
    if (edit == null) return KeyEventResult.ignored;

    controller.value = TextEditingValue(
      text: edit.text,
      selection: TextSelection.collapsed(offset: edit.selection),
    );
    widget.onChanged?.call();
    return KeyEventResult.handled;
  }

  /// Paste, made smart and still reversible (D20).
  ///
  /// HTML becomes markdown; an IMAGE becomes an embed; a URL dropped on a
  /// selection becomes a link. The whole new text is assigned ONCE, so a
  /// single undo restores the raw paste — "smart" paste without one-step undo
  /// is hostile.
  ///
  /// Both interesting flavours arrive through the host (`MarkdownForge`'s
  /// clipboard seam). This used to call `Clipboard.getData('text/html')`
  /// directly, which returns null on EVERY platform — Flutter's clipboard
  /// channel implements `text/plain` and nothing else — so the HTML branch had
  /// never run once and `htmlToMarkdown` was reachable only from its own unit
  /// test. One seam revives both.
  Future<void> _smartPaste() async {
    final controller = widget.controller;
    final selection = controller.selection;
    if (!selection.isValid) return;

    final clipboard = await context.mdClipboardReader();
    final onImage = widget.onPasteImage;
    if (clipboard.isEmpty || !mounted) return;

    var pasted = '';
    final bytes = clipboard.imageBytes;
    if (bytes != null && bytes.isNotEmpty && onImage != null) {
      // The upload is the host's, and it can fail or be declined; when it
      // does, fall through to the text that came with the image rather than
      // pasting nothing and leaving the user wondering.
      pasted = await onImage(bytes, clipboard.imageName) ?? '';
      if (!mounted) return;
    }
    if (pasted.isEmpty) {
      final html = clipboard.html;
      pasted = html != null && html.isNotEmpty
          ? htmlToMarkdown(html)
          : (clipboard.text ?? '');
    }
    if (pasted.isEmpty) return;

    final edit = pasteOverSelection(
      controller.text,
      selection.start,
      selection.end,
      pasted,
    );
    controller.value = TextEditingValue(
      text: edit.text,
      selection: TextSelection.collapsed(offset: edit.selection),
    );
    _onTextChanged();
  }

  void _onTextChanged() {
    widget.onChanged?.call();
    final controller = widget.controller;
    final token = slashTokenAt(
      controller.text,
      controller.selection.baseOffset,
    );
    final matches = token == null ? const <MdAction>[] : matchSlash(token);
    setState(() => _slashMatches = matches);
  }

  /// ⌘K / Ctrl+K (D18). The palette picks an action; applying it is the same
  /// single assignment every other surface makes, so it is one undo.
  Future<void> _openPalette() async {
    final action = await showMdCommandPalette(context);
    if (action == null || !mounted) return;
    applyMdAction(widget.controller, action);
    _onTextChanged();
  }

  /// Replaces the `/token` with the action's result (D19).
  void _applySlash(MdAction action) {
    final controller = widget.controller;
    final caret = controller.selection.baseOffset;
    final token = slashTokenAt(controller.text, caret);
    if (token != null) {
      controller.value = TextEditingValue(
        text: controller.text.replaceRange(caret - token.length, caret, ''),
        selection: TextSelection.collapsed(offset: caret - token.length),
      );
    }
    applyMdAction(controller, action);
    setState(() => _slashMatches = const []);
    widget.onChanged?.call();
  }

  @override
  void initState() {
    super.initState();
    _sourceScroll.addListener(() => _mirror(_sourceScroll, _previewScroll));
    _previewScroll.addListener(() => _mirror(_previewScroll, _sourceScroll));
  }

  @override
  void dispose() {
    _sourceScroll.dispose();
    _previewScroll.dispose();
    _fieldFocus.dispose();
    super.dispose();
  }

  /// Two-way scroll sync (D5), by proportion.
  ///
  /// Proportional rather than line-for-line: mapping a source LINE to a
  /// rendered offset needs each block's painted position, and the block →
  /// line map exists (OPH-247) but the offsets do not until something measures
  /// them. That measurement belongs with the outline and anchor jumps, which
  /// are OPH-249's job — so this is deliberately the simpler half, and it is
  /// marked as such rather than left looking finished.
  void _mirror(ScrollController from, ScrollController to) {
    if (_syncing || !_split) return;
    if (!from.hasClients || !to.hasClients) return;
    if (from.position.maxScrollExtent <= 0 ||
        to.position.maxScrollExtent <= 0) {
      return;
    }
    _syncing = true;
    final ratio = from.offset / from.position.maxScrollExtent;
    to.jumpTo(
      (ratio * to.position.maxScrollExtent).clamp(
        0,
        to.position.maxScrollExtent,
      ),
    );
    _syncing = false;
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= kNoteSplitBreakpoint;
    // A window that shrinks below the breakpoint must not leave the toggle on
    // with nowhere to put the second pane.
    final split = _split && wide;

    return CallbackShortcuts(
      bindings: {
        for (final action in mdActions())
          for (final activator in action.shortcuts)
            activator: () {
              applyMdAction(widget.controller, action);
              widget.onChanged?.call();
            },
        for (final activator in mdPaletteShortcuts)
          activator: () => unawaited(_openPalette()),
        ...noteFindShortcuts(
          onFind: () => setState(() {
            _finding = true;
            _replacing = false;
          }),
          onReplace: () => setState(() {
            _finding = true;
            _replacing = true;
          }),
        ),
      },
      child: Focus(
        autofocus: true,
        child: _content(wide: wide, split: split),
      ),
    );
  }

  Widget _content({required bool wide, required bool split}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_finding)
          FindReplaceBar(
            target: widget.controller,
            showReplace: _replacing,
            onClose: () => setState(() => _finding = false),
          ),
        if (wide)
          Padding(
            padding: const EdgeInsets.only(
              left: MdSpace.x5,
              bottom: MdSpace.x1,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton.icon(
                    key: const Key('note-focus-toggle'),
                    onPressed: () => setState(() {
                      _focusMode = !_focusMode;
                      widget.controller.focusMode = _focusMode;
                    }),
                    icon: Icon(
                      _focusMode
                          ? Icons.center_focus_strong
                          : Icons.center_focus_weak,
                      size: 18,
                    ),
                    label: Text(
                      _focusMode
                          ? context.mdStrings.focusOff
                          : context.mdStrings.focusOn,
                    ),
                  ),
                  TextButton.icon(
                    key: const Key('note-split-toggle'),
                    onPressed: () => setState(() => _split = !_split),
                    icon: Icon(
                      split ? Icons.vertical_split : Icons.horizontal_rule,
                      size: 18,
                    ),
                    label: Text(
                      split
                          ? context.mdStrings.splitOff
                          : context.mdStrings.splitOn,
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (_slashMatches.isNotEmpty)
          MdSlashMenu(matches: _slashMatches, onPick: _applySlash),
        Expanded(
          child: split
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _editor()),
                    const VerticalDivider(width: 1),
                    Expanded(child: _preview()),
                  ],
                )
              : _editor(),
        ),
        MdCountStrip(text: widget.controller.text),
        // The host's floating chrome, cleared ONCE for the column — otherwise
        // the count strip is the thing hidden under the bar and the editor
        // would have to clear it a second time. 0 where nothing floats.
        SizedBox(height: mdChromeInset(context)),
      ],
    );
  }

  /// Puts the caret at the end and opens the keyboard.
  ///
  /// What the blank space under the text is FOR. Space that places no caret is
  /// a dead affordance (§22), and "tap below the last line to keep writing" is
  /// the gesture every note app trains people to expect.
  void _caretToEnd() {
    _fieldFocus.requestFocus();
    widget.controller.selection = TextSelection.collapsed(
      offset: widget.controller.text.length,
    );
  }

  /// The editor, in a scroll view rather than scrolling inside itself.
  ///
  /// It used to be `expands: true`, which fills the box and scrolls the text
  /// within it — and that shape cannot express "scroll past the end" at all:
  /// `contentPadding.bottom` would carve a permanent blank strip out of the
  /// visible area instead of adding scrollable room after it, and the last line
  /// would still be pinned to the bottom of a shorter box. See
  /// `md_bottom_room.dart` for what the room is for.
  ///
  /// `minHeight` keeps the old behaviour for a SHORT note: the field still
  /// fills what is left of the screen, so tapping anywhere below the text lands
  /// in the field and the caret goes to the end, exactly as before.
  Widget _editor() => LayoutBuilder(
    builder: (context, constraints) {
      final room = mdBottomRoom(
        viewportHeight: constraints.maxHeight,
        // The chrome is cleared once for the whole column (see `build`), so
        // this is reach only — adding it twice would double the gap.
        chromeInset: 0,
        reachFraction: kMdEditorReachFraction,
      );
      final minField = (constraints.maxHeight - room).clamp(
        0.0,
        constraints.maxHeight,
      );
      return SingleChildScrollView(
        controller: _sourceScroll,
        padding: const EdgeInsets.symmetric(horizontal: MdSpace.x5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: minField),
              child: Focus(
                onKeyEvent: _onKey,
                child: TextField(
                  key: const Key('note-source-field'),
                  controller: widget.controller,
                  focusNode: _fieldFocus,
                  onChanged: (_) {
                    _onTextChanged();
                    if (_split) setState(() {}); // the preview follows the text
                  },
                  maxLines: null,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontFamilyFallback: ['Menlo', 'Consolas', 'Courier New'],
                    height: 1.5,
                  ),
                  decoration: InputDecoration(
                    hintText: context.mdStrings.sourceHint,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    isDense: true,
                  ),
                ),
              ),
            ),
            GestureDetector(
              key: const Key('note-source-tail'),
              behavior: HitTestBehavior.opaque,
              onTap: _caretToEnd,
              child: SizedBox(height: room),
            ),
          ],
        ),
      );
    },
  );

  Widget _preview() => MarkdownView(
    key: const Key('note-split-preview'),
    document: parseMarkdown(widget.controller.text),
    controller: _previewScroll,
    padding: const EdgeInsets.symmetric(horizontal: MdSpace.x5),
  );
}
