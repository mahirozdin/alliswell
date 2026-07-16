import 'package:flutter/material.dart';

/// AllisWell design tokens — the single source of truth for the visual
/// language ("AllisWell Glass", see docs/DESIGN.md). Every color here is
/// contrast-verified: text ≥ 4.5:1, icons/borders ≥ 3:1 against the surfaces
/// they appear on, in BOTH brightnesses. Do not hardcode colors in widgets;
/// pull them from [AwTokens] or the [ColorScheme].

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

/// Corner radius scale. Chips/small = s, inputs & list rows = m,
/// cards = l, sheets/dialogs = xl.
abstract final class AwRadius {
  static const double s = 10;
  static const double m = 14;
  static const double l = 18;
  static const double xl = 24;
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
const double kAwGlassSigma = 18;

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
    required this.auroraTop,
    required this.auroraBottom,
    required this.blobA,
    required this.blobB,
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

  /// Glass chrome fill drawn over the backdrop blur. High opacity by design:
  /// text on glass must keep its contrast no matter what scrolls beneath.
  final Color glassTint;

  /// 1px stroke around glass chrome.
  final Color glassStroke;

  /// Faint top-edge light on glass chrome (the "liquid" catchlight).
  final Color glassHighlight;

  /// Ambient background wash (top → bottom) behind every screen.
  final Color auroraTop;
  final Color auroraBottom;

  /// Static, low-alpha color blobs in the wash. Never behind body text at
  /// full strength — the scaffold [veil] sits on top.
  final Color blobA;
  final Color blobB;

  /// Translucent scaffold background over the aurora wash.
  final Color veil;

  /// Task priority colors — same hues in both modes (meaning never shifts),
  /// lightness adapted per mode to keep ≥ 3:1 icon contrast.
  final Color prioLow;
  final Color prioMedium;
  final Color prioHigh;
  final Color prioUrgent;

  static const light = AwTokens(
    success: Color(0xFF047857),
    warning: Color(0xFFB45309),
    link: Color(0xFF1D4ED8),
    hairline: Color(0x14101828),
    glassTint: Color(0xC9F3F6FC),
    glassStroke: Color(0x8CFFFFFF),
    glassHighlight: Color(0x59FFFFFF),
    auroraTop: Color(0xFFF6F8FC),
    auroraBottom: Color(0xFFEAEFF8),
    blobA: Color(0x1F2563EB),
    blobB: Color(0x1A0D9488),
    veil: Color(0xB8F4F6FB),
    prioLow: Color(0xFF047857),
    prioMedium: Color(0xFFB45309),
    prioHigh: Color(0xFFC2410C),
    prioUrgent: Color(0xFFDC2626),
  );

  static const dark = AwTokens(
    success: Color(0xFF34D399),
    warning: Color(0xFFFBBF24),
    link: Color(0xFF8AB4FF),
    hairline: Color(0x1FE7ECF6),
    glassTint: Color(0xCC101828),
    glassStroke: Color(0x1FFFFFFF),
    glassHighlight: Color(0x14FFFFFF),
    auroraTop: Color(0xFF0D1322),
    auroraBottom: Color(0xFF090D18),
    blobA: Color(0x3D2563EB),
    blobB: Color(0x2E14B8A6),
    veil: Color(0xA30B1020),
    prioLow: Color(0xFF34D399),
    prioMedium: Color(0xFFFBBF24),
    prioHigh: Color(0xFFFB923C),
    prioUrgent: Color(0xFFF87171),
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
    Color? auroraTop,
    Color? auroraBottom,
    Color? blobA,
    Color? blobB,
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
      auroraTop: auroraTop ?? this.auroraTop,
      auroraBottom: auroraBottom ?? this.auroraBottom,
      blobA: blobA ?? this.blobA,
      blobB: blobB ?? this.blobB,
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
      auroraTop: mix(auroraTop, other.auroraTop),
      auroraBottom: mix(auroraBottom, other.auroraBottom),
      blobA: mix(blobA, other.blobA),
      blobB: mix(blobB, other.blobB),
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
