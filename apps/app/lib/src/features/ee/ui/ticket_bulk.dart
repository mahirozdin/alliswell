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
import '../../workspaces/workspaces.dart';
import '../assignments_providers.dart';
import '../data/ticket_write_api.dart';
import '../ticket_bulk_providers.dart';
import '../ticket_write_providers.dart';
import 'ticket_actions.dart' show kTicketEndings;

/// EE-227 — one action on many requests, from the queue.
///
/// ── THE SAME DOORS, FIFTY TIMES ───────────────────────────────────────
///
/// EE-171's endpoint walks every row through the single door's checks —
/// the lifecycle, the verbs, the approval gate, its own audit line — and
/// answers for each one. This screen adds nothing to that and takes nothing
/// away: the moves it offers are the server's (`eeBulkOptionsProvider`), the
/// second taps are the single sheet's (a reason before `waiting`, a yes
/// before an ending), and what comes back is shown row by row. "Nothing a
/// single request cannot do can be done in bulk" is enforced where it can be
/// enforced — on the server — and this screen's job is not to promise more.
///
/// ── HONEST ABOUT A PARTIAL ANSWER ─────────────────────────────────────
///
/// A desk's ordinary batch has a row somebody closed a minute ago. So the
/// result is "12 of 15 changed", then the three, each under the reason the
/// single door would have given. Offline the bar greys out and says why
/// (E19's rule for every write on a request): selecting works with no
/// signal, sending does not.

/// Why the batch cannot be sent right now — or null when it can.
String? bulkBlockedReason(WidgetRef ref, int count) {
  if (ref.watch(serverReachabilityProvider) == false) {
    return 'ee.tickets.bulk.offline'.tr();
  }
  if (count > kBulkMax) {
    return 'ee.tickets.bulk.tooMany'.tr(args: {'max': '$kBulkMax'});
  }
  return null;
}

/// A row's reason, in the words the single door would have used.
String bulkReasonText(String code) =>
    AwI18n.instance.maybeTranslate('ee.tickets.bulk.reason.$code') ??
    AwI18n.instance.maybeTranslate('error.$code') ??
    code;

/// One request per status the selection holds — the server is asked what
/// each status may become, not every request (`EeBulkOptions`).
String bulkRepresentatives(List<TicketRecord> tickets) {
  final byStatus = <String, String>{};
  for (final ticket in tickets) {
    byStatus.putIfAbsent(ticket.status, () => ticket.id);
  }
  return byStatus.values.join(',');
}

/// The queue's bar while requests are selected.
class EeBulkAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const EeBulkAppBar({super.key, required this.visible});

  /// The rows on screen — "select all" means these: the filter's answer.
  final List<TicketRecord> visible;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(ticketSelectionProvider);
    final chosen = [
      for (final ticket in visible)
        if (selection.contains(ticket.id)) ticket,
    ];
    final blocked = bulkBlockedReason(ref, chosen.length) != null;
    VoidCallback? open(Widget Function(List<TicketRecord>) sheet) =>
        blocked || chosen.isEmpty
        ? null
        : () => _runBatch(context, ref, sheet(chosen), chosen);
    return AppBar(
      leading: IconButton(
        key: const Key('bulk-exit'),
        tooltip: 'ee.tickets.bulk.exit'.tr(),
        icon: const Icon(Icons.close),
        onPressed: () => ref.read(ticketSelectionProvider.notifier).clear(),
      ),
      title: Text(
        'ee.tickets.bulk.selected'.tr(args: {'count': '${chosen.length}'}),
        key: const Key('bulk-count'),
      ),
      actions: [
        IconButton(
          key: const Key('bulk-select-all'),
          tooltip: 'ee.tickets.bulk.selectAll'.tr(),
          icon: const Icon(Icons.select_all),
          onPressed: () => ref
              .read(ticketSelectionProvider.notifier)
              .selectAll(visible.map((ticket) => ticket.id)),
        ),
        IconButton(
          key: const Key('bulk-status'),
          tooltip: 'ee.tickets.bulk.status'.tr(),
          icon: const Icon(Icons.swap_horiz),
          onPressed: open((tickets) => _BulkStatusSheet(tickets: tickets)),
        ),
        IconButton(
          key: const Key('bulk-priority'),
          tooltip: 'ee.tickets.bulk.priority'.tr(),
          icon: const Icon(Icons.low_priority),
          onPressed: open((tickets) => _BulkPrioritySheet(tickets: tickets)),
        ),
        IconButton(
          key: const Key('bulk-assign'),
          tooltip: 'ee.tickets.bulk.assign'.tr(),
          icon: const Icon(Icons.person_add_alt_1_outlined),
          onPressed: open((tickets) => _BulkAssignSheet(tickets: tickets)),
        ),
      ],
    );
  }
}

/// Under the bar while the batch cannot be sent: the reason, in words, so a
/// grey button is never the only thing the person gets (DESIGN §22).
class EeBulkBlockedNote extends ConsumerWidget {
  const EeBulkBlockedNote({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(ticketSelectionProvider).length;
    final reason = bulkBlockedReason(ref, count);
    if (reason == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      key: const Key('bulk-blocked'),
      padding: const EdgeInsets.fromLTRB(
        AwSpace.x4,
        AwSpace.x2,
        AwSpace.x4,
        AwSpace.x1,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AwSpace.x2),
          Expanded(child: Text(reason, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// Opens a sheet, sends from it, and says what happened.
Future<void> _runBatch(
  BuildContext context,
  WidgetRef ref,
  Widget sheet,
  List<TicketRecord> chosen,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final selection = ref.read(ticketSelectionProvider.notifier);
  final engine = ref.read(syncEngineProvider);
  final result = await showModalBottomSheet<EeBulkResult>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => sheet,
  );
  if (result == null) return;
  // The queue reads the device's copy: ask for the moved rows now rather than
  // at the next scheduled pull.
  unawaited(engine?.syncNow());
  if (result.skipped == 0) {
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          'ee.tickets.bulk.allDone'.tr(args: {'count': '${result.changed}'}),
        ),
      ),
    );
  } else if (context.mounted) {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => EeBulkResultSheet(
        result: result,
        tickets: {for (final ticket in chosen) ticket.id: ticket},
      ),
    );
  }
  selection.clear();
}

/// The send, the wait and the refusal, shared by the three sheets.
mixin _BulkSend<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  bool busy = false;
  String? error;

  List<TicketRecord> get tickets;

  Future<void> send(Map<String, Object> action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await ref.read(eeTicketWriteApiProvider).bulk([
        for (final ticket in tickets) ticket.id,
      ], action);
      if (mounted) Navigator.of(context).pop(result);
    } on ApiException catch (failure) {
      // A refusal of the whole batch (a verb it lacks) is not a row's answer:
      // it stays here, in the sheet that asked, in the server's words.
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

/// The frame all three sheets draw in: the title, the server's options (or
/// why there are none), and a refusal kept on screen.
class _BulkFrame extends ConsumerWidget {
  const _BulkFrame({
    required this.title,
    required this.tickets,
    required this.error,
    required this.builder,
  });

  final String title;
  final List<TicketRecord> tickets;
  final String? error;
  final List<Widget> Function(EeBulkOptions options) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final options = ref.watch(
      eeBulkOptionsProvider(bulkRepresentatives(tickets)),
    );
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AwSpace.x4,
          0,
          AwSpace.x4,
          AwSpace.x4,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: AwSpace.x2),
            ...options.when(
              loading: () => const [
                Padding(
                  padding: EdgeInsets.all(AwSpace.x6),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ],
              error: (failure, _) => [
                AwInlineError(message: localizedError(failure)),
              ],
              data: (data) => data == null
                  ? [Text('ee.tickets.bulk.offline'.tr())]
                  : builder(data),
            ),
            if (error != null) ...[
              const SizedBox(height: AwSpace.x3),
              AwInlineError(message: error!, textKey: const Key('bulk-error')),
            ],
          ],
        ),
      ),
    );
  }
}

class _BulkStatusSheet extends ConsumerStatefulWidget {
  const _BulkStatusSheet({required this.tickets});

  final List<TicketRecord> tickets;

  @override
  ConsumerState<_BulkStatusSheet> createState() => _BulkStatusSheetState();
}

class _BulkStatusSheetState extends ConsumerState<_BulkStatusSheet>
    with _BulkSend<_BulkStatusSheet> {
  /// The move waiting for its second step — a reason, or a yes.
  String? _target;
  String? _reason;

  @override
  List<TicketRecord> get tickets => widget.tickets;

  void _pick(String to) {
    if (to == 'waiting' || kTicketEndings.contains(to)) {
      setState(() {
        _target = to;
        _reason = null;
      });
      return;
    }
    unawaited(send({'type': 'status', 'status': to}));
  }

  @override
  Widget build(BuildContext context) {
    final count = '${widget.tickets.length}';
    return _BulkFrame(
      title: 'ee.tickets.bulk.statusTitle'.tr(args: {'count': count}),
      tickets: widget.tickets,
      error: error,
      builder: (options) {
        final target = options.moves.contains(_target) ? _target : null;
        if (target == 'waiting') {
          return [
            Text(
              'ee.tickets.waitingReasonRequired'.tr(),
              style: _quiet(context),
            ),
            RadioGroup<String>(
              groupValue: _reason,
              onChanged: (value) {
                if (!busy) setState(() => _reason = value);
              },
              child: Column(
                children: [
                  // The server's list, in its order (EE-190) — never a copy.
                  for (final reason in options.waitingReasons)
                    RadioListTile<String>(
                      key: Key('bulk-reason-$reason'),
                      contentPadding: EdgeInsets.zero,
                      value: reason,
                      title: Text('ee.sla.reason.$reason'.tr()),
                    ),
                ],
              ),
            ),
            _Buttons(
              busy: busy,
              onBack: () => setState(() => _target = null),
              label: 'ee.tickets.status.waiting'.tr(),
              onConfirm: _reason == null
                  ? null
                  : () => send({
                      'type': 'status',
                      'status': 'waiting',
                      'waitingReason': _reason!,
                    }),
            ),
          ];
        }
        if (target != null) {
          final closing = target == 'closed';
          return [
            Text(
              (closing
                      ? 'ee.tickets.bulk.confirmClose'
                      : 'ee.tickets.bulk.confirmCancel')
                  .tr(args: {'count': count}),
              key: const Key('bulk-confirm-text'),
            ),
            const SizedBox(height: AwSpace.x3),
            _Buttons(
              busy: busy,
              onBack: () => setState(() => _target = null),
              label: 'ee.tickets.status.$target'.tr(),
              onConfirm: () => send({'type': 'status', 'status': target}),
            ),
          ];
        }
        if (options.moves.isEmpty) {
          return [
            Text(
              'ee.tickets.bulk.noMoves'.tr(),
              key: const Key('bulk-no-moves'),
            ),
          ];
        }
        return [
          for (final to in options.moves)
            ListTile(
              key: Key('bulk-status-$to'),
              contentPadding: EdgeInsets.zero,
              enabled: !busy,
              leading: Icon(switch (to) {
                'closed' => Icons.task_alt,
                'cancelled' => Icons.block,
                _ => Icons.arrow_forward,
              }),
              title: Text('ee.tickets.status.$to'.tr()),
              trailing: to == 'waiting' || kTicketEndings.contains(to)
                  ? const Icon(Icons.chevron_right)
                  : null,
              onTap: () => _pick(to),
            ),
        ];
      },
    );
  }
}

class _BulkPrioritySheet extends ConsumerStatefulWidget {
  const _BulkPrioritySheet({required this.tickets});

  final List<TicketRecord> tickets;

  @override
  ConsumerState<_BulkPrioritySheet> createState() => _BulkPrioritySheetState();
}

class _BulkPrioritySheetState extends ConsumerState<_BulkPrioritySheet>
    with _BulkSend<_BulkPrioritySheet> {
  @override
  List<TicketRecord> get tickets => widget.tickets;

  @override
  Widget build(BuildContext context) => _BulkFrame(
    title: 'ee.tickets.bulk.priorityTitle'.tr(
      args: {'count': '${widget.tickets.length}'},
    ),
    tickets: widget.tickets,
    error: error,
    builder: (options) => [
      // A request whose priority is the desk's matrix answer refuses a
      // different one without `tickets.override_priority` — the server says
      // so for that row, exactly as the single sheet would.
      for (final priority in options.priorities)
        ListTile(
          key: Key('bulk-priority-$priority'),
          contentPadding: EdgeInsets.zero,
          enabled: !busy,
          title: Text('ee.tickets.priority.$priority'.tr()),
          onTap: () => send({'type': 'priority', 'priority': priority}),
        ),
    ],
  );
}

class _BulkAssignSheet extends ConsumerStatefulWidget {
  const _BulkAssignSheet({required this.tickets});

  final List<TicketRecord> tickets;

  @override
  ConsumerState<_BulkAssignSheet> createState() => _BulkAssignSheetState();
}

class _BulkAssignSheetState extends ConsumerState<_BulkAssignSheet>
    with _BulkSend<_BulkAssignSheet> {
  @override
  List<TicketRecord> get tickets => widget.tickets;

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserIdProvider);
    // The queue is one unit's workspace, so the batch has one roster.
    final roster =
        ref
            .watch(workspaceRosterOfProvider(widget.tickets.first.workspaceId))
            .value ??
        const [];
    return _BulkFrame(
      title: 'ee.tickets.bulk.assignTitle'.tr(
        args: {'count': '${widget.tickets.length}'},
      ),
      tickets: widget.tickets,
      error: error,
      builder: (options) => [
        // Taking them yourself needs no verb — the single door's rule, and
        // since EE-245 the batch's too.
        if (me != null)
          ListTile(
            key: const Key('bulk-assign-me'),
            contentPadding: EdgeInsets.zero,
            enabled: !busy,
            leading: const Icon(Icons.front_hand_outlined),
            title: Text('ee.tickets.bulk.me'.tr()),
            onTap: () => send({'type': 'assign', 'userId': me}),
          ),
        if (options.canAssignOthers)
          for (final person in roster)
            if (person.userId != me)
              ListTile(
                key: Key('bulk-assign-${person.userId}'),
                contentPadding: EdgeInsets.zero,
                enabled: !busy,
                leading: const Icon(Icons.person_outline),
                // The roster checklist's fallback, so a nameless profile
                // reads the same in both lists.
                title: Text(person.displayName ?? person.initials ?? '—'),
                onTap: () => send({'type': 'assign', 'userId': person.userId}),
              ),
        if (!options.canAssignOthers)
          Text(
            'ee.tickets.assign.selfOnly'.tr(),
            key: const Key('bulk-assign-self-only'),
            style: _quiet(context),
          ),
      ],
    );
  }
}

/// A partial answer, row by row: what changed, then each reason with the
/// requests it stopped. `NO_CHANGE` goes last — "it already was" is not a
/// failure, and leading with it would bury the rows that need a look.
class EeBulkResultSheet extends StatelessWidget {
  const EeBulkResultSheet({
    super.key,
    required this.result,
    required this.tickets,
  });

  final EeBulkResult result;
  final Map<String, TicketRecord> tickets;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final byReason = <String, List<String>>{};
    for (final row in result.rows) {
      if (row.changed) continue;
      byReason.putIfAbsent(row.reason ?? 'UNKNOWN', () => []).add(row.ticketId);
    }
    final reasons = byReason.keys.toList()
      ..sort((a, b) => (a == 'NO_CHANGE' ? 1 : 0) - (b == 'NO_CHANGE' ? 1 : 0));
    String label(String id) {
      final ticket = tickets[id];
      if (ticket == null) return id;
      return ticket.number == null
          ? ticket.subject
          : '#${ticket.number} · ${ticket.subject}';
    }

    return SafeArea(
      child: SingleChildScrollView(
        key: const Key('bulk-result'),
        padding: const EdgeInsets.fromLTRB(
          AwSpace.x4,
          0,
          AwSpace.x4,
          AwSpace.x4,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'ee.tickets.bulk.partial'.tr(
                args: {
                  'changed': '${result.changed}',
                  'total': '${result.changed + result.skipped}',
                },
              ),
              key: const Key('bulk-result-title'),
              style: theme.textTheme.titleMedium,
            ),
            for (final reason in reasons) ...[
              const SizedBox(height: AwSpace.x3),
              Text(
                '${bulkReasonText(reason)} (${byReason[reason]!.length})',
                key: Key('bulk-result-$reason'),
                style: theme.textTheme.titleSmall,
              ),
              for (final id in byReason[reason]!)
                Padding(
                  padding: const EdgeInsets.only(top: AwSpace.x1),
                  child: Text('• ${label(id)}', style: _quiet(context)),
                ),
            ],
            const SizedBox(height: AwSpace.x4),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton(
                key: const Key('bulk-result-ok'),
                onPressed: () => Navigator.of(context).pop(),
                child: Text('ee.tickets.bulk.ok'.tr()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Buttons extends StatelessWidget {
  const _Buttons({
    required this.busy,
    required this.onBack,
    required this.label,
    required this.onConfirm,
  });

  final bool busy;
  final VoidCallback onBack;
  final String label;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.end,
    spacing: AwSpace.x2,
    children: [
      TextButton(
        key: const Key('bulk-back'),
        onPressed: busy ? null : onBack,
        child: Text('ee.tickets.bulk.back'.tr()),
      ),
      FilledButton(
        key: const Key('bulk-confirm'),
        onPressed: busy ? null : onConfirm,
        child: busy
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(label),
      ),
    ],
  );
}

TextStyle? _quiet(BuildContext context) => Theme.of(context).textTheme.bodySmall
    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
