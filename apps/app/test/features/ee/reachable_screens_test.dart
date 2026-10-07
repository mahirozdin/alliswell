import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderScope;
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/core/server_url.dart' show kServerUrlPrefKey;
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/ee/assignments_providers.dart';
import 'package:alliswell/src/features/ee/data/meeting_models.dart';
import 'package:alliswell/src/features/ee/data/team_admin_models.dart';
import 'package:alliswell/src/features/ee/meetings_providers.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/team_admin_providers.dart';
import 'package:alliswell/src/features/ee/ui/audit_log_screen.dart';
import 'package:alliswell/src/features/ee/ui/meeting_screen.dart';
import 'package:alliswell/src/features/ee/ui/meetings_screen.dart';
import 'package:alliswell/src/features/ee/ui/notification_center_screen.dart';
import 'package:alliswell/src/features/ee/ui/notification_prefs_screen.dart';
import 'package:alliswell/src/sync/db/database.dart';

import '../projects/fake_api.dart';
import '../settings/settings_groups_test.dart'
    show app, openGroup, openSettings;

/// AW-E26 / EE-271 — three screens nothing led to, and the doors that do now.
///
/// DESIGN §22's rule in its plainest form: a screen nobody can reach by
/// touching the app is not a feature. Measured on 2026-09-24: the meeting
/// screen had a route and no link, the notification preferences had a route
/// and a guide paragraph pointing at it and no link, and the audit log had
/// neither a link nor a route — only its test imported it. Each path here is
/// walked in the real app from the settings root, by tapping.
///
/// And the other half of the same rule (EE-282, EE-290): a door must not lead
/// nowhere. On a plain instance the settings root drew eight team-admin rows
/// onto screens whose endpoints answer 404, because the permission gate says
/// "yes" to a workspace nothing governs — and on a LICENSED instance it kept
/// drawing them for somebody with only a personal workspace, which is what
/// the owner saw on the hosted service. The administration rows now belong to
/// the team's owner and admins alone; the tests at the end pin all of it.
const _me = MemberProfile(
  id: 'MP1',
  workspaceId: 'W1',
  userId: 'U1',
  displayName: 'Ayşe',
  colorRgb: '#2563EB',
  revision: 1,
);

/// The team's administration, as the settings root lists it (EE-290).
const _adminRows = [
  'settings-group-services',
  'settings-group-sla',
  'settings-group-portal',
  'settings-group-team-ai',
  'settings-group-team-identity',
  'settings-group-team-mail',
  'settings-group-team-webhooks',
  'settings-group-team-audit',
];

/// EE-294: Approvals is not a Settings row for anybody any more — it is in
/// the navigation (`approvals_entry_test.dart`). EE-296: nor is "assigned to
/// me" — a member's Home is their work.
const _gone = ['settings-group-team-approvals', 'settings-group-assignments'];

/// What anybody in a team may open: asking, being away, being told.
const _memberRows = [
  'settings-group-my-tickets',
  'settings-group-absences',
  'settings-group-team-notifications',
];

EeTeamInfo _team(String role) => EeTeamInfo(
  id: 'T1',
  name: 'Acme',
  slug: 'acme',
  status: 'active',
  myRole: role,
);

void main() {
  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(1280, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// Somebody in a team, on an instance that has teams and meetings.
  List<Override> inTeam({
    Set<String> features = const {'teams', 'meetings'},
  }) => [
    workspaceRosterProvider.overrideWith((ref) => Stream.value(const [_me])),
    eeFeatureProvider.overrideWith((ref, name) => features.contains(name)),
  ];

  /// …who is that team's owner or admin — the one answer `/ee/team` gives
  /// that the administration rows are drawn for (EE-290).
  List<Override> asAdmin({
    Set<String> features = const {'teams', 'meetings', 'directory'},
  }) => [
    ...inTeam(features: features),
    eeTeamProvider.overrideWith((ref) async => _team('admin')),
  ];

  Finder key(String k) => find.byKey(Key(k));

  testWidgets('AW-E26: meetings — Settings opens the unit\'s list, and the '
      'list opens a meeting', (tester) async {
    tall(tester);
    await tester.pumpWidget(
      await app(
        FakeApi(),
        extra: [
          ...inTeam(),
          eeMeetingListProvider.overrideWith(
            (ref, workspaceId) async => [
              EeMeetingSummary(
                id: 'M1',
                workspaceId: workspaceId,
                status: EeMeetingStatus.ready,
                attempts: 1,
                decisionCount: 3,
                ideaCount: 2,
                createdAt: DateTime(2026, 9, 24, 10),
                title: 'Vardiya devri',
              ),
            ],
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await openSettings(tester);
    await openGroup(tester, 'settings-group-meetings');
    expect(find.byType(EeMeetingsScreen), findsOneWidget);
    expect(find.text('Vardiya devri'), findsOneWidget);

    await tester.tap(key('meeting-M1'));
    await tester.pumpAndSettle();
    expect(find.byType(EeMeetingScreen), findsOneWidget);
  });

  testWidgets('AW-E26: notification preferences — from the centre\'s bar, '
      'and from Settings › Notifications', (tester) async {
    tall(tester);
    await tester.pumpWidget(await app(FakeApi(), extra: inTeam()));
    await tester.pumpAndSettle();
    await openSettings(tester);

    // Two rows, two places, two names. They used to share one key and one
    // title, so a person saw "Notifications" twice and a test could not say
    // which one it meant.
    expect(key('settings-group-notifications'), findsOneWidget);
    expect(key('settings-group-team-notifications'), findsOneWidget);

    await openGroup(tester, 'settings-group-team-notifications');
    expect(find.byType(EeNotificationCenterScreen), findsOneWidget);
    await tester.tap(key('notif-open-prefs'));
    await tester.pumpAndSettle();
    expect(find.byType(EeNotificationPrefsScreen), findsOneWidget);

    // Back to the root, and in through the device's own notification page —
    // where somebody looking for "notification settings" looks first.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await openGroup(tester, 'settings-group-notifications');
    await tester.tap(key('settings-team-notification-prefs'));
    await tester.pumpAndSettle();
    expect(find.byType(EeNotificationPrefsScreen), findsOneWidget);
  });

  testWidgets('AW-E26: the audit log — Settings opens it for an admin who '
      'holds team.view_audit', (tester) async {
    tall(tester);
    final api = FakeApi()
      ..eeGoverned = true
      ..eePermissions = ['team.view_audit'];
    await tester.pumpWidget(await app(api, extra: asAdmin()));
    await tester.pumpAndSettle();
    await openSettings(tester);
    // An admin whose role was trimmed draws the one row its verb opens.
    expect(key('settings-group-services'), findsNothing);
    await openGroup(tester, 'settings-group-team-audit');
    expect(find.byType(EeAuditLogScreen), findsOneWidget);
  });

  testWidgets('AW-E26: without team.view_audit there is no door to the audit '
      'log', (tester) async {
    tall(tester);
    final api = FakeApi()
      ..eeGoverned = true
      ..eePermissions = ['services.manage'];
    await tester.pumpWidget(await app(api, extra: asAdmin()));
    await tester.pumpAndSettle();
    await openSettings(tester);
    expect(key('settings-group-team-audit'), findsNothing);
    expect(key('settings-group-services'), findsOneWidget);
  });

  testWidgets('EE-282: a plain instance draws none of the team rows', (
    tester,
  ) async {
    tall(tester);
    // No overrides: a CE server — no entitlement, no roster, and a
    // permission answer of "ungoverned", which says yes to everything.
    await tester.pumpWidget(await app(FakeApi()));
    await tester.pumpAndSettle();
    await openSettings(tester);
    for (final row in [
      'settings-group-services',
      'settings-group-sla',
      'settings-group-portal',
      'settings-group-team-ai',
      'settings-group-team-identity',
      'settings-group-team-mail',
      'settings-group-team-webhooks',
      ..._gone,
      'settings-group-team-audit',
      'settings-group-team-notifications',
      'settings-group-meetings',
    ]) {
      expect(key(row), findsNothing, reason: '$row leads nowhere on CE');
    }
    // The device's own groups are untouched.
    expect(key('settings-group-notifications'), findsOneWidget);
    expect(key('settings-group-general'), findsOneWidget);
  });

  testWidgets('EE-290: on a licensed instance, somebody with only a personal '
      'workspace sees Settings as the core app draws it', (tester) async {
    tall(tester);
    // The owner's report, reproduced with nothing overridden: the instance is
    // licensed for everything, the only workspace is the person's own (the
    // fake's `/me` is one `owner` row, and its permission answer is
    // "ungoverned"), and `/ee/team` answers 404 — as it does on the service's
    // own address. Every one of these rows used to be drawn.
    final api = FakeApi()
      ..eeState = 'active'
      ..eeFeatures = ['teams', 'itsm', 'directory', 'meetings'];
    await tester.pumpWidget(await app(api));
    await tester.pumpAndSettle();
    await openSettings(tester);
    for (final row in [..._adminRows, ..._memberRows, 'settings-group-team']) {
      expect(key(row), findsNothing, reason: '$row is a team\'s, not theirs');
    }
    for (final row in [
      'settings-group-general',
      'settings-group-notifications',
      'settings-group-integrations',
      'settings-group-developer',
      'settings-group-data',
    ]) {
      expect(key(row), findsOneWidget, reason: '$row is theirs');
    }
  });

  testWidgets('EE-290: a member of the team sees their own rows and none of '
      'its administration', (tester) async {
    tall(tester);
    // A member whose personal workspace is the one the permission question
    // is asked about — "ungoverned", which says yes to every verb. That is
    // exactly how a member used to be handed the admin's rows.
    await tester.pumpWidget(
      await app(
        FakeApi(),
        extra: [
          ...inTeam(),
          eeTeamProvider.overrideWith((ref) async => _team('member')),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await openSettings(tester);
    for (final row in _adminRows) {
      expect(key(row), findsNothing, reason: '$row is the admin\'s');
    }
    for (final row in _memberRows) {
      expect(key(row), findsOneWidget, reason: '$row is any member\'s');
    }
  });

  for (final role in ['admin', 'owner']) {
    testWidgets('EE-290: the team\'s $role gets its administration', (
      tester,
    ) async {
      tall(tester);
      await tester.pumpWidget(
        await app(
          FakeApi(),
          extra: [
            ...inTeam(features: {'teams', 'meetings', 'directory'}),
            eeTeamProvider.overrideWith((ref) async => _team(role)),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await openSettings(tester);
      for (final row in _adminRows) {
        expect(key(row), findsOneWidget, reason: '$row for the $role');
      }
      for (final row in _gone) {
        expect(key(row), findsNothing, reason: '$row lives in the navigation');
      }
    });
  }

  testWidgets('EE-290: identity sources need the directory license too', (
    tester,
  ) async {
    tall(tester);
    await tester.pumpWidget(
      await app(FakeApi(), extra: asAdmin(features: {'teams', 'meetings'})),
    );
    await tester.pumpAndSettle();
    await openSettings(tester);
    expect(key('settings-group-team-identity'), findsNothing);
    expect(key('settings-group-team-mail'), findsOneWidget);
  });

  // UI-AUDIT #7 (OPH-356): signed in on the service's own address, a team
  // member's rows opened screens that could only answer 404 — "you have not
  // asked for anything", "you may not". One row now says where the team is.
  FakeApi onApex({Map<String, dynamic>? myTeam}) => FakeApi()
    ..eeState = 'active'
    ..eeFeatures = ['teams', 'itsm', 'meetings']
    ..eeBaseDomain = 'example.com'
    ..eeMyTeam = myTeam;

  testWidgets('UI-AUDIT #7: off the team\'s address, the team rows give way '
      'to one that names the address — and switches to it', (tester) async {
    tall(tester);
    // The switch persists the address; the next test starts on the default.
    addTearDown(() => localKv.remove(kServerUrlPrefKey));
    final api = onApex(
      myTeam: {
        'slug': 'acme',
        'name': 'Demir Çelik Fabrikası',
        'color': '#16A34A',
        'origin': 'https://acme.example.com',
      },
    );
    await tester.pumpWidget(
      await app(
        api,
        extra: [
          workspaceRosterProvider.overrideWith(
            (ref) => Stream.value(const [_me]),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await openSettings(tester);

    expect(key('settings-team-address-required'), findsOneWidget);
    expect(
      find.text('Demir Çelik Fabrikası is at acme.example.com — tap to switch'),
      findsOneWidget,
    );
    for (final row in _memberRows) {
      expect(key(row), findsNothing, reason: '$row would only answer 404');
    }
    expect(key('settings-group-meetings'), findsNothing);

    final container = ProviderScope.containerOf(
      tester.element(find.byKey(const Key('settings-team-address-required'))),
    );
    await tester.tap(key('settings-team-address-required'));
    await tester.pumpAndSettle();
    expect(container.read(apiBaseUrlProvider), 'https://acme.example.com');
    // Home, where a person on their team's address starts.
    expect(
      find.byKey(const Key('settings-team-address-required')),
      findsNothing,
    );
    // Same session, same person — a team host is the same instance.
    expect(container.read(authControllerProvider).value, isNotNull);
  });

  testWidgets('UI-AUDIT #7: with no hint from the server, the replica\'s team '
      'roster is enough to say it — never the 404s behind the rows', (
    tester,
  ) async {
    tall(tester);
    await tester.pumpWidget(
      await app(
        onApex(),
        extra: [
          workspaceRosterProvider.overrideWith(
            (ref) => Stream.value(const [_me]),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await openSettings(tester);
    expect(key('settings-team-address-required'), findsOneWidget);
    expect(
      find.text('Team screens open on your team\'s own address'),
      findsOneWidget,
    );
    for (final row in _memberRows) {
      expect(key(row), findsNothing);
    }
  });

  testWidgets('UI-AUDIT #7: somebody in no team on a licensed instance is '
      'told nothing about team addresses', (tester) async {
    tall(tester);
    await tester.pumpWidget(await app(onApex()));
    await tester.pumpAndSettle();
    await openSettings(tester);
    expect(key('settings-team-address-required'), findsNothing);
  });
}
