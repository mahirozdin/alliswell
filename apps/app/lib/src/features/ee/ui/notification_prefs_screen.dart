import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_messages.dart';
import '../../../i18n/i18n.dart';
import '../../../widgets/status_views.dart';
import '../data/notification_prefs_api.dart';
import '../notification_prefs_providers.dart';

/// The preference screen (EE-077, on EE-076's matrix).
///
/// EVERY SWITCH IS DRAWN FROM THE SERVER'S MATRIX, including the ones that
/// cannot move. A locked switch is shown disabled with the reason beside it
/// rather than hidden: hiding it would answer "can I stop these SLA e-mails?"
/// with silence, and somebody would keep looking. `silenceable` arrives as data
/// precisely so this screen does not need its own copy of the policy — one
/// answer, on the server, where it is also enforced.
class EeNotificationPrefsScreen extends ConsumerWidget {
  const EeNotificationPrefsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(eeNotificationPrefsProvider);
    return Scaffold(
      appBar: AppBar(title: Text('ee.notif.prefsTitle'.tr())),
      body: prefs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AwErrorState(message: localizedError(error)),
        data: (data) => ListView(
          padding: awListPadding(context),
          children: [
            for (final row in data.matrix) _ClassRow(row: row),
            const Divider(height: 32),
            _QuietHours(prefs: data),
          ],
        ),
      ),
    );
  }
}

class _ClassRow extends ConsumerWidget {
  const _ClassRow({required this.row});

  final EeNotificationPrefRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                // A CATEGORY label, not the notification's own title.
                //
                // This first reused `ee.notif.<class>.title` — the key the
                // notification itself renders with — on the reasoning that one
                // wording could not drift from the other. The screenshot said
                // otherwise: those titles carry parameters, so the screen read
                // "Size atandı: {taskTitle}". A preference names a KIND of
                // event ("when work is assigned to you"); a notification names
                // an instance of one. They are different sentences, and every
                // test was green while this one was wrong.
                'ee.notif.class.${row.eventClass}'.tr(),
                style: theme.textTheme.titleSmall,
              ),
            ),
            if (!row.silenceable)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'ee.notif.prefsLockedWhy'.tr(),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            for (final channel in row.channels)
              SwitchListTile(
                key: Key('notif-pref-${row.eventClass}-$channel'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  channel == 'push'
                      ? 'ee.notif.prefsPush'.tr()
                      : 'ee.notif.prefsEmail'.tr(),
                ),
                subtitle: row.silenceable
                    ? null
                    : Text('ee.notif.prefsLocked'.tr()),
                // ON means "send me this", so the stored MUTE is inverted here.
                value: !row.isMuted(channel),
                // A locked class has no onChanged at all: Flutter greys the
                // switch itself, which is the platform saying what a custom
                // colour would only imply (DESIGN §22).
                onChanged: row.silenceable
                    ? (wantsIt) => ref
                          .read(eeNotificationPrefsProvider.notifier)
                          .setMuted(
                            eventClass: row.eventClass,
                            channel: channel,
                            muted: !wantsIt,
                          )
                    : null,
              ),
          ],
        ),
      ),
    );
  }
}

/// Quiet hours: two times, and a sentence saying what they do NOT do.
///
/// "E-mail that arrives in this window is not dropped" is on the screen because
/// it is the question this control actually raises — a person who thinks quiet
/// hours delete their notifications will not use them, and one who finds out
/// afterwards that they did will not trust the app again.
class _QuietHours extends ConsumerWidget {
  const _QuietHours({required this.prefs});

  final EeNotificationPrefs prefs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final notifier = ref.read(eeNotificationPrefsProvider.notifier);

    Future<void> pick({required bool start}) async {
      final current = start ? prefs.quietFrom : prefs.quietTo;
      final initial = TimeOfDay(
        hour: (current ?? (start ? 22 * 60 : 7 * 60)) ~/ 60,
        minute: (current ?? 0) % 60,
      );
      final picked = await showTimePicker(
        context: context,
        initialTime: initial,
      );
      if (picked == null) return;
      final minutes = picked.hour * 60 + picked.minute;
      final from = start ? minutes : (prefs.quietFrom ?? 22 * 60);
      final to = start ? (prefs.quietTo ?? 7 * 60) : minutes;
      if (from == to) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('ee.notif.quietSame'.tr())));
        return;
      }
      await notifier.setQuietHours(from: from, to: to);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ee.notif.quietTitle'.tr(), style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text('ee.notif.quietBody'.tr(), style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        ListTile(
          key: const Key('notif-quiet-summary'),
          contentPadding: EdgeInsets.zero,
          title: Text(
            prefs.hasQuietHours
                ? 'ee.notif.quietRange'.tr(
                    args: {
                      'from': _hhmm(prefs.quietFrom!),
                      'to': _hhmm(prefs.quietTo!),
                      'zone': prefs.timezone,
                    },
                  )
                : 'ee.notif.quietOff'.tr(),
          ),
          trailing: prefs.hasQuietHours
              ? IconButton(
                  key: const Key('notif-quiet-clear'),
                  icon: const Icon(Icons.close),
                  onPressed: () => notifier.setQuietHours(),
                )
              : null,
        ),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: const Key('notif-quiet-start'),
                onPressed: () => pick(start: true),
                child: Text('ee.notif.quietStart'.tr()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                key: const Key('notif-quiet-end'),
                onPressed: () => pick(start: false),
                child: Text('ee.notif.quietEnd'.tr()),
              ),
            ),
          ],
        ),
      ],
    );
  }

  static String _hhmm(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
      '${(minutes % 60).toString().padLeft(2, '0')}';
}
