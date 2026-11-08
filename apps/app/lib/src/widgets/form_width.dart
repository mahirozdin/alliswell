import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// A form's or a settings page's content, never wider than
/// [kAwFormMaxWidth] (OPH-410, DESIGN §51 D6).
///
/// The page around it keeps the window's width — its app bar and background
/// still reach the edges — and the content stands in a centred column, as
/// the core's own Settings pages do. At or below the cap the insets are
/// zero: a phone's layout does not change by a pixel.
class AwFormWidth extends StatelessWidget {
  const AwFormWidth({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final spare = box.hasBoundedWidth ? box.maxWidth - kAwFormMaxWidth : 0;
      // Insets, not a loose box: the child keeps the constraints it had
      // (tight height for a list, a stretched column), only narrower. Always
      // the same widget, so a resize across the cap keeps the child's state.
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: spare > 0 ? spare / 2 : 0),
        child: child,
      );
    },
  );
}
