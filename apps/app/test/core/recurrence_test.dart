import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/core/recurrence.dart';

/// ADR-0020 §6: this port and `apps/api/src/lib/recurrence.js` must agree day
/// for day. Both suites read the same fixture — the ADR-0013 fold arrangement.
void main() {
  final fixture =
      jsonDecode(
            File('test/fixtures/recurrence_parity.json').readAsStringSync(),
          )
          as Map<String, dynamic>;

  group('recurrence — cross-stack parity fixture', () {
    for (final entry
        in (fixture['cases'] as List).cast<Map<String, dynamic>>()) {
      test(entry['name'] as String, () {
        final rule = AwRepeatRule.fromJson(entry['rule']);
        expect(rule, isNotNull, reason: 'rule must parse');
        final days = awExpandOccurrences(
          rule!,
          anchor: entry['anchor'] as String,
          from: entry['from'] as String?,
          to: entry['to'] as String?,
          max: (entry['max'] as int?) ?? kAwMaxOccurrences,
        );
        expect(days, (entry['expected'] as List).cast<String>());
      });
    }
  });

  group('recurrence — the rule model', () {
    test('round-trips through JSON without losing a field', () {
      const rule = AwRepeatRule(
        freq: AwRepeatFreq.monthly,
        interval: 2,
        byWeekday: [AwWeekdayPick('MO')],
        byMonthDay: [23, 24, 25, 26, 27, 28, 29],
        end: AwRepeatEnd.count(10),
      );
      final back = AwRepeatRule.fromJson(jsonDecode(jsonEncode(rule.toJson())));
      expect(back, rule);
    });

    test('survives a rule written by the server (ordinal nulls included)', () {
      final rule = AwRepeatRule.fromJson({
        'freq': 'monthly',
        'interval': 1,
        'byWeekday': [
          {'day': 'TU', 'ordinal': 2},
        ],
        'end': {'type': 'never'},
      });
      expect(rule!.byWeekday.single.ordinal, 2);
      expect(rule.end.isNever, isTrue);
    });

    test('rejects nonsense instead of guessing', () {
      expect(AwRepeatRule.fromJson({'freq': 'hourly'}), isNull);
      expect(AwRepeatRule.fromJson('every day'), isNull);
      expect(
        awValidateRepeatRule(
          const AwRepeatRule(
            freq: AwRepeatFreq.weekly,
            byWeekday: [AwWeekdayPick('MO', ordinal: 2)],
          ),
        ),
        isNotNull,
      );
    });
  });

  group('recurrence — the preview the dialog asks for', () {
    test('returns exactly five days from today', () {
      final days = awExpandOccurrences(
        const AwRepeatRule(freq: AwRepeatFreq.daily),
        anchor: '2026-01-01',
        max: 5,
      );
      expect(days, [
        '2026-01-01',
        '2026-01-02',
        '2026-01-03',
        '2026-01-04',
        '2026-01-05',
      ]);
    });

    test('shows the clamp, so the user sees the system did not break', () {
      final days = awExpandOccurrences(
        const AwRepeatRule(freq: AwRepeatFreq.monthly, byMonthDay: [31]),
        anchor: '2026-01-31',
        max: 3,
      );
      expect(days, ['2026-01-31', '2026-02-28', '2026-03-31']);
    });

    test('awDayKey formats a local date the engine can read back', () {
      expect(awDayKey(DateTime(2026, 2, 5)), '2026-02-05');
      expect(awLastDayOfMonth(2028, 2), 29);
    });
  });
}
