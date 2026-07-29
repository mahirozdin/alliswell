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
  SeriesStore(this._db, this._poke);

  final AwDatabase _db;
  final void Function() _poke;

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
    required String timezone,
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
              timezone: Value(timezone),
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
          'timezone': timezone,
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
  /// Locally we only drop the rule row: which occurrences survive is the
  /// server's decision (it keeps everything finished), and guessing here would
  /// make the list flicker into a state that is about to be corrected.
  Future<void> stop({
    required String workspaceId,
    required String seriesId,
  }) async {
    await _db.transaction(() async {
      await (_db.delete(
        _db.taskSeries,
      )..where((s) => s.id.equals(seriesId))).go();
      await enqueueMutation(
        _db,
        workspaceId: workspaceId,
        entityType: 'task_series',
        entityId: seriesId,
        operation: 'delete',
        patch: const {},
      );
    });
    _poke();
  }
}
