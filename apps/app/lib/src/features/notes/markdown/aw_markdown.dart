/// The reading view (DESIGN §29 D6–D12, OPH-247).
///
/// One entry point over the AST + source map that `md_parse.dart` produces.
/// Everything a document can contain is drawn here or handed to a sibling
/// widget; nothing is silently dropped, which is the promise D11 makes and
/// §28 M2 made before it.
///
/// **Stateful on purpose.** A document is full of links, and every tappable
/// `TextSpan` needs a `TapGestureRecognizer` that somebody disposes —
/// `LinkifiedText` learned this the hard way and says so in its own comment
/// ("`TextSpan` recognizers leak if nobody does"). A README has hundreds of
/// them, so this widget owns the list and clears it on every rebuild.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;

import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import 'md_callout.dart';
import 'md_code_block.dart';
import 'md_parse.dart';
import 'md_security.dart';
import 'md_syntaxes.dart';
import 'md_table.dart';
import 'md_theme.dart';
import 'md_unsupported.dart';

/// How a rendered document reaches the outside world.
typedef MdLinkTap = void Function(Uri uri);

/// A tap on an image. The source is passed verbatim — an `alliswell://file/{id}`
/// embed, an absolute URL, or a relative path the caller may or may not be able
/// to resolve.
typedef MdImageTap = void Function(String source);

class AwMarkdown extends StatefulWidget {
  const AwMarkdown({
    super.key,
    required this.document,
    this.onOpenLink,
    this.onTapImage,
    this.padding = const EdgeInsets.symmetric(horizontal: AwSpace.x5),
    this.shrinkWrap = false,
  });

  final MdDocument document;
  final MdLinkTap? onOpenLink;
  final MdImageTap? onTapImage;
  final EdgeInsets padding;

  /// Tests and short embeds want the whole document laid out at once; a real
  /// README wants the lazy list. Both go through the same block builders.
  final bool shrinkWrap;

  @override
  State<AwMarkdown> createState() => _AwMarkdownState();
}

class _AwMarkdownState extends State<AwMarkdown> {
  final List<TapGestureRecognizer> _recognizers = [];

  void _clearRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _clearRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _clearRecognizers();
    final styles = MdStyles.of(context);
    final blocks = widget.document.blocks;

    if (widget.shrinkWrap) {
      return Padding(
        padding: widget.padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [for (final block in blocks) _block(block, styles)],
        ),
      );
    }

    // Lazy by block: a 2 000-line README should not build every paragraph to
    // show its first screen. The list stays INDEXABLE by block, which is what
    // OPH-249 needs to jump to a heading — the scroll mechanism is that task's
    // choice, not this one's.
    return ListView.builder(
      padding: widget.padding,
      itemCount: blocks.length,
      itemBuilder: (_, i) => _block(blocks[i], styles),
    );
  }

  // ── blocks ────────────────────────────────────────────────────────────────

  Widget _block(MdBlock block, MdStyles styles) {
    final node = block.node;
    if (node is! md.Element) {
      final text = node.textContent.trim();
      if (text.isEmpty) return const SizedBox.shrink();
      return _paragraph([node], styles);
    }
    return _element(node, styles, block);
  }

  Widget _element(md.Element el, MdStyles styles, MdBlock block) {
    final children = el.children ?? const <md.Node>[];

    switch (el.tag) {
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        final level = int.parse(el.tag.substring(1));
        return Padding(
          padding: EdgeInsets.only(
            top: level <= 2 ? AwSpace.x6 : AwSpace.x4,
            bottom: AwSpace.x2,
          ),
          child: Text.rich(
            TextSpan(
              children: _inline(children, styles.headingFor(level), styles),
            ),
          ),
        );

      case 'p':
        return _paragraph(children, styles);

      case 'pre':
        final code = children.whereType<md.Element>().firstOrNull;
        final language = (code?.attributes['class'] ?? '').replaceFirst(
          'language-',
          '',
        );
        return MdCodeBlock(
          source: code?.textContent ?? el.textContent,
          language: language.isEmpty ? null : language,
        );

      case 'blockquote':
        return Container(
          margin: const EdgeInsets.symmetric(vertical: AwSpace.x2),
          padding: const EdgeInsets.only(left: AwSpace.x3),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: styles.hairline, width: 3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final child in children)
                _block(
                  MdBlock(node: child, startLine: -1, endLine: -1),
                  styles,
                ),
            ],
          ),
        );

      case 'div':
        final kind = mdAlertKindFrom(el.attributes['class']);
        if (kind != null) {
          return MdCallout(
            kind: kind,
            children: [
              for (final child in children)
                // Drop the parser's own English title paragraph; MdCallout
                // draws the localised label itself.
                if (!_isAlertTitle(child))
                  _block(
                    MdBlock(node: child, startLine: -1, endLine: -1),
                    styles,
                  ),
            ],
          );
        }
        return _paragraph(children, styles);

      case 'ul' || 'ol':
        return _list(el, styles, ordered: el.tag == 'ol');

      case 'table':
        return _table(el, styles);

      case 'hr':
        return Divider(height: AwSpace.x8, color: styles.hairline);

      case 'section':
        // The synthesised footnote container.
        return Padding(
          padding: const EdgeInsets.only(top: AwSpace.x6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Divider(color: styles.hairline),
              for (final child in children)
                _block(
                  MdBlock(node: child, startLine: -1, endLine: -1),
                  styles,
                ),
            ],
          ),
        );

      case kMdFrontMatter:
        return _FrontMatterStrip(source: el.textContent);

      case kMdMathBlock:
        return _mathBlock(el.textContent, styles);

      case kMdRawHtml:
        return MdRawHtmlBlock(source: el.textContent);

      case 'li':
        return _paragraph(children, styles);

      default:
        // Nothing is dropped silently — an unknown block shows its source and
        // says so (D11). If this fires often it is a gap, not a fallback.
        return MdUnsupportedBlock(
          reason: 'markdown.unsupportedBlock'.tr(),
          source: sourceOf(widget.document, block),
        );
    }
  }

  bool _isAlertTitle(md.Node node) =>
      node is md.Element && node.attributes['class'] == kMdAlertTitleClass;

  Widget _paragraph(List<md.Node> nodes, MdStyles styles) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AwSpace.x1),
    child: Text.rich(TextSpan(children: _inline(nodes, styles.body, styles))),
  );

  Widget _list(md.Element el, MdStyles styles, {required bool ordered}) {
    final items = (el.children ?? const <md.Node>[])
        .whereType<md.Element>()
        .where((e) => e.tag == 'li')
        .toList();

    return Padding(
      padding: const EdgeInsets.only(left: AwSpace.x2, top: AwSpace.x1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < items.length; i++)
            _listItem(items[i], styles, ordered: ordered, index: i),
        ],
      ),
    );
  }

  Widget _listItem(
    md.Element li,
    MdStyles styles, {
    required bool ordered,
    required int index,
  }) {
    final children = li.children ?? const <md.Node>[];
    // GFM task lists arrive as a leading `<input type="checkbox">`.
    final checkbox = children
        .whereType<md.Element>()
        .where((e) => e.tag == 'input')
        .firstOrNull;
    final checked = checkbox?.attributes['checked'] == 'true';
    final rest = children.where((n) => !identical(n, checkbox)).toList();

    // Nested lists are blocks, not inline content — they get their own row.
    final nested = rest
        .whereType<md.Element>()
        .where((e) => e.tag == 'ul' || e.tag == 'ol')
        .toList();
    final inlinePart = rest.where((n) => !nested.contains(n)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 26,
              child: checkbox != null
                  ? Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(
                        checked
                            ? Icons.check_box_outlined
                            : Icons.check_box_outline_blank,
                        size: 18,
                        color: checked ? styles.tokens.success : styles.muted,
                      ),
                    )
                  : Text(
                      ordered ? '${index + 1}.' : '•',
                      style: styles.body.copyWith(color: styles.muted),
                    ),
            ),
            Expanded(
              child: Text.rich(
                TextSpan(children: _inline(inlinePart, styles.body, styles)),
              ),
            ),
          ],
        ),
        for (final child in nested)
          Padding(
            padding: const EdgeInsets.only(left: AwSpace.x4),
            child: _list(child, styles, ordered: child.tag == 'ol'),
          ),
      ],
    );
  }

  Widget _table(md.Element el, MdStyles styles) {
    final header = <MdTableCell>[];
    final rows = <List<MdTableCell>>[];

    for (final section
        in (el.children ?? const <md.Node>[]).whereType<md.Element>()) {
      for (final tr
          in (section.children ?? const <md.Node>[])
              .whereType<md.Element>()
              .where((e) => e.tag == 'tr')) {
        final cells = <MdTableCell>[
          for (final cell
              in (tr.children ?? const <md.Node>[]).whereType<md.Element>())
            MdTableCell(
              align: cell.attributes['align'],
              content: Text.rich(
                TextSpan(
                  children: _inline(
                    cell.children ?? const <md.Node>[],
                    styles.body,
                    styles,
                  ),
                ),
              ),
            ),
        ];
        if (section.tag == 'thead' && header.isEmpty) {
          header.addAll(cells);
        } else {
          rows.add(cells);
        }
      }
    }
    return MdTable(header: header, rows: rows);
  }

  Widget _mathBlock(String tex, MdStyles styles) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AwSpace.x3),
    child: Center(
      child: Math.tex(
        tex,
        mathStyle: MathStyle.display,
        textStyle: styles.body,
        // D11 at formula scale: an expression we cannot typeset shows itself
        // and says why, instead of leaving a hole in the page.
        onErrorFallback: (error) => MdUnsupportedBlock(
          icon: Icons.functions,
          reason: 'markdown.badMath'.tr(),
          source: tex,
        ),
      ),
    ),
  );

  // ── inline ────────────────────────────────────────────────────────────────

  /// Builds inline spans.
  ///
  /// [recognizer] is threaded down rather than attached to a wrapping span,
  /// because Flutter's hit testing resolves an offset to the innermost span
  /// that carries **text** — a parent that only has `children` is never the
  /// one that gets tapped. A link whose recognizer sits on the wrapper looks
  /// like a link and does nothing, which is the failure mode D10's tests
  /// exist to catch.
  List<InlineSpan> _inline(
    List<md.Node> nodes,
    TextStyle base,
    MdStyles styles, {
    GestureRecognizer? recognizer,
  }) {
    final spans = <InlineSpan>[];
    for (final node in nodes) {
      if (node is md.Text) {
        spans.add(
          TextSpan(text: node.textContent, style: base, recognizer: recognizer),
        );
        continue;
      }
      if (node is! md.Element) continue;
      final children = node.children ?? const <md.Node>[];

      switch (node.tag) {
        case 'strong':
          spans.addAll(
            _inline(
              children,
              base.copyWith(fontWeight: FontWeight.w700),
              styles,
              recognizer: recognizer,
            ),
          );
        case 'em':
          spans.addAll(
            _inline(
              children,
              base.copyWith(fontStyle: FontStyle.italic),
              styles,
              recognizer: recognizer,
            ),
          );
        case 'del':
          spans.addAll(
            _inline(
              children,
              base.copyWith(decoration: TextDecoration.lineThrough),
              styles,
              recognizer: recognizer,
            ),
          );
        case 'mark':
          spans.addAll(
            _inline(
              children,
              base.copyWith(
                backgroundColor: styles.tokens.warning.withValues(alpha: 0.28),
              ),
              styles,
              recognizer: recognizer,
            ),
          );
        case 'code':
          spans.add(
            TextSpan(
              text: node.textContent,
              recognizer: recognizer,
              style: styles.code.copyWith(
                backgroundColor: styles.codePanel,
                fontSize: base.fontSize != null ? base.fontSize! * 0.92 : null,
              ),
            ),
          );
        case 'a':
          spans.addAll(_link(node, base, styles));
        case 'img':
          spans.add(_image(node, styles));
        case 'br':
          spans.add(const TextSpan(text: '\n'));
        // `kMdMathBlock` reaches the INLINE builder too: `$$x$$` written on one
        // line is an inline node, not a block. Same engine, display style.
        case kMdMathInline || kMdMathBlock:
          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Math.tex(
                node.textContent,
                mathStyle: node.tag == kMdMathBlock
                    ? MathStyle.display
                    : MathStyle.text,
                textStyle: base,
                // Inline, a failed formula falls back to its own source rather
                // than to the full D11 card — a boxed explanation in the middle
                // of a sentence would break the paragraph it is explaining.
                onErrorFallback: (_) => Text(
                  node.textContent,
                  style: styles.code.copyWith(color: styles.muted),
                ),
              ),
            ),
          );
        case 'sup':
          spans.addAll(
            _inline(
              children,
              base.copyWith(
                fontSize: base.fontSize != null ? base.fontSize! * 0.75 : null,
              ),
              styles,
              recognizer: recognizer,
            ),
          );
        default:
          spans.addAll(_inline(children, base, styles, recognizer: recognizer));
      }
    }
    return spans;
  }

  List<InlineSpan> _link(md.Element node, TextStyle base, MdStyles styles) {
    final href = node.attributes['href'];
    final children = node.children ?? const <md.Node>[];

    // D10: a scheme we do not allow is not a link. It renders as ordinary
    // text, with no recognizer at all — not as a styled span that swallows
    // taps, which would be a different lie.
    if (!isSafeMarkdownLink(href)) {
      return _inline(children, base, styles);
    }

    final style = base.copyWith(
      color: styles.link,
      decoration: TextDecoration.underline,
      decorationColor: styles.link,
    );

    final onOpen = widget.onOpenLink;
    final uri = Uri.tryParse(href!.trim());
    if (onOpen == null || uri == null) {
      return _inline(children, style, styles);
    }

    final recognizer = TapGestureRecognizer()..onTap = () => onOpen(uri);
    _recognizers.add(recognizer);
    return _inline(children, style, styles, recognizer: recognizer);
  }

  InlineSpan _image(md.Element node, MdStyles styles) {
    final source = node.attributes['src'] ?? '';
    final alt = node.attributes['alt'] ?? '';
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: MdImage(source: source, alt: alt, onTap: widget.onTapImage),
    );
  }
}

/// A YAML front-matter block, rendered as a compact strip (D12).
///
/// Not parsed as YAML — this shows the keys a document declares, it does not
/// interpret them. Dumping it as body text is what makes an app look broken on
/// the first screen of every Jekyll file, which is the whole point of the rule.
class _FrontMatterStrip extends StatelessWidget {
  const _FrontMatterStrip({required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    final styles = MdStyles.of(context);
    final lines = source
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.startsWith('#'))
        .toList();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AwSpace.x4),
      padding: const EdgeInsets.all(AwSpace.x3),
      decoration: BoxDecoration(
        color: styles.scheme.surfaceContainerLow,
        borderRadius: const BorderRadius.all(Radius.circular(AwRadius.m)),
        border: Border.all(color: styles.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'markdown.frontMatter'.tr(),
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: styles.muted),
          ),
          const SizedBox(height: AwSpace.x1),
          for (final line in lines)
            Text(line, style: styles.code.copyWith(fontSize: 12)),
        ],
      ),
    );
  }
}

/// An image inside a document.
///
/// Placeholder-first: OPH-247 renders alt text and hands the tap upward. The
/// real pixels land in the same viewer everything else uses — but resolving a
/// source needs to know whether it is a file id, a URL or a path relative to a
/// document's folder, and the last of those only has an answer once external
/// files carry their base directory (OPH-251).
class MdImage extends StatelessWidget {
  const MdImage({super.key, required this.source, this.alt = '', this.onTap});

  final String source;
  final String alt;
  final MdImageTap? onTap;

  @override
  Widget build(BuildContext context) {
    final styles = MdStyles.of(context);
    final relative = !Uri.parse(source).hasScheme && !source.startsWith('/');

    return Semantics(
      label: alt.isEmpty ? null : alt,
      image: true,
      child: InkWell(
        onTap: onTap == null ? null : () => onTap!(source),
        borderRadius: const BorderRadius.all(Radius.circular(AwRadius.s)),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AwSpace.x2,
            vertical: AwSpace.x1,
          ),
          decoration: BoxDecoration(
            color: styles.scheme.surfaceContainer,
            borderRadius: const BorderRadius.all(Radius.circular(AwRadius.s)),
            border: Border.all(color: styles.hairline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                relative ? Icons.link_off_outlined : Icons.image_outlined,
                size: 16,
                color: styles.muted,
              ),
              const SizedBox(width: AwSpace.x1),
              Flexible(
                child: Text(
                  alt.isNotEmpty
                      ? alt
                      : (relative
                            ? 'markdown.relativeImage'.tr()
                            : 'markdown.image'.tr()),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: styles.muted),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
