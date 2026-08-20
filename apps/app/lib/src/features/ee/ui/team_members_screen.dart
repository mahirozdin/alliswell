import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_messages.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../data/team_admin_models.dart';
import '../team_admin_providers.dart';

/// The management roster (EE-042).
///
/// Three rules the layout follows, all of them about not lying:
///
///   • THE SEAT BANNER IS ALWAYS VISIBLE, because every decision here is made
///     against it — and "already over" is shown differently from "cannot add
///     one more", since they are different problems with different fixes.
///   • A DEACTIVATED MEMBER STAYS ON THE LIST, dimmed and labelled. Hiding
///     them would make "where did Cem go?" unanswerable in the one place
///     built to answer it.
///   • EVERY DESTRUCTIVE ACTION SAYS WHAT IT WILL DO FIRST. Removal is not
///     undoable — coming back needs a new invitation — and deactivation is,
///     so the two are never one tap apart without a sentence in between.
class EeTeamMembersScreen extends ConsumerWidget {
  const EeTeamMembersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roster = ref.watch(eeTeamRosterProvider);
    return Scaffold(
      appBar: AppBar(title: Text('ee.team.members.title'.tr())),
      body: roster.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AwErrorState(
          message: localizedError(error),
          onRetry: () => ref.invalidate(eeTeamRosterProvider),
        ),
        data: (data) => ListView(
          padding: const EdgeInsets.all(AwSpace.x4),
          children: [
            _SeatBanner(seats: data.seats),
            const SizedBox(height: AwSpace.x4),
            for (final member in data.members)
              _MemberTile(key: Key('member-${member.userId}'), member: member),
          ],
        ),
      ),
    );
  }
}

class _SeatBanner extends StatelessWidget {
  const _SeatBanner({required this.seats});
  final EeSeats seats;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // "Over the plan" and "cannot add one more" are different sentences on
    // purpose: the first is a billing conversation, the second is a blocked
    // action, and telling somebody the wrong one wastes their afternoon.
    final over = seats.exceeded;
    return Card(
      key: const Key('team-seat-banner'),
      color: over ? scheme.errorContainer : null,
      child: ListTile(
        leading: Icon(
          over ? Icons.error_outline : Icons.event_seat_outlined,
          color: over ? scheme.onErrorContainer : null,
        ),
        title: Text(
          seats.max == null
              ? 'ee.team.seats.unlimited'.tr(args: {'used': '${seats.used}'})
              : 'ee.team.seats.count'.tr(
                  args: {'used': '${seats.used}', 'max': '${seats.max}'},
                ),
        ),
        subtitle: Text(
          over
              ? 'ee.team.seats.over'.tr()
              : seats.pending > 0
              ? 'ee.team.seats.pending'.tr(args: {'n': '${seats.pending}'})
              : 'ee.team.seats.room'.tr(),
        ),
      ),
    );
  }
}

class _MemberTile extends ConsumerWidget {
  const _MemberTile({super.key, required this.member});
  final EeTeamMember member;

  Color? _color() {
    final hex = member.colorRgb;
    if (hex == null || hex.length != 7) return null;
    return Color(int.parse('FF${hex.substring(1)}', radix: 16));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(eeTeamRosterProvider.notifier);
    final dimmed = !member.active;
    return Opacity(
      opacity: dimmed ? 0.55 : 1,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _color(),
          child: Text(
            member.initials ?? '?',
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ),
        title: Text(member.label),
        subtitle: Text(
          [
            'ee.team.role.${member.role}'.tr(),
            if (dimmed) 'ee.team.members.deactivated'.tr(),
            if (member.email != null) member.email!,
          ].join(' · '),
        ),
        trailing: PopupMenuButton<String>(
          key: Key('member-menu-${member.userId}'),
          onSelected: (action) => _run(context, ref, controller, action),
          itemBuilder: (context) => [
            if (member.active)
              PopupMenuItem(
                value: 'deactivate',
                child: Text('ee.team.members.deactivate'.tr()),
              )
            else
              PopupMenuItem(
                value: 'reactivate',
                child: Text('ee.team.members.reactivate'.tr()),
              ),
            if (member.role != 'admin' && member.role != 'owner')
              PopupMenuItem(
                value: 'promote',
                child: Text('ee.team.members.promote'.tr()),
              ),
            if (member.role == 'admin')
              PopupMenuItem(
                value: 'demote',
                child: Text('ee.team.members.demote'.tr()),
              ),
            PopupMenuItem(
              value: 'remove',
              child: Text('ee.team.members.remove'.tr()),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    EeRosterController controller,
    String action,
  ) async {
    // The one action that cannot be undone asks first, and says why in the
    // same breath — deactivation is right there and it IS reversible.
    if (action == 'remove') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('ee.team.members.removeTitle'.tr()),
          content: Text(
            'ee.team.members.removeBody'.tr(args: {'name': member.label}),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('common.cancel'.tr()),
            ),
            FilledButton(
              key: const Key('member-remove-confirm'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text('ee.team.members.remove'.tr()),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    switch (action) {
      case 'deactivate':
        await controller.deactivate(member.userId);
      case 'reactivate':
        await controller.reactivate(member.userId);
      case 'promote':
        await controller.setRole(member.userId, 'admin');
      case 'demote':
        await controller.setRole(member.userId, 'member');
      case 'remove':
        await controller.remove(member.userId);
    }
  }
}
