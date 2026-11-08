import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Zero-width space: a line-break opportunity that draws nothing.
const String kAwZwsp = '​';

final RegExp _wordGaps = RegExp('[\\s$kAwZwsp]+');

/// Text that wraps between words and never inside one (OPH-400 / R-09,
/// DESIGN §45 W8).
///
/// At the largest accessibility sizes (iOS AX3+, Android 2.0×) one long word
/// can be wider than its slot: Flutter then breaks it wherever the line runs
/// out — "Entegrasyonla / r". This measures the widest word at the reader's
/// text size and, only when that word cannot fit, draws the whole text at the
/// largest size where it does. Everything else wraps at spaces as before, so
/// a short label at 1.0× is exactly a plain [Text].
///
/// Needs a bounded width and does not answer intrinsic sizes (it is a
/// [LayoutBuilder]); use it in rows, list tiles and `Expanded` slots.
class AwWordSafeText extends StatelessWidget {
  const AwWordSafeText(
    this.text, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
    this.semanticsLabel,
  });

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaler = MediaQuery.textScalerOf(context);
        final fitted = constraints.maxWidth.isFinite
            ? awWordSafeScaler(
                context,
                text,
                style: style,
                scaler: scaler,
                maxWidth: constraints.maxWidth,
              )
            : scaler;
        return Text(
          text,
          style: style,
          maxLines: maxLines,
          overflow: overflow,
          textAlign: textAlign,
          textScaler: fitted,
          semanticsLabel: semanticsLabel,
        );
      },
    );
  }
}

/// The [scaler] itself when every word of [text] fits [maxWidth] at it;
/// otherwise a linear scaler just small enough for the widest word to fit.
TextScaler awWordSafeScaler(
  BuildContext context,
  String text, {
  required TextScaler scaler,
  required double maxWidth,
  TextStyle? style,
}) {
  final effective = DefaultTextStyle.of(context).style.merge(style);
  final words = text.split(_wordGaps).where((w) => w.isNotEmpty);
  if (words.isEmpty || maxWidth <= 0) return scaler;
  final painter = TextPainter(
    textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
    locale: Localizations.maybeLocaleOf(context),
    textScaler: scaler,
    maxLines: 1,
  );
  var widest = 0.0;
  for (final word in words) {
    painter
      ..text = TextSpan(text: word, style: effective)
      ..layout();
    widest = math.max(widest, painter.width);
  }
  painter.dispose();
  if (widest <= maxWidth) return scaler;
  final base = effective.fontSize ?? 14;
  final current = scaler.scale(base) / base;
  // A hair under the exact ratio: glyph advances round, and a word that
  // measures exactly the slot width can still be pushed to a second line.
  return TextScaler.linear(current * (maxWidth / widest) * 0.98);
}

/// An e-mail address (or host) that can wrap where a reader would break it:
/// before the `@` and before each `.` — "demo / @alliswell / .space", never
/// "demo@alliswel / l.space" (OPH-400 / R-09). Pair it with the plain
/// address as the semantics label.
String awBreakableAddress(String address) =>
    address.replaceAllMapped(RegExp(r'(?<=.)([@.])'), (m) => '$kAwZwsp${m[1]}');

/// Room above the first outlined field of a scrolling form so its floating
/// label is not clipped by the scroll view (OPH-400 / R-09): the label floats
/// half above the border, and at AX3 that half is taller than a fixed 4 pt.
double awFloatingLabelClearance(BuildContext context, {double min = 4}) {
  final theme = Theme.of(context);
  final label =
      theme.inputDecorationTheme.labelStyle ?? theme.textTheme.bodyLarge;
  final size = (label?.fontSize ?? 16) * 0.75; // Material's float scale
  final line =
      MediaQuery.textScalerOf(context).scale(size) * (label?.height ?? 1.2);
  return math.max(min, line / 2 + 2);
}
