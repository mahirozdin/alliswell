/// The user's own re-alert chain (round 9 #7, OPH-179 — DESIGN §18,
/// NOTIFICATIONS §5b).
///
/// Until now the chain was a compile-time constant (`[0, +2, +5, +10, +30]`), so
/// "how many times should this thing nag me, and how far apart" was a decision
/// the user could not touch. It is a profile now: pure value, device-local
/// preference, passed into the planner.
library;

import 'dart:convert';

/// How many alerts one alarm may schedule. The ceiling is not taste: iOS keeps
/// only the **64 soonest pending** notifications, so a long chain spends a
/// budget shared with every other alarm (see [alarmsFullyCovered]).
const int kMaxReminderSlots = 20;

/// The smallest gap the user may put between two alerts, in minutes. Their own
/// anti-collision rule from round 9 ("min araları 1 dk olma zorunluluğu"), and
/// also what keeps the OS from coalescing two alerts into one.
const int kMinReminderGapMinutes = 1;

/// The planner's window (`NotificationScheduler.maxPending`) — the number the
/// capacity line divides.
const int kPlannerWindow = 40;

/// A named chain the user can pick without touching a stepper (N2).
class ReminderProfilePreset {
  const ReminderProfilePreset(this.id, this.slots);

  final String id;
  final List<int> slots;
}

/// Calm · Standard · Insistent. Standard is the factory chain — the shape that
/// shipped before the profile existed, so an upgrade changes nothing.
const List<ReminderProfilePreset> kReminderProfilePresets = [
  ReminderProfilePreset('calm', [0]),
  ReminderProfilePreset('standard', [0, 2, 5, 10, 30]),
  ReminderProfilePreset('insistent', [0, 1, 2, 3, 5, 8, 12, 17, 25, 40]),
];

/// Minutes after the alarm instant at which the alerts fire, plus whether a
/// post-snooze ring runs the same chain again.
class ReminderProfile {
  const ReminderProfile({required this.slots, this.repeatAfterSnooze = true});

  /// Sorted, deduplicated, at least [kMinReminderGapMinutes] apart, ≤
  /// [kMaxReminderSlots] long, first ≥ 0. Use [normalizeSlots] to get there.
  final List<int> slots;

  /// When false, a snoozed alarm rings ONCE when it comes back instead of
  /// running the whole chain again.
  final bool repeatAfterSnooze;

  /// What shipped before this was configurable.
  static const ReminderProfile factory = ReminderProfile(
    slots: [0, 2, 5, 10, 30],
  );

  List<Duration> get offsets => [
    for (final minutes in slots) Duration(minutes: minutes),
  ];

  /// How many alarms this profile covers END TO END inside the planner's window
  /// (N5). Stated on screen, because the alternative is the OS silently
  /// dropping the far slots and the product looking like it lost an alarm.
  int get alarmsFullyCovered =>
      slots.isEmpty ? 0 : kPlannerWindow ~/ slots.length;

  ReminderProfile copyWith({List<int>? slots, bool? repeatAfterSnooze}) =>
      ReminderProfile(
        slots: slots ?? this.slots,
        repeatAfterSnooze: repeatAfterSnooze ?? this.repeatAfterSnooze,
      );

  String encode() =>
      jsonEncode({'slots': slots, 'repeatAfterSnooze': repeatAfterSnooze});

  /// Anything unparseable — a corrupted preference, a value from a future
  /// version, an empty string — falls back to [factory]. A broken preference
  /// must never leave a user without alarms (the `parseTaskTime` rule).
  static ReminderProfile parse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return factory;
    try {
      final data = jsonDecode(raw);
      if (data is! Map) return factory;
      final rawSlots = data['slots'];
      if (rawSlots is! List) return factory;
      final slots = normalizeSlots([
        for (final value in rawSlots)
          if (value is int) value else if (value is num) value.toInt(),
      ]);
      return ReminderProfile(
        slots: slots,
        repeatAfterSnooze: data['repeatAfterSnooze'] is bool
            ? data['repeatAfterSnooze'] as bool
            : true,
      );
    } on Object {
      return factory;
    }
  }

  /// The one place the rules live: drop negatives, sort, deduplicate, enforce
  /// the minimum gap, cap the length — and never return an empty chain, because
  /// an alarm that rings zero times is not an alarm.
  static List<int> normalizeSlots(Iterable<int> raw) {
    final sorted = raw.where((m) => m >= 0).toSet().toList()..sort();
    final kept = <int>[];
    for (final minutes in sorted) {
      if (kept.isEmpty || minutes - kept.last >= kMinReminderGapMinutes) {
        kept.add(minutes);
      }
      if (kept.length == kMaxReminderSlots) break;
    }
    return kept.isEmpty ? const [0] : kept;
  }

  /// The smallest value a step may take, given the step before it — what the
  /// editor's stepper clamps to, so the 1-minute rule is enforced while typing
  /// instead of silently applied on save (N5).
  static int minSlotAfter(int? previous) =>
      previous == null ? 0 : previous + kMinReminderGapMinutes;

  /// Which named preset this is, or null for a hand-built chain.
  String? get presetId {
    for (final preset in kReminderProfilePresets) {
      if (preset.slots.length == slots.length) {
        var same = true;
        for (var i = 0; i < slots.length; i++) {
          if (preset.slots[i] != slots[i]) {
            same = false;
            break;
          }
        }
        if (same) return preset.id;
      }
    }
    return null;
  }
}

/// What the first snooze is before the user reorders anything — also the one
/// the OS-level AlarmKit alert offers, since it has room for a single snooze
/// button (OPH-182).
const String kDefaultSnoozePreset = '5_min';

/// The snooze presets the alarm screen offers, in the user's own order (N4 —
/// the one list where dragging means something: a sorted numeric chain would
/// just re-sort itself).
const List<String> kSnoozePresetIds = [
  kDefaultSnoozePreset,
  '30_min',
  '1_hour',
  'tomorrow_morning',
];

/// Parses a stored order, keeping only known presets and appending any the user
/// has never seen (so adding a preset in a future version cannot hide it).
List<String> parseSnoozePresetOrder(String? raw) {
  final parsed = <String>[];
  for (final part in (raw ?? '').split(',')) {
    final id = part.trim();
    if (kSnoozePresetIds.contains(id) && !parsed.contains(id)) parsed.add(id);
  }
  for (final id in kSnoozePresetIds) {
    if (!parsed.contains(id)) parsed.add(id);
  }
  return parsed;
}

/// i18n keys for the snooze presets, in one place (the ring screen and the
/// reminder settings screen both render them).
const Map<String, String> kSnoozePresetLabels = {
  '5_min': 'notif.action.snooze5m',
  '30_min': 'notif.action.snooze30m',
  '1_hour': 'notif.action.snooze1h',
  'tomorrow_morning': 'notif.action.snoozeTomorrow',
};
