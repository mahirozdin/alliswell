import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/home/month_calendar.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';

/// OPH-359 — UI-AUDIT #60: Home's month calendar speaks the app's language.
///
/// The month and the weekday names were fixed English arrays, and the screen
/// reader's ", today" / ", has tasks" were English literals — so a Turkish
/// Home said "October 2026 · Mon Tue Wed" beside a date picker that said
/// "Ekim 2026".
void main() {
  tearDown(() => AwI18n.instance.setActiveCached(const Locale('en')));

  // A marked day that is never today, whatever today is.
  int markedDay() => DateTime.now().day == 3 ? 4 : 3;

  Future<void> pump(WidgetTester tester, {required DateTime month}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAwTheme(Brightness.light),
        home: Scaffold(
          body: SingleChildScrollView(
            child: MonthCalendar(
              markedDays: {DateTime(month.year, month.month, markedDay())},
              selectedDay: null,
              onDaySelected: (_) {},
              initialMonth: month,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('UI-AUDIT #60: Turkish month, Turkish weekdays', (tester) async {
    AwI18n.instance.setActiveCached(const Locale('tr'));
    await pump(tester, month: DateTime(2026, 10));
    expect(find.text('Ekim 2026'), findsOneWidget);
    expect(find.text('Pzt'), findsOneWidget);
    expect(find.text('Paz'), findsOneWidget);
    expect(find.text('October 2026'), findsNothing);
    expect(find.text('Mon'), findsNothing);
  });

  testWidgets('UI-AUDIT #60: the English build still reads in English', (
    tester,
  ) async {
    AwI18n.instance.setActiveCached(const Locale('en'));
    await pump(tester, month: DateTime(2026, 10));
    expect(find.text('October 2026'), findsOneWidget);
    expect(find.text('Mon'), findsOneWidget);
  });

  testWidgets('a day selected from outside shows its own month', (
    tester,
  ) async {
    // A widget event row (`alliswell://day/…`) can select a day in another
    // month; the grid follows it, or the selection would be invisible.
    AwI18n.instance.setActiveCached(const Locale('en'));
    Widget grid(DateTime? selected) => MaterialApp(
      theme: buildAwTheme(Brightness.light),
      home: Scaffold(
        body: SingleChildScrollView(
          child: MonthCalendar(
            markedDays: const {},
            selectedDay: selected,
            onDaySelected: (_) {},
            initialMonth: DateTime(2026, 10),
          ),
        ),
      ),
    );
    await tester.pumpWidget(grid(null));
    expect(find.text('October 2026'), findsOneWidget);
    await tester.pumpWidget(grid(DateTime(2026, 12, 3)));
    await tester.pumpAndSettle();
    expect(find.text('December 2026'), findsOneWidget);
  });

  testWidgets('UI-AUDIT #60: a day is read in the app\'s language, once', (
    tester,
  ) async {
    AwI18n.instance.setActiveCached(const Locale('tr'));
    final handle = tester.ensureSemantics();
    final now = DateTime.now();
    await pump(tester, month: DateTime(now.year, now.month));
    final today = find.byKey(
      Key('calendar-day-${now.year}-${now.month}-${now.day}'),
    );
    final label = tester.getSemantics(today).label;
    expect(label, '${now.day}, ${'calendar.a11yToday'.tr()}');
    expect(label, isNot(contains('today')));

    final marked = find.byKey(
      Key('calendar-day-${now.year}-${now.month}-${markedDay()}'),
    );
    expect(
      tester.getSemantics(marked).label,
      contains('calendar.a11yHasTasks'.tr()),
    );
    handle.dispose();
  });

  // ── OPH-401 (U-04, DESIGN §47 W1–W2): the week strip ─────────────────────

  int cells(WidgetTester tester) => find
      .byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key as ValueKey<String>).value.startsWith('calendar-day-'),
      )
      .evaluate()
      .length;

  Future<List<String>> pumpWeek(
    WidgetTester tester, {
    DateTime? selected,
    DateTime? initial,
  }) async {
    final modes = <String>[];
    var mode = AwCalendarMode.week;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAwTheme(Brightness.light),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              child: MonthCalendar(
                markedDays: {DateTime(2026, 10, 2)},
                selectedDay: selected,
                onDaySelected: (_) {},
                initialMonth: initial ?? DateTime(2026, 10),
                mode: mode,
                onModeChanged: (next) {
                  modes.add(next.name);
                  setState(() => mode = next);
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return modes;
  }

  testWidgets('week mode draws one row of seven days, Monday first', (
    tester,
  ) async {
    AwI18n.instance.setActiveCached(const Locale('en'));
    await pumpWeek(tester);
    expect(cells(tester), 7);
    // 1 Oct 2026 is a Thursday: its week runs 28 Sep – 4 Oct.
    expect(find.byKey(const Key('calendar-day-2026-9-28')), findsOneWidget);
    expect(find.byKey(const Key('calendar-day-2026-10-4')), findsOneWidget);
    expect(find.text('October 2026'), findsOneWidget);
    // ≈64 pt: weekday 11 + day 17 in a 32 pt circle + the dot.
    final strip = tester.getSize(find.byKey(const Key('calendar-week-strip')));
    expect(strip.height, inInclusiveRange(56, 68));
    final day = find.byKey(const Key('calendar-day-2026-10-1'));
    expect(tester.getSize(day).height, greaterThanOrEqualTo(48));
  });

  testWidgets('the arrows move a week; the toggle asks for the month', (
    tester,
  ) async {
    AwI18n.instance.setActiveCached(const Locale('en'));
    final modes = await pumpWeek(tester);
    await tester.tap(find.byTooltip('Next week'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('calendar-day-2026-10-5')), findsOneWidget);
    expect(find.byKey(const Key('calendar-day-2026-10-4')), findsNothing);
    await tester.tap(find.byTooltip('Previous week'));
    await tester.tap(find.byTooltip('Previous week'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('calendar-day-2026-9-21')), findsOneWidget);

    final toggle = find.byKey(const Key('calendar-mode-toggle'));
    expect(tester.getSize(toggle), const Size(48, 48));
    expect(find.byTooltip('Show month'), findsOneWidget);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(modes, ['month']);
    expect(cells(tester), 42);
    expect(find.byTooltip('Show week'), findsOneWidget);
  });

  testWidgets('week mode opens on the selected day\'s week, today filled', (
    tester,
  ) async {
    AwI18n.instance.setActiveCached(const Locale('en'));
    await pumpWeek(tester, selected: DateTime(2026, 11, 18));
    expect(find.byKey(const Key('calendar-day-2026-11-16')), findsOneWidget);
    expect(find.byKey(const Key('calendar-day-2026-11-22')), findsOneWidget);
    expect(find.text('November 2026'), findsOneWidget);
  });

  testWidgets('without onModeChanged (the wide panel) there is no toggle', (
    tester,
  ) async {
    await pump(tester, month: DateTime(2026, 10));
    expect(find.byKey(const Key('calendar-mode-toggle')), findsNothing);
    expect(cells(tester), 42);
  });
}
