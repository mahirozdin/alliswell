import 'package:flutter/material.dart';

import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';

/// The widest a project badge may be (polish 3 J-03, DESIGN §46 R6): about a
/// quarter of a phone row. A name whose whole pill is wider is not cut — the
/// row shows it in the meta line instead.
const double kAwProjectBadgeMaxWidth = 96;

/// A small filled pill in a project's color, used on task rows so the owning
/// project is legible at a glance (OPH-104, docs/DESIGN.md §4 "Project badge").
///
/// The label is the WHOLE project name, never cut (polish 3 J-03, DESIGN §46
/// R6): a row shows the badge only when [fits] says the name fits a compact
/// pill ([kAwProjectBadgeMaxWidth]); otherwise the row moves the full name to
/// its meta line, behind the colour dot. The fill/ink pair is
/// computed from the project color so the label always clears WCAG AA. The
/// badge is tap-transparent — the surrounding row handles taps.
class ProjectBadge extends StatelessWidget {
  const ProjectBadge({super.key, required this.name, required this.color});

  final String name;
  final Color color;

  /// The label's style: `labelSmall` w600 (DESIGN §4 "Project badge").
  static TextStyle? labelStyle(BuildContext context) => Theme.of(
    context,
  ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600, height: 1.1);

  /// Whether the pill holding the whole [name], at the reader's text size, is
  /// no wider than [kAwProjectBadgeMaxWidth]. Measured, not counted: a name
  /// of narrow letters may be longer than one of wide ones.
  static bool fits(BuildContext context, String name) {
    final painter = TextPainter(
      text: TextSpan(text: name, style: labelStyle(context)),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width + _padX * 2;
    painter.dispose();
    return width <= kAwProjectBadgeMaxWidth;
  }

  static const double _padX = 8;

  static const Color _ink = Color(0xFF101828); // near-black
  static const Color _paper = Color(0xFFFFFFFF); // white

  /// Fill + ink for a project [base] color whose label clears WCAG AA (4.5:1).
  ///
  /// Ink is whichever of near-black/white contrasts higher. Most colors pass
  /// untouched; a maximally-saturated mid-tone (e.g. the palette's violet
  /// `#8B5CF6`, whose luminance ≈ 0.198 sits in the dead zone where NEITHER
  /// pure ink reaches 4.5 on the raw color) is nudged a few percent in
  /// lightness — away from the ink — until it passes. The shift is monotonic
  /// (lightening only ever favors dark ink), so it never oscillates.
  static ({Color fill, Color ink}) legibleColors(Color base) {
    Color inkFor(Color c) =>
        awContrastRatio(_ink, c) >= awContrastRatio(_paper, c) ? _ink : _paper;

    var fill = base;
    var ink = inkFor(fill);
    if (awContrastRatio(ink, fill) >= 4.5) return (fill: fill, ink: ink);

    final hsl = HSLColor.fromColor(base);
    final towardLight = ink == _ink; // dark ink wants a lighter fill
    for (var step = 1; step <= 10; step++) {
      final l = (hsl.lightness + (towardLight ? 0.04 : -0.04) * step).clamp(
        0.0,
        1.0,
      );
      fill = hsl.withLightness(l).toColor();
      ink = inkFor(fill);
      if (awContrastRatio(ink, fill) >= 4.5) break;
    }
    return (fill: fill, ink: ink);
  }

  @override
  Widget build(BuildContext context) {
    final (:fill, :ink) = legibleColors(color);
    // OPH-407 (T-07): one localized label, the name heard once. It was
    // "Project: X" in every language, then X again from the text and again
    // from the tooltip.
    return Tooltip(
      message: name,
      waitDuration: const Duration(milliseconds: 400),
      excludeFromSemantics: true,
      child: Semantics(
        label: 'task.projectSemantic'.tr(args: {'project': name}),
        excludeSemantics: true,
        // DecoratedBox + Padding sizes to the label, so the pill hugs its text.
        // (A Container with `alignment` set expanded to the row height under the
        // row's loose constraints — feedback round 5.)
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(AwRadius.s),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: _padX, vertical: 3),
            child: Text(
              name,
              maxLines: 1,
              softWrap: false,
              style: labelStyle(context)?.copyWith(color: ink),
            ),
          ),
        ),
      ),
    );
  }
}
