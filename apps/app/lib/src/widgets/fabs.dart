import 'package:flutter/material.dart';

/// An extended FAB that is actually pill-shaped.
///
/// The app theme sets `shape: CircleBorder()` for every flavour of FAB
/// (`theme.dart`, the EE-042 note), because that is right for the plain
/// circular ones — which is all of them but three. This Flutter's
/// `FloatingActionButtonThemeData` has no separate slot for the extended
/// variant, so the circle applies there too, and a `CircleBorder` on a
/// ~145x48 button paints a 48px disc centred horizontally: the icon at
/// x≈16-40 falls OUTSIDE the painted area and, drawn in `onPrimary`, simply
/// disappears, while the label straddles the edge and survives. The reported
/// symptom is "the button has a label and no icon" (OPH-293), and it looked
/// for all the world like a missing glyph.
///
/// Passing `shape: StadiumBorder()` at the call site fixes it — and every
/// call site had to remember, which is why two of the three did not. This
/// widget is the place to remember it once. `scripts/design/check-extended-fab.mjs`
/// keeps the fourth one, written next year, from rediscovering the bug.
class AwExtendedFab extends StatelessWidget {
  const AwExtendedFab({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final Widget icon;
  final Widget label;

  /// Null disables the button, as on any FAB — used while a create is in
  /// flight so a second tap cannot mint a second thing.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => FloatingActionButton.extended(
    // The whole point of this widget. Do not remove it and do not move it
    // into the theme: the theme slot is shared with the circular FABs.
    shape: const StadiumBorder(),
    onPressed: onPressed,
    icon: icon,
    label: label,
  );
}
