import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'sheets.dart';

/// One entry of a [showAwChoiceSheet].
class AwChoice<T> {
  const AwChoice({
    required this.id,
    required this.value,
    required this.label,
    this.leading,
  });

  /// Stable, readable id for the row's key: `aw-choice-<id>`.
  final String id;
  final T value;
  final String label;

  /// A mark before the label (a colour dot, a flag); null leaves the column
  /// empty so every label still starts on one x.
  final Widget? leading;
}

/// What the user did in a [showAwChoiceSheet]: picked [value], or took the
/// sheet's trailing action ([isAction], e.g. "+ Add project").
class AwChoicePick<T> {
  const AwChoicePick.value(this.value) : isAction = false;
  const AwChoicePick.action() : value = null, isAction = true;

  final T? value;
  final bool isAction;
}

/// The Glass choice pattern (OPH-403, H-6 — DESIGN §49 N6): a row of the
/// form opens a SOLID sheet (G1 — content, never glass) that lists the
/// choices, the current one marked with a check and announced as selected,
/// and an optional action row at the end. It replaces the Material dropdown,
/// whose floating-label box was a second input style on the same form.
///
/// Returns null when the user backs out — the caller keeps what it had.
Future<AwChoicePick<T>?> showAwChoiceSheet<T>(
  BuildContext context, {
  required String title,
  required List<AwChoice<T>> choices,
  required T? selected,
  String? actionLabel,
  IconData actionIcon = Icons.add,
}) {
  return showAwSheet<AwChoicePick<T>>(
    context,
    showDragHandle: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      final scheme = theme.colorScheme;
      return SafeArea(
        child: Column(
          key: const Key('aw-choice-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AwSpace.x5,
                0,
                AwSpace.x5,
                AwSpace.x2,
              ),
              child: Semantics(
                header: true,
                child: Text(title, style: theme.textTheme.titleMedium),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: AwSpace.x2),
                children: [
                  for (final choice in choices)
                    _ChoiceRow(
                      rowKey: Key('aw-choice-${choice.id}'),
                      leading: choice.leading,
                      label: choice.label,
                      selected: choice.value == selected,
                      onTap: () => Navigator.of(
                        sheetContext,
                      ).pop(AwChoicePick<T>.value(choice.value)),
                    ),
                  if (actionLabel != null)
                    ListTile(
                      key: const Key('aw-choice-action'),
                      leading: Icon(actionIcon, color: scheme.primary),
                      title: Text(
                        actionLabel,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onTap: () => Navigator.of(
                        sheetContext,
                      ).pop(AwChoicePick<T>.action()),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.rowKey,
    required this.leading,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  /// On the ListTile itself, so a test reads its `selected`.
  final Key rowKey;
  final Widget? leading;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListTile(
      key: rowKey,
      selected: selected,
      // The check carries the selection; the label keeps its own colour so
      // it reads at body contrast in both themes.
      selectedColor: scheme.onSurface,
      leading: SizedBox(
        width: 24,
        child: Center(child: leading ?? const SizedBox.shrink()),
      ),
      title: Text(
        label,
        style: selected
            ? theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)
            : null,
      ),
      trailing: selected ? Icon(Icons.check, color: scheme.primary) : null,
      onTap: onTap,
    );
  }
}
