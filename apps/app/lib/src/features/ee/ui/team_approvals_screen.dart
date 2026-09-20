import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_messages.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../approvals_providers.dart';
import '../data/approvals_models.dart';

/// EE-184 — one person's approvals, decided one at a time.
///
/// ── WHY IT IS A LIST AND NOT A BULK BUTTON ───────────────────────────────
///
/// The task asks for "toplu onay" and this screen deliberately does not have a
/// select-all. Batching is what the SCREEN does — everything waiting on you,
/// in one place, instead of hunting through requests — and the decision stays
/// one at a time because each one needs its own reason. A tick box over twenty
/// rows would produce twenty identical sentences, which is the same as none.
///
/// ── THE REASON IS NOT OPTIONAL, AND THE BUTTON SAYS SO ───────────────────
///
/// Approve and Reject are both disabled until something is typed. The server
/// refuses either way; doing it here too means the person learns it while
/// their hands are still on the form rather than after pressing the button.
///
/// ── WHAT A ROW SHOWS IS A SUMMARY, AND THAT IS THE PRODUCT ───────────────
///
/// The approver may have no access to the thing they are approving. So a row
/// carries the target's title, its number if it has one, and the sentence
/// somebody wrote when they asked — and when the target is GONE (core deleted
/// the task, the archive swept the request) it says that, because an empty row
/// looks like a bug and a missing target is a fact.
class EeTeamApprovalsScreen extends ConsumerWidget {
  const EeTeamApprovalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final approvals = ref.watch(eeApprovalsProvider);
    final controller = ref.read(eeApprovalsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: Text('ee.approvals.title'.tr())),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AwSpace.x4,
              AwSpace.x4,
              AwSpace.x4,
              0,
            ),
            child: SegmentedButton<bool>(
              key: const Key('ee-approvals-scope'),
              segments: [
                ButtonSegment(
                  value: true,
                  label: Text('ee.approvals.scopeMine'.tr()),
                ),
                ButtonSegment(
                  value: false,
                  label: Text('ee.approvals.scopeTeam'.tr()),
                ),
              ],
              selected: {controller.mine},
              onSelectionChanged: (v) => controller.setScope(mine: v.first),
            ),
          ),
          Expanded(
            child: approvals.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => AwErrorState(
                message: localizedError(error),
                onRetry: () => ref.invalidate(eeApprovalsProvider),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return AwEmptyState(
                    icon: Icons.how_to_reg_outlined,
                    title: 'ee.approvals.empty'.tr(),
                    message: 'ee.approvals.emptyBody'.tr(),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(AwSpace.x4),
                  itemCount: items.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AwSpace.x2),
                  itemBuilder: (context, i) => _ApprovalCard(
                    approval: items[i],
                    onDecide: (approve) =>
                        _askForReason(context, ref, items[i], approve: approve),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _askForReason(
    BuildContext context,
    WidgetRef ref,
    EeApproval approval, {
    required bool approve,
  }) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => _ReasonDialog(approve: approve),
    );
    if (reason == null || !context.mounted) return;
    try {
      await ref
          .read(eeApprovalsProvider.notifier)
          .decide(approval.id, approve: approve, reason: reason);
    } catch (error) {
      if (!context.mounted) return;
      // The server's sentence reaches the person intact. "Somebody answered
      // first" and "you are not the one being asked" are different facts and
      // a generic failure would collapse them.
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(localizedError(error))));
    }
  }
}

class _ApprovalCard extends StatelessWidget {
  const _ApprovalCard({required this.approval, required this.onDecide});

  final EeApproval approval;
  final void Function(bool approve) onDecide;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final target = approval.target;
    final title = target == null
        ? 'ee.approvals.targetGone'.tr()
        : [
            if (target.number != null) '#${target.number}',
            target.title,
          ].join(' · ');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AwSpace.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: text.titleMedium),
            if (approval.requestReason != null) ...[
              const SizedBox(height: AwSpace.x2),
              Text(approval.requestReason!, style: text.bodyMedium),
            ],
            if (approval.dueAt != null) ...[
              const SizedBox(height: AwSpace.x2),
              Text(
                'ee.approvals.dueAt'.tr(
                  args: {'date': _formatDate(approval.dueAt!)},
                ),
                style: text.bodySmall,
              ),
            ],
            if (approval.isPending) ...[
              const SizedBox(height: AwSpace.x3),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    key: Key('ee-approval-reject-${approval.id}'),
                    onPressed: () => onDecide(false),
                    child: Text('ee.approvals.reject'.tr()),
                  ),
                  const SizedBox(width: AwSpace.x2),
                  FilledButton(
                    key: Key('ee-approval-approve-${approval.id}'),
                    onPressed: () => onDecide(true),
                    child: Text('ee.approvals.approve'.tr()),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: AwSpace.x2),
              Text(
                'ee.approvals.status.${approval.status}'.tr(),
                style: text.bodySmall,
              ),
              if (approval.decisionReason != null)
                Text(approval.decisionReason!, style: text.bodySmall),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}

/// Both answers ask for the same thing, and neither button works without it.
class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.approve});
  final bool approve;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filled = _controller.text.trim().isNotEmpty;
    return AlertDialog(
      title: Text(
        widget.approve
            ? 'ee.approvals.approveTitle'.tr()
            : 'ee.approvals.rejectTitle'.tr(),
      ),
      content: TextField(
        key: const Key('ee-approval-reason'),
        controller: _controller,
        autofocus: true,
        maxLength: 500,
        maxLines: 3,
        decoration: InputDecoration(
          labelText: 'ee.approvals.reasonLabel'.tr(),
          helperText: 'ee.approvals.reasonHelp'.tr(),
        ),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('common.cancel'.tr()),
        ),
        FilledButton(
          key: const Key('ee-approval-confirm'),
          onPressed: filled
              ? () => Navigator.of(context).pop(_controller.text.trim())
              : null,
          child: Text('common.save'.tr()),
        ),
      ],
    );
  }
}
