// #47 / OPH-444 (owner answer 3): urgent alarms that share a UTC minute ring
// together as ONE alarm, and writing a task into a taken minute is never
// blocked. The create sheet, the task detail and the quick-add confirmation
// only SAY it: "09:00’da 2 acil alarm birlikte çalacak" (the count includes
// the task being written), and the two forms offer "Saati değiştir", which
// opens that instant's own picker. No other task's title is ever shown.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/core/day_boundary.dart';
import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/tasks/ui/task_create_sheet.dart';
import 'package:alliswell/src/features/tasks/ui/task_detail_screen.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/notifications/alarm_overlay.dart';
import 'package:alliswell/src/notifications/planner.dart';
import 'package:alliswell/src/notifications/urgent_minute.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/sync_overrides.dart';
import 'tasks_flow_test.dart' show signedInAppWith, wideSurface, isoAt;

Future<Widget> _app(FakeApi api, {List<Override> extra = const []}) async {
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
      ...extra,
    ],
    child: const AllisWellApp(),
  );
}

/// Tomorrow at [hour]:00 on the wall clock: always in the future, so the
/// alarm still rings and the minute still counts.
DateTime _tomorrowAt(int hour) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day + 1, hour);
}

AlarmInput _alarm(
  String taskId,
  DateTime at, {
  bool urgent = true,
  String kind = 'remind',
}) => AlarmInput(
  reminderId: 'r-$taskId-$kind',
  taskId: taskId,
  taskTitle: 'Task $taskId',
  kind: kind,
  remindAt: at.toUtc(),
  status: 'scheduled',
  urgent: urgent,
  requiresAcknowledgement: urgent,
);

void main() {
  setUp(() => localKv.remove('alliswell_default_task_time'));

  testWidgets('the create sheet shows the shared-minute line and still '
      'saves', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final nine = _tomorrowAt(9);
    final api = FakeApi()
      ..seedTask(
        title: 'Gizli başka görev',
        isUrgent: true,
        remindAt: isoAt(nine),
      );
    await tester.pumpWidget(await _app(api));
    await tester.pumpAndSettle();

    // A deadline at 10:00 derives its reminder an hour before: 09:00, the
    // minute the other task's urgent alarm already holds. 10:00 is free.
    final context = tester.element(find.byType(Scaffold).first);
    // ignore: unawaited_futures
    showTaskCreateSheet(context, initialDue: _tomorrowAt(10));
    await tester.pumpAndSettle();

    final line = find.byKey(const Key('urgent-minute-line-remind'));
    await tester.ensureVisible(line);
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(line).data, sharedMinuteLine(nine, 2));
    expect(find.byKey(const Key('urgent-minute-line-due')), findsNothing);
    // Privacy: the other task's title never appears.
    expect(
      find.descendant(
        of: find.byType(TaskCreateSheet),
        matching: find.textContaining('Gizli başka görev'),
      ),
      findsNothing,
    );

    // "Change time" opens the reminder's own picker; backing out keeps it.
    final change = find.byKey(const Key('urgent-minute-change-remind'));
    expect(tester.getSize(change).height, greaterThanOrEqualTo(48));
    await tester.tap(change);
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    expect(line, findsOneWidget);

    // The switch off: a normal reminder never joins a group — no line.
    final urgent = find.byKey(const Key('task-sheet-urgent'));
    await tester.ensureVisible(urgent);
    await tester.pumpAndSettle();
    await tester.tap(urgent);
    await tester.pumpAndSettle();
    expect(line, findsNothing);
    await tester.tap(urgent);
    await tester.pumpAndSettle();
    expect(line, findsOneWidget);

    // Save is never blocked: no dialog, the task is written as typed.
    await tester.enterText(find.byKey(const Key('task-sheet-title')), 'Kira');
    await tester.pump();
    await tester.tap(find.byKey(const Key('task-sheet-create')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    final created = api.tasks.singleWhere((t) => t['title'] == 'Kira');
    expect(created['isUrgent'], true);
    expect(
      DateTime.parse(created['remindAt'] as String).toLocal(),
      nine,
      reason: 'the minute is never shifted',
    );
  });

  testWidgets('the detail screen shows the line when another urgent alarm '
      'holds the minute', (tester) async {
    await wideSurface(tester);
    final nine = _tomorrowAt(9);
    final api = FakeApi()
      ..seedTask(title: 'Birinci', isUrgent: true, remindAt: isoAt(nine))
      ..seedTask(
        title: 'İkinci gizli',
        isUrgent: true,
        // Another second of the same minute is the same minute.
        remindAt: isoAt(nine.add(const Duration(seconds: 30))),
      );
    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Birinci'));
    await tester.pumpAndSettle();

    final detailList = find.descendant(
      of: find.byType(TaskDetailScreen),
      matching: find.byType(ListView),
    );
    final line = find.byKey(const Key('urgent-minute-line-remind'));
    await tester.dragUntilVisible(line, detailList, const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(line).data, sharedMinuteLine(nine, 2));
    final text = tester.widget<Text>(line).data!;
    expect(text, isNot(contains('İkinci')));

    // "Change time" opens the reminder's picker.
    await tester.tap(find.byKey(const Key('urgent-minute-change-remind')));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();

    // Urgent off on this task: its reminder is a normal one — no line.
    await tester.ensureVisible(find.byKey(const Key('urgent-switch')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('urgent-switch')));
    await tester.pumpAndSettle();
    expect(line, findsNothing);
  });

  testWidgets('quick add confirmation names the shared minute', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // Friday 16 October 2026, 10:00 — the parser's and the alarm clock's now.
    final now = DateTime(2026, 10, 16, 10);
    final nine = DateTime(2026, 10, 17, 9);
    final api = FakeApi()
      ..seedTask(
        title: 'Başkasının işi',
        isUrgent: true,
        dueAt: isoAt(DateTime(2026, 10, 17, 12)),
        remindAt: isoAt(nine),
      );
    await tester.pumpWidget(
      await _app(
        api,
        extra: [
          nowProvider.overrideWithValue(() => now),
          alarmClockProvider.overrideWithValue(() => now),
        ],
      ),
    );
    await tester.pumpAndSettle();

    // "yarın 9'da" = due 09:00 (taken), reminder 08:00 (free).
    await tester.enterText(
      find.byKey(const Key('home-quick-add')),
      "Yarın 9'da kira",
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    final toast = tester.widget<Text>(
      find
          .descendant(
            of: find.byKey(const Key('quick-add-added')),
            matching: find.byType(Text),
          )
          .first,
    );
    expect(toast.data, contains('kira'));
    expect(toast.data, contains('\n${sharedMinuteLine(nine, 2)}'));
    expect(toast.data, isNot(contains('Başkasının')));
    // No "change time" here — the toast only says it; the task is saved.
    expect(find.byKey(const Key('urgent-minute-change-due')), findsNothing);
    expect(api.tasks.where((t) => t['title'] == 'kira'), hasLength(1));
  });

  test('no line for a normal reminder or an empty minute', () {
    final now = DateTime(2030, 6, 1, 8);
    final nine = DateTime(2030, 6, 1, 9);
    final ten = DateTime(2030, 6, 1, 10);
    final feed = [_alarm('other', nine), _alarm('normal', ten, urgent: false)];

    // Urgent off: a normal reminder rings alone, whatever the minute holds.
    expect(
      sharedUrgentMinutes(feed, urgent: false, remindAt: nine, now: now),
      isEmpty,
    );
    // An empty minute, and a minute only a normal reminder holds.
    expect(
      sharedUrgentMinutes(
        feed,
        urgent: true,
        remindAt: nine.add(const Duration(minutes: 1)),
        dueAt: ten,
        now: now,
      ),
      isEmpty,
    );
    // The task's own alarm never makes its minute "taken".
    expect(
      sharedUrgentMinutes(
        feed,
        urgent: true,
        remindAt: nine,
        taskId: 'other',
        now: now,
      ),
      isEmpty,
    );
    // A minute already gone never rings again.
    expect(
      sharedUrgentMinutes(
        feed,
        urgent: true,
        remindAt: nine,
        now: nine.add(const Duration(minutes: 1)),
      ),
      isEmpty,
    );
    // Taken: remind and due each say so, the count includes this task.
    final both = sharedUrgentMinutes(
      [...feed, _alarm('third', ten.add(const Duration(seconds: 9)))],
      urgent: true,
      remindAt: nine,
      dueAt: ten,
      now: now,
    );
    expect(both.map((h) => (h.kind, h.count)), [('remind', 2), ('due', 2)]);
    // Remind and due in one minute are one alarm: one line.
    expect(
      sharedUrgentMinutes(
        feed,
        urgent: true,
        remindAt: nine,
        dueAt: nine.add(const Duration(seconds: 20)),
        now: now,
      ).map((h) => h.kind),
      ['remind'],
    );

    // The owner's exact wording (Turkish locative through OPH-422).
    AwI18n.instance.setActiveCached(const Locale('tr'));
    addTearDown(() => AwI18n.instance.setActiveCached(const Locale('en')));
    expect(sharedMinuteLine(nine, 2), '09:00’da 2 acil alarm birlikte çalacak');
    expect(
      sharedMinuteLine(DateTime(2030, 6, 1, 9, 5), 3),
      '09:05’te 3 acil alarm birlikte çalacak',
    );
    expect('alarm.sharedMinuteChange'.tr(), 'Saati değiştir');
  });
}
