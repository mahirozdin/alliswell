import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/providers.dart';
import '../features/calendar/apple/apple_calendar_card.dart';
import '../features/integrations/ui/google_calendar_card.dart';
import '../features/onboarding/tour.dart';
import '../features/settings/account_locale.dart';
import '../i18n/i18n.dart';
import '../notifications/gateway.dart';
import '../notifications/providers.dart';
import '../theme/tokens.dart';
import '../widgets/status_views.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider).value;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('settings.title'.tr())),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: awListPadding(context, top: AwSpace.x2),
            children: [
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: scheme.primaryContainer,
                        child: Icon(
                          Icons.person_outline,
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                      title: Text(
                        session?.user.displayName ?? 'settings.account'.tr(),
                      ),
                      subtitle: Text(
                        session?.user.email ?? 'settings.notSignedIn'.tr(),
                      ),
                    ),
                    const Divider(indent: AwSpace.x4, endIndent: AwSpace.x4),
                    ListTile(
                      leading: const Icon(Icons.dns_outlined),
                      title: Text('settings.server'.tr()),
                      subtitle: Text(ref.watch(apiBaseUrlProvider)),
                    ),
                    // OPH-064: lock-screen privacy — generic notification
                    // content ("Bir hatırlatıcın var") instead of task titles.
                    SwitchListTile(
                      key: const Key('notification-privacy'),
                      secondary: const Icon(Icons.notifications_outlined),
                      title: Text('settings.privateNotifications'.tr()),
                      subtitle: Text('settings.privateNotificationsSub'.tr()),
                      value: ref.watch(notificationPrivacyProvider),
                      onChanged: (_) => ref
                          .read(notificationPrivacyProvider.notifier)
                          .toggle(),
                    ),
                    // Feedback round 6: an honest status row for the
                    // product's backbone — can the alarm actually ring on
                    // this device? Tapping re-runs the permission flow.
                    const _AlarmStatusTile(),
                    // OPH-111: replay the first-run tour on demand. Start it,
                    // then pop back to the shell where the overlay lives.
                    ListTile(
                      key: const Key('replay-tour'),
                      leading: const Icon(Icons.help_outline),
                      title: Text('settings.appTour'.tr()),
                      subtitle: Text('settings.appTourSub'.tr()),
                      onTap: () {
                        ref.read(tourControllerProvider.notifier).start();
                        Navigator.of(context).pop();
                      },
                    ),
                    // OPH-121: language override. Following the device shows the
                    // "System default" subtitle; an explicit pick shows its
                    // endonym. Changing it rebuilds the whole app (app.dart).
                    ListTile(
                      key: const Key('settings-language'),
                      leading: const Icon(Icons.language_outlined),
                      title: Text('settings.language.title'.tr()),
                      subtitle: Text(
                        AwI18n.instance.followsDevice
                            ? 'settings.language.system'.tr()
                            : awLanguageEndonyms[AwI18n
                                      .instance
                                      .locale
                                      .languageCode] ??
                                  AwI18n.instance.locale.languageCode,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => showLanguagePicker(context),
                    ),
                    AboutListTile(
                      icon: const Icon(Icons.info_outline),
                      applicationName: 'AllisWell',
                      applicationVersion: '0.1.0',
                      aboutBoxChildren: [Text('settings.aboutBody'.tr())],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AwSpace.x3),
              // OPH-080: the only door to the Epic 08 calendar vertical.
              const GoogleCalendarCard(),
              const SizedBox(height: AwSpace.x3),
              // OPH-078: the device-side twin — hides itself off Apple platforms.
              const AppleCalendarCard(),
              const SizedBox(height: AwSpace.x3),
              // Destructive action, visually separated from the rest.
              Card(
                child: ListTile(
                  leading: Icon(Icons.logout, color: scheme.error),
                  title: Text(
                    'settings.signOut'.tr(),
                    style: TextStyle(
                      color: scheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  // Router redirect drops the user on /login once state clears.
                  onTap: () =>
                      ref.read(authControllerProvider.notifier).logout(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Feedback round 6: the alarm-permission status row. It reports what the OS
/// will actually let an urgent alarm do — in plain language, worst problem
/// first — and a tap re-runs the permission flow (Android: deep-links to the
/// "Alarms & reminders" special access when that is the missing piece).
class _AlarmStatusTile extends ConsumerStatefulWidget {
  const _AlarmStatusTile();

  @override
  ConsumerState<_AlarmStatusTile> createState() => _AlarmStatusTileState();
}

class _AlarmStatusTileState extends ConsumerState<_AlarmStatusTile> {
  late Future<AlarmSupport> _support;

  @override
  void initState() {
    super.initState();
    _support = _probe();
  }

  Future<AlarmSupport> _probe() async {
    final gateway = ref.read(notificationsGatewayProvider);
    try {
      await gateway.initialize();
      return await gateway.alarmSupport();
    } catch (_) {
      // No notification surface here (web) — nothing to warn about.
      return const AlarmSupport(
        notificationsEnabled: true,
        criticalAlertsEnabled: false,
      );
    }
  }

  Future<void> _request() async {
    final gateway = ref.read(notificationsGatewayProvider);
    try {
      await gateway.requestPermissions();
    } catch (_) {
      // Denials and missing platform surfaces both just re-probe below.
    }
    if (mounted) setState(() => _support = _probe());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AlarmSupport>(
      future: _support,
      builder: (context, snapshot) {
        final support = snapshot.data;
        final subtitle = support == null
            ? 'settings.alarms.checking'.tr()
            : !support.notificationsEnabled
            ? 'settings.alarms.off'.tr()
            : support.exactAlarmsEnabled == false
            ? 'settings.alarms.exact'.tr()
            : support.criticalAlertsEnabled
            ? 'settings.alarms.readyCritical'.tr()
            : 'settings.alarms.ready'.tr();
        final warn =
            support != null &&
            (!support.notificationsEnabled ||
                support.exactAlarmsEnabled == false);
        return ListTile(
          key: const Key('alarm-status'),
          leading: Icon(
            warn ? Icons.alarm_off_outlined : Icons.alarm_on_outlined,
            color: warn ? Theme.of(context).colorScheme.error : null,
          ),
          title: Text('settings.alarms.title'.tr()),
          subtitle: Text(subtitle),
          onTap: _request,
        );
      },
    );
  }
}

/// OPH-121: the language override picker — "System default" (follow the device)
/// plus every shipped locale by its own name (endonym). The current choice
/// carries a check. Picking one persists it and rebuilds the app (AwI18n).
Future<void> showLanguagePicker(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => const _LanguagePickerSheet(),
  );
}

class _LanguagePickerSheet extends ConsumerWidget {
  const _LanguagePickerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final i18n = AwI18n.instance;
    // OPH-126: also push the choice to the account (best-effort) so it can
    // follow the user to another device.
    final syncToAccount = ref.read(accountLocaleSyncProvider);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AwSpace.x4,
              AwSpace.x1,
              AwSpace.x4,
              AwSpace.x2,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'settings.language.title'.tr(),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          _LanguageOption(
            key: const Key('language-system'),
            label: 'settings.language.system'.tr(),
            selected: i18n.followsDevice,
            onTap: () async {
              await i18n.useSystemLocale();
              unawaited(syncToAccount(i18n.locale.languageCode));
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
          for (final locale in awSupportedLocales)
            _LanguageOption(
              key: Key('language-${locale.languageCode}'),
              label:
                  awLanguageEndonyms[locale.languageCode] ??
                  locale.languageCode,
              selected:
                  !i18n.followsDevice &&
                  i18n.locale.languageCode == locale.languageCode,
              onTap: () async {
                await i18n.setLocale(locale);
                unawaited(syncToAccount(locale.languageCode));
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
          const SizedBox(height: AwSpace.x2),
        ],
      ),
    );
  }
}

class _LanguageOption extends StatelessWidget {
  const _LanguageOption({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      title: Text(label),
      trailing: selected ? Icon(Icons.check, color: scheme.primary) : null,
      onTap: onTap,
    );
  }
}
