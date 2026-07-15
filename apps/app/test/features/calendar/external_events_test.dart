import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/calendar/data/external_event.dart';
import 'package:alliswell/src/features/home/task_grouping.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/sync_api.dart' show SyncChange;
import 'package:alliswell/src/sync/sync_applier.dart';

/// OPH-083 — the user's own calendar, in the replica (ADR-0008). Found by
/// using the app: connecting Google did nothing visible, because tasks alone
/// cannot answer "what does my day look like".
ExternalEvent event({
  String id = 'E1',
  String? summary = 'Ekip toplantısı',
  required DateTime startsAt,
  required DateTime endsAt,
  bool isAllDay = false,
  bool isBusy = true,
}) => ExternalEvent(
  id: id,
  summary: summary,
  startsAt: startsAt,
  endsAt: endsAt,
  isAllDay: isAllDay,
  isBusy: isBusy,
);

void main() {
  group('day maths (OPH-083)', () {
    test('an all-day event marks ONE day, not two', () {
      // Google's end is EXCLUSIVE: the 5th runs 05-00:00 → 06-00:00. Marking
      // the 6th too would put a phantom dot on the calendar.
      final oneDay = event(
        startsAt: DateTime(2030, 6, 5),
        endsAt: DateTime(2030, 6, 6),
        isAllDay: true,
      );
      expect(daysOfEvent(oneDay), [DateTime(2030, 6, 5)]);
    });

    test('a multi-day event marks every day it touches', () {
      final trip = event(
        startsAt: DateTime(2030, 6, 5),
        endsAt: DateTime(2030, 6, 8),
        isAllDay: true,
      );
      expect(daysOfEvent(trip), [
        DateTime(2030, 6, 5),
        DateTime(2030, 6, 6),
        DateTime(2030, 6, 7),
      ]);
    });

    test('a meeting that runs past midnight marks both days', () {
      final late = event(
        startsAt: DateTime(2030, 6, 5, 23),
        endsAt: DateTime(2030, 6, 6, 1),
      );
      expect(daysOfEvent(late), [DateTime(2030, 6, 5), DateTime(2030, 6, 6)]);
    });

    test('a day with a meeting is not an empty day', () {
      final events = [
        event(
          startsAt: DateTime(2030, 6, 5, 9),
          endsAt: DateTime(2030, 6, 5, 10),
        ),
        event(
          id: 'E2',
          startsAt: DateTime(2030, 6, 9, 9),
          endsAt: DateTime(2030, 6, 9, 10),
        ),
      ];
      expect(daysWithEvents(events), {
        DateTime(2030, 6, 5),
        DateTime(2030, 6, 9),
      });
    });

    test('a day lists all-day events first, then by start time', () {
      final events = [
        event(
          id: 'late',
          startsAt: DateTime(2030, 6, 5, 15),
          endsAt: DateTime(2030, 6, 5, 16),
        ),
        event(
          id: 'allday',
          startsAt: DateTime(2030, 6, 5),
          endsAt: DateTime(2030, 6, 6),
          isAllDay: true,
        ),
        event(
          id: 'early',
          startsAt: DateTime(2030, 6, 5, 9),
          endsAt: DateTime(2030, 6, 5, 10),
        ),
        event(
          id: 'other',
          startsAt: DateTime(2030, 6, 7, 9),
          endsAt: DateTime(2030, 6, 7, 10),
        ),
      ];
      expect(eventsOn(events, DateTime(2030, 6, 5)).map((e) => e.id), [
        'allday',
        'early',
        'late',
      ]);
    });

    test('an untitled event still has something to render', () {
      // Google allows them; "(Untitled)" beats a blank row or a crash.
      final blank = event(
        summary: null,
        startsAt: DateTime(2030, 6, 5, 9),
        endsAt: DateTime(2030, 6, 5, 10),
      );
      expect(blank.title, '(Untitled)');
    });
  });

  group('replica (OPH-083)', () {
    late AwDatabase db;

    setUp(() => db = AwDatabase(DatabaseConnection(NativeDatabase.memory())));
    tearDown(() => db.close());

    SyncChange change(
      String op,
      Map<String, dynamic>? data, {
      int revision = 1,
    }) => SyncChange(
      entityType: 'external_event',
      entityId: 'EV1'.padRight(26, '0'),
      operation: op,
      revision: revision,
      data: data,
    );

    test('a pulled event round-trips into the replica', () async {
      await applyPulledChanges(
        db,
        workspaceId: 'W1'.padRight(26, '0'),
        toRevision: 1,
        changes: [
          change('create', {
            'id': 'EV1'.padRight(26, '0'),
            'workspaceId': 'W1'.padRight(26, '0'),
            'summary': 'Diş randevusu',
            'location': 'Kadıköy',
            'startsAt': '2030-06-05T09:00:00.000Z',
            'endsAt': '2030-06-05T10:00:00.000Z',
            'isAllDay': false,
            'isBusy': true,
            'revision': 1,
          }),
        ],
      );

      final stored = await ExternalEventStore(
        db,
      ).watchAll('W1'.padRight(26, '0')).first;
      expect(stored, hasLength(1));
      expect(stored.single.summary, 'Diş randevusu');
      expect(stored.single.location, 'Kadıköy');
      expect(stored.single.startsAt, DateTime.utc(2030, 6, 5, 9));
      expect(stored.single.isBusy, isTrue);
    });

    test('a meeting deleted in Google disappears from the replica', () async {
      await applyPulledChanges(
        db,
        workspaceId: 'W1'.padRight(26, '0'),
        toRevision: 1,
        changes: [
          change('create', {
            'id': 'EV1'.padRight(26, '0'),
            'workspaceId': 'W1'.padRight(26, '0'),
            'summary': 'İptal olacak',
            'startsAt': '2030-06-05T09:00:00.000Z',
            'endsAt': '2030-06-05T10:00:00.000Z',
            'revision': 1,
          }),
        ],
      );
      await applyPulledChanges(
        db,
        workspaceId: 'W1'.padRight(26, '0'),
        toRevision: 2,
        changes: [change('delete', null, revision: 2)],
      );

      expect(
        await ExternalEventStore(db).watchAll('W1'.padRight(26, '0')).first,
        isEmpty,
      );
    });

    test('events of another workspace stay out', () async {
      await applyPulledChanges(
        db,
        workspaceId: 'W2'.padRight(26, '0'),
        toRevision: 1,
        changes: [
          change('create', {
            'id': 'EV1'.padRight(26, '0'),
            'workspaceId': 'W2'.padRight(26, '0'),
            'summary': 'Başka alan',
            'startsAt': '2030-06-05T09:00:00.000Z',
            'endsAt': '2030-06-05T10:00:00.000Z',
            'revision': 1,
          }),
        ],
      );

      expect(
        await ExternalEventStore(db).watchAll('W1'.padRight(26, '0')).first,
        isEmpty,
      );
    });
  });
}
