import '../tasks/data/task.dart';
import '../tasks/data/task_store.dart' show kPlanningStatuses;

/// One card of a Board column: a task, and how many later occurrences of its
/// series the card stands for (OPH-394, E-25).
class BoardEntry {
  const BoardEntry(this.task, {this.moreOccurrences = 0});

  final Task task;

  /// Later open occurrences of the same series folded into this card.
  final int moreOccurrences;
}

/// A column's cards: a repeating task shows only its NEXT occurrence, with a
/// "+N" for the rest (OPH-394, E-25).
///
/// The server materializes a series ahead of time, so an open column used to
/// list every future "Invoice Acme", newest first, and its count grew with the
/// rule rather than with the work. Only planning statuses fold: a finished or
/// cancelled occurrence is history, and each one happened on its own day.
///
/// The column keeps its order; the folded card sits where its next occurrence
/// sat.
List<BoardEntry> foldBoardSeries(String status, List<Task> tasks) {
  if (!kPlanningStatuses.contains(status)) {
    return [for (final task in tasks) BoardEntry(task)];
  }
  final bySeries = <String, List<Task>>{};
  for (final task in tasks) {
    final series = task.seriesId;
    if (series != null && series.isNotEmpty) {
      bySeries.putIfAbsent(series, () => []).add(task);
    }
  }
  final next = <String, Task>{
    for (final MapEntry(:key, :value) in bySeries.entries)
      key: value.reduce((a, b) => _occursBefore(b, a) ? b : a),
  };
  return [
    for (final task in tasks)
      if (task.seriesId == null || task.seriesId!.isEmpty)
        BoardEntry(task)
      else if (identical(next[task.seriesId], task))
        BoardEntry(task, moreOccurrences: bySeries[task.seriesId]!.length - 1),
  ];
}

/// The slot first (`YYYY-MM-DD` sorts as text), then the deadline, then the
/// id — so the choice never depends on the order the sync wrote rows in.
bool _occursBefore(Task a, Task b) {
  final byDate = (a.occurrenceDate ?? '').compareTo(b.occurrenceDate ?? '');
  if (byDate != 0) return byDate < 0;
  final [da, db] = [a.dueAt, b.dueAt];
  if (da != null && db != null && da != db) return da.isBefore(db);
  if ((da == null) != (db == null)) return da != null;
  return a.id.compareTo(b.id) < 0;
}
