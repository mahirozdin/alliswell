import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/widgets/widget_clock.dart';

/// Round 17 (OPH-253) — the header clock is DRAWN in Swift and in an Android
/// layout, and no Dart test can exercise either.
///
/// `widget_clock_test.dart` owns the rules. This owns the claim that the native
/// files still obey them: the same staleness threshold, the same horizon, the
/// trailing column, the tabular digits. It is the `web_shell_test.dart` pattern
/// from round 16 — guard the rule in the file you cannot run, so that deleting
/// the rule breaks a test instead of breaking a widget nobody photographs for
/// another three months.
///
/// These assertions are deliberately about STRUCTURE, not formatting: they name
/// the identifiers and constants that carry meaning, so reindenting or renaming
/// a local never fails the suite.
void main() {
  final swift = File(
    'ios/AllisWellWidget/AllisWellWidget.swift',
  ).readAsStringSync();
  final layout = File(
    'android/app/src/main/res/layout/tasks_widget.xml',
  ).readAsStringSync();
  final provider = File(
    'android/app/src/main/kotlin/com/alliswell/alliswell/TasksWidgetProvider.kt',
  ).readAsStringSync();

  group('iOS mirrors the Dart rule (C3, C4)', () {
    test('the staleness threshold is the same number on both sides', () {
      expect(
        swift,
        contains('kAWClockStaleSeconds: TimeInterval = $kWidgetClockStaleSeconds'),
        reason:
            'the honesty gate has to fire at the same age in Swift as it does '
            'in widget_clock.dart — two thresholds is no threshold',
      );
    });

    test('the minute horizon is the same number on both sides', () {
      expect(
        swift,
        contains('kAWClockHorizonMinutes = $kWidgetClockHorizonMinutes'),
        reason:
            'the horizon sets the reload cost (1440 / horizon per day); if the '
            'two drift, the budget written in DESIGN §31 C4 is fiction',
      );
    });

    test('both gates are actually applied, not just declared', () {
      // A constant nobody reads is the failure mode this test exists for.
      expect(swift, contains('guard entry.showsClock else { return nil }'));
      expect(swift, contains('now.timeIntervalSince(entry.date)'));
      expect(swift, contains('kAWClockStaleSeconds else { return nil }'));
    });

    test('the entries beyond the horizon carry no clock', () {
      // The midnight entries are the fallback for when the reload never comes,
      // which is exactly when a clock would be lying.
      expect(swift, contains('showsClock: false'));
    });

    test('the horizon is budgeted in BYTES, not in entries', () {
      // Measured on device: 241 systemLarge entries archived to 16,665,560
      // bytes and chronod rejected the whole timeline — "too large timeline
      // archive" — leaving the widget stuck on its placeholder with no visible
      // error. The cost scales with the ROWS drawn, so a fixed entry count
      // fails precisely for the users with the most tasks. If someone ever
      // deletes this budget and goes back to a constant, this test dies.
      expect(swift, contains('kAWArchiveBudgetBytes'));
      expect(swift, contains('kAWEntryBytesPerRow'));
      expect(
        swift,
        contains('kAWArchiveBudgetBytes / max(bytesPerEntry, 1)'),
        reason: 'the horizon must be derived from the budget, not hardcoded',
      );
      expect(
        swift,
        contains('awRowBudget(context.family)'),
        reason:
            'the row count depends on the widget SIZE; an extraLarge draws 18 '
            'rows where a medium draws 4, and the archive scales with it',
      );
    });

    test('the clock ticks on the minute, not on the second it was built', () {
      expect(
        swift,
        contains('matching: DateComponents(second: 0)'),
        reason:
            'entries built by adding 60 s to "now" land partway into every '
            'minute, so the clock flips late by however long ago the reload was',
      );
    });

    test('the right column is trailing-aligned and tabular', () {
      expect(
        swift,
        contains('VStack(alignment: .trailing, spacing: 0)'),
        reason:
            'two lines of different widths under a Spacer default to leading, '
            'which leaves the shorter one hanging in mid-air (§31 C1)',
      );
      expect(swift, contains('.monospacedDigit()'));
    });

    test('the pattern comes from the snapshot, never from native guesswork', () {
      // W9: which clock the user reads is a product rule, and the app settled
      // it for the task rows already (OPH-174).
      expect(swift, contains('entry.snapshot.clockFormat'));
      expect(
        swift,
        isNot(contains('dateFormat = "HH:mm"')),
        reason:
            'hardcoding a 24-hour pattern hands the wrong clock to every '
            '12-hour user — C2\'s exact prohibition',
      );
    });
  });

  group('Android draws the same header (C1, C2, C5)', () {
    test('the layout carries a TextClock, not a TextView we update', () {
      // TextClock is a @RemoteView and ticks inside the launcher's host for
      // free. A TextView would need a refresh per minute, which is the one
      // thing C4 forbids.
      expect(layout, contains('<TextClock'));
      expect(layout, contains('android:id="@+id/aw_clock"'));
    });

    test('the clock is bold, in the header ink, with tabular digits', () {
      final clock = layout.substring(
        layout.indexOf('<TextClock'),
        layout.indexOf('/>', layout.indexOf('<TextClock')),
      );
      expect(clock, contains('android:textStyle="bold"'));
      expect(clock, contains('@color/aw_widget_text'));
      expect(
        clock,
        contains('android:fontFeatureSettings="tnum"'),
        reason: 'without tabular figures the header jitters every minute (C2)',
      );
    });

    test('the right column stacks and hugs the trailing edge', () {
      expect(layout, contains('android:gravity="end"'));
      // C5: the count still hides at zero, and the header's own
      // center_vertical then centres the clock. Both must survive.
      expect(layout, contains('android:id="@+id/aw_open_today"'));
      expect(layout, contains('android:visibility="gone"'));
      expect(layout, contains('android:gravity="center_vertical"'));
    });

    test('the provider pushes the app\'s pattern into BOTH clock slots', () {
      // TextClock picks 12h or 24h from the device; setting both to the same
      // resolved pattern is what stops the device toggle overruling the app.
      expect(provider, contains('"setFormat12Hour"'));
      expect(provider, contains('"setFormat24Hour"'));
      expect(provider, contains('clockFormat'));
    });
  });
}
