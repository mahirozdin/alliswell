import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/ai/data/ai_context_builder.dart';
import 'package:alliswell/src/features/ai/ui/ai_bubble.dart';
import 'package:alliswell/src/features/ai/ui/ai_settings_screen.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/tasks/ui/task_create_sheet.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/fake_share_inbox.dart';
import '../../support/fake_share_intent.dart';
import '../../support/sync_overrides.dart';

/// OPH-243 — **where shared text goes**.
///
/// `ai_share_test.dart` opens the bubble directly, so it can never see this
/// decision. These drive the real path: the binder hands the payload to
/// `HomeShell`, and `HomeShell` picks a destination.
///
/// The destination CHANGED in round 17's second pass (owner decision): with no
/// AI provider, sharing no longer offers a lesser version of itself. The text
/// is captured to the Inbox and a dialog says why. So the assertions below are
/// about two things at once — the right screen, and the fact that nothing the
/// person shared was lost on the way to it.
Future<Widget> _app(
  FakeApi api, {
  required FakeShareIntentSource share,
  Map<String, Object> prefs = const {},
  FakeShareInbox? inbox,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final store = InMemorySecretStore();
  await TokenStorage(store).save(fakeSession());
  return ProviderScope(
    retry: awRetry,
    overrides: [
      ...syncTestOverrides(shareIntentSource: share, shareInbox: inbox),
      secretStoreProvider.overrideWithValue(store),
      apiClientProvider.overrideWithValue(
        fakeDio(FakeHttpClientAdapter(api.handle)),
      ),
    ],
    child: const AllisWellApp(),
  );
}

/// The localKv row `AiStatusController` caches its last-known answer in. It is
/// the ONLY signal available before the network replies, which is why a
/// cold-start share can be routed correctly at all.
Map<String, Object> _cachedAiStatus({required bool configured}) => {
  'alliswell_ai_status::${fakeSession().user.id}': jsonEncode({
    'configured': configured,
    'providers': configured ? ['anthropic'] : <String>[],
    'instanceProviders': <String>[],
  }),
};

void main() {
  void wide(WidgetTester tester) {
    tester.view.physicalSize = const Size(1280, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('with no AI, a share is captured to the Inbox and explained', (
    tester,
  ) async {
    wide(tester);
    final api = FakeApi(); // AI disabled — the default
    final share = FakeShareIntentSource(
      initial: const SharedPayload(
        text: 'Yayla için rezervasyon yap\npazartesiye kadar',
      ),
    );
    addTearDown(share.dispose);

    await tester.pumpWidget(await _app(api, share: share));
    await tester.pumpAndSettle();

    // The explanation, not a lesser version of the feature.
    expect(find.byKey(const Key('share-no-provider')), findsOneWidget);
    expect(find.byType(TaskCreateSheet), findsNothing);
    expect(find.byType(AiBubble), findsNothing);

    // …and NOTHING was asked of the model. Without a provider there is nothing
    // to ask, and pretending otherwise is how round 14 lost a day.
    expect(
      api.aiExtractCalls,
      0,
      reason: 'the AI-free path must not touch /ai/extract',
    );

    // The actual guarantee: the words survived. Title is the first line
    // (clipTaskTitle), the whole text rides in the description, status inbox.
    final captured = api.tasks.where((t) => t['status'] == 'inbox').toList();
    expect(captured, hasLength(1));
    expect(captured.single['title'], 'Yayla için rezervasyon yap');
    expect(
      captured.single['description'],
      'Yayla için rezervasyon yap\npazartesiye kadar',
    );
  });

  testWidgets('the capture happens BEFORE the dialog, so dismissing keeps it', (
    tester,
  ) async {
    wide(tester);
    final api = FakeApi();
    final share = FakeShareIntentSource(
      initial: const SharedPayload(text: 'kaybolmasın'),
    );
    addTearDown(share.dispose);

    await tester.pumpWidget(await _app(api, share: share));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('share-no-provider')), findsNothing);
    expect(
      api.tasks.where((t) => t['status'] == 'inbox'),
      hasLength(1),
      reason: 'a dialog swallowed by a route change must not take the text',
    );
  });

  testWidgets('the dialog is not a dead end: it routes to AI settings', (
    tester,
  ) async {
    wide(tester);
    final api = FakeApi();
    final share = FakeShareIntentSource(
      initial: const SharedPayload(text: 'sağlayıcı lazım'),
    );
    addTearDown(share.dispose);

    await tester.pumpWidget(await _app(api, share: share));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add a provider'));
    await tester.pumpAndSettle();

    expect(find.byType(AiSettingsScreen), findsOneWidget);
  });

  testWidgets('with AI configured, a warm share opens the bubble', (
    tester,
  ) async {
    wide(tester);
    final api = FakeApi()..aiEnabled = true;
    api.seedAiConnection(provider: 'anthropic');
    final share = FakeShareIntentSource();
    addTearDown(share.dispose);

    await tester.pumpWidget(await _app(api, share: share));
    await tester.pumpAndSettle();

    share.emit(const SharedPayload(text: 'bunu göreve çevir'));
    await tester.pumpAndSettle();

    expect(
      find.byType(TaskCreateSheet),
      findsNothing,
      reason:
          'with a provider there IS something to structure the text with — '
          'the bubble and its confirm card stay the destination',
    );
    expect(find.byType(AiBubble), findsOneWidget);
  });

  // ── The gap round 17 wrote down instead of hiding, now closed ─────────────
  //
  // `AiStatusController.build()` used to return `AiStatus.disabled` outright
  // while `currentWorkspaceProvider` had no value, and the AI FAB reads the
  // provider on the very first frame — so the placeholder stuck, and a
  // cold-start share (which is exactly that window) sent an AI user down the
  // no-AI branch. The fix is in the provider, not at the call site: it reads
  // its localKv cache BEFORE the workspace guard.
  testWidgets('a COLD-START share reaches the bubble when the cache knows', (
    tester,
  ) async {
    wide(tester);
    final api = FakeApi()..aiEnabled = true;
    api.seedAiConnection(provider: 'anthropic');
    final share = FakeShareIntentSource(
      initial: const SharedPayload(text: 'soğuk başlangıçta paylaşıldı'),
    );
    addTearDown(share.dispose);

    await tester.pumpWidget(
      await _app(api, share: share, prefs: _cachedAiStatus(configured: true)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AiBubble), findsOneWidget);
    expect(find.byKey(const Key('share-no-provider')), findsNothing);
  });

  testWidgets('a stale cache is corrected by the bubble, not by losing the '
      'share', (tester) async {
    wide(tester);
    // The realistic staleness: AI is still on for this server, but the user's
    // own connection is gone (revoked key, removed provider). The cache from
    // last launch still says "configured".
    final api = FakeApi()..aiEnabled = true;
    final share = FakeShareIntentSource(
      initial: const SharedPayload(text: 'bayat cache'),
    );
    addTearDown(share.dispose);

    await tester.pumpWidget(
      await _app(api, share: share, prefs: _cachedAiStatus(configured: true)),
    );
    await tester.pumpAndSettle();

    // It opened the bubble on the cache's word — and the bubble owns the
    // correction, which is the whole reason an optimistic cache is safe here.
    expect(find.byType(AiBubble), findsOneWidget);
    expect(find.byKey(const Key('ai-unconfigured')), findsOneWidget);
  });

  // ── The second transport (OPH-242, ADR-0029) ──────────────────────────────
  //
  // On iOS nothing above can fire: the extension writes the App Group and
  // stops, because an appex cannot open its host app on iOS 18+. So the drain
  // is not a fallback there, it is the only path — and since it also runs on
  // every resume, "how many times was the mailbox read" is the assertion that
  // matters. A mailbox that is not cleared turns one share into four tasks.
  testWidgets('a payload waiting in the App Group is routed like any other', (
    tester,
  ) async {
    wide(tester);
    final api = FakeApi();
    final share = FakeShareIntentSource();
    addTearDown(share.dispose);
    final inbox = FakeShareInbox(
      pending: const SharedPayload(text: 'uzantıdan geldi'),
    );

    await tester.pumpWidget(await _app(api, share: share, inbox: inbox));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('share-no-provider')), findsOneWidget);
    expect(api.tasks.where((t) => t['status'] == 'inbox'), hasLength(1));
    expect(inbox.takes, greaterThan(0));
  });

  testWidgets('a drained payload is never replayed on the next resume', (
    tester,
  ) async {
    wide(tester);
    final api = FakeApi();
    final share = FakeShareIntentSource();
    addTearDown(share.dispose);
    final inbox = FakeShareInbox(pending: const SharedPayload(text: 'bir kez'));

    await tester.pumpWidget(await _app(api, share: share, inbox: inbox));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();

    // Background → foreground, the shape a notification tap has from here.
    // The framework asserts on the real transition order, so walk it.
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();

    expect(
      api.tasks.where((t) => t['status'] == 'inbox'),
      hasLength(1),
      reason: 'read-and-clear: one share must not become two tasks',
    );
    expect(find.byKey(const Key('share-no-provider')), findsNothing);
  });

  testWidgets('no cache and a cold share falls to the honest branch', (
    tester,
  ) async {
    wide(tester);
    // AI really is configured server-side, but this device has never asked.
    final api = FakeApi()..aiEnabled = true;
    api.seedAiConnection(provider: 'anthropic');
    final share = FakeShareIntentSource(
      initial: const SharedPayload(text: 'ilk kez'),
    );
    addTearDown(share.dispose);

    await tester.pumpWidget(await _app(api, share: share));
    await tester.pumpAndSettle();

    // Pinned deliberately: the cache is the only cold-start signal there is,
    // and the failure is one-directional — the text is in the Inbox and the
    // reason is on screen. Anyone "fixing" this with a blocking network await
    // would reintroduce the hostage-taking `_shareStatusBudget` exists to stop.
    expect(find.byKey(const Key('share-no-provider')), findsOneWidget);
    expect(
      api.tasks.where((t) => t['status'] == 'inbox'),
      hasLength(1),
      reason: 'one-directional means cheap, not lossy',
    );
  });
}
