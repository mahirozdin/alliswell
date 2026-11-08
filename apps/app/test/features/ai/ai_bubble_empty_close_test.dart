import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/ai/data/ai_stream_client.dart';
import 'package:alliswell/src/features/ai/ui/ai_bubble.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/theme/theme.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/fake_ai.dart';
import '../../support/sync_overrides.dart';

/// OPH-402 (polish 4, T-04 / iOS E-5): the AI sheet opened on an empty
/// conversation says what it can do and offers starters, and its close
/// control really closes it — a visible button, a tap on the handle, and the
/// one "Close" node a screen reader activates.
Future<Widget> sheetHost(FakeApi api, ScriptedAiStreamClient stream) async {
  SharedPreferences.setMockInitialValues({});
  final store = InMemorySecretStore();
  await TokenStorage(store).save(fakeSession());
  return ProviderScope(
    retry: awRetry,
    overrides: [
      ...syncTestOverrides(aiStreamClient: stream),
      secretStoreProvider.overrideWithValue(store),
      apiClientProvider.overrideWithValue(
        fakeDio(FakeHttpClientAdapter(api.handle)),
      ),
    ],
    child: MaterialApp(
      theme: buildAwTheme(Brightness.dark),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              key: const Key('open-ai'),
              onPressed: () => showAiBubble(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> openSheet(
  WidgetTester tester,
  FakeApi api,
  ScriptedAiStreamClient stream,
) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(await sheetHost(api, stream));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('open-ai')));
  await tester.pumpAndSettle();
  expect(find.byType(AiBubble), findsOneWidget);
}

void main() {
  group('T-04 empty state', () {
    testWidgets('an empty conversation says what to ask, with three starters', (
      tester,
    ) async {
      final api = FakeApi()..seedAiConnection(provider: 'anthropic');
      await openSheet(tester, api, ScriptedAiStreamClient());

      expect(find.byKey(const Key('ai-empty')), findsOneWidget);
      expect(find.text('Ask, or tell me a task'), findsOneWidget);
      for (var i = 0; i < 3; i++) {
        expect(find.byKey(Key('ai-suggestion-$i')), findsOneWidget);
      }
      expect(find.text('Dentist tomorrow at 3 pm'), findsOneWidget);
    });

    testWidgets('a starter fills the field and sends nothing by itself', (
      tester,
    ) async {
      final api = FakeApi()..seedAiConnection(provider: 'anthropic');
      final stream = ScriptedAiStreamClient(
        script: const [AiTextDelta('Tamam'), AiStreamDone()],
      );
      await openSheet(tester, api, stream);

      await tester.tap(find.byKey(const Key('ai-suggestion-0')));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(find.byKey(const Key('ai-input')));
      expect(field.controller!.text, 'Dentist tomorrow at 3 pm');
      expect(stream.requests, isEmpty);

      // Send enables on the filled text; once a turn exists the empty
      // state steps aside.
      await tester.tap(find.byKey(const Key('ai-send')));
      await tester.pumpAndSettle();
      expect(stream.requests, hasLength(1));
      expect(find.byKey(const Key('ai-empty')), findsNothing);
    });

    testWidgets('the unconfigured face keeps its own message, no starters', (
      tester,
    ) async {
      final api = FakeApi()..aiEnabled = true;
      await openSheet(tester, api, ScriptedAiStreamClient());
      expect(find.byKey(const Key('ai-unconfigured')), findsOneWidget);
      expect(find.byKey(const Key('ai-empty')), findsNothing);
    });
  });

  group('T-04 close', () {
    testWidgets('the visible Close button closes the sheet', (tester) async {
      final api = FakeApi()..seedAiConnection(provider: 'anthropic');
      await openSheet(tester, api, ScriptedAiStreamClient());

      final close = find.byKey(const Key('ai-close'));
      expect(close, findsOneWidget);
      final size = tester.getSize(close);
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(find.byType(AiBubble), findsNothing);
    });

    testWidgets('a plain tap on the drag handle closes the sheet', (
      tester,
    ) async {
      final api = FakeApi()..seedAiConnection(provider: 'anthropic');
      await openSheet(tester, api, ScriptedAiStreamClient());

      await tester.tap(find.byKey(const Key('ai-sheet-handle')));
      await tester.pumpAndSettle();
      expect(find.byType(AiBubble), findsNothing);
    });

    testWidgets(
      'one Close node for a screen reader, and activating it closes',
      (tester) async {
        final handle = tester.ensureSemantics();
        final api = FakeApi()..seedAiConnection(provider: 'anthropic');
        await openSheet(tester, api, ScriptedAiStreamClient());

        // VoiceOver/TalkBack read a node's label and tooltip together.
        final nodes = find.semantics.byPredicate(
          (n) => n.label == 'Close' || n.tooltip == 'Close',
        );
        expect(nodes, findsOne);
        // No second, unlabeled-for-us "Dismiss" handle node beside it.
        expect(find.semantics.byLabel('Dismiss'), findsNothing);
        final node = nodes.evaluate().single;
        expect(node.getSemanticsData().flagsCollection.isButton, isTrue);
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);

        tester.semantics.tap(nodes);
        await tester.pumpAndSettle();
        expect(find.byType(AiBubble), findsNothing);
        handle.dispose();
      },
    );
  });
}
