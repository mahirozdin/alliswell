import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/core/pending_deletes.dart';
import 'package:alliswell/src/core/recurrence.dart';
import 'package:alliswell/src/core/recurrence_text.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/tasks/ui/repeat_dialog.dart';
import 'package:alliswell/src/i18n/i18n.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/sync_overrides.dart';

/// OPH-375 (ADR-0056, DESIGN §25 R10) — "repeat N days / weeks / months after
/// completion" in the app.
///
/// The server makes the next occurrence when the completion lands; the app's
/// job is the rule and its honesty: the basis switch, one interval and one
/// unit, ONE date ("if you complete it today"), a sentence in each language,
/// and no scope question on an occurrence that has no siblings to scope over.
Future<void> _pumpDialog(
  WidgetTester tester, {
  AwRepeatRule? initial,
  required DateTime today,
  void Function(AwRepeatRule?)? onClosed,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                final rule = await showRepeatDialog(
                  context,
                  anchor: DateTime(2026, 10, 20, 9),
                  initial: initial,
                  today: today,
                );
                onClosed?.call(rule);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<Widget> _app(FakeApi api) async {
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

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// A task that is the open occurrence of a "90 days after completion" series.
Map<String, dynamic> _seedAfterCompletion(FakeApi api, {String? title}) {
  final now = DateTime.now();
  final due = DateTime(now.year, now.month, now.day + 1, 9);
  final series = api.seedSeries(
    rule: {
      'freq': 'daily',
      'interval': 90,
      'end': {'type': 'never'},
      'basis': 'completion',
    },
    template: {'title': title ?? 'Su filtresi'},
    anchorAt: due.toUtc().toIso8601String(),
  );
  return api.seedTask(
    title: title ?? 'Su filtresi',
    dueAt: due.toUtc().toIso8601String(),
    seriesId: series['id'] as String,
    occurrenceDate:
        '${due.year}-${due.month.toString().padLeft(2, '0')}-'
        '${due.day.toString().padLeft(2, '0')}',
  );
}

List<Map<String, dynamic>> _pushed(FakeApi api, String entityType, String op) =>
    [
      for (final m in api.pushedMutations)
        if (m['entityType'] == entityType && m['operation'] == op)
          ((m['patch'] as Map?) ?? const {}).cast<String, dynamic>(),
    ];

void main() {
  group('the sentence (R2)', () {
    test('English and Turkish, every unit and the N forms', () async {
      String say(AwRepeatFreq freq, int n) => awRepeatSentence(
        AwRepeatRule(freq: freq, interval: n, basis: AwRepeatBasis.completion),
        dateFormat: 'dmy_dot',
      );

      await AwI18n.instance.setLocale(const Locale('en'));
      expect(say(AwRepeatFreq.daily, 1), '1 day after completion · no end');
      expect(say(AwRepeatFreq.daily, 90), '90 days after completion · no end');
      expect(say(AwRepeatFreq.weekly, 1), '1 week after completion · no end');
      expect(say(AwRepeatFreq.weekly, 2), '2 weeks after completion · no end');
      expect(say(AwRepeatFreq.monthly, 1), '1 month after completion · no end');
      expect(
        say(AwRepeatFreq.monthly, 6),
        '6 months after completion · no end',
      );

      await AwI18n.instance.setLocale(const Locale('tr'));
      expect(
        say(AwRepeatFreq.daily, 1),
        'Tamamlanınca 1 gün sonra · bitiş yok',
      );
      expect(
        say(AwRepeatFreq.daily, 90),
        'Tamamlanınca 90 gün sonra · bitiş yok',
      );
      expect(
        say(AwRepeatFreq.weekly, 2),
        'Tamamlanınca 2 hafta sonra · bitiş yok',
      );
      expect(
        say(AwRepeatFreq.monthly, 1),
        'Tamamlanınca 1 ay sonra · bitiş yok',
      );
      expect(
        say(AwRepeatFreq.monthly, 3),
        'Tamamlanınca 3 ay sonra · bitiş yok',
      );
      expect(
        awRepeatSentence(
          const AwRepeatRule(
            freq: AwRepeatFreq.weekly,
            basis: AwRepeatBasis.completion,
            end: AwRepeatEnd.count(4),
          ),
          dateFormat: 'dmy_dot',
        ),
        'Tamamlanınca 1 hafta sonra · 4 kez',
      );
    });
  });

  group('the dialog (R10)', () {
    setUp(() => AwI18n.instance.setLocale(const Locale('en')));

    testWidgets('starts on a schedule; switches to after completion and back', (
      tester,
    ) async {
      await _pumpDialog(tester, today: DateTime(2026, 10, 17));
      expect(find.byKey(const Key('repeat-basis')), findsOneWidget);
      expect(find.byKey(const Key('repeat-preset-monthly')), findsOneWidget);
      expect(find.byKey(const Key('repeat-after-interval')), findsNothing);

      await tester.tap(find.byKey(const Key('repeat-basis-completion')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('repeat-preset-monthly')), findsNothing);
      expect(find.text('Next 5'), findsNothing);
      expect(find.byKey(const Key('repeat-after-interval')), findsOneWidget);
      expect(find.byKey(const Key('repeat-after-unit')), findsOneWidget);
      expect(find.byKey(const Key('repeat-after-hint')), findsOneWidget);

      await tester.tap(find.byKey(const Key('repeat-basis-calendar')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('repeat-preset-monthly')), findsOneWidget);
      expect(find.text('Next 5'), findsOneWidget);
    });

    testWidgets('interval and unit drive the one date it previews and saves', (
      tester,
    ) async {
      AwRepeatRule? result;
      await _pumpDialog(
        tester,
        today: DateTime(2026, 10, 17, 15),
        onClosed: (rule) => result = rule,
      );
      await tester.tap(find.byKey(const Key('repeat-basis-completion')));
      await tester.pumpAndSettle();

      // 1 day is the default: tomorrow.
      expect(
        find.byKey(const Key('repeat-after-preview-2026-10-18')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const Key('repeat-after-interval')),
        '90',
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('repeat-after-preview-2027-01-15')),
        findsOneWidget,
      );
      expect(find.text('90 days after completion · no end'), findsOneWidget);

      await tester.tap(find.byKey(const Key('repeat-after-unit-months')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('repeat-after-preview-2034-04-17')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('repeat-after-unit-days')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('repeat-save')));
      await tester.pumpAndSettle();
      expect(
        result,
        const AwRepeatRule(
          freq: AwRepeatFreq.daily,
          interval: 90,
          basis: AwRepeatBasis.completion,
        ),
      );
      expect(result!.toJson()['basis'], 'completion');
    });

    testWidgets('a month after the 31st previews the clamped month end', (
      tester,
    ) async {
      await _pumpDialog(tester, today: DateTime(2027, 1, 31));
      await tester.tap(find.byKey(const Key('repeat-basis-completion')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('repeat-after-unit-months')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('repeat-after-preview-2027-02-28')),
        findsOneWidget,
      );
    });

    testWidgets('an after-completion rule reopens in its own mode, unchanged', (
      tester,
    ) async {
      const initial = AwRepeatRule(
        freq: AwRepeatFreq.weekly,
        interval: 2,
        basis: AwRepeatBasis.completion,
      );
      AwRepeatRule? result;
      await _pumpDialog(
        tester,
        initial: initial,
        today: DateTime(2026, 10, 17),
        onClosed: (rule) => result = rule,
      );
      expect(find.byKey(const Key('repeat-after-interval')), findsOneWidget);
      expect(
        find.byKey(const Key('repeat-after-preview-2026-10-31')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('repeat-save')));
      await tester.pumpAndSettle();
      expect(result, initial);
    });
  });

  group('an occurrence of an after-completion series (R10)', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await localKv.remove('alliswell_home_view');
    });

    testWidgets('the detail reads the rule as a sentence', (tester) async {
      _phone(tester);
      final api = FakeApi();
      _seedAfterCompletion(api);
      await tester.pumpWidget(await _app(api));
      await tester.pumpAndSettle();
      await AwI18n.instance.setLocale(const Locale('en'));
      await tester.tap(find.text('Su filtresi'));
      await tester.pumpAndSettle();

      final summary = find.byKey(const Key('repeat-summary'));
      await tester.ensureVisible(summary);
      expect(
        tester.widget<Text>(summary).data,
        '90 days after completion · no end',
      );
    });

    testWidgets('a title edit asks no scope question and sends no scope', (
      tester,
    ) async {
      _phone(tester);
      final api = FakeApi();
      final task = _seedAfterCompletion(api);
      await tester.pumpWidget(await _app(api));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Su filtresi'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('task-title')),
        'Su filtresini değiştir',
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('series-scope-dialog')), findsNothing);
      final patch = _pushed(api, 'task', 'update').last;
      expect(patch['title'], 'Su filtresini değiştir');
      expect(patch.containsKey('seriesScope'), isFalse);
      expect(
        api.tasks.firstWhere((t) => t['id'] == task['id'])['title'],
        'Su filtresini değiştir',
      );
    });

    testWidgets('deleting the open one asks nothing and stops the repeat', (
      tester,
    ) async {
      _phone(tester);
      final api = FakeApi();
      final task = _seedAfterCompletion(api);
      await tester.pumpWidget(await _app(api));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Su filtresi'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('task-delete')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('occurrence-delete-scope')), findsNothing);
      // The undo window is open: nothing written yet.
      expect(_pushed(api, 'task', 'delete'), isEmpty);
      expect(_pushed(api, 'task_series', 'delete'), isEmpty);

      await tester.pump(kAwUndoWindow + const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(
        api.pushedMutations.where(
          (m) => m['entityType'] == 'task' && m['operation'] == 'delete',
        ),
        hasLength(1),
      );
      final stop = _pushed(api, 'task_series', 'delete');
      expect(stop, hasLength(1));
      expect(stop.single['fromDay'], task['occurrenceDate']);
    });
  });
}
