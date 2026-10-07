import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/date_format.dart';
import '../../../core/day_boundary.dart';
import '../../../core/persisted_prefs.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../data/approvals_models.dart';
import 'change_labels.dart';

/// "Mehmet Kaya" → "MK". The approver may hold no roster copy of the person
/// who asked (they are usually not in the unit), so the initials come from
/// the name the server resolved.
String approvalInitials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  final first = parts.first.characters.first;
  final last = parts.length > 1 ? parts.last.characters.first : '';
  return (first + last).toUpperCase();
}

/// The line under a title: `#1042 · Laptop` or "What this was about is gone".
String approvalTitle(EeApproval approval) {
  final target = approval.target;
  if (target == null) return 'ee.approvals.targetGone'.tr();
  return [
    if (target.number != null) '#${target.number}',
    target.title,
  ].join(' · ');
}

/// An approval's state in words (OPH-358, UI-AUDIT #14). `withdrawn` is
/// EE-302's: the request it asked about was cancelled or closed, so nobody
/// needs to answer it. A state this build does not know reads as a neutral
/// word — never the raw key.
String approvalStatusLabel(String status) =>
    AwI18n.instance.maybeTranslate('ee.approvals.status.$status') ??
    'ee.approvals.statusUnknown'.tr();

/// Who is being asked — a person's or a custom role's name, else a built-in
/// role's word in this language.
String approvalWaitingOn(EeApproval approval) {
  if (approval.approverName case final name?) return name;
  if (approval.approverRoleKey case final key?) {
    return AwI18n.instance.maybeTranslate('ee.team.role.$key') ?? key;
  }
  return '—';
}

/// One approval in the approver's queue (EE-294).
///
/// The owner's report named what a row was missing: WHO opened the request,
/// WHEN, and WHAT it says. A row now reads, top to bottom: what kind of thing
/// and which one; who asked and when; the service and the desk (a change's
/// type, risk and window; a task's due date); the first lines of what they
/// wrote; and when the approval was asked, by whom if not them, until when,
/// and how far the signatures have got. The buttons come last and only where
/// the door would accept them ([EeApproval.actionable]).
///
/// Every row opens (EE-295 gives it somewhere to go); [onOpen] null draws no
/// chevron.
class EeApprovalCard extends ConsumerWidget {
  const EeApprovalCard({
    super.key,
    required this.approval,
    this.onOpen,
    this.onDecide,
  });

  final EeApproval approval;
  final VoidCallback? onOpen;
  final void Function(bool approve)? onDecide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final muted = theme.colorScheme.onSurfaceVariant;
    final format = ref.watch(dateFormatProvider);
    final now = ref.watch(nowProvider)();
    final ctx = approval.context;
    final target = approval.target;

    final kindLabel = 'ee.approvals.kind.${approval.targetType}'.tr();
    final detail = _detailLine(ctx, format, now);
    final asked = [
      'ee.approvals.askedAgo'.tr(
        args: {'when': awRelativePast(approval.createdAt, now)},
      ),
      if (approval.requestedByName case final by? when by != ctx?.requesterName)
        'ee.approvals.askedBy'.tr(args: {'name': by}),
      if (approval.dueAt case final due?)
        'ee.approvals.dueShort'.tr(
          args: {'date': awFormatShort(due, format: format, withTime: false)},
        ),
      if (approval.progress.total > 1)
        'ee.approvals.progress'.tr(
          args: {
            'approved': '${approval.progress.approved}',
            'total': '${approval.progress.total}',
          },
        ),
    ].join(' · ');
    // A service rule asks with the service's name as its reason, which the
    // detail line already says; a desk member's own sentence is worth its
    // own line.
    final reason = approval.requestReason;
    final showReason =
        reason != null && reason.isNotEmpty && reason != ctx?.serviceName;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('ee-approval-open-${approval.id}'),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(AwSpace.x4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _KindChip(label: kindLabel),
                  const SizedBox(width: AwSpace.x2),
                  Expanded(
                    child: Text(
                      approvalTitle(approval),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium,
                    ),
                  ),
                  if (onOpen != null) Icon(Icons.chevron_right, color: muted),
                ],
              ),
              if (ctx?.requesterName case final who?) ...[
                const SizedBox(height: AwSpace.x2),
                Row(
                  children: [
                    _InitialsAvatar(name: who),
                    const SizedBox(width: AwSpace.x2),
                    Expanded(
                      child: Text(
                        [
                          who,
                          if (ctx!.requesterKind case final kind?
                              when kind != 'member')
                            'ee.approvals.via.$kind'.tr(),
                          if (ctx.openedAt case final opened?)
                            '${awRelativePast(opened, now)} · '
                                '${awFormatShort(opened, format: format)}',
                        ].join(' · '),
                        key: Key('ee-approval-requester-${approval.id}'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ],
              if (detail.isNotEmpty) ...[
                const SizedBox(height: AwSpace.x1),
                Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(color: muted),
                ),
              ],
              if (ctx?.excerpt case final excerpt?) ...[
                const SizedBox(height: AwSpace.x2),
                Text(
                  excerpt,
                  key: Key('ee-approval-excerpt-${approval.id}'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium?.copyWith(color: muted),
                ),
              ],
              if (showReason) ...[
                const SizedBox(height: AwSpace.x2),
                Text('“$reason”', style: text.bodyMedium),
              ],
              const SizedBox(height: AwSpace.x2),
              Text(
                asked,
                key: Key('ee-approval-asked-${approval.id}'),
                style: text.bodySmall?.copyWith(color: muted),
              ),
              if (approval.addressedTo == 'other' && approval.isPending) ...[
                const SizedBox(height: AwSpace.x1),
                Text(
                  'ee.approvals.waitingOn'.tr(
                    args: {'who': approvalWaitingOn(approval)},
                  ),
                  style: text.bodySmall?.copyWith(color: muted),
                ),
              ],
              if (!approval.live) ...[
                const SizedBox(height: AwSpace.x1),
                Text(
                  target == null
                      ? 'ee.approvals.notLiveGone'.tr()
                      : 'ee.approvals.notLiveCancelled'.tr(),
                  style: text.bodySmall?.copyWith(color: muted),
                ),
              ],
              if (!approval.isPending) ...[
                const SizedBox(height: AwSpace.x2),
                Text(
                  approvalStatusLabel(approval.status),
                  key: Key('ee-approval-status-${approval.id}'),
                  style: text.bodySmall,
                ),
                if (approval.decisionReason != null)
                  Text(approval.decisionReason!, style: text.bodySmall),
              ],
              if (approval.actionable && onDecide != null) ...[
                const SizedBox(height: AwSpace.x3),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      key: Key('ee-approval-reject-${approval.id}'),
                      onPressed: () => onDecide!(false),
                      child: Text('ee.approvals.reject'.tr()),
                    ),
                    const SizedBox(width: AwSpace.x2),
                    FilledButton(
                      key: Key('ee-approval-approve-${approval.id}'),
                      onPressed: () => onDecide!(true),
                      child: Text('ee.approvals.approve'.tr()),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Service · desk for a request; type · risk · window for a change; the
  /// due date for a task.
  String _detailLine(EeApprovalContext? ctx, String format, DateTime now) {
    if (ctx == null) return '';
    return switch (approval.targetType) {
      'ee_change' => [
        if (ctx.changeType case final type?) 'ee.changes.type.$type'.tr(),
        if (ctx.risk case final risk?) 'ee.changes.risk.$risk'.tr(),
        if ((ctx.windowStart, ctx.windowEnd) case (final s?, final e?))
          changeWindowText(s, e, format: format),
        // UI-AUDIT #77: still asking for a signature on a night gone by.
        if (approval.isPending && (ctx.windowEnd?.isBefore(now) ?? false))
          'ee.changes.windowPassed'.tr(),
      ].join(' · '),
      'task' => [
        if (ctx.taskDueAt case final due?)
          'ee.approvals.taskDue'.tr(
            args: {'date': awFormatShort(due, format: format)},
          ),
        ?ctx.unitName,
      ].join(' · '),
      _ => [
        ?ctx.serviceName,
        ?ctx.unitName,
        if (ctx.priority case final p? when p != 'normal')
          'ee.tickets.priority.$p'.tr(),
      ].join(' · '),
    };
  }
}

/// Who asked, as a face: their initials in a ringed circle. Not
/// `AwPersonAvatar` — that one wears a ROSTER colour and draws a tombstone
/// for anybody it has none for, and the person who asked is usually not on
/// the approver's roster at all. Token colours only; the ring is the
/// contrast, as it is on the roster's avatar.
class _InitialsAvatar extends StatelessWidget {
  const _InitialsAvatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      label: name,
      excludeSemantics: true,
      child: Container(
        width: 24,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          shape: BoxShape.circle,
          border: Border.all(color: scheme.outline, width: 1),
        ),
        child: Text(
          approvalInitials(name),
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
      ),
    );
  }
}

class _KindChip extends StatelessWidget {
  const _KindChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.symmetric(horizontal: AwSpace.x2, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(AwRadius.s),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: scheme.onSecondaryContainer),
      ),
    );
  }
}
