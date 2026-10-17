import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/api_exception.dart';
import 'package:alliswell/src/features/import/data/import_api.dart';
import 'package:alliswell/src/features/import/data/import_models.dart';
import 'package:alliswell/src/i18n/i18n.dart';

import 'import_fakes.dart';

/// OPH-371 — the wizard: source → file → preview → import → result, the
/// batching loop, the completed toggle, and every refusal said in words.
Future<void> toPreview(WidgetTester tester, {String source = 'todoist'}) async {
  await tester.tap(find.byKey(Key('import-source-$source')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('import-pick')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('import-preview')));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(900, 3200);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
  }

  testWidgets('the whole flow: preview counts, three batches, sync, report', (
    tester,
  ) async {
    tall(tester);
    var synced = 0;
    final api = FakeImportApi(
      preview: (inc) => sampleSummary(includeCompleted: inc),
      batches: [
        batch(tasks: 20, remaining: 22),
        batch(tasks: 20, remaining: 2),
        batch(tasks: 2, remaining: 0, errors: 1),
      ],
    );
    await tester.pumpWidget(
      wizardApp(importOverrides(api: api, onSync: () => synced += 1)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Step 1 of 4'), findsOneWidget);
    // Apple Reminders is not offered — and the screen says why.
    expect(
      find.textContaining('Apple Reminders has no export file'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('import-source-todoist')));
    await tester.pumpAndSettle();
    expect(find.text('Step 2 of 4'), findsOneWidget);
    expect(find.textContaining('Settings › Backups'), findsOneWidget);
    await tester.tap(find.byKey(const Key('import-pick')));
    await tester.pumpAndSettle();
    expect(find.text('Ev İşleri [2203306142].csv'), findsOneWidget);

    await tester.tap(find.byKey(const Key('import-preview')));
    await tester.pumpAndSettle();
    expect(api.calls.single.dryRun, isTrue);
    expect(api.calls.single.options['defaultTaskTime'], '23:59');
    expect(api.calls.single.options.containsKey('timezone'), isFalse);
    expect(find.text('Step 3 of 4'), findsOneWidget);
    final tasksCount = tester.widget<Text>(
      find.byKey(const Key('import-count-tasks')),
    );
    expect(tasksCount.data, '34');
    expect(find.text('P1'), findsOneWidget);
    expect(find.byKey(const Key('import-google-notice')), findsOneWidget);
    // Todoist has no completed tasks to offer.
    expect(find.byKey(const Key('import-include-completed')), findsNothing);
    expect(
      find.text(
        'A repeat could not be converted; it is kept in the description',
      ),
      findsOneWidget,
    );

    await tester.ensureVisible(find.byKey(const Key('import-run')));
    await tester.tap(find.byKey(const Key('import-run')));
    await tester.pumpAndSettle();

    expect(api.calls.where((c) => !c.dryRun), hasLength(3));
    expect(synced, 1);
    expect(find.byKey(const Key('import-result')), findsOneWidget);
    // 20+20+2 tasks, plus the 6 repeats and 2 notes each partial batch made.
    expect(find.text('58 items imported.'), findsOneWidget);
    expect(find.byKey(const Key('import-result-errors')), findsOneWidget);
    expect(
      find.textContaining('Ev İşleri [2203306142].csv:40'),
      findsOneWidget,
    );
  });

  testWidgets('a batch that makes no progress stops the loop', (tester) async {
    tall(tester);
    final api = FakeImportApi(
      preview: (_) => sampleSummary(),
      batches: [
        batch(tasks: 40, remaining: 2),
        const ImportSummary(total: 0, remaining: 2),
      ],
    );
    await tester.pumpWidget(wizardApp(importOverrides(api: api)));
    await tester.pumpAndSettle();
    await toPreview(tester);
    await tester.ensureVisible(find.byKey(const Key('import-run')));
    await tester.tap(find.byKey(const Key('import-run')));
    await tester.pumpAndSettle();
    // Call 2 made nothing and left the same 2 → stop, do not spin.
    expect(api.calls.where((c) => !c.dryRun), hasLength(2));
    expect(find.byKey(const Key('import-result')), findsOneWidget);
  });

  testWidgets('TickTick: the completed switch re-runs the preview', (
    tester,
  ) async {
    tall(tester);
    final api = FakeImportApi(
      preview: (inc) => sampleSummary(includeCompleted: inc),
    );
    await tester.pumpWidget(wizardApp(importOverrides(api: api)));
    await tester.pumpAndSettle();
    await toPreview(tester, source: 'ticktick');

    expect(find.text('Include completed tasks (2)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('import-include-completed')));
    await tester.pumpAndSettle();
    expect(api.calls, hasLength(2));
    expect(api.calls.last.options['includeCompleted'], isTrue);
    expect(find.text('Import 44 items'), findsOneWidget);
  });

  testWidgets('a TickTick file chosen as Todoist says so', (tester) async {
    tall(tester);
    final api = FakeImportApi(preview: (_) => sampleSummary())
      ..error = const ImportSourceMismatch('ticktick');
    await tester.pumpWidget(wizardApp(importOverrides(api: api)));
    await tester.pumpAndSettle();
    await toPreview(tester);
    expect(find.byKey(const Key('import-error')), findsOneWidget);
    expect(
      find.textContaining('This looks like a TickTick backup'),
      findsOneWidget,
    );
  });

  testWidgets('a 413 from a proxy explains the upload limit', (tester) async {
    tall(tester);
    final api = FakeImportApi(preview: (_) => sampleSummary())
      ..error = const ApiException('HTTP_413', 'x', statusCode: 413);
    await tester.pumpWidget(wizardApp(importOverrides(api: api)));
    await tester.pumpAndSettle();
    await toPreview(tester);
    expect(find.textContaining('client_max_body_size 10m'), findsOneWidget);
  });

  testWidgets('offline shows the inline error, not an empty preview', (
    tester,
  ) async {
    tall(tester);
    final api = FakeImportApi(preview: (_) => sampleSummary())
      ..error = asApiException(
        DioException(requestOptions: RequestOptions(path: '/x')),
      );
    await tester.pumpWidget(wizardApp(importOverrides(api: api)));
    await tester.pumpAndSettle();
    await toPreview(tester);
    expect(find.textContaining('Importing needs a connection'), findsOneWidget);
    expect(find.byKey(const Key('import-counts')), findsNothing);
  });

  testWidgets('everything already imported: nothing to press', (tester) async {
    tall(tester);
    final api = FakeImportApi(
      preview: (_) => const ImportSummary(total: 0, alreadyImported: 42),
    );
    await tester.pumpWidget(wizardApp(importOverrides(api: api)));
    await tester.pumpAndSettle();
    await toPreview(tester);
    expect(
      find.text('Everything in this file has already been imported.'),
      findsOneWidget,
    );
    final run = tester.widget<FilledButton>(
      find.byKey(const Key('import-run')),
    );
    expect(run.onPressed, isNull);
  });

  testWidgets('renders in Turkish', (tester) async {
    tall(tester);
    await AwI18n.instance.setLocale(const Locale('tr'));
    addTearDown(() => AwI18n.instance.setLocale(const Locale('en')));
    final api = FakeImportApi(preview: (_) => sampleSummary());
    await tester.pumpWidget(wizardApp(importOverrides(api: api)));
    await tester.pumpAndSettle();
    expect(find.text('Nereden taşınıyorsunuz?'), findsOneWidget);
    await toPreview(tester);
    expect(api.calls.single.options['locale'], 'tr');
    expect(find.text('42 öğeyi içe aktar'), findsOneWidget);
  });
}
