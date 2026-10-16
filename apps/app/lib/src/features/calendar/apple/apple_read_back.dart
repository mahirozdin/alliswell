import '../../tasks/data/task.dart';
import 'apple_calendar_gateway.dart';
import 'apple_mirror.dart';

/// Apple event → task decision (OPH-369, ADR-0050) — pure, like the outbound
/// `decideAppleMirror`, so the whole read-back matrix is unit-testable without
/// EventKit or a device. The engine only executes what this answers.
///
/// It is the device-side twin of the server's Google inbound policy
/// (`apps/api/src/lib/inbound.js` `reconcileProviderEvent`, ADR-0007), with the
/// SAME semantics:
///
/// - **Only time flows back.** A moved or resized event writes
///   `scheduledStartAt`/`scheduledEndAt` — never `dueAt`; moving a block says
///   "I'll do it then", not "the deadline moved". Title and notes are left to
///   the next outbound write.
/// - **A cosmetic edit is not a move.** The event is compared with the block
///   §7.1 DERIVES, not the raw columns.
/// - **A deleted event stops the mirror, never the task.** The event is not
///   recreated (in that calendar) and the task is never deleted.
/// - **A series, or boundaries no block can express, is flagged** and left
///   alone on both sides.
/// - **Both sides changed → last-write-wins** (BLUEPRINT §6.5), the event's
///   `lastModified` against the task's `updatedAt`; without both, the task
///   wins — the replica/server is canonical (AGENTS.md §6).
///
/// Where it differs, it differs because EventKit does: there is no etag, so
/// echo suppression is content-based — the times WE last wrote are kept in the
/// link's signature, and an event still showing them is our own write.

/// iCloud/CalDAV store whole seconds, while a task's `createdAt`/`dueAt` carry
/// milliseconds: comparing exact instants would turn every iCloud round-trip
/// into a phantom drag that pins the task to `scheduled_*`. A real drag in
/// Calendar moves by 5 minutes or more, so a minute swallows no user edit.
const appleSameInstantTolerance = Duration(minutes: 1);

bool _same(DateTime a, DateTime b) =>
    a.difference(b).abs() < appleSameInstantTolerance;

bool _sameWindow((DateTime, DateTime) a, (DateTime, DateTime) b) =>
    _same(a.$1, b.$1) && _same(a.$2, b.$2);

/// What we last wrote to the event, parsed back out of
/// [DesiredAppleEvent.signature] (`title|startIso|endIso`), or null when it is
/// not one. The title may itself contain `|`, so the times are the LAST two
/// segments.
({String title, DateTime start, DateTime end})? parseAppleSignature(
  String signature,
) {
  final endBar = signature.lastIndexOf('|');
  if (endBar <= 0) return null;
  final startBar = signature.lastIndexOf('|', endBar - 1);
  if (startBar < 0) return null;
  final start = DateTime.tryParse(signature.substring(startBar + 1, endBar));
  final end = DateTime.tryParse(signature.substring(endBar + 1));
  if (start == null || end == null) return null;
  return (title: signature.substring(0, startBar), start: start, end: end);
}

/// The signature of an event we now consider written with [start]–[end] and
/// the title we last wrote — what the link must hold after a read-back adopts
/// the user's times, so the next outbound pass sees nothing of its own to
/// push (and an all-day event the user made stays all-day).
String appleSignatureWith(String writtenTitle, DateTime start, DateTime end) =>
    '$writtenTitle|${start.toUtc().toIso8601String()}|'
    '${end.toUtc().toIso8601String()}';

/// The task-shaped window of an event, or null when it cannot be one: a
/// recurring series (many instants, one task) or unusable boundaries.
///
/// An all-day event maps to local midnight → the midnight AFTER its last day,
/// the shape Google's exclusive `end.date` gives on the server. EventKit may
/// report that end either as 23:59:59 of the last day or as the next midnight
/// itself; both land on the same block.
(DateTime, DateTime)? appleEventWindow(AppleEventSnapshot event) {
  if (event.hasRecurrence) return null;
  var start = event.start;
  var end = event.end;
  if (event.isAllDay) {
    final s = start.toLocal();
    final e = end.toLocal();
    start = DateTime(s.year, s.month, s.day);
    final endsAtMidnight =
        e.hour == 0 &&
        e.minute == 0 &&
        e.second == 0 &&
        e.millisecond == 0 &&
        e.microsecond == 0;
    end = endsAtMidnight && e.isAfter(start)
        ? DateTime(e.year, e.month, e.day)
        : DateTime(e.year, e.month, e.day + 1);
  }
  if (!end.isAfter(start)) return null;
  return (start, end);
}

enum AppleReadBackDecision {
  /// Not ours to judge this pass (suppressed, no block wanted, calendar
  /// unreachable, no baseline).
  ignore,

  /// The event still shows what we wrote — our own write coming back, or an
  /// edit to something we do not map (colour, notes, title).
  echo,

  /// The event already shows the task's block (another device applied the
  /// same drag): nothing to write, only the baseline to refresh.
  touch,

  /// The user moved/resized it: write its times to the task.
  apply,

  /// Both changed and the task is newer: the outbound pass re-asserts it.
  push,

  /// The user deleted the event: stop mirroring this task into that calendar.
  suppress,

  /// A series or an unusable window: flag it, write nothing either way.
  flag,
}

class AppleReadBackOutcome {
  const AppleReadBackOutcome(
    this.decision,
    this.reason, {
    this.start,
    this.end,
  });

  final AppleReadBackDecision decision;

  /// Present on [AppleReadBackDecision.apply] and `touch`: the window to adopt.
  final DateTime? start;
  final DateTime? end;

  /// For the log line and the tests — the same vocabulary as `inbound.js`.
  final String reason;
}

/// Decides what one mapped event means for its task.
///
/// [event] is null when EventKit no longer has it (after the engine's url
/// recovery failed); [calendarPresent] is false when the link's calendar is
/// not among the device's calendars right now — an unreachable calendar is
/// never taken as "the user deleted it".
AppleReadBackOutcome decideAppleReadBack({
  required Task task,
  required AppleEventLink link,
  required AppleEventSnapshot? event,
  required bool calendarPresent,
}) {
  if (link.suppressedAt != null) {
    return const AppleReadBackOutcome(
      AppleReadBackDecision.ignore,
      'suppressed',
    );
  }
  final desired = desiredAppleEvent(task);
  if (desired == null) {
    // The task stopped earning an event; the outbound pass removes it (the
    // server's `remove-remote`). Local state is canonical.
    return const AppleReadBackOutcome(
      AppleReadBackDecision.ignore,
      'outbound-removes',
    );
  }
  if (!calendarPresent) {
    return const AppleReadBackOutcome(
      AppleReadBackDecision.ignore,
      'calendar-unavailable',
    );
  }
  if (event == null) {
    // Our own removals drop the link first, so a surviving link to a missing
    // event means the USER deleted it. Recreating it would fight them forever;
    // deleting their task would be worse.
    return const AppleReadBackOutcome(
      AppleReadBackDecision.suppress,
      'provider-deleted',
    );
  }
  final window = appleEventWindow(event);
  if (window == null) {
    return const AppleReadBackOutcome(
      AppleReadBackDecision.flag,
      'unmappable-times',
    );
  }
  final written = parseAppleSignature(link.signature);
  if (written == null) {
    return const AppleReadBackOutcome(
      AppleReadBackDecision.ignore,
      'no-baseline',
    );
  }
  if (_sameWindow(window, (written.start, written.end))) {
    return const AppleReadBackOutcome(AppleReadBackDecision.echo, 'echo');
  }
  // Compared with what §7.1 DERIVES (inbound.js does the same): an event built
  // from `dueAt` sits at a time no column holds.
  final derived = (desired.start, desired.end);
  if (_sameWindow(window, derived)) {
    return AppleReadBackOutcome(
      AppleReadBackDecision.touch,
      'provider-matches-task',
      start: window.$1,
      end: window.$2,
    );
  }
  final localChanged = !_sameWindow(derived, (written.start, written.end));
  if (!localChanged) {
    return AppleReadBackOutcome(
      AppleReadBackDecision.apply,
      'provider-only',
      start: window.$1,
      end: window.$2,
    );
  }
  final modified = event.lastModified;
  final updated = task.updatedAt;
  if (modified != null && updated != null && modified.isAfter(updated)) {
    return AppleReadBackOutcome(
      AppleReadBackDecision.apply,
      'both-changed-provider-newer',
      start: window.$1,
      end: window.$2,
    );
  }
  return const AppleReadBackOutcome(
    AppleReadBackDecision.push,
    'both-changed-local-newer',
  );
}
