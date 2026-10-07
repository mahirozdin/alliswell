import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/ee/data/ee_models.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/router.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/sync_overrides.dart';

/// EE-052 — the gates as a person meets them.
///
/// Two shapes, and the difference between them is the point:
///
///   • a CREATE affordance is HIDDEN. A greyed-out "+" asks "why can't I?"
///     every time the screen is drawn; an absent one reads as "not your job
///     here".
///   • a control that acts on something already on screen is DISABLED, with
///     a reason. The urgent-alarm switch is a property of the task in front
///     of you — hiding it would make the setting look like it does not exist.
///
/// And the case that must never regress: a plain build shows everything.
const _cacheKey =
    'alliswell_ee_permissions::user-1::01WSAAAAAAAAAAAAAAAAAAAAAA';

Future<Widget> signedInApp(FakeApi api) async {
  SharedPreferences.setMockInitialValues({});
  final store = InMemorySecretStore();
  await TokenStorage(store).save(fakeSession());
  return ProviderScope(
    retry: awRetry,
    overrides: [
      ...syncTestOverrides(),
      secretStoreProvider.overrideWithValue(store),
      apiClientProvider.overrideWithValue(
        fakeDio(FakeHttpClientAdapter(api.handle)),
      ),
    ],
    child: const AllisWellApp(),
  );
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await localKv.remove(_cacheKey);
  });

  testWidgets('a plain build keeps every create button', (tester) async {
    final api = FakeApi();
    await tester.pumpWidget(await signedInApp(api));
    await tester.pumpAndSettle();

    expect(find.byType(FloatingActionButton), findsWidgets);
    expect(find.byTooltip('New task with options'), findsOneWidget);
  });

  testWidgets('a role without tasks.create is not shown the + at all', (
    tester,
  ) async {
    final api = FakeApi()
      ..eeGoverned = true
      ..eePermissions = ['tasks.view', 'tasks.complete'];
    await tester.pumpWidget(await signedInApp(api));
    await tester.pumpAndSettle();

    expect(find.byTooltip('New task with options'), findsNothing);
  });

  testWidgets('the urgent-alarm switch stays visible and goes dead', (
    tester,
  ) async {
    // The other shape of gate: this control acts on the task in front of you,
    // so it is disabled with a reason rather than hidden.
    final api = FakeApi()
      ..eeGoverned = true
      ..eePermissions = ['tasks.view', 'tasks.create'];
    await tester.pumpWidget(await signedInApp(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('New task with options'));
    await tester.pumpAndSettle();

    final urgent = tester.widget<SwitchListTile>(
      find.byKey(const Key('task-sheet-urgent')),
    );
    expect(urgent.onChanged, isNull, reason: 'the switch must be dead');
    expect(find.text('Your role cannot raise urgent alarms'), findsOneWidget);
  });

  testWidgets('a plain build leaves the urgent switch alive', (tester) async {
    final api = FakeApi();
    await tester.pumpWidget(await signedInApp(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('New task with options'));
    await tester.pumpAndSettle();

    final urgent = tester.widget<SwitchListTile>(
      find.byKey(const Key('task-sheet-urgent')),
    );
    expect(urgent.onChanged, isNotNull);
  });

  // UI-AUDIT #61 (OPH-356): a member who opened an admin address got a red
  // "something went wrong" with a retry that could never work, a different
  // message on every screen, and the create button drawn over it.
  group('UI-AUDIT #61: the team administration\'s door', () {
    FakeApi teamHost({required String role, List<String> grants = const []}) =>
        FakeApi()
          ..eeState = 'active'
          ..eeFeatures = ['teams']
          ..eeGoverned = true
          ..eePermissions = grants
          ..eeTeamInfo = {
            'id': 'T1',
            'name': 'Acme',
            'slug': 'acme',
            'status': 'active',
            'memberCount': 3,
            'myRole': role,
          };

    Future<void> open(WidgetTester tester, String location) async {
      final container = ProviderScope.containerOf(
        tester.element(find.byType(Scaffold).first),
      );
      container.read(routerProvider).go(location);
      await tester.pumpAndSettle();
    }

    for (final location in [
      '/settings/team',
      '/settings/team/roles',
      '/settings/team/invites',
      '/settings/team/services',
      '/settings/team/audit',
    ]) {
      testWidgets('a member at $location meets one locked state, no "+", and '
          'no request to the endpoint', (tester) async {
        final api = teamHost(role: 'member', grants: ['tasks.view']);
        await tester.pumpWidget(await signedInApp(api));
        await tester.pumpAndSettle();
        api.eeTeamRequests.clear();
        await open(tester, location);

        expect(find.byKey(const Key('ee-forbidden')), findsOneWidget);
        expect(
          find.text('This screen is for the team\'s admins'),
          findsOneWidget,
        );
        expect(find.byType(FloatingActionButton), findsNothing);
        expect(find.text('Something went wrong'), findsNothing);
        // Only the door's own question (who is this person in the team) was
        // asked — never the screen's list.
        expect(
          api.eeTeamRequests.where((r) => r != 'GET /api/v1/ee/team'),
          isEmpty,
        );
      });
    }

    testWidgets('an admin who holds the verb gets the screen and its "+"', (
      tester,
    ) async {
      final api = teamHost(role: 'admin', grants: ['team.manage_roles']);
      await tester.pumpWidget(await signedInApp(api));
      await tester.pumpAndSettle();
      await open(tester, '/settings/team/roles');
      expect(find.byKey(const Key('ee-forbidden')), findsNothing);
      expect(find.byKey(const Key('role-new')), findsOneWidget);
    });

    test('nothing is drawn on a guess: while the permissions load, every '
        'answer is no', () async {
      final pending = Completer<EePermissions>();
      final container = ProviderContainer(
        overrides: [
          eePermissionsProvider.overrideWith(() => _Pending(pending.future)),
        ],
      );
      addTearDown(container.dispose);
      // Before OPH-356 this was TRUE: a delegated manager was handed "New
      // unit" for the second the answer took to arrive.
      expect(container.read(canProvider('units.manage')), isFalse);
      pending.complete(EePermissions.unknown);
      await container.read(eePermissionsProvider.future);
      expect(container.read(canProvider('units.manage')), isTrue);
    });
  });
}

class _Pending extends EePermissionsController {
  _Pending(this._answer);
  final Future<EePermissions> _answer;
  @override
  Future<EePermissions> build() => _answer;
}
