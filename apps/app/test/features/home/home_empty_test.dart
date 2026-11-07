import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/import/ui/import_wizard_screen.dart';
import 'package:alliswell/src/i18n/i18n.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/sync_overrides.dart';

/// OPH-404 (U-28, A-12, research `ux-core-screens.md` §4.1; DESIGN §50):
/// Home empty for somebody who has never added a task is not Home empty for
/// somebody who finished everything. The first gets a way in; the second
/// gets "all caught up" — and no beach umbrella.
void main() {
  setUp(() => AwI18n.instance.setActiveCached(const Locale('en')));

  Future<void> pump(WidgetTester tester, FakeApi api) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = InMemorySecretStore();
    await TokenStorage(store).save(fakeSession());
    await tester.pumpWidget(
      ProviderScope(
        retry: awRetry,
        overrides: [
          ...syncTestOverrides(),
          secretStoreProvider.overrideWithValue(store),
          apiClientProvider.overrideWithValue(
            fakeDio(FakeHttpClientAdapter(api.handle)),
          ),
        ],
        child: const AllisWellApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  final firstRun = find.byKey(const Key('home-empty-first-run'));
  final done = find.byKey(const Key('home-empty-done'));

  testWidgets('a new account: "No tasks yet", a button into the quick-add '
      'field and a way to move in', (tester) async {
    await pump(tester, FakeApi());

    expect(firstRun, findsOneWidget);
    expect(done, findsNothing);
    expect(find.text('No tasks yet'), findsOneWidget);
    expect(
      find.text('Type in the box above to add your first task.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.beach_access_outlined), findsNothing);

    // "Add your first task" puts the cursor in the field the copy names.
    final field = find.descendant(
      of: find.byKey(const Key('home-quick-add')),
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(field).focusNode.hasFocus, isFalse);
    await tester.tap(find.byKey(const Key('home-empty-add-first')));
    await tester.pumpAndSettle();
    expect(tester.widget<EditableText>(field).focusNode.hasFocus, isTrue);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    // The import link opens the Todoist / TickTick wizard (DESIGN §37).
    expect(find.text('Move in from Todoist or TickTick'), findsOneWidget);
    await tester.tap(find.byKey(const Key('home-empty-import')));
    await tester.pumpAndSettle();
    expect(find.byType(ImportWizardScreen), findsOneWidget);
  });

  testWidgets('every task finished: "All caught up", no first-run '
      'buttons', (tester) async {
    final api = FakeApi()
      ..seedTask(
        title: 'Filed last month',
        status: 'completed',
        completedAt: DateTime.now()
            .subtract(const Duration(days: 30))
            .toUtc()
            .toIso8601String(),
      );
    await pump(tester, api);

    expect(done, findsOneWidget);
    expect(firstRun, findsNothing);
    expect(find.text('All caught up'), findsOneWidget);
    expect(find.text('Nothing left open.'), findsOneWidget);
    expect(find.byKey(const Key('home-empty-add-first')), findsNothing);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    expect(find.byIcon(Icons.beach_access_outlined), findsNothing);
  });

  testWidgets('an idea in the Inbox is not a first run either', (tester) async {
    await pump(tester, FakeApi()..seedTask(title: 'Maybe', status: 'inbox'));
    expect(done, findsOneWidget);
    expect(firstRun, findsNothing);
  });

  testWidgets('Turkish copy (A-12)', (tester) async {
    AwI18n.instance.setActiveCached(const Locale('tr'));
    expect('home.firstRunTitle'.tr(), 'Henüz görev yok');
    expect(
      'home.firstRunBody'.tr(),
      'Yukarıdaki kutuya yazarak ilk görevini ekle.',
    );
    expect('home.allCaughtUp'.tr(), 'Bugünlük bu kadar');
    expect('home.allCaughtUpBody'.tr(), 'Açık görevin kalmadı.');
  });
}
