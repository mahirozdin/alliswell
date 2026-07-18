import 'package:flutter/material.dart';

/// AllisWell design tokens — the single source of truth for the visual
/// language ("AllisWell Glass v2 — Liquid", see docs/DESIGN.md). Every color
/// here is contrast-verified: text ≥ 4.5:1, icons/borders ≥ 3:1 against the
/// surfaces they appear on, in BOTH brightnesses. Do not hardcode colors in
/// widgets; pull them from [AwTokens] or the [ColorScheme].

/// Spacing scale (4pt grid). Use these instead of magic numbers.
abstract final class AwSpace {
  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x5 = 20;
  static const double x6 = 24;
  static const double x8 = 32;
  static const double x12 = 48;
}

/// Corner radius scale (Liquid Glass v2: rounder, concentric — a nested
/// shape's radius ≈ parent radius − padding). Chips/badges = s, inputs &
/// list rows = m, cards = l, sheets/dialogs = xl, floating chrome = pill.
abstract final class AwRadius {
  static const double s = 12;
  static const double m = 16;
  static const double l = 20;
  static const double xl = 28;

  /// Floating glass chrome (bottom bar capsule, nav rail panel).
  static const double pill = 32;
}

/// Motion tokens: quick, physical, never decorative-slow.
abstract final class AwMotion {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration base = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 320);
  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;
}

/// Blur strength for glass chrome (nav bar, nav rail). Content surfaces are
/// solid on purpose — glass is for chrome, never under body text.
const double kAwGlassSigma = 22;

/// Saturation boost applied to the backdrop of glass chrome. Liquid Glass
/// doesn't just blur what's beneath it — it lets color bleed through more
/// vividly, which is what makes the material read as glass instead of fog.
const double kAwGlassSaturation = 1.55;

/// WCAG relative-luminance contrast ratio between two opaque colors (≥ 1).
/// Small helper for choosing legible ink on user-picked (data) colors.
double awContrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// Theme-dependent tokens that Material's [ColorScheme] has no slot for.
@immutable
class AwTokens extends ThemeExtension<AwTokens> {
  const AwTokens({
    required this.success,
    required this.warning,
    required this.link,
    required this.hairline,
    required this.glassTint,
    required this.glassStroke,
    required this.glassHighlight,
    required this.glassShadow,
    required this.auroraTop,
    required this.auroraBottom,
    required this.blobA,
    required this.blobB,
    required this.blobC,
    required this.veil,
    required this.prioLow,
    required this.prioMedium,
    required this.prioHigh,
    required this.prioUrgent,
  });

  /// Positive/confirmation accents (≥ 4.5:1 as text on surface).
  final Color success;

  /// Favorites/pinned stars and caution accents (≥ 3:1 as icon on surface).
  final Color warning;

  /// Text-button/link foreground — darker than primary in light mode so
  /// small link text stays ≥ 4.5:1 on the background.
  final Color link;

  /// Decorative 1px borders (cards, separators). Intentionally quiet;
  /// functional borders (inputs) use [ColorScheme.outline] instead.
  final Color hairline;

  /// Glass chrome fill drawn over the (blurred + saturated) backdrop. High
  /// opacity by design: text on glass must keep its contrast no matter what
  /// scrolls beneath.
  final Color glassTint;

  /// Bright lensing edge of glass chrome — the light that "bends" around
  /// the rim of the material. Rendered as a gradient stroke, strongest on
  /// the top edge.
  final Color glassStroke;

  /// Specular top catchlight inside glass chrome.
  final Color glassHighlight;

  /// Soft ambient shadow under floating glass chrome (bottom bar capsule,
  /// rail panel, FAB) — what visually lifts the functional layer above the
  /// content layer.
  final Color glassShadow;

  /// Ambient background wash (top → bottom) behind every screen.
  final Color auroraTop;
  final Color auroraBottom;

  /// Static color blobs in the wash — deliberately colorful so the glass
  /// chrome has something to refract. Never behind body text at full
  /// strength: the scaffold [veil] sits on top.
  final Color blobA;
  final Color blobB;
  final Color blobC;

  /// Translucent scaffold background over the aurora wash.
  final Color veil;

  /// Task priority colors — same hues in both modes (meaning never shifts),
  /// lightness adapted per mode to keep ≥ 3:1 icon contrast.
  final Color prioLow;
  final Color prioMedium;
  final Color prioHigh;
  final Color prioUrgent;

  static const light = AwTokens(
    success: Color(0xFF0D7A33),
    warning: Color(0xFFC77700),
    link: Color(0xFF0B54D0),
    hairline: Color(0x140F1B2E),
    glassTint: Color(0xBDF6F9FF),
    glassStroke: Color(0xA6FFFFFF),
    glassHighlight: Color(0x73FFFFFF),
    glassShadow: Color(0x33203A66),
    auroraTop: Color(0xFFE9F2FF),
    auroraBottom: Color(0xFFF1EBFF),
    blobA: Color(0x4D3D7DFF),
    blobB: Color(0x408E5CFF),
    blobC: Color(0x3800C7B0),
    veil: Color(0x94F5F9FF),
    prioLow: Color(0xFF0F9D46),
    prioMedium: Color(0xFFC77700),
    prioHigh: Color(0xFFE8500A),
    prioUrgent: Color(0xFFE3261A),
  );

  static const dark = AwTokens(
    success: Color(0xFF30D158),
    warning: Color(0xFFFFC400),
    link: Color(0xFF3E9BFF),
    hairline: Color(0x1FEAF0FD),
    glassTint: Color(0xB8111A38),
    glassStroke: Color(0x40FFFFFF),
    glassHighlight: Color(0x24FFFFFF),
    glassShadow: Color(0x8A02040C),
    auroraTop: Color(0xFF0B1233),
    auroraBottom: Color(0xFF070B1F),
    blobA: Color(0x6B3D7DFF),
    blobB: Color(0x598B5CF6),
    blobC: Color(0x4A22C9B4),
    veil: Color(0x7A0A102A),
    prioLow: Color(0xFF30D158),
    prioMedium: Color(0xFFFFC400),
    prioHigh: Color(0xFFFF8A1E),
    prioUrgent: Color(0xFFFF453A),
  );

  @override
  AwTokens copyWith({
    Color? success,
    Color? warning,
    Color? link,
    Color? hairline,
    Color? glassTint,
    Color? glassStroke,
    Color? glassHighlight,
    Color? glassShadow,
    Color? auroraTop,
    Color? auroraBottom,
    Color? blobA,
    Color? blobB,
    Color? blobC,
    Color? veil,
    Color? prioLow,
    Color? prioMedium,
    Color? prioHigh,
    Color? prioUrgent,
  }) {
    return AwTokens(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      link: link ?? this.link,
      hairline: hairline ?? this.hairline,
      glassTint: glassTint ?? this.glassTint,
      glassStroke: glassStroke ?? this.glassStroke,
      glassHighlight: glassHighlight ?? this.glassHighlight,
      glassShadow: glassShadow ?? this.glassShadow,
      auroraTop: auroraTop ?? this.auroraTop,
      auroraBottom: auroraBottom ?? this.auroraBottom,
      blobA: blobA ?? this.blobA,
      blobB: blobB ?? this.blobB,
      blobC: blobC ?? this.blobC,
      veil: veil ?? this.veil,
      prioLow: prioLow ?? this.prioLow,
      prioMedium: prioMedium ?? this.prioMedium,
      prioHigh: prioHigh ?? this.prioHigh,
      prioUrgent: prioUrgent ?? this.prioUrgent,
    );
  }

  @override
  AwTokens lerp(AwTokens? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AwTokens(
      success: mix(success, other.success),
      warning: mix(warning, other.warning),
      link: mix(link, other.link),
      hairline: mix(hairline, other.hairline),
      glassTint: mix(glassTint, other.glassTint),
      glassStroke: mix(glassStroke, other.glassStroke),
      glassHighlight: mix(glassHighlight, other.glassHighlight),
      glassShadow: mix(glassShadow, other.glassShadow),
      auroraTop: mix(auroraTop, other.auroraTop),
      auroraBottom: mix(auroraBottom, other.auroraBottom),
      blobA: mix(blobA, other.blobA),
      blobB: mix(blobB, other.blobB),
      blobC: mix(blobC, other.blobC),
      veil: mix(veil, other.veil),
      prioLow: mix(prioLow, other.prioLow),
      prioMedium: mix(prioMedium, other.prioMedium),
      prioHigh: mix(prioHigh, other.prioHigh),
      prioUrgent: mix(prioUrgent, other.prioUrgent),
    );
  }
}

/// Shorthand: `context.awTokens`.
extension AwTokensContext on BuildContext {
  AwTokens get awTokens => Theme.of(this).extension<AwTokens>()!;
}
