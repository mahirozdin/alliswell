import 'package:drift/drift.dart';

import '../../../sync/db/database.dart';

/// One event from the user's own calendar (OPH-083, ADR-0008).
///
/// Deliberately NOT a Task and deliberately not editable: AllisWell did not
/// create these and must never write them back. They exist so Home and the
/// Calendar tab can answer "what does my day look like" — a question tasks
/// alone cannot answer.
class ExternalEvent {
  const ExternalEvent({
    required this.id,
    required this.startsAt,
    required this.endsAt,
    required this.isAllDay,
    required this.isBusy,
    this.summary,
    this.location,
    this.htmlLink,
  });

  final String id;

  /// Google allows untitled events; the UI says "(Untitled)" rather than lie.
  final String? summary;
  final String? location;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool isAllDay;

  /// `false` = on the calendar but marked free (Google's `transparent`).
  final bool isBusy;
  final String? htmlLink;

  String get title =>
      (summary == null || summary!.isEmpty) ? '(Untitled)' : summary!;
}

/// Local-first reads over the replica — the server is the only writer, so this
/// store has no write path at all (that absence IS the read-only guarantee).
class ExternalEventStore {
  ExternalEventStore(this._db);

  final AwDatabase _db;

  /// Everything in the workspace, soonest first. The calendar window is
  /// already applied server-side (ADR-0008 §4), so this is a bounded set.
  Stream<List<ExternalEvent>> watchAll(String workspaceId) =>
      (_db.select(_db.externalEvents)
            ..where((e) => e.workspaceId.equals(workspaceId))
            ..orderBy([(e) => OrderingTerm.asc(e.startsAt)]))
          .watch()
          .map((rows) => rows.map(_event).toList());

  static ExternalEvent _event(ExternalEventRecord r) => ExternalEvent(
    id: r.id,
    summary: r.summary,
    location: r.location,
    startsAt: r.startsAt,
    endsAt: r.endsAt,
    isAllDay: r.isAllDay,
    isBusy: r.isBusy,
    htmlLink: r.htmlLink,
  );
}
