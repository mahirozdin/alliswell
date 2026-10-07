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
}
