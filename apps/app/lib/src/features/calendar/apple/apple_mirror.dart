import '../../tasks/data/task.dart';

/// Task → Apple calendar event derivation (OPH-078, BLUEPRINT §7.1) — pure, so
/// the mirroring rule is unit-testable without EventKit or a device.
///
/// This is the fourth pure decision function in the calendar stack, exactly as
/// ADR-0008 predicted. It mirrors the server's `desiredEventForTask`
/// fixture-for-fixture: the two sides derive the SAME block, so a task shows at
/// the same time whether it reaches the calendar through Google (server) or
/// EventKit (device).

const _slot = Duration(minutes: 30);
const _goneStatuses = {'completed', 'cancelled', 'archived'};

/// The custom-scheme marker Apple events carry in their URL field (ADR-0003) —
/// the recovery key when EventKit's own identifier goes stale.
String appleTaskUrl(String taskId) => 'alliswell://task/$taskId';

/// What EventKit should hold for a task, or null when it should hold nothing.
/// Deliberately carries no calendar id or event id — those belong to the device
/// (which calendar the user picked, which identifier EventKit assigned), not to
/// the task. The engine adds them.
class DesiredAppleEvent {
  const DesiredAppleEvent({
    required this.title,
    required this.url,
    required this.start,
    required this.end,
  });

  final String title;
  final String url;
  final DateTime start;
  final DateTime end;

  /// Content fingerprint, so the engine can skip a write when nothing a
  /// calendar shows has changed — a title-only-unchanged reconcile costs no
  /// EventKit round-trip. (The server uses revisions; the client cannot, since
  /// local edits do not bump the server revision, so it compares content.)
  String get signature =>
      '$title|${start.toUtc().toIso8601String()}|${end.toUtc().toIso8601String()}';
}

/// §7.1: a task earns a calendar block when it opts in AND has a time — the
/// scheduled block first, then the due slot, then an urgent reminder block.
/// Finished/cancelled/archived tasks earn nothing (their event is removed).
DesiredAppleEvent? desiredAppleEvent(Task task) {
  if (!task.calendarMirrorEnabled) return null;
  if (_goneStatuses.contains(task.status)) return null;

  DateTime start;
  DateTime end;
  if (task.scheduledStartAt != null) {
    start = task.scheduledStartAt!;
    final scheduledEnd = task.scheduledEndAt;
    // No end, or one left behind by a moved start: fall back to the default
    // slot rather than derive a backwards block (server parity — the mirror.js
    // guard added for the same reason).
    end = (scheduledEnd != null && scheduledEnd.isAfter(start))
        ? scheduledEnd
        : start.add(_slot);
  } else if (task.dueAt != null) {
    start = task.dueAt!;
    end = start.add(_slot);
  } else if (task.isUrgent && task.remindAt != null) {
    start = task.remindAt!;
    end = start.add(_slot);
  } else {
    return null;
  }

  return DesiredAppleEvent(
    title: '[Task] ${task.title}',
    url: appleTaskUrl(task.id),
    start: start,
    end: end,
  );
}

/// What the engine should do about one task, given what EventKit already holds
/// for it. Pure — the engine executes, this decides.
enum AppleMirrorDecision {
  /// No event wanted and none mapped — nothing to do.
  none,

  /// Wanted, nothing mapped yet — create it.
  create,

  /// Wanted and mapped, content changed — update in place.
  update,

  /// Wanted and mapped, content identical — leave EventKit alone.
  noop,

  /// No longer wanted but still mapped — remove the event.
  remove,
}

/// The mapping we persist per task (mirrors the server's `calendar_event_links`,
/// trimmed to what a one-way device mirror needs).
class AppleEventLink {
  const AppleEventLink({
    required this.taskId,
    required this.calendarId,
    required this.eventId,
    required this.signature,
  });

  final String taskId;

  /// Which calendar the event was created in. If the user picks a DIFFERENT
  /// calendar later, the old event is orphaned in the old one — the engine
  /// deletes and recreates rather than move (EventKit moves are lossy).
  final String calendarId;
  final String eventId;

  /// The [DesiredAppleEvent.signature] last written — the basis for `noop`.
  final String signature;
}

/// Decide, given the task's desired event, its existing link, and the calendar
/// the user chose. `targetCalendarId` is null when no calendar is selected yet
/// — then nothing can be created, but existing events can still be removed.
AppleMirrorDecision decideAppleMirror({
  required DesiredAppleEvent? desired,
  required AppleEventLink? link,
  required String? targetCalendarId,
}) {
  if (desired == null) {
    return link == null ? AppleMirrorDecision.none : AppleMirrorDecision.remove;
  }
  if (targetCalendarId == null) {
    // Wanted, but nowhere to put it. If one already exists (calendar was later
    // unset), leaving it is the least surprising choice — do not delete a real
    // event just because the setting changed.
    return link == null ? AppleMirrorDecision.none : AppleMirrorDecision.noop;
  }
  if (link == null) return AppleMirrorDecision.create;
  // The user re-pointed to a different calendar: the old event lives in the old
  // one and must go, then be recreated in the new (EventKit has no clean move).
  if (link.calendarId != targetCalendarId) return AppleMirrorDecision.remove;
  return link.signature == desired.signature
      ? AppleMirrorDecision.noop
      : AppleMirrorDecision.update;
}
