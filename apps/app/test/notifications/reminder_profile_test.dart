import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/notifications/planner.dart';
import 'package:alliswell/src/notifications/reminder_profile.dart';

final now = DateTime.utc(2026, 7, 15, 12);

AlarmInput urgent({String status = 'scheduled', DateTime? snoozedUntil}) =>
    AlarmInput(
      reminderId: 'R1'.padRight(26, '0'),
      taskId: 'T1'.padRight(26, '0'),
      taskTitle: 'Görev',
      remindAt: now.add(const Duration(hours: 1)),
      status: status,
      urgent: true,
      requiresAcknowledgement: true,
      snoozedUntil: snoozedUntil,
    );

/// OPH-179 — the re-alert chain is the user's (round 9 #7, DESIGN §18).
void main() {
  group('normalizeSlots — the rules live in ONE place (N5)', () {
    test('sorts, deduplicates and drops negatives', () {
      expect(ReminderProfile.normalizeSlots([30, 2, 2, -5, 0, 10]), [
        0,
        2,
        10,
        30,
      ]);
    });

    test('enforces the minimum gap the user asked for', () {
      // "30 seconds later" cannot be expressed, and two alerts in the same
      // minute would collide — so the second is dropped, not silently merged.
      expect(ReminderProfile.normalizeSlots([0, 0, 1, 1, 2]), [0, 1, 2]);
      expect(ReminderProfile.normalizeSlots(List.generate(5, (i) => 7)), [7]);
    });

    test('caps the chain at $kMaxReminderSlots alerts', () {
      final slots = ReminderProfile.normalizeSlots(
        List.generate(50, (i) => i * 2),
      );
      expect(slots, hasLength(kMaxReminderSlots));
      expect(slots.first, 0);
    });

    test('never returns an empty chain — an alarm must ring at least once', () {
      expect(ReminderProfile.normalizeSlots(const []), [0]);
      expect(ReminderProfile.normalizeSlots([-3, -1]), [0]);
    });

    test('the stepper floor keeps the gap while editing, not on save', () {
      expect(ReminderProfile.minSlotAfter(null), 0);
      expect(ReminderProfile.minSlotAfter(5), 5 + kMinReminderGapMinutes);
    });
  });

  group('parse / encode', () {
    test('round-trips', () {
      const profile = ReminderProfile(
        slots: [0, 3, 9],
        repeatAfterSnooze: false,
      );
      final parsed = ReminderProfile.parse(profile.encode());
      expect(parsed.slots, [0, 3, 9]);
      expect(parsed.repeatAfterSnooze, isFalse);
    });

    test('junk, empties and hostile values fall back to the factory chain', () {
      for (final raw in [
        null,
        '',
        '   ',
        'not json',
        '[]',
        '{"slots":"nope"}',
        '{}',
      ]) {
        expect(
          ReminderProfile.parse(raw).slots,
          ReminderProfile.factory.slots,
          reason: 'a broken preference must never cost the user their alarms',
        );
      }
    });

    test('a stored chain is normalized on the way in', () {
      final parsed = ReminderProfile.parse('{"slots":[9,9,1,0,-2]}');
      expect(parsed.slots, [0, 1, 9]);
    });

    test('names the preset it matches, and admits when it is custom', () {
      expect(ReminderProfile.factory.presetId, 'standard');
      expect(const ReminderProfile(slots: [0]).presetId, 'calm');
      expect(const ReminderProfile(slots: [0, 4, 40]).presetId, isNull);
    });
  });

  group('capacity (N5) — the OS budget is stated, never silently spent', () {
    test('a shorter chain covers more concurrent alarms', () {
      expect(const ReminderProfile(slots: [0]).alarmsFullyCovered, 40);
      expect(ReminderProfile.factory.alarmsFullyCovered, 8);
      expect(
        ReminderProfile(
          slots: List.generate(kMaxReminderSlots, (i) => i),
        ).alarmsFullyCovered,
        2,
      );
    });
  });

  group('the planner obeys the profile', () {
    test('a calm profile rings once; an insistent one rings ten times', () {
      final calm = planNotifications(
        alarms: [urgent()],
        now: now,
        privacyMode: false,
        profile: const ReminderProfile(slots: [0]),
      );
      expect(calm, hasLength(1));

      final insistent = planNotifications(
        alarms: [urgent()],
        now: now,
        privacyMode: false,
        profile: ReminderProfile(
          slots: kReminderProfilePresets
              .firstWhere((p) => p.id == 'insistent')
              .slots,
        ),
      );
      expect(insistent, hasLength(10));
    });

    test('the offsets are exactly the ones the user chose', () {
      const profile = ReminderProfile(slots: [0, 7, 21]);
      final plan = planNotifications(
        alarms: [urgent()],
        now: now,
        privacyMode: false,
        profile: profile,
      );
      final base = now.add(const Duration(hours: 1));
      expect(plan.map((n) => n.fireAt), [
        base,
        base.add(const Duration(minutes: 7)),
        base.add(const Duration(minutes: 21)),
      ]);
    });

    test('repeatAfterSnooze off makes a snoozed alarm ring ONCE', () {
      final snoozedAt = now.add(const Duration(minutes: 5));
      final once = planNotifications(
        alarms: [urgent(status: 'snoozed', snoozedUntil: snoozedAt)],
        now: now,
        privacyMode: false,
        profile: const ReminderProfile(
          slots: [0, 2, 5],
          repeatAfterSnooze: false,
        ),
      );
      expect(once, hasLength(1));
      expect(once.single.fireAt, snoozedAt);

      // On (the default), the whole chain runs again from the snooze instant.
      final again = planNotifications(
        alarms: [urgent(status: 'snoozed', snoozedUntil: snoozedAt)],
        now: now,
        privacyMode: false,
        profile: const ReminderProfile(slots: [0, 2, 5]),
      );
      expect(again, hasLength(3));
    });
  });

  group('snooze preset order (N4)', () {
    test('keeps the stored order and appends anything unknown to it', () {
      expect(parseSnoozePresetOrder('1_hour,5_min'), [
        '1_hour',
        '5_min',
        // The rest still exist — a new preset can never be hidden by an old
        // preference.
        '30_min',
        'tomorrow_morning',
      ]);
    });

    test('ignores junk and duplicates', () {
      expect(parseSnoozePresetOrder('nope,5_min,5_min,,30_min'), [
        '5_min',
        '30_min',
        '1_hour',
        'tomorrow_morning',
      ]);
      expect(parseSnoozePresetOrder(null), kSnoozePresetIds);
    });
  });
}
