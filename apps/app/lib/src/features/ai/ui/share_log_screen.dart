import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/date_format.dart';
import '../../../core/persisted_prefs.dart';
import '../../../i18n/i18n.dart';
import '../../../sync/db/database.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../data/share_intent.dart';
import '../data/share_log.dart';

/// The share log (OPH-242): a plain, read-only list of what actually reached
/// the app when something was shared to it, newest first, plus one sentence of
/// honest scope.
///
/// It exists because round 17 opened with a report nothing could settle — "I
/// shared a text, chose AllisWell, and nothing happened, not even a crash". The
/// `AlarmLogScreen` twin, for the same reason and with the same shape.
///
/// The scope sentence carries the finding that matters: **an empty list after a
/// share attempt is itself the answer** — the payload never reached the app, so
/// the fault is on the OS side of the hand-off, not in how the app routes it.
class ShareLogScreen extends ConsumerWidget {
  const ShareLogScreen({super.key});

  static String _label(String event) => switch (event) {
    ShareLogEvent.initialShare => 'shareLog.event.initialShare'.tr(),
    ShareLogEvent.warmShare => 'shareLog.event.warmShare'.tr(),
    ShareLogEvent.initialDocument => 'shareLog.event.initialDocument'.tr(),
    ShareLogEvent.warmDocument => 'shareLog.event.warmDocument'.tr(),
    ShareLogEvent.readFailed => 'shareLog.event.readFailed'.tr(),
    ShareLogEvent.consumed => 'shareLog.event.consumed'.tr(),
    _ => event,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(shareLogRowsProvider).value ?? const <ShareEvent>[];
    final dateFormat = ref.watch(dateFormatProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('shareLog.title'.tr()),
        actions: [
          IconButton(
            key: const Key('share-log-copy'),
            tooltip: 'shareLog.copy'.tr(),
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: rows.isEmpty
                ? null
                : () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await Clipboard.setData(
                      ClipboardData(
                        text: rows.map(formatShareLogLine).join('\n'),
                      ),
                    );
                    messenger.showSnackBar(
                      SnackBar(content: Text('shareLog.copied'.tr())),
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
                          'shareLog.scope'.tr(),
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
                  icon: Icons.ios_share_outlined,
                  title: 'shareLog.emptyTitle'.tr(),
                  message: 'shareLog.emptyBody'.tr(),
                )
              else
                for (final row in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Card(
                      child: ListTile(
                        dense: true,
                        title: Text(
                          _label(row.event),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          // Data, not prose: the part that goes into a bug
                          // report verbatim.
                          formatShareLogLine(row),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
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
