import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/error_messages.dart';
import '../../../core/reachability.dart';
import '../../../i18n/i18n.dart';
import '../../../sync/db/database.dart';
import '../../../sync/providers.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../data/ticket_write_api.dart';
import '../ticket_links_providers.dart';
import '../ticket_write_providers.dart';

/// EE-224 — moving a request, and saying how urgent it is, from its own screen.
///
/// ── NOTHING HERE KNOWS THE LIFECYCLE ─────────────────────────────────────
///
/// The status sheet lists the moves the SERVER listed for this person on this
/// request: the lifecycle map, minus the endings for whoever may not end a
/// matter, minus what a pending approval stops. The app adds no move and
/// removes none, so a transition the doors would refuse is one this screen
/// never offered. The one thing it decides is which of the offered moves get
/// a second tap — the two endings, because neither can be walked back. That
/// is presentation, not permission.
///
/// ── ONLINE, AND HONEST ABOUT IT (E19) ────────────────────────────────────
///
/// The composer's stance (EE-223): a request is server-canonical, so with no
/// connection the chips grey out BEFORE they are pressed and the line under
/// them says why ([EeTicketActionsOffline], from `serverReachabilityProvider`).
class EeTicketStatusAction extends ConsumerWidget {
  const EeTicketStatusAction({super.key, required this.ticket});

  final TicketRecord ticket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(serverReachabilityProvider) == false;
    return ActionChip(
      key: const Key('ticket-status'),
      avatar: const Icon(Icons.swap_horiz, size: 18),
      label: Text('ee.tickets.status.${ticket.status}'.tr()),
      tooltip: 'ee.tickets.actions.statusTitle'.tr(),
      onPressed: offline
          ? null
          : () => _openSheet(
              context,
              ref,
              ticket.id,
              _StatusSheet(ticketId: ticket.id),
            ),
    );
  }
}

/// The priority chip, opening the matrix or the direct choice (EE-183).
class EeTicketPriorityAction extends ConsumerWidget {
  const EeTicketPriorityAction({super.key, required this.ticket});

  final TicketRecord ticket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(serverReachabilityProvider) == false;
    return ActionChip(
      key: const Key('ticket-priority'),
      avatar: const Icon(Icons.flag_outlined, size: 18),
      label: Text('ee.tickets.priority.${ticket.priority}'.tr()),
      tooltip: 'ee.tickets.actions.priorityTitle'.tr(),
      onPressed: offline
          ? null
          : () => _openSheet(
              context,
              ref,
              ticket.id,
              _PrioritySheet(ticketId: ticket.id),
            ),
    );
  }
}

/// Why the two chips above are grey — one line, only while it is true.
class EeTicketActionsOffline extends ConsumerWidget {
  const EeTicketActionsOffline({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(serverReachabilityProvider) != false) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      key: const Key('ticket-actions-offline'),
      padding: const EdgeInsets.only(top: AwSpace.x2),
      child: Row(
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 16,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: AwSpace.x1),
          Expanded(
            child: Text(
              'ee.tickets.actions.offline'.tr(),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens [sheet]; a sheet that wrote pops with the sentence to confirm it.
///
/// The screen then asks for the moved row now rather than at the next
/// scheduled pull (the composer's precedent), and forgets the server's last
/// answer about what may happen next — it described a request that has since
/// moved.
Future<void> _openSheet(
  BuildContext context,
  WidgetRef ref,
  String ticketId,
  Widget sheet,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final done = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => sheet,
  );
  if (done == null || !context.mounted) return;
  ref.invalidate(eeTicketActionsProvider(ticketId));
  // The parking reason on the screen is drawn from the relations read.
  ref.invalidate(eeTicketRelationsProvider(ticketId));
  unawaited(ref.read(syncEngineProvider)?.syncNow());
  messenger?.showSnackBar(SnackBar(content: Text(done)));
}

/// The part both sheets share: one write at a time, and a refusal kept on
/// screen in the server's words rather than in a toast that is gone before
/// anybody reads it.
mixin _SheetWrite<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  bool busy = false;
  String? error;

  Future<void> write(
    Future<Object?> Function(EeTicketWriteApi api) call,
    String Function(Object? answer) done,
  ) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final answer = await call(ref.read(eeTicketWriteApiProvider));
      if (mounted) Navigator.of(context).pop(done(answer));
    } on ApiException catch (failure) {
      if (failure.code == 'NETWORK_ERROR') {
        ref.read(serverReachabilityProvider.notifier).unreachable();
      }
      if (mounted) {
        setState(() {
          busy = false;
          error = localizedError(failure);
        });
      }
    }
  }
}

/// The sheet's frame: the server's answer, or why there is none.
Widget _answered(
  BuildContext context,
  WidgetRef ref,
  AsyncValue<EeTicketActions?> actions,
  Widget Function(EeTicketActions data) body,
) {
  final data = actions.value;
  final Widget child;
  if (data != null) {
    child = body(data);
  } else if (actions.isLoading) {
    child = const Padding(
      padding: EdgeInsets.all(AwSpace.x6),
      child: Center(child: CircularProgressIndicator()),
    );
  } else if (actions.hasError) {
    child = AwInlineError(message: localizedError(actions.error));
  } else {
    child = Padding(
      padding: const EdgeInsets.symmetric(vertical: AwSpace.x4),
      child: Text(
        (ref.watch(serverReachabilityProvider) == false
                ? 'ee.tickets.actions.offline'
                : 'ee.tickets.actions.unavailable')
            .tr(),
        key: const Key('ticket-actions-unavailable'),
      ),
    );
  }
  return SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AwSpace.x4,
          0,
          AwSpace.x4,
          AwSpace.x4,
        ),
        child: child,
      ),
    ),
  );
}

TextStyle? _quiet(BuildContext context) {
  final theme = Theme.of(context);
  return theme.textTheme.bodySmall?.copyWith(
    color: theme.colorScheme.onSurfaceVariant,
  );
}

// ── Status ────────────────────────────────────────────────────────────────

class _StatusSheet extends ConsumerStatefulWidget {
  const _StatusSheet({required this.ticketId});

  final String ticketId;

  @override
  ConsumerState<_StatusSheet> createState() => _StatusSheetState();
}

class _StatusSheetState extends ConsumerState<_StatusSheet>
    with _SheetWrite<_StatusSheet> {
  /// The moves that get a second tap: they end the matter, and the server
  /// has no way back from either (a problem that returns becomes a NEW
  /// request, ADR-0011 §2).
  static const _endings = {'closed', 'cancelled'};

  /// The move waiting for its second step — `waiting` owes a reason
  /// (EE-190), an ending owes a yes. Null while the list is shown.
  String? _target;

  /// The reason being picked is for a clock pause, not a park.
  bool _pausing = false;
  String? _reason;

  void _back() => setState(() {
    _target = null;
    _pausing = false;
    _reason = null;
    error = null;
  });

  void _pick(String to) {
    if (to == 'waiting' || _endings.contains(to)) {
      setState(() {
        _target = to;
        _reason = null;
        error = null;
      });
      return;
    }
    _move(to);
  }

  void _move(String to, {String? reason}) => write(
    (api) => api.setStatus(widget.ticketId, to, waitingReason: reason),
    (_) => 'ee.tickets.actions.statusChanged'.tr(
      args: {'status': 'ee.tickets.status.$to'.tr()},
    ),
  );

  @override
  Widget build(BuildContext context) => _answered(
    context,
    ref,
    ref.watch(eeTicketActionsProvider(widget.ticketId)),
    (data) {
      // A second step outlives its offer only as long as the server keeps
      // making it: a pull that moved the request while the sheet was open
      // may have taken the move (or the clock) away, and then the list is
      // what is true.
      final target = data.allowedTransitions.contains(_target) ? _target : null;
      final pausing = _pausing && data.canPauseSla && data.slaPausable;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pausing || target == 'waiting')
            ..._reasonStep(context, data, pausing: pausing)
          else if (target != null)
            ..._confirmStep(context, target)
          else
            ..._list(context, data),
          if (error != null) ...[
            const SizedBox(height: AwSpace.x3),
            AwInlineError(
              message: error!,
              textKey: const Key('ticket-action-error'),
            ),
          ],
        ],
      );
    },
  );

  List<Widget> _list(BuildContext context, EeTicketActions data) {
    final theme = Theme.of(context);
    final hold = data.canPauseSla && (data.slaHeld || data.slaPausable);
    return [
      Text(
        'ee.tickets.actions.statusTitle'.tr(),
        style: theme.textTheme.titleMedium,
      ),
      const SizedBox(height: AwSpace.x1),
      Text(
        [
          'ee.tickets.actions.now'.tr(
            args: {'status': 'ee.tickets.status.${data.status}'.tr()},
          ),
          if (data.waitingReason != null)
            'ee.sla.reason.${data.waitingReason}'.tr(),
        ].join(' · '),
        style: _quiet(context),
      ),
      if (data.approvalPending) ...[
        const SizedBox(height: AwSpace.x3),
        Row(
          key: const Key('ticket-approval-pending'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.hourglass_top_outlined,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: AwSpace.x2),
            Expanded(
              child: Text(
                'ee.tickets.actions.approvalPending'.tr(),
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ],
      const SizedBox(height: AwSpace.x2),
      if (data.allowedTransitions.isEmpty)
        Padding(
          key: const Key('ticket-status-none'),
          padding: const EdgeInsets.symmetric(vertical: AwSpace.x2),
          child: Text('ee.tickets.actions.noMoves'.tr()),
        ),
      for (final to in data.allowedTransitions)
        ListTile(
          key: Key('ticket-status-$to'),
          contentPadding: EdgeInsets.zero,
          enabled: !busy,
          leading: Icon(switch (to) {
            'closed' => Icons.task_alt,
            'cancelled' => Icons.block,
            _ => Icons.arrow_forward,
          }),
          title: Text('ee.tickets.status.$to'.tr()),
          // A second step waits behind these two kinds of move; the chevron
          // says so before the tap.
          trailing: to == 'waiting' || _endings.contains(to)
              ? const Icon(Icons.chevron_right)
              : null,
          onTap: () => _pick(to),
        ),
      // EE-190: the clock, "from the same place" — without moving the request.
      if (hold) ...[
        const Divider(height: AwSpace.x6),
        Text(
          'ee.tickets.actions.slaTitle'.tr(),
          style: theme.textTheme.titleSmall,
        ),
        for (final reason in data.slaHoldReasons)
          Padding(
            padding: const EdgeInsets.only(top: AwSpace.x1),
            child: Text(
              'ee.tickets.actions.slaHeld'.tr(
                args: {'reason': 'ee.sla.reason.$reason'.tr()},
              ),
              style: _quiet(context),
            ),
          ),
        const SizedBox(height: AwSpace.x2),
        Wrap(
          spacing: AwSpace.x2,
          runSpacing: AwSpace.x2,
          children: [
            if (data.slaHeld)
              OutlinedButton.icon(
                key: const Key('ticket-sla-resume'),
                onPressed: busy
                    ? null
                    : () => write(
                        (api) => api.resumeSla(widget.ticketId),
                        (_) => 'ee.tickets.actions.slaResumed'.tr(),
                      ),
                icon: const Icon(Icons.play_arrow_outlined),
                label: Text('ee.sla.resume'.tr()),
              ),
            if (data.slaPausable)
              OutlinedButton.icon(
                key: const Key('ticket-sla-pause'),
                onPressed: busy
                    ? null
                    : () => setState(() {
                        _pausing = true;
                        _reason = null;
                        error = null;
                      }),
                icon: const Icon(Icons.pause_outlined),
                label: Text('ee.sla.pause'.tr()),
              ),
          ],
        ),
      ],
    ];
  }

  List<Widget> _reasonStep(
    BuildContext context,
    EeTicketActions data, {
    required bool pausing,
  }) {
    final reason = _reason;
    return [
      Text(
        (pausing ? 'ee.sla.pauseReason' : 'ee.tickets.waitingReason').tr(),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: AwSpace.x1),
      Text(
        (pausing
                ? 'ee.tickets.actions.pauseHint'
                : 'ee.tickets.waitingReasonRequired')
            .tr(),
        style: _quiet(context),
      ),
      const SizedBox(height: AwSpace.x2),
      RadioGroup<String>(
        groupValue: reason,
        onChanged: (value) {
          if (!busy) setState(() => _reason = value);
        },
        child: Column(
          children: [
            // The server's list, in its order (EE-190) — never a copy.
            for (final option in data.waitingReasons)
              RadioListTile<String>(
                key: Key('ticket-reason-$option'),
                contentPadding: EdgeInsets.zero,
                value: option,
                title: Text('ee.sla.reason.$option'.tr()),
              ),
          ],
        ),
      ),
      const SizedBox(height: AwSpace.x2),
      _StepButtons(
        busy: busy,
        onBack: _back,
        confirmKey: const Key('ticket-reason-apply'),
        confirmIcon: pausing ? Icons.pause_outlined : Icons.schedule,
        confirmLabel: (pausing ? 'ee.sla.pause' : 'ee.tickets.actions.park')
            .tr(),
        onConfirm: reason == null
            ? null
            : pausing
            ? () => write(
                (api) => api.pauseSla(widget.ticketId, reason),
                (_) => 'ee.tickets.actions.slaPaused'.tr(),
              )
            : () => _move('waiting', reason: reason),
      ),
    ];
  }

  List<Widget> _confirmStep(BuildContext context, String to) {
    final closing = to == 'closed';
    return [
      Text(
        'ee.tickets.status.$to'.tr(),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: AwSpace.x2),
      Text(
        (closing
                ? 'ee.tickets.actions.confirmClose'
                : 'ee.tickets.actions.confirmCancel')
            .tr(),
        key: const Key('ticket-status-confirm-text'),
      ),
      const SizedBox(height: AwSpace.x4),
      _StepButtons(
        busy: busy,
        onBack: _back,
        confirmKey: const Key('ticket-status-confirm'),
        confirmIcon: closing ? Icons.task_alt : Icons.block,
        confirmLabel:
            (closing ? 'ee.tickets.actions.close' : 'ee.tickets.actions.cancel')
                .tr(),
        onConfirm: () => _move(to),
      ),
    ];
  }
}

class _StepButtons extends StatelessWidget {
  const _StepButtons({
    required this.busy,
    required this.onBack,
    required this.confirmKey,
    required this.confirmIcon,
    required this.confirmLabel,
    required this.onConfirm,
  });

  final bool busy;
  final VoidCallback onBack;
  final Key confirmKey;
  final IconData confirmIcon;
  final String confirmLabel;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: AwSpace.x2,
    runSpacing: AwSpace.x2,
    children: [
      TextButton(
        key: const Key('ticket-action-back'),
        onPressed: busy ? null : onBack,
        child: Text('ee.tickets.actions.back'.tr()),
      ),
      FilledButton.icon(
        key: confirmKey,
        onPressed: busy ? null : onConfirm,
        icon: busy
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(confirmIcon),
        label: Text(confirmLabel),
      ),
    ],
  );
}

// ── Priority ──────────────────────────────────────────────────────────────

/// "If the desk runs the matrix, impact × urgency; otherwise the priority
/// itself" — the task's sentence, read against EE-183's model: a desk runs
/// the matrix when it customised it, and a request is IN the matrix when it
/// carries both inputs (from a form, say) whatever the desk did.
///
/// On a matrix request a hand-picked tier is an override, which is a verb of
/// its own: without it the choice is not offered, and the sheet says why.
/// The preview line is a lookup in the table the server handed out — the
/// server derives again on save, and its answer is the one that lands.
class _PrioritySheet extends ConsumerStatefulWidget {
  const _PrioritySheet({required this.ticketId});

  final String ticketId;

  @override
  ConsumerState<_PrioritySheet> createState() => _PrioritySheetState();
}

class _PrioritySheetState extends ConsumerState<_PrioritySheet>
    with _SheetWrite<_PrioritySheet> {
  /// What the person picked; null means "as the request has it".
  String? _impact;
  String? _urgency;

  String _priorityDone(Object? answer) => 'ee.tickets.actions.priorityChanged'
      .tr(args: {'priority': 'ee.tickets.priority.$answer'.tr()});

  @override
  Widget build(BuildContext context) {
    final matrix = ref.watch(eePriorityMatrixProvider);
    return _answered(
      context,
      ref,
      ref.watch(eeTicketActionsProvider(widget.ticketId)),
      (data) {
        if (matrix.isLoading && !matrix.hasValue) {
          return const Padding(
            padding: EdgeInsets.all(AwSpace.x6),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return _body(context, data, matrix);
      },
    );
  }

  Widget _body(
    BuildContext context,
    EeTicketActions data,
    AsyncValue<EePriorityMatrix?> matrixAsync,
  ) {
    final theme = Theme.of(context);
    final matrix = matrixAsync.value;
    final matrixOpen = matrix != null && (matrix.customised || data.usesMatrix);
    // A tier named by hand on a matrix request is an override; on any other
    // request it is simply the priority.
    final direct =
        data.canOverridePriority ||
        (!data.usesMatrix && !(matrix?.customised ?? false));
    final impact = _impact ?? data.impact;
    final urgency = _urgency ?? data.urgency;
    final derived = matrix?.derive(impact, urgency);
    final derivedNow = matrix?.derive(data.impact, data.urgency);
    final changed = impact != data.impact || urgency != data.urgency;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'ee.tickets.actions.priorityTitle'.tr(),
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: AwSpace.x1),
        Text(
          [
            'ee.tickets.actions.now'.tr(
              args: {'status': 'ee.tickets.priority.${data.priority}'.tr()},
            ),
            if (data.usesMatrix)
              'ee.tickets.actions.inputs'.tr(
                args: {
                  'impact': 'ee.tickets.impact.${data.impact}'.tr(),
                  'urgency': 'ee.tickets.urgency.${data.urgency}'.tr(),
                },
              ),
          ].join(' · '),
          style: _quiet(context),
        ),
        if (matrixAsync.hasError) ...[
          const SizedBox(height: AwSpace.x3),
          AwInlineError(message: localizedError(matrixAsync.error)),
        ],
        if (matrixOpen) ...[
          const SizedBox(height: AwSpace.x4),
          Text(
            'ee.tickets.actions.matrixTitle'.tr(),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: AwSpace.x2),
          Text(
            'ee.tickets.actions.impact'.tr(),
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: AwSpace.x1),
          _Segments(
            key: const Key('ticket-impact'),
            values: matrix.impacts,
            selected: impact,
            label: (v) => 'ee.tickets.impact.$v'.tr(),
            onChanged: busy ? null : (v) => setState(() => _impact = v),
          ),
          const SizedBox(height: AwSpace.x3),
          Text(
            'ee.tickets.actions.urgency'.tr(),
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: AwSpace.x1),
          _Segments(
            key: const Key('ticket-urgency'),
            values: matrix.urgencies,
            selected: urgency,
            label: (v) => 'ee.tickets.urgency.$v'.tr(),
            onChanged: busy ? null : (v) => setState(() => _urgency = v),
          ),
          if (derived != null) ...[
            const SizedBox(height: AwSpace.x3),
            Text(
              'ee.tickets.actions.matrixGives'.tr(
                args: {'priority': 'ee.tickets.priority.$derived'.tr()},
              ),
              key: const Key('ticket-matrix-preview'),
              style: theme.textTheme.bodyMedium,
            ),
          ],
          if (data.priorityOverridden) ...[
            const SizedBox(height: AwSpace.x2),
            Text(
              'ee.tickets.actions.overridden'.tr(),
              key: const Key('ticket-priority-overridden'),
              style: _quiet(context),
            ),
            // Agreeing with the matrix is not an override and needs no verb
            // (EE-183): it hands the request back, and the next impact
            // correction re-derives again.
            if (derivedNow != null && derivedNow != data.priority)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: const Key('ticket-priority-rematrix'),
                  onPressed: busy
                      ? null
                      : () => write(
                          (api) => api.setPriority(widget.ticketId, derivedNow),
                          _priorityDone,
                        ),
                  icon: const Icon(Icons.undo),
                  label: Text(
                    'ee.tickets.actions.rematrix'.tr(
                      args: {
                        'priority': 'ee.tickets.priority.$derivedNow'.tr(),
                      },
                    ),
                  ),
                ),
              ),
          ],
          const SizedBox(height: AwSpace.x3),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton.icon(
              key: const Key('ticket-matrix-apply'),
              onPressed: busy || !changed || impact == null || urgency == null
                  ? null
                  : () => write(
                      (api) => api.setMatrixInputs(
                        widget.ticketId,
                        impact: impact,
                        urgency: urgency,
                      ),
                      (answer) => answer is String
                          ? _priorityDone(answer)
                          : 'ee.tickets.actions.inputsSaved'.tr(),
                    ),
              icon: const Icon(Icons.check),
              label: Text('ee.tickets.actions.apply'.tr()),
            ),
          ),
          if (!data.canOverridePriority) ...[
            const SizedBox(height: AwSpace.x2),
            Text(
              'ee.tickets.actions.matrixOnly'.tr(),
              key: const Key('ticket-priority-matrix-only'),
              style: _quiet(context),
            ),
          ],
        ],
        if (direct) ...[
          SizedBox(height: matrixOpen ? AwSpace.x6 : AwSpace.x4),
          Text(
            (data.usesMatrix
                    ? 'ee.tickets.actions.overrideTitle'
                    : 'ee.tickets.actions.directTitle')
                .tr(),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: AwSpace.x2),
          Wrap(
            spacing: AwSpace.x2,
            runSpacing: AwSpace.x2,
            children: [
              for (final priority in data.priorities)
                ChoiceChip(
                  key: Key('ticket-priority-$priority'),
                  label: Text('ee.tickets.priority.$priority'.tr()),
                  selected: priority == data.priority,
                  onSelected: busy || priority == data.priority
                      ? null
                      : (_) => write(
                          (api) => api.setPriority(widget.ticketId, priority),
                          _priorityDone,
                        ),
                ),
            ],
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: AwSpace.x3),
          AwInlineError(
            message: error!,
            textKey: const Key('ticket-action-error'),
          ),
        ],
      ],
    );
  }
}

class _Segments extends StatelessWidget {
  const _Segments({
    super.key,
    required this.values,
    required this.selected,
    required this.label,
    required this.onChanged,
  });

  final List<String> values;
  final String? selected;
  final String Function(String value) label;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => SegmentedButton<String>(
    showSelectedIcon: false,
    emptySelectionAllowed: true,
    segments: [
      for (final value in values)
        ButtonSegment(value: value, label: Text(label(value))),
    ],
    selected: {?selected},
    onSelectionChanged: onChanged == null
        ? null
        : (selection) {
            if (selection.isNotEmpty) onChanged!(selection.first);
          },
  );
}
