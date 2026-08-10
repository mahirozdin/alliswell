import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/core/deep_link.dart';
import 'package:alliswell/src/features/tasks/data/task_store.dart';
import 'package:alliswell/src/features/widgets/widget_callback.dart';
import 'package:alliswell/src/features/widgets/widget_snapshot.dart';
import 'package:alliswell/src/features/tasks/data/task.dart';
import 'package:alliswell/src/sync/db/database.dart';

/// OPH-189 (`alliswell://` routing, ADR-0016), OPH-188 (the widget's background
/// write) and OPH-187 (today's open count).
///
/// The routing table is a pure function on purpose: a redirect nobody can unit
/// test is how "No route for alliswell://open/" survived a release.
Task _task({
  required String title,
  DateTime? due,
  bool done = false,
  bool snoozed = false,
}) => Task(
  id: title.padRight(26, '0'),
  workspaceId: 'W1',
  title: title,
  status: done ? 'completed' : 'open',
  priority: 'none',
  timezone: 'Europe/Istanbul',
  isUrgent: false,
  requiresAcknowledgement: false,
  sortOrder: 0,
  revision: 1,
  dueAt: due,
  snoozedUntil: snoozed ? DateTime.now().add(const Duration(hours: 1)) : null,
);

void main() {
  group('awRouteForUri', () {
    const id = '01JABCDEFGHJKMNPQRSTVWXYZ0';

    test('routes the three URLs the app actually produces', () {
      expect(awRouteForUri(Uri.parse('alliswell://open')), '/home');
      expect(awRouteForUri(Uri.parse('alliswell://task/$id')), '/tasks/$id');
      expect(awRouteForUri(Uri.parse('alliswell://file/$id')), '/files');
    });

    test('refuses ids that are not ULIDs', () {
      // A URL is untrusted input — it can arrive from a synced calendar event
      // written by somebody else's client (ADR-0016).
      for (final bad in ['abc', '../../etc', '01JABC', 'I' * 26, '']) {
        expect(
          awRouteForUri(Uri.parse('alliswell://task/$bad')),
          isNull,
          reason: '"$bad" must not become a route',
        );
      }
    });

    test('unknown verbs and foreign schemes resolve to nothing', () {
      expect(awRouteForUri(Uri.parse('alliswell://wat')), isNull);
      expect(awRouteForUri(Uri.parse('alliswell://open/extra')), isNull);
      expect(
        awRouteForUri(Uri.parse('https://alliswell.space/tasks/$id')),
        isNull,
      );
      expect(awRouteForUri(Uri.parse('alliswell://')), isNull);
    });

    test('the write verbs are NOT routable — they are background actions', () {
      // ADR-0016's security line: a tapped link may navigate, never mutate.
      final complete = Uri.parse('alliswell://complete?id=$id');
      expect(awRouteForUri(complete), isNull);
      expect(awIsBackgroundAction(complete), isTrue);
      expect(awIsBackgroundAction(Uri.parse('alliswell://task/$id')), isFalse);
    });
  });

  group('handleWidgetAction (OPH-188)', () {
    late AwDatabase db;

    setUp(() => db = AwDatabase(DatabaseConnection(NativeDatabase.memory())));
    // The handler closes only the db IT opened — an injected handle belongs to
    // its owner, so the test still owns this one.
    tearDown(() => db.close());

    test(
      'completing from the widget writes the replica AND the outbox',
      () async {
        final store = TaskStore(db, () {});
        final id = await store.create('W1', {'title': 'Widget’tan bitir'});

        final ok = await handleWidgetAction(
          Uri.parse('alliswell://complete?id=$id'),
          openDatabase: () => db,
        );
        expect(ok, isTrue);

        final row = await (db.select(
          db.tasks,
        )..where((t) => t.id.equals(id))).getSingle();
        expect(row.status, 'completed');
        // The outbox row is the whole point: the widget has no write path of its
        // own, so an offline completion still reaches the server later.
        final queued = await db.select(db.pendingMutations).get();
        expect(queued.where((m) => m.entityId == id), isNotEmpty);
      },
    );

    test('ignores anything that is not our background action', () async {
      for (final uri in [
        null,
        Uri.parse('alliswell://task/01JABCDEFGHJKMNPQRSTVWXYZ0'),
        Uri.parse('https://example.com/complete?id=x'),
        Uri.parse('alliswell://complete'),
      ]) {
        expect(
          await handleWidgetAction(uri, openDatabase: () => db),
          isFalse,
          reason: '$uri must not write anything',
        );
      }
    });
  });

  group('openToday (OPH-187)', () {
    final now = DateTime(2026, 7, 29, 12);

    test('counts overdue + today, and nothing else', () {
      final snapshot = buildWidgetSnapshot([
        _task(title: 'Geciken', due: DateTime(2026, 7, 27, 9)),
        _task(title: 'Bugun', due: DateTime(2026, 7, 29, 17)),
        _task(title: 'Yarin', due: DateTime(2026, 7, 30, 9)),
        _task(title: 'Tarihsiz'),
      ], now: now);

      // The user's own words: "gecikenler dahil, o gün için aktif kaç task".
      // Dateless work belongs to every day, so counting it would inflate every
      // day — the decision is written down in DESIGN §8 W9.
      expect(snapshot.openToday, 2);
      expect(snapshot.toJson()['openToday'], 2);
    });

    test('snoozed work still counts — it is still open', () {
      final snapshot = buildWidgetSnapshot([
        _task(
          title: 'Ertelenmis',
          due: DateTime(2026, 7, 29, 9),
          snoozed: true,
        ),
      ], now: now);
      expect(snapshot.openToday, 1);
    });

    test('completed work does not count, and zero hides the badge', () {
      final snapshot = buildWidgetSnapshot([
        _task(title: 'Bitti', due: DateTime(2026, 7, 29, 9), done: true),
      ], now: now);
      expect(snapshot.openToday, 0);
      // Absent rather than "0": a badge reading zero is noise, and the native
      // side reads a missing field as "hide".
      expect(snapshot.toJson().containsKey('openToday'), isFalse);
    });

    test('the snapshot declares v3 and carries the localized phrase', () {
      final snapshot = buildWidgetSnapshot([
        _task(title: 'Bugun', due: DateTime(2026, 7, 29, 17)),
      ], now: now);
      // Pinned as a LITERAL on purpose: bumping the schema has to break a test,
      // because a new field means an older widget is about to read a snapshot
      // it does not fully understand (v3 = OPH-253's `clockFormat`).
      expect(snapshot.toJson()['v'], 3);
      // Native code carries no translations (W-rule) — the wording ships here.
      expect(snapshot.strings['openToday'], contains('1'));
    });
  });
}
