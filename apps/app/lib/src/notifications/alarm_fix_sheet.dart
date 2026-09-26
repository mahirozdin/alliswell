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
///
/// **And on the web (#19)** the same button opened `app-settings:` in a new
/// tab — an iOS address no browser knows, so the tab was dead and the promised
/// fix unreachable. Every problem now maps to its action through one
/// exhaustive switch ([_actionFor]): a new problem does not compile until
/// someone decides what its button does, instead of falling through to the
/// iOS page on a platform that has none.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/integrations/providers.dart' show urlLauncherProvider;
import '../i18n/i18n.dart';
import '../theme/tokens.dart';
import '../widgets/sheets.dart';
import 'gateway.dart';
import 'providers.dart';

/// The OS page that holds the switch on iOS/macOS.
///
/// `app-settings:` is Apple's documented deep link to an app's own Settings
/// page — the one place every switch in the cascade lives. Only the problems a
/// NATIVE gateway reports open it; a browser never gets here, because
/// `url_launcher` on the web does not fail on an unknown scheme — it opens a
/// tab, and the tab is a dead end (#19).
const String kIosAppSettingsUrl = 'app-settings:';

Future<void> showAlarmFixSheet(
  BuildContext context,
  WidgetRef ref,
  AlarmProblem problem,
) => showAwSheet<void>(
  context,
  builder: (_) => _AlarmFixSheet(problem: problem),
);

/// What the sheet's one button does.
enum _FixAction {
  /// An iOS/macOS switch on the app's own Settings page.
  openAppSettings,

  /// Android's special-access screen, which the plugin's own request
  /// deep-links.
  askOs,

  /// A browser that has not been asked: its prompt IS the fix.
  askBrowser,

  /// A browser that has answered, or granted without a subscription (OPH-313).
  /// Asking again shows nothing while it is blocked and subscribes the moment
  /// the user has allowed it — so the honest label is "check again", after
  /// the steps above it have been followed.
  checkAgain,

  /// Nothing a button can do: a browser with no web push at all.
  none,
}

_FixAction _actionFor(AlarmProblem problem) => switch (problem) {
  AlarmProblem.notificationsOff ||
  AlarmProblem.provisional ||
  AlarmProblem.soundOff ||
  AlarmProblem.alertOff ||
  AlarmProblem.timeSensitiveOff ||
  AlarmProblem.alarmKitOff => _FixAction.openAppSettings,
  AlarmProblem.exactAlarmsOff => _FixAction.askOs,
  AlarmProblem.webPermissionPrompt => _FixAction.askBrowser,
  AlarmProblem.webPermissionBlocked ||
  AlarmProblem.webPushOff => _FixAction.checkAgain,
  AlarmProblem.webUnsupported => _FixAction.none,
};

class _AlarmFixSheet extends ConsumerWidget {
  const _AlarmFixSheet({required this.problem});

  final AlarmProblem problem;

  Future<void> _run(BuildContext context, _FixAction action) async {
    // Read before anything is awaited. A browser's permission prompt is not
    // modal, so the sheet can be dismissed while it is open — and after that
    // a WidgetRef throws and a blind `pop()` would close someone else's route.
    final container = ProviderScope.containerOf(context, listen: false);
    final navigator = Navigator.of(context);
    switch (action) {
      case _FixAction.askOs:
      case _FixAction.askBrowser:
      case _FixAction.checkAgain:
        // Nothing is awaited before this call on purpose: Safari shows its
        // prompt only from inside the tap that asked for it.
        try {
          await container
              .read(notificationsGatewayProvider)
              .requestPermissions();
        } on Object {
          // A refusal and a missing platform surface both just re-probe below.
        }
      case _FixAction.openAppSettings:
        // Best effort by design: a platform with no such URL simply leaves the
        // written steps, which are the part that actually explains the fix.
        try {
          await container
              .read(urlLauncherProvider)
              .call(Uri.parse(kIosAppSettingsUrl));
        } on Object {
          // The steps stand on their own.
        }
      case _FixAction.none:
        return;
    }
    container.invalidate(alarmSupportProvider);
    if (context.mounted && navigator.canPop()) navigator.pop();
  }

  /// The button's words and icon, or null when there is nothing to press.
  (String, IconData)? _button(_FixAction action) => switch (action) {
    _FixAction.openAppSettings ||
    _FixAction.askOs => ('alarm.fix.open'.tr(), Icons.settings_outlined),
    _FixAction.askBrowser => (
      'alarm.fix.allow'.tr(),
      Icons.notifications_active_outlined,
    ),
    _FixAction.checkAgain => ('alarm.fix.checkAgain'.tr(), Icons.refresh),
    _FixAction.none => null,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final action = _actionFor(problem);
    final button = _button(action);
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
            if (button != null) ...[
              const SizedBox(height: AwSpace.x4),
              FilledButton.icon(
                key: const Key('alarm-fix-open'),
                onPressed: () => _run(context, action),
                icon: Icon(button.$2),
                label: Text(button.$1),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
