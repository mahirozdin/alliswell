/// Reading a document, with its outline (DESIGN §29 D13/D14/D16, OPH-249).
///
/// "The outline is one tap away and follows you." Sheet on a phone, side panel
/// at ≥ 900 px — the same breakpoint the split view uses, because they are the
/// same judgement about how much room a second column needs.
///
/// Folding lives here too, and deliberately as a set of SLUGS held by this
/// widget: per-session, never persisted, never written into the document. D14
/// says folding must not mutate somebody's file, and the cheapest way to keep
/// that promise is to have nowhere to write it.
library;

import 'package:flutter/material.dart';

import 'markdown_view.dart';
import 'md_outline.dart';
import 'md_parse.dart';
import 'md_scroll.dart';
import 'md_theme.dart';
import '../seams.dart';

/// The width at which the outline becomes a panel instead of a sheet.
const double kNoteOutlineBreakpoint = 900;

class ReadingMode extends StatefulWidget {
  const ReadingMode({
    super.key,
    required this.markdown,
    this.onOpenLink,
    this.onTapImage,
  });

  final String markdown;
  final void Function(Uri uri)? onOpenLink;

  /// A tap on an image, with the document's whole gallery in body order and
  /// the index that was tapped. The host opens its own viewer.
  final MdImageTap? onTapImage;

  @override
  State<ReadingMode> createState() => _ReadingModeState();
}

class _ReadingModeState extends State<ReadingMode> {
  final AwMarkdownController _controller = AwMarkdownController();

  /// Collapsed section slugs. Session-only by construction (D14).
  final Set<String> _collapsed = {};

  late MdDocument _doc;
  late List<MdHeading> _headings;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScrolled);
  }

  // NOT initState: the heading slugs come from the host's fold, which arrives
  // by InheritedWidget (`MarkdownStrings.of`), and Flutter forbids reading one
  // from initState. didChangeDependencies is the frame-one place that MAY —
  // and it re-runs if the host swaps the strings, which is exactly when slugs
  // must be recomputed anyway.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _parse();
  }

  @override
  void didUpdateWidget(ReadingMode old) {
    super.didUpdateWidget(old);
    if (old.markdown != widget.markdown) _parse();
  }

  void _parse() {
    _doc = parseMarkdown(widget.markdown);
    _headings = outlineHeadings(_doc, fold: context.mdStrings.fold);
    // A heading that no longer exists cannot stay folded — otherwise editing a
    // title would hide a section nobody can unhide.
    _collapsed.removeWhere((slug) => !_headings.any((h) => h.slug == slug));
  }

  void _onScrolled() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onScrolled)
      ..dispose();
    super.dispose();
  }

  Future<void> _goTo(MdHeading heading) =>
      _controller.jumpToBlock(_visibleIndexOf(heading.blockIndex));

  /// The heading's position in the list AS RENDERED — collapsed sections are
  /// not in it, so the raw block index would overshoot.
  int _visibleIndexOf(int blockIndex) {
    if (_collapsed.isEmpty) return blockIndex;
    final hidden = <int>{};
    for (final heading in _headings) {
      if (!_collapsed.contains(heading.slug)) continue;
      final range = foldedRangeFor(_doc, _headings, heading);
      for (var i = range.start; i < range.end; i++) {
        hidden.add(i);
      }
    }
    var visible = 0;
    for (var i = 0; i < blockIndex; i++) {
      if (!hidden.contains(i)) visible++;
    }
    return visible;
  }

  /// A `#anchor` tap (D16). Resolved through our own slugs, not the parser's —
  /// its generator drops Turkish letters entirely.
  bool _handleAnchor(Uri uri) {
    if (!uri.hasScheme && uri.fragment.isNotEmpty && uri.path.isEmpty) {
      final heading = headingForAnchor(
        _headings,
        fold: context.mdStrings.fold,
        uri.fragment,
      );
      if (heading != null) {
        _goTo(heading);
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= kNoteOutlineBreakpoint;
    final current = headingAt(_headings, _controller.firstVisibleBlock);

    final document = MarkdownView(
      key: const Key('note-reading'),
      document: _doc,
      markdownController: _controller,
      collapsed: _collapsed,
      onOpenLink: (uri) {
        if (_handleAnchor(uri)) return;
        widget.onOpenLink?.call(uri);
      },
      onTapImage: widget.onTapImage,
    );

    if (!wide) {
      // The phone's way in (D13). A small floating affordance rather than an
      // app-bar action: the outline belongs to the reading view, and the shell
      // that owns the bar does not know this document's headings.
      return Stack(
        children: [
          document,
          if (_headings.isNotEmpty)
            Positioned(
              right: MdSpace.x3,
              bottom: MdSpace.x3,
              child: FloatingActionButton.small(
                key: const Key('note-outline-button'),
                heroTag: 'note-outline',
                tooltip: context.mdStrings.outline,
                onPressed: () => showOutlineSheet(
                  context,
                  headings: _headings,
                  current: current,
                  onTap: _goTo,
                ),
                child: const Icon(Icons.list_alt_outlined),
              ),
            ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 260,
          child: _OutlinePanel(
            headings: _headings,
            current: current,
            collapsed: _collapsed,
            onTap: _goTo,
            onToggleFold: _toggleFold,
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: document),
      ],
    );
  }

  void _toggleFold(MdHeading heading) => setState(() {
    if (!_collapsed.remove(heading.slug)) _collapsed.add(heading.slug);
  });

  /// The phone's way in (D13): the same tree, in a sheet.
  static Future<void> showOutlineSheet(
    BuildContext context, {
    required List<MdHeading> headings,
    required MdHeading? current,
    required void Function(MdHeading) onTap,
  }) => showModalBottomSheet<void>(
    context: context,
    // OPH-212: the ROOT navigator, like every sheet in this app.
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (sheetContext) => _OutlinePanel(
      headings: headings,
      current: current,
      collapsed: const {},
      onTap: (heading) {
        Navigator.of(sheetContext).pop();
        onTap(heading);
      },
    ),
  );
}

class _OutlinePanel extends StatelessWidget {
  const _OutlinePanel({
    required this.headings,
    required this.current,
    required this.collapsed,
    required this.onTap,
    this.onToggleFold,
  });

  final List<MdHeading> headings;
  final MdHeading? current;
  final Set<String> collapsed;
  final void Function(MdHeading) onTap;
  final void Function(MdHeading)? onToggleFold;

  @override
  Widget build(BuildContext context) {
    final styles = MdStyles.of(context);
    if (headings.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(MdSpace.x4),
          child: Text(
            context.mdStrings.noHeadings,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: styles.muted),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.builder(
      key: const Key('note-outline'),
      padding: const EdgeInsets.symmetric(vertical: MdSpace.x2),
      itemCount: headings.length,
      itemBuilder: (context, i) {
        final heading = headings[i];
        final active = heading.slug == current?.slug;
        return InkWell(
          onTap: () => onTap(heading),
          child: Container(
            padding: EdgeInsets.only(
              left: MdSpace.x3 + (heading.level - 1) * 12.0,
              right: MdSpace.x2,
              top: MdSpace.x2,
              bottom: MdSpace.x2,
            ),
            decoration: BoxDecoration(
              color: active
                  ? styles.scheme.primary.withValues(alpha: 0.10)
                  : null,
              border: Border(
                left: BorderSide(
                  color: active ? styles.scheme.primary : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            child: Row(
              children: [
                if (onToggleFold != null)
                  InkWell(
                    key: Key('outline-fold-${heading.slug}'),
                    onTap: () => onToggleFold!(heading),
                    child: Padding(
                      padding: const EdgeInsets.only(right: MdSpace.x1),
                      child: Icon(
                        collapsed.contains(heading.slug)
                            ? Icons.chevron_right
                            : Icons.expand_more,
                        size: 16,
                        color: styles.muted,
                      ),
                    ),
                  ),
                Expanded(
                  child: Text(
                    heading.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: active ? styles.scheme.primary : null,
                      fontWeight: active ? FontWeight.w600 : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
