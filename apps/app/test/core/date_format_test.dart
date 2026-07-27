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
}
