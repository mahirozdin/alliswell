import 'package:flutter/material.dart';

import '../../core/list_sort.dart';
import '../../i18n/i18n.dart';
import '../../theme/tokens.dart';
import '../../widgets/popup_menu.dart';

/// Home's "View ⌄" on a phone (OPH-398, ADR-0062 §6, DESIGN §16 H5).
///
/// The phone's app bar carries at most three targets — ⚡, this, Settings —
/// so list/board, the calendar and the order (or, on the board, its columns)
/// share one labelled menu instead of four unlabelled icons (R-05, C-03). It
/// is the Notes precedent (§34 L2) applied to Home: the escape from a full
/// bar is a menu, not another icon.
///
/// The button shows the current view's glyph and a ⌄, so it reads as "how
/// this list looks" before it is opened; its tooltip and screen-reader label
/// say "View".
class HomeViewMenuButton extends StatelessWidget {
  const HomeViewMenuButton({
    super.key,
    required this.isBoard,
    required this.calendarVisible,
    required this.sortChoices,
    required this.sort,
    required this.onView,
    required this.onToggleCalendar,
    required this.onSort,
    required this.onEditColumns,
  });

  final bool isBoard;
  final bool calendarVisible;
  final List<AwSortChoice> sortChoices;
  final AwSortState sort;

  /// 'list' or 'board'.
  final ValueChanged<String> onView;
  final VoidCallback onToggleCalendar;
  final ValueChanged<AwSortState> onSort;
  final VoidCallback onEditColumns;

  static const _list = 'view:list';
  static const _board = 'view:board';
  static const _calendar = 'calendar';
  static const _columns = 'columns';
  static const _reverse = 'sort:__reverse';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    PopupMenuItem<String> header(String key) => PopupMenuItem<String>(
      enabled: false,
      height: 28,
      child: Text(
        key.tr(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
    );

    PopupMenuItem<String> item({
      required Key key,
      required String value,
      required String label,
      IconData? leading,
      bool checked = false,
      bool selectable = false,
    }) => PopupMenuItem<String>(
      key: key,
      value: value,
      // OPH-407 (T-07): a choice says it is the selected one; an action
      // (calendar, columns, reverse) is never announced as selected.
      child: Semantics(
        selected: selectable ? checked : null,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          // G5: the check is the state, the label is the meaning.
          leading: Icon(
            checked ? Icons.check : leading,
            size: 20,
            color: checked ? scheme.primary : null,
          ),
          title: Text(label),
        ),
      ),
    );

    return AwPopupMenuButton<String>(
      key: const Key('home-view-menu'),
      tooltip: 'home.viewMenu'.tr(),
      onSelected: (value) {
        switch (value) {
          case _list:
            onView('list');
          case _board:
            onView('board');
          case _calendar:
            onToggleCalendar();
          case _columns:
            onEditColumns();
          case _reverse:
            onSort(sort.reversed());
          default:
            if (value.startsWith('sort:')) {
              final id = value.substring(5);
              onSort(sort.select(sortChoices.firstWhere((c) => c.id == id)));
            }
        }
      },
      itemBuilder: (context) => [
        header('home.viewMenu'),
        item(
          key: const Key('home-view-list'),
          value: _list,
          label: 'board.viewList'.tr(),
          checked: !isBoard,
          selectable: true,
        ),
        item(
          key: const Key('home-view-board'),
          value: _board,
          label: 'board.viewBoard'.tr(),
          checked: isBoard,
          selectable: true,
        ),
        const PopupMenuDivider(),
        if (isBoard)
          item(
            key: const Key('board-edit-columns'),
            value: _columns,
            label: 'board.editColumns'.tr(),
            leading: Icons.tune,
          )
        else ...[
          item(
            key: const Key('toggle-calendar'),
            value: _calendar,
            label: calendarVisible
                ? 'home.hideCalendar'.tr()
                : 'home.showCalendar'.tr(),
            leading: calendarVisible
                ? Icons.calendar_month
                : Icons.calendar_month_outlined,
          ),
          // §16: the order applies INSIDE each day group; the board's
          // columns carry their own, so it is offered on the list only.
          const PopupMenuDivider(),
          header('sort.sectionTitle'),
          for (final choice in sortChoices)
            item(
              key: Key('sort-option-${choice.id}'),
              value: 'sort:${choice.id}',
              label: choice.labelKey.tr(),
              checked: choice.id == sort.id,
              selectable: true,
            ),
          item(
            key: const Key('sort-reverse'),
            value: _reverse,
            label: 'sort.reverse'.tr(),
            leading: sort.descending
                ? Icons.arrow_downward
                : Icons.arrow_upward,
          ),
        ],
      ],
      // G4: a 48 × 48 target at least; the glyph never scales with text, so
      // the bar keeps its room for the title at 2.0× (OPH-398 Kabul).
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AwSpace.x2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isBoard
                    ? Icons.view_kanban_outlined
                    : Icons.view_agenda_outlined,
                size: 24,
              ),
              const Icon(Icons.arrow_drop_down, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
