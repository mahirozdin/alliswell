import 'package:flutter/material.dart';

import '../../../i18n/i18n.dart';

/// EE-212, EE-228 — the catalogue's icons, drawn from the app's own font.
///
/// The server keeps a CLOSED set of names (`categories.js` `SERVICE_ICONS`)
/// and refuses anything else at the door, precisely so a surface never has
/// to draw a blank square for a name it does not know. This is the app's
/// half of that promise: every name maps to a glyph. The list is mirrored in
/// the server's order because the picker offers exactly what a save accepts.
const kServiceIconTokens = [
  'wrench',
  'laptop',
  'printer',
  'network',
  'lock',
  'key',
  'mail',
  'phone',
  'building',
  'truck',
  'box',
  'chart',
  'people',
  'shield',
  'question',
];

/// The glyph for a token; the desk's generic one for none — and for a token
/// a newer server knows and this build does not, rather than nothing.
IconData serviceIconData(String? token) => switch (token) {
  'wrench' => Icons.build_outlined,
  'laptop' => Icons.laptop_outlined,
  'printer' => Icons.print_outlined,
  'network' => Icons.lan_outlined,
  'lock' => Icons.lock_outline,
  'key' => Icons.key_outlined,
  'mail' => Icons.mail_outline,
  'phone' => Icons.phone_outlined,
  'building' => Icons.apartment_outlined,
  'truck' => Icons.local_shipping_outlined,
  'box' => Icons.inventory_2_outlined,
  'chart' => Icons.insert_chart_outlined,
  'people' => Icons.people_outline,
  'shield' => Icons.shield_outlined,
  'question' => Icons.help_outline,
  _ => Icons.support_agent_outlined,
};

/// Picks one of [kServiceIconTokens], or none (null).
///
/// A grid of the glyphs themselves: the admin is choosing what a requester
/// will SEE, so the choice is made by looking, and each carries its name for
/// a screen reader. The selected one is the tonal button — the pair
/// `onSecondaryContainer` on `secondaryContainer`, measured in both themes.
class EeIconPicker extends StatelessWidget {
  const EeIconPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.keyPrefix = 'icon',
  });

  final String? value;
  final ValueChanged<String?>? onChanged;

  /// Test keys are `<prefix>-<token>` and `<prefix>-none`.
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    Widget choice(String? token, IconData glyph, String label) {
      final selected = value == token;
      final onPressed = onChanged == null ? null : () => onChanged!(token);
      final key = Key('$keyPrefix-${token ?? 'none'}');
      return selected
          ? IconButton.filledTonal(
              key: key,
              tooltip: label,
              isSelected: true,
              onPressed: onPressed,
              icon: Icon(glyph),
            )
          : IconButton(
              key: key,
              tooltip: label,
              onPressed: onPressed,
              icon: Icon(glyph),
            );
    }

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        choice(null, Icons.block_outlined, 'ee.team.services.iconNone'.tr()),
        for (final token in kServiceIconTokens)
          choice(
            token,
            serviceIconData(token),
            'ee.team.services.icons.$token'.tr(),
          ),
      ],
    );
  }
}
