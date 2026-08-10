import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/core/date_format.dart';
import 'package:alliswell/src/features/tasks/data/task.dart';
import 'package:alliswell/src/features/widgets/widget_clock.dart';
import 'package:alliswell/src/features/widgets/widget_snapshot.dart';
import 'package:alliswell/src/i18n/i18n.dart';

/// The widget header's clock (OPH-253, DESIGN §31 C1–C5).
///
/// The clock is DRAWN natively — iOS by `DateFormatter`, Android by `TextClock`
/// — but every decision about it is made here: which pattern, and whether the
/// entry being rendered is still young enough to be telling the truth. These
/// are the tests for those decisions; `widget_clock_native_test.dart` pins that
/// the native files carry the same constants.
void main() {
  setUp(() => AwI18n.instance.setActiveCached(const Locale('en')));

  group('widgetClockPattern (C2)', () {
    test('the system default follows the locale, not a hardcoded clock', () {
      // English is a 12-hour locale, Turkish a 24-hour one. A clock that shows
      // 24-hour time to someone who set 12-hour is not their clock.
      //
      // Matched in parts: CLDR separates the AM/PM marker with a NARROW NO-BREAK
      // SPACE, and pinning invisible whitespace is how widget_core_test already
      // got burned on the row times.
      final en = widgetClockPattern(format: kAwSystemDateFormat, locale: 'en');
      expect(en, startsWith('h:mm'));
      expect(en, endsWith('a'));
      expect(
        widgetClockPattern(format: kAwSystemDateFormat, locale: 'tr'),
        'HH:mm',
      );
    });

    test('the CLDR narrow no-break space survives into the pattern', () {
      // U+202F, not a plain space — and it must STAY. The task rows under the
      // clock are formatted from the same CLDR data and carry it too; if the
      // header normalised it away, the clock and the rows would space their
      // AM/PM differently on the very same widget (OPH-174's whole point).
      // Both native sides treat it as a pattern literal.
      expect(
        widgetClockPattern(format: kAwSystemDateFormat, locale: 'en'),
        contains('\u202F'),
      );
    });

    test('a chosen format wins over the locale — in BOTH directions', () {
      // OPH-174: the widget speaks the app's format. Someone on a Turkish app
      // who picked the 12-hour format gets a 12-hour header, and an English
      // user who picked a 24-hour format gets a 24-hour one — otherwise the
      // header and the rows under it would disagree.
      expect(widgetClockPattern(format: 'mdy_12h', locale: 'tr'), 'h:mm a');
      expect(widgetClockPattern(format: 'dmy_dot', locale: 'en'), 'HH:mm');
      expect(widgetClockPattern(format: 'iso', locale: 'en'), 'HH:mm');
    });

    test('a retired or corrupted preference falls back, never throws', () {
      // The `parseTaskTime` rule: a bad persisted value must not break a screen
      // — here it must not blank the widget's whole header.
      expect(
        widgetClockPattern(format: 'a-format-we-deleted', locale: 'en'),
        widgetClockPattern(format: kAwSystemDateFormat, locale: 'en'),
      );
    });
  });

  group('widgetClockIsFresh (C3 — the honesty gate)', () {
    final entry = DateTime(2026, 8, 10, 14, 37);

    test('inside the threshold the clock stays', () {
      expect(
        widgetClockIsFresh(
          entryDate: entry,
          renderedAt: entry.add(const Duration(seconds: 89)),
        ),
        isTrue,
      );
    });

    test('past the threshold the clock is dropped', () {
      // A wrong clock is worse than no clock: past 90 s at least one minute
      // entry was never drawn, so the number on screen is not the time.
      expect(
        widgetClockIsFresh(
          entryDate: entry,
          renderedAt: entry.add(const Duration(seconds: 91)),
        ),
        isFalse,
      );
    });

    test('an entry rendered early is not stale', () {
      // WidgetKit may draw an entry slightly before its date. A clock that
      // vanished for being too FRESH would be its own bug.
      expect(
        widgetClockIsFresh(
          entryDate: entry,
          renderedAt: entry.subtract(const Duration(seconds: 30)),
        ),
        isTrue,
      );
    });

    test('a whole stale day is dropped, not wrapped around', () {
      expect(
        widgetClockIsFresh(
          entryDate: entry,
          renderedAt: entry.add(const Duration(days: 1)),
        ),
        isFalse,
      );
    });
  });

  group('the snapshot carries the pattern (v3)', () {
    Task task(String id, DateTime due) => Task(
      id: id,
      workspaceId: 'W1',
      title: id,
      status: 'open',
      priority: 'none',
      timezone: 'Europe/Istanbul',
      isUrgent: false,
      requiresAcknowledgement: false,
      sortOrder: 0,
      revision: 1,
      dueAt: due,
    );

    final now = DateTime(2026, 8, 10, 14, 37);

    test('clockFormat rides in the JSON and matches the row times', () {
      final snap = buildWidgetSnapshot([
        task('t', DateTime(2026, 8, 10, 16)),
      ], now: now);

      expect(snap.version, 3);
      expect(snap.clockFormat, 'h:mm\u202Fa');
      expect(snap.toJson()['clockFormat'], 'h:mm\u202Fa');
      // The header and the row it sits above resolve from the same preference —
      // both 12-hour here, so they cannot contradict each other on screen.
      expect(snap.buckets.single.items.single.time, contains('PM'));
    });

    test('a chosen 24-hour format reaches the widget as one', () {
      final snap = buildWidgetSnapshot(
        [task('t', DateTime(2026, 8, 10, 16))],
        now: now,
        dateFormat: 'dmy_dot',
      );
      expect(snap.clockFormat, 'HH:mm');
      expect(snap.buckets.single.items.single.time, '16:00');
    });
  });
}
