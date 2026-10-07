import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../../workspaces/workspaces.dart';
import '../unit_scope_providers.dart';

/// A unit list's title: what the list is, and WHOSE it is (OPH-359,
/// UI-AUDIT #29).
///
/// The request queue, the knowledge base, changes, problems and meetings each
/// show the selected unit's copy, and none of them said which unit that was —
/// so an empty list could not be told from the wrong one. The unit's name
/// rides under the title whenever it is known.
class EeUnitScopedTitle extends ConsumerWidget {
  const EeUnitScopedTitle({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unit = ref.watch(eeUnitHereProvider).unit;
    if (unit == null) return Text(title);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        Text(
          unit.unitName,
          key: const Key('ee-unit-scope-name'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// The body of a unit list, or — when the selected workspace is not a unit —
/// a "choose a unit" state with the person's units to choose from.
///
/// "Nothing in this unit" said about the team's general space was a sentence
/// about a unit that was not there, beside a strip counting 70 breached
/// requests in the units that were. Unknown (offline with no answer yet, no
/// team) draws the list as before: guessing "not a unit" would hide a real one.
class EeUnitScopeGate extends ConsumerWidget {
  const EeUnitScopeGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final here = ref.watch(eeUnitHereProvider);
    if (here.state != EeUnitHereState.notUnit) return child;
    return AwEmptyState(
      key: const Key('ee-unit-scope-choose'),
      icon: Icons.workspaces_outline,
      title: 'ee.unitScope.chooseTitle'.tr(),
      message: here.units.isEmpty
          ? 'ee.unitScope.noUnitsBody'.tr()
          : 'ee.unitScope.chooseBody'.tr(),
      action: here.units.isEmpty
          ? null
          : Wrap(
              alignment: WrapAlignment.center,
              spacing: AwSpace.x2,
              runSpacing: AwSpace.x2,
              children: [
                for (final unit in here.units)
                  FilledButton.tonal(
                    key: Key('ee-unit-scope-pick-${unit.workspaceId}'),
                    onPressed: () => ref
                        .read(selectedWorkspaceIdProvider.notifier)
                        .select(unit.workspaceId),
                    child: Text(unit.unitName),
                  ),
              ],
            ),
    );
  }
}
