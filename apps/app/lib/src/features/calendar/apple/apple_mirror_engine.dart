import '../../../sync/db/database.dart';
import '../../tasks/data/task.dart';
import 'apple_calendar_gateway.dart';
import 'apple_mirror.dart';

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
        ),
      );

  Future<void> delete(String taskId) => (_db.delete(
    _db.appleEventLinks,
  )..where((l) => l.taskId.equals(taskId))).go();

  AppleEventLink _fromRow(AppleEventLinkRow row) => AppleEventLink(
    taskId: row.taskId,
    calendarId: row.calendarId,
    eventId: row.eventId,
    signature: row.signature,
  );
}

/// Drives the task→EventKit mirror (OPH-078). The DECISIONS live in
/// `apple_mirror.dart` (pure, tested); this only executes them against the
/// gateway and keeps the map in step.
///
/// Apple has no server API, so — unlike Google's server-side BullMQ mirror —
/// this runs on the device, reacting to the replica. It is one-way in v1:
/// task → event. Reading foreign Apple edits back into tasks is future work
/// (the analogue of OPH-076, deliberately deferred: it needs a conflict policy
/// and there is no push, only foreground polling).
class AppleMirrorEngine {
  AppleMirrorEngine({
    required this.gateway,
    required this.links,
    required this.calendarId,
  });

  final AppleCalendarGateway gateway;
  final AppleEventLinkStore links;

  /// The calendar the user chose to mirror INTO, or null if none yet. Without
  /// it nothing is created (but stale events can still be cleaned up).
  final String? calendarId;

  /// Reconcile ONE task against EventKit. Idempotent and signature-guarded, so
  /// running it on every replica emit costs a round-trip only when something a
  /// calendar shows actually changed.
  Future<void> reconcileTask(Task task) async {
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
  /// them. EventKit has no push, so this on-resume pass is how the calendar
  /// re-asserts itself.
  Future<void> reconcileAll(List<Task> tasks) async {
    if (!gateway.isSupported) return;
    for (final task in tasks) {
      await reconcileTask(task);
    }
    final liveIds = {for (final t in tasks) t.id};
    for (final link in await links.all()) {
      if (!liveIds.contains(link.taskId)) {
        await gateway.deleteEvent(link.eventId);
        await links.delete(link.taskId);
      }
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
