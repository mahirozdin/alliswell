import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/providers.dart';
import '../features/integrations/ui/google_calendar_card.dart';
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
      appBar: AppBar(title: const Text('Settings')),
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
                      title: Text(session?.user.displayName ?? 'Account'),
                      subtitle: Text(session?.user.email ?? 'Not signed in'),
                    ),
                    const Divider(indent: AwSpace.x4, endIndent: AwSpace.x4),
                    ListTile(
                      leading: const Icon(Icons.dns_outlined),
                      title: const Text('Server'),
                      subtitle: Text(ref.watch(apiBaseUrlProvider)),
                    ),
                    // OPH-064: lock-screen privacy — generic notification
                    // content ("Bir hatırlatıcın var") instead of task titles.
                    SwitchListTile(
                      key: const Key('notification-privacy'),
                      secondary: const Icon(Icons.notifications_outlined),
                      title: const Text('Private notifications'),
                      subtitle: const Text(
                        'Hide task titles in reminders and alarms',
                      ),
                      value: ref.watch(notificationPrivacyProvider),
                      onChanged: (_) => ref
                          .read(notificationPrivacyProvider.notifier)
                          .toggle(),
                    ),
                    const AboutListTile(
                      icon: Icon(Icons.info_outline),
                      applicationName: 'AllisWell',
                      applicationVersion: '0.1.0',
                      aboutBoxChildren: [
                        Text(
                          'Open-source, self-hosted productivity hub — '
                          'tasks, projects, notes, calendar and reminders.',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AwSpace.x3),
              // OPH-080: the only door to the Epic 08 calendar vertical.
              const GoogleCalendarCard(),
              const SizedBox(height: AwSpace.x3),
              // Destructive action, visually separated from the rest.
              Card(
                child: ListTile(
                  leading: Icon(Icons.logout, color: scheme.error),
                  title: Text(
                    'Sign out',
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
