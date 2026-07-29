import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/calendar/apple/apple_calendar_gateway.dart';
import 'package:alliswell/src/features/calendar/apple/apple_mirror.dart';
import 'package:alliswell/src/features/calendar/apple/apple_mirror_engine.dart';
import 'package:alliswell/src/features/tasks/data/task.dart';
import 'package:alliswell/src/sync/db/database.dart';

Task _task(
  String id, {
  String title = 'İş',
  String status = 'open',
  bool mirror = true,
  bool urgent = false,
  DateTime? scheduledStart,
  DateTime? scheduledEnd,
  DateTime? due,
  DateTime? remind,
  DateTime? created,
}) => Task(
  id: id,
  workspaceId: 'W1',
  title: title,
  status: status,
  priority: 'none',
  timezone: 'Europe/Istanbul',
  isUrgent: urgent,
  requiresAcknowledgement: false,
  sortOrder: 0,
  revision: 1,
  calendarMirrorEnabled: mirror,
  scheduledStartAt: scheduledStart,
  scheduledEndAt: scheduledEnd,
  dueAt: due,
  remindAt: remind,
  createdAt: created,
);

/// Records what the engine asked EventKit to do, and hands back canned ids —
/// so the whole mirror is testable without a device.
class FakeAppleGateway implements AppleCalendarGateway {
  FakeAppleGateway({this.supported = true});

  final bool supported;

  final List<AppleEventSpec> saved = [];
  final List<String> deleted = [];
  String? preexistingByUrl; // what findEventByUrl returns (re-link path)
  int _seq = 0;

  @override
  bool get isSupported => supported;

  @override
  Future<EventKitAccess> status() async => EventKitAccess.fullAccess;

  @override
  Future<EventKitAccess> requestAccess() async => EventKitAccess.fullAccess;

  @override
  Future<List<AppleCalendar>> calendars() async => const [];

  @override
  Future<String> saveEvent(AppleEventSpec spec) async {
    saved.add(spec);
    return spec.eventId ?? 'ev-${++_seq}';
  }

  @override
  Future<void> deleteEvent(String eventId) async => deleted.add(eventId);

  @override
  Future<String?> findEventByUrl({
    required String calendarId,
    required String url,
    required DateTime from,
    required DateTime to,
  }) async => preexistingByUrl;
}

void main() {
  // ── Pure derivation (§7.1, server parity) ─────────────────────────────────

  group('desiredAppleEvent (OPH-078, §7.1)', () {
    test('scheduled block verbatim, [Task] title, task url', () {
      final e = desiredAppleEvent(
        _task(
          'T1',
          title: 'Sunum',
          scheduledStart: DateTime.utc(2030, 6, 1, 9),
          scheduledEnd: DateTime.utc(2030, 6, 1, 10, 30),
        ),
      );
      expect(e!.title, '[Task] Sunum');
      expect(e.url, 'alliswell://task/T1');
      expect(e.start, DateTime.utc(2030, 6, 1, 9));
      expect(e.end, DateTime.utc(2030, 6, 1, 10, 30));
    });

    test('a dated task gets a 30-minute block, and midnight is a wall', () {
      // Round 12 (ADR-0021 §1): no opt-in and no urgent-only rule — a time is
      // enough. Local, because the device's clock IS the user's wall clock.
      final due = desiredAppleEvent(_task('T', due: DateTime(2030, 6, 1, 12)))!;
      expect(due.start, DateTime(2030, 6, 1, 12));
      expect(due.end, DateTime(2030, 6, 1, 12, 30));

      final lateNight = desiredAppleEvent(
        _task('T', due: DateTime(2030, 6, 1, 23, 59)),
      )!;
      expect(lateNight.start, DateTime(2030, 6, 1, 23, 29));
      expect(lateNight.end, DateTime(2030, 6, 1, 23, 59));
    });

    test('an undated task sits on the day it was created', () {
      final e = desiredAppleEvent(
        _task('T', created: DateTime(2030, 5, 20, 9, 15)),
      )!;
      expect(e.start, DateTime(2030, 5, 20, 9, 15));
      expect(e.end, DateTime(2030, 5, 20, 9, 45));
    });

    test('a completed task keeps its block, marked (ADR-0021 §2)', () {
      final e = desiredAppleEvent(
        _task('T', status: 'completed', due: DateTime(2030, 6, 1, 12)),
      )!;
      expect(e.title, '✓ [Task] İş');
      expect(e.start, DateTime(2030, 6, 1, 12));
    });

    test('a backwards scheduled end falls back to the default slot', () {
      final e = desiredAppleEvent(
        _task(
          'T',
          scheduledStart: DateTime.utc(2030, 6, 1, 14),
          scheduledEnd: DateTime.utc(2030, 6, 1, 10),
        ),
      )!;
      expect(e.end, DateTime.utc(2030, 6, 1, 14, 30));
    });

    test('no event for withdrawn work, or a task with no time at all', () {
      expect(desiredAppleEvent(_task('T')), isNull); // no date, no created_at
      // `completed` left this list in round 12 — done work keeps its block.
      for (final s in ['cancelled', 'archived']) {
        expect(
          desiredAppleEvent(
            _task('T', status: s, due: DateTime.utc(2030, 6, 1, 12)),
          ),
          isNull,
        );
      }
    });

    test('matches the server block rule, case by case (ADR-0021)', () {
      // The same fixture apps/api/test/unit/google-mirror.test.js asserts: two
      // mirrors that disagree in front of the user is what §17 D1 forbids.
      final fixture =
          jsonDecode(
                File(
                  'test/fixtures/calendar_block_parity.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      String wall(DateTime d) =>
          '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}T'
          '${d.hour.toString().padLeft(2, '0')}:'
          '${d.minute.toString().padLeft(2, '0')}';
      for (final raw in (fixture['cases'] as List)) {
        final testCase = raw as Map<String, dynamic>;
        final block = appleBlockFor(DateTime.parse(testCase['at'] as String));
        expect(
          wall(block.$1),
          testCase['start'],
          reason: testCase['name'] as String,
        );
        expect(
          wall(block.$2),
          testCase['end'],
          reason: testCase['name'] as String,
        );
      }
    });
  });

  // ── Pure decision matrix ──────────────────────────────────────────────────

  group('decideAppleMirror', () {
    final desired = desiredAppleEvent(
      _task('T', due: DateTime.utc(2030, 6, 1, 12)),
    )!;
    AppleEventLink link({String cal = 'cal-1', String? sig}) => AppleEventLink(
      taskId: 'T',
      calendarId: cal,
      eventId: 'ev-1',
      signature: sig ?? desired.signature,
    );

    test('create when wanted and unmapped', () {
      expect(
        decideAppleMirror(
          desired: desired,
          link: null,
          targetCalendarId: 'cal-1',
        ),
        AppleMirrorDecision.create,
      );
    });

    test('noop when mapped and content identical', () {
      expect(
        decideAppleMirror(
          desired: desired,
          link: link(),
          targetCalendarId: 'cal-1',
        ),
        AppleMirrorDecision.noop,
      );
    });

    test('update when content changed', () {
      expect(
        decideAppleMirror(
          desired: desired,
          link: link(sig: 'stale'),
          targetCalendarId: 'cal-1',
        ),
        AppleMirrorDecision.update,
      );
    });

    test('remove when no longer wanted', () {
      expect(
        decideAppleMirror(
          desired: null,
          link: link(),
          targetCalendarId: 'cal-1',
        ),
        AppleMirrorDecision.remove,
      );
    });

    test(
      're-point to a different calendar removes (then engine recreates)',
      () {
        expect(
          decideAppleMirror(
            desired: desired,
            link: link(cal: 'cal-OLD'),
            targetCalendarId: 'cal-1',
          ),
          AppleMirrorDecision.remove,
        );
      },
    );

    test('no calendar chosen: never create, never delete a real event', () {
      expect(
        decideAppleMirror(desired: desired, link: null, targetCalendarId: null),
        AppleMirrorDecision.none,
      );
      expect(
        decideAppleMirror(
          desired: desired,
          link: link(),
          targetCalendarId: null,
        ),
        AppleMirrorDecision.noop,
      );
    });
  });

  // ── Engine against a fake gateway + real in-memory replica ────────────────

  group('AppleMirrorEngine (OPH-078)', () {
    late AwDatabase db;
    late AppleEventLinkStore links;
    late FakeAppleGateway gateway;

    setUp(() {
      db = AwDatabase(DatabaseConnection(NativeDatabase.memory()));
      links = AppleEventLinkStore(db);
      gateway = FakeAppleGateway();
    });
    tearDown(() => db.close());

    AppleMirrorEngine engine({String? calendar = 'cal-1'}) =>
        AppleMirrorEngine(gateway: gateway, links: links, calendarId: calendar);

    test('creates an event and maps it', () async {
      await engine().reconcileTask(
        _task('T1', due: DateTime.utc(2030, 6, 1, 12)),
      );
      expect(gateway.saved, hasLength(1));
      expect(gateway.saved.single.url, 'alliswell://task/T1');
      final link = await links.get('T1');
      expect(link!.calendarId, 'cal-1');
      expect(link.eventId, 'ev-1');
    });

    test(
      'a second identical reconcile writes nothing (signature guard)',
      () async {
        final task = _task('T1', due: DateTime.utc(2030, 6, 1, 12));
        await engine().reconcileTask(task);
        await engine().reconcileTask(task);
        expect(gateway.saved, hasLength(1)); // not two
      },
    );

    test('a changed time updates the same event', () async {
      await engine().reconcileTask(
        _task('T1', due: DateTime.utc(2030, 6, 1, 12)),
      );
      await engine().reconcileTask(
        _task('T1', due: DateTime.utc(2030, 6, 2, 12)),
      );
      expect(gateway.saved, hasLength(2));
      expect(gateway.saved.last.eventId, 'ev-1'); // update in place
    });

    test('completing a task marks its event; cancelling removes it', () async {
      await engine().reconcileTask(
        _task('T1', due: DateTime.utc(2030, 6, 1, 12)),
      );
      // Round 12 (ADR-0021 §2): done work keeps its block, marked — the event
      // is UPDATED, not deleted, and the mapping survives.
      await engine().reconcileTask(
        _task('T1', status: 'completed', due: DateTime.utc(2030, 6, 1, 12)),
      );
      expect(gateway.deleted, isEmpty);
      expect(await links.get('T1'), isNotNull);

      // Withdrawn work is different.
      await engine().reconcileTask(
        _task('T1', status: 'cancelled', due: DateTime.utc(2030, 6, 1, 12)),
      );
      expect(gateway.deleted, ['ev-1']);
      expect(await links.get('T1'), isNull);
    });

    test(
      're-linking adopts a pre-existing event instead of duplicating',
      () async {
        gateway.preexistingByUrl = 'ev-orphan';
        await engine().reconcileTask(
          _task('T1', due: DateTime.utc(2030, 6, 1, 12)),
        );
        // Saved with the adopted id, not a fresh create.
        expect(gateway.saved.single.eventId, 'ev-orphan');
        expect((await links.get('T1'))!.eventId, 'ev-orphan');
      },
    );

    test('reconcileAll sweeps orphans whose task vanished', () async {
      await engine().reconcileTask(
        _task('T1', due: DateTime.utc(2030, 6, 1, 12)),
      );
      await engine().reconcileTask(
        _task('T2', due: DateTime.utc(2030, 6, 2, 12)),
      );
      // T2 is gone from the world entirely (deleted / no longer pulled).
      await engine().reconcileAll([
        _task('T1', due: DateTime.utc(2030, 6, 1, 12)),
      ]);
      expect(gateway.deleted, contains('ev-2'));
      expect(await links.get('T2'), isNull);
      expect(await links.get('T1'), isNotNull); // survivor untouched
    });

    test('does nothing on a platform without EventKit', () async {
      final off = AppleMirrorEngine(
        gateway: FakeAppleGateway(supported: false),
        links: links,
        calendarId: 'cal-1',
      );
      await off.reconcileAll([_task('T1', due: DateTime.utc(2030, 6, 1, 12))]);
      expect(await links.all(), isEmpty);
    });
  });
}
