import 'package:drift/drift.dart';

import '../../core/fold.dart';

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
  // ADR-0013 (v6): folded shadows for search.
  TextColumn get nameFold => text().nullable()();
  TextColumn get descriptionFold => text().nullable()();
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
  // ADR-0013 (v6): folded shadow of [name] — search matches run on this.
  // Writers (stores + applier) MUST keep it in step via foldSearchText.
  TextColumn get nameFold => text().nullable()();
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

  /// Silenced indefinitely since this instant (OPH-178); null = alarms live.
  /// A muted task keeps its dates and stays OPEN — silence is not completion.
  DateTimeColumn get alarmsMutedAt => dateTime().nullable()();
  TextColumn get timezone =>
      text().withDefault(const Constant('Europe/Istanbul'))();
  BoolColumn get isUrgent => boolean().withDefault(const Constant(false))();
  BoolColumn get requiresAcknowledgement =>
      boolean().withDefault(const Constant(false))();

  /// Frozen since OPH-205 (ADR-0020 §7): recurrence lives in [TaskSeries] now.
  /// The column stays because the server's does; nothing reads or writes it.
  TextColumn get repeatRule => text().nullable()();

  /// Which series produced this task, and which day of it this is (v14,
  /// OPH-205). Server-owned: the client never writes them, it learns them from
  /// the pull. `occurrenceDate` is the series SLOT (`YYYY-MM-DD`, immutable) —
  /// `dueAt` is when the occurrence actually happens and may be moved.
  TextColumn get seriesId => text().nullable()();
  TextColumn get occurrenceDate => text().nullable()();
  IntColumn get estimatedMinutes => integer().nullable()();
  IntColumn get actualMinutes => integer().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  // OPH-081 — opt-in mirroring to the connected calendar (BLUEPRINT §7.1).
  // Added in schema v2; NOT NULL + default matches the server column.
  BoolColumn get calendarMirrorEnabled =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get completedAt => dateTime().nullable()();
  // ADR-0013 (v6): folded shadows for search (title > … > description).
  TextColumn get titleFold => text().nullable()();
  TextColumn get descriptionFold => text().nullable()();
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
  // ADR-0013 (v6): folded shadows — Home search covers the calendar too.
  TextColumn get summaryFold => text().nullable()();
  TextColumn get locationFold => text().nullable()();
  IntColumn get revision => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Attachment metadata (OPH-153, Epic 14, ADR-0011) — pull-only like
/// [ExternalEvents]: the binaries live in object storage (R2), only verified
/// `ready` rows ever sync, and writes are REST + `syncNow()` — so there is no
/// outbox path for this table and the server is the only writer. Added in
/// schema v5.
@DataClassName('FileRecord')
class FileRows extends Table {
  TextColumn get id => text()();
  TextColumn get workspaceId => text()();

  /// `project` | `task` | `note` — who this file hangs off.
  TextColumn get targetType => text()();
  TextColumn get targetId => text()();
  TextColumn get name => text()();
  TextColumn get mime => text()();
  IntColumn get sizeBytes => integer()();

  /// Always `ready` in practice (uploading rows never sync) — kept so the
  /// shape mirrors the server serializer field-for-field.
  TextColumn get status => text()();
  TextColumn get uploadedBy => text().nullable()();

  /// Folder membership — workspace-target files only (v7, ADR-0014).
  TextColumn get folderId => text().nullable()();
  IntColumn get revision => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// User folders for the global Dosyalar section (OPH-170, ADR-0014) —
/// push-pull like projects/tags: pure metadata, offline create/rename/move.
/// Added in schema v7.
@DataClassName('FolderRecord')
class Folders extends Table {
  TextColumn get id => text()();
  TextColumn get workspaceId => text()();
  TextColumn get parentId => text().nullable()();
  TextColumn get name => text()();
  IntColumn get revision => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// The user's personal shortcut rail (OPH-198, ADR-0018, BLUEPRINT §4.12) —
/// push-pull like folders, but USER-scoped: the server only ever sends rows
/// belonging to the signed-in user, and `watchMine` filters by [userId] again
/// locally, because one device can outlive a sign-out. Added in schema v13.
///
/// There is no `deletedAt` here, deliberately: no replica table has one. A
/// tombstone deletes the row (sync_applier), which is also what makes the
/// server's "drop invisible rows" rule safe.
@DataClassName('QuickLinkRecord')
class QuickLinks extends Table {
  TextColumn get id => text()();
  TextColumn get workspaceId => text()();
  TextColumn get userId => text()();

  /// `project | task | note | folder | file | url`.
  TextColumn get kind => text()();

  /// The entity this points at — null for `url` rows. Stored as an id, never
  /// as a route string (ADR-0016: routes are a client concern).
  TextColumn get targetId => text().nullable()();
  TextColumn get url => text().nullable()();
  TextColumn get title => text()();
  TextColumn get emoji => text().nullable()();
  TextColumn get colorRgb => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  IntColumn get revision => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// A recurrence rule and the template its occurrences are stamped with
/// (OPH-205, ADR-0020). Added in schema v14.
///
/// The occurrences themselves are ordinary rows in [Tasks] — this table exists
/// so the edit dialog shows the same rule on every device, and so the "next 5"
/// preview can be computed offline. The client NEVER generates occurrences:
/// they arrive over sync like any other task.
@DataClassName('TaskSeriesRecord')
class TaskSeries extends Table {
  TextColumn get id => text()();
  TextColumn get workspaceId => text()();

  /// The ADR-0020 rule object, stored as JSON text (drift has no JSON column
  /// and the rule is read and written whole — never field by field).
  TextColumn get ruleJson => text()();

  /// Task fields every occurrence inherits (title, project, priority…), JSON.
  TextColumn get templateJson => text()();
  TextColumn get timezone =>
      text().withDefault(const Constant('Europe/Istanbul'))();

  /// Seed instant: the pattern's first candidate day and the time of day every
  /// occurrence inherits.
  DateTimeColumn get anchorAt => dateTime()();
  IntColumn get revision => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

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

  /// Which of the two above is CANONICAL (v17, OPH-248, ADR-0028 §1).
  ///
  /// `'delta'` or `'markdown'`. Defaulted rather than nullable so the replica
  /// answers the same way the server does for every row that predates the
  /// column — the migration backfills nothing because it does not have to.
  TextColumn get contentFormat => text().withDefault(const Constant('delta'))();
  TextColumn get plainText => text().nullable()();
  BoolColumn get isPinned => boolean().withDefault(const Constant(false))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  // ADR-0013 (v6): folded shadows (body = the delta's plain text).
  TextColumn get titleFold => text().nullable()();
  TextColumn get bodyFold => text().nullable()();
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

  /// Which alarm this is (OPH-175): `remind` (the nudge the user asked for) or
  /// `due` (an urgent task's own deadline). Server-owned; a task can hold one
  /// active row of each.
  TextColumn get kind => text().withDefault(const Constant('remind'))();

  /// How many snooze rounds this alarm has been through (OPH-177) — the
  /// post-snooze alert says WHICH round it is. Reset when the alarm is re-armed
  /// to a new instant: a moved deadline is a new alarm.
  IntColumn get snoozeCount => integer().withDefault(const Constant(0))();
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

/// The local alarm log (OPH-176, DESIGN §11 A6). Device-only — NEVER synced and
/// never pushed: it exists so a delivery question ("which sound? which lane?
/// was it even scheduled?") is answered by a record instead of a memory. Kept to
/// [kAlarmLogLimit] newest rows.
class AlarmEvents extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// When we recorded it (UTC).
  DateTimeColumn get at => dateTime()();

  /// `scheduled` | `cancelled` | `interacted` | `action` | `ring_shown` |
  /// `degraded`.
  TextColumn get event => text()();

  /// `notification` | `alarmkit` | `inapp`.
  TextColumn get lane => text()();

  /// The alarm's kind (`remind`/`due`) where one is known.
  TextColumn get kind => text().nullable()();

  /// Which slot of the re-alert chain, 0-based.
  IntColumn get slotIndex => integer().nullable()();
  BoolColumn get urgent => boolean().withDefault(const Constant(false))();

  /// What we ASKED the OS for (see `ScheduledDelivery`).
  TextColumn get sound => text().nullable()();
  TextColumn get level => text().nullable()();

  /// The instant the alarm was scheduled to fire (UTC), when applicable.
  DateTimeColumn get fireAt => dateTime().nullable()();
  TextColumn get taskId => text().nullable()();
  TextColumn get reminderId => text().nullable()();

  /// Free-form extra (an action id, a degradation reason).
  TextColumn get detail => text().nullable()();
}

/// How many alarm-log rows the device keeps (a ring buffer, newest first).
const int kAlarmLogLimit = 200;

/// The AI bubble's chat history (OPH-221, Epic 20, ADR-0019). Device-only —
/// NEVER synced and never pushed: a synced `conversation` entity would change
/// the privacy stance and is a parked, deliberate decision. Ring-buffered to
/// [kAiMessageLimit] newest rows, exactly like the alarm log.
class AiMessages extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get workspaceId => text()();

  /// `user` | `assistant`.
  TextColumn get role => text()();

  /// The final text (a stream is buffered in memory; the row is written on
  /// done / cancel / error).
  TextColumn get content => text()();

  /// `done` | `cancelled` | `error`.
  TextColumn get status => text().withDefault(const Constant('done'))();

  /// The packed context bundle summary for the message's context chip (user
  /// rows), as JSON. Null on assistant rows.
  TextColumn get contextJson => text().nullable()();

  /// Correlates with the server's requestId, where one exists.
  TextColumn get requestId => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();
}

/// How many AI chat rows the device keeps (a ring buffer, newest first).
const int kAiMessageLimit = 200;

/// The share pipeline's own record (OPH-242). Device-only, like the alarm log
/// and for the same reason: round 17 opened with "I shared a text and nothing
/// happened — not even a crash report", and nothing in the app could confirm or
/// deny it. Every inbound share now leaves a row.
///
/// The most valuable reading of this table is an EMPTY one: zero rows after a
/// share attempt proves the payload never reached Dart, which places the fault
/// on the native side (the URL scheme, the App Group, the OS) rather than in
/// the app's routing.
///
/// Content is never stored — only its size — so the log stays safe to copy into
/// a bug report.
class ShareEvents extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// When we recorded it (UTC).
  DateTimeColumn get at => dateTime()();

  /// `initial_share` | `warm_share` | `initial_document` | `warm_document` |
  /// `read_failed` | `consumed`.
  TextColumn get event => text()();

  /// `text` | `url` | `markdown`, where the shape is known.
  TextColumn get payloadKind => text().nullable()();

  /// How much arrived — never WHAT arrived.
  IntColumn get bytes => integer().nullable()();

  /// Free-form extra: a file's extension, an error's runtime type. Never
  /// payload text, never a full path.
  TextColumn get detail => text().nullable()();
}

/// How many share-log rows the device keeps (a ring buffer, newest first).
/// Smaller than the alarm log: shares are rare and only the recent ones answer
/// "did the last thing I tried arrive?".
const int kShareLogLimit = 100;

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

/// Task → Apple calendar event mapping (OPH-078). Device-LOCAL, never synced:
/// Apple events live on this device (EventKit has no server), so this table is
/// per-install state like [SyncStates], not a replicated entity. One row per
/// mirrored task; [signature] is the last-written content fingerprint, so a
/// reconcile can skip EventKit when nothing a calendar shows has changed.
///
/// Row class renamed to avoid colliding with the domain `AppleEventLink` in
/// `apple_mirror.dart` (the pure type the engine and tests speak in).
@DataClassName('AppleEventLinkRow')
class AppleEventLinks extends Table {
  TextColumn get taskId => text()();
  TextColumn get calendarId => text()();
  TextColumn get eventId => text()();
  TextColumn get signature => text()();

  @override
  Set<Column<Object>> get primaryKey => {taskId};
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
    AppleEventLinks,
    FileRows,
    Folders,
    QuickLinks,
    TaskSeries,
    AlarmEvents,
    AiMessages,
    ShareEvents,
    PendingMutations,
    SyncStates,
  ],
)
class AwDatabase extends _$AwDatabase {
  AwDatabase(super.e);

  /// Bump this for every schema change AND add the matching step below.
  /// v1 → v2 (OPH-081): tasks.calendar_mirror_enabled.
  /// v2 → v3 (OPH-083): external_events (the user's own calendar).
  /// v3 → v4 (OPH-078): apple_event_links (device-local Apple mirror map).
  /// v4 → v5 (OPH-153): file_rows (attachment metadata, pull-only).
  /// v5 → v6 (OPH-167): `*_fold` search shadows (ADR-0013) + Dart backfill.
  /// v6 → v7 (OPH-170): folders + file_rows.folder_id (ADR-0014).
  /// v11 → v12 (OPH-186): `idx_tasks_completed` for the Completed archive.
  /// v12 → v13 (OPH-198): quick_links, the personal shortcut rail (ADR-0018).
  /// v13 → v14 (OPH-205): task_series + tasks.series_id/occurrence_date
  /// (ADR-0020) — recurring tasks.
  /// v14 → v15 (OPH-221): ai_messages, the AI bubble's device-local chat
  /// history (ADR-0019 — NOT a sync entity; the decision is written).
  /// v15 → v16 (OPH-242): share_events, the share pipeline's device-local
  /// diagnostic trail — content-free, never synced.
  @override
  int get schemaVersion => 17;

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
    onCreate: (m) async {
      await m.createAll();
      // Ad-hoc indexes are not part of the generated schema, so a fresh install
      // has to create them explicitly — `createAll` alone would leave new users
      // on the scan path the v12 step exists to remove.
      await _createCompletedIndex();
    },
    onUpgrade: (m, from, to) async {
      // v2 (OPH-081): opt-in calendar mirroring. ADD COLUMN with a NOT NULL
      // default — existing rows take `false`, nothing is rewritten.
      if (from < 2) await m.addColumn(tasks, tasks.calendarMirrorEnabled);
      // v3 (OPH-083): the user's own calendar events. A brand new table, so
      // nothing existing is touched; the next pull fills it.
      if (from < 3) await m.createTable(externalEvents);
      // v4 (OPH-078): device-local Apple mirror map. New table, untouched data.
      if (from < 4) await m.createTable(appleEventLinks);
      // v5 (OPH-153): attachment metadata. New pull-only table; the next
      // sync pull fills it — nothing existing is touched.
      if (from < 5) await m.createTable(fileRows);
      // v6 (OPH-167, ADR-0013): folded search shadows. Columns are nullable
      // (no rewrite on ADD), then a one-time Dart backfill folds existing
      // rows — the fold CANNOT run in SQL, that is the whole point.
      if (from < 6) {
        await m.addColumn(projects, projects.nameFold);
        await m.addColumn(projects, projects.descriptionFold);
        await m.addColumn(tags, tags.nameFold);
        await m.addColumn(tasks, tasks.titleFold);
        await m.addColumn(tasks, tasks.descriptionFold);
        await m.addColumn(notes, notes.titleFold);
        await m.addColumn(notes, notes.bodyFold);
        // external_events only exists pre-v6 for installs that were ≥ v3;
        // older ones just got it CREATED above with the current definition —
        // fold columns included — and a second ADD would throw.
        if (from >= 3) {
          await m.addColumn(externalEvents, externalEvents.summaryFold);
          await m.addColumn(externalEvents, externalEvents.locationFold);
        }
        await backfillSearchFolds(this);
      }
      // v7 (OPH-170, ADR-0014): the folder tree + file membership. New table
      // + one nullable column — existing rows untouched, the next pull fills.
      if (from < 7) {
        await m.createTable(folders);
        // file_rows only exists for installs that were ≥ v5; older ones just
        // got it CREATED with the current definition (folder_id included) —
        // the v6 external_events lesson, same shape.
        if (from >= 5) {
          await m.addColumn(fileRows, fileRows.folderId);
        }
      }
      // v8 (OPH-175): a task can own TWO alarms — the reminder and, when it is
      // urgent, its deadline. Existing rows take the column default (`remind`),
      // which is right for every one of them: the deadline-only case was
      // written as a reminder row by the old `remind_at ?? due_at` rule, and the
      // server's own backfill re-labels those on the next pull.
      if (from < 8) await m.addColumn(reminders, reminders.kind);
      // v9 (OPH-176): the local alarm log. A brand new device-only table, so
      // nothing existing is touched and there is nothing to backfill — the log
      // starts the moment this version runs.
      if (from < 9) await m.createTable(alarmEvents);
      // v10 (OPH-177): snooze rounds. Existing rows take 0 — an alarm that was
      // already snoozed simply starts counting from its next round, which is
      // honest: we cannot know how many rounds it had before we counted.
      if (from < 10) await m.addColumn(reminders, reminders.snoozeCount);
      // v11 (OPH-178): "sustur". Nullable, so every existing task keeps its
      // alarms — silence has to be asked for.
      if (from < 11) await m.addColumn(tasks, tasks.alarmsMutedAt);
      // v12 (OPH-186): the Completed archive pages over `status` and sorts by
      // `COALESCE(due_at, completed_at)`. Without an index that is a full scan
      // per page, on the one list that only ever grows. Index only — no column,
      // no data change, nothing to backfill.
      if (from < 12) await _createCompletedIndex();
      // v13 (OPH-198, ADR-0018): the quick access rail. A brand new table, so
      // no `from >=` guard is needed — that guard exists for COLUMNS added to
      // a table this same migration may have just created with them included.
      // The next pull fills it; nothing existing is touched.
      if (from < 13) await m.createTable(quickLinks);
      // v14 (OPH-205, ADR-0020): recurring tasks. The table is new, but the two
      // task columns are NOT — hence the `from >= 1` guard, which is the rule
      // this file learned in v6/v7: a column added to a table the same
      // migration may have just created (with the column already in it) must
      // not be added twice. Nothing is backfilled: every existing task simply
      // belongs to no series.
      if (from < 14) {
        await m.createTable(taskSeries);
        if (from >= 1) {
          await m.addColumn(tasks, tasks.seriesId);
          await m.addColumn(tasks, tasks.occurrenceDate);
        }
      }
      // v15 (OPH-221, ADR-0019): the AI bubble's device-local chat history. A
      // brand new table (no `from >=` guard, per the v13 rule); it holds no
      // synced data, so nothing is backfilled.
      if (from < 15) await m.createTable(aiMessages);
      // v16 (OPH-242): the share pipeline's diagnostic trail. Another brand new
      // device-local table — nothing to backfill, and nothing that could ever
      // have been synced.
      if (from < 16) await m.createTable(shareEvents);
      // v17 (OPH-248, ADR-0028 §1): which field is a note's canonical content.
      // A column on an EXISTING table, so it needs the `from >= 1` guard the
      // file learned in v6/v7 — a fresh install creates `notes` with the
      // column already in it, and adding it again would fail.
      if (from < 17 && from >= 1) {
        await m.addColumn(notes, notes.contentFormat);
      }
    },
  );

  /// `IF NOT EXISTS` so the two callers (fresh install, upgrade) can never
  /// collide, and a re-run is a no-op.
  Future<void> _createCompletedIndex() => customStatement(
    'CREATE INDEX IF NOT EXISTS idx_tasks_completed '
    'ON tasks (workspace_id, status, completed_at)',
  );
}

/// One-time v6 backfill (ADR-0013): fold existing rows' searchable text into
/// the shadow columns. Runs inside the migration; the fold cannot run in SQL
/// — that gap is why the columns exist at all.
Future<void> backfillSearchFolds(AwDatabase db) async {
  Future<void> run(String table, Map<String, String> srcToFold) async {
    final cols = srcToFold.keys.join(', ');
    final rows = await db.customSelect('SELECT id, $cols FROM $table').get();
    for (final row in rows) {
      final sets = <String>[];
      final args = <Object?>[];
      srcToFold.forEach((src, fold) {
        final value = row.read<String?>(src);
        sets.add('$fold = ?');
        args.add(value == null ? null : foldSearchText(value));
      });
      args.add(row.read<String>('id'));
      await db.customStatement(
        'UPDATE $table SET ${sets.join(', ')} WHERE id = ?',
        args,
      );
    }
  }

  await run('projects', {
    'name': 'name_fold',
    'description': 'description_fold',
  });
  await run('tags', {'name': 'name_fold'});
  await run('tasks', {
    'title': 'title_fold',
    'description': 'description_fold',
  });
  await run('notes', {'title': 'title_fold', 'plain_text': 'body_fold'});
  await run('external_events', {
    'summary': 'summary_fold',
    'location': 'location_fold',
  });
}
