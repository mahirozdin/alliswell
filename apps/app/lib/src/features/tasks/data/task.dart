/// Mirrors the API's task shape (apps/api routes/tasks.js). `tagIds` and
/// `checklist` are only present on detail responses — list rows keep them empty.
class Task {
  const Task({
    required this.id,
    required this.workspaceId,
    required this.title,
    required this.status,
    required this.priority,
    required this.timezone,
    required this.isUrgent,
    required this.requiresAcknowledgement,
    required this.sortOrder,
    required this.revision,
    this.calendarMirrorEnabled = false,
    this.projectId,
    this.parentTaskId,
    this.description,
    this.colorRgb,
    this.startAt,
    this.dueAt,
    this.scheduledStartAt,
    this.scheduledEndAt,
    this.remindAt,
    this.snoozedUntil,
    this.completedAt,
    this.tagIds = const [],
    this.checklist = const [],
  });

  factory Task.fromJson(Map<String, dynamic> json) => Task(
    id: json['id'] as String,
    workspaceId: json['workspaceId'] as String,
    projectId: json['projectId'] as String?,
    parentTaskId: json['parentTaskId'] as String?,
    title: json['title'] as String,
    description: json['description'] as String?,
    status: json['status'] as String,
    priority: json['priority'] as String,
    colorRgb: json['colorRgb'] as String?,
    startAt: _date(json['startAt']),
    dueAt: _date(json['dueAt']),
    scheduledStartAt: _date(json['scheduledStartAt']),
    scheduledEndAt: _date(json['scheduledEndAt']),
    remindAt: _date(json['remindAt']),
    snoozedUntil: _date(json['snoozedUntil']),
    completedAt: _date(json['completedAt']),
    timezone: json['timezone'] as String,
    isUrgent: json['isUrgent'] as bool,
    requiresAcknowledgement: json['requiresAcknowledgement'] as bool,
    calendarMirrorEnabled: (json['calendarMirrorEnabled'] as bool?) ?? false,
    sortOrder: json['sortOrder'] as int,
    revision: json['revision'] as int,
    tagIds: ((json['tagIds'] as List?) ?? const []).cast<String>(),
    checklist: ((json['checklist'] as List?) ?? const [])
        .map((i) => ChecklistItem.fromJson(i as Map<String, dynamic>))
        .toList(),
  );

  final String id;
  final String workspaceId;
  final String? projectId;
  final String? parentTaskId;
  final String title;
  final String? description;
  final String status;
  final String priority;
  final String? colorRgb;
  final DateTime? startAt;
  final DateTime? dueAt;

  /// When you plan to actually DO it — the calendar block (§7.1). Dragging the
  /// mirrored event in Google lands here (OPH-076), which is why the detail
  /// screen shows it.
  final DateTime? scheduledStartAt;
  final DateTime? scheduledEndAt;
  final DateTime? remindAt;
  final DateTime? snoozedUntil;
  final DateTime? completedAt;

  /// What §7.1 would build an event from — nothing to mirror without one.
  bool get hasCalendarTime =>
      scheduledStartAt != null ||
      dueAt != null ||
      (isUrgent && remindAt != null);
  final String timezone;
  final bool isUrgent;
  final bool requiresAcknowledgement;

  /// Opt-in: mirror this task into the connected calendar (OPH-072/081).
  final bool calendarMirrorEnabled;
  final int sortOrder;
  final int revision;
  final List<String> tagIds;
  final List<ChecklistItem> checklist;

  bool get isCompleted => status == 'completed';
}

class ChecklistItem {
  const ChecklistItem({
    required this.id,
    required this.title,
    required this.isDone,
    required this.sortOrder,
  });

  factory ChecklistItem.fromJson(Map<String, dynamic> json) => ChecklistItem(
    id: json['id'] as String,
    title: json['title'] as String,
    isDone: json['isDone'] as bool,
    sortOrder: (json['sortOrder'] as int?) ?? 0,
  );

  final String id;
  final String title;
  final bool isDone;
  final int sortOrder;
}

DateTime? _date(Object? value) =>
    value == null ? null : DateTime.parse(value as String);

const kTaskStatuses = [
  'inbox',
  'open',
  'scheduled',
  'in_progress',
  'waiting',
  'completed',
  'cancelled',
  'archived',
];

const kTaskPriorities = ['none', 'low', 'medium', 'high', 'urgent'];
