import 'package:flutter/material.dart';

import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../data/changes_models.dart';
import 'approval_card.dart';

/// One signature asked about something — who, and what they said (EE-269).
///
/// Drawn on a change's detail (the board's signatures) and, since EE-295, on
/// an approval's detail (every signature asked about the same request). The
/// buttons appear only where the server said this person may decide
/// (`canDecide`, the decision door's own rule) AND the host passed
/// [onDecide]: the approval's detail decides from its own bar and draws the
/// cards as the record.
class EeSignatureCard extends StatelessWidget {
  const EeSignatureCard({
    super.key,
    required this.approval,
    this.onDecide,
    this.keyPrefix = 'change-approval',
  });

  final EeChangeApproval approval;
  final void Function(bool approve)? onDecide;

  /// `change-approval-<id>`, `…-approve-<id>`, `…-reject-<id>`.
  final String keyPrefix;

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
        _ => approvalStatusLabel(approval.status),
      };
    }
    final decide = onDecide;
    return Card(
      key: Key('$keyPrefix-${approval.id}'),
      // OPH-353: one rhythm for every card list (DESIGN §4).
      margin: kAwListRowPadding,
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
            ],
            if (approval.canDecide && decide != null) ...[
              const SizedBox(height: AwSpace.x2),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    key: Key('$keyPrefix-reject-${approval.id}'),
                    onPressed: () => decide(false),
                    child: Text('ee.approvals.reject'.tr()),
                  ),
                  const SizedBox(width: AwSpace.x2),
                  FilledButton(
                    key: Key('$keyPrefix-approve-${approval.id}'),
                    onPressed: () => decide(true),
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
