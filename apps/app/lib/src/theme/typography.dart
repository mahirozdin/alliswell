import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// "Glass Type v1" — the type scale and its tracking (ADR-0063, DESIGN §3.3).
///
/// Sizes are Material's; what changes is the tracking, the line heights and
/// the weights. Two rules carry the whole scale:
///
/// - **Tracking comes from the font, never from a widget.** Material's
///   `englishLike` tracking (+0.5 on body, +0.25, +0.4 …) is tuned for Roboto
///   and was being applied to SF Pro, which Flutter draws WITHOUT Apple's
///   dynamic tracking. Measured on an iOS simulator against UILabel, that made
///   row titles 9.4–11.3 % wider than native. The HIG table reproduces native
///   widths within 0.02–0.15 pt (`docs/research/2026-11-design-ux/
///   typography-sf-verification.md`); every other platform keeps its font's
///   own metrics (0).
/// - **Weights are 400 / 500 / 600 / 700.** w800 belongs to the alarm label
///   alone. State is told by colour, not weight, so a label never jumps width.

/// The HIG SF Pro tracking table, in points (iOS, iPadOS — Apple's
/// "Tracking values"). Sizes between rows round to the nearest row.
const Map<int, double> kAwSfTracking = {
  6: 0.24,
  7: 0.23,
  8: 0.21,
  9: 0.17,
  10: 0.12,
  11: 0.06,
  12: 0,
  13: -0.08,
  14: -0.15,
  15: -0.23,
  16: -0.31,
  17: -0.43,
  18: -0.44,
  19: -0.45,
  20: -0.45,
  21: -0.36,
  22: -0.26,
  23: -0.10,
  24: 0.07,
  25: 0.15,
  26: 0.22,
  27: 0.29,
  28: 0.38,
  29: 0.40,
  30: 0.40,
  31: 0.39,
  32: 0.41,
  33: 0.40,
  34: 0.40,
  35: 0.38,
  36: 0.37,
  37: 0.36,
  38: 0.37,
  39: 0.38,
  40: 0.37,
  41: 0.36,
  42: 0.37,
  43: 0.38,
  44: 0.37,
  45: 0.35,
  46: 0.36,
  47: 0.37,
  48: 0.35,
  49: 0.33,
  50: 0.34,
  51: 0.35,
  52: 0.33,
  53: 0.31,
  54: 0.32,
  56: 0.30,
  58: 0.28,
  60: 0.26,
  62: 0.24,
  64: 0.22,
  66: 0.19,
  68: 0.17,
  70: 0.14,
  72: 0.14,
  76: 0.07,
  80: 0,
};

/// Letter spacing for [size] (ADR-0063 #1): the HIG table when the text is
/// drawn in Apple's system font ([apple]), 0 for every other font.
double awTracking(double size, {required bool apple}) {
  if (!apple) return 0;
  final rows = kAwSfTracking.keys.toList();
  if (size <= rows.first) return kAwSfTracking[rows.first]!;
  if (size >= rows.last) return 0;
  var best = rows.first;
  for (final row in rows) {
    if ((row - size).abs() < (best - size).abs()) best = row;
  }
  return kAwSfTracking[best]!;
}

/// Whether the theme draws in Apple's system font: iOS or macOS, not the web
/// (the web draws the app's own Roboto) and not a test/screenshot override.
bool awUsesAppleSystemFont({
  required TargetPlatform platform,
  String? fontFamilyOverride,
}) =>
    fontFamilyOverride == null &&
    !kIsWeb &&
    (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS);

const _tabular = FontFeature.tabularFigures();

/// [style] with tabular figures — dates, times, counters, badges (ADR-0063
/// #3): a digit is as wide as any other, so a ticking or growing number does
/// not shift the text beside it. Keeps any feature the style already has.
TextStyle awTabular(TextStyle style) {
  final features = style.fontFeatures ?? const <FontFeature>[];
  if (features.contains(_tabular)) return style;
  return style.copyWith(fontFeatures: [...features, _tabular]);
}

/// Builds the Glass Type v1 [TextTheme] from Material's 2021 [base].
///
/// Line heights are set in logical pixels and stored as a ratio, so they
/// scale with the text; tracking is [awTracking] of the role's own size.
TextTheme buildAwTextTheme(TextTheme base, {required bool apple}) {
  TextStyle? role(
    TextStyle? s, {
    required double lineHeight,
    required FontWeight weight,
    bool tabular = false,
  }) {
    if (s == null) return null;
    final size = s.fontSize!;
    final out = s.copyWith(
      height: lineHeight / size,
      fontWeight: weight,
      letterSpacing: awTracking(size, apple: apple),
    );
    return tabular ? awTabular(out) : out;
  }

  return base.copyWith(
    displayLarge: role(
      base.displayLarge,
      lineHeight: 64,
      weight: FontWeight.w400,
    ),
    displayMedium: role(
      base.displayMedium,
      lineHeight: 52,
      weight: FontWeight.w400,
    ),
    // The big number on a dashboard.
    displaySmall: role(
      base.displaySmall,
      lineHeight: 44,
      weight: FontWeight.w700,
      tabular: true,
    ),
    headlineLarge: role(
      base.headlineLarge,
      lineHeight: 40,
      weight: FontWeight.w700,
    ),
    headlineMedium: role(
      base.headlineMedium,
      lineHeight: 34,
      weight: FontWeight.w700,
    ),
    headlineSmall: role(
      base.headlineSmall,
      lineHeight: 30,
      weight: FontWeight.w700,
    ),
    titleLarge: role(base.titleLarge, lineHeight: 28, weight: FontWeight.w700),
    titleMedium: role(
      base.titleMedium,
      lineHeight: 22,
      weight: FontWeight.w600,
    ),
    titleSmall: role(base.titleSmall, lineHeight: 20, weight: FontWeight.w600),
    // The row title and the input text.
    bodyLarge: role(base.bodyLarge, lineHeight: 22, weight: FontWeight.w400),
    bodyMedium: role(base.bodyMedium, lineHeight: 20, weight: FontWeight.w400),
    bodySmall: role(base.bodySmall, lineHeight: 16, weight: FontWeight.w400),
    labelLarge: role(base.labelLarge, lineHeight: 20, weight: FontWeight.w600),
    labelMedium: role(
      base.labelMedium,
      lineHeight: 16,
      weight: FontWeight.w600,
    ),
    labelSmall: role(base.labelSmall, lineHeight: 14, weight: FontWeight.w500),
  );
}

/// The semantic roles screens used to copy as `copyWith` chains (ADR-0063
/// #2): `context.awText.sectionLabel` instead of `labelLarge.copyWith(
/// fontWeight: w700, letterSpacing: 0.4)` retyped in four files.
///
/// They carry no colour beyond the theme's body ink; a call site sets the
/// colour its meaning needs.
@immutable
class AwTextRoles extends ThemeExtension<AwTextRoles> {
  const AwTextRoles({
    required this.apple,
    required this.sectionLabel,
    required this.meta,
    required this.metaStrong,
    required this.rowTitle,
    required this.dayNumber,
  });

  /// Builds the roles for a theme whose body ink is [ink].
  factory AwTextRoles.build({required bool apple, required Color ink}) {
    TextStyle style(double size, double lineHeight, FontWeight weight) =>
        TextStyle(
          inherit: true,
          color: ink,
          fontSize: size,
          height: lineHeight / size,
          fontWeight: weight,
          letterSpacing: awTracking(size, apple: apple),
          leadingDistribution: TextLeadingDistribution.even,
        );
    final meta = awTabular(style(13, 18, FontWeight.w400));
    return AwTextRoles(
      apple: apple,
      sectionLabel: awTabular(style(15, 20, FontWeight.w700)),
      meta: meta,
      metaStrong: meta.copyWith(fontWeight: FontWeight.w500),
      rowTitle: style(16, 22, FontWeight.w400),
      dayNumber: awTabular(style(17, 22, FontWeight.w600)),
    );
  }

  /// Whether tracking follows Apple's table (see [awTracking]).
  final bool apple;

  /// A list section's header ("Overdue  3"): 15/20 w700 (OPH-401, DESIGN
  /// §47 S1), sentence case, tabular count.
  final TextStyle sectionLabel;

  /// A row's meta line (date · repeat · alarm): 13/18 w400, tabular.
  final TextStyle meta;

  /// [meta]'s emphasis (overdue, snoozed): w500, never w600.
  final TextStyle metaStrong;

  /// A task or note row's title: 16/22 w400.
  final TextStyle rowTitle;

  /// A day number in Home's week strip (DESIGN §47 W2): 17/22 w600, tabular.
  final TextStyle dayNumber;

  /// Tracking for a size this theme draws that is not one of its roles (a
  /// fixed-size bar label).
  double tracking(double size) => awTracking(size, apple: apple);

  /// [style] with tabular figures; see [awTabular].
  TextStyle numeric(TextStyle style) => awTabular(style);

  @override
  AwTextRoles copyWith({
    bool? apple,
    TextStyle? sectionLabel,
    TextStyle? meta,
    TextStyle? metaStrong,
    TextStyle? rowTitle,
    TextStyle? dayNumber,
  }) => AwTextRoles(
    apple: apple ?? this.apple,
    sectionLabel: sectionLabel ?? this.sectionLabel,
    meta: meta ?? this.meta,
    metaStrong: metaStrong ?? this.metaStrong,
    rowTitle: rowTitle ?? this.rowTitle,
    dayNumber: dayNumber ?? this.dayNumber,
  );

  @override
  AwTextRoles lerp(AwTextRoles? other, double t) {
    if (other == null) return this;
    return AwTextRoles(
      apple: t < 0.5 ? apple : other.apple,
      sectionLabel: TextStyle.lerp(sectionLabel, other.sectionLabel, t)!,
      meta: TextStyle.lerp(meta, other.meta, t)!,
      metaStrong: TextStyle.lerp(metaStrong, other.metaStrong, t)!,
      rowTitle: TextStyle.lerp(rowTitle, other.rowTitle, t)!,
      dayNumber: TextStyle.lerp(dayNumber, other.dayNumber, t)!,
    );
  }
}

/// Shorthand: `context.awText`.
extension AwTextContext on BuildContext {
  AwTextRoles get awText => Theme.of(this).extension<AwTextRoles>()!;
}
