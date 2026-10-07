import 'package:flutter/material.dart';

import '../i18n/i18n.dart';

/// A round colour swatch with a selected state — the picker cell projects,
/// tags and quick-access shortcuts all use (OPH-202).
///
/// It lived inside `project_edit_sheet.dart` until Quick Access needed it; a
/// feature importing another feature's SHEET file for a widget is not how this
/// codebase is laid out, so it moved here beside the other shared pieces.
class AwColorSwatchDot extends StatelessWidget {
  const AwColorSwatchDot({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
    this.semanticLabel,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  /// What a screen reader says for this colour — its name, never its hex
  /// (OPH-359, UI-AUDIT #64). Defaults to [awColorName].
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    // Check mark adapts to the swatch so it stays visible on light colors.
    final checkColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black87;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Semantics(
        button: true,
        selected: selected,
        label: semanticLabel ?? awColorName(color),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: selected
                ? Border.all(
                    color: Theme.of(context).colorScheme.onSurface,
                    width: 3,
                  )
                : null,
          ),
          child: selected
              ? Icon(Icons.check, size: 18, color: checkColor)
              : null,
        ),
      ),
    );
  }
}

/// A colour's everyday name in the app's language — "Blue", "Mavi" — from its
/// hue (OPH-359, UI-AUDIT #64). Colour pickers were read out as "#2563EB":
/// correct, and useless to anybody who cannot see the swatch.
String awColorName(Color color) {
  final hsl = HSLColor.fromColor(color);
  // Slate and its neighbours are greys with a tint, and read as grey.
  if (hsl.saturation < 0.2) return 'color.grey'.tr();
  final h = hsl.hue;
  final key = h < 15 || h >= 345
      ? 'red'
      : h < 40
      ? 'orange'
      : h < 70
      ? 'yellow'
      : h < 165
      ? 'green'
      : h < 195
      ? 'teal'
      : h < 255
      ? 'blue'
      : h < 290
      ? 'purple'
      : 'pink';
  return 'color.$key'.tr();
}

/// [awColorName] for a row of swatches, numbered where two share a name
/// ("Blue", "Blue 2") so a reader can still tell them apart.
List<String> awColorNames(List<Color> colors) {
  final names = colors.map(awColorName).toList();
  final seen = <String, int>{};
  return [
    for (final name in names)
      names.where((n) => n == name).length > 1
          ? (seen[name] = (seen[name] ?? 0) + 1) == 1
                ? name
                : '$name ${seen[name]}'
          : name,
  ];
}
