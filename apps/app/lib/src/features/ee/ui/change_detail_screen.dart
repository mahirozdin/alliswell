import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error_messages.dart';
import '../../../core/persisted_prefs.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../changes_providers.dart';
import '../data/changes_models.dart';
import '../services_providers.dart';
import '../tickets_providers.dart';
import 'approval_reason_dialog.dart';
import 'change_labels.dart';
import 'ticket_detail_screen.dart';

/// Opens one change (EE-269) — by its address when a router is there, so the
/// list, a request's relations and the approver's queue reach the SAME screen
/// a link does, and by a plain push where the screen is hosted without one.
void awOpenChange(BuildContext context, String changeId) {
  if (GoRouter.maybeOf(context) != null) {
    context.push('/changes/$changeId');
    return;
  }
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => EeChangeDetailScreen(changeId: changeId),
    ),
  );
}

/// One change (EE-269, AW-E09): the plan from the device's copy, and what
/// only the server knows — who is asked to sign, what the window meets in the
/// calendar, what it touches, where it came from.
///
/// ── THE PLAN OPENS WITH NO SIGNAL ──────────────────────────────────────
///
/// Title, type, risk, window, impact and the way back are the replica's, so a
/// technician on a floor with no signal reads tonight's plan and its rollback.
/// The rest is asked every time and says so when it cannot be: a signature or
/// a freeze drawn from a copy would be old data passing for current.
///
/// ── THE SIGNATURE IS THE DOOR'S, NOT THE SCREEN'S ─────────────────────
///
/// The buttons appear only where the server said this person may decide
/// (`canDecide`: the row names them or a role they hold, AND they hold
/// `approvals.decide`). The decision goes through EE-184's door with a reason
/// — the same dialog as the approver's queue — and the door still decides.
class EeChangeDetailScreen extends ConsumerWidget {
  const EeChangeDetailScreen({super.key, required this.changeId});

  final String changeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = ref.watch(eeChangeOnDeviceProvider(changeId));
    final live = ref.watch(eeChangeLiveProvider(changeId));

    return Scaffold(
      appBar: AppBar(title: Text('ee.changes.detailTitle'.tr())),
      body: device.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AwErrorState(message: localizedError(error)),
        data: (onDevice) {
          // Not on this device: another unit's change (reached from a clash,
          // a request or the approver's queue), one just raised and not yet
          // pulled, or one EE-219 took off devices. The server's copy stands
          // in, labelled as such — or, with no signal, the screen says the
          // change exists elsewhere rather than that it does not exist.
          final change = onDevice ?? live.value?.change;
          if (change == null) {
            if (live.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            final offline = changeNeedsConnection(live.error);
            return AwEmptyState(
              key: const Key('change-not-on-device'),
              icon: offline ? Icons.cloud_off_outlined : Icons.event_busy,
              title: offline
                  ? 'ee.changes.notOnDevice'.tr()
                  : 'ee.changes.gone'.tr(),
              message: offline
                  ? 'ee.changes.notOnDeviceBody'.tr()
                  : 'ee.changes.goneBody'.tr(),
            );
          }
          return _Body(
            change: change,
            fromDevice: onDevice != null,
            live: live,
          );
        },
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.change,
    required this.fromDevice,
    required this.live,
  });

  final EeChange change;
  final bool fromDevice;
  final AsyncValue<EeChangeLive?> live;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final format = ref.watch(dateFormatProvider);
    final muted = theme.colorScheme.onSurfaceVariant;

    return ListView(
      padding: awListPadding(context, top: AwSpace.x4),
      children: [
        Text(change.title, style: theme.textTheme.titleLarge),
        const SizedBox(height: AwSpace.x2),
        EeChangeChips(change: change),
        const SizedBox(height: AwSpace.x3),
        Row(
          children: [
            Icon(Icons.schedule, size: 20, color: muted),
            const SizedBox(width: AwSpace.x2),
            Expanded(
              child: Text(
                change.hasWindow
                    ? changeWindowText(
                        change.windowStart!,
                        change.windowEnd!,
                        format: format,
                      )
                    : 'ee.changes.noWindow'.tr(),
                key: const Key('change-window'),
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
        if (!fromDevice) ...[
          const SizedBox(height: AwSpace.x2),
          Row(
            key: const Key('change-from-server'),
            children: [
              Icon(Icons.cloud_outlined, size: 18, color: muted),
              const SizedBox(width: AwSpace.x2),
              Expanded(
                child: Text(
                  'ee.changes.fromServer'.tr(),
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ),
            ],
          ),
        ],
        _Text(title: 'ee.changes.impact'.tr(), body: change.impact),
        if (change.rollbackPlan != null && change.rollbackPlan!.isNotEmpty)
          // Full text, never truncated: a way back cut in half is a wrong one.
          _Text(title: 'ee.changes.rollback'.tr(), body: change.rollbackPlan!),
        if (change.description != null && change.description!.isNotEmpty)
          _Text(
            title: 'ee.changes.description'.tr(),
            body: change.description!,
          ),
        const SizedBox(height: AwSpace.x2),
        _Live(change: change, live: live),
      ],
    );
  }
}

/// A titled block of the change's own words.
class _Text extends StatelessWidget {
  const _Text({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AwSpace.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          const SizedBox(height: AwSpace.x1),
          Text(body, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// The half only the server knows. One line when it cannot be asked.
class _Live extends ConsumerWidget {
  const _Live({required this.change, required this.live});

  final EeChange change;
  final AsyncValue<EeChangeLive?> live;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return live.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: AwSpace.x4),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) {
        if (changeNeedsConnection(error)) {
          return Padding(
            key: const Key('change-live-offline'),
            padding: const EdgeInsets.only(top: AwSpace.x4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.cloud_off_outlined, size: 18, color: muted),
                const SizedBox(width: AwSpace.x2),
                Expanded(
                  child: Text(
                    'ee.changes.live.offline'.tr(),
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ),
              ],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(top: AwSpace.x4),
          child: AwInlineError(message: localizedError(error)),
        );
      },
      data: (data) {
        // No entitlement: the endpoints do not exist and nothing was asked.
        if (data == null) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Signatures(changeId: change.id, approvals: data.approvals),
            _Calendar(change: data.change, conflicts: data.conflicts),
            if (data.change.sourceTicketId != null)
              _Source(ticketId: data.change.sourceTicketId!),
            _Services(serviceIds: data.change.serviceIds),
            if (data.assets.isNotEmpty) _Assets(assets: data.assets),
          ],
        );
      },
    );
  }
}

/// A section heading inside the live half.
class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AwSpace.x6, bottom: AwSpace.x2),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}

/// EE-269 box 2 — the board's signature, on the change.
class _Signatures extends ConsumerWidget {
  const _Signatures({required this.changeId, required this.approvals});

  final String changeId;
  final List<EeChangeApproval> approvals;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Heading('ee.changes.approval.title'.tr()),
        if (approvals.isEmpty)
          Text(
            'ee.changes.approval.none'.tr(),
            key: const Key('change-approval-none'),
            style: theme.textTheme.bodySmall,
          )
        else
          for (final approval in approvals)
            _SignatureCard(
              approval: approval,
              onDecide: (approve) => _decide(context, ref, approval, approve),
            ),
      ],
    );
  }

  Future<void> _decide(
    BuildContext context,
    WidgetRef ref,
    EeChangeApproval approval,
    bool approve,
  ) async {
    final reason = await askApprovalReason(context, approve: approve);
    if (reason == null || !context.mounted) return;
    try {
      await ref
          .read(eeChangeActionsProvider)
          .decide(
            changeId: changeId,
            approvalId: approval.id,
            approve: approve,
            reason: reason,
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            approve
                ? 'ee.changes.approval.approvedToast'.tr()
                : 'ee.changes.approval.rejectedToast'.tr(),
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      // The door's own sentence: "somebody answered first" and "you are not
      // the one asked" are different facts.
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(localizedError(error))));
    }
  }
}

class _SignatureCard extends StatelessWidget {
  const _SignatureCard({required this.approval, required this.onDecide});

  final EeChangeApproval approval;
  final void Function(bool approve) onDecide;

  /// Who is asked: a person or a custom role by name, a built-in role by the
  /// app's own word for it.
  String _who() =>
      approval.approverName ??
      (approval.approverRoleKey == null
          ? '—'
          : AwI18n.instance.maybeTranslate(
                  'ee.team.role.${approval.approverRoleKey}',
                ) ??
                approval.approverRoleKey!);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final String line;
    if (approval.isPending) {
      line = 'ee.changes.approval.pending'.tr(args: {'who': _who()});
    } else {
      final by = approval.decidedByName ?? _who();
      line = switch (approval.status) {
        'approved' => 'ee.changes.approval.approved'.tr(args: {'who': by}),
        'rejected' => 'ee.changes.approval.rejected'.tr(args: {'who': by}),
        _ =>
          AwI18n.instance.maybeTranslate(
                'ee.approvals.status.${approval.status}',
              ) ??
              approval.status,
      };
    }
    return Card(
      key: Key('change-approval-${approval.id}'),
      margin: const EdgeInsets.only(bottom: AwSpace.x2),
      child: Padding(
        padding: const EdgeInsets.all(AwSpace.x3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  approval.isPending
                      ? Icons.hourglass_top
                      : approval.status == 'approved'
                      ? Icons.verified_outlined
                      : Icons.block,
                  size: 20,
                ),
                const SizedBox(width: AwSpace.x2),
                Expanded(child: Text(line, style: theme.textTheme.bodyMedium)),
              ],
            ),
            if (approval.decisionReason != null) ...[
              const SizedBox(height: AwSpace.x2),
              Text(
                '“${approval.decisionReason}”',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (approval.canDecide) ...[
              const SizedBox(height: AwSpace.x2),
              Text(
                'ee.changes.approval.yours'.tr(),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: AwSpace.x2),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    key: Key('change-approval-reject-${approval.id}'),
                    onPressed: () => onDecide(false),
                    child: Text('ee.approvals.reject'.tr()),
                  ),
                  const SizedBox(width: AwSpace.x2),
                  FilledButton(
                    key: Key('change-approval-approve-${approval.id}'),
                    onPressed: () => onDecide(true),
                    child: Text('ee.approvals.approve'.tr()),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// EE-269 box 3 — what the window meets, each by name.
class _Calendar extends ConsumerWidget {
  const _Calendar({required this.change, required this.conflicts});

  final EeChange change;
  final EeChangeConflicts? conflicts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final format = ref.watch(dateFormatProvider);
    final c = conflicts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Heading('ee.changes.calendar.title'.tr()),
        if (c == null)
          Text(
            'ee.changes.calendar.noWindow'.tr(),
            style: theme.textTheme.bodySmall,
          )
        else if (c.isEmpty)
          Text(
            'ee.changes.calendar.clear'.tr(),
            key: const Key('change-calendar-clear'),
            style: theme.textTheme.bodySmall,
          )
        else ...[
          // A freeze first: it is the company having already decided, and
          // the scheduling door refuses what it covers (emergency aside).
          for (final freeze in c.freezes)
            _ConflictLine(
              key: Key('change-freeze-${freeze.id}'),
              icon: Icons.ac_unit,
              text: 'ee.changes.calendar.freeze'.tr(
                args: {
                  'reason': freeze.reason,
                  'window': changeWindowText(
                    freeze.startsAt,
                    freeze.endsAt,
                    format: format,
                  ),
                },
              ),
            ),
          // A clash WARNS (EE-187): two changes on one service in one window
          // is sometimes exactly right. The screen says so and a person
          // decides — and the other change opens from here.
          for (final clash in c.clashes)
            _ConflictLine(
              key: Key('change-clash-${clash.changeId}'),
              icon: Icons.call_split,
              text: 'ee.changes.calendar.clash'.tr(
                args: {
                  'title': clash.title,
                  'window': changeWindowText(
                    clash.windowStart,
                    clash.windowEnd,
                    format: format,
                  ),
                },
              ),
              onTap: () => awOpenChange(context, clash.changeId),
            ),
        ],
      ],
    );
  }
}

class _ConflictLine extends StatelessWidget {
  const _ConflictLine({
    super.key,
    required this.icon,
    required this.text,
    this.onTap,
  });

  final IconData icon;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: AwSpace.x2),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AwSpace.x3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: theme.colorScheme.error),
              const SizedBox(width: AwSpace.x2),
              Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
              if (onTap != null) const Icon(Icons.chevron_right, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// EE-279 — the request this change was raised from.
class _Source extends ConsumerWidget {
  const _Source({required this.ticketId});

  final String ticketId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The device's copy names it when it holds it; otherwise the row still
    // opens it — the request's own screen knows where it lives now (EE-266).
    final ticket = ref.watch(ticketProvider(ticketId)).value;
    final label = ticket == null
        ? 'ee.changes.source.open'.tr()
        : [
            if (ticket.number != null) '#${ticket.number}',
            ticket.subject,
          ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Heading('ee.changes.source.title'.tr()),
        Card(
          key: const Key('change-source'),
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            leading: const Icon(Icons.support_agent),
            title: Text(label),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => awOpenTicket(context, ticketId),
          ),
        ),
      ],
    );
  }
}

/// The services it touches — the set EE-187's clash is computed over.
class _Services extends ConsumerWidget {
  const _Services({required this.serviceIds});

  final List<String> serviceIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (serviceIds.isEmpty) return const SizedBox.shrink();
    // EE-284: names every member can read, not only the admin list's.
    final names = {
      for (final s in ref.watch(eeServiceGlancesProvider).values) s.id: s.name,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Heading('ee.changes.services'.tr()),
        Wrap(
          spacing: AwSpace.x2,
          runSpacing: AwSpace.x1,
          children: [
            for (final id in serviceIds)
              // A service the catalogue does not name (archived, or the
              // catalogue could not be read) is still one this touches.
              Chip(
                key: Key('change-service-$id'),
                label: Text(names[id] ?? 'ee.changes.serviceUnknown'.tr()),
              ),
          ],
        ),
      ],
    );
  }
}

class _Assets extends StatelessWidget {
  const _Assets({required this.assets});

  final List<EeChangeAsset> assets;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _Heading('ee.changes.assets'.tr()),
      for (final asset in assets)
        ListTile(
          key: Key('change-asset-${asset.assetId}'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: const Icon(Icons.precision_manufacturing_outlined),
          // Tag first: it is painted on the machine.
          title: Text('${asset.tag} · ${asset.name}'),
          subtitle: Text(
            [
              'ee.assets.status.${asset.status}'.tr(),
              if (asset.location != null) asset.location!,
            ].join(' · '),
          ),
        ),
    ],
  );
}
