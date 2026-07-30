import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/ai/data/ai_context_builder.dart';
import 'package:alliswell/src/features/ai/data/ai_stream_client.dart';
import 'package:alliswell/src/features/ai/data/share_intent.dart';
import 'package:alliswell/src/features/ai/ui/ai_bubble.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/workspaces/workspaces.dart';
import 'package:alliswell/src/theme/theme.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/fake_ai.dart';
import '../../support/fake_share_intent.dart';
import '../../support/sync_overrides.dart';

/// OPH-225 — the share target: the seam → pending → bubble binder, and the four
/// action chips (make task / take note / summarize / ask) + the always-works
/// Inbox capture.

// ── the seam mapping (pure) ────────────────────────────────────────────────
void mappingTests() {
  test('payloadFromMedia maps a URL to text + url, drops files', () {
    final url = payloadFromMedia([
      SharedMediaFile(path: 'https://a.example/x', type: SharedMediaType.url),
    ]);
    expect(url?.url, 'https://a.example/x');
    expect(url?.text, 'https://a.example/x');

    final text = payloadFromMedia([
      SharedMediaFile(path: 'buy milk', type: SharedMediaType.text),
    ]);
    expect(text?.text, 'buy milk');
    expect(text?.url, isNull);

    final file = payloadFromMedia([
      SharedMediaFile(path: '/tmp/x.png', type: SharedMediaType.image),
    ]);
    expect(file, isNull);
  });
}

Future<ProviderContainer> containerWith(
  FakeApi api, {
  ShareIntentSource? shareSource,
}) async {
  final store = InMemorySecretStore();
  final container = ProviderContainer(
    retry: awRetry,
    overrides: [
      ...syncTestOverrides(shareIntentSource: shareSource),
      secretStoreProvider.overrideWithValue(store),
      apiClientProvider.overrideWithValue(
        fakeDio(FakeHttpClientAdapter(api.handle)),
      ),
    ],
  );
  addTearDown(container.dispose);
  await TokenStorage(store).save(fakeSession());
  await container.read(authControllerProvider.future);
  await container.read(workspacesProvider.future);
  return container;
}

// ── the bubble harness (opens with a shared payload) ───────────────────────
Future<Widget> shareBubble(
  FakeApi api,
  SharedPayload shared, {
  ScriptedAiStreamClient? stream,
}) async {
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
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showAiBubble(context, shared: shared),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> openShare(WidgetTester tester, Widget app) async {
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('seam mapping', mappingTests);

  test('the binder remembers a cold-start share', () async {
    final api = FakeApi()..seedAiConnection(provider: 'anthropic');
    final source = FakeShareIntentSource(
      initial: const SharedPayload(text: 'cold share'),
    );
    addTearDown(source.dispose);
    final container = await containerWith(api, shareSource: source);

    container.read(shareBinderProvider); // keep-alive, like HomeShell
    await Future<void>.delayed(Duration.zero); // let initialShare resolve
    expect(container.read(pendingSharePayloadProvider)?.text, 'cold share');
    expect(source.calls, containsAll(['initialShare', 'reset']));
  });

  test('the binder remembers a warm share', () async {
    final api = FakeApi()..seedAiConnection(provider: 'anthropic');
    final source = FakeShareIntentSource();
    addTearDown(source.dispose);
    final container = await containerWith(api, shareSource: source);

    container.read(shareBinderProvider);
    await Future<void>.delayed(Duration.zero);
    source.emit(const SharedPayload(text: 'warm share'));
    await Future<void>.delayed(Duration.zero);
    expect(container.read(pendingSharePayloadProvider)?.text, 'warm share');
  });

  test('pending payload replays only once', () async {
    final api = FakeApi();
    final container = await containerWith(api);
    final pending = container.read(pendingSharePayloadProvider.notifier);
    pending.remember(const SharedPayload(text: 'x'));
    expect(pending.take()?.text, 'x');
    expect(pending.take(), isNull);
  });

  testWidgets('a share opens the bubble with five action chips', (
    tester,
  ) async {
    final api = FakeApi()..seedAiConnection(provider: 'anthropic');
    await openShare(
      tester,
      await shareBubble(api, const SharedPayload(text: 'read this article')),
    );
    for (final key in const [
      'ai-share-task',
      'ai-share-note',
      'ai-share-summarize',
      'ai-share-ask',
      'ai-share-inbox',
    ]) {
      expect(find.byKey(Key(key)), findsOneWidget);
    }
  });

  testWidgets('"make task" routes shared text to the confirm card', (
    tester,
  ) async {
    final api = FakeApi()..seedAiConnection(provider: 'anthropic');
    api.nextProposal = {
      'intent': 'create_tasks',
      'tasks': [
        {'title': 'Makaleyi oku', 'confidence': 0.9},
      ],
    };
    await openShare(
      tester,
      await shareBubble(api, const SharedPayload(text: 'read this article')),
    );
    await tester.tap(find.byKey(const Key('ai-share-task')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ai-confirm-accept')), findsOneWidget);
    expect(api.requests.any((r) => r.contains('/ai/extract')), isTrue);
  });

  testWidgets('"take note" saves a note with zero AI', (tester) async {
    final api = FakeApi()..aiEnabled = true; // no connection — no AI at all
    await openShare(
      tester,
      await shareBubble(
        api,
        const SharedPayload(text: 'a thought', url: 'https://a.example'),
      ),
    );
    await tester.tap(find.byKey(const Key('ai-share-note')));
    await tester.pumpAndSettle();

    final create = api.pushedMutations.firstWhere(
      (m) => m['entityType'] == 'note' && m['operation'] == 'create',
    );
    expect((create['patch'] as Map)['title'], 'a thought');
    // The extract endpoint was never touched — take-note is AI-free.
    expect(api.requests.any((r) => r.contains('/ai/extract')), isFalse);
  });

  testWidgets('"save to Inbox" captures shared text as an inbox task', (
    tester,
  ) async {
    final api = FakeApi()..aiEnabled = true;
    await openShare(
      tester,
      await shareBubble(api, const SharedPayload(text: 'buy stamps')),
    );
    await tester.tap(find.byKey(const Key('ai-share-inbox')));
    await tester.pumpAndSettle();

    final create = api.pushedMutations.firstWhere(
      (m) => m['entityType'] == 'task' && m['operation'] == 'create',
    );
    expect((create['patch'] as Map)['status'], 'inbox');
    expect((create['patch'] as Map)['title'], 'buy stamps');
  });

  testWidgets('"summarize" sends a chat turn carrying the shared content', (
    tester,
  ) async {
    final api = FakeApi()..seedAiConnection(provider: 'anthropic');
    final stream = ScriptedAiStreamClient(
      script: const [
        AiTextDelta('Özet: '),
        AiTextDelta('kısa.'),
        AiStreamDone(),
      ],
    );
    await openShare(
      tester,
      await shareBubble(
        api,
        const SharedPayload(text: 'a long article body'),
        stream: stream,
      ),
    );
    await tester.tap(find.byKey(const Key('ai-share-summarize')));
    await tester.pumpAndSettle();

    expect(find.text('Özet: kısa.'), findsOneWidget);
    // The shared content rode along as fenced context, not as chat text.
    final ctx = stream.requests.single.context;
    expect(ctx, isNotNull);
    final segments = (ctx!['segments'] as List).cast<Map>();
    expect(segments.any((s) => s['source'] == 'external_share'), isTrue);
  });

  testWidgets('an unconfigured share still offers note + Inbox', (
    tester,
  ) async {
    final api = FakeApi()..aiEnabled = true; // enabled, unconfigured
    await openShare(
      tester,
      await shareBubble(api, const SharedPayload(text: 'capture me')),
    );
    // The AI-free paths are present even with no provider.
    expect(find.byKey(const Key('ai-share-note')), findsOneWidget);
    expect(find.byKey(const Key('ai-share-inbox')), findsOneWidget);
  });
}
