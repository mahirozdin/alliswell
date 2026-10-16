import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show debugPrint;

import '../../../sync/db/database.dart';
import '../../tasks/data/task.dart';
import 'apple_calendar_gateway.dart';
import 'apple_mirror.dart';
import 'apple_read_back.dart';

/// Local-first store for the task→Apple-event map (OPH-078). Device-only: Apple
/// events live on this device, so this never touches the outbox or sync — it is
/// pure device cache, and rebuilt by a foreground resync if lost.
class AppleEventLinkStore {
  AppleEventLinkStore(this._db);

  final AwDatabase _db;

  Future<AppleEventLink?> get(String taskId) async {
    final row = await (_db.select(
      _db.appleEventLinks,
    )..where((l) => l.taskId.equals(taskId))).getSingleOrNull();
    return row == null ? null : _fromRow(row);
  }

  Future<List<AppleEventLink>> all() async {
    final rows = await _db.select(_db.appleEventLinks).get();
    return rows.map(_fromRow).toList();
  }

  Future<void> put(AppleEventLink link) => _db
      .into(_db.appleEventLinks)
      .insertOnConflictUpdate(
        AppleEventLinksCompanion.insert(
          taskId: link.taskId,
          calendarId: link.calendarId,
          eventId: link.eventId,
          signature: link.signature,
          suppressedAt: Value(link.suppressedAt),
        ),
      );

  Future<void> delete(String taskId) => (_db.delete(
    _db.appleEventLinks,
  )..where((l) => l.taskId.equals(taskId))).go();

  /// OPH-369: the user deleted the event — stop mirroring into its calendar.
  Future<void> suppress(String taskId, DateTime at) =>
      (_db.update(_db.appleEventLinks)..where((l) => l.taskId.equals(taskId)))
          .write(AppleEventLinksCompanion(suppressedAt: Value(at.toUtc())));

  /// OPH-369: the same event under a new EventKit identifier (an iCloud move),
  /// found again by its `alliswell://` url.
  Future<void> relink(String taskId, String eventId) =>
      (_db.update(_db.appleEventLinks)..where((l) => l.taskId.equals(taskId)))
          .write(AppleEventLinksCompanion(eventId: Value(eventId)));

  AppleEventLink _fromRow(AppleEventLinkRow row) => AppleEventLink(
    taskId: row.taskId,
    calendarId: row.calendarId,
    eventId: row.eventId,
    signature: row.signature,
    suppressedAt: row.suppressedAt,
  );
}

/// Writes a time the user gave the event in Apple Calendar back to its task —
/// through the task store (optimistic row + outbox), never REST (AGENTS §4).
typedef AppleTaskTimeWriter =
    Future<void> Function(String taskId, DateTime start, DateTime end);

/// Drives the task⇄EventKit mirror (OPH-078, OPH-369). The DECISIONS live in
/// `apple_mirror.dart` and `apple_read_back.dart` (pure, tested); this only
/// executes them against the gateway and keeps the map in step.
///
/// Apple has no server API, so — unlike Google's server-side BullMQ mirror —
/// this runs on the device, reacting to the replica. Outbound, task → event, on
/// every replica emit. Read-back, event → task (ADR-0050), on the first pass
/// and every return to the foreground (EventKit has no push), plus a one-event
/// look before any outbound update so a fresh drag is not overwritten.
class AppleMirrorEngine {
  AppleMirrorEngine({
    required this.gateway,
    required this.links,
    required this.calendarId,
    AppleTaskTimeWriter? writeTaskTimes,
    DateTime Function()? now,
  }) : writeTaskTimes = writeTaskTimes ?? _noWriter,
       _now = now ?? DateTime.now;

  static Future<void> _noWriter(String _, DateTime _, DateTime _) async {}

  final AppleCalendarGateway gateway;
  final AppleEventLinkStore links;

  /// The calendar the user chose to mirror INTO, or null if none yet. Without
  /// it nothing is created (but stale events can still be cleaned up).
  final String? calendarId;

  final AppleTaskTimeWriter writeTaskTimes;
  final DateTime Function() _now;

  /// How far around the last-written window the url recovery looks for an
  /// event whose EventKit identifier changed.
  static const recoveryWindow = Duration(days: 90);

  // ── The one entry point the app uses ────────────────────────────────────────

  List<Task>? _pending;
  bool _pendingReadBack = false;
  Future<void>? _running;

  /// Serialised and coalescing: passes never overlap (two overlapping passes
  /// could each create the same event), and a burst of replica emits collapses
  /// into one pass over the LATEST task list. A read-back request survives the
  /// coalescing. The returned future completes when the queue drains.
  Future<void> sync(List<Task> tasks, {bool readBack = false}) {
    _pending = tasks;
    _pendingReadBack = _pendingReadBack || readBack;
    return _running ??= _drain();
  }

  Future<void> _drain() async {
    try {
      while (_pending != null) {
        final tasks = _pending!;
        final readBack = _pendingReadBack;
        _pending = null;
        _pendingReadBack = false;
        try {
          final applied = readBack ? await readBackAll(tasks) : <String>{};
          // Tasks whose times were just written back are SKIPPED here: their
          // objects in [tasks] are stale, and reconciling them would push the
          // old block over the user's drag. The write's own replica emit
          // brings them back with the new times.
          await reconcileAll(tasks, skip: applied, preRead: !readBack);
        } on EventKitException catch (e) {
          // One failed pass must not wedge the chain; the next emit retries.
          debugPrint('apple mirror: $e');
        }
      }
    } finally {
      _running = null;
    }
  }

  // ── Read-back (OPH-369) ─────────────────────────────────────────────────────

  /// Reads every live mapped event and settles it against its task. Returns the
  /// ids of tasks whose times were written from Apple in this pass.
  Future<Set<String>> readBackAll(List<Task> tasks) async {
    final applied = <String>{};
    if (!gateway.isSupported) return applied;
    final present = {for (final c in await gateway.calendars()) c.id};
    // No calendars at all is a store hiccup or a revoked grant, not a world in
    // which the user deleted every event.
    if (present.isEmpty) return applied;

    final byId = {for (final t in tasks) t.id: t};
    final checked = <(AppleEventLink, Task)>[];
    for (final link in await links.all()) {
      final task = byId[link.taskId];
      if (link.suppressedAt != null || task == null) continue;
      if (desiredAppleEvent(task) == null) continue;
      checked.add((link, task));
    }
    if (checked.isEmpty) return applied;

    final read = await gateway.readEvents([
      for (final (link, _) in checked) link.eventId,
    ]);
    if (read == null) return applied; // this build cannot read back
    final events = {for (final e in read) e.id: e};

    final missing = [
      for (final c in checked)
        if (!events.containsKey(c.$1.eventId)) c,
    ];
    // Mass-vanish guard: most of our events gone at once is iCloud signing out
    // or resyncing, not the user deleting them one by one. When unsure, do
    // nothing — a later pass sees the truth.
    final massVanish =
        missing.length > 3 && missing.length * 2 > checked.length;
    if (massVanish) {
      debugPrint(
        'apple read-back: ${missing.length}/${checked.length} events '
        'missing — skipping deletions this pass',
      );
    }

    for (var (link, task) in checked) {
      var event = events[link.eventId];
      final calendarPresent = present.contains(link.calendarId);
      if (event == null) {
        if (massVanish || !calendarPresent) continue;
        // EventKit's identifier changes on an iCloud move (LESSONS calendar):
        // look the event up again by its url before believing it is gone.
        final recovered = await _recover(link, task);
        if (recovered != null) {
          link = AppleEventLink(
            taskId: link.taskId,
            calendarId: link.calendarId,
            eventId: recovered.id,
            signature: link.signature,
          );
          event = recovered;
        }
      }
      final outcome = decideAppleReadBack(
        task: task,
        link: link,
        event: event,
        calendarPresent: calendarPresent,
      );
      if (await _execute(task, link, outcome)) applied.add(task.id);
    }
    return applied;
  }

  Future<AppleEventSnapshot?> _recover(AppleEventLink link, Task task) async {
    final written = parseAppleSignature(link.signature);
    if (written == null) return null;
    final foundId = await gateway.findEventByUrl(
      calendarId: link.calendarId,
      url: appleTaskUrl(task.id),
      from: written.start.subtract(recoveryWindow),
      to: written.end.add(recoveryWindow),
    );
    if (foundId == null) return null;
    await links.relink(task.id, foundId);
    final again = await gateway.readEvents([foundId]);
    return (again == null || again.isEmpty) ? null : again.first;
  }

  /// Carries out one read-back outcome. True when the task's times were
  /// written.
  Future<bool> _execute(
    Task task,
    AppleEventLink link,
    AppleReadBackOutcome outcome,
  ) async {
    switch (outcome.decision) {
      case AppleReadBackDecision.apply:
      case AppleReadBackDecision.touch:
        // The link FIRST (the server flags its link before the task write, for
        // the same reason): the emit the task write triggers must find the new
        // times already written, so the outbound pass is a no-op and does not
        // reshape the user's event.
        final written = parseAppleSignature(link.signature);
        await links.put(
          AppleEventLink(
            taskId: link.taskId,
            calendarId: link.calendarId,
            eventId: link.eventId,
            signature: appleSignatureWith(
              written?.title ?? desiredAppleEvent(task)!.title,
              outcome.start!,
              outcome.end!,
            ),
          ),
        );
        if (outcome.decision == AppleReadBackDecision.touch) return false;
        await writeTaskTimes(task.id, outcome.start!, outcome.end!);
        return true;
      case AppleReadBackDecision.suppress:
        await links.suppress(task.id, _now());
        return false;
      case AppleReadBackDecision.flag:
      case AppleReadBackDecision.push:
      case AppleReadBackDecision.echo:
      case AppleReadBackDecision.ignore:
        if (outcome.decision != AppleReadBackDecision.echo) {
          debugPrint('apple read-back ${task.id}: ${outcome.reason}');
        }
        return false;
    }
  }

  // ── Outbound (OPH-078) ──────────────────────────────────────────────────────

  /// Reconcile ONE task against EventKit. Idempotent and signature-guarded, so
  /// running it on every replica emit costs a round-trip only when something a
  /// calendar shows actually changed.
  ///
  /// [preRead] (OPH-369): before overwriting an event, look at it once — the
  /// user may have dragged it since the last read-back (a pull changed the
  /// task while Calendar was in front), and last-write-wins decides.
  Future<void> reconcileTask(Task task, {bool preRead = true}) async {
    final desired = desiredAppleEvent(task);
    final link = await links.get(task.id);
    switch (decideAppleMirror(
      desired: desired,
      link: link,
      targetCalendarId: calendarId,
    )) {
      case AppleMirrorDecision.none:
      case AppleMirrorDecision.noop:
        return;

      case AppleMirrorDecision.remove:
        if (link != null) {
          await gateway.deleteEvent(link.eventId);
          await links.delete(task.id);
        }
        // A re-point (calendar changed) removes then recreates: fall through to
        // create in the new calendar within the same pass.
        if (desired != null && calendarId != null) {
          await _create(task.id, desired);
        }
        return;

      case AppleMirrorDecision.create:
        await _create(task.id, desired!);
        return;

      case AppleMirrorDecision.update:
        if (preRead && await _readBeforeUpdate(task, link!)) return;
        final eventId = await gateway.saveEvent(
          _spec(task.id, desired!, eventId: link!.eventId),
        );
        await links.put(
          AppleEventLink(
            taskId: task.id,
            calendarId: calendarId!,
            eventId: eventId,
            signature: desired.signature,
          ),
        );
        return;
    }
  }

  /// Foreground resync (§7.3): reconcile the whole open set, then delete events
  /// for tasks that have VANISHED entirely (deleted, or no longer pulled) — a
  /// per-task reconcile never sees those, so the orphan sweep is what removes
  /// them. [skip] holds tasks a read-back just wrote: they are live (not
  /// orphans) but their objects here are stale.
  Future<void> reconcileAll(
    List<Task> tasks, {
    Set<String> skip = const {},
    bool preRead = true,
  }) async {
    if (!gateway.isSupported) return;
    for (final task in tasks) {
      if (skip.contains(task.id)) continue;
      await reconcileTask(task, preRead: preRead);
    }
    final liveIds = {for (final t in tasks) t.id};
    for (final link in await links.all()) {
      if (!liveIds.contains(link.taskId)) {
        // Idempotent for a suppressed link too: its event is already gone.
        await gateway.deleteEvent(link.eventId);
        await links.delete(link.taskId);
      }
    }
  }

  /// The targeted look before an outbound update. True when the update must
  /// not happen (the user's newer times were adopted instead). A missing event
  /// here never suppresses: only the full read-back, with its url recovery and
  /// mass-vanish guard, may decide the user deleted something.
  Future<bool> _readBeforeUpdate(Task task, AppleEventLink link) async {
    final read = await gateway.readEvents([link.eventId]);
    if (read == null || read.isEmpty) return false;
    final outcome = decideAppleReadBack(
      task: task,
      link: link,
      event: read.first,
      calendarPresent: true,
    );
    switch (outcome.decision) {
      case AppleReadBackDecision.apply:
        await _execute(task, link, outcome);
        return true;
      case AppleReadBackDecision.touch:
        // The event already shows the task's times; refresh the baseline and
        // update only if something else (the title) is still left to write.
        await _execute(task, link, outcome);
        final refreshed = await links.get(task.id);
        return refreshed?.signature == desiredAppleEvent(task)?.signature;
      default:
        return false;
    }
  }

  Future<void> _create(String taskId, DesiredAppleEvent desired) async {
    // Re-link before creating: an event carrying our url may already exist from
    // a previous install/crash whose map row is gone (ADR-0003). Adopting it
    // instead of duplicating keeps one event per task.
    final existingId = await gateway.findEventByUrl(
      calendarId: calendarId!,
      url: desired.url,
      from: desired.start.subtract(const Duration(days: 1)),
      to: desired.end.add(const Duration(days: 1)),
    );
    final eventId = await gateway.saveEvent(
      _spec(taskId, desired, eventId: existingId),
    );
    await links.put(
      AppleEventLink(
        taskId: taskId,
        calendarId: calendarId!,
        eventId: eventId,
        signature: desired.signature,
      ),
    );
  }

  AppleEventSpec _spec(
    String taskId,
    DesiredAppleEvent desired, {
    String? eventId,
  }) => AppleEventSpec(
    eventId: eventId,
    calendarId: calendarId!,
    title: desired.title,
    url: desired.url,
    // A human-readable trail plus the machine marker (ADR-0003) — belt and
    // braces if the url field is ever stripped by a sync.
    notes: 'AllisWell • ${desired.url}',
    start: desired.start,
    end: desired.end,
  );
}
