import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../core/deep_link.dart';

/// AI output is text, not surface (DESIGN §24 AI6): plain text + minimal
/// markdown, NO HTML, NO auto-opened links. The only tappable links are
/// `alliswell://` URIs that resolve through [awRouteForUri] (navigation-only,
/// ADR-0016); every other URL renders as inert, selectable text — which
/// removes the exfiltration-tap leg entirely.
///
/// [parseAiSpans] is pure and unit-tested; the widget just renders it.
class AiText extends StatefulWidget {
  const AiText(this.text, {super.key, this.onNavigate, this.style});

  final String text;

  /// Called with a resolved in-app route (e.g. `/tasks/<id>`) when an
  /// `alliswell://` chip is tapped. Never receives an external URL.
  final void Function(String route)? onNavigate;
  final TextStyle? style;

  @override
  State<AiText> createState() => _AiTextState();
}

class _AiTextState extends State<AiText> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();

    final base = widget.style ?? DefaultTextStyle.of(context).style;
    final scheme = Theme.of(context).colorScheme;
    final spans = <InlineSpan>[];

    for (final token in parseAiSpans(widget.text)) {
      switch (token) {
        case AiSpanText(:final text, :final bold, :final italic, :final code):
          spans.add(
            TextSpan(
              text: text,
              style: base.copyWith(
                fontWeight: bold ? FontWeight.w700 : null,
                fontStyle: italic ? FontStyle.italic : null,
                fontFamily: code ? 'monospace' : null,
                backgroundColor: code ? scheme.surfaceContainerHighest : null,
              ),
            ),
          );
        case AiSpanNavLink(:final label, :final route):
          final recognizer = TapGestureRecognizer()
            ..onTap = () => widget.onNavigate?.call(route);
          _recognizers.add(recognizer);
          spans.add(
            TextSpan(
              text: label,
              style: base.copyWith(
                color: scheme.primary,
                decoration: TextDecoration.underline,
              ),
              recognizer: recognizer,
            ),
          );
      }
    }

    // SelectionArea lets the user copy any inert URL text — reading, not
    // launching, is the only affordance for external links.
    return SelectionArea(child: Text.rich(TextSpan(children: spans)));
  }
}

sealed class AiSpan {
  const AiSpan();
}

class AiSpanText extends AiSpan {
  const AiSpanText(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.code = false,
  });
  final String text;
  final bool bold;
  final bool italic;
  final bool code;
}

class AiSpanNavLink extends AiSpan {
  const AiSpanNavLink({required this.label, required this.route});
  final String label;
  final String route;
}

final _boldPattern = RegExp(r'\*\*(.+?)\*\*');
final _italicPattern = RegExp(r'(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)');
final _codePattern = RegExp(r'`([^`]+)`');
final _alliswellUri = RegExp(r'alliswell://[^\s)]+');

/// Pure: turns model output into a flat list of renderable spans. HTML is
/// never interpreted; `alliswell://` URIs that resolve become nav links, all
/// other text (including http(s) URLs) stays plain.
List<AiSpan> parseAiSpans(String input) {
  final spans = <AiSpan>[];

  // First pass: split out alliswell:// nav links (the only tappable thing).
  var cursor = 0;
  for (final match in _alliswellUri.allMatches(input)) {
    if (match.start > cursor) {
      spans.addAll(_inlineMarkdown(input.substring(cursor, match.start)));
    }
    final uri = Uri.tryParse(match.group(0)!);
    final route = uri == null ? null : awRouteForUri(uri);
    if (route != null && !awIsBackgroundAction(uri!)) {
      spans.add(AiSpanNavLink(label: match.group(0)!, route: route));
    } else {
      // Unresolvable / background-action scheme → inert text, never tappable.
      spans.add(AiSpanText(match.group(0)!));
    }
    cursor = match.end;
  }
  if (cursor < input.length) {
    spans.addAll(_inlineMarkdown(input.substring(cursor)));
  }
  return spans;
}

/// Applies bold/italic/code to a plain run. Non-overlapping, left to right.
List<AiSpan> _inlineMarkdown(String text) {
  final spans = <AiSpan>[];
  var remaining = text;

  while (remaining.isNotEmpty) {
    final bold = _boldPattern.firstMatch(remaining);
    final italic = _italicPattern.firstMatch(remaining);
    final code = _codePattern.firstMatch(remaining);
    final matches = [
      if (bold != null) (bold, 'bold'),
      if (italic != null) (italic, 'italic'),
      if (code != null) (code, 'code'),
    ]..sort((a, b) => a.$1.start.compareTo(b.$1.start));

    if (matches.isEmpty) {
      spans.add(AiSpanText(remaining));
      break;
    }
    final (match, kind) = matches.first;
    if (match.start > 0) {
      spans.add(AiSpanText(remaining.substring(0, match.start)));
    }
    spans.add(
      AiSpanText(
        match.group(1)!,
        bold: kind == 'bold',
        italic: kind == 'italic',
        code: kind == 'code',
      ),
    );
    remaining = remaining.substring(match.end);
  }
  return spans;
}
