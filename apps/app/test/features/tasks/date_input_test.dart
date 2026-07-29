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

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/sync_overrides.dart';

/// OPH-191 — one date INPUT path (DESIGN §17 D5), and OPH-192 — "planlanan"
/// stops being a permanent field.
///
/// The regression these tests exist for, in one sentence: changing only the DAY
/// of a 14:30 task used to move it to 23:59, silently, because the detail
/// screen asked for a date and then stamped the default task time on it.
Future<Widget> app(FakeApi api) async {
  SharedPreferences.setMockInitialValues({});
  await localKv.remove('alliswell_home_view');
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

void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// The task as the fake SERVER now holds it — the honest end of the round trip.
Map<String, dynamic> serverTask(FakeApi api, String id) =>
    api.tasks.firstWhere((t) => t['id'] == id);

Future<void> openDetail(WidgetTester tester, String title) async {
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await localKv.remove('alliswell_home_view');
  });

  testWidgets('editing the DAY of a timed task keeps its time', (tester) async {
    phone(tester);
    final api = FakeApi();
    // A local 14:30 today — the picker and the assertion both work in local
    // time, so the test says what the user would say.
    final now = DateTime.now();
    final at = DateTime(now.year, now.month, now.day, 14, 30);
    final task = api.seedTask(
      title: 'Saatli görev',
      dueAt: at.toUtc().toIso8601String(),
    );

    await tester.pumpWidget(await app(api));
    await tester.pumpAndSettle();
    await openDetail(tester, 'Saatli görev');

    await tester.tap(find.byKey(const Key('due-row')));
    await tester.pumpAndSettle();
    // The date picker opens on the current value; accept the same day.
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    // A TIME picker must follow — this is the step that did not exist.
    expect(
      find.byType(TimePickerDialog),
      findsOneWidget,
      reason: 'a field that stores a time must ask for one (D5)',
    );
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    final due = DateTime.parse(
      serverTask(api, task['id'] as String)['dueAt'] as String,
    ).toLocal();
    expect(due.hour, 14);
    expect(due.minute, 30);
  });

  testWidgets('the reminder row asks for a time too', (tester) async {
    phone(tester);
    final api = FakeApi();
    final task = api.seedTask(title: 'Hatırlatma');

    await tester.pumpWidget(await app(api));
    await tester.pumpAndSettle();
    await openDetail(tester, 'Hatırlatma');

    // The Repeat row (OPH-207) pushed this below a phone fold; scroll first.
    await tester.ensureVisible(find.byKey(const Key('remind-row')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('remind-row')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(serverTask(api, task['id'] as String)['remindAt'], isNotNull);
  });

  testWidgets('backing out of the date picker changes nothing', (tester) async {
    phone(tester);
    final api = FakeApi();
    final now = DateTime.now();
    final at = DateTime(now.year, now.month, now.day, 9, 15);
    final task = api.seedTask(
      title: 'Dokunma',
      dueAt: at.toUtc().toIso8601String(),
    );

    await tester.pumpWidget(await app(api));
    await tester.pumpAndSettle();
    await openDetail(tester, 'Dokunma');

    await tester.tap(find.byKey(const Key('due-row')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    final due = DateTime.parse(
      serverTask(api, task['id'] as String)['dueAt'] as String,
    ).toLocal();
    expect(due.hour, 9);
    expect(due.minute, 15);
  });

  group('OPH-192 — the planned date row', () {
    testWidgets('is absent on an ordinary task', (tester) async {
      phone(tester);
      final api = FakeApi()..seedTask(title: 'Sade görev');

      await tester.pumpWidget(await app(api));
      await tester.pumpAndSettle();
      await openDetail(tester, 'Sade görev');

      // Absence is the whole point, so assert the widget is not in the tree —
      // the OPH-172 lesson about tests with teeth.
      expect(find.byKey(const Key('scheduled-row')), findsNothing);
      expect(find.byKey(const Key('due-row')), findsOneWidget);
    });

    testWidgets('appears, explains itself and can be reset once dragged', (
      tester,
    ) async {
      phone(tester);
      final api = FakeApi();
      // What a Google Calendar drag writes: `scheduled_*`, never `due_at`.
      final task = api.seedTask(
        title: 'Takvimde taşınmış',
        scheduledStartAt: DateTime.utc(2026, 7, 30, 11).toIso8601String(),
        scheduledEndAt: DateTime.utc(2026, 7, 30, 11, 30).toIso8601String(),
      );

      await tester.pumpWidget(await app(api));
      await tester.pumpAndSettle();
      await openDetail(tester, 'Takvimde taşınmış');

      expect(find.byKey(const Key('scheduled-row')), findsOneWidget);
      // It says what it IS, not "Planlanan" — the word that meant nothing.
      expect(find.textContaining('Moved in your calendar'), findsOneWidget);

      // The detail column grew a Repeat row (OPH-207), so the button can sit
      // below the fold on a phone — scroll to it instead of tapping into space.
      await tester.ensureVisible(find.byKey(const Key('reset-schedule')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reset-schedule')));
      await tester.pumpAndSettle();

      final row = serverTask(api, task['id'] as String);
      expect(row['scheduledStartAt'], isNull);
      // The end belongs to the block: a start left behind an end would make
      // §7.1 derive a backwards calendar block.
      expect(row['scheduledEndAt'], isNull);
      expect(find.byKey(const Key('scheduled-row')), findsNothing);
    });
  });
}
