import 'package:flutter/material.dart';

import '../core/list_sort.dart';
import '../i18n/i18n.dart';

/// A radio group shown above the sort block — Notes puts its list/grid view
/// here, so one app-bar button carries everything about *how the list looks*.
class AwMenuChoiceGroup {
  const AwMenuChoiceGroup({
    required this.titleKey,
    required this.choices,
    required this.selectedId,
    required this.onSelected,
  });

  final String titleKey;
  final List<AwSortChoice> choices;
  final String selectedId;
  final ValueChanged<String> onSelected;
}

/// The app-bar control for "how is this list ordered" (DESIGN §34 L2).
///
/// A menu rather than a row of segments, and a menu rather than a second icon:
/// the phone app bars in this app are measured to be at their limit (the Notes
/// bar already turned its file actions into one — `external_open_menu.dart`).
/// L1's whole point is that choosing an order must not cost a row of the list.
class AwSortMenuButton extends StatelessWidget {
  const AwSortMenuButton({
    super.key,
    required this.choices,
    required this.sort,
    required this.onChanged,
    this.groups = const [],
    this.icon = Icons.sort,
    this.tooltipKey = 'sort.tooltip',
  });

  final List<AwSortChoice> choices;
  final AwSortState sort;
  final ValueChanged<AwSortState> onChanged;

  /// Extra radio groups rendered above the sort options.
  final List<AwMenuChoiceGroup> groups;
  final IconData icon;
  final String tooltipKey;

  static const _reverseValue = '__reverse';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    PopupMenuItem<String> radio({
      required String value,
      required String labelKey,
      required bool selected,
    }) => PopupMenuItem<String>(
      key: Key('sort-option-$value'),
      value: value,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        // G5: the checkmark is the state, the label is the meaning — never
        // colour alone.
        leading: Icon(
          selected ? Icons.check : null,
          size: 20,
          color: theme.colorScheme.primary,
        ),
        title: Text(labelKey.tr()),
      ),
    );

    return PopupMenuButton<String>(
      key: const Key('list-sort-menu'),
      tooltip: tooltipKey.tr(),
      icon: Icon(icon),
      onSelected: (value) {
        if (value == _reverseValue) {
          onChanged(sort.reversed());
          return;
        }
        for (final group in groups) {
          if (value.startsWith('${group.titleKey}:')) {
            group.onSelected(value.substring(group.titleKey.length + 1));
            return;
          }
        }
        final picked = choices.firstWhere((c) => c.id == value);
        onChanged(sort.select(picked));
      },
      itemBuilder: (context) => [
        for (final group in groups) ...[
          PopupMenuItem<String>(
            enabled: false,
            height: 28,
            child: Text(
              group.titleKey.tr(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          for (final choice in group.choices)
            radio(
              value: '${group.titleKey}:${choice.id}',
              labelKey: choice.labelKey,
              selected: choice.id == group.selectedId,
            ),
          const PopupMenuDivider(),
        ],
        PopupMenuItem<String>(
          enabled: false,
          height: 28,
          child: Text(
            'sort.sectionTitle'.tr(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        for (final choice in choices)
          radio(
            value: choice.id,
            labelKey: choice.labelKey,
            selected: choice.id == sort.id,
          ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          key: const Key('sort-reverse'),
          value: _reverseValue,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: Icon(
              sort.descending ? Icons.arrow_downward : Icons.arrow_upward,
              size: 20,
            ),
            title: Text('sort.reverse'.tr()),
          ),
        ),
      ],
    );
  }
}
