import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/core/server_url.dart';
import 'package:alliswell/src/features/api_keys/ui/api_keys_screen.dart';
import 'package:alliswell/src/features/integrations/providers.dart'
    show UrlLauncher, urlLauncherProvider;
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/theme/theme.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/sync_overrides.dart';

/// OPH-265 — API access (ADR-0032). The load-bearing assertions: the secret is
/// shown ONCE and it is the one the server minted, a revoked key stops
/// offering revocation, and an unreachable server SAYS so instead of showing
/// an empty list that would read as "you have no keys".

Future<Widget> screenWith(
  FakeApi api, {
  Brightness? brightness,
  UrlLauncher? launcher,
}) async {
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
      // The docs hand-off goes through a provider so it is observable here
      // without a platform channel.
      if (launcher != null) urlLauncherProvider.overrideWithValue(launcher),
    ],
    child: MaterialApp(
      theme: buildAwTheme(brightness ?? Brightness.light),
      home: const ApiKeysScreen(),
    ),
  );
}

void main() {
  testWidgets('an empty workspace says what a key is for', (tester) async {
    await tester.pumpWidget(await screenWith(FakeApi()));
    await tester.pumpAndSettle();

    expect(find.text('No keys yet'), findsOneWidget);
    expect(find.byKey(const Key('api-key-create')), findsOneWidget);
  });

  testWidgets('an empty workspace still offers the documentation', (
    tester,
  ) async {
    // OPH-296: the person with no keys is deciding whether the API can do
    // what they need, and this screen cannot answer that. The reference can.
    final opened = <Uri>[];
    await tester.pumpWidget(
      await screenWith(
        FakeApi(),
        launcher: (url) async {
          opened.add(url);
          return true;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('api-key-docs-empty')));
    await tester.pumpAndSettle();

    expect(opened.single.toString(), kApiDocsUrl);
  });

  testWidgets('a key in hand comes with the reference beside it', (
    tester,
  ) async {
    // The original complaint, in one assertion: the moment a secret exists
    // there is a way to learn what to do with it, on this screen.
    final opened = <Uri>[];
    final api = FakeApi()..seedApiKey(name: 'cron');
    await tester.pumpWidget(
      await screenWith(
        api,
        launcher: (url) async {
          opened.add(url);
          return true;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('settings-api-docs')));
    await tester.pumpAndSettle();

    expect(opened.single.toString(), kApiDocsUrl);
  });

  testWidgets('the create button is a pill, so its icon is inside it', (
    tester,
  ) async {
    // OPH-293: the theme sets CircleBorder for every FAB flavour, and this
    // Flutter has no separate slot for the extended one. A circle on a wide
    // button paints a 48px disc centred horizontally, leaving the icon
    // outside the painted area — the reported symptom was a label with no
    // icon, which reads as a missing glyph and sends you looking in the
    // wrong place entirely. Pin the shape, not the appearance.
    await tester.pumpWidget(await screenWith(FakeApi()));
    await tester.pumpAndSettle();

    final fab = tester.widget<FloatingActionButton>(
      find.descendant(
        of: find.byKey(const Key('api-key-create')),
        matching: find.byType(FloatingActionButton),
      ),
    );
    expect(fab.shape, isA<StadiumBorder>());

    // And the icon really is painted: a glyph the button owns, not a
    // tooltip standing in for one.
    expect(
      find.descendant(
        of: find.byKey(const Key('api-key-create')),
        matching: find.byIcon(Icons.add),
      ),
      findsOneWidget,
    );
  });

  testWidgets('creating a key shows the secret ONCE, and it is the server’s', (
    tester,
  ) async {
    // The repo's clipboard recipe (ai_settings_test): without the mock the
    // platform channel throws and the copy path never runs.
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    final api = FakeApi();
    await tester.pumpWidget(await screenWith(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('api-key-create')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('api-key-name-field')),
      'Yedekleme script’i',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('api-key-lifetime-30')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('api-key-create-submit')));
    await tester.pumpAndSettle();

    // The dialog shows the value the FAKE SERVER minted — not something the
    // app made up, and not a masked placeholder.
    expect(find.byKey(const Key('api-key-secret-dialog')), findsOneWidget);
    final shown = tester
        .widget<SelectableText>(find.byKey(const Key('api-key-secret-value')))
        .data;
    expect(shown, api.mintedApiKeys.single);
    expect(find.textContaining('only time it is shown'), findsOneWidget);
    // The request carried what the sheet collected.
    expect(api.apiKeys.single['name'], 'Yedekleme script’i');
    expect(api.apiKeys.single['expiresAt'], isNotNull);

    // Copy closes the dialog, puts the REAL secret on the clipboard (not the
    // prefix, not a placeholder) and confirms.
    await tester.tap(find.byKey(const Key('api-key-secret-copy')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('api-key-secret-dialog')), findsNothing);
    expect(copied.single, api.mintedApiKeys.single);
    expect(find.text('Key copied'), findsOneWidget);

    // …and the secret is nowhere on the list screen afterwards. This is the
    // whole promise of "shown once": the only way back to it is the clipboard.
    expect(find.text(shown!), findsNothing);
    expect(find.textContaining(shown.substring(0, 12)), findsOneWidget);
  });

  testWidgets('a key with no expiry is an explicit choice, not a default', (
    tester,
  ) async {
    final api = FakeApi();
    await tester.pumpWidget(await screenWith(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('api-key-create')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('api-key-name-field')), 'cron');
    await tester.pump();
    await tester.tap(find.byKey(const Key('api-key-lifetime-never')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('api-key-create-submit')));
    await tester.pumpAndSettle();

    expect(api.apiKeys.single['expiresAt'], isNull);
  });

  testWidgets('revoking confirms first, then the row stops offering it', (
    tester,
  ) async {
    final api = FakeApi();
    final seeded = api.seedApiKey(name: 'Eski script');
    await tester.pumpWidget(await screenWith(api));
    await tester.pumpAndSettle();

    expect(find.textContaining('Never used'), findsOneWidget);

    await tester.tap(find.byKey(Key('api-key-revoke-${seeded['id']}')));
    await tester.pumpAndSettle();
    // A confirmation the user can back out of…
    await tester.tap(find.byKey(const Key('api-key-revoke-cancel')));
    await tester.pumpAndSettle();
    expect(api.apiKeys.single['revokedAt'], isNull);

    await tester.tap(find.byKey(Key('api-key-revoke-${seeded['id']}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('api-key-revoke-confirm')));
    await tester.pumpAndSettle();

    expect(api.apiKeys.single['revokedAt'], isNotNull);
    // The row is still there (the record of what existed), but a revoked key
    // has nothing left to revoke.
    expect(find.byKey(Key('api-key-${seeded['id']}')), findsOneWidget);
    expect(find.byKey(Key('api-key-revoke-${seeded['id']}')), findsNothing);
    expect(find.textContaining('Revoked'), findsOneWidget);
  });

  testWidgets('an unreachable server says so — never an empty list', (
    tester,
  ) async {
    final api = FakeApi()..offline = true;
    await tester.pumpWidget(await screenWith(api));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not reach the server'), findsOneWidget);
    // The empty state would have been a lie: "no keys" is a claim about the
    // server, and we never heard from it.
    expect(find.text('No keys yet'), findsNothing);
  });

  testWidgets('the screen renders in dark too', (tester) async {
    final api = FakeApi()..seedApiKey(name: 'Gece');
    await tester.pumpWidget(await screenWith(api, brightness: Brightness.dark));
    await tester.pumpAndSettle();
    expect(find.text('Gece'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
