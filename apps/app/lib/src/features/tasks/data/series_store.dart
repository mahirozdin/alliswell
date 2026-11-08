import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/recurrence.dart';
import '../../../core/ulid.dart';
import '../../../sync/db/database.dart';
import '../../../sync/outbox.dart';

/// A recurrence series, as the app sees it (OPH-207, ADR-0020).
class TaskSeriesModel {
  const TaskSeriesModel({
    required this.id,
    required this.workspaceId,
    required this.rule,
    required this.template,
    required this.timezone,
    required this.anchorAt,
  });

  final String id;
  final String workspaceId;
  final AwRepeatRule rule;
  final Map<String, dynamic> template;
  final String timezone;
  final DateTime anchorAt;

  static TaskSeriesModel? fromRow(TaskSeriesRecord row) {
    final rule = AwRepeatRule.fromJson(jsonDecode(row.ruleJson));
    if (rule == null) return null;
    return TaskSeriesModel(
      id: row.id,
      workspaceId: row.workspaceId,
      rule: rule,
      template: (jsonDecode(row.templateJson) as Map).cast<String, dynamic>(),
      timezone: row.timezone,
      anchorAt: row.anchorAt,
    );
  }
}

/// Local-first series access (OPH-207).
///
/// The client NEVER generates occurrences — the server owns that (ADR-0020 §4).
/// This store writes the RULE optimistically and enqueues it; the occurrence
/// rows arrive on the next pull like any other task. That asymmetry is the
/// whole reason a repeating task works offline on one device and is correct on
/// every other one.
class SeriesStore {
  SeriesStore(this._db, this._poke, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AwDatabase _db;
  final void Function() _poke;
  final DateTime Function() _clock;

  Stream<TaskSeriesModel?> watch(String seriesId) =>
      (_db.select(_db.taskSeries)..where((s) => s.id.equals(seriesId)))
          .watchSingleOrNull()
          .map((row) => row == null ? null : TaskSeriesModel.fromRow(row));

  Future<TaskSeriesModel?> byId(String seriesId) async {
    final row = await (_db.select(
      _db.taskSeries,
    )..where((s) => s.id.equals(seriesId))).getSingleOrNull();
    return row == null ? null : TaskSeriesModel.fromRow(row);
  }

  /// Starts repeating [fromTaskId] on [rule].
  ///
  /// The occurrences appear when the server answers — including this task's own
  /// day, which the server ADOPTS rather than duplicating (OPH-205). Until then
  /// the rule is already local, so the detail screen can show its summary and
  /// the switch stays on across a restart.
  Future<String> create({
    required String workspaceId,
    required AwRepeatRule rule,
    required Map<String, dynamic> template,
    required DateTime anchorAt,
    String? timezone,
    String? fromTaskId,
  }) async {
    final id = newUlid();
    final ruleJson = rule.toJson();
    await _db.transaction(() async {
      await _db
          .into(_db.taskSeries)
          .insert(
            TaskSeriesCompanion.insert(
              id: id,
              workspaceId: workspaceId,
              ruleJson: jsonEncode(ruleJson),
              templateJson: jsonEncode(template),
              timezone: Value(timezone ?? 'Europe/Istanbul'),
              anchorAt: anchorAt.toUtc(),
              createdAt: Value(DateTime.now().toUtc()),
              updatedAt: Value(DateTime.now().toUtc()),
            ),
          );
      await enqueueMutation(
        _db,
        workspaceId: workspaceId,
        entityType: 'task_series',
        entityId: id,
        operation: 'create',
        patch: {
          'rule': ruleJson,
          'template': template,
          // Omitted on purpose when the caller has none: the SERVER fills it
          // from the user's own profile. A device can report "+03"; only the
          // server knows that means Europe/Istanbul (OPH-208).
          'timezone': ?timezone,
          'anchorAt': anchorAt.toUtc().toIso8601String(),
          'fromTaskId': ?fromTaskId,
        },
      );
      if (fromTaskId != null) {
        // Optimistic: the row the user is looking at joins the series now, so
        // the badge appears with the switch rather than after a round trip.
        await (_db.update(_db.tasks)..where((t) => t.id.equals(fromTaskId)))
            .write(TasksCompanion(seriesId: Value(id)));
      }
    });
    _poke();
    return id;
  }

  /// Replaces the rule. The server rebuilds the future in one transaction and
  /// the new occurrence rows arrive on the next pull.
  Future<void> updateRule({
    required String workspaceId,
    required String seriesId,
    required AwRepeatRule rule,
  }) async {
    final ruleJson = rule.toJson();
    await _db.transaction(() async {
      await (_db.update(
        _db.taskSeries,
      )..where((s) => s.id.equals(seriesId))).write(
        TaskSeriesCompanion(
          ruleJson: Value(jsonEncode(ruleJson)),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );
      await enqueueMutation(
        _db,
        workspaceId: workspaceId,
        entityType: 'task_series',
        entityId: seriesId,
        operation: 'update',
        patch: {'rule': ruleJson},
      );
    });
    _poke();
  }

  /// "Tekrarı durdur" — the future goes, the past stays (DESIGN §25 R7).
  ///
  /// The replica takes the stop NOW, in the same transaction that enqueues it,
  /// and by the server's own rule (`softDeleteSeries`, OPH-417) so the pull
  /// that follows changes nothing (#32, OPH-418):
  ///
  /// - [fromDay] ("this and future", undoing a quick add): open occurrences
  ///   on or after that day go; every other open one is kept and unlinked.
  /// - [keepTaskId] (the Repeat switch): the open occurrence the user stopped
  ///   on is kept and unlinked, and so is every earlier open one; open ones
  ///   AFTER its day go. Like the server (OPH-417), the cut is never before
  ///   the first open occurrence on or after today, so today's task stays.
  ///   The wire carries that boundary as `fromDay` = the next day, so device
  ///   and server cut at exactly the same place (the server's own "today"
  ///   lives in the series' zone, which could differ from this device's).
  ///   An after-completion series has nothing after its open occurrence and
  ///   sends no day (OPH-375); a kept task the replica has no day for yet
  ///   (adopted, not pulled) sends only its id and the server decides.
  ///
  /// Finished occurrences are history and are never touched (§20 C4).
  Future<void> stop({
    required String workspaceId,
    required String seriesId,
    String? fromDay,
    String? keepTaskId,
  }) async {
    await _db.transaction(() async {
      final seriesRow = await (_db.select(
        _db.taskSeries,
      )..where((s) => s.id.equals(seriesId))).getSingleOrNull();
      final afterCompletion =
          seriesRow != null &&
          (TaskSeriesModel.fromRow(seriesRow)?.rule.isAfterCompletion ?? false);
      await (_db.delete(
        _db.taskSeries,
      )..where((s) => s.id.equals(seriesId))).go();

      final open =
          await (_db.select(_db.tasks)..where(
                (t) =>
                    t.seriesId.equals(seriesId) &
                    t.status.isNotIn(_finishedStatuses),
              ))
              .get();
      final keep = fromDay == null ? keepTaskId : null;
      var cut = fromDay;
      final keptDay = keep == null || afterCompletion
          ? null
          : open.where((t) => t.id == keep).firstOrNull?.occurrenceDate;
      if (keptDay != null) {
        // OPH-417's reference day: the kept task's day, but never before the
        // first open occurrence on or after today — stopping from an overdue
        // one keeps today's task too.
        final today = awDayKey(_clock());
        final upcoming = [
          for (final t in open)
            if (t.occurrenceDate != null &&
                t.occurrenceDate!.compareTo(today) >= 0)
              t.occurrenceDate!,
        ]..sort();
        final head = upcoming.firstOrNull ?? today;
        cut = nextStopDay(keptDay.compareTo(head) >= 0 ? keptDay : head);
      }

      for (final row in open) {
        final day = row.occurrenceDate;
        if (cut != null && day != null && day.compareTo(cut) >= 0) {
          await _dropOccurrence(row.id);
        } else if (cut != null || afterCompletion || row.id == keep) {
          await (_db.update(
            _db.tasks,
          )..where((t) => t.id.equals(row.id))).write(
            const TasksCompanion(
              seriesId: Value(null),
              occurrenceDate: Value(null),
            ),
          );
        }
      }

      await enqueueMutation(
        _db,
        workspaceId: workspaceId,
        entityType: 'task_series',
        entityId: seriesId,
        operation: 'delete',
        // The same two options as `DELETE /task-series/:id?fromDay=&keepTaskId=`.
        patch: {'fromDay': ?cut, 'keepTaskId': ?keep},
      );
    });
    _poke();
  }

  // The server's FINISHED_STATUSES (task-series.js): an archived occurrence
  // is history too — the server keeps it and writes no revision for it, so
  // a row dropped here would never come back on a pull.
  static const _finishedStatuses = ['completed', 'cancelled', 'archived'];

  /// The server retires these with a task tombstone; the replica drops them
  /// the way that tombstone would, so nothing is left to flicker back.
  Future<void> _dropOccurrence(String taskId) async {
    await (_db.delete(_db.tasks)..where((t) => t.id.equals(taskId))).go();
    await (_db.delete(
      _db.taskTagRows,
    )..where((r) => r.taskId.equals(taskId))).go();
    await (_db.delete(
      _db.checklistItems,
    )..where((c) => c.taskId.equals(taskId))).go();
  }
}

/// The local day before [anchorAt] (`YYYY-MM-DD`). A series' occurrences are
/// on or after its anchor's day in the series' zone, which is at most a day
/// off this device's — so a stop from here takes every one of them (undoing a
/// quick add before its occurrences were pulled, #32).
String dayBeforeAnchor(DateTime anchorAt) {
  final local = anchorAt.toLocal();
  return awDayKey(DateTime(local.year, local.month, local.day - 1));
}

/// The day after [day] (`YYYY-MM-DD`), or null for anything else — then the
/// stop falls back to naming the kept task only.
String? nextStopDay(String day) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(day);
  if (m == null) return null;
  final next = DateTime.utc(
    int.parse(m[1]!),
    int.parse(m[2]!),
    int.parse(m[3]!),
  ).add(const Duration(days: 1));
  return awDayKey(next);
}
