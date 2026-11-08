import 'package:flutter/material.dart';

/// A segment's label that never breaks inside a word (OPH-407, DESIGN §45).
///
/// A [SegmentedButton] gives each segment an equal share of the width and
/// lets its label wrap, so a long word on a narrow phone or at a large text
/// size fell to a second line in the middle ("Standar / t"). This keeps the
/// label on one line and, when it does not fit, draws it smaller rather than
/// cutting it.
class AwSegmentLabel extends StatelessWidget {
  const AwSegmentLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(text, maxLines: 1, softWrap: false),
    );
  }
}
