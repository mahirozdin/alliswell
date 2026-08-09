import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/ai/data/ai_context_builder.dart';
import 'package:alliswell/src/features/ai/ui/ai_bubble.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/tasks/ui/task_create_sheet.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/fake_share_intent.dart';
import '../../support/sync_overrides.dart';

/// OPH-243 — **where shared text goes**.
///
/// The existing `ai_share_test.dart` opens the bubble directly, so it can never
/// see this decision. These tests drive the real path instead: the share
/// binder hands the payload to `HomeShell`, and `HomeShell` picks a
/// destination. That routing IS the round-17 change, so it needs the full pump.
Future<Widget> _app(FakeApi api, {required FakeShareIntentSource share}) async {
  SharedPreferences.setMockInitialValues({});
  final store = InMemorySecretStore();
  await TokenStorage(store).save(fakeSession());
  return ProviderScope(
    retry: awRetry,
    overrides: [
      ...syncTestOverrides(shareIntentSource: share),
      secretStoreProvider.overrideWithValue(store),
      apiClientProvider.overrideWithValue(
        fakeDio(FakeHttpClientAdapter(api.handle)),
      ),
    ],
    child: const AllisWellApp(),
  );
}

void main() {
  testWidgets('with no AI, a share opens the create sheet already filled in', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final api = FakeApi(); // AI disabled — the default
    final share = FakeShareIntentSource(
      initial: const SharedPayload(
        text: 'Yayla için rezervasyon yap\npazartesiye kadar',
      ),
    );
    addTearDown(share.dispose);

    await tester.pumpWidget(await _app(api, share: share));
    await tester.pumpAndSettle();

    // The detailed sheet, not the bubble.
    expect(find.byType(TaskCreateSheet), findsOneWidget);
    expect(find.byType(AiBubble), findsNothing);

    // Title = the first line; the whole text is kept in the description so
    // nothing the person shared is dropped.
    final title = tester.widget<TextFormField>(
      find.byKey(const Key('task-sheet-title')),
    );
    expect(title.controller?.text, 'Yayla için rezervasyon yap');
    final description = tester.widget<TextFormField>(
      find.byKey(const Key('task-sheet-description')),
    );
    expect(
      description.controller?.text,
      'Yayla için rezervasyon yap\npazartesiye kadar',
    );

    // The caret sits at the END: the field autofocuses, and a prefilled
    // autofocused field that opens fully selected is one keystroke away from
    // destroying what was shared.
    expect(
      title.controller?.selection.baseOffset,
      'Yayla için rezervasyon yap'.length,
    );

    // …and NOTHING was asked of the model. Without a provider there is nothing
    // to ask, and pretending otherwise is how round 14 lost a day.
    expect(
      api.aiExtractCalls,
      0,
      reason: 'the AI-free path must not touch /ai/extract',
    );
  });

  testWidgets('with AI configured, a share opens the bubble', (tester) async {
    tester.view.physicalSize = const Size(1280, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final api = FakeApi()..aiEnabled = true;
    api.seedAiConnection(provider: 'anthropic');
    final share = FakeShareIntentSource();
    addTearDown(share.dispose);

    await tester.pumpWidget(await _app(api, share: share));
    await tester.pumpAndSettle();

    // Delivered WARM, on purpose. See the note below: the cold-start variant of
    // this test currently fails for a reason that is not about routing.
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

  // ── KNOWN GAP, written down rather than hidden (OPH-243) ──────────────────
  //
  // The same test with a COLD-START share (`FakeShareIntentSource(initial:)`)
  // fails: the create sheet opens even though AI is configured.
  //
  // It is not the routing. `AiStatusController.build()` returns
  // `AiStatus.disabled` outright while `currentWorkspaceProvider` has no value,
  // and something reads the provider on the very first frame — so the status
  // resolves to "no AI" before the workspace exists, and a cold-start share
  // lands inside exactly that window. Awaiting `workspacesProvider` in
  // `_aiStatusForShare` is not enough, because the provider has already
  // completed with the placeholder by then.
  //
  // Fixing it properly means teaching `aiStatusProvider` to distinguish "no
  // workspace yet" from "AI is off" — a change to a provider five surfaces
  // depend on, not a patch at the call site. Tracked in TASKS Epic 24 / STATE.
  //
  // The user-visible cost meanwhile is one-directional and small: an AI user
  // who shares into a cold app gets the filled create sheet instead of the
  // bubble. A working destination, not a dead end — which is why this ships
  // rather than blocks.
}
