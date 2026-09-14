import '../../../core/fold.dart';
import '../../../core/list_sort.dart';
import 'task.dart';

/// How a list of tasks can be ordered (OPH-305, DESIGN §34).
///
/// Sorting reached notes in round 18 and files soon after, and never reached
/// the one list people spend their day in. The report that fixed that asked for
/// it by name: *"any methods to sort and categorise upcoming tasks … listed by
/// the order of 'priority'"*.
///
/// `date` is first, and first is what an unrecognised preference falls back to
/// (`AwSortState.parse`) — so a preference that outlives its option restores
/// the order Home has always had rather than reshuffling somebody's day.
///
/// Like every other sort in the app this is a VIEWING preference: device-local,
/// never synced (§34). Two people looking at the same workspace may order it
/// differently without arguing through the sync engine.
///
/// `date` is deliberately the one sort here whose natural direction is
/// ASCENDING. Everywhere else in the app a date means "newest first" — the note
/// you edited last, the file you added last. A task's date is a deadline, and
/// the deadline you want at the top is the nearest one.
const List<AwSortChoice> kTaskSortChoices = [
  AwSortChoice(
    id: 'date',
    labelKey: 'sort.taskDate',
    descendingByDefault: false,
  ),
  AwSortChoice(id: 'priority', labelKey: 'sort.taskPriority'),
  AwSortChoice(id: 'title', labelKey: 'sort.title', descendingByDefault: false),
];

/// Where a priority ranks, ascending — `none` lowest, `urgent` highest.
///
/// `kTaskPriorities` is already written in that order, so the index IS the
/// rank; spelling it out again here would be a second source of truth that
/// only has to disagree once. An unknown value (a newer peer's, a hand-edited
/// row) ranks lowest rather than throwing: a list that will not render is worse
/// than a task in the wrong place.
int taskPriorityRank(String priority) {
  final index = kTaskPriorities.indexOf(priority);
  return index < 0 ? 0 : index;
}

/// The key a title sorts by.
///
/// Folded, because neither SQLite nor MySQL folds `ı`→`i` (ADR-0013) and the
/// app owns that rule. A sort that disagreed with the app's own search about
/// where "Islak" goes would be its own bug.
String taskTitleKey(String title) => foldSearchText(title);
