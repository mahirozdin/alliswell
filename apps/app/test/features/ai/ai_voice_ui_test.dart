import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/ai/ui/ai_bubble.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/theme/theme.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/fake_stt.dart';
import '../../support/sync_overrides.dart';

/// OPH-224 — the voice UI wiring end to end: the mic drives the STT seam, a
/// finalized transcript lands in the editable field (never auto-sent, AI9), and
/// send runs the intent gate → confirm card / inline answer / offline Inbox.
Future<Widget> voiceBubble(FakeApi api, FakeSttController stt) async {
  SharedPreferences.setMockInitialValues({});
  final store = InMemorySecretStore();
  await TokenStorage(store).save(fakeSession());
  return ProviderScope(
    retry: awRetry,
    overrides: [
      ...syncTestOverrides(stt: stt),
      secretStoreProvider.overrideWithValue(store),
      apiClientProvider.overrideWithValue(
        fakeDio(FakeHttpClientAdapter(api.handle)),
      ),
    ],
    child: MaterialApp(
      theme: buildAwTheme(Brightness.light),
      // A host so the bubble opens as a real sheet — the tasks route pops it
      // and pushes the confirm card, and the Inbox snackbar lands on the host.
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showAiBubble(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Opens the bubble and speaks [utterance], stopping to finalize it. Leaves the
/// bubble in the reviewing phase with the transcript in the field.
Future<void> speak(
  WidgetTester tester,
  FakeSttController stt,
  String utterance,
) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('ai-mic')));
  await tester.pumpAndSettle();
  stt.emitPartial(utterance);
  await tester.pump();
  await tester.tap(find.byKey(const Key('ai-listen-stop')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('mic → partial → stop finalizes into the editable field', (
    tester,
  ) async {
    final api = FakeApi()..seedAiConnection(provider: 'anthropic');
    final stt = FakeSttController();
    await tester.pumpWidget(await voiceBubble(api, stt));
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ai-mic')));
    await tester.pumpAndSettle();
    expect(stt.calls, contains('initialize'));
    expect(stt.calls.any((c) => c.startsWith('start:')), isTrue);

    stt.emitPartial('süt al');
    await tester.pump();
    expect(find.byKey(const Key('ai-partial')), findsOneWidget);

    await tester.tap(find.byKey(const Key('ai-listen-stop')));
    await tester.pumpAndSettle();
    // The transcript is in the field, editable, and NOT auto-sent (AI9).
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('ai-input')))
          .controller!
          .text,
      'süt al',
    );
    expect(find.byKey(const Key('ai-send')), findsOneWidget);
  });

  testWidgets('a create_tasks utterance routes to the confirm card', (
    tester,
  ) async {
    final api = FakeApi()..seedAiConnection(provider: 'anthropic');
    api.nextProposal = {
      'intent': 'create_tasks',
      'tasks': [
        {'title': 'Ahmet projesine fatura', 'confidence': 0.9},
      ],
    };
    final stt = FakeSttController();
    await tester.pumpWidget(await voiceBubble(api, stt));
    await tester.pumpAndSettle();

    await speak(tester, stt, 'Ahmet projesine fatura ekle');
    await tester.tap(find.byKey(const Key('ai-send')));
    await tester.pumpAndSettle();

    // The bubble handed off to the confirm card.
    expect(find.byKey(const Key('ai-confirm-accept')), findsOneWidget);
    expect(api.requests.any((r) => r.contains('/ai/extract')), isTrue);
  });

  testWidgets('an answer intent renders inline in the bubble', (tester) async {
    final api = FakeApi()..seedAiConnection(provider: 'anthropic');
    api.nextProposal = {
      'intent': 'answer',
      'answer': 'Bugün üç görevin var.',
      'tasks': <dynamic>[],
    };
    final stt = FakeSttController();
    await tester.pumpWidget(await voiceBubble(api, stt));
    await tester.pumpAndSettle();

    await speak(tester, stt, 'bugün kaç işim var');
    await tester.tap(find.byKey(const Key('ai-send')));
    await tester.pumpAndSettle();

    expect(find.text('Bugün üç görevin var.'), findsOneWidget);
    expect(find.byKey(const Key('ai-user-message')), findsOneWidget);
  });

  testWidgets(
    'unconfigured voice preserves the transcript and saves to Inbox',
    (tester) async {
      final api = FakeApi()..aiEnabled = true; // enabled, no connection
      final stt = FakeSttController();
      await tester.pumpWidget(await voiceBubble(api, stt));
      await tester.pumpAndSettle();

      await speak(tester, stt, 'ekmek al');
      await tester.tap(find.byKey(const Key('ai-send')));
      await tester.pumpAndSettle();

      // Offline/unconfigured → the honest fallback surfaces.
      expect(find.byKey(const Key('ai-save-inbox')), findsOneWidget);
      await tester.tap(find.byKey(const Key('ai-save-inbox')));
      await tester.pumpAndSettle();

      final create = api.pushedMutations.firstWhere(
        (m) => m['entityType'] == 'task' && m['operation'] == 'create',
      );
      expect((create['patch'] as Map)['status'], 'inbox');
      expect((create['patch'] as Map)['title'], 'ekmek al');
    },
  );
}
