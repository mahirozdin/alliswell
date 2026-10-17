import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/tasks/data/task_when.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/providers.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/sync_overrides.dart';

/// OPH-372 (ADR-0053) — "When" and "Duration" in the create sheet and the
/// task detail, end to end through the outbox, the (fake) server and the pull
/// back into the replica.
///
/// The rules under test, in one breath: "when" is a DAY, independent of the
/// deadline and the reminder; it belongs to one occurrence of a series (no
/// scope question); duration is a series field (the scope question); both
/// survive a sync round trip; a cleared field is sent as null.
late AwDatabase _db;

Future<Widget> _app(FakeApi api) async {
  SharedPreferences.setMockInitialValues({});
  await localKv.remove('alliswell_home_view');
  final store = InMemorySecretStore();
  await TokenStorage(store).save(fakeSession());
  final overrides = syncTestOverrides();
  return ProviderScope(
    retry: awRetry,
    overrides: [
      ...overrides,
      secretStoreProvider.overrideWithValue(store),
      apiClientProvider.overrideWithValue(
        fakeDio(FakeHttpClientAdapter(api.handle)),
      ),
    ],
    child: Consumer(
      builder: (context, ref, _) {
        _db = ref.watch(databaseProvider);
        return const AllisWellApp();
      },
    ),
  );
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Map<String, dynamic> _server(FakeApi api, String id) =>
    api.tasks.firstWhere((t) => t['id'] == id);

List<Map<String, dynamic>> _pushedPatches(FakeApi api, String operation) => [
  for (final m in api.pushedMutations)
    if (m['entityType'] == 'task' && m['operation'] == operation)
      ((m['patch'] as Map?) ?? const {}).cast<String, dynamic>(),
];

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _pickDuration(WidgetTester tester, int preset) async {
  expect(find.byKey(const Key('duration-dialog')), findsOneWidget);
  await tester.tap(find.byKey(Key('duration-preset-$preset')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('duration-save')));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await localKv.remove('alliswell_home_view');
  });

  testWidgets(
    'the create sheet writes When and Duration, and both survive a sync',
    (tester) async {
      _phone(tester);
      final api = FakeApi();
      await tester.pumpWidget(await _app(api));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('task-sheet-title')),
        'Ne zaman görevi',
      );

      // The When tile asks for a DAY only: one date picker, no clock.
      await _tapVisible(tester, find.byKey(const Key('task-sheet-when')));
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(
        find.byType(TimePickerDialog),
        findsNothing,
        reason: '"When" stores a day; asking for a time would be a lie (D5)',
      );

      await _tapVisible(tester, find.byKey(const Key('task-sheet-duration')));
      await _pickDuration(tester, 45);
      expect(find.text('45 min'), findsOneWidget);

      await _tapVisible(tester, find.byKey(const Key('task-sheet-create')));

      // An empty When opens on tomorrow (OPH-173) — that is the day chosen.
      final now = DateTime.now();
      final tomorrow = DateTime(now.year, now.month, now.day + 1);
      final created = _pushedPatches(api, 'create').single;
      expect(created['startAt'], awWhenIso(tomorrow));
      expect(created['estimatedMinutes'], 45);
      // When never arms or moves a reminder, and is not the deadline.
      expect(created.containsKey('remindAt'), isFalse);
      expect(created.containsKey('dueAt'), isFalse);

      // The fake server holds both, and the pull brought them back into the
      // replica: the row on Home shows the duration (FakeApi echo, LESSONS).
      final server = api.tasks.single;
      expect(server['startAt'], awWhenIso(tomorrow));
      expect(server['estimatedMinutes'], 45);
      final row = await (_db.select(
        _db.tasks,
      )..where((t) => t.id.equals(server['id'] as String))).getSingle();
      expect(row.estimatedMinutes, 45);
      expect(row.startAt, DateTime.parse(awWhenIso(tomorrow)));
      expect(find.byKey(Key('task-duration-${server['id']}')), findsOneWidget);
    },
  );

  testWidgets('detail: When is a day, never touches the reminder, and clears', (
    tester,
  ) async {
    _phone(tester);
    final api = FakeApi();
    final now = DateTime.now();
    final due = DateTime(now.year, now.month, now.day + 3, 17);
    final remind = DateTime(now.year, now.month, now.day + 3, 16);
    final task = api.seedTask(
      title: 'Cuma teslim',
      dueAt: due.toUtc().toIso8601String(),
      remindAt: remind.toUtc().toIso8601String(),
    );
    final id = task['id'] as String;

    await tester.pumpWidget(await _app(api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cuma teslim'));
    await tester.pumpAndSettle();

    await _tapVisible(tester, find.byKey(const Key('when-row')));
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsNothing);
    expect(find.byKey(const Key('series-scope-dialog')), findsNothing);

    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final updates = _pushedPatches(api, 'update');
    expect(updates.last.keys, ['startAt']);
    expect(_server(api, id)['startAt'], awWhenIso(tomorrow));
    // The deadline and its alarm did not move (ADR-0053).
    expect(DateTime.parse(_server(api, id)['dueAt'] as String), due.toUtc());
    expect(
      DateTime.parse(_server(api, id)['remindAt'] as String),
      remind.toUtc(),
    );

    // The row's ✕ clears it with an explicit null.
    final clear = find.descendant(
      of: find.byKey(const Key('when-row')),
      matching: find.byIcon(Icons.close),
    );
    await _tapVisible(tester, clear);
    expect(_pushedPatches(api, 'update').last, {'startAt': null});
    expect(_server(api, id)['startAt'], isNull);
  });

  testWidgets('detail: Duration sets, then clears with null', (tester) async {
    _phone(tester);
    final api = FakeApi();
    final task = api.seedTask(title: 'Süreli iş');
    final id = task['id'] as String;

    await tester.pumpWidget(await _app(api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Süreli iş'));
    await tester.pumpAndSettle();

    await _tapVisible(tester, find.byKey(const Key('duration-row')));
    await _pickDuration(tester, 90);
    expect(_pushedPatches(api, 'update').last, {'estimatedMinutes': 90});
    expect(_server(api, id)['estimatedMinutes'], 90);
    expect(find.text('1 h 30 min'), findsOneWidget);

    // A custom value outside 1..1440 is refused in the dialog itself.
    await _tapVisible(tester, find.byKey(const Key('duration-row')));
    await tester.enterText(find.byKey(const Key('duration-custom')), '2000');
    await tester.tap(find.byKey(const Key('duration-save')));
    await tester.pumpAndSettle();
    expect(find.text('Enter 1 to 1440 minutes.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('duration-cancel')));
    await tester.pumpAndSettle();
    expect(_server(api, id)['estimatedMinutes'], 90);

    final clear = find.descendant(
      of: find.byKey(const Key('duration-row')),
      matching: find.byIcon(Icons.close),
    );
    await _tapVisible(tester, clear);
    expect(_pushedPatches(api, 'update').last, {'estimatedMinutes': null});
    expect(_server(api, id)['estimatedMinutes'], isNull);
  });

  testWidgets('a recurring task: When asks no scope question, Duration does', (
    tester,
  ) async {
    _phone(tester);
    final api = FakeApi();
    final now = DateTime.now();
    final due = DateTime(now.year, now.month, now.day + 2, 9);
    final series = api.seedSeries(
      rule: {'freq': 'weekly', 'interval': 1},
      template: {'title': 'Haftalık rapor'},
      anchorAt: due.toUtc().toIso8601String(),
    );
    final task = api.seedTask(
      title: 'Haftalık rapor',
      dueAt: due.toUtc().toIso8601String(),
      seriesId: series['id'] as String,
      occurrenceDate:
          '${due.year}-${due.month.toString().padLeft(2, '0')}-'
          '${due.day.toString().padLeft(2, '0')}',
    );
    final id = task['id'] as String;

    await tester.pumpWidget(await _app(api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Haftalık rapor'));
    await tester.pumpAndSettle();

    // "When" belongs to THIS occurrence.
    await _tapVisible(tester, find.byKey(const Key('when-row')));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('series-scope-dialog')), findsNothing);
    expect(_pushedPatches(api, 'update').last.keys, ['startAt']);

    // Duration is a series field: the scope question, then seriesScope.
    await _tapVisible(tester, find.byKey(const Key('duration-row')));
    await _pickDuration(tester, 30);
    expect(find.byKey(const Key('series-scope-dialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('scope-apply')));
    await tester.pumpAndSettle();
    final patch = _pushedPatches(api, 'update').last;
    expect(patch['estimatedMinutes'], 30);
    expect(patch['seriesScope'], 'future');
    expect(_server(api, id)['estimatedMinutes'], 30);
  });
}
