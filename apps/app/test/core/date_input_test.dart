// The one date+time input path (core/date_input.dart).
//
// OPH-471 (walkthrough W-06): in a 24-hour locale (tr) the picker draws a
// 24-hour dial with no AM/PM toggle, but Flutter's text-entry parser reads
// MediaQuery.alwaysUse24HourFormat — false on web and desktop — and treated a
// typed "05" as a 12-hour value in the current half of the day. From the
// default 23:59 (PM) the task was saved at 17:25. The fix forces the flag on
// whenever the locale's own clock is 24-hour, whatever the user's DISPLAY
// format says.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/core/date_input.dart';
import 'package:alliswell/src/core/persisted_prefs.dart';

/// Opens [awPickDateTime] from a button, the way the create sheet does, with
/// the platform reporting "no 24-hour preference" (web, desktop, a phone with
/// the system 24-hour switch off).
Future<DateTime? Function()> _openPicker(
  WidgetTester tester, {
  required Locale locale,
  required String dateFormat,
}) async {
  DateTime? picked;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dateFormatProvider.overrideWith(
          () => PersistedChoice(kDateFormatPrefKey, fallback: dateFormat),
        ),
      ],
      child: MaterialApp(
        locale: locale,
        supportedLocales: const [Locale('en'), Locale('tr')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
          child: child!,
        ),
        home: Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () async {
              picked = await awPickDateTime(context, ref);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return () => picked;
}

/// Confirms the date step, switches the clock to text entry and types
/// [hour]:[minute].
Future<void> _typeTime(
  WidgetTester tester, {
  required String ok,
  required String hour,
  required String minute,
}) async {
  await tester.tap(find.text(ok));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.keyboard_outlined));
  await tester.pumpAndSettle();
  final fields = find.byType(TextField);
  expect(fields, findsNWidgets(2));
  await tester.enterText(fields.at(0), hour);
  await tester.enterText(fields.at(1), minute);
}

void main() {
  group('typing 05:25 in the time picker saves 05:25 in both hour formats', () {
    for (final format in const ['dmy_dot', 'mdy_12h']) {
      testWidgets('tr locale, user format $format', (tester) async {
        final result = await _openPicker(
          tester,
          locale: const Locale('tr'),
          dateFormat: format,
        );
        await _typeTime(tester, ok: 'Tamam', hour: '05', minute: '25');
        // The locale's clock is 24-hour: no AM/PM toggle to say otherwise.
        expect(find.text('ÖS'), findsNothing);
        await tester.tap(find.text('Tamam'));
        await tester.pumpAndSettle();
        final picked = result();
        expect(picked, isNotNull);
        expect((picked!.hour, picked.minute), (5, 25));
      });
    }

    testWidgets('tr locale: an afternoon hour typed as 17 is accepted', (
      tester,
    ) async {
      final result = await _openPicker(
        tester,
        locale: const Locale('tr'),
        dateFormat: 'mdy_12h',
      );
      await _typeTime(tester, ok: 'Tamam', hour: '17', minute: '05');
      await tester.tap(find.text('Tamam'));
      await tester.pumpAndSettle();
      final picked = result();
      expect(picked, isNotNull);
      expect((picked!.hour, picked.minute), (17, 5));
    });

    testWidgets('en locale keeps its 12-hour clock: AM + 05:25 is 05:25', (
      tester,
    ) async {
      final result = await _openPicker(
        tester,
        locale: const Locale('en'),
        dateFormat: 'mdy_12h',
      );
      await _typeTime(tester, ok: 'OK', hour: '05', minute: '25');
      // A 12-hour locale still shows its AM/PM toggle; the hour follows it.
      await tester.tap(find.text('AM'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      final picked = result();
      expect(picked, isNotNull);
      expect((picked!.hour, picked.minute), (5, 25));
    });
  });

  testWidgets('a dial pick in tr keeps the hour the dial shows', (
    tester,
  ) async {
    final result = await _openPicker(
      tester,
      locale: const Locale('tr'),
      dateFormat: 'mdy_12h',
    );
    await tester.tap(find.text('Tamam'));
    await tester.pumpAndSettle();
    // The default 23:59 stays 23:59 when confirmed on the dial.
    await tester.tap(find.text('Tamam'));
    await tester.pumpAndSettle();
    final picked = result();
    expect(picked, isNotNull);
    expect((picked!.hour, picked.minute), (23, 59));
  });
}
