import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/data/team_admin_api.dart';
import 'package:alliswell/src/features/ee/data/team_admin_models.dart';
import 'package:alliswell/src/features/ee/team_admin_providers.dart';
import 'package:alliswell/src/features/ee/ui/team_roles_screen.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';
import 'package:alliswell/src/features/ee/providers.dart';

/// EE-053 — the role list and its grant matrix.
///
/// What is pinned here is what a redesign would quietly lose: `owner` is
/// visible and closed rather than hidden, a role says how many people it
/// affects before anyone narrows it, deleting one explains where its holders
/// land, and the matrix sends FULL grant sets (the server owns the
/// translation into deltas — a client that computed them would be a second
/// implementation of a rule it cannot see).

const _catalogue = [
  EePermissionDef(
    id: 'tasks.view',
    label: 'ee.perm.tasks.view',
    description: 'See tasks',
    defaultGrants: ['owner', 'admin', 'member'],
  ),
  EePermissionDef(
    id: 'tasks.create',
    label: 'ee.perm.tasks.create',
    description: 'Create tasks',
    defaultGrants: ['owner', 'admin', 'member'],
  ),
  EePermissionDef(
    id: 'notes.view',
    label: 'ee.perm.notes.view',
    description: 'See notes',
    defaultGrants: ['owner', 'admin', 'member'],
  ),
];

class FakeRolesApi implements EeTeamAdminApi {
  FakeRolesApi({List<EeRole>? roles})
    : _roles =
          roles ??
          [
            const EeRole(
              key: 'owner',
              name: 'owner',
              base: true,
              anchor: 'owner',
              editable: false,
              grants: ['tasks.view', 'tasks.create', 'notes.view'],
              memberCount: 1,
            ),
            const EeRole(
              key: 'member',
              name: 'member',
              base: true,
              anchor: 'member',
              editable: true,
              grants: ['tasks.view'],
              memberCount: 4,
            ),
            const EeRole(
              key: '01ROLE0000000000000000000A',
              name: 'Destek Uzmanı',
              base: false,
              anchor: 'member',
              editable: true,
              grants: ['tasks.view', 'notes.view'],
              memberCount: 2,
            ),
          ];

  List<EeRole> _roles;
  final List<String> calls = [];

  @override
  Future<List<EeRole>> roles() async => _roles;

  @override
  Future<List<EePermissionDef>> catalogue() async => _catalogue;

  @override
  Future<void> createRole({
    required String name,
    required String anchor,
    required List<String> grants,
  }) async {
    calls.add('create:$name:$anchor:${grants.join(",")}');
  }

  @override
  Future<void> updateRole({
    required String roleKey,
    String? name,
    List<String>? grants,
  }) async {
    calls.add('update:$roleKey:${name ?? "-"}:${grants?.join(",") ?? "-"}');
  }

  @override
  Future<void> deleteRole(String roleKey) async {
    calls.add('delete:$roleKey');
    _roles = _roles.where((r) => r.key != roleKey).toList();
  }

  // ── Not under test here ──────────────────────────────────────────────────
  @override
  Future<EeTeamInfo?> info() async => null;
  @override
  Future<EeTeamRoster> members() async =>
      const EeTeamRoster(members: [], seats: EeSeats(used: 0));
  @override
  Future<void> setRole({
    required String userId,
    required String role,
    String? customRoleId,
    bool clearCustomRole = false,
  }) async => calls.add('setRole:$userId:$role:${customRoleId ?? "-"}');
  @override
  Future<void> deactivate(String userId) async {}
  @override
  Future<void> reactivate(String userId) async {}
  @override
  Future<void> remove(String userId) async {}
  @override
  Future<List<EeInvite>> invites() async => const [];
  @override
  Future<EeMintedInvite> invite({
    required String email,
    String role = 'member',
  }) async => throw UnimplementedError();
  @override
  Future<void> revokeInvite(String inviteId) async {}
}

Widget harness(FakeRolesApi api) => ProviderScope(
  overrides: [
    eeTeamAdminApiProvider.overrideWithValue(api),
    // OPH-356: the "+" waits for a yes; this file is about an admin.
    canProvider.overrideWith((ref, id) => true),
  ],
  child: MaterialApp(
    theme: buildAwTheme(Brightness.light),
    home: const EeTeamRolesScreen(),
  ),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('en'));
  });

  testWidgets('every role is listed, with what it costs to change it', (
    tester,
  ) async {
    await tester.pumpWidget(harness(FakeRolesApi()));
    await tester.pumpAndSettle();

    // A base role's name is translated; a custom role's is what somebody
    // typed, and translating THAT would be translating data.
    expect(find.text('Member'), findsOneWidget);
    expect(find.text('Destek Uzmanı'), findsOneWidget);
    // "Can I narrow this?" is unanswerable without knowing who it hits.
    expect(find.text('1 permissions · 4 members'), findsOneWidget);
    expect(find.text('2 permissions · 2 members'), findsOneWidget);
  });

  testWidgets('owner is present and closed, not hidden', (tester) async {
    await tester.pumpWidget(harness(FakeRolesApi()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('role-owner')), findsOneWidget);
    expect(find.text('Always everything'), findsOneWidget);

    // Tapping it does nothing — there is no editor behind a role a team
    // cannot edit, and offering one would be a lie.
    await tester.tap(find.byKey(const Key('role-owner')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('role-save')), findsNothing);
  });

  testWidgets('the matrix sends a FULL grant set, not a diff', (tester) async {
    final api = FakeRolesApi();
    await tester.pumpWidget(harness(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('role-01ROLE0000000000000000000A')));
    await tester.pumpAndSettle();

    // It opens ticked with what the role effectively has.
    Checkbox box(String id) => tester.widget<Checkbox>(
      find.descendant(
        of: find.byKey(Key('grant-$id')),
        matching: find.byType(Checkbox),
      ),
    );
    expect(box('tasks.view').value, isTrue);
    expect(box('notes.view').value, isTrue);
    expect(box('tasks.create').value, isFalse);

    await tester.tap(find.byKey(const Key('grant-tasks.create')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('role-save')));
    await tester.pumpAndSettle();

    expect(
      api.calls,
      contains(
        'update:01ROLE0000000000000000000A:Destek Uzmanı:'
        'notes.view,tasks.create,tasks.view',
      ),
    );
  });

  testWidgets('a base role can be narrowed but not renamed', (tester) async {
    final api = FakeRolesApi();
    await tester.pumpWidget(harness(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('role-member')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('role-name')), findsNothing);
    expect(find.byKey(const Key('role-delete')), findsNothing);
    await tester.tap(find.byKey(const Key('grant-notes.view')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('role-save')));
    await tester.pumpAndSettle();

    expect(api.calls, contains('update:member:-:notes.view,tasks.view'));
  });

  testWidgets('deleting a role says where its people land', (tester) async {
    final api = FakeRolesApi();
    await tester.pumpWidget(harness(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('role-01ROLE0000000000000000000A')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('role-delete')));
    await tester.pumpAndSettle();

    // Nobody is locked out — the sentence says so before the tap that does it.
    expect(
      find.text(
        '2 people hold it. They keep their place in the team and fall back '
        'to Member.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(api.calls, contains('delete:01ROLE0000000000000000000A'));
  });

  testWidgets('a new role starts empty and carries its anchor', (tester) async {
    final api = FakeRolesApi();
    await tester.pumpWidget(harness(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('role-new')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('role-name')), 'Nöbetçi');
    await tester.tap(find.byKey(const Key('grant-tasks.view')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('role-save')));
    await tester.pumpAndSettle();

    expect(api.calls, contains('create:Nöbetçi:member:tasks.view'));
  });

  testWidgets(
    'UI-AUDIT #45: permission descriptions are in Turkish under a Turkish UI',
    (tester) async {
      AwI18n.instance.setActiveCached(const Locale('tr'));
      final api = FakeRolesApi();
      await tester.pumpWidget(harness(api));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('role-new')));
      await tester.pumpAndSettle();
      expect(find.text('Görevleri gör'), findsWidgets);
      expect(find.text('See tasks'), findsNothing);
      expect(find.text('Create tasks'), findsNothing);
    },
  );

  test(
    'UI-AUDIT #45: a verb this build has no words for keeps the server text',
    () {
      AwI18n.instance.setActiveCached(const Locale('tr'));
      expect(
        eePermissionDescription(
          const EePermissionDef(
            id: 'future.verb',
            label: 'ee.perm.future.verb',
            description: 'Something new',
          ),
        ),
        'Something new',
      );
    },
  );

  test(
    'UI-AUDIT #45: every catalogue verb has a description in both languages',
    () {
      // The server's catalogue (EE `GET /ee/permissions`), 71 verbs on 2026-10-07.
      const ids = [
        'absences.manage',
        'alarms.create_urgent',
        'announcements.manage',
        'approvals.decide',
        'assets.manage',
        'assets.view',
        'calendar.manage',
        'calendar.view',
        'changes.create',
        'changes.edit',
        'changes.implement',
        'customers.manage',
        'files.delete',
        'files.edit',
        'files.upload',
        'files.view',
        'kb.publish',
        'kb.write',
        'notes.create',
        'notes.delete',
        'notes.edit',
        'notes.view',
        'oncall.manage',
        'portal.manage_links',
        'problems.manage',
        'projects.archive',
        'projects.create',
        'projects.edit',
        'projects.view',
        'services.manage',
        'shares.create',
        'shares.revoke',
        'sla.manage',
        'suppliers.manage',
        'tasks.assign',
        'tasks.complete',
        'tasks.create',
        'tasks.delete',
        'tasks.edit',
        'tasks.view',
        'team.export_data',
        'team.force_logout',
        'team.import_members',
        'team.import_tickets',
        'team.manage_ai_keys',
        'team.manage_deliveries',
        'team.manage_identity',
        'team.manage_invites',
        'team.manage_mail',
        'team.manage_members',
        'team.manage_roles',
        'team.manage_security',
        'team.manage_settings',
        'team.view_audit',
        'team.workspace.archive',
        'team.workspace.create',
        'team.workspace.view',
        'tickets.assign',
        'tickets.close',
        'tickets.comment',
        'tickets.convert',
        'tickets.create',
        'tickets.create_on_behalf',
        'tickets.export',
        'tickets.link',
        'tickets.manage_worklog',
        'tickets.override_priority',
        'tickets.pause_sla',
        'units.manage',
        'units.manage_members',
        'webhooks.manage',
      ];
      expect(ids, hasLength(71));
      for (final locale in const [Locale('en'), Locale('tr')]) {
        AwI18n.instance.setActiveCached(locale);
        for (final id in ids) {
          expect(
            AwI18n.instance.maybeTranslate('ee.permDescription.$id'),
            isNotNull,
            reason: '$id in ${locale.languageCode}',
          );
        }
      }
    },
  );
}
