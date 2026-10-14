/// The one print style every note exporter draws with (ADR-0048).
///
/// The PDF writer (`note_pdf.dart`) and the Word writer (`note_docx.dart`)
/// must produce the SAME page: a note exported to .docx that looks different
/// from the same note exported to .pdf is the class of mismatch round 19b
/// removed between the screen and the page. So the numbers live here, once, as
/// plain values — no `pdf` types, no OOXML units — and each writer converts
/// them into its own unit (PDF points, Word twips / half-points / EMUs).
///
/// Print is always "light": a dark-theme page would waste ink and read badly
/// on paper.
library;

/// Colours as 0xAARRGGBB, the print equivalents of the app tokens.
///
/// The role colours are copied VALUE FOR VALUE from the app's LIGHT theme
/// (`note_pdf_palette_test.dart` fails and names the one that drifted):
///
///   success  = AwTokens.light.success   (theme/tokens.dart)
///   warning  = AwTokens.light.warning
///   secondary/error = the light ColorScheme (theme/theme.dart)
///   accent   = the light primary
abstract final class NotePrintPalette {
  static const int ink = 0xFF0F1B2E;
  static const int muted = 0xFF44536F;
  static const int accent = 0xFF0A5CFF;
  static const int rule = 0xFFD8DEEA;
  static const int codeBg = 0xFFF2F4F9;

  static const int success = 0xFF0D7A33;
  static const int warning = 0xFFC77700;
  static const int secondary = 0xFF5A50E0;
  static const int error = 0xFFD70015;

  /// A highlight's tint. `AwTokens.warning` at the same alpha the source
  /// editor uses, pre-blended onto white — neither a PDF text background nor a
  /// Word shading can carry alpha.
  static const int markBg = 0xFFFDF0D5;

  /// The table grid and the `---` rule (the `pdf` package's `grey400`).
  static const int tableRule = 0xFFBDBDBD;

  /// The edge colour of a GFM alert, by its kind — the same five roles
  /// `MdStyles.alertAccent` maps on screen. An unknown kind takes the neutral
  /// one rather than vanishing.
  static int calloutEdge(String? kind) => switch (kind) {
    'tip' => success,
    'important' => secondary,
    'warning' => warning,
    'caution' => error,
    _ => accent, // `note`, and anything the parser invents later
  };

  /// How much of [calloutEdge] tints the alert's panel.
  static const double calloutTintAlpha = 0.08;

  /// [calloutEdge] at [calloutTintAlpha], pre-blended onto white paper — for a
  /// writer (Word) whose shading has no alpha channel. The PDF draws the same
  /// colour with real alpha over the same white page, so the two agree.
  static int calloutTint(String? kind) =>
      blendOnWhite(calloutEdge(kind), calloutTintAlpha);

  /// [argb] at [alpha] over white, as an opaque colour.
  static int blendOnWhite(int argb, double alpha) {
    int channel(int shift) {
      final c = (argb >> shift) & 0xFF;
      return (255 - (255 - c) * alpha).round().clamp(0, 255);
    }

    return 0xFF000000 | channel(16) << 16 | channel(8) << 8 | channel(0);
  }

  /// `RRGGBB` without the alpha — the form OOXML wants.
  static String hex(int argb) =>
      (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
}

/// Sizes and spacing, in typographic points unless named otherwise.
abstract final class NotePrintMetrics {
  // Page: A4 portrait.
  static const double pageWidthCm = 21.0;
  static const double pageHeightCm = 29.7;
  static const double marginSideCm = 2.2;
  static const double marginTopBottomCm = 2.0;

  /// Points per centimetre (72 / 2.54).
  static const double pointsPerCm = 72.0 / 2.54;

  /// The width a block may take: the page minus both side margins.
  static double get contentWidth =>
      (pageWidthCm - 2 * marginSideCm) * pointsPerCm;

  // Type sizes.
  static const double title = 24;
  static const double titleLetterSpacing = -0.4;
  static const double heading1 = 19;
  static const double heading2 = 15.5;
  static const double heading3 = 13;
  static const double body = 11;
  static const double code = 9.5;
  static const double meta = 9; // updated label, header, footer, front matter
  static const double table = 10;

  /// Extra leading between the lines of running text…
  static const double bodyLineGap = 2.4;

  /// …and of code, figure sources and front matter.
  static const double codeLineGap = 2;

  // Vertical rhythm: space before / after each kind of block.
  static const double blockAfter = 6;
  static const double listAfter = 3;
  static const double heading1Before = 8;
  static const double heading2Before = 7;
  static const double heading3Before = 6;
  static const double calloutBefore = 4;
  static const double frontMatterAfter = 10;
  static const double imageBefore = 4;
  static const double figureBefore = 6;
  static const double mediaAfter = 10;
  static const double dividerBefore = 4;
  static const double tableBefore = 4;

  /// An intentionally blank line keeps this much air.
  static const double blankLine = 6;

  // The title block.
  static const double titleToLabel = 4;
  static const double titleToRule = 10;
  static const double ruleToBody = 14;
  static const double titleRuleWidth = 0.7;

  // Running header / footer.
  static const double headerGap = 12;

  // Lists.
  static const double indentPerLevel = 16;
  static const int maxIndentLevel = 6;
  static const double markerWidth = 18;

  // Panels.
  static const double quoteEdge = 2.5;
  static const double quotePadding = 10;
  static const double calloutEdge = 3;
  static const double calloutPaddingH = 10;
  static const double calloutPaddingV = 8;
  static const double panelPadding = 8; // code, figure source, front matter
  static const double placeholderPaddingH = 10;
  static const double placeholderPaddingV = 8;
  static const double hairline = 0.7; // front matter / placeholder border
  static const double dividerWidth = 1;
  static const double tableBorder = 0.5;
  static const double tableCellPadding = 4;

  // Pictures: fitted inside the content width and these heights, ratio kept.
  static const double imageMaxHeight = 320;
  static const double figureMaxHeight = 420;
}
