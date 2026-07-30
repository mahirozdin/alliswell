import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/ai/data/ai_models.dart';
import 'package:alliswell/src/features/ai/ui/ai_confirm_card.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/theme/theme.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/sync_overrides.dart';

/// OPH-222 — the confirm card commits through TaskStore, per-row, with undo,
/// and reject writes nothing.
AiProposal proposalOf(List<AiProposalTask> tasks) => AiProposal(
  requestId: 'REQ1',
  actionId: 'ACT1',
  intent: 'create_tasks',
  tasks: tasks,
);

Future<Widget> cardWith(FakeApi api, AiProposal proposal) async {
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
      // A host so the card opens as a real sheet — accept pops it and the
      // undo snackbar lands cleanly on the host scaffold.
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showAiConfirmSheet(context, proposal),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> pumpSettled(WidgetTester tester, Widget app) async {
  await tester.pumpWidget(app);
  await tester.pump();
  await tester.pump();
  await tester.pumpAndSettle();
  await tester.tap(find.text('open')); // open the confirm sheet
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('accepts only the enabled rows', (tester) async {
    final api = FakeApi();
    final proposal = proposalOf(const [
      AiProposalTask(title: 'Fatura öde'),
      AiProposalTask(title: 'Rapor yaz'),
      AiProposalTask(title: 'Toplantı ayarla'),
    ]);
    await pumpSettled(tester, await cardWith(api, proposal));

    // Turn off the middle row.
    await tester.tap(find.byKey(const Key('ai-confirm-toggle-1')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('ai-confirm-accept')));
    await tester.pumpAndSettle();

    final creates = api.pushedMutations.where(
      (m) => m['entityType'] == 'task' && m['operation'] == 'create',
    );
    expect(creates, hasLength(2));
    final titles = creates.map((m) => (m['patch'] as Map)['title']).toSet();
    expect(titles, {'Fatura öde', 'Toplantı ayarla'});
  });

  testWidgets('checklist items are created alongside the task', (tester) async {
    final api = FakeApi();
    final proposal = proposalOf(const [
      AiProposalTask(title: 'Alışveriş', checklist: ['süt', 'ekmek']),
    ]);
    await pumpSettled(tester, await cardWith(api, proposal));
    await tester.tap(find.byKey(const Key('ai-confirm-accept')));
    await tester.pumpAndSettle();

    final checklist = api.pushedMutations.where(
      (m) => m['entityType'] == 'checklist_item',
    );
    expect(checklist, hasLength(2));
  });

  testWidgets('reject writes NOTHING to the outbox', (tester) async {
    final api = FakeApi();
    final proposal = proposalOf(const [AiProposalTask(title: 'İş')]);
    await pumpSettled(tester, await cardWith(api, proposal));
    await tester.tap(find.byKey(const Key('ai-confirm-reject')));
    await tester.pumpAndSettle();
    expect(
      api.pushedMutations.where((m) => m['entityType'] == 'task'),
      isEmpty,
    );
  });

  testWidgets('undo deletes the created tasks', (tester) async {
    final api = FakeApi();
    final proposal = proposalOf(const [AiProposalTask(title: 'İş')]);
    await pumpSettled(tester, await cardWith(api, proposal));
    await tester.tap(find.byKey(const Key('ai-confirm-accept')));
    await tester.pump(); // build the snackbar
    await tester.pump(const Duration(seconds: 1)); // let it animate fully in
    // The undo snackbar is up — tap its action button.
    final undo = find.widgetWithText(SnackBarAction, 'Undo');
    expect(undo, findsOneWidget);
    await tester.tap(undo);
    await tester.pumpAndSettle();
    // create + delete both went to the outbox → the row ends up gone.
    expect(
      api.pushedMutations.where(
        (m) => m['entityType'] == 'task' && m['operation'] == 'delete',
      ),
      hasLength(1),
    );
  });

  testWidgets('an unresolved project shows the spoken name as a hint', (
    tester,
  ) async {
    final api = FakeApi();
    final proposal = proposalOf(const [
      AiProposalTask(title: 'İş', projectName: 'Bilinmeyen Proje'),
    ]);
    await pumpSettled(tester, await cardWith(api, proposal));
    expect(find.textContaining('Bilinmeyen Proje'), findsOneWidget);
  });

  testWidgets('the dueAtSource shows beside the resolved date', (tester) async {
    final api = FakeApi();
    final proposal = proposalOf([
      AiProposalTask(
        title: 'Yarınki iş',
        dueAt: DateTime.now()
            .add(const Duration(days: 1))
            .toUtc()
            .toIso8601String(),
        dueAtSource: 'yarın',
      ),
    ]);
    await pumpSettled(tester, await cardWith(api, proposal));
    expect(find.textContaining('yarın →'), findsOneWidget);
  });
}
