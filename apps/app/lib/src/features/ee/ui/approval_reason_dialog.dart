import 'package:flutter/material.dart';

import '../../../i18n/i18n.dart';

/// Asks for the sentence a decision needs (EE-184), and returns it — or null
/// when the person backs out.
///
/// One dialog for every place a signature is given: the approver's queue and,
/// since EE-269, a change's own detail. Two copies would drift, and the one
/// thing both must keep is that NEITHER button works without a reason — the
/// server refuses either way, and saying so while the person's hands are
/// still on the form is cheaper than after they press.
Future<String?> askApprovalReason(
  BuildContext context, {
  required bool approve,
}) => showDialog<String>(
  context: context,
  builder: (context) => EeApprovalReasonDialog(approve: approve),
);

class EeApprovalReasonDialog extends StatefulWidget {
  const EeApprovalReasonDialog({super.key, required this.approve});
  final bool approve;

  @override
  State<EeApprovalReasonDialog> createState() => _EeApprovalReasonDialogState();
}

class _EeApprovalReasonDialogState extends State<EeApprovalReasonDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filled = _controller.text.trim().isNotEmpty;
    final title = widget.approve
        ? 'ee.approvals.approveTitle'.tr()
        : 'ee.approvals.rejectTitle'.tr();
    return AlertDialog(
      // OPH-359 (UI-AUDIT #64): named for what it asks, not the platform's
      // generic "Alert".
      semanticLabel: title,
      title: Text(title),
      content: TextField(
        key: const Key('ee-approval-reason'),
        controller: _controller,
        autofocus: true,
        maxLength: 500,
        maxLines: 3,
        decoration: InputDecoration(
          labelText: 'ee.approvals.reasonLabel'.tr(),
          helperText: 'ee.approvals.reasonHelp'.tr(),
          // OPH-360 (UI-AUDIT #65): the sentence is the point; it wraps
          // rather than being cut at one line.
          helperMaxLines: 3,
        ),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('common.cancel'.tr()),
        ),
        // OPH-360 (UI-AUDIT #65): the button says the decision — "Approve"
        // or "Reject" — not "Save"; a rejection takes the error role.
        FilledButton(
          key: const Key('ee-approval-confirm'),
          style: widget.approve
              ? null
              : FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
          onPressed: filled
              ? () => Navigator.of(context).pop(_controller.text.trim())
              : null,
          child: Text(
            widget.approve
                ? 'ee.approvals.approve'.tr()
                : 'ee.approvals.reject'.tr(),
          ),
        ),
      ],
    );
  }
}
