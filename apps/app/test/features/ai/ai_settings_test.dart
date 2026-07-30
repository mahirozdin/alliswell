import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/ai/ui/ai_settings_card.dart';
import 'package:alliswell/src/features/ai/ui/ai_settings_screen.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/theme/theme.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/sync_overrides.dart';

/// OPH-220 — AI settings + consent. The load-bearing assertions: surfaces
/// withdraw when disabled, the connect flow walks consent before the key, the
/// Gemini amber warning appears, and only …last4 is ever shown.

Future<Widget> screenWith(FakeApi api) async {
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
    child: MaterialApp(
      theme: buildAwTheme(Brightness.light),
      home: const AiSettingsScreen(),
    ),
  );
}

Future<Widget> cardWith(FakeApi api) async {
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
    child: MaterialApp(
      theme: buildAwTheme(Brightness.light),
      home: const Scaffold(
        body: SingleChildScrollView(child: AiSettingsCard()),
      ),
    ),
  );
}

void main() {
  testWidgets('the settings card hides itself when AI is disabled', (
    tester,
  ) async {
    final api = FakeApi()..aiEnabled = false;
    await tester.pumpWidget(await cardWith(api));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-ai')), findsNothing);
  });

  testWidgets(
    'the settings card shows a connect CTA when enabled but unconfigured',
    (tester) async {
      final api = FakeApi();
      await tester.pumpWidget(await cardWith(api));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('settings-ai')), findsOneWidget);
      expect(
        find.text('Connect a provider — with your own key'),
        findsOneWidget,
      );
    },
  );

  testWidgets('the /settings/ai screen shows the honest disabled state', (
    tester,
  ) async {
    final api = FakeApi()..aiEnabled = false;
    await tester.pumpWidget(await screenWith(api));
    await tester.pumpAndSettle();
    expect(find.text('AI is off'), findsOneWidget);
    expect(find.byKey(const Key('ai-add-provider')), findsNothing);
  });

  testWidgets('connecting walks consent BEFORE the key, then creates', (
    tester,
  ) async {
    final api = FakeApi();
    await tester.pumpWidget(await screenWith(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ai-add-provider')));
    await tester.pumpAndSettle();
    // Pick Anthropic.
    await tester.tap(find.byKey(const Key('ai-provider-anthropic')));
    await tester.pumpAndSettle();

    // The consent screen is up — the key field is NOT yet reachable.
    expect(find.byKey(const Key('ai-consent-accept')), findsOneWidget);
    expect(find.byKey(const Key('ai-key-field')), findsNothing);
    // Anthropic has no amber warning.
    expect(find.byKey(const Key('ai-consent-amber')), findsNothing);
    await tester.tap(find.byKey(const Key('ai-consent-accept')));
    await tester.pumpAndSettle();

    // Now the key form.
    expect(find.byKey(const Key('ai-key-field')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('ai-key-field')),
      'sk-ant-secret-9999',
    );
    await tester.tap(find.byKey(const Key('ai-key-save')));
    await tester.pumpAndSettle();

    expect(api.aiConnections, hasLength(1));
    expect(api.aiConnections.single['provider'], 'anthropic');
    // Only the last 4 are shown — never the whole key.
    expect(find.textContaining('9999'), findsOneWidget);
    expect(find.textContaining('sk-ant-secret'), findsNothing);
  });

  testWidgets('Gemini shows the amber training warning', (tester) async {
    final api = FakeApi();
    await tester.pumpWidget(await screenWith(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ai-add-provider')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ai-provider-gemini')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ai-consent-amber')), findsOneWidget);
  });

  testWidgets('an existing connection lists with …last4 and a test button', (
    tester,
  ) async {
    final api = FakeApi()
      ..seedAiConnection(provider: 'openai', keyLast4: '4242');
    await tester.pumpWidget(await screenWith(api));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ai-connection-openai')), findsOneWidget);
    expect(find.text('••••4242'), findsOneWidget);

    await tester.tap(find.byKey(const Key('ai-test-openai')));
    await tester.pumpAndSettle();
    expect(api.requests.any((r) => r.contains('/test')), isTrue);
    expect(find.text('The connection works'), findsOneWidget);
  });

  testWidgets('removing a connection deletes it', (tester) async {
    final api = FakeApi()..seedAiConnection(provider: 'openai');
    await tester.pumpWidget(await screenWith(api));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ai-remove-openai')));
    await tester.pumpAndSettle();
    expect(api.aiConnections, isEmpty);
  });

  testWidgets(
    'the MCP connector card shows the instance /mcp URL and copies it',
    (tester) async {
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
      expect(find.textContaining('/mcp'), findsOneWidget);
      await tester.tap(find.byKey(const Key('ai-mcp-copy')));
      await tester.pump();
      expect(copied, hasLength(1));
      expect(copied.single, endsWith('/mcp'));
    },
  );
}
