/// "Why isn't my alarm ringing, and where do I turn it back on?" (OPH-277).
///
/// Round 19's report ended with the sentence this file exists to answer: *"if
/// it is a permission problem it should at least warn me and I should be able
/// to know where to open it — I don't know what the problem is."*
///
/// Two things were missing, and they compounded. The probe threw away four of
/// the five answers the OS gives it (`gateway_local.alarmSupport`), so most
/// broken states looked healthy. And the one banner that did appear re-ran
/// `requestPermissions()` on tap — which does nothing at all once the user has
/// answered the prompt, because iOS never shows it twice. A warning nobody sees
/// and a fix button that cannot fix anything.
///
/// So: one sheet, one problem at a time, naming the switch and opening the page
/// that holds it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/integrations/providers.dart' show urlLauncherProvider;
import '../i18n/i18n.dart';
import '../theme/tokens.dart';
import '../widgets/sheets.dart';
import 'gateway.dart';
import 'providers.dart';

/// The OS page that holds the switch, per platform.
///
/// `app-settings:` is Apple's documented deep link to an app's own Settings
/// page — the one place every switch in the cascade lives. Android has no
/// single equivalent, and the plugin already deep-links "Alarms & reminders"
/// from `requestPermissions()`, so there the sheet re-runs that instead.
const String kIosAppSettingsUrl = 'app-settings:';

Future<void> showAlarmFixSheet(
  BuildContext context,
  WidgetRef ref,
  AlarmProblem problem,
) => showAwSheet<void>(
  context,
  builder: (_) => _AlarmFixSheet(problem: problem),
);

class _AlarmFixSheet extends ConsumerWidget {
  const _AlarmFixSheet({required this.problem});

  final AlarmProblem problem;

  /// Android's special-access screens are reached through the plugin's own
  /// request; everything else is an iOS/macOS switch on the app's page.
  bool get _isAndroidSpecialAccess => problem == AlarmProblem.exactAlarmsOff;

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final navigator = Navigator.of(context);
    if (_isAndroidSpecialAccess) {
      await ref.read(notificationsGatewayProvider).requestPermissions();
    } else {
      // Best effort by design: a platform with no such URL simply leaves the
      // written steps, which are the part that actually explains the fix.
      try {
        await ref.read(urlLauncherProvider).call(Uri.parse(kIosAppSettingsUrl));
      } on Object {
        // The steps stand on their own.
      }
    }
    ref.invalidate(alarmSupportProvider);
    if (navigator.canPop()) navigator.pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AwSpace.x5,
          AwSpace.x2,
          AwSpace.x5,
          AwSpace.x5,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.alarm_off_outlined, color: scheme.error),
                const SizedBox(width: AwSpace.x2),
                Expanded(
                  child: Text(
                    'alarm.problem.${problem.name}'.tr(),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AwSpace.x3),
            Text(
              'alarm.fix.${problem.name}'.tr(),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AwSpace.x4),
            FilledButton.icon(
              key: const Key('alarm-fix-open'),
              onPressed: () => _open(context, ref),
              icon: const Icon(Icons.settings_outlined),
              label: Text('alarm.fix.open'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}
