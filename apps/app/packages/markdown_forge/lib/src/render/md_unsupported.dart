/// "This block could not be drawn, and here is why" (DESIGN §29 D11, §10 F3).
///
/// The rule exists because a missing diagram that leaves a gap is
/// indistinguishable from a bug — and because round 17 was full of features
/// that were shipped, rendered and invisible. A blank is a lie; a box that
/// shows the source and names the reason is not.
///
/// It is NOT `AwInlineError`: that widget is a form-validation band on an error
/// container, and an unrenderable diagram is not an error the reader made. The
/// anatomy is borrowed (icon + message on a tinted band), the semantics are not.
library;

import 'package:flutter/material.dart';

import 'md_theme.dart';
import '../seams.dart';

class MdUnsupportedBlock extends StatelessWidget {
  const MdUnsupportedBlock({
    super.key,
    required this.reason,
    required this.source,
    this.icon = Icons.description_outlined,
  });

  /// Already-localised sentence saying what happened. Two different failures
  /// must not share a sentence — "this diagram type is not drawn yet" and
  /// "this diagram could not be parsed" send the reader to different places.
  final String reason;

  /// The markdown that produced this block, shown verbatim. This is the part
  /// that keeps the document lossless: whatever we cannot draw, the reader can
  /// still read.
  final String source;

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final styles = MdStyles.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: MdSpace.x2),
      decoration: BoxDecoration(
        color: styles.scheme.surfaceContainer,
        borderRadius: const BorderRadius.all(Radius.circular(MdRadius.m)),
        border: Border.all(color: styles.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              MdSpace.x3,
              MdSpace.x3,
              MdSpace.x3,
              MdSpace.x2,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 18, color: styles.muted),
                const SizedBox(width: MdSpace.x2),
                Expanded(
                  child: Text(
                    reason,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: styles.muted),
                  ),
                ),
              ],
            ),
          ),
          if (source.trim().isNotEmpty)
            // Its own horizontal scroll (D8) — a long line inside a fallback
            // must not make the whole page scroll sideways either.
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(
                MdSpace.x3,
                0,
                MdSpace.x3,
                MdSpace.x3,
              ),
              child: SelectableText(source, style: styles.code),
            ),
        ],
      ),
    );
  }
}

/// The inert rendering of raw HTML (D10).
///
/// HTML is not made safe by escaping it into entities — it is made safe by
/// never being live. It is shown as what it is: source someone else wrote.
class MdRawHtmlBlock extends StatelessWidget {
  const MdRawHtmlBlock({super.key, required this.source});

  final String source;

  @override
  Widget build(BuildContext context) => MdUnsupportedBlock(
    icon: Icons.code_off_outlined,
    reason: context.mdStrings.rawHtml,
    source: source,
  );
}
