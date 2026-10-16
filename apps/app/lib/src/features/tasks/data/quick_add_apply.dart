import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import '../../../core/date_format.dart';
import '../../../core/day_boundary.dart';
import '../../../core/fold.dart';
import '../../../core/persisted_prefs.dart';
import '../../../core/quick_parse.dart';
import '../../../i18n/i18n.dart';
import '../../projects/providers.dart';
import '../../../sync/providers.dart';
import '../../tags/tags.dart';
import '../../workspaces/workspaces.dart';
import '../providers.dart';
import 'task_defaults.dart';
import 'task_when.dart';

/// Turning an offline quick-add parse (OPH-373, `core/quick_parse.dart`) into
/// a task — Riverpod-level and BuildContext-free, so the bars and the
/// headless capture paths (OPH-376) create the same task from the same text.

/// A `ref.read` tear-off (the [createOwnTask] convention).
typedef AwRead = T Function<T>(ProviderListenable<T>);

/// What a quick-add bar hands its owner on Enter: the raw text (the ✨ AI
/// rider and error messages want it) and the parse the user saw.
class QuickAddSubmission {
  const QuickAddSubmission({required this.raw, required this.parse});

  /// A submission with no recognitions — for callers that have plain text.
  factory QuickAddSubmission.plain(String title) => QuickAddSubmission(
    raw: title,
    parse: AwQuickParse(title: title, tokens: const [], chips: const []),
  );

  final String raw;
  final AwQuickParse parse;
}

/// The parser's view of the user's settings.
///
/// - `now` from [nowProvider], so tests and the day boundary agree;
/// - a day-only deadline lands on the default task time (OPH-161);
/// - `5/11` is month-first only under the US format preference, or when the
///   format follows an English UI;
/// - weeks start on Monday — the app has no week-start setting, and the
///   month grid and the recurrence engine are Monday-first (ADR-0020).
AwQuickParseOptions quickParseOptions(
  AwRead read, {
  bool parseProject = true,
  Set<String> ignored = const {},
}) {
  final (hour, minute) = parseTaskTime(read(defaultTaskTimeProvider));
  final format = read(dateFormatProvider);
  final monthFirst =
      format == 'mdy_12h' ||
      (format == kAwSystemDateFormat &&
          AwI18n.instance.locale.languageCode == 'en');
  final projects = parseProject
      ? (read(projectsControllerProvider).value ?? const [])
      : const [];
  return AwQuickParseOptions(
    now: read(nowProvider)(),
    defaultHour: hour,
    defaultMinute: minute,
    monthFirstSlash: monthFirst,
    parseProject: parseProject,
    projects: [
      for (final p in projects)
        if (p.status != 'archived') AwQuickProject(id: p.id, name: p.name),
    ],
    ignored: ignored,
  );
}

/// The create body for [parse] (tags excluded — they need ids first).
///
/// [withDefaults] applies the round-14 quick-add defaults (medium priority,
/// urgent alarm, reminder an hour before a deadline — `task_defaults.dart`);
/// without them a deadline still arms its derived reminder (DESIGN §26 C2).
/// A typed priority always wins. [dueAt] is the fallback deadline when the
/// text gave none (Home's date picker).
Map<String, dynamic> quickParseBody(
  AwQuickParse parse, {
  required bool withDefaults,
  DateTime? dueAt,
}) {
  final due = parse.dueAt ?? dueAt;
  return {
    'title': parse.title,
    if (withDefaults)
      ...awQuickTaskDefaults(dueAt: due)
    else if (due != null) ...{
      'dueAt': due.toUtc().toIso8601String(),
      'remindAt': awAutoReminderFor(due)!.toUtc().toIso8601String(),
    },
    if (parse.whenDay != null) 'startAt': awWhenIso(parse.whenDay!),
    if (parse.project != null) 'projectId': parse.project!.id,
    if (parse.priority != null) 'priority': parse.priority,
  };
}

/// Tag ids for [names] in [workspaceId]: an existing tag whose fold matches
/// is reused ("#Ev" finds "ev"), a missing one is created — the tag field's
/// own rule (`tag_input.dart`).
Future<List<String>> resolveQuickTags(
  AwRead read,
  String workspaceId,
  List<String> names,
) async {
  if (names.isEmpty) return const [];
  // Straight from the replica, not `workspaceTagsProvider(...).future`: a
  // stream nobody listens to is paused, and a headless caller has no widget
  // listening (LESSONS flutter-app).
  final db = read(databaseProvider);
  final existing = await (db.select(
    db.tags,
  )..where((t) => t.workspaceId.equals(workspaceId))).get();
  final ids = <String>[];
  for (final name in names) {
    final folded = foldSearchText(name);
    String? id;
    for (final tag in existing) {
      if (foldSearchText(tag.name) == folded) {
        id = tag.id;
        break;
      }
    }
    id ??= await read(tagStoreProvider).create(workspaceId, name);
    if (!ids.contains(id)) ids.add(id);
  }
  return ids;
}

/// Create the task [parse] describes, in the workspace on screen.
///
/// [base] carries the surface's own fields (Inbox's `status`, the project
/// tab's `projectId` — which wins over a parsed one). [claim] puts the author
/// on it in an organisation (Home and Inbox; [createOwnTask]). A recurrence
/// starts a series that adopts the new task as its first occurrence, with the
/// create sheet's template fields (OPH-208). Returns the id, or null without
/// a workspace.
Future<String?> createFromQuickParse(
  AwRead read, {
  required AwQuickParse parse,
  Map<String, dynamic> base = const {},
  required bool withDefaults,
  DateTime? dueAt,
  bool claim = true,
}) async {
  final workspaceId = await read(activeWorkspaceIdProvider.future);
  if (workspaceId == null) return null;
  final tagIds = await resolveQuickTags(read, workspaceId, parse.tagNames);
  final body = <String, dynamic>{
    ...quickParseBody(parse, withDefaults: withDefaults, dueAt: dueAt),
    ...base,
    if (tagIds.isNotEmpty) 'tagIds': tagIds,
  };
  final id = await read(taskStoreProvider).create(workspaceId, body);
  if (claim) {
    await claimIfShared(read, workspaceId: workspaceId, taskId: id);
  }
  final rule = parse.repeat;
  final anchor = parse.dueAt;
  if (rule != null && anchor != null) {
    await read(seriesStoreProvider).create(
      workspaceId: workspaceId,
      rule: rule,
      template: {
        'title': body['title'],
        'description': null,
        'projectId': body['projectId'],
        'priority': body['priority'] ?? 'none',
        'isUrgent': body['isUrgent'] ?? false,
        'tagIds': tagIds,
      },
      anchorAt: anchor,
      fromTaskId: id,
    );
  }
  return id;
}
