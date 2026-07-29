import 'package:flutter/material.dart';

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
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

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
