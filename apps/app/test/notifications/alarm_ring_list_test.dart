import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/core/day_boundary.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/notifications/alarm_action_tile.dart';
import 'package:alliswell/src/notifications/alarm_overlay.dart';
import 'package:alliswell/src/notifications/alarm_ring_list.dart';
import 'package:alliswell/src/notifications/planner.dart';
import 'package:alliswell/src/notifications/providers.dart';
import 'package:alliswell/src/theme/tokens.dart';

import '../support/created_tickers.dart';
import '../support/sync_overrides.dart';

String id(String p) => p.padRight(26, '0');

/// The list mode alone (#47, OPH-443): its header, the rows' sheet, and what
/// a screen reader gets from it. The answers themselves are covered in
/// alarm_ring_screen_test.dart, through the shell's layer.
void main() {
  // Local 09:00: "5 min" lands on 09:05.
  final now = DateTime(2030, 6, 1, 9);

  AlarmInput row(String n, DateTime at, {String status = 'scheduled'}) =>
      AlarmInput(
        reminderId: id('R$n'),
        taskId: id('T$n'),
        taskTitle: 'Task $n',
        remindAt: at,
        status: status,
        urgent: true,
        requiresAcknowledgement: true,
      );

  Future<void> pumpList(
    WidgetTester tester,
    List<AlarmInput> rows, {
    List<AlarmInput> alarms = const [],
    Size size = const Size(430, 932),
    bool reduceMotion = false,
    List<Override> extra = const [],
    ValueListenable<List<AlarmInput>>? live,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (reduceMotion) {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
    }
    final container = ProviderContainer(
      overrides: [
        ...syncTestOverrides(),
        nowProvider.overrideWithValue(() => now),
        ...extra,
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF2563EB),
            ),
            extensions: const [AwTokens.light],
          ),
          home: Scaffold(
            body: live == null
                ? AlarmRingList(rows: rows, alarms: alarms)
                : ValueListenableBuilder<List<AlarmInput>>(
                    valueListenable: live,
                    builder: (_, rows, _) =>
                        AlarmRingList(rows: rows, alarms: alarms),
                  ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  String header(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const Key('alarm-list-header-text')))
      .textSpan!
      .toPlainText()
      .replaceAll('\u202f', ' ');

  /// A Text reading [value], whatever space the time format puts before
  /// AM/PM (a narrow no-break space in en).
  Finder textOf(String value) => find.byWidgetPredicate(
    (w) => w is Text && w.data?.replaceAll('\u202f', ' ') == value,
  );

  // ── X-05: the header tells the truth about its minute ────────────────────

  testWidgets('rows in different minutes: the header shows the count only', (
    tester,
  ) async {
    await pumpList(tester, [
      row('1', now.add(const Duration(minutes: 11))),
      row('2', now.add(const Duration(minutes: 13))),
      row('3', now.add(const Duration(minutes: 13, seconds: 20))),
    ]);
    expect(header(tester), '3 URGENT REMINDERS');
    // Each card still says its own time.
    expect(textOf('9:11 AM'), findsOneWidget);
    expect(textOf('9:13 AM'), findsNWidgets(2));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('rows in one minute: the header shows the count and the time', (
    tester,
  ) async {
    await pumpList(tester, [
      row('1', now.add(const Duration(minutes: 11))),
      row('2', now.add(const Duration(minutes: 11, seconds: 40))),
    ]);
    expect(header(tester), '2 URGENT REMINDERS · 9:11 AM');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a snoozed row counts at its snooze minute', (tester) async {
    await pumpList(tester, [
      row('1', now.add(const Duration(minutes: 11))),
      AlarmInput(
        reminderId: id('R2'),
        taskId: id('T2'),
        taskTitle: 'Task 2',
        remindAt: now.subtract(const Duration(minutes: 20)),
        snoozedUntil: now.add(const Duration(minutes: 11, seconds: 5)),
        status: 'snoozed',
        urgent: true,
        requiresAcknowledgement: true,
      ),
    ]);
    expect(header(tester), '2 URGENT REMINDERS · 9:11 AM');
    await tester.pumpWidget(const SizedBox());
  });

  // ── X-04: the row sheet marks a minute another alarm already holds ───────

  testWidgets('the row sheet says a preset rings together with another alarm', (
    tester,
  ) async {
    final rows = [
      row('1', now.subtract(const Duration(seconds: 10))),
      row('2', now.subtract(const Duration(seconds: 5))),
    ];
    // Task 9 was snoozed into 09:05 a moment ago: "5 min" joins it, the
    // other presets do not. Task 2's own alarm (still ringing) never counts.
    final other = AlarmInput(
      reminderId: id('R9'),
      taskId: id('T9'),
      taskTitle: 'Task 9',
      remindAt: now.subtract(const Duration(minutes: 30)),
      snoozedUntil: now.add(const Duration(minutes: 5, seconds: 20)),
      status: 'snoozed',
      urgent: true,
      requiresAcknowledgement: true,
    );
    await pumpList(tester, rows, alarms: [...rows, other]);
    await tester.tap(find.byKey(Key('alarm-row-snooze-${id('T1')}')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final five = find.byKey(const Key('alarm-sheet-snooze-5_min'));
    expect(
      find.descendant(
        of: five,
        matching: find.text('alarm.sheet.joinsGroup'.tr()),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: five, matching: textOf('9:05 AM')),
      findsOneWidget,
    );
    for (final p in ['30_min', '1_hour', 'tomorrow_morning']) {
      expect(
        find.descendant(
          of: find.byKey(Key('alarm-sheet-snooze-$p')),
          matching: find.text('alarm.sheet.joinsGroup'.tr()),
        ),
        findsNothing,
        reason: p,
      );
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the row sheet marks nothing when the minutes are free', (
    tester,
  ) async {
    final rows = [
      row('1', now.subtract(const Duration(seconds: 10))),
      row('2', now.subtract(const Duration(seconds: 5))),
    ];
    await pumpList(tester, rows, alarms: rows);
    await tester.tap(find.byKey(Key('alarm-row-snooze-${id('T1')}')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('alarm.sheet.joinsGroup'.tr()), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  // ── X-07: the list for a screen reader ───────────────────────────────────

  testWidgets('a screen reader reads the header, each card with its two '
      'buttons, the Snooze all tiles and Acknowledge all, in that order', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpList(tester, [
      row('1', now.add(const Duration(seconds: 1))),
      row('2', now.add(const Duration(seconds: 2))),
    ]);

    // The header is a heading of its own, not the name of the screen.
    final head = tester.getSemantics(
      find.bySemanticsLabel(RegExp(r'^2 URGENT REMINDERS')),
    );
    expect(head, isSemantics(isHeader: true));
    expect(head.rect.height, lessThan(120));
    expect(head.label, isNot(contains('Snooze all')));
    final snoozeAll = tester.getSemantics(find.bySemanticsLabel('Snooze all'));
    expect(snoozeAll, isSemantics(isHeader: true));
    expect(snoozeAll.rect.height, lessThan(60));

    for (final (key, spoken) in [
      ('5_min', 'Snooze 5 minutes'),
      ('30_min', 'Snooze 30 minutes'),
      ('1_hour', 'Snooze 1 hour'),
    ]) {
      final tile = find.bySemanticsLabel(
        RegExp('^${RegExp.escape(spoken)}, rings at \\S+'),
      );
      expect(tile, findsOneWidget, reason: key);
      expect(
        tester.getSemantics(tile),
        isSemantics(isButton: true, hasTapAction: true),
      );
      expect(
        tester.getSemantics(tile).rect.height,
        lessThanOrEqualTo(kAwAlarmTileHeight + 1),
      );
    }

    final order = [
      for (final node in tester.semantics.simulatedAccessibilityTraversal())
        if (node.label.isNotEmpty) node.label,
    ];
    int at(String p, [int from = 0]) =>
        order.indexWhere((l) => l.startsWith(p), from);
    final card1 = at('Task 1');
    final card2 = at('Task 2');
    final expected = [
      at('2 URGENT REMINDERS'),
      card1,
      at('Task 1: Snooze'),
      at('Task 1: Acknowledge'),
      card2,
      at('Task 2: Snooze'),
      at('Task 2: Acknowledge'),
      at('Snooze all'),
      at('Snooze 5 minutes'),
      at('Snooze 30 minutes'),
      at('Snooze 1 hour'),
      at('Pick a time'),
      at('Acknowledge all'),
    ];
    expect(expected, everyElement(greaterThanOrEqualTo(0)), reason: '$order');
    expect(expected, orderedEquals([...expected]..sort()), reason: '$order');
    semantics.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  // ── S0 (CI on Flutter 3.44): dispose() constructs nothing ────────────────

  testWidgets('a list that never pulsed disposes without creating a '
      'controller', (tester) async {
    // Reduced motion: the header badge never pulses, so a lazily built pulse
    // controller would first be constructed inside dispose(), on a
    // deactivated element — Flutter 3.44 throws there and the minute timer
    // stays pending.
    await pumpList(tester, [row('1', now), row('2', now)], reduceMotion: true);
    expect(find.byType(AlarmRingList), findsOneWidget);

    final created = await tickersCreatedDuring(
      () => tester.pumpWidget(const SizedBox()),
    );

    expect(created, isEmpty);
    expect(tester.takeException(), isNull);
  });

  // ── S3 (Y-03): list mode for a screen reader ─────────────────────────────

  testWidgets('list mode is not one labelled group; row buttons name their '
      'task', (tester) async {
    final semantics = tester.ensureSemantics();
    // A fresh browser: the silent sentence shows under the header (Y-03 was
    // seen with it; it named the whole list).
    await pumpList(
      tester,
      [
        row('1', now.add(const Duration(seconds: 1))),
        row('2', now.add(const Duration(seconds: 2))),
      ],
      extra: [alarmOpensSilentProvider.overrideWithValue(true)],
    );
    expect(find.byKey(const Key('alarm-silent-default')), findsOneWidget);

    // Nothing above the header carries a name: the group is a plain
    // container, as on the single layout (X-07).
    final head = tester.getSemantics(
      find.bySemanticsLabel(RegExp(r'^2 URGENT REMINDERS')),
    );
    final named = <String>[];
    for (var node = head.parent; node != null; node = node.parent) {
      if (node.label.isNotEmpty) named.add(node.label);
    }
    expect(named, isEmpty);

    // The sentence is a node of its own, with no child under it.
    final sentence = tester.getSemantics(
      find.bySemanticsLabel(RegExp(r'^Alarms in this browser are silent')),
    );
    expect(sentence.childrenCount, 0);

    // Each row's buttons say which task they answer; the pills still read
    // "Snooze" and "Acknowledge".
    for (final n in ['1', '2']) {
      for (final action in ['Snooze', 'Acknowledge']) {
        final button = find.bySemanticsLabel('Task $n: $action');
        expect(button, findsOneWidget, reason: 'Task $n: $action');
        expect(
          tester.getSemantics(button),
          isSemantics(isButton: true, hasTapAction: true),
        );
      }
      final pill = find.byKey(Key('alarm-row-snooze-${id('T$n')}'));
      expect(
        find.descendant(of: pill, matching: find.text('Snooze')),
        findsOneWidget,
      );
    }
    semantics.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  // ── S3 (run 7): the keyboard after a row's sheet ─────────────────────────

  for (final close in ['the scrim', 'a snooze that takes the row away']) {
    testWidgets('after the row sheet closes Enter acknowledges all '
        '(closed by $close)', (tester) async {
      final rows = ValueNotifier([row('1', now), row('2', now), row('3', now)]);
      addTearDown(rows.dispose);
      // A row answered leaves the list, as the overlay's state does.
      final spy = _SpyOverlay(
        onRow: (task) => rows.value = [
          for (final r in rows.value)
            if (r.taskId != task) r,
        ],
      );
      await pumpList(
        tester,
        rows.value,
        live: rows,
        size: const Size(1280, 800),
        extra: [alarmOverlayControllerProvider.overrideWith(() => spy)],
      );

      // A web screen reader's click focuses the node it presses: the row's
      // "Snooze" holds the focus when its sheet opens.
      final pill = find.byKey(Key('alarm-row-snooze-${id('T1')}'));
      Focus.of(
        tester.element(
          find.descendant(of: pill, matching: find.text('Snooze')),
        ),
      ).requestFocus();
      await tester.tap(pill);
      // The header badge pulses forever: the sheet's 250 ms in fixed steps.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const Key('alarm-sheet-open')), findsOneWidget);
      if (close == 'the scrim') {
        await tester.tapAt(const Offset(8, 8));
      } else {
        await tester.tap(find.byKey(const Key('alarm-sheet-snooze-5_min')));
      }
      // While the sheet is still sliding out, the focus is already back on
      // the list. On the web its focused node is a DOM element: left in the
      // sheet, the element's removal blurs the page and parks the focus
      // outside every widget, so Enter and 1–3 reached nothing (run 7).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const Key('alarm-sheet-open')), findsOneWidget);
      final focused = FocusManager.instance.primaryFocus?.context;
      expect(
        find.descendant(
          of: find.byKey(const Key('alarm-acknowledge-all')),
          matching: find.byElementPredicate((e) => e == focused),
        ),
        findsOneWidget,
        reason: '${FocusManager.instance.primaryFocus}',
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const Key('alarm-sheet-open')), findsNothing);
      expect(spy.rowAnswers, close == 'the scrim' ? isEmpty : [id('T1')]);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(spy.acknowledgedAll, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.pump();
      expect(spy.snoozedAll, hasLength(1));
      await tester.pumpWidget(const SizedBox());
    });
  }
}

/// The overlay controller with its bulk answers recorded instead of written.
class _SpyOverlay extends AlarmOverlayController {
  _SpyOverlay({this.onRow});

  final void Function(String taskId)? onRow;
  int acknowledgedAll = 0;
  final List<String> rowAnswers = [];
  final List<DateTime> snoozedAll = [];

  @override
  Future<bool> acknowledgeAll({void Function()? onSaved}) async {
    acknowledgedAll++;
    return true;
  }

  @override
  Future<bool> snoozeAll(DateTime until, {void Function()? onSaved}) async {
    snoozedAll.add(until);
    return true;
  }

  @override
  Future<bool> actOnRow(
    String taskId,
    AlarmRowAction action, {
    void Function()? onSaved,
  }) async {
    rowAnswers.add(taskId);
    onRow?.call(taskId);
    return true;
  }
}
