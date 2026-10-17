import 'package:flutter/material.dart';

import '../../../theme/tokens.dart';

/// The quick-add field's controller (OPH-373, DESIGN §39 Q2): it paints the
/// ranges the offline parser recognized in the link ink, semibold, so the
/// user sees what will become a date, tag or priority before pressing Enter.
///
/// While the IME is composing (Turkish keyboards, Android Gboard, iOS marked
/// text) it draws the plain text: restyling the composing region swaps the
/// span the platform is editing and loses or doubles letters (LESSONS
/// flutter-app). Highlighting resumes as soon as the word is committed.
class QuickAddTextController extends TextEditingController {
  QuickAddTextController({super.text});

  List<TextRange> _recognized = const [];

  List<TextRange> get recognized => _recognized;

  set recognized(List<TextRange> ranges) {
    if (_same(ranges, _recognized)) return;
    _recognized = List.unmodifiable(ranges);
    notifyListeners();
  }

  static bool _same(List<TextRange> a, List<TextRange> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final composing = value.composing;
    final text = value.text;
    final ranges = [
      for (final r in _recognized)
        if (r.isValid && r.start < r.end && r.end <= text.length) r,
    ]..sort((a, b) => a.start - b.start);
    if (ranges.isEmpty || (composing.isValid && !composing.isCollapsed)) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    // `tokens.link` on the input fill is a measured pair (contrast.py
    // "link on raised container": 4.5+ in both themes).
    final mark = (style ?? const TextStyle()).copyWith(
      color: context.awTokens.link,
      fontWeight: FontWeight.w600,
    );
    final children = <TextSpan>[];
    var at = 0;
    for (final r in ranges) {
      if (r.start < at) continue; // overlapping — keep the first
      if (r.start > at) {
        children.add(TextSpan(text: text.substring(at, r.start)));
      }
      children.add(TextSpan(text: text.substring(r.start, r.end), style: mark));
      at = r.end;
    }
    if (at < text.length) children.add(TextSpan(text: text.substring(at)));
    return TextSpan(style: style, children: children);
  }
}
