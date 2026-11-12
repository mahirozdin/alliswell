import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/persisted_prefs.dart';
import '../features/devices/providers.dart' show noRingingDeviceProvider;
import '../i18n/i18n.dart';
import '../theme/tokens.dart';
import 'alarm_fix_sheet.dart';
import 'alarm_overlay.dart' show alarmClockProvider;
import 'gateway.dart';
import 'providers.dart';

/// Where a closed strip is remembered: `<problem>@<until, epoch ms>`.
/// Device-local, like the probe it hides — another device has its own OS.
const String kAlarmBannerDismissedKey = 'alliswell_alarm_banner_dismissed';

/// How long "×" hides a strip (OPH-393, U-05). Long enough to stop nagging,
/// short enough that a problem nobody fixed comes back to be seen.
const Duration kAlarmBannerSnooze = Duration(days: 7);

final alarmBannerDismissedProvider = NotifierProvider<PersistedChoice, String>(
  () => PersistedChoice(kAlarmBannerDismissedKey, fallback: ''),
);

/// Where the closed "no device rings urgent alarms" item is remembered, in
/// the same `<item>@<until>` form. Its own key: closing a permission strip
/// after it must not bring it back (OPH-453).
const String kAlarmBannerDeviceDismissedKey =
    'alliswell_alarm_banner_device_dismissed';

final alarmBannerDeviceDismissedProvider =
    NotifierProvider<PersistedChoice, String>(
      () => PersistedChoice(kAlarmBannerDeviceDismissedKey, fallback: ''),
    );

const String _noRingingDevice = 'noRingingDevice';

/// Whether the item called [name] was closed and its week is not over yet.
bool _dismissed(String stored, String name, DateTime now) {
  final at = stored.lastIndexOf('@');
  if (at <= 0 || stored.substring(0, at) != name) return false;
  final until = int.tryParse(stored.substring(at + 1));
  return until != null && now.millisecondsSinceEpoch < until;
}

/// The verb on the strip's button, or null when nothing the person presses
/// can fix it (Ek A A-02…A-06; OPH-393). The sentence never says "tap": the
/// button says what it does (§3.3).
String? _actionKey(AlarmProblem problem) => switch (problem) {
  AlarmProblem.notificationsOff ||
  AlarmProblem.provisional ||
  AlarmProblem.soundOff ||
  AlarmProblem.alertOff ||
  AlarmProblem.timeSensitiveOff => 'alarm.banner.turnOn',
  AlarmProblem.alarmKitOff ||
  AlarmProblem.exactAlarmsOff ||
  AlarmProblem.webPermissionPrompt => 'alarm.banner.allow',
  AlarmProblem.webPushOff => 'alarm.banner.finishSetup',
  AlarmProblem.webPermissionBlocked ||
  AlarmProblem.webUnsupported => 'alarm.banner.showHow',
  // The server's admin fixes this one; the strip only says so (E-14).
  AlarmProblem.webPushUnconfigured => null,
};

/// Honest degradation strip (OPH-143; NOTIFICATIONS.md §1 "never fail
/// silently"): when the OS can't ring urgent alarms reliably, say so at the top
/// of Home and offer the fix. Renders nothing when delivery is healthy, still
/// being probed, or while a permission prompt is open.
///
/// OPH-393 (U-05, E-14): a warning, not an alarm — amber, one calm sentence,
/// a verb button, and an "×" that hides it for a week. A server without push
/// keys is the admin's message, never the person's fault.
///
/// OPH-453 (#48): when the account has devices and none rings urgent alarms,
/// that goes first — it is why no alarm rings anywhere, this device's
/// permissions included — with "Choose a device" into Settings ▸ Devices.
/// One strip at a time; closing it lets the next one through.
class AlarmDegradationBanner extends ConsumerWidget {
  const AlarmDegradationBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The OS prompt is asking the question this strip would answer: wait for
    // the answer (ios/05 showed "notifications are off" behind it).
    if (ref.watch(alarmPermissionAskProvider) > 0) {
      return const SizedBox.shrink();
    }
    final now = ref.watch(alarmClockProvider)();
    String until() => '${now.add(kAlarmBannerSnooze).millisecondsSinceEpoch}';

    if (ref.watch(noRingingDeviceProvider) &&
        !_dismissed(
          ref.watch(alarmBannerDeviceDismissedProvider),
          _noRingingDevice,
          now,
        )) {
      void pick() => context.push('/settings/devices');
      return _Strip(
        itemKey: const Key('alarm-banner-no-device'),
        surfaceKey: const Key('alarm-banner-no-device-surface'),
        icon: Icons.devices_outlined,
        message: 'alarm.banner.noRingingDevice'.tr(),
        action: 'alarm.banner.pickDevice'.tr(),
        actionKey: const Key('alarm-banner-pick-device'),
        onOpen: pick,
        onAction: pick,
        onClose: () => ref
            .read(alarmBannerDeviceDismissedProvider.notifier)
            .set('$_noRingingDevice@${until()}'),
      );
    }

    final support = ref.watch(alarmSupportProvider).value;
    if (support == null) return const SizedBox.shrink();

    // Worst problem first — and the cascade itself lives on [AlarmSupport]
    // (OPH-277), so this strip and the Settings row cannot drift apart.
    final problem = support.worstProblem;
    if (problem == null) return const SizedBox.shrink();
    if (_dismissed(
      ref.watch(alarmBannerDismissedProvider),
      problem.name,
      now,
    )) {
      return const SizedBox.shrink();
    }
    final actionKey = _actionKey(problem);
    // Round 19: the old banner re-ran `requestPermissions()`, which does
    // nothing once the person has answered. It opens the page that CAN fix
    // it, and says which switch to look for.
    void fix() => showAlarmFixSheet(context, ref, problem);
    return _Strip(
      itemKey: const Key('alarm-banner'),
      surfaceKey: const Key('alarm-banner-surface'),
      icon: problem == AlarmProblem.webPushUnconfigured
          ? Icons.dns_outlined
          : Icons.notifications_off_outlined,
      message: 'alarm.problem.${problem.name}'.tr(),
      action: actionKey?.tr(),
      actionKey: const Key('alarm-banner-action'),
      // The sentence is a target too: it opens the same explanation.
      onOpen: fix,
      onAction: fix,
      onClose: () => ref
          .read(alarmBannerDismissedProvider.notifier)
          .set('${problem.name}@${until()}'),
    );
  }
}

/// One item of the band: icon, sentence, an optional verb and "×".
class _Strip extends StatelessWidget {
  const _Strip({
    required this.itemKey,
    required this.surfaceKey,
    required this.icon,
    required this.message,
    required this.action,
    required this.actionKey,
    required this.onOpen,
    required this.onAction,
    required this.onClose,
  });

  final Key itemKey;
  final Key surfaceKey;
  final IconData icon;
  final String message;

  /// The verb on the button, or null when nothing the person presses fixes it.
  final String? action;
  final Key actionKey;
  final VoidCallback onOpen;
  final VoidCallback onAction;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tokens = context.awTokens;
    // DESIGN §7: a state colour tints the surface at 10% and colours the icon
    // only; the words stay `onSurface` (warning as text measures 2.96:1).
    final surface = Color.alphaBlend(
      tokens.warning.withValues(alpha: 0.10),
      scheme.surface,
    );
    final ink = scheme.onSurface;
    // Large text: a button squeezed beside two lines of 2× text truncates the
    // sentence, so it drops below at full width (U-05).
    final stacked = MediaQuery.textScalerOf(context).scale(1) > 1.3;

    final message = Text(
      this.message,
      style: theme.textTheme.bodyMedium?.copyWith(color: ink),
    );
    final label = this.action;
    final action = label == null
        ? null
        : TextButton(
            key: actionKey,
            style: TextButton.styleFrom(
              foregroundColor: ink,
              minimumSize: const Size(48, 44),
              textStyle: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            onPressed: onAction,
            child: Text(label),
          );
    final close = IconButton(
      key: const Key('alarm-banner-close'),
      tooltip: 'alarm.banner.close'.tr(),
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      icon: Icon(Icons.close, size: 20, color: scheme.onSurfaceVariant),
      onPressed: onClose,
    );
    final icon = Icon(this.icon, size: 20, color: tokens.warning);

    return Padding(
      padding: const EdgeInsets.fromLTRB(AwSpace.x4, AwSpace.x2, AwSpace.x4, 0),
      child: Material(
        key: surfaceKey,
        color: surface,
        borderRadius: const BorderRadius.all(Radius.circular(AwRadius.m)),
        child: InkWell(
          key: itemKey,
          borderRadius: const BorderRadius.all(Radius.circular(AwRadius.m)),
          onTap: onOpen,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsetsDirectional.only(start: AwSpace.x3),
              child: stacked
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            icon,
                            const SizedBox(width: AwSpace.x2),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: AwSpace.x3,
                                ),
                                child: message,
                              ),
                            ),
                            close,
                          ],
                        ),
                        if (action != null)
                          Padding(
                            padding: const EdgeInsetsDirectional.only(
                              end: AwSpace.x3,
                              bottom: AwSpace.x2,
                            ),
                            child: action,
                          ),
                      ],
                    )
                  : Row(
                      children: [
                        icon,
                        const SizedBox(width: AwSpace.x2),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: AwSpace.x2,
                            ),
                            child: message,
                          ),
                        ),
                        ?action,
                        close,
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
