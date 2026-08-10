/// GFM alerts as tinted cards (DESIGN §29 D6, OPH-247).
///
/// The accent colours the icon and the left edge; the body text stays
/// `onSurface`. That split is measured, not stylistic — see [MdStyles] and
/// `scripts/design/contrast.py`. The label is drawn from our own i18n keys
/// rather than the parser's built-in English title, so a Turkish document does
/// not sprout the word "Note".
///
/// The type is never carried by colour alone: there is an icon, and there is
/// the label in words.
library;

import 'package:flutter/material.dart';

import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import 'md_theme.dart';

class MdCallout extends StatelessWidget {
  const MdCallout({super.key, required this.kind, required this.children});

  final MdAlertKind kind;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final styles = MdStyles.of(context);
    final accent = styles.alertAccent(kind);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: AwSpace.x2),
      padding: const EdgeInsets.fromLTRB(
        AwSpace.x3,
        AwSpace.x3,
        AwSpace.x3,
        AwSpace.x3,
      ),
      decoration: BoxDecoration(
        color: styles.alertTint(kind),
        borderRadius: const BorderRadius.all(Radius.circular(AwRadius.m)),
        border: Border(left: BorderSide(color: accent, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(styles.alertIcon(kind), size: 18, color: accent),
              const SizedBox(width: AwSpace.x2),
              Text(
                styles.alertLabelKey(kind).tr(),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  // onSurface, not the accent: the accent fails 4.5:1 as text
                  // on its own card in light mode (warning measures 2.96).
                  color: styles.scheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: AwSpace.x1),
          ...children,
        ],
      ),
    );
  }
}
