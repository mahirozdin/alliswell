import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/ai/providers.dart';
import 'package:alliswell/src/features/ai/ui/ai_bubble_controller.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/tasks/providers.dart';
import 'package:alliswell/src/features/workspaces/workspaces.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/sync_overrides.dart';

/// OPH-224 — voice → extract routing and the offline Inbox fallback, driven
/// through the bubble controller with a fake API.
Future<ProviderContainer> signedInContainer(FakeApi api) async {
  final store = InMemorySecretStore();
  final container = ProviderContainer(
    retry: awRetry,
    overrides: [
      ...syncTestOverrides(),
      secretStoreProvider.overrideWithValue(store),
      apiClientProvider.overrideWithValue(
        fakeDio(FakeHttpClientAdapter(api.handle)),
      ),
    ],
  );
  addTearDown(container.dispose);
  await TokenStorage(store).save(fakeSession());
  // Wait for the auth restore FIRST — workspacesProvider returns [] while the
  // session is still loading, so reading it before auth resolves is empty.
  await container.read(authControllerProvider.future);
  await container.read(workspacesProvider.future);
  await container.read(aiStatusProvider.future);
  return container;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a create_tasks utterance routes to the confirm proposal', () async {
    final api = FakeApi()..seedAiConnection(provider: 'anthropic');
    api.nextProposal = {
      'intent': 'create_tasks',
      'tasks': [
        {
          'title': 'Ahmet projesine fatura',
          'projectName': 'Ahmet',
          'confidence': 0.9,
        },
        {'title': 'Rapor gönder', 'confidence': 0.8},
      ],
    };
    final container = await signedInContainer(api);

    final route = await container
        .read(aiBubbleControllerProvider.notifier)
        .extractUtterance('Ahmet projesine yarın iki iş ekle', source: 'voice');
    expect(route, isA<AiRouteTasks>());
    expect((route as AiRouteTasks).proposal.tasks, hasLength(2));
    expect(api.requests.any((r) => r.contains('/ai/extract')), isTrue);
  });

  test('an answer intent routes to a chat answer', () async {
    final api = FakeApi()..seedAiConnection(provider: 'anthropic');
    api.nextProposal = {
      'intent': 'answer',
      'answer': 'Bugün 3 görevin var.',
      'tasks': [],
    };
    final container = await signedInContainer(api);

    final route = await container
        .read(aiBubbleControllerProvider.notifier)
        .extractUtterance('bugün kaç işim var', source: 'voice');
    expect(route, isA<AiRouteAnswer>());
    expect((route as AiRouteAnswer).text, contains('3 görev'));
  });

  test(
    'unconfigured routes offline and captureToInbox creates an inbox row',
    () async {
      final api = FakeApi()..aiEnabled = true; // enabled, but NO connection
      final container = await signedInContainer(api);
      final wsId = (await container.read(workspacesProvider.future)).first.id;

      final controller = container.read(aiBubbleControllerProvider.notifier);
      final route = await controller.extractUtterance(
        'süt al',
        source: 'voice',
      );
      expect(route, isA<AiRouteOffline>());

      // Capture writes LOCALLY (drift), with zero network — that is the whole
      // point of the offline fallback, so we assert the local Inbox row.
      await controller.captureToInbox('süt al');
      final inbox = await container
          .read(taskStoreProvider)
          .watchInbox(wsId)
          .first;
      expect(inbox, hasLength(1));
      expect(inbox.single.title, 'süt al');
      expect(inbox.single.status, 'inbox');
    },
  );

  test(
    'a long transcript clips the title and keeps the full text as body',
    () async {
      final api = FakeApi();
      final container = await signedInContainer(api);
      final wsId = (await container.read(workspacesProvider.future)).first.id;

      final long = 'a' * 200;
      await container
          .read(aiBubbleControllerProvider.notifier)
          .captureToInbox(long);
      final row =
          (await container.read(taskStoreProvider).watchInbox(wsId).first)
              .single;
      expect(row.title.length, lessThanOrEqualTo(140));
      expect(row.title.endsWith('…'), isTrue);
      expect(row.description, long);
    },
  );
}
