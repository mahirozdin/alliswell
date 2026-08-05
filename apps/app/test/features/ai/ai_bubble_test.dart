import 'package:flutter/material.dart';
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

/// OPH-221 — the bubble streams, stops, and renders states with a scripted
/// client (no real SSE).
Future<Widget> bubbleWith(FakeApi api, ScriptedAiStreamClient stream) async {
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
      theme: buildAwTheme(Brightness.light),
      home: const Scaffold(body: AiBubble()),
    ),
  );
}

void main() {
  testWidgets('a message streams token by token and commits to history', (
    tester,
  ) async {
    final api = FakeApi()..seedAiConnection(provider: 'anthropic');
    final stream = ScriptedAiStreamClient(
      script: const [AiTextDelta('Mer'), AiTextDelta('haba'), AiStreamDone()],
    );
    await tester.pumpWidget(await bubbleWith(api, stream));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('ai-input')), 'selam');
    await tester.pump();
    await tester.tap(find.byKey(const Key('ai-send')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ai-user-message')), findsOneWidget);
    expect(find.text('Merhaba'), findsOneWidget);
    expect(stream.requests, hasLength(1));
  });

  testWidgets('Stop cancels the stream (scripted, hanging)', (tester) async {
    final api = FakeApi()..seedAiConnection(provider: 'anthropic');
    final stream = ScriptedAiStreamClient(script: const [AiTextDelta('yarım')])
      ..hang = true;
    await tester.pumpWidget(await bubbleWith(api, stream));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('ai-input')), 'uzun iş');
    await tester.pump();
    await tester.tap(find.byKey(const Key('ai-send')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    // Streaming → the Stop button is live.
    expect(find.byKey(const Key('ai-stop')), findsOneWidget);
    await tester.tap(find.byKey(const Key('ai-stop')));
    await tester.pumpAndSettle();
    expect(stream.cancelled, contains(stream.requests.single.requestId));
  });

  testWidgets(
    'round 15b: sending clears and LOCKS the field until the answer lands',
    (tester) async {
      final api = FakeApi()..seedAiConnection(provider: 'anthropic');
      final stream = ScriptedAiStreamClient(
        script: const [AiTextDelta('yarım')],
      )..hang = true;
      await tester.pumpWidget(await bubbleWith(api, stream));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('ai-input')), 'uzun iş');
      await tester.pump();
      await tester.tap(find.byKey(const Key('ai-send')));
      await tester.pump();

      // The field emptied the MOMENT the send left (no stale text to
      // re-submit), and it is disabled for the whole live turn.
      TextField field() =>
          tester.widget<TextField>(find.byKey(const Key('ai-input')));
      expect(field().controller!.text, isEmpty);
      await tester.pump(const Duration(milliseconds: 10));
      expect(field().enabled, isFalse);

      // Stop ends the turn — the field unlocks for the next message.
      await tester.tap(find.byKey(const Key('ai-stop')));
      await tester.pumpAndSettle();
      // ignore: avoid_print
      expect(field().enabled, isTrue);
      expect(stream.requests, hasLength(1));
    },
  );

  testWidgets('round 15b: the conversation follows its own tail', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 560);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final api = FakeApi()..seedAiConnection(provider: 'anthropic');
    // A long first answer overflows the sheet; the second user turn must
    // still end up VISIBLE without any manual scrolling.
    final stream = ScriptedAiStreamClient(
      script: [
        AiTextDelta(List.filled(80, 'uzun satır dolgu metni').join('\n')),
      ],
    );
    await tester.pumpWidget(await bubbleWith(api, stream));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('ai-input')), 'ilk soru');
    await tester.pump();
    await tester.tap(find.byKey(const Key('ai-send')));
    await tester.pumpAndSettle();

    stream.script = const [AiTextDelta('kısa cevap')];
    await tester.enterText(find.byKey(const Key('ai-input')), 'ikinci soru');
    await tester.pump();
    await tester.tap(find.byKey(const Key('ai-send')));
    await tester.pumpAndSettle();

    expect(find.text('ikinci soru').hitTestable(), findsOneWidget);
    expect(find.text('kısa cevap').hitTestable(), findsOneWidget);
  });

  testWidgets('an unconfigured status opens the honest capture state', (
    tester,
  ) async {
    // No connection seeded → status.configured is false.
    final api = FakeApi()..aiEnabled = true;
    final stream = ScriptedAiStreamClient();
    await tester.pumpWidget(await bubbleWith(api, stream));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ai-unconfigured')), findsOneWidget);
  });
}
