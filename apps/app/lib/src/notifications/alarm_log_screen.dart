import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/date_format.dart';
import '../core/persisted_prefs.dart';
import '../i18n/i18n.dart';
import '../sync/db/database.dart';
import '../theme/tokens.dart';
import '../widgets/status_views.dart';
import 'alarm_log.dart';
import 'providers.dart';
import '../widgets/route_leading.dart';
import '../theme/typography.dart';

/// The alarm log (OPH-176, DESIGN §11 A6): a plain, read-only list of what this
/// device DID about alarms, newest first, plus one sentence of honest scope.
///
/// It exists because round 9 was diagnosed from memory and could not be settled:
/// which lane fired, with which sound, at which slot. It does NOT pretend to
/// know about delivery — iOS reports nothing for a notification the user never
/// touches — so it shows what was scheduled, what the user interacted with, and
/// what rang in-app.
///
/// OPH-395 (E-29): each row reads as words — what happened, on which surface,
/// when it rings — and the raw diagnostic line (ISO UTC, slot, level, ids)
/// sits behind a per-row "Details" toggle. "Copy the log" still copies the raw
/// lines, which is what a bug report needs.
class AlarmLogScreen extends ConsumerWidget {
  const AlarmLogScreen({super.key});

  static String _label(String event) => switch (event) {
    AlarmLogEvent.scheduled => 'alarmLog.event.scheduled'.tr(),
    AlarmLogEvent.cancelled => 'alarmLog.event.cancelled'.tr(),
    AlarmLogEvent.interacted => 'alarmLog.event.interacted'.tr(),
    AlarmLogEvent.action => 'alarmLog.event.action'.tr(),
    AlarmLogEvent.ringShown => 'alarmLog.event.ringShown'.tr(),
    AlarmLogEvent.degraded => 'alarmLog.event.degraded'.tr(),
    AlarmLogEvent.delivered => 'alarmLog.event.delivered'.tr(),
    AlarmLogEvent.dropped => 'alarmLog.event.dropped'.tr(),
    AlarmLogEvent.test => 'alarmLog.event.test'.tr(),
    _ => event,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(alarmLogRowsProvider).value ?? const <AlarmEvent>[];
    final dateFormat = ref.watch(dateFormatProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: awRouteLeading(context),
        title: Text('alarmLog.title'.tr()),
        actions: [
          IconButton(
            key: const Key('alarm-log-copy'),
            tooltip: 'alarmLog.copy'.tr(),
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: rows.isEmpty
                ? null
                : () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await Clipboard.setData(
                      ClipboardData(
                        text: rows.map(formatAlarmLogLine).join('\n'),
                      ),
                    );
                    messenger.showSnackBar(
                      SnackBar(content: Text('alarmLog.copied'.tr())),
                    );
                  },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: awListPadding(context, top: AwSpace.x2),
            children: [
              // The honest scope, before the data (A6): never claim a delivery
              // we cannot observe.
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AwSpace.x4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: AwSpace.x3),
                      Expanded(
                        child: Text(
                          'alarmLog.scope'.tr(),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AwSpace.x3),
              if (rows.isEmpty)
                AwEmptyState(
                  icon: Icons.history_toggle_off,
                  title: 'alarmLog.emptyTitle'.tr(),
                  message: 'alarmLog.emptyBody'.tr(),
                )
              else
                for (final row in rows)
                  Padding(
                    padding: kAwListRowPadding,
                    child: _AlarmLogRow(
                      row: row,
                      label: _label(row.event),
                      dateFormat: dateFormat,
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

String _laneLabel(String lane) => switch (lane) {
  AlarmLogLane.notification => 'alarmLog.lane.notification'.tr(),
  AlarmLogLane.alarmkit => 'alarmLog.lane.alarmkit'.tr(),
  AlarmLogLane.inapp => 'alarmLog.lane.inapp'.tr(),
  _ => lane,
};

class _AlarmLogRow extends StatefulWidget {
  const _AlarmLogRow({
    required this.row,
    required this.label,
    required this.dateFormat,
  });

  final AlarmEvent row;
  final String label;
  final String dateFormat;

  @override
  State<_AlarmLogRow> createState() => _AlarmLogRowState();
}

class _AlarmLogRowState extends State<_AlarmLogRow> {
  var _open = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final row = widget.row;
    final summary = [
      _laneLabel(row.lane),
      if (row.urgent) 'alarmLog.urgent'.tr(),
      if (row.fireAt != null)
        'alarmLog.ringsAt'.tr(
          args: {'time': awFormatShort(row.fireAt!, format: widget.dateFormat)},
        ),
    ].join(' · ');

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            title: Text(
              widget.label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              summary,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
            trailing: Text(
              awFormatShort(row.at, format: widget.dateFormat),
              style: awTabular(
                theme.textTheme.labelSmall!.copyWith(color: muted),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: AwSpace.x2),
            child: TextButton.icon(
              key: Key('alarm-log-details-${row.id}'),
              style: TextButton.styleFrom(
                foregroundColor: muted,
                minimumSize: const Size(48, 48),
              ),
              onPressed: () => setState(() => _open = !_open),
              icon: Icon(
                _open ? Icons.expand_less : Icons.expand_more,
                size: 20,
              ),
              label: Semantics(
                expanded: _open,
                child: Text('alarmLog.details'.tr()),
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AwSpace.x4,
                0,
                AwSpace.x4,
                AwSpace.x3,
              ),
              // Data, not prose: the part that goes into a bug report
              // verbatim, so it can be selected and copied.
              child: SelectableText(
                formatAlarmLogLine(row),
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ),
        ],
      ),
    );
  }
}
