import 'package:flutter/material.dart';

import '../../../theme/tokens.dart';

/// A small filled pill in a project's color, used on task rows so the owning
/// project is legible at a glance (OPH-104, docs/DESIGN.md §4 "Project badge").
///
/// The label is the project name, truncated to its first 6 characters + "…"
/// when longer (grapheme-safe); the FULL name is always reachable through the
/// tooltip (hover + long-press) and the semantic label. The fill/ink pair is
/// computed from the project color so the label always clears WCAG AA. The
/// badge is tap-transparent — the surrounding row handles taps.
class ProjectBadge extends StatelessWidget {
  const ProjectBadge({super.key, required this.name, required this.color});

  final String name;
  final Color color;

  /// First 6 graphemes + "…" when longer, so the pill hugs a short label
  /// (NOT `TextOverflow`, which would let it stretch to the row's width).
  static String shortLabel(String name) {
    final chars = name.characters;
    if (chars.length <= 6) return name;
    return '${chars.take(6)}…';
  }

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
    return Tooltip(
      message: name,
      waitDuration: const Duration(milliseconds: 400),
      child: Semantics(
        label: 'Project: $name',
        // DecoratedBox + Padding sizes to the label, so the pill hugs its text.
        // (A Container with `alignment` set expanded to the row height under the
        // row's loose constraints — feedback round 5.)
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(AwRadius.s),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            child: Text(
              shortLabel(name),
              maxLines: 1,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: ink,
                fontWeight: FontWeight.w600,
                height: 1.1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
