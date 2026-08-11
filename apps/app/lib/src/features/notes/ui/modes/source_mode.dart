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

import 'package:flutter/material.dart';

import '../../../../i18n/i18n.dart';
import '../../../../theme/tokens.dart';
import '../../../notes/markdown/aw_markdown.dart';
import '../../../notes/markdown/md_parse.dart';
import '../../data/note_document.dart';

/// Below this the split view is not offered at all (D5).
const double kNoteSplitBreakpoint = 900;

class SourceMode extends StatefulWidget {
  const SourceMode({super.key, required this.document, this.onChanged});

  final NoteDocument document;
  final VoidCallback? onChanged;

  @override
  State<SourceMode> createState() => _SourceModeState();
}

class _SourceModeState extends State<SourceMode> {
  final ScrollController _sourceScroll = ScrollController();
  final ScrollController _previewScroll = ScrollController();
  bool _split = false;
  bool _syncing = false;

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (wide)
          Padding(
            padding: const EdgeInsets.only(
              left: AwSpace.x5,
              bottom: AwSpace.x1,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('note-split-toggle'),
                onPressed: () => setState(() => _split = !_split),
                icon: Icon(
                  split ? Icons.vertical_split : Icons.horizontal_rule,
                  size: 18,
                ),
                label: Text(split ? 'note.splitOff'.tr() : 'note.splitOn'.tr()),
              ),
            ),
          ),
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
      ],
    );
  }

  Widget _editor() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AwSpace.x5),
    child: TextField(
      key: const Key('note-source-field'),
      controller: widget.document.source,
      scrollController: _sourceScroll,
      onChanged: (_) {
        widget.onChanged?.call();
        if (_split) setState(() {}); // the preview follows the text
      },
      maxLines: null,
      expands: true,
      textAlignVertical: TextAlignVertical.top,
      style: const TextStyle(
        fontFamily: 'monospace',
        fontFamilyFallback: ['Menlo', 'Consolas', 'Courier New'],
        height: 1.5,
      ),
      decoration: InputDecoration(
        hintText: 'note.sourceHint'.tr(),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        filled: false,
        isDense: true,
      ),
    ),
  );

  Widget _preview() => AwMarkdown(
    key: const Key('note-split-preview'),
    document: parseMarkdown(widget.document.source.text),
    controller: _previewScroll,
    padding: const EdgeInsets.symmetric(horizontal: AwSpace.x5),
  );
}
