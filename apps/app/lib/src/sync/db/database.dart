import 'package:drift/drift.dart';

part 'database.g.dart';

/// Local replica of the server's synced entities (OPH-054, BLUEPRINT §6).
/// Columns mirror the API serializers field for field (camelCase → snake in
/// SQL is handled by drift). MySQL stays canonical: rows here are snapshots
/// applied from `GET /sync/pull` plus optimistic local writes awaiting push.
@DataClassName('ProjectRecord')
class Projects extends Table {
  TextColumn get id => text()();
  TextColumn get workspaceId => text()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  TextColumn get colorRgb => text().withDefault(const Constant('#2563EB'))();
  TextColumn get icon => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('active'))();
  DateTimeColumn get startAt => dateTime().nullable()();
  DateTimeColumn get dueAt => dateTime().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  TextColumn get readmeNoteId => text().nullable()();
  IntColumn get revision => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('TagRecord')
class Tags extends Table {
  TextColumn get id => text()();
  TextColumn get workspaceId => text()();
  TextColumn get name => text()();
  TextColumn get slug => text()();
  TextColumn get colorRgb => text().withDefault(const Constant('#64748B'))();
  TextColumn get icon => text().nullable()();
  IntColumn get revision => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('TaskRecord')
class Tasks extends Table {
  TextColumn get id => text()();
  TextColumn get workspaceId => text()();
  TextColumn get projectId => text().nullable()();
  TextColumn get parentTaskId => text().nullable()();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('open'))();
  TextColumn get priority => text().withDefault(const Constant('none'))();
  TextColumn get colorRgb => text().nullable()();
  DateTimeColumn get startAt => dateTime().nullable()();
  DateTimeColumn get dueAt => dateTime().nullable()();
  DateTimeColumn get scheduledStartAt => dateTime().nullable()();
  DateTimeColumn get scheduledEndAt => dateTime().nullable()();
  DateTimeColumn get remindAt => dateTime().nullable()();
  DateTimeColumn get snoozedUntil => dateTime().nullable()();
  TextColumn get timezone =>
      text().withDefault(const Constant('Europe/Istanbul'))();
  BoolColumn get isUrgent => boolean().withDefault(const Constant(false))();
  BoolColumn get requiresAcknowledgement =>
      boolean().withDefault(const Constant(false))();
  TextColumn get repeatRule => text().nullable()();
  IntColumn get estimatedMinutes => integer().nullable()();
  IntColumn get actualMinutes => integer().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  // OPH-081 — opt-in mirroring to the connected calendar (BLUEPRINT §7.1).
  // Added in schema v2; NOT NULL + default matches the server column.
  BoolColumn get calendarMirrorEnabled =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get completedAt => dateTime().nullable()();
  IntColumn get revision => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// The user's OWN calendar events (OPH-083, ADR-0008) — meetings and
/// appointments AllisWell did not create. Read-only: nothing here is ever
/// pushed, so there is no outbox path and no revision bookkeeping beyond the
/// server's. Added in schema v3.
@DataClassName('ExternalEventRecord')
class ExternalEvents extends Table {
  TextColumn get id => text()();
  TextColumn get workspaceId => text()();
  TextColumn get summary => text().nullable()();
  TextColumn get location => text().nullable()();
  DateTimeColumn get startsAt => dateTime()();
  DateTimeColumn get endsAt => dateTime()();
  BoolColumn get isAllDay => boolean().withDefault(const Constant(false))();
  BoolColumn get isBusy => boolean().withDefault(const Constant(true))();
  TextColumn get htmlLink => text().nullable()();
  IntColumn get revision => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class TaskTagRows extends Table {
  TextColumn get taskId => text()();
  TextColumn get tagId => text()();

  @override
  Set<Column<Object>> get primaryKey => {taskId, tagId};
}

@DataClassName('ChecklistItemRecord')
class ChecklistItems extends Table {
  TextColumn get id => text()();
  TextColumn get taskId => text()();
  TextColumn get title => text()();
  BoolColumn get isDone => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  IntColumn get revision => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('NoteRecord')
class Notes extends Table {
  TextColumn get id => text()();
  TextColumn get workspaceId => text()();
  TextColumn get projectId => text().nullable()();
  TextColumn get createdFromTaskId => text().nullable()();
  TextColumn get title => text()();

  /// Quill delta ops as a JSON string (canonical content, §9.1).
  TextColumn get contentDelta => text().nullable()();
  TextColumn get contentMarkdown => text().nullable()();
  TextColumn get plainText => text().nullable()();
  BoolColumn get isPinned => boolean().withDefault(const Constant(false))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  IntColumn get revision => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class NoteLinkRows extends Table {
  TextColumn get id => text()();
  TextColumn get noteId => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Reminders extends Table {
  TextColumn get id => text()();
  TextColumn get taskId => text()();
  DateTimeColumn get remindAt => dateTime()();
  TextColumn get timezone =>
      text().withDefault(const Constant('Europe/Istanbul'))();
  TextColumn get alarmLevel => text().withDefault(const Constant('normal'))();
  BoolColumn get requiresAcknowledgement =>
      boolean().withDefault(const Constant(false))();
  TextColumn get repeatRule => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('scheduled'))();
  DateTimeColumn get snoozedUntil => dateTime().nullable()();
  DateTimeColumn get deliveredAt => dateTime().nullable()();
  DateTimeColumn get acknowledgedAt => dateTime().nullable()();
  IntColumn get revision => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// The offline outbox (OPH-055, BLUEPRINT §6.3): one row per local write, in
/// creation order. `id` doubles as the server-visible `clientMutationId`, so
/// retries stay idempotent end to end.
class PendingMutations extends Table {
  TextColumn get id => text()();
  TextColumn get workspaceId => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();

  /// create | update | delete
  TextColumn get operation => text()();

  /// JSON-encoded patch (absent for deletes).
  TextColumn get patchJson => text().nullable()();
  DateTimeColumn get localUpdatedAt => dateTime()();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Per-workspace sync cursor + the client identity used for push idempotency.
class SyncStates extends Table {
  TextColumn get workspaceId => text()();
  TextColumn get clientId => text()();
  IntColumn get lastRevision => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastPulledAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {workspaceId};
}

@DriftDatabase(
  tables: [
    Projects,
    Tags,
    Tasks,
    TaskTagRows,
    ChecklistItems,
    Notes,
    NoteLinkRows,
    Reminders,
    ExternalEvents,
    PendingMutations,
    SyncStates,
  ],
)
class AwDatabase extends _$AwDatabase {
  AwDatabase(super.e);

  /// Bump this for every schema change AND add the matching step below.
  /// v1 → v2 (OPH-081): tasks.calendar_mirror_enabled.
  /// v2 → v3 (OPH-083): external_events (the user's own calendar).
  @override
  int get schemaVersion => 3;

  /// The replica is disposable cache — MySQL is canonical (AGENTS.md §6) — but
  /// it is NOT expendable: it holds the outbox, so a failed open would strand
  /// writes that never reached the server. Hence a real migration rather than
  /// "wipe and re-pull".
  ///
  /// One `if (from < n)` per version, in order, each one narrow enough to be
  /// obviously correct. (Drift's generated `stepByStep` would be nicer, but it
  /// needs `drift_dev schema dump`, which this toolchain cannot run — see the
  /// OPH-081 migration plan in docs/TASKS.md.)
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      // v2 (OPH-081): opt-in calendar mirroring. ADD COLUMN with a NOT NULL
      // default — existing rows take `false`, nothing is rewritten.
      if (from < 2) await m.addColumn(tasks, tasks.calendarMirrorEnabled);
      // v3 (OPH-083): the user's own calendar events. A brand new table, so
      // nothing existing is touched; the next pull fills it.
      if (from < 3) await m.createTable(externalEvents);
    },
  );
}
