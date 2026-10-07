import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/ui/team_chip.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';

/// EE-018 — the app-side acceptance: two team origins in sequence show two
/// identities, and a CE server shows NOTHING (the community build must be
/// pixel-identical). Container-level so the whole shell need not be pumped:
/// the chip is the only new chrome, and it reads the same provider chain the
/// shell does.
///
/// Setup runs inside `tester.runAsync`: signing in and fetching `/ee/status`
/// are real async work, and under `testWidgets`' fake clock the auth
/// repository's own `.timeout(4s)` timer never fires — the await would hang
/// forever instead of failing (it did, first run).
Future<ProviderContainer> containerFor(
  FakeApi api, {
  required String serverUrl,
}) async {
  final store = InMemorySecretStore();
  final container = ProviderContainer(
    retry: awRetry,
    overrides: [
      secretStoreProvider.overrideWithValue(store),
      apiBaseUrlProvider.overrideWithValue(serverUrl),
      apiClientProvider.overrideWithValue(
        fakeDio(FakeHttpClientAdapter(api.handle)),
      ),
    ],
  );
  addTearDown(container.dispose);
  await TokenStorage(store).save(fakeSession());
  await container.read(authControllerProvider.future);
  await container.read(eeStatusProvider.future);
  return container;
}

Widget chipHarness(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    theme: buildAwTheme(Brightness.light),
    home: const Scaffold(
      appBar: null,
      body: Align(alignment: Alignment.topLeft, child: AwTeamChip()),
    ),
  ),
);

FakeApi entitledApi() => FakeApi()
  ..eeState = 'active'
  ..eeFeatures = ['teams']
  ..eeBaseDomain = 'example.com';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('en'));
  });

  /// Builds a signed-in container OUTSIDE the fake clock and clears the cached
  /// entitlement status first (localKv is a process-wide singleton).
  Future<ProviderContainer> prepared(
    WidgetTester tester,
    FakeApi api, {
    required String serverUrl,
  }) async {
    late ProviderContainer container;
    await tester.runAsync(() async {
      await localKv.remove('alliswell_ee_status::user-1');
      container = await containerFor(api, serverUrl: serverUrl);
    });
    return container;
  }

  testWidgets('two team origins in sequence show two identities', (
    tester,
  ) async {
    final acme = await prepared(
      tester,
      entitledApi(),
      serverUrl: 'https://acme.example.com',
    );
    await tester.pumpWidget(chipHarness(acme));
    await tester.pumpAndSettle();
    expect(find.text('Acme'), findsOneWidget);
    expect(find.text('Globex'), findsNothing);

    // Switching teams is switching servers — the same flow a self-hoster
    // already uses, so nothing new is persisted.
    final globex = await prepared(
      tester,
      entitledApi(),
      serverUrl: 'https://globex.example.com',
    );
    await tester.pumpWidget(chipHarness(globex));
    await tester.pumpAndSettle();
    expect(find.text('Globex'), findsOneWidget);
    expect(find.text('Acme'), findsNothing);
  });

  testWidgets('a CE server draws nothing at all', (tester) async {
    // Default FakeApi = CE: state none, no features, no baseDomain.
    final ce = await prepared(
      tester,
      FakeApi(),
      serverUrl: 'https://acme.example.com',
    );
    await tester.pumpWidget(chipHarness(ce));
    await tester.pumpAndSettle();

    expect(find.text('Acme'), findsNothing);
    expect(find.byType(Tooltip), findsNothing);
    // Not "an empty chip" — no chip widget subtree at all.
    expect(
      tester.widget<AwTeamChip>(find.byType(AwTeamChip)).runtimeType,
      AwTeamChip,
    );
    expect(
      find.descendant(of: find.byType(AwTeamChip), matching: find.byType(Row)),
      findsNothing,
    );
  });

  testWidgets('an entitled server without a baseDomain still draws nothing', (
    tester,
  ) async {
    // The instance runs teams but serves no apex — a single-origin EE install.
    final api = entitledApi()..eeBaseDomain = null;
    final container = await prepared(
      tester,
      api,
      serverUrl: 'https://acme.example.com',
    );
    await tester.pumpWidget(chipHarness(container));
    await tester.pumpAndSettle();
    expect(find.text('Acme'), findsNothing);
  });

  // UI-AUDIT #84 (OPH-356): one company, one name. The chip said the slug's
  // "Acme" beside a unit switcher saying the team's real name.
  testWidgets(
    'UI-AUDIT #84: the chip carries the team\'s own name and colour',
    (tester) async {
      final api = entitledApi()
        ..eeMyTeam = {
          'slug': 'acme',
          'name': 'Demir Çelik Fabrikası',
          'color': '#16A34A',
          'origin': 'https://acme.example.com',
        };
      final container = await prepared(
        tester,
        api,
        serverUrl: 'https://acme.example.com',
      );
      await tester.pumpWidget(chipHarness(container));
      await tester.pumpAndSettle();
      expect(find.text('Demir Çelik Fabrikası'), findsOneWidget);
      expect(find.text('Acme'), findsNothing);
      final dot = tester.widget<Container>(
        find.descendant(
          of: find.byType(AwTeamChip),
          matching: find.byType(Container),
        ),
      );
      expect((dot.decoration! as BoxDecoration).color, const Color(0xFF16A34A));
    },
  );

  testWidgets('UI-AUDIT #84: a server without /ee/me/team still names the team '
      'from its own record', (tester) async {
    final api = entitledApi()
      ..eeTeamInfo = {
        'id': 'T1',
        'name': 'Demir Çelik Fabrikası',
        'slug': 'acme',
        'status': 'active',
        'memberCount': 3,
        'myRole': 'member',
      };
    final container = await prepared(
      tester,
      api,
      serverUrl: 'https://acme.example.com',
    );
    await tester.pumpWidget(chipHarness(container));
    await tester.pumpAndSettle();
    expect(find.text('Demir Çelik Fabrikası'), findsOneWidget);
    expect(find.text('Acme'), findsNothing);
  });

  testWidgets('UI-AUDIT #84: another team\'s record never renames this one', (
    tester,
  ) async {
    final api = entitledApi()
      ..eeMyTeam = {
        'slug': 'globex',
        'name': 'Globex',
        'color': '#000000',
        'origin': 'https://globex.example.com',
      };
    final container = await prepared(
      tester,
      api,
      serverUrl: 'https://acme.example.com',
    );
    await tester.pumpWidget(chipHarness(container));
    await tester.pumpAndSettle();
    // The slug's name is the honest fallback.
    expect(find.text('Acme'), findsOneWidget);
  });
}
