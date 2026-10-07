import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api_exception.dart';
import '../../../core/date_format.dart';
import '../../../core/day_boundary.dart';
import '../../../core/error_messages.dart';
import '../../../core/persisted_prefs.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../../integrations/providers.dart';
import '../approvals_providers.dart';
import '../data/approvals_models.dart';
import '../data/new_ticket_api.dart';
import 'approval_card.dart';
import 'approval_reason_dialog.dart';
import 'approval_signature_card.dart';
import 'change_detail_screen.dart';
import 'change_labels.dart';
import 'form_field_view.dart';
import 'ticket_detail_screen.dart';

/// Opens one approval by its address (EE-295) — what a row of the queue and an
/// approval notification both open.
void awOpenApproval(BuildContext context, String approvalId) {
  if (GoRouter.maybeOf(context) != null) {
    context.push('/approvals/$approvalId');
    return;
  }
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => EeApprovalDetailScreen(approvalId: approvalId),
    ),
  );
}

/// EE-295 — the approver's window onto what they are asked to decide
/// (ADR-0018 D18.2, D18.3; the server's EE-293).
///
/// The owner's words (2026-09-30): the approver sees EVERY detail of the
/// request — the internal notes and their files too — and may correct what
/// the requester wrote before deciding; the correction lands in the
/// request's history under the approver's name. So this page reads top to
/// bottom as a decision is made: where it stands, what is asked, who asked
/// and when, what they wrote and answered, what the desk said and attached,
/// who else was asked — and then, at the bottom, the two answers.
///
/// Somebody the approval does not name reads the summary the queue shows
/// (`access.full` false) and is told so; nothing here is worked out on the
/// device — what this person may read, correct or open is the server's
/// `access`, and the buttons are the decision door's own `canDecide`.
class EeApprovalDetailScreen extends ConsumerStatefulWidget {
  const EeApprovalDetailScreen({super.key, required this.approvalId});

  final String approvalId;

  @override
  ConsumerState<EeApprovalDetailScreen> createState() =>
      _EeApprovalDetailScreenState();
}

class _EeApprovalDetailScreenState
    extends ConsumerState<EeApprovalDetailScreen> {
  bool _editing = false;
  bool _busy = false;
  final _subject = TextEditingController();
  final _body = TextEditingController();
  Map<String, Object?> _answers = {};

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  void _startCorrection(EeApprovalRequestView request) {
    _subject.text = request.subject;
    _body.text = request.body ?? '';
    _answers = {...request.answerValues};
    setState(() => _editing = true);
  }

  Future<void> _saveCorrection(EeApprovalRequestView request) async {
    final messenger = ScaffoldMessenger.of(context);
    final subject = _subject.text.trim();
    if (subject.isEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text('ee.approvals.subjectRequired'.tr())),
      );
      return;
    }
    final missing = missingRequiredFields(request.fields, _answers);
    if (missing.isNotEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'ee.approvals.answerRequired'.tr(
              args: {'label': missing.first.label},
            ),
          ),
        ),
      );
      return;
    }
    // Only what changed travels — the history then says exactly what the
    // approver touched.
    final body = _body.text;
    final answersMoved =
        request.fields.isNotEmpty && !_sameAnswers(request.answerValues);
    setState(() => _busy = true);
    try {
      await ref
          .read(eeApprovalActionsProvider)
          .correct(
            widget.approvalId,
            subject: subject == request.subject ? null : subject,
            body: body == (request.body ?? '') ? null : body,
            answers: answersMoved ? _answers : null,
          );
      if (!mounted) return;
      setState(() => _editing = false);
      messenger.showSnackBar(
        SnackBar(content: Text('ee.approvals.corrected'.tr())),
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(localizedError(error))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _sameAnswers(Map<String, String> before) {
    final now = {
      for (final entry in _answers.entries)
        if (entry.value != null && '${entry.value}'.trim().isNotEmpty)
          entry.key: '${entry.value}'.trim(),
    };
    if (now.length != before.length) return false;
    return now.entries.every((e) => before[e.key] == e.value);
  }

  Future<void> _decide(EeApproval approval, {required bool approve}) async {
    final reason = await askApprovalReason(context, approve: approve);
    if (reason == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(eeApprovalActionsProvider)
          .decide(approval.id, approve: approve, reason: reason);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            approve
                ? 'ee.approvals.approvedToast'.tr()
                : 'ee.approvals.rejectedToast'.tr(),
          ),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(localizedError(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(eeApprovalDetailProvider(widget.approvalId));
    final value = detail.value;
    final request = value?.request;
    final canPop =
        GoRouter.maybeOf(context)?.canPop() ?? Navigator.canPop(context);

    return Scaffold(
      appBar: AppBar(
        leading: canPop
            ? null
            : IconButton(
                key: const Key('ee-approval-detail-home'),
                icon: const Icon(Icons.home_outlined),
                tooltip: 'nav.home'.tr(),
                onPressed: () => context.go('/home'),
              ),
        title: Text('ee.approvals.detailTitle'.tr()),
        actions: [
          if (value != null &&
              value.access.edit &&
              request != null &&
              !_editing)
            IconButton(
              key: const Key('ee-approval-correct'),
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'ee.approvals.correct'.tr(),
              onPressed: () => _startCorrection(request),
            ),
        ],
      ),
      body: detail.when(
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) {
          if (error is ApiException && error.code == 'HTTP_404') {
            return AwEmptyState(
              icon: Icons.how_to_reg_outlined,
              title: 'ee.approvals.goneTitle'.tr(),
              message: 'ee.approvals.goneBody'.tr(),
              action: FilledButton(
                key: const Key('ee-approval-gone-back'),
                onPressed: () => context.go('/approvals'),
                child: Text('ee.approvals.backToList'.tr()),
              ),
            );
          }
          return AwErrorState(
            message: localizedError(error),
            onRetry: () =>
                ref.invalidate(eeApprovalDetailProvider(widget.approvalId)),
          );
        },
        data: (d) => RefreshIndicator(
          onRefresh: () async =>
              ref.invalidate(eeApprovalDetailProvider(widget.approvalId)),
          child: ListView(
            key: const Key('ee-approval-detail'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: awListPadding(context),
            children: _editing && d.request != null
                ? _correction(context, d.request!)
                : _reading(context, d),
          ),
        ),
      ),
      bottomNavigationBar:
          value != null && value.approval.actionable && !_editing
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AwSpace.x4,
                  AwSpace.x2,
                  AwSpace.x4,
                  AwSpace.x3,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        key: const Key('ee-approval-detail-reject'),
                        onPressed: () =>
                            _decide(value.approval, approve: false),
                        child: Text('ee.approvals.reject'.tr()),
                      ),
                    ),
                    const SizedBox(width: AwSpace.x3),
                    Expanded(
                      child: FilledButton(
                        key: const Key('ee-approval-detail-approve'),
                        onPressed: () => _decide(value.approval, approve: true),
                        child: Text('ee.approvals.approve'.tr()),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  // ── Reading ───────────────────────────────────────────────────────────────

  List<Widget> _reading(BuildContext context, EeApprovalDetail d) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final muted = theme.colorScheme.onSurfaceVariant;
    final format = ref.watch(dateFormatProvider);
    final now = ref.watch(nowProvider)();
    final approval = d.approval;
    final request = d.request;

    String when(DateTime at) =>
        '${awFormatDateTime(at, format: format)} · ${awRelativePast(at, now)}';

    return [
      _StatusBanner(approval: approval, full: d.access.full),
      const SizedBox(height: AwSpace.x3),
      // What is asked.
      Text(
        'ee.approvals.kind.${approval.targetType}'.tr(),
        style: text.labelMedium?.copyWith(color: muted),
      ),
      const SizedBox(height: AwSpace.x1),
      Text(
        approvalTitle(approval),
        key: const Key('ee-approval-detail-title'),
        style: text.titleLarge,
      ),
      if (request != null) ...[
        const SizedBox(height: AwSpace.x2),
        Wrap(
          spacing: AwSpace.x2,
          runSpacing: AwSpace.x2,
          children: [
            _Pill('ee.tickets.status.${request.status}'.tr()),
            if (request.priority case final p?)
              _Pill('ee.tickets.priority.$p'.tr()),
            if (request.serviceName case final s?) _Pill(s),
            if (request.unitName case final u?) _Pill(u),
          ],
        ),
        _Heading('ee.approvals.section.requester'.tr()),
        _Fact(
          icon: Icons.person_outline,
          text: [
            request.requester.name ?? 'ee.tickets.askedBy.teamMember'.tr(),
            if (request.requester.kind case final kind? when kind != 'member')
              'ee.approvals.via.$kind'.tr(),
          ].join(' · '),
          textKey: const Key('ee-approval-detail-requester'),
        ),
        if (request.requester.email case final email?)
          _Fact(icon: Icons.alternate_email, text: email, selectable: true),
        if (request.createdAt case final opened?)
          _Fact(
            icon: Icons.event_outlined,
            text: 'ee.approvals.openedAt'.tr(args: {'when': when(opened)}),
            textKey: const Key('ee-approval-detail-opened'),
          ),
        _Heading('ee.approvals.section.description'.tr()),
        if ((request.body ?? '').trim().isEmpty)
          Text('ee.approvals.noDescription'.tr(), style: text.bodyMedium)
        else
          SelectableText(
            request.body!,
            key: const Key('ee-approval-detail-body'),
            style: text.bodyMedium,
          ),
        if (request.answers.isNotEmpty) ...[
          _Heading('ee.approvals.section.answers'.tr()),
          EeTicketAnswersView(
            answers: request.answers,
            dateFormat: format,
            titled: false,
          ),
        ],
        if (request.files.isNotEmpty) ...[
          _Heading('ee.approvals.section.files'.tr()),
          for (final file in request.files)
            ListTile(
              key: Key('ee-approval-file-${file.id}'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.attach_file),
              title: Text(
                file.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                [
                  _size(file.sizeBytes),
                  if (file.internal) 'ee.approvals.internal'.tr(),
                ].join(' · '),
              ),
              trailing: const Icon(Icons.download_outlined),
              onTap: () => _download(d.approval.id, file),
            ),
        ],
        if (request.comments.isNotEmpty) ...[
          _Heading('ee.approvals.section.conversation'.tr()),
          for (final comment in request.comments)
            _CommentTile(comment: comment, when: when),
        ],
      ],
      if (d.change case final change?) ...[
        const SizedBox(height: AwSpace.x2),
        Wrap(
          spacing: AwSpace.x2,
          runSpacing: AwSpace.x2,
          children: [
            if (change.type case final t?) _Pill('ee.changes.type.$t'.tr()),
            if (change.risk case final r?) _Pill('ee.changes.risk.$r'.tr()),
          ],
        ),
        if ((change.windowStart, change.windowEnd) case (final s?, final e?))
          _Fact(
            icon: Icons.schedule,
            text: changeWindowText(s, e, format: format),
          ),
        // UI-AUDIT #77: a signature for a night that has passed.
        if (changeWindowPassed(change.windowEnd, change.status, now)) ...[
          const EeWindowPassedBadge(),
          const SizedBox(height: AwSpace.x2),
        ],
        if (change.createdByName case final by?)
          _Fact(icon: Icons.person_outline, text: by),
        if (change.impact case final impact?) ...[
          _Heading('ee.approvals.section.impact'.tr()),
          Text(impact, style: text.bodyMedium),
        ],
      ],
      if (d.task case final task?) ...[
        if (task.projectName case final project?)
          _Fact(icon: Icons.folder_outlined, text: project),
        if (task.dueAt case final due?)
          _Fact(
            icon: Icons.event_outlined,
            text: 'ee.approvals.taskDue'.tr(
              args: {'date': awFormatDateTime(due, format: format)},
            ),
          ),
        if (task.createdByName case final by?)
          _Fact(icon: Icons.person_outline, text: by),
        if (task.description case final description?) ...[
          _Heading('ee.approvals.section.description'.tr()),
          Text(description, style: text.bodyMedium),
        ],
      ],
      if (!d.access.full && approval.context == null) ...[
        const SizedBox(height: AwSpace.x3),
        Text(
          'ee.approvals.summaryOnly'.tr(),
          key: const Key('ee-approval-detail-summary-only'),
          style: text.bodySmall?.copyWith(color: muted),
        ),
      ],
      if (d.access.openTarget) ...[
        const SizedBox(height: AwSpace.x3),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const Key('ee-approval-open-target'),
            icon: const Icon(Icons.open_in_new),
            label: Text('ee.approvals.openTarget.${approval.targetType}'.tr()),
            onPressed: () => _openTarget(approval),
          ),
        ),
      ],
      _Heading('ee.approvals.section.signatures'.tr()),
      for (final signature in d.signatures)
        EeSignatureCard(approval: signature, keyPrefix: 'ee-signature'),
      _Heading('ee.approvals.section.ask'.tr()),
      _Fact(
        icon: Icons.how_to_reg_outlined,
        text: [
          'ee.approvals.askedAgo'.tr(
            args: {'when': awRelativePast(approval.createdAt, now)},
          ),
          if (approval.requestedByName case final by?)
            'ee.approvals.askedBy'.tr(args: {'name': by}),
        ].join(' · '),
      ),
      // A service rule asks with the service's name as its reason — already
      // on the pills above, so only a reason somebody wrote is said here.
      if (approval.requestReason case final reason?
          when reason.isNotEmpty &&
              reason != (request?.serviceName ?? approval.context?.serviceName))
        _Fact(icon: Icons.notes, text: '“$reason”'),
      if (approval.dueAt case final due?)
        _Fact(
          icon: Icons.timer_outlined,
          text: 'ee.approvals.dueShort'.tr(
            args: {'date': awFormatDateTime(due, format: format)},
          ),
        ),
      const SizedBox(height: AwSpace.x6),
    ];
  }

  /// Opens what is being decided — and reads this page again on the way back
  /// (UI-AUDIT #74): a note written on the request there belongs on the page
  /// the decision is made from.
  Future<void> _openTarget(EeApproval approval) async {
    switch (approval.targetType) {
      case 'ee_ticket':
        await awOpenTicket(context, approval.targetId);
      case 'ee_change':
        await awOpenChange(context, approval.targetId);
      case 'task':
        await context.push<void>('/tasks/${approval.targetId}');
    }
    if (!mounted) return;
    ref.invalidate(eeApprovalDetailProvider(widget.approvalId));
  }

  Future<void> _download(String approvalId, EeApprovalFile file) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final url = await ref
          .read(eeApprovalsApiProvider)
          .fileDownload(approvalId, file.id);
      if (url == null) {
        messenger.showSnackBar(
          SnackBar(content: Text('ee.approvals.fileUnavailable'.tr())),
        );
        return;
      }
      await ref.read(urlLauncherProvider)(url);
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(localizedError(error))));
    }
  }

  // ── Correcting ────────────────────────────────────────────────────────────

  List<Widget> _correction(BuildContext context, EeApprovalRequestView r) {
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final subjectLabel = 'ee.approvals.correctSubject'.tr();
    final bodyLabel = 'ee.approvals.correctBody'.tr();
    return [
      Text(
        'ee.approvals.correctHint'.tr(),
        style: text.bodySmall?.copyWith(color: muted),
      ),
      const SizedBox(height: AwSpace.x3),
      TextField(
        key: const Key('ee-approval-correct-subject'),
        controller: _subject,
        enabled: !_busy,
        maxLength: 200,
        decoration: InputDecoration(labelText: subjectLabel),
      ),
      const SizedBox(height: AwSpace.x2),
      TextField(
        key: const Key('ee-approval-correct-body'),
        controller: _body,
        enabled: !_busy,
        minLines: 3,
        maxLines: 10,
        keyboardType: TextInputType.multiline,
        decoration: InputDecoration(labelText: bodyLabel),
      ),
      for (final field in visibleFormFields(r.fields, _answers))
        Padding(
          padding: const EdgeInsets.only(top: AwSpace.x3),
          child: EeFormFieldView(
            key: ValueKey('${r.serviceId}/${field.key}'),
            field: field,
            value: _answers[field.key],
            keyPrefix: 'ee-approval-correct-field',
            enabled: !_busy,
            onChanged: (value) => setState(() {
              if (value == null) {
                _answers.remove(field.key);
              } else {
                _answers[field.key] = value;
              }
            }),
          ),
        ),
      const SizedBox(height: AwSpace.x4),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            key: const Key('ee-approval-correct-cancel'),
            onPressed: _busy ? null : () => setState(() => _editing = false),
            child: Text('common.cancel'.tr()),
          ),
          const SizedBox(width: AwSpace.x2),
          FilledButton(
            key: const Key('ee-approval-correct-save'),
            onPressed: _busy ? null : () => _saveCorrection(r),
            child: Text('common.save'.tr()),
          ),
        ],
      ),
    ];
  }
}

String _size(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// Where the approval stands, in one line at the top.
class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.approval, required this.full});

  final EeApproval approval;
  final bool full;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final String line;
    if (!approval.live) {
      line = approval.target == null
          ? 'ee.approvals.notLiveGone'.tr()
          : 'ee.approvals.notLiveCancelled'.tr();
    } else if (approval.isPending && approval.canDecide) {
      line = 'ee.approvals.bannerYours'.tr();
    } else if (approval.isPending) {
      line = 'ee.approvals.waitingOn'.tr(
        args: {'who': approvalWaitingOn(approval)},
      );
    } else {
      line = [
        approvalStatusLabel(approval.status),
        ?approval.decidedByName,
        if (approval.decisionReason case final reason?) '“$reason”',
      ].join(' · ');
    }
    return Container(
      key: const Key('ee-approval-detail-status'),
      padding: const EdgeInsets.all(AwSpace.x3),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(AwRadius.m),
      ),
      child: Text(
        line,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: scheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AwSpace.x5, bottom: AwSpace.x2),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}

class _Pill extends StatelessWidget {
  const _Pill(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AwSpace.x2,
        vertical: AwSpace.x1,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AwRadius.s),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({
    required this.icon,
    required this.text,
    this.textKey,
    this.selectable = false,
  });

  final IconData icon;
  final String text;
  final Key? textKey;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.only(bottom: AwSpace.x2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: AwSpace.x2),
          Expanded(
            child: selectable
                ? SelectableText(text, key: textKey, style: style)
                : Text(text, key: textKey, style: style),
          ),
        ],
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment, required this.when});

  final EeApprovalComment comment;
  final String Function(DateTime) when;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final header = [
      comment.authorName ?? 'ee.approvals.requesterSide'.tr(),
      if (comment.createdAt case final at?) when(at),
    ].join(' · ');
    return Container(
      key: Key('ee-approval-comment-${comment.id}'),
      margin: const EdgeInsets.only(bottom: AwSpace.x2),
      padding: const EdgeInsets.all(AwSpace.x3),
      decoration: BoxDecoration(
        color: comment.internal
            ? scheme.tertiaryContainer
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AwRadius.m),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  header,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: comment.internal
                        ? scheme.onTertiaryContainer
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (comment.internal)
                Text(
                  'ee.approvals.internal'.tr(),
                  key: Key('ee-approval-comment-internal-${comment.id}'),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onTertiaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AwSpace.x1),
          Text(
            comment.body,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: comment.internal
                  ? scheme.onTertiaryContainer
                  : scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
