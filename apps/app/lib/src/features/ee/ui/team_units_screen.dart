import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_messages.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../data/units_models.dart';
import '../providers.dart';
import '../units_providers.dart';

/// Units, and the people in them (EE-057).
///
/// One screen serves two very different callers, and the layout is what keeps
/// that honest:
///
///   • A TEAM ADMIN sees every unit and may change the team's shape — open a
///     unit, rename it, retire it, appoint a manager.
///   • A DELEGATED MANAGER sees only the units they run, and may only staff
///     them. No "new unit" button, no rename, no archive: those are
///     `units.manage`, which they do not hold, and drawing a control that
///     answers 403 is a small lie an app tells its own user (DESIGN §22 /
///     EE-052's rule — ask what this person may do BEFORE drawing a button).
///
/// The row carries its member count for the same reason the role list does:
/// "may I narrow this?" cannot be answered without knowing whom it touches.
class EeTeamUnitsScreen extends ConsumerWidget {
  const EeTeamUnitsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final units = ref.watch(eeUnitsProvider);
    // `units.manage` is purely role-based, so this gate is honest for both
    // callers: an admin holds it, a delegated manager never does.
    final mayShape = ref.watch(canProvider('units.manage'));

    return Scaffold(
      appBar: AppBar(title: Text('ee.team.units.title'.tr())),
      floatingActionButton: mayShape
          ? FloatingActionButton(
              key: const Key('unit-new'),
              tooltip: 'ee.team.units.create'.tr(),
              onPressed: () => _rename(context, ref, null),
              child: const Icon(Icons.add),
            )
          : null,
      body: units.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AwErrorState(
          message: localizedError(error),
          onRetry: () => ref.invalidate(eeUnitsProvider),
        ),
        data: (list) {
          // Null is "you may act on no unit" — the screen should not have been
          // reachable, but a stale link can still land here.
          if (list == null) {
            return AwEmptyState(
              icon: Icons.lock_outline,
              title: 'ee.team.units.noneTitle'.tr(),
              message: 'ee.team.units.noneBody'.tr(),
            );
          }
          if (list.isEmpty) {
            return AwEmptyState(
              icon: Icons.apartment_outlined,
              title: 'ee.team.units.emptyTitle'.tr(),
              message: 'ee.team.units.emptyBody'.tr(),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(AwSpace.x4),
            children: [
              Text(
                mayShape
                    ? 'ee.team.units.intro'.tr()
                    : 'ee.team.units.introManager'.tr(),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AwSpace.x3),
              for (final unit in list)
                _UnitCard(unit: unit, mayShape: mayShape),
            ],
          );
        },
      ),
    );
  }

  /// Null unit = opening a new one. Same sheet either way: naming a unit and
  /// renaming one are the same act with a different starting value.
  static Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    EeUnit? unit,
  ) async {
    final controller = TextEditingController(text: unit?.name ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          unit == null
              ? 'ee.team.units.create'.tr()
              : 'ee.team.units.rename'.tr(),
        ),
        content: TextField(
          key: const Key('unit-name'),
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: 'ee.team.units.name'.tr()),
          onSubmitted: (value) => Navigator.of(ctx).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            key: const Key('unit-name-save'),
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text('common.save'.tr()),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final notifier = ref.read(eeUnitsProvider.notifier);
    if (unit == null) {
      await notifier.create(name);
    } else {
      await notifier.rename(unit.id, name);
    }
  }
}

class _UnitCard extends ConsumerWidget {
  const _UnitCard({required this.unit, required this.mayShape});

  final EeUnit unit;
  final bool mayShape;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      key: Key('unit-${unit.id}'),
      child: ListTile(
        leading: Icon(
          unit.archived ? Icons.inventory_2_outlined : Icons.apartment_outlined,
          // An archived unit reads as retired, not as broken: the row is
          // muted, never struck through or coloured like an error.
          color: unit.archived ? theme.disabledColor : null,
        ),
        title: Text(unit.name),
        subtitle: Text(
          [
            'ee.team.units.memberCount'.tr(
              args: {'count': '${unit.memberCount}'},
            ),
            if (unit.archived) 'ee.team.units.archived'.tr(),
            // Only ever shown to somebody who IS the delegate — an admin sees
            // no badge, because "I run this one" is not true of them.
            if (unit.manages) 'ee.team.units.youManage'.tr(),
          ].join(' · '),
          style: theme.textTheme.bodySmall,
        ),
        trailing: mayShape
            ? PopupMenuButton<String>(
                key: Key('unit-menu-${unit.id}'),
                onSelected: (value) async {
                  switch (value) {
                    case 'rename':
                      await EeTeamUnitsScreen._rename(context, ref, unit);
                    case 'archive':
                      await ref
                          .read(eeUnitsProvider.notifier)
                          .setArchived(unit.id, archived: !unit.archived);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'rename',
                    child: Text('ee.team.units.rename'.tr()),
                  ),
                  PopupMenuItem(
                    value: 'archive',
                    child: Text(
                      unit.archived
                          ? 'ee.team.units.unarchive'.tr()
                          : 'ee.team.units.archive'.tr(),
                    ),
                  ),
                ],
              )
            : const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => EeUnitMembersScreen(unit: unit),
          ),
        ),
      ),
    );
  }
}

/// One unit's roster. Reachable by both callers — staffing a unit is exactly
/// what a delegated manager is for.
class EeUnitMembersScreen extends ConsumerWidget {
  const EeUnitMembersScreen({required this.unit, super.key});

  final EeUnit unit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(eeUnitMembersProvider(unit.id));
    final mayAppoint = ref.watch(canProvider('units.manage'));
    final actions = ref.read(eeUnitMemberActionsProvider(unit.id));

    return Scaffold(
      appBar: AppBar(title: Text(unit.name)),
      floatingActionButton: FloatingActionButton(
        key: const Key('unit-member-add'),
        tooltip: 'ee.team.units.addMember'.tr(),
        onPressed: () => _pick(context, ref, actions),
        child: const Icon(Icons.person_add_alt),
      ),
      body: members.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AwErrorState(
          message: localizedError(error),
          onRetry: () => ref.invalidate(eeUnitMembersProvider(unit.id)),
        ),
        data: (list) => ListView(
          padding: const EdgeInsets.all(AwSpace.x4),
          children: [
            for (final member in list)
              Card(
                key: Key('unit-member-${member.userId}'),
                child: ListTile(
                  leading: Icon(
                    member.isManager
                        ? Icons.manage_accounts_outlined
                        : Icons.person_outline,
                  ),
                  title: Text(member.label),
                  subtitle: member.isManager
                      ? Text('ee.team.units.manager'.tr())
                      : null,
                  trailing: PopupMenuButton<String>(
                    key: Key('unit-member-menu-${member.userId}'),
                    onSelected: (value) async {
                      switch (value) {
                        case 'promote':
                          await actions.setRole(member.userId, 'manager');
                        case 'demote':
                          await actions.setRole(member.userId, 'member');
                        case 'remove':
                          await actions.remove(member.userId);
                      }
                    },
                    itemBuilder: (_) => [
                      // Appointing a manager is TEAM authority: a delegated
                      // manager cannot grow their own delegation, so the
                      // control is absent rather than refused.
                      if (mayAppoint)
                        PopupMenuItem(
                          value: member.isManager ? 'demote' : 'promote',
                          child: Text(
                            member.isManager
                                ? 'ee.team.units.demote'.tr()
                                : 'ee.team.units.promote'.tr(),
                          ),
                        ),
                      PopupMenuItem(
                        value: 'remove',
                        child: Text('ee.team.units.removeMember'.tr()),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pick(
    BuildContext context,
    WidgetRef ref,
    EeUnitMemberActions actions,
  ) async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => Consumer(
        builder: (_, sheetRef, _) => sheetRef
            .watch(eeUnitCandidatesProvider(unit.id))
            .when(
              loading: () => const Padding(
                padding: EdgeInsets.all(AwSpace.x6),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => Padding(
                padding: const EdgeInsets.all(AwSpace.x6),
                child: Text(localizedError(error)),
              ),
              data: (candidates) => candidates.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(AwSpace.x6),
                      child: Text('ee.team.units.noCandidates'.tr()),
                    )
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        for (final candidate in candidates)
                          ListTile(
                            key: Key('unit-candidate-${candidate.userId}'),
                            leading: const Icon(Icons.person_outline),
                            title: Text(candidate.label),
                            onTap: () =>
                                Navigator.of(ctx).pop(candidate.userId),
                          ),
                      ],
                    ),
            ),
      ),
    );
    if (chosen != null) await actions.add(chosen);
  }
}
