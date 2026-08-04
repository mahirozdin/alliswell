import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/sync_overrides.dart';

/// OPH-222 — the quick-add ✨ rider runs pasted text through extraction into
/// the same confirm card, and only appears when AI is configured.
Future<Widget> signedInApp(FakeApi api) async {
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
    child: const AllisWellApp(),
  );
}

void main() {
  testWidgets('no ✨ affordance when AI is unconfigured', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final api = FakeApi()
      ..aiEnabled = true; // AI enabled, no connection → unconfigured
    await tester.pumpWidget(await signedInApp(api));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('quick-add-parse')), findsNothing);
  });

  /// The per-row "AI is filling this in" badge, whatever task id it carries.
  Finder enrichingBadge() => find.byWidgetPredicate(
    (w) =>
        w.key is ValueKey<String> &&
        (w.key as ValueKey<String>).value.startsWith('ai-enriching-'),
  );

  testWidgets('✨ adds instantly; the AI fills fields in asynchronously', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final api = FakeApi()..seedAiConnection(provider: 'anthropic');
    api.extractDelay = const Duration(milliseconds: 300);
    final dueAt = DateTime.now().add(const Duration(days: 1)).toUtc();
    api.nextProposal = {
      'intent': 'create_tasks',
      'tasks': [
        {
          'title': 'Faturayı öde',
          'dueAt': dueAt.toIso8601String(),
          'confidence': 0.9,
        },
        {'title': 'Raporu gönder', 'confidence': 0.8},
      ],
    };
    await tester.pumpWidget(await signedInApp(api));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('quick-add-parse')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('home-quick-add')),
      'faturayı öde ve raporu gönder',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('quick-add-parse')));
    // Round 14: the row exists BEFORE the proposal answers — plain quick-add
    // semantics, marked by the enriching badge; no confirm card, no blocking.
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('faturayı öde ve raporu gönder'), findsOneWidget);
    expect(enrichingBadge(), findsOneWidget);
    expect(find.byKey(const Key('ai-confirm-accept')), findsNothing);

    // Let the extraction land.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(enrichingBadge(), findsNothing);
    expect(find.byKey(const Key('ai-confirm-accept')), findsNothing);
    expect(find.text('Faturayı öde'), findsOneWidget);
    expect(find.text('Raporu gönder'), findsOneWidget);
    expect(api.requests.any((r) => r.contains('/ai/extract')), isTrue);

    // First task was UPDATED in place; the second was created whole; both
    // carry the round-14 quick-add defaults, and the extracted deadline
    // derived its one-hour-before reminder.
    expect(api.tasks, hasLength(2));
    final first = api.tasks.firstWhere((t) => t['title'] == 'Faturayı öde');
    expect(first['priority'], 'medium');
    expect(first['isUrgent'], true);
    final due = DateTime.parse(first['dueAt'] as String);
    final remind = DateTime.parse(first['remindAt'] as String);
    expect(due.difference(remind), const Duration(hours: 1));
    // The auto-applied proposal is reported as an accepted action with both
    // task refs — audit parity with the confirm card.
    expect(api.aiActionAccepts, hasLength(1));
    expect(api.aiActionAccepts.single['accepted'], true);
    expect((api.aiActionAccepts.single['entityRefs'] as List), hasLength(2));
  });

  testWidgets('✨ failure leaves the plain quick-added task standing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final api = FakeApi()..seedAiConnection(provider: 'anthropic');
    // `nextProposal` unset → the fake answers intent:none — the "AI found
    // nothing" shape; the row must simply stay a plain quick add.
    await tester.pumpWidget(await signedInApp(api));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('home-quick-add')),
      'öylesine bir not',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('quick-add-parse')));
    await tester.pumpAndSettle();

    expect(find.text('öylesine bir not'), findsOneWidget);
    expect(enrichingBadge(), findsNothing);
    expect(find.byKey(const Key('ai-confirm-accept')), findsNothing);
    expect(api.tasks, hasLength(1));
    expect(api.tasks.single['title'], 'öylesine bir not');
    expect(api.tasks.single['priority'], 'medium');
    expect(api.tasks.single['isUrgent'], true);
  });
}
