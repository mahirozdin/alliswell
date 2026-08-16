import 'package:flutter/material.dart';

/// The colours a note may carry, stored by NAME (OPH-259, DESIGN §33 R4).
///
/// ## Why a name and not a hex
///
/// A Quill `color`/`background` attribute holds one string, and until now the
/// obvious thing to put there was `#RRGGBB`. Measured, that cannot work: the
/// surface under the text and the ink over a highlight both change with the
/// theme, so one fixed value has to satisfy two different backgrounds. None
/// can. Of eighteen candidate text hues, **zero** cleared 4.5:1 against both
/// `#FFFFFF` and `#151F3C`; for highlights the two ratios multiply to at most
/// 21, so both sides can only reach ~4.6 at a single mid lightness — the best
/// candidate, `#808080`, measured 4.37 / 3.46 and failed both.
///
/// So the document stores `aw:text-red`, and each theme resolves it to its own
/// hex. flutter_quill supports exactly this: `stringToColor` consults
/// `DefaultStyles.palette` before it tries to parse anything, so the names are
/// resolved by the package itself rather than by a fork of its renderer.
///
/// This is also what the app's own `==mark==` already did — tint a token, keep
/// the body ink — so the two ways of marking text finally agree.
///
/// Every pair below is checked in `scripts/design/contrast.py`: text against
/// its own surface, highlights against the body ink that will sit on them.
class AwNoteColor {
  const AwNoteColor({
    required this.id,
    required this.labelKey,
    required this.light,
    required this.dark,
  });

  /// What the document stores. Stable — it outlives any palette retune.
  final String id;
  final String labelKey;
  final Color light;
  final Color dark;

  Color forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;
}

/// Text colours: legible on the surface each theme actually paints.
const kAwNoteTextColors = <AwNoteColor>[
  AwNoteColor(
    id: 'aw:text-red',
    labelKey: 'color.red',
    light: Color(0xFFB3261E),
    dark: Color(0xFFFF9E96),
  ),
  AwNoteColor(
    id: 'aw:text-orange',
    labelKey: 'color.orange',
    light: Color(0xFFA8410A),
    dark: Color(0xFFFFB07A),
  ),
  AwNoteColor(
    id: 'aw:text-green',
    labelKey: 'color.green',
    light: Color(0xFF1B6E2F),
    dark: Color(0xFF6FE08A),
  ),
  AwNoteColor(
    id: 'aw:text-teal',
    labelKey: 'color.teal',
    light: Color(0xFF0F6E6E),
    dark: Color(0xFF5FD9D9),
  ),
  AwNoteColor(
    id: 'aw:text-blue',
    labelKey: 'color.blue',
    light: Color(0xFF0B54D0),
    dark: Color(0xFF8FBEFF),
  ),
  AwNoteColor(
    id: 'aw:text-purple',
    labelKey: 'color.purple',
    light: Color(0xFF6D28D9),
    dark: Color(0xFFC4A7FF),
  ),
  AwNoteColor(
    id: 'aw:text-pink',
    labelKey: 'color.pink',
    light: Color(0xFF9D174D),
    dark: Color(0xFFFF9EC4),
  ),
  AwNoteColor(
    id: 'aw:text-grey',
    labelKey: 'color.grey',
    light: Color(0xFF4A5568),
    dark: Color(0xFFAEB9D4),
  ),
];

/// Highlight fills: pale under dark ink, deep under light ink.
const kAwNoteHighlightColors = <AwNoteColor>[
  AwNoteColor(
    id: 'aw:mark-yellow',
    labelKey: 'color.yellow',
    light: Color(0xFFFFF3A3),
    dark: Color(0xFF5A4A12),
  ),
  AwNoteColor(
    id: 'aw:mark-green',
    labelKey: 'color.green',
    light: Color(0xFFCDEFD4),
    dark: Color(0xFF1E4A2C),
  ),
  AwNoteColor(
    id: 'aw:mark-blue',
    labelKey: 'color.blue',
    light: Color(0xFFCFE3FF),
    dark: Color(0xFF1B3A63),
  ),
  AwNoteColor(
    id: 'aw:mark-pink',
    labelKey: 'color.pink',
    light: Color(0xFFFFD6E4),
    dark: Color(0xFF5A2340),
  ),
  AwNoteColor(
    id: 'aw:mark-purple',
    labelKey: 'color.purple',
    light: Color(0xFFE6D9FF),
    dark: Color(0xFF3B2A66),
  ),
  AwNoteColor(
    id: 'aw:mark-grey',
    labelKey: 'color.grey',
    light: Color(0xFFDFE4EC),
    dark: Color(0xFF333B52),
  ),
];

const kAwNoteColors = [...kAwNoteTextColors, ...kAwNoteHighlightColors];

/// What a bare `==mark==` means when it becomes a Delta (OPH-259).
///
/// Markdown's highlight carries no colour, so the conversion has to choose one
/// — and it chooses the same yellow the renderer has always drawn for `==…==`,
/// by NAME, so it stays readable in both themes.
const kAwDefaultHighlightId = 'aw:mark-yellow';

/// The map flutter_quill resolves note colours through.
Map<String, Color> awNoteColorPalette(Brightness brightness) => {
  for (final color in kAwNoteColors) color.id: color.forBrightness(brightness),
};

/// Looks a stored value up. Returns null for anything that is not one of ours —
/// a raw hex written by an older build, or by another editor.
AwNoteColor? awNoteColorById(String? id) {
  if (id == null) return null;
  for (final color in kAwNoteColors) {
    if (color.id == id) return color;
  }
  return null;
}

/// Resolves a stored value to something paintable, for the surfaces that do
/// their own drawing (the picker's swatches).
Color? awResolveNoteColor(String? id, Brightness brightness) =>
    awNoteColorById(id)?.forBrightness(brightness);
