import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/core/recurrence.dart';
import 'package:alliswell/src/core/recurrence_text.dart';
import 'package:alliswell/src/features/tasks/ui/repeat_dialog.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// OPH-207 — the recurrence surface (DESIGN §25).
///
/// Two promises are pinned here: the rule reads as a SENTENCE in each language
/// (built from the rule, never from translated fragments), and the dialog's
/// "Sonraki 5" preview tells the truth about clamping — which is the only way
/// a user can see that "the 31st" did not break in February.
Future<void> pumpDialog(
  WidgetTester tester, {
  AwRepeatRule? initial,
  DateTime? anchor,
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
                  anchor: anchor ?? DateTime(2026, 1, 31),
                  initial: initial,
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

void main() {
  setUp(() async {
    await AwI18n.instance.setLocale(const Locale('tr'));
  });

  group('the rule as a sentence (R2)', () {
    test('Turkish and English build their own word order', () async {
      const rule = AwRepeatRule(freq: AwRepeatFreq.monthly, byMonthDay: [-1]);
      // The sentence follows the APP's language (the i18n facade is global —
      // ADR-0009); the `locale` argument only shapes dates inside it.
      expect(
        awRepeatSentence(rule, dateFormat: 'dmy_dot', locale: 'tr'),
        'Her ayın son günü · bitiş yok',
      );
      await AwI18n.instance.setLocale(const Locale('en'));
      expect(
        awRepeatSentence(rule, dateFormat: 'dmy_dot', locale: 'en'),
        'Every month on the last day · no end',
      );
      await AwI18n.instance.setLocale(const Locale('tr'));
    });

    test('scenario C reads as itself, not as a seven-day window', () {
      final rule = awAfterDayRule(day: 22, weekday: 'MO');
      expect(
        awRepeatSentence(rule, dateFormat: 'dmy_dot', locale: 'tr'),
        'Her ayın 22. gününden sonraki ilk Pazartesi · bitiş yok',
      );
    });

    test('the nth weekday and the interval get their own forms', () {
      const rule = AwRepeatRule(
        freq: AwRepeatFreq.monthly,
        interval: 2,
        byWeekday: [AwWeekdayPick('TU', ordinal: 2)],
        end: AwRepeatEnd.count(10),
      );
      expect(
        awRepeatSentence(rule, dateFormat: 'dmy_dot', locale: 'tr'),
        '2 ayda bir, ayın 2. Salı günü · 10 kez',
      );
    });

    test('five weekdays say "weekdays" instead of listing themselves', () {
      const rule = AwRepeatRule(
        freq: AwRepeatFreq.weekly,
        byWeekday: [
          AwWeekdayPick('MO'),
          AwWeekdayPick('TU'),
          AwWeekdayPick('WE'),
          AwWeekdayPick('TH'),
          AwWeekdayPick('FR'),
        ],
      );
      expect(
        awRepeatSentence(rule, dateFormat: 'dmy_dot', locale: 'tr'),
        'Her hafta hafta içi her gün · bitiş yok',
      );
    });

    test('scenario C round-trips through its recogniser', () {
      final rule = awAfterDayRule(day: 22, weekday: 'MO');
      final read = awAfterDayOf(rule);
      expect(read?.day, 22);
      expect(read?.weekday, 'MO');
      // A rule that merely looks similar is not mistaken for scenario C.
      expect(
        awAfterDayOf(
          const AwRepeatRule(freq: AwRepeatFreq.monthly, byMonthDay: [23, 25]),
        ),
        isNull,
      );
    });
  });

  group('the dialog (R1, R3, R4)', () {
    testWidgets('opens on presets and previews the next five days', (
      tester,
    ) async {
      await pumpDialog(tester);
      expect(find.byKey(const Key('repeat-dialog')), findsOneWidget);
      expect(find.byKey(const Key('repeat-preset-monthly')), findsOneWidget);
      expect(find.text('Sonraki 5'), findsOneWidget);
    });

    testWidgets('the preview shows the clamp — February reads 28', (
      tester,
    ) async {
      await pumpDialog(tester, anchor: DateTime(2026, 1, 31));
      // The anchor is the 31st, so "every month" means the 31st, clamped.
      expect(
        find.byKey(const Key('repeat-preview-2026-02-28')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('repeat-preview-2026-01-31')),
        findsOneWidget,
      );
    });

    testWidgets('cancelling returns null — nothing half-configured survives', (
      tester,
    ) async {
      AwRepeatRule? result;
      var called = false;
      await pumpDialog(
        tester,
        onClosed: (rule) {
          result = rule;
          called = true;
        },
      );
      await tester.tap(find.byKey(const Key('repeat-cancel')));
      await tester.pumpAndSettle();
      expect(called, isTrue);
      expect(result, isNull);
    });

    testWidgets('saving hands back the rule the presets built', (tester) async {
      AwRepeatRule? result;
      await pumpDialog(tester, onClosed: (rule) => result = rule);
      await tester.tap(find.byKey(const Key('repeat-preset-weekdays')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('repeat-save')));
      await tester.pumpAndSettle();
      expect(result?.freq, AwRepeatFreq.weekly);
      expect(result?.byWeekday.length, 5);
    });

    testWidgets('an existing rule comes back into the dialog unchanged', (
      tester,
    ) async {
      final initial = awAfterDayRule(day: 22, weekday: 'MO');
      AwRepeatRule? result;
      await pumpDialog(
        tester,
        initial: initial,
        onClosed: (rule) => result = rule,
      );
      expect(find.byKey(const Key('repeat-sentence')), findsOneWidget);
      await tester.tap(find.byKey(const Key('repeat-save')));
      await tester.pumpAndSettle();
      expect(result, initial);
    });
  });
}
