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

/// The alarm log (OPH-176, DESIGN §11 A6): a plain, read-only list of what this
/// device DID about alarms, newest first, plus one sentence of honest scope.
///
/// It exists because round 9 was diagnosed from memory and could not be settled:
/// which lane fired, with which sound, at which slot. It does NOT pretend to
/// know about delivery — iOS reports nothing for a notification the user never
/// touches — so it shows what was scheduled, what the user interacted with, and
/// what rang in-app.
class AlarmLogScreen extends ConsumerWidget {
  const AlarmLogScreen({super.key});

  static String _label(String event) => switch (event) {
    AlarmLogEvent.scheduled => 'alarmLog.event.scheduled'.tr(),
    AlarmLogEvent.cancelled => 'alarmLog.event.cancelled'.tr(),
    AlarmLogEvent.interacted => 'alarmLog.event.interacted'.tr(),
    AlarmLogEvent.action => 'alarmLog.event.action'.tr(),
    AlarmLogEvent.ringShown => 'alarmLog.event.ringShown'.tr(),
    AlarmLogEvent.degraded => 'alarmLog.event.degraded'.tr(),
    _ => event,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(alarmLogRowsProvider).value ?? const <AlarmEvent>[];
    final dateFormat = ref.watch(dateFormatProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
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
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Card(
                      child: ListTile(
                        dense: true,
                        title: Text(
                          '${_label(row.event)} · ${row.lane}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          // Data, not prose: the part that goes into a bug
                          // report verbatim.
                          formatAlarmLogLine(row),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontFeatures: const [],
                          ),
                        ),
                        trailing: Text(
                          awFormatTime(row.at, format: dateFormat),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
