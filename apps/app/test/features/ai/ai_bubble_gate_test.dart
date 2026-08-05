import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/ai/data/ai_live_context.dart';
import 'package:alliswell/src/features/ai/providers.dart';
import 'package:alliswell/src/features/ai/data/ai_stream_client.dart';
import 'package:alliswell/src/features/ai/ui/ai_bubble_controller.dart';
import 'package:alliswell/src/features/ai/ui/ai_bubble_state.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/workspaces/workspaces.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/fake_ai.dart';
import '../../support/sync_overrides.dart';

/// Round 15 — the typed path's intent gate + the live context bundle: the
/// two halves of "the chat neither saw my data nor created my tasks" (the
/// owner's live screenshots). Controller-level, the voice wiring harness.
Future<ProviderContainer> signedInContainer(
  FakeApi api,
  ScriptedAiStreamClient stream,
) async {
  final store = InMemorySecretStore();
  final container = ProviderContainer(
    retry: awRetry,
    overrides: [
      ...syncTestOverrides(aiStreamClient: stream),
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
  await container.read(aiStatusProvider.future);
  return container;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a typed task-command gates to the proposal — no chat stream', () async {
    final api = FakeApi()..seedAiConnection(provider: 'anthropic');
    api.nextProposal = {
      'intent': 'create_tasks',
      'tasks': [
        {'title': 'Toplantı', 'confidence': 0.9},
      ],
    };
    final stream = ScriptedAiStreamClient();
    final container = await signedInContainer(api, stream);
    final controller = container.read(aiBubbleControllerProvider.notifier);

    controller.editInput('yarın 16 da toplantımı hatırlat acil iş');
    final proposal = await controller.sendGated();

    expect(proposal, isNotNull);
    expect(proposal!.tasks, hasLength(1));
    expect(api.requests.any((r) => r.contains('/ai/extract')), isTrue);
    expect(stream.requests, isEmpty, reason: 'the card takes over — no chat');
    // The bubble is back to composing, ready for the card to be shown.
    expect(
      container.read(aiBubbleControllerProvider).phase,
      AiBubblePhase.composing,
    );
  });

  test(
    'a plain question falls through to streamed chat WITH context',
    () async {
      final api = FakeApi()..seedAiConnection(provider: 'anthropic');
      // nextProposal unset → the fake extract answers intent:none.
      final stream = ScriptedAiStreamClient(
        script: const [AiTextDelta('Bakalım…')],
      );
      final container = await signedInContainer(api, stream);
      final controller = container.read(aiBubbleControllerProvider.notifier);

      controller.editInput('yoğun birisi miyim');
      final proposal = await controller.sendGated(
        context: buildLiveAiContext(
          read: container.read,
          query: 'yoğun birisi miyim',
        ),
      );
      await pumpEventQueue();

      expect(proposal, isNull);
      expect(stream.requests, hasLength(1));
      final sent = stream.requests.single;
      expect(sent.context, isNotNull, reason: 'AI.md §7 finally rides along');
      final segments = (sent.context!['segments'] as List).cast<Map>();
      expect(segments, isNotEmpty);
      expect(segments.first['tier'], 't0');
      expect(segments.first['source'], 'meta');
      expect(segments.first['text'], contains('tz='));
      // The answer streamed and committed as a normal chat turn.
      final state = container.read(aiBubbleControllerProvider);
      expect(state.history.last.role, 'assistant');
      expect(state.history.last.text, 'Bakalım…');
    },
  );

  test('retryLast re-runs the failed turn without duplicating it', () async {
    final api = FakeApi()..seedAiConnection(provider: 'anthropic');
    final stream = ScriptedAiStreamClient(
      script: const [AiStreamFailure('AI_UPSTREAM_ERROR', 'boom')],
    );
    final container = await signedInContainer(api, stream);
    final controller = container.read(aiBubbleControllerProvider.notifier);

    controller.editInput('selam');
    await controller.sendGated();
    await pumpEventQueue();
    expect(
      container.read(aiBubbleControllerProvider).phase,
      AiBubblePhase.error,
    );

    stream.script = const [AiTextDelta('tamam')];
    await controller.retryLast();
    await pumpEventQueue();

    final state = container.read(aiBubbleControllerProvider);
    expect(state.phase, AiBubblePhase.composing);
    expect(state.history.map((e) => e.role), ['user', 'assistant']);
    expect(state.history.last.text, 'tamam');
    expect(stream.requests, hasLength(2));
    // The second request carries the SAME single user turn — never a copy.
    expect(stream.requests.last.messages, hasLength(1));
    expect(stream.requests.last.messages.single.role, 'user');
  });

  test('round 15b: an eager double-send fires exactly one turn', () async {
    final api = FakeApi()..seedAiConnection(provider: 'anthropic');
    final stream = ScriptedAiStreamClient(
      script: const [AiTextDelta('tek cevap')],
    );
    final container = await signedInContainer(api, stream);
    final controller = container.read(aiBubbleControllerProvider.notifier);

    controller.editInput('selam');
    // The user's Enter-Enter-Enter: both calls race before the machine
    // consumes the input — the _busySending latch must let only one through.
    final first = controller.sendGated();
    final second = controller.sendGated();
    await Future.wait([first, second]);
    await pumpEventQueue();

    expect(stream.requests, hasLength(1));
    expect(api.requests.where((r) => r.contains('/ai/extract')), hasLength(1));
    final history = container.read(aiBubbleControllerProvider).history;
    expect(history.where((e) => e.role == 'user'), hasLength(1));
  });

  test('round 15b: no new send while a turn is thinking/streaming', () async {
    final api = FakeApi()..seedAiConnection(provider: 'anthropic');
    final stream = ScriptedAiStreamClient(script: const [AiTextDelta('akıyor')])
      ..hang = true; // never Done — the turn stays live
    final container = await signedInContainer(api, stream);
    final controller = container.read(aiBubbleControllerProvider.notifier);

    controller.editInput('ilk');
    await controller.sendGated();
    await pumpEventQueue();
    expect(
      container.read(aiBubbleControllerProvider).phase,
      AiBubblePhase.streaming,
    );

    controller.editInput('ikinci');
    final blocked = await controller.sendGated();
    expect(blocked, isNull);
    expect(stream.requests, hasLength(1), reason: 'one turn at a time');
  });

  test('a gate failure degrades to plain chat, never a dead end', () async {
    final api = FakeApi()..seedAiConnection(provider: 'anthropic');
    api.extractStatusCode = 502; // the provider is down for extraction…
    final stream = ScriptedAiStreamClient(
      script: const [AiTextDelta('yine de buradayım')],
    );
    final container = await signedInContainer(api, stream);
    final controller = container.read(aiBubbleControllerProvider.notifier);

    controller.editInput('naber');
    final proposal = await controller.sendGated();
    await pumpEventQueue();

    expect(proposal, isNull);
    expect(stream.requests, hasLength(1), reason: '…but chat still streams');
    expect(
      container.read(aiBubbleControllerProvider).history.last.text,
      'yine de buradayım',
    );
  });
}
