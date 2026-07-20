import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../core/linkify.dart';

/// Body text whose URLs are tappable (round 8, OPH-164). Owns and disposes the
/// tap recognizers — `TextSpan` recognizers leak if nobody does.
class LinkifiedText extends StatefulWidget {
  const LinkifiedText(this.text, {super.key, required this.onOpen, this.style});

  final String text;
  final void Function(Uri uri) onOpen;
  final TextStyle? style;

  @override
  State<LinkifiedText> createState() => _LinkifiedTextState();
}

class _LinkifiedTextState extends State<LinkifiedText> {
  final List<TapGestureRecognizer> _recognizers = [];

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final theme = Theme.of(context);
    final base = widget.style ?? theme.textTheme.bodyMedium;
    final linkStyle = base?.copyWith(
      color: theme.colorScheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: theme.colorScheme.primary,
    );
    return Text.rich(
      TextSpan(
        children: [
          for (final segment in linkifySegments(widget.text))
            if (segment.uri == null)
              TextSpan(text: segment.text, style: base)
            else
              TextSpan(
                text: segment.text,
                style: linkStyle,
                recognizer: () {
                  final uri = segment.uri!;
                  final recognizer = TapGestureRecognizer()
                    ..onTap = () => widget.onOpen(uri);
                  _recognizers.add(recognizer);
                  return recognizer;
                }(),
              ),
        ],
      ),
    );
  }
}
