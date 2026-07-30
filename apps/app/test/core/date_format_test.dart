import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/core/date_format.dart';

void main() {
  group('awInitialPickerDate (OPH-173, round 9 #4)', () {
    final now = DateTime(2026, 7, 28, 14, 30);

    test('an empty field opens on TOMORROW', () {
      expect(awInitialPickerDate(now: now), DateTime(2026, 7, 29));
    });

    test('an existing value always wins', () {
      final current = DateTime(2026, 8, 15, 9);
      expect(
        awInitialPickerDate(
          current: current,
          anchor: DateTime(2026, 9, 1),
          now: now,
        ),
        current,
      );
    });

    test('with no value, the anchor wins over tomorrow', () {
      // A reminder opens on its task's due day, not on tomorrow.
      final due = DateTime(2026, 8, 3, 23, 59);
      expect(awInitialPickerDate(anchor: due, now: now), due);
    });

    test('rolls over month and year ends', () {
      expect(
        awInitialPickerDate(now: DateTime(2026, 7, 31, 8)),
        DateTime(2026, 8, 1),
      );
      expect(
        awInitialPickerDate(now: DateTime(2026, 12, 31, 23, 59)),
        DateTime(2027, 1, 1),
      );
    });

    test('crossing a DST boundary still lands on the next calendar day', () {
      // Europe/Istanbul has no DST today, but the constructor-based arithmetic
      // is what makes this safe anywhere: +1 day, not +24 hours.
      final springForward = DateTime(2026, 3, 28, 23, 30);
      expect(awInitialPickerDate(now: springForward), DateTime(2026, 3, 29));
    });
  });

  group('awFormat* (OPH-174, round 9 #5)', () {
    // The sample the Settings picker previews: 31.12.2026 23:59.
    final sample = kAwDateFormatSample;

    test('every offered format renders the sample the way it promises', () {
      expect(
        awFormatDateTime(sample, format: 'dmy_dot', locale: 'tr'),
        '31.12.2026 23:59',
        reason: "round 9 asked for exactly this shape",
      );
      expect(
        awFormatDateTime(sample, format: 'dmy_slash', locale: 'tr'),
        '31/12/2026 23:59',
      );
      expect(
        awFormatDateTime(sample, format: 'iso', locale: 'tr'),
        '2026-12-31 23:59',
      );
      expect(
        awFormatDateTime(sample, format: 'dmy_long', locale: 'tr'),
        '31 Aralık 2026 23:59',
      );
      expect(
        awFormatDateTime(sample, format: 'mdy_12h', locale: 'en'),
        '12/31/2026 11:59 PM',
        reason: 'an explicit `h:mm a` pattern keeps a plain space',
      );
    });

    test('"system" follows the language (tr → 24h, en → 12h)', () {
      expect(
        awFormatDateTime(sample, format: kAwSystemDateFormat, locale: 'tr'),
        '31.12.2026 23:59',
      );
      // CLDR puts a narrow no-break space before PM, so assert the parts —
      // pinning the exact whitespace would break on the next intl bump.
      final en = awFormatDateTime(
        sample,
        format: kAwSystemDateFormat,
        locale: 'en',
      );
      expect(en, startsWith('12/31/2026 '));
      expect(en, contains('11:59'));
      expect(en, contains('PM'), reason: 'en follows its own 12h clock');
    });

    test('a junk or retired preference falls back to "system"', () {
      expect(awDateFormatSpec('nope').id, kAwSystemDateFormat);
      expect(awDateFormatSpec(null).id, kAwSystemDateFormat);
      expect(
        awFormatDateTime(sample, format: 'nope', locale: 'tr'),
        awFormatDateTime(sample, format: kAwSystemDateFormat, locale: 'tr'),
      );
    });

    test('the row form drops the year and can drop the time (D4)', () {
      expect(
        awFormatShort(sample, format: 'dmy_dot', locale: 'tr'),
        '31 Ara, 23:59',
      );
      expect(
        awFormatShort(sample, format: 'dmy_dot', locale: 'tr', withTime: false),
        '31 Ara',
      );
    });

    test('date and time parts are usable on their own', () {
      expect(
        awFormatDate(sample, format: 'dmy_dot', locale: 'tr'),
        '31.12.2026',
      );
      expect(awFormatTime(sample, format: 'dmy_dot', locale: 'tr'), '23:59');
      expect(awFormatTime(sample, format: 'mdy_12h', locale: 'en'), '11:59 PM');
    });

    test('UTC instants are rendered in local time', () {
      final utc = DateTime.utc(2026, 12, 31, 23, 59);
      expect(
        awFormatDateTime(utc, format: 'iso', locale: 'tr'),
        awFormatDateTime(utc.toLocal(), format: 'iso', locale: 'tr'),
      );
    });
  });

  // ── The custom snooze's date/time composition ─────────────────────────────
  //
  // The alarm ring screen suggests "half an hour from now" as the snooze time
  // and opens its date picker on the same instant. Those two MUST share an
  // anchor: anchoring the date on `now` while taking the time from `now + 30m`
  // composes today-at-00:10 whenever the alarm rings after 23:30 — about a day
  // in the past — and the screen then discarded the tap in silence. It only
  // ever failed on CI, which runs in UTC; on a UTC+3 machine the window is
  // 20:30–21:00 local and nobody was testing then.
  //
  // Driving a Material time picker to a chosen minute is brittle, so the rule
  // is asserted here as arithmetic, at every hour of the day.
  group('custom snooze anchoring', () {
    DateTime composed(DateTime now) {
      final suggested = now.add(const Duration(minutes: 30));
      final date = awInitialPickerDate(anchor: suggested, now: now);
      // What the screen builds once both pickers are accepted untouched.
      return DateTime(
        date.year,
        date.month,
        date.day,
        suggested.hour,
        suggested.minute,
      );
    }

    test('accepting both defaults always lands in the future', () {
      for (var hour = 0; hour < 24; hour++) {
        for (final minute in [0, 29, 30, 31, 45, 59]) {
          final now = DateTime(2026, 7, 31, hour, minute);
          expect(
            composed(now).isAfter(now),
            isTrue,
            reason: 'a snooze offered at $hour:$minute landed in the past',
          );
        }
      }
    });

    test(
      'the half hour before midnight rolls the DATE, not just the clock',
      () {
        final now = DateTime(2026, 7, 31, 23, 40);
        final until = composed(now);
        expect(until.day, 1, reason: 'it must roll into 1 August');
        expect(until.month, 8);
        expect(until.hour, 0);
        expect(until.minute, 10);
      },
    );

    test('a month boundary rolls the month too', () {
      final until = composed(DateTime(2026, 12, 31, 23, 55));
      expect(
        [until.year, until.month, until.day],
        [2027, 1, 1],
        reason: 'the last minutes of a year are still a valid time to snooze',
      );
    });
  });
}
