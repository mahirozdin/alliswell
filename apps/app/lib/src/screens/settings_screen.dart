import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:markdown_forge/markdown_forge.dart';
import '../core/app_version.dart';
import '../core/date_format.dart';
import '../core/persisted_prefs.dart';
import '../features/ai/ui/ai_settings_card.dart';
import '../features/auth/providers.dart';
import '../features/calendar/apple/apple_calendar_card.dart';
import '../features/integrations/ui/google_calendar_card.dart';
import '../features/notes/providers.dart' show noteSourceStylingChoiceProvider;
import '../features/onboarding/tour.dart';
import '../features/settings/account_deletion.dart';
import '../features/settings/account_locale.dart';
import '../features/quick_access/ui/quick_access_bubble.dart';
import '../features/quick_access/ui/quick_access_row.dart';
import '../features/settings/server_url_sheet.dart';
import '../features/ee/providers.dart' show canProvider;
import '../features/ee/team_admin_providers.dart';
import '../features/ee/ui/notification_badge.dart';
import '../features/ee/units_providers.dart';
import '../i18n/i18n.dart';
import '../notifications/alarm_fix_sheet.dart';
import '../notifications/alarm_log.dart';
import '../notifications/gateway.dart';
import '../notifications/providers.dart';
import '../theme/tokens.dart';
import '../widgets/status_views.dart';
import '../features/ee/assignments_providers.dart';

/// Settings, as an index (OPH-260, DESIGN §32).
///
/// It used to be one card of fourteen tiles followed by four loose ones —
/// nineteen rows in a single column, ordered by the epic that added them
/// rather than by what anyone was looking for. Now the root names five places
/// and gets out of the way; every row still exists, with the same key and the
/// same string, one level down (S2's mapping is the proof, and a test counts
/// them so a re-home can never quietly drop one).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider).value;
    final scheme = Theme.of(context).colorScheme;
    return _SettingsPage(
      title: 'settings.title'.tr(),
      children: [
        Card(
          child: Column(
            children: [
              // S1: the account is the one row that is also a destination —
              // it names who you are and opens where that is changed.
              ListTile(
                key: const Key('settings-group-account'),
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
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/settings/account'),
              ),
              const Divider(indent: AwSpace.x4, endIndent: AwSpace.x4),
              // S1: each group says what is inside it, so nobody has to open
              // one to find out.
              _GroupRow(
                keyName: 'settings-group-general',
                icon: Icons.tune_outlined,
                titleKey: 'settings.group.general',
                subtitleKey: 'settings.group.generalSub',
                path: '/settings/general',
              ),
              _GroupRow(
                keyName: 'settings-group-notifications',
                icon: Icons.notifications_active_outlined,
                titleKey: 'settings.group.notifications',
                subtitleKey: 'settings.group.notificationsSub',
                path: '/settings/notifications',
              ),
              _GroupRow(
                keyName: 'settings-group-integrations',
                icon: Icons.hub_outlined,
                titleKey: 'settings.group.integrations',
                subtitleKey: 'settings.group.integrationsSub',
                path: '/settings/integrations',
              ),
              _GroupRow(
                keyName: 'settings-group-data',
                icon: Icons.inventory_2_outlined,
                titleKey: 'settings.group.data',
                subtitleKey: 'settings.group.dataSub',
                path: '/settings/data',
              ),
              // EE-042: present only where there is a team AND the caller
              // runs it. Both halves matter — the entitlement decides whether
              // the capability exists, the role decides whether this person
              // has anything to do there. A member who sees an admin group
              // and meets a 403 behind it has been told a small lie by their
              // own app.
              if (ref.watch(eeTeamAdminProvider))
                _GroupRow(
                  keyName: 'settings-group-team',
                  icon: Icons.groups_outlined,
                  titleKey: 'settings.group.team',
                  subtitleKey: 'settings.group.teamSub',
                  path: '/settings/team',
                ),
              // EE-057: a delegated unit manager is an ordinary member
              // everywhere else, so the Team group above never opens for them
              // — and the units they run would be unreachable. Their own row,
              // shown only when they are NOT an admin: an admin already has
              // the same destination inside the group, and two doors to one
              // room is a list that reads as a mistake.
              if (!ref.watch(eeTeamAdminProvider) &&
                  ref.watch(eeUnitsVisibleProvider))
                _GroupRow(
                  keyName: 'settings-group-units',
                  icon: Icons.apartment_outlined,
                  titleKey: 'settings.group.units',
                  subtitleKey: 'settings.group.unitsSub',
                  path: '/settings/team/units',
                ),
              // EE-087: "my requests". Shown to anyone whose workspace has a
              // roster — asking for something is the least privileged act in
              // the product, and the person most likely to want this list is
              // the one with the fewest other team rows.
              if (ref.watch(workspaceRosterProvider).value?.isNotEmpty ?? false)
                _GroupRow(
                  keyName: 'settings-group-my-tickets',
                  icon: Icons.help_outline,
                  titleKey: 'settings.group.myTickets',
                  subtitleKey: 'settings.group.myTicketsSub',
                  path: '/settings/team/my-tickets',
                ),
              // EE-082: the service catalogue. `services.manage` is a plain
              // role verb, so `canProvider` is honest here — unlike the units
              // row above, which had to ask the server because a delegated
              // manager holds no role that says so.
              //
              // PROVISIONAL PLACEMENT. This is a team-admin screen and it
              // belongs behind the Team group, next to members, invites and
              // roles — except that group's landing page is the settings FORM
              // and has no links onward, so those three screens are reachable
              // only by URL today. Rather than add a fourth unreachable
              // screen, this row is its door until that hub exists; the task
              // that builds it absorbs this row.
              if (ref.watch(canProvider('services.manage')))
                _GroupRow(
                  keyName: 'settings-group-services',
                  icon: Icons.support_agent_outlined,
                  titleKey: 'settings.group.services',
                  subtitleKey: 'settings.group.servicesSub',
                  path: '/settings/team/services',
                ),
              // EE-099: SLA policies, calendars and monitors. Gated on the
              // verb itself — `sla.manage` is a plain role-based permission,
              // so `canProvider` is the honest gate and an admin who lacks it
              // sees no door rather than a forbidden one.
              if (ref.watch(canProvider('sla.manage')))
                _GroupRow(
                  keyName: 'settings-group-sla',
                  icon: Icons.gavel_outlined,
                  titleKey: 'settings.group.sla',
                  subtitleKey: 'settings.group.slaSub',
                  path: '/settings/team/sla',
                ),
              // EE-106: the public request links. Same gate shape as the SLA
              // row above — `portal.manage_links` is a plain role permission,
              // so an admin who lacks it sees no door rather than a forbidden
              // one.
              if (ref.watch(canProvider('portal.manage_links')))
                _GroupRow(
                  keyName: 'settings-group-portal',
                  icon: Icons.add_link,
                  titleKey: 'settings.group.portal',
                  subtitleKey: 'settings.group.portalSub',
                  path: '/settings/team/portal',
                ),
              // EE-111: the team's AI keys and the personal-key policy. Same
              // gate shape as the two rows above — a permission, not an
              // entitlement, so the door is absent rather than forbidden.
              if (ref.watch(canProvider('team.manage_ai_keys')))
                _GroupRow(
                  keyName: 'settings-group-team-ai',
                  icon: Icons.vpn_key_outlined,
                  titleKey: 'settings.group.teamAi',
                  subtitleKey: 'settings.group.teamAiSub',
                  path: '/settings/team/ai-keys',
                ),
              // OPH-287: the team's identity sources. Same gate shape as the
              // rows above — a permission, not an entitlement, so the door is
              // absent rather than forbidden for somebody who cannot use it.
              if (ref.watch(canProvider('team.manage_identity')))
                _GroupRow(
                  keyName: 'settings-group-team-identity',
                  icon: Icons.account_tree_outlined,
                  titleKey: 'settings.group.teamIdentity',
                  subtitleKey: 'settings.group.teamIdentitySub',
                  path: '/settings/team/identity',
                ),
              // OPH-290: the team's own mail relay, gated the same way. Until
              // this existed every team's notifications left through the
              // operator's server; now a team that has not filled this in
              // sends nothing, so the row has to be findable.
              if (ref.watch(canProvider('team.manage_mail')))
                _GroupRow(
                  keyName: 'settings-group-team-mail',
                  icon: Icons.outgoing_mail,
                  titleKey: 'ee.mail.settingsRow',
                  subtitleKey: 'ee.mail.settingsRowHint',
                  path: '/settings/team/mail',
                ),
              // EE-077: the notification centre and its preferences. Gated
              // the same way the assignments row is — by the REPLICA's own
              // roster — so it is right offline and simply absent on a plain
              // build, with no entitlement check to get wrong.
              if (ref.watch(workspaceRosterProvider).value?.isNotEmpty ?? false)
                _GroupRow(
                  keyName: 'settings-group-notifications',
                  icon: Icons.notifications_active_outlined,
                  titleKey: 'settings.group.notifications',
                  subtitleKey: 'settings.group.notificationsSub',
                  path: '/notifications',
                  trailing: const AwNotificationBadge(),
                ),
              // EE-068: "assigned to me". Shown to anyone whose workspace has
              // a roster — being given work is not an admin act, and the
              // person most likely to want this list is the one with the
              // fewest other team rows. The test is the REPLICA's own data,
              // so it is right offline and absent on a plain build.
              if (ref.watch(workspaceRosterProvider).value?.isNotEmpty ?? false)
                _GroupRow(
                  keyName: 'settings-group-assignments',
                  icon: Icons.assignment_ind_outlined,
                  titleKey: 'settings.group.assignments',
                  subtitleKey: 'settings.group.assignmentsSub',
                  path: '/settings/team/assignments',
                ),
              // Kept on the root, and kept a dialog: it is one screenful of
              // facts, not a place with settings in it.
              AboutListTile(
                icon: const Icon(Icons.info_outline),
                applicationName: 'AllisWell',
                // Read from the bundle, not retyped — a hardcoded string here
                // silently lied about the version for three releases.
                applicationVersion: ref.watch(appVersionProvider),
                aboutBoxChildren: [Text('settings.aboutBody'.tr())],
              ),
            ],
          ),
        ),
        const SizedBox(height: AwSpace.x3),
        // S4: the one action people arrive stressed for does not get buried.
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
            onTap: () => ref.read(authControllerProvider.notifier).logout(),
          ),
        ),
      ],
    );
  }
}

/// One row of the index: icon, name, and what it holds.
class _GroupRow extends StatelessWidget {
  const _GroupRow({
    required this.keyName,
    required this.icon,
    required this.titleKey,
    required this.subtitleKey,
    required this.path,
    this.trailing,
  });

  final String keyName;
  final IconData icon;
  final String titleKey;
  final String subtitleKey;
  final String path;

  /// Shown BEFORE the chevron, for a row that carries live state — the unread
  /// badge (EE-077) is the only one so far. The chevron stays: it is what says
  /// "this goes somewhere", and a badge is not a replacement for that.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => ListTile(
    key: Key(keyName),
    leading: Icon(icon),
    title: Text(titleKey.tr()),
    subtitle: Text(subtitleKey.tr()),
    trailing: trailing == null
        ? const Icon(Icons.chevron_right)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [trailing!, const Icon(Icons.chevron_right)],
          ),
    onTap: () => context.push(path),
  );
}

/// The shape every settings surface shares (S6): one readable column, the same
/// paddings, the same card. Extracted so five new pages could not each invent
/// their own.
class _SettingsPage extends StatelessWidget {
  const _SettingsPage({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: awListPadding(context, top: AwSpace.x2),
          children: children,
        ),
      ),
    ),
  );
}

/// Hesap: who you are, which server, and the way out (§32 S2).
class SettingsAccountScreen extends ConsumerWidget {
  const SettingsAccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider).value;
    final scheme = Theme.of(context).colorScheme;
    return _SettingsPage(
      title: 'settings.group.account'.tr(),
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
              // Self-hosting: the address is a setting, not a fact — changing
              // it signs the user out (tokens belong to the server that
              // issued them).
              const ServerUrlTile(),
            ],
          ),
        ),
        const SizedBox(height: AwSpace.x3),
        // Deleting the account must be reachable from inside the app
        // (App Store 5.1.1(v) / Google Play) — and reversible while the grace
        // period lasts.
        const _DeleteAccountCard(),
      ],
    );
  }
}

/// Genel: the choices that shape everyday use (§32 S2).
class SettingsGeneralScreen extends ConsumerWidget {
  const SettingsGeneralScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final format = ref.watch(dateFormatProvider);
    final (hour, minute) = parseTaskTime(ref.watch(defaultTaskTimeProvider));
    final current = TimeOfDay(hour: hour, minute: minute);
    return _SettingsPage(
      title: 'settings.group.general'.tr(),
      children: [
        Card(
          child: Column(
            children: [
              // OPH-121: language override. Following the device shows the
              // "System default" subtitle; an explicit pick shows its endonym.
              // Changing it rebuilds the whole app (app.dart).
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
              // OPH-174 (DESIGN §17): how dates are DISPLAYED. The row and the
              // picker show results, never patterns — nobody should have to
              // read `dd.MM.yyyy` to choose how their app looks.
              ListTile(
                key: const Key('settings-date-format'),
                leading: const Icon(Icons.event_note_outlined),
                title: Text('settings.dateFormat.title'.tr()),
                subtitle: Text(
                  awFormatDateTime(kAwDateFormatSample, format: format),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showDateFormatPicker(context),
              ),
              // OPH-161: where a day-only task lands. One source of truth for
              // quick-add, the FAB prefill and date pickers.
              ListTile(
                key: const Key('settings-default-task-time'),
                leading: const Icon(Icons.schedule_outlined),
                title: Text('settings.defaultTaskTime.title'.tr()),
                subtitle: Text(
                  'settings.defaultTaskTime.sub'.tr(
                    args: {'time': current.format(context)},
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: current,
                  );
                  if (picked == null) return;
                  final value =
                      '${picked.hour.toString().padLeft(2, '0')}:'
                      '${picked.minute.toString().padLeft(2, '0')}';
                  await ref.read(defaultTaskTimeProvider.notifier).set(value);
                },
              ),
              // Round 19 #4: what the note SOURCE editor paints. A display
              // preference like the two above it — the note itself is
              // unaffected, only how the writing surface looks.
              ListTile(
                key: const Key('settings-note-source-styling'),
                leading: const Icon(Icons.edit_note_outlined),
                title: Text('settings.noteSourceStyling.title'.tr()),
                subtitle: Text(
                  'settings.noteSourceStyling.${ref.watch(noteSourceStylingChoiceProvider).name}'
                      .tr(),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showNoteSourceStylingPicker(context),
              ),
              // OPH-200 (DESIGN §23 Q5): the floating shortcut button is
              // optional, and turning it off does not remove the feature — the
              // Home app bar grows a ⚡ entry instead. A gesture is never the
              // only path.
              SwitchListTile(
                key: const Key('quick-bubble-toggle'),
                secondary: const Icon(kQuickAccessIcon),
                title: Text('settings.quickBubble'.tr()),
                subtitle: Text('settings.quickBubbleSub'.tr()),
                value: ref.watch(quickBubbleEnabledProvider),
                onChanged: (_) =>
                    ref.read(quickBubbleEnabledProvider.notifier).toggle(),
              ),
              // OPH-111: replay the first-run tour on demand. Start it, then
              // pop back to the shell where the overlay lives — from here that
              // means all the way out of settings.
              ListTile(
                key: const Key('replay-tour'),
                leading: const Icon(Icons.help_outline),
                title: Text('settings.appTour'.tr()),
                subtitle: Text('settings.appTourSub'.tr()),
                onTap: () {
                  ref.read(tourControllerProvider.notifier).start();
                  context.go('/home');
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Bildirimler & Alarmlar: whether this device can ring, and what it did (§32 S2).
class SettingsNotificationsScreen extends ConsumerWidget {
  const SettingsNotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => _SettingsPage(
    title: 'settings.group.notifications'.tr(),
    children: [
      Card(
        child: Column(
          children: [
            // Feedback round 6: an honest status row for the product's
            // backbone — can the alarm actually ring on this device? Tapping
            // re-runs the permission flow.
            const _AlarmStatusTile(),
            // OPH-064: lock-screen privacy — generic notification content
            // ("Bir hatırlatıcın var") instead of task titles.
            SwitchListTile(
              key: const Key('notification-privacy'),
              secondary: const Icon(Icons.notifications_outlined),
              title: Text('settings.privateNotifications'.tr()),
              subtitle: Text('settings.privateNotificationsSub'.tr()),
              value: ref.watch(notificationPrivacyProvider),
              onChanged: (_) =>
                  ref.read(notificationPrivacyProvider.notifier).toggle(),
            ),
            // OPH-179 (DESIGN §18 N1): one destination for how insistent
            // alarms are — chain, snooze order, and (from OPH-181) the sounds.
            ListTile(
              key: const Key('settings-reminder-system'),
              leading: const Icon(Icons.notifications_active_outlined),
              title: Text('reminderSettings.title'.tr()),
              subtitle: Text('reminderSettings.sub'.tr()),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/reminders'),
            ),
            // OPH-176 (DESIGN §11 A6): what this device DID about alarms.
            // Round 9 was argued from memory; it won't be again.
            ListTile(
              key: const Key('settings-alarm-log'),
              leading: const Icon(Icons.history_outlined),
              title: Text('alarmLog.title'.tr()),
              subtitle: Text('alarmLog.sub'.tr()),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/alarm-log'),
            ),
          ],
        ),
      ),
    ],
  );
}

/// Entegrasyonlar: the things AllisWell talks to (§32 S2).
class SettingsIntegrationsScreen extends StatelessWidget {
  const SettingsIntegrationsScreen({super.key});

  @override
  Widget build(BuildContext context) => _SettingsPage(
    title: 'settings.group.integrations'.tr(),
    children: [
      // OPH-080: the only door to the Epic 08 calendar vertical.
      const GoogleCalendarCard(),
      const SizedBox(height: AwSpace.x3),
      // OPH-078: the device-side twin — hides itself off Apple platforms.
      const AppleCalendarCard(),
      const SizedBox(height: AwSpace.x3),
      // OPH-220: AI — hides itself when the server has AI disabled. The MCP
      // connector card lives inside it and stays there.
      const AiSettingsCard(),
      const SizedBox(height: AwSpace.x3),
      // OPH-265: the space OPH-260 left here, now filled — the door to the
      // keys a person hands to their own scripts (ADR-0032).
      Card(
        child: ListTile(
          key: const Key('settings-api-keys'),
          leading: const Icon(Icons.vpn_key_outlined),
          title: Text('apiKeys.title'.tr()),
          subtitle: Text('apiKeys.sub'.tr()),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/settings/api-keys'),
        ),
      ),
    ],
  );
}

/// Veri: what this device recorded, and the work already done (§32 S2).
class SettingsDataScreen extends StatelessWidget {
  const SettingsDataScreen({super.key});

  @override
  Widget build(BuildContext context) => _SettingsPage(
    title: 'settings.group.data'.tr(),
    children: [
      Card(
        child: Column(
          children: [
            // OPH-186 (DESIGN §20 C4): the archive of finished work. Home
            // keeps today's; everything older lives here.
            ListTile(
              key: const Key('settings-completed'),
              leading: const Icon(Icons.check_circle_outline),
              title: Text('completed.title'.tr()),
              subtitle: Text('completed.sub'.tr()),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/completed'),
            ),
            // OPH-242: what actually reached the app when something was shared
            // to it. Round 17 opened with a report nobody could settle; this
            // is the alarm log's twin for that class of question.
            ListTile(
              key: const Key('settings-share-log'),
              leading: const Icon(Icons.ios_share_outlined),
              title: Text('shareLog.title'.tr()),
              subtitle: Text('shareLog.sub'.tr()),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/share-log'),
            ),
          ],
        ),
      ),
    ],
  );
}

/// Account deletion (App Store 5.1.1(v) / Google Play): the request, the
/// countdown while it is still undoable, and the way out of it.
///
/// The server owns the state — after every action the provider is invalidated
/// and the row re-renders from what the server says, never from a local guess
/// about whether the deletion "probably" went through.
class _DeleteAccountCard extends ConsumerWidget {
  const _DeleteAccountCard();

  Future<void> _request(BuildContext context, WidgetRef ref) async {
    final scheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      // Round 13 #2: dialogs go to the ROOT navigator for the same
      // reason sheets do (OPH-212) — inside a shell branch the
      // Scaffold's own bar and FAB paint over them.
      useRootNavigator: true,
      builder: (context) => AlertDialog(
        title: Text('settings.deleteAccount.title'.tr()),
        content: Text('settings.deleteAccount.confirmBody'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: scheme.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('settings.deleteAccount.confirm'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(accountDeletionApiProvider).requestDeletion();
      ref.invalidate(accountDeletionProvider);
    } on Object {
      messenger.showSnackBar(
        SnackBar(content: Text('settings.deleteAccount.failed'.tr())),
      );
    }
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(accountDeletionApiProvider).cancelDeletion();
      ref.invalidate(accountDeletionProvider);
      messenger.showSnackBar(
        SnackBar(content: Text('settings.deleteAccount.cancelled'.tr())),
      );
    } on Object {
      messenger.showSnackBar(
        SnackBar(content: Text('settings.deleteAccount.failed'.tr())),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final state = ref.watch(accountDeletionProvider);

    // A pending deletion outranks everything: show the deadline and the undo.
    final pending = state.value;
    if (pending != null && pending.isPending) {
      return Card(
        color: scheme.errorContainer,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                Icons.timer_outlined,
                color: scheme.onErrorContainer,
              ),
              title: Text(
                'settings.deleteAccount.pendingTitle'.tr(),
                style: TextStyle(
                  color: scheme.onErrorContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                'settings.deleteAccount.pendingBody'.tr(
                  args: {
                    'date': _formatDeadline(
                      pending.scheduledAt!,
                      ref.watch(dateFormatProvider),
                    ),
                  },
                ),
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AwSpace.x3,
                0,
                AwSpace.x3,
                AwSpace.x3,
              ),
              child: Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => _cancel(context, ref),
                  child: Text('settings.deleteAccount.keepAccount'.tr()),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      child: ListTile(
        leading: Icon(Icons.delete_forever_outlined, color: scheme.error),
        title: Text(
          'settings.deleteAccount.title'.tr(),
          style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600),
        ),
        subtitle: Text('settings.deleteAccount.sub'.tr()),
        // Never block the action on a failed status read — the point of this
        // row is that it always works.
        onTap: state.isLoading ? null : () => _request(context, ref),
      ),
    );
  }

  static String _formatDeadline(DateTime at, String dateFormat) =>
      awFormatDateTime(at, format: dateFormat);
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
  bool _testing = false;

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
        // OPH-277: the cascade is `AlarmSupport.worstProblem` now — one ordered
        // list, shared with the Home banner. This row used to carry its own
        // copy of a two-branch `if` and would have needed five more.
        final problem = support?.worstProblem;
        final subtitle = support == null
            ? 'settings.alarms.checking'.tr()
            : problem != null
            ? 'alarm.problem.${problem.name}'.tr()
            : support.criticalAlertsEnabled
            ? 'settings.alarms.readyCritical'.tr()
            : 'settings.alarms.ready'.tr();
        return Column(
          children: [
            ListTile(
              key: const Key('alarm-status'),
              leading: Icon(
                problem != null
                    ? Icons.alarm_off_outlined
                    : Icons.alarm_on_outlined,
                color: problem != null
                    ? Theme.of(context).colorScheme.error
                    : null,
              ),
              title: Text('settings.alarms.title'.tr()),
              subtitle: Text(subtitle),
              // A healthy row is not a dead affordance: re-running the request
              // is still how Android grants "Alarms & reminders", and a re-probe
              // is a reasonable thing to want.
              onTap: problem == null
                  ? _request
                  : () => showAlarmFixSheet(context, ref, problem),
            ),
            // OPH-277: the thing a report about a silent alarm never had — a way
            // to make it happen on purpose, right now, with the log watching.
            ListTile(
              key: const Key('alarm-test'),
              leading: const Icon(Icons.play_circle_outline),
              title: Text('settings.alarms.test'.tr()),
              subtitle: Text(
                'settings.alarms.testSub'.tr(
                  args: {'seconds': '${kAlarmTestDelay.inSeconds}'},
                ),
              ),
              onTap: _testing ? null : _runTest,
            ),
          ],
        );
      },
    );
  }

  Future<void> _runTest() async {
    setState(() => _testing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final delivery = await ref
          .read(notificationsGatewayProvider)
          .scheduleTestAlarm(
            title: 'settings.alarms.testTitle'.tr(),
            body: 'settings.alarms.testBody'.tr(),
            after: kAlarmTestDelay,
            soundName:
                (await ref
                        .read(alarmSoundResolverProvider)
                        .resolve(ref.read(alarmSoundChoiceProvider)))
                    .name,
          );
      await ref
          .read(alarmLogProvider)
          .record(
            event: AlarmLogEvent.test,
            lane: AlarmLogLane.notification,
            urgent: true,
            sound: delivery.sound,
            level: delivery.level,
            fireAt: DateTime.now().toUtc().add(kAlarmTestDelay),
            detail: 'user-requested rehearsal',
          );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'settings.alarms.testArmed'.tr(
              args: {'seconds': '${kAlarmTestDelay.inSeconds}'},
            ),
          ),
        ),
      );
    } on Object catch (error) {
      // The failure IS the diagnosis — saying "armed" here would be the lie
      // this whole round is about.
      await ref
          .read(alarmLogProvider)
          .record(
            event: AlarmLogEvent.degraded,
            lane: AlarmLogLane.notification,
            detail: 'test alarm failed: $error',
          );
      messenger.showSnackBar(
        SnackBar(content: Text('settings.alarms.testFailed'.tr())),
      );
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }
}

/// OPH-174 (DESIGN §17 D2): the date-format picker. Every row is the SAME sample
/// instant rendered in that option, because a result is what the user is
/// choosing — a pattern like `dd.MM.yyyy` is a technical concept and those never
/// reach end-user UI (round 1's rule, the same one that banned hex codes).
Future<void> showDateFormatPicker(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    // OPH-212: the ROOT navigator. Pushed into a shell branch, a sheet
    // renders UNDER the shell's own glass bar and FAB — they are painted by
    // the Scaffold that owns the branch, above its body.
    useRootNavigator: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (context) => const _DateFormatPickerSheet(),
  );
}

class _DateFormatPickerSheet extends ConsumerWidget {
  const _DateFormatPickerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(dateFormatProvider);
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
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
                'settings.dateFormat.title'.tr(),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          for (final spec in kAwDateFormats)
            ListTile(
              key: Key('date-format-${spec.id}'),
              // The result IS the label; the system option says what it follows
              // (otherwise, in Turkish, it would look like a duplicate row).
              title: Text(
                awFormatDateTime(kAwDateFormatSample, format: spec.id),
              ),
              subtitle: spec.id == kAwSystemDateFormat
                  ? Text('settings.dateFormat.system'.tr())
                  : null,
              trailing: spec.id == current ? const Icon(Icons.check) : null,
              onTap: () async {
                await ref.read(dateFormatProvider.notifier).set(spec.id);
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
        ],
      ),
    );
  }
}

/// Round 19 #4: the source-editor styling picker.
///
/// Every row renders the SAME markdown line in the style it names, for the
/// reason the date-format picker shows dates rather than patterns: a person is
/// choosing a result, and "markersOnly" is a technical concept that must never
/// reach the end user by itself.
Future<void> showNoteSourceStylingPicker(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (context) => const _NoteSourceStylingSheet(),
  );
}

/// One line with a bit of everything the report was about: a heading marker,
/// a bold run and a highlight. Not localized — it is markdown SOURCE, and the
/// point is to see the `#`/`**`/`==` characters themselves.
const String _kSourceStylingSample = '# Başlık **kalın** ==vurgu==';

class _NoteSourceStylingSheet extends ConsumerWidget {
  const _NoteSourceStylingSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(noteSourceStylingChoiceProvider);
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
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
                'settings.noteSourceStyling.title'.tr(),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          for (final styling in MdSyntaxStyling.values)
            ListTile(
              key: Key('note-source-styling-${styling.name}'),
              title: _SourceStylingSample(styling: styling),
              subtitle: Text('settings.noteSourceStyling.${styling.name}'.tr()),
              trailing: styling == current ? const Icon(Icons.check) : null,
              onTap: () async {
                await ref
                    .read(noteSourceStylingProvider.notifier)
                    .set(styling.name);
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
        ],
      ),
    );
  }
}

/// The sample, painted by the REAL controller rather than a hand-made
/// imitation — a preview that can disagree with the editor is worse than none.
class _SourceStylingSample extends StatefulWidget {
  const _SourceStylingSample({required this.styling});

  final MdSyntaxStyling styling;

  @override
  State<_SourceStylingSample> createState() => _SourceStylingSampleState();
}

class _SourceStylingSampleState extends State<_SourceStylingSample> {
  late final MdSourceController _controller =
      MdSourceController(text: _kSourceStylingSample)
        ..styling = widget.styling
        ..selection = const TextSelection.collapsed(offset: -1);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).textTheme.bodyLarge!;
    return Text.rich(
      _controller.buildTextSpan(
        context: context,
        style: base,
        withComposing: false,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// OPH-121: the language override picker — "System default" (follow the device)
/// plus every shipped locale by its own name (endonym). The current choice
/// carries a check. Picking one persists it and rebuilds the app (AwI18n).
Future<void> showLanguagePicker(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    // OPH-212: the ROOT navigator. Pushed into a shell branch, a sheet
    // renders UNDER the shell's own glass bar and FAB — they are painted by
    // the Scaffold that owns the branch, above its body.
    useRootNavigator: true,
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
