import 'dart:math' as math;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/calendar/apple/apple_calendar_gateway.dart';
import 'package:alliswell/src/features/calendar/apple/apple_mirror.dart';
import 'package:alliswell/src/features/calendar/apple/apple_mirror_engine.dart';
import 'package:alliswell/src/features/calendar/apple/apple_read_back.dart';
import 'package:alliswell/src/features/tasks/data/task.dart';
import 'package:alliswell/src/sync/db/database.dart';

/// OPH-369 (ADR-0050) — Apple Calendar read-back: a move, resize or delete the
/// user makes to a mirrored event flows back to the task, with the semantics
/// of the server's Google inbound path (`inbound.js`). Pure decisions first,
/// then the engine against an EventKit fake and a real in-memory replica.

Task _task(
  String id, {
  String title = 'İş',
  String status = 'open',
  DateTime? scheduledStart,
  DateTime? scheduledEnd,
  DateTime? due,
  DateTime? created,
  DateTime? updated,
}) => Task(
  id: id,
  workspaceId: 'W1',
  title: title,
  status: status,
  priority: 'none',
  timezone: 'Europe/Istanbul',
  isUrgent: false,
  requiresAcknowledgement: false,
  sortOrder: 0,
  revision: 1,
  scheduledStartAt: scheduledStart,
  scheduledEndAt: scheduledEnd,
  dueAt: due,
  createdAt: created,
  updatedAt: updated,
);

AppleEventSnapshot _event({
  String id = 'ev-1',
  required DateTime start,
  required DateTime end,
  bool allDay = false,
  bool recurrence = false,
  DateTime? modified,
}) => AppleEventSnapshot(
  id: id,
  calendarId: 'cal-1',
  url: 'alliswell://task/T',
  start: start,
  end: end,
  isAllDay: allDay,
  hasRecurrence: recurrence,
  lastModified: modified,
);

/// EventKit as the engine sees it: events by id, calendars, and the way the
/// real store behaves — whole seconds only, a stale id on save CREATES a new
/// event, deleting a missing event succeeds.
class EventKitFake implements AppleCalendarGateway {
  bool supported = true;
  bool canRead = true;
  List<String> calendarIds = ['cal-1'];
  DateTime clock = DateTime.utc(2030, 1, 1);

  final Map<String, AppleEventSnapshot> events = {};
  final List<AppleEventSpec> saved = [];
  final List<String> deleted = [];
  int _seq = 0;
  int _active = 0;
  int maxActive = 0;

  @override
  bool get isSupported => supported;

  @override
  Future<EventKitAccess> status() async => EventKitAccess.fullAccess;

  @override
  Future<EventKitAccess> requestAccess() async => EventKitAccess.fullAccess;

  @override
  Future<List<AppleCalendar>> calendars() async => [
    for (final id in calendarIds)
      AppleCalendar(id: id, title: id, isWritable: true, isDefault: false),
  ];

  static DateTime _seconds(DateTime d) => DateTime.fromMillisecondsSinceEpoch(
    d.toUtc().millisecondsSinceEpoch ~/ 1000 * 1000,
    isUtc: true,
  );

  @override
  Future<String> saveEvent(AppleEventSpec spec) async {
    _active++;
    maxActive = math.max(maxActive, _active);
    await Future<void>.delayed(Duration.zero);
    _active--;
    final existing = spec.eventId == null ? null : events[spec.eventId];
    final id = existing?.id ?? 'ev-${++_seq}';
    events[id] = AppleEventSnapshot(
      id: id,
      calendarId: existing?.calendarId ?? spec.calendarId,
      url: spec.url,
      start: _seconds(spec.start),
      end: _seconds(spec.end),
      isAllDay: spec.isAllDay,
      lastModified: clock,
    );
    saved.add(spec);
    return id;
  }

  @override
  Future<void> deleteEvent(String eventId) async {
    deleted.add(eventId);
    events.remove(eventId);
  }

  @override
  Future<String?> findEventByUrl({
    required String calendarId,
    required String url,
    required DateTime from,
    required DateTime to,
  }) async {
    for (final e in events.values) {
      if (e.calendarId == calendarId &&
          e.url == url &&
          e.start.isBefore(to) &&
          e.end.isAfter(from)) {
        return e.id;
      }
    }
    return null;
  }

  @override
  Future<List<AppleEventSnapshot>?> readEvents(List<String> ids) async {
    if (!canRead) return null;
    return [
      for (final id in ids)
        if (events[id] != null) events[id]!,
    ];
  }

  /// The user, in Calendar: move/resize/convert an event.
  void userEdits(
    String id, {
    required DateTime start,
    required DateTime end,
    bool allDay = false,
    bool recurrence = false,
    DateTime? modified,
  }) {
    final e = events[id]!;
    events[id] = AppleEventSnapshot(
      id: id,
      calendarId: e.calendarId,
      url: e.url,
      start: start.toUtc(),
      end: end.toUtc(),
      isAllDay: allDay,
      hasRecurrence: recurrence,
      lastModified: modified ?? clock.add(const Duration(minutes: 5)),
    );
  }

  /// iCloud re-identifies an event (LESSONS calendar).
  void reidentify(String from, String to) {
    final e = events.remove(from)!;
    events[to] = AppleEventSnapshot(
      id: to,
      calendarId: e.calendarId,
      url: e.url,
      start: e.start,
      end: e.end,
      isAllDay: e.isAllDay,
      lastModified: e.lastModified,
    );
  }
}

void main() {
  // ── Pure: the signature is the echo baseline ──────────────────────────────

  group('parseAppleSignature', () {
    test('reads back exactly what the outbound side wrote', () {
      final desired = desiredAppleEvent(
        _task('T', due: DateTime.utc(2030, 6, 1, 12)),
      )!;
      final parsed = parseAppleSignature(desired.signature)!;
      expect(parsed.title, '[Task] İş');
      expect(parsed.start.isAtSameMomentAs(desired.start), isTrue);
      expect(parsed.end.isAtSameMomentAs(desired.end), isTrue);
    });

    test('a title containing "|" does not confuse it', () {
      final sig = appleSignatureWith(
        '[Task] A | B | C',
        DateTime.utc(2030, 6, 1, 9),
        DateTime.utc(2030, 6, 1, 10),
      );
      final parsed = parseAppleSignature(sig)!;
      expect(parsed.title, '[Task] A | B | C');
      expect(parsed.start, DateTime.utc(2030, 6, 1, 9));
      expect(parsed.end, DateTime.utc(2030, 6, 1, 10));
    });

    test('garbage is no baseline', () {
      expect(parseAppleSignature('stale'), isNull);
      expect(parseAppleSignature('a|b|c'), isNull);
      expect(parseAppleSignature(''), isNull);
    });
  });

  // ── Pure: an event's task-shaped window ───────────────────────────────────

  group('appleEventWindow', () {
    test('a timed event is its own window', () {
      final w = appleEventWindow(
        _event(
          start: DateTime.utc(2030, 6, 1, 9),
          end: DateTime.utc(2030, 6, 1, 10),
        ),
      )!;
      expect(w.$1, DateTime.utc(2030, 6, 1, 9));
      expect(w.$2, DateTime.utc(2030, 6, 1, 10));
    });

    test('all-day ending 23:59:59 → midnight to the next midnight', () {
      final w = appleEventWindow(
        _event(
          start: DateTime(2030, 6, 1),
          end: DateTime(2030, 6, 1, 23, 59, 59),
          allDay: true,
        ),
      )!;
      expect(w.$1, DateTime(2030, 6, 1));
      expect(w.$2, DateTime(2030, 6, 2));
    });

    test('all-day with an exclusive midnight end lands on the same block', () {
      final w = appleEventWindow(
        _event(
          start: DateTime(2030, 6, 1),
          end: DateTime(2030, 6, 2),
          allDay: true,
        ),
      )!;
      expect(w.$1, DateTime(2030, 6, 1));
      expect(w.$2, DateTime(2030, 6, 2));
    });

    test('a multi-day all-day event spans all its days', () {
      final w = appleEventWindow(
        _event(
          start: DateTime(2030, 6, 1),
          end: DateTime(2030, 6, 3, 23, 59, 59),
          allDay: true,
        ),
      )!;
      expect(w.$1, DateTime(2030, 6, 1));
      expect(w.$2, DateTime(2030, 6, 4));
    });

    test('a series or a backwards window is no window', () {
      expect(
        appleEventWindow(
          _event(
            start: DateTime.utc(2030, 6, 1, 9),
            end: DateTime.utc(2030, 6, 1, 10),
            recurrence: true,
          ),
        ),
        isNull,
      );
      expect(
        appleEventWindow(
          _event(
            start: DateTime.utc(2030, 6, 1, 10),
            end: DateTime.utc(2030, 6, 1, 10),
          ),
        ),
        isNull,
      );
    });
  });

  // ── Pure: the decision matrix (inbound.js parity) ─────────────────────────

  group('decideAppleReadBack', () {
    // The task's derived block: 12:00–12:30 (from due).
    final due = DateTime.utc(2030, 6, 1, 12);
    final task = _task('T', due: due, updated: DateTime.utc(2030, 5, 1));
    final desired = desiredAppleEvent(task)!;
    AppleEventLink link({String? sig, DateTime? suppressed}) => AppleEventLink(
      taskId: 'T',
      calendarId: 'cal-1',
      eventId: 'ev-1',
      signature: sig ?? desired.signature,
      suppressedAt: suppressed,
    );
    AppleReadBackOutcome decide({
      Task? t,
      AppleEventLink? l,
      AppleEventSnapshot? event,
      bool calendarPresent = true,
    }) => decideAppleReadBack(
      task: t ?? task,
      link: l ?? link(),
      event: event,
      calendarPresent: calendarPresent,
    );
    final moved = _event(
      start: DateTime.utc(2030, 6, 1, 15),
      end: DateTime.utc(2030, 6, 1, 15, 30),
      modified: DateTime.utc(2030, 5, 2),
    );

    test('a suppressed link is not judged again', () {
      final o = decide(
        l: link(suppressed: DateTime.utc(2030, 5, 3)),
        event: moved,
      );
      expect(o.decision, AppleReadBackDecision.ignore);
      expect(o.reason, 'suppressed');
    });

    test('a task that wants no event is left to the outbound remove', () {
      final o = decide(
        t: _task('T', status: 'cancelled', due: due),
        event: moved,
      );
      expect(o.decision, AppleReadBackDecision.ignore);
      expect(o.reason, 'outbound-removes');
    });

    test('an unreachable calendar is NOT a deletion', () {
      final o = decide(event: null, calendarPresent: false);
      expect(o.decision, AppleReadBackDecision.ignore);
      expect(o.reason, 'calendar-unavailable');
    });

    test('a missing event means the user deleted it → suppress', () {
      final o = decide(event: null);
      expect(o.decision, AppleReadBackDecision.suppress);
      expect(o.reason, 'provider-deleted');
    });

    test('a series is flagged, nothing written', () {
      final o = decide(
        event: _event(start: desired.start, end: desired.end, recurrence: true),
      );
      expect(o.decision, AppleReadBackDecision.flag);
    });

    test('the event still showing what we wrote is an echo', () {
      final o = decide(
        event: _event(start: desired.start.toUtc(), end: desired.end.toUtc()),
      );
      expect(o.decision, AppleReadBackDecision.echo);
    });

    test('second-truncated by iCloud is still an echo', () {
      // We wrote 12:00:00.123; CalDAV keeps whole seconds.
      final precise = _task(
        'T',
        due: DateTime.utc(2030, 6, 1, 12, 0, 0, 123),
        updated: DateTime.utc(2030, 5, 1),
      );
      final o = decide(
        t: precise,
        l: link(sig: desiredAppleEvent(precise)!.signature),
        event: _event(
          start: DateTime.utc(2030, 6, 1, 12),
          end: DateTime.utc(2030, 6, 1, 12, 30),
        ),
      );
      expect(o.decision, AppleReadBackDecision.echo);
    });

    test(
      'our own stale write is an echo even when its lastModified is newer',
      () {
        // The task moved locally to 15:00 and the outbound pass has not run
        // yet; the event still shows OUR 12:00, and iCloud bumped its
        // lastModified on the round-trip. Without the echo baseline this
        // would look like "both changed, provider newer" and undo the edit.
        final edited = _task(
          'T',
          scheduledStart: DateTime.utc(2030, 6, 1, 15),
          scheduledEnd: DateTime.utc(2030, 6, 1, 16),
          updated: DateTime.utc(2030, 5, 1),
        );
        final o = decide(
          t: edited,
          event: _event(
            start: desired.start.toUtc(),
            end: desired.end.toUtc(),
            modified: DateTime.utc(2030, 5, 9),
          ),
        );
        expect(o.decision, AppleReadBackDecision.echo);
      },
    );

    test('the event already showing the task block is a touch', () {
      // Another device applied the same drag; the task carries it already.
      final applied = _task(
        'T',
        due: due,
        scheduledStart: DateTime.utc(2030, 6, 1, 15),
        scheduledEnd: DateTime.utc(2030, 6, 1, 15, 30),
      );
      final o = decide(t: applied, event: moved);
      expect(o.decision, AppleReadBackDecision.touch);
      expect(o.reason, 'provider-matches-task');
    });

    test('a move the task did not make is applied', () {
      final o = decide(event: moved);
      expect(o.decision, AppleReadBackDecision.apply);
      expect(o.reason, 'provider-only');
      expect(o.start, DateTime.utc(2030, 6, 1, 15));
      expect(o.end, DateTime.utc(2030, 6, 1, 15, 30));
    });

    test('a resize carries the new end', () {
      final o = decide(
        event: _event(
          start: desired.start.toUtc(),
          end: DateTime.utc(2030, 6, 1, 14),
        ),
      );
      expect(o.decision, AppleReadBackDecision.apply);
      expect(o.start!.isAtSameMomentAs(desired.start), isTrue);
      expect(o.end, DateTime.utc(2030, 6, 1, 14));
    });

    group('both changed (§6.5 last-write-wins)', () {
      final edited = _task(
        'T',
        scheduledStart: DateTime.utc(2030, 6, 1, 9),
        scheduledEnd: DateTime.utc(2030, 6, 1, 10),
        updated: DateTime.utc(2030, 5, 5),
      );

      test('provider newer → apply', () {
        final o = decide(
          t: edited,
          event: _event(
            start: DateTime.utc(2030, 6, 1, 15),
            end: DateTime.utc(2030, 6, 1, 16),
            modified: DateTime.utc(2030, 5, 6),
          ),
        );
        expect(o.decision, AppleReadBackDecision.apply);
        expect(o.reason, 'both-changed-provider-newer');
      });

      test('task newer → push', () {
        final o = decide(
          t: edited,
          event: _event(
            start: DateTime.utc(2030, 6, 1, 15),
            end: DateTime.utc(2030, 6, 1, 16),
            modified: DateTime.utc(2030, 5, 4),
          ),
        );
        expect(o.decision, AppleReadBackDecision.push);
      });

      test('no lastModified → the task (canonical) wins', () {
        final o = decide(
          t: edited,
          event: _event(
            start: DateTime.utc(2030, 6, 1, 15),
            end: DateTime.utc(2030, 6, 1, 16),
          ),
        );
        expect(o.decision, AppleReadBackDecision.push);
      });
    });

    test('a link with an unreadable signature has no baseline', () {
      final o = decide(
        l: link(sig: 'stale'),
        event: moved,
      );
      expect(o.decision, AppleReadBackDecision.ignore);
      expect(o.reason, 'no-baseline');
    });
  });

  // ── Pure: the outbound side honours a suppression ─────────────────────────

  group('decideAppleMirror with a suppressed link', () {
    final desired = desiredAppleEvent(
      _task('T', due: DateTime.utc(2030, 6, 1, 12)),
    )!;
    final suppressed = AppleEventLink(
      taskId: 'T',
      calendarId: 'cal-1',
      eventId: 'ev-1',
      signature: 'old',
      suppressedAt: DateTime.utc(2030, 5, 1),
    );

    test('the same calendar never resurrects the event', () {
      expect(
        decideAppleMirror(
          desired: desired,
          link: suppressed,
          targetCalendarId: 'cal-1',
        ),
        AppleMirrorDecision.noop,
      );
    });

    test('a different calendar starts over (remove, then create)', () {
      expect(
        decideAppleMirror(
          desired: desired,
          link: suppressed,
          targetCalendarId: 'cal-2',
        ),
        AppleMirrorDecision.remove,
      );
    });

    test('a task that wants nothing drops the dead row', () {
      expect(
        decideAppleMirror(
          desired: null,
          link: suppressed,
          targetCalendarId: 'cal-1',
        ),
        AppleMirrorDecision.remove,
      );
    });
  });

  // ── Engine: EventKit fake + real in-memory replica ────────────────────────

  group('AppleMirrorEngine read-back (OPH-369)', () {
    late AwDatabase db;
    late AppleEventLinkStore links;
    late EventKitFake kit;
    late List<(String, DateTime, DateTime)> writes;
    late List<String?> signatureAtWrite;

    setUp(() {
      db = AwDatabase(DatabaseConnection(NativeDatabase.memory()));
      links = AppleEventLinkStore(db);
      kit = EventKitFake();
      writes = [];
      signatureAtWrite = [];
    });
    tearDown(() => db.close());

    AppleMirrorEngine engine({String? calendar = 'cal-1'}) => AppleMirrorEngine(
      gateway: kit,
      links: links,
      calendarId: calendar,
      now: () => DateTime.utc(2030, 5, 20),
      writeTaskTimes: (id, start, end) async {
        // The link must already hold the adopted times when the task write
        // lands: the replica emit it causes runs the outbound pass.
        signatureAtWrite.add((await links.get(id))?.signature);
        writes.add((id, start, end));
      },
    );

    final noon = DateTime.utc(2030, 6, 1, 12);
    Task t1({DateTime? updated}) =>
        _task('T1', due: noon, updated: updated ?? DateTime.utc(2030, 1, 1));

    test('our own create comes back as an echo — nothing written', () async {
      // Milliseconds on the anchor: iCloud keeps seconds, so this is the
      // round-trip that must NOT read as a drag.
      final precise = _task(
        'T1',
        created: DateTime.utc(2030, 6, 1, 9, 15, 0, 456),
      );
      final e = engine();
      await e.sync([precise]);
      await e.sync([precise], readBack: true);
      expect(writes, isEmpty);
      expect(kit.saved, hasLength(1));
    });

    test(
      'a drag is written to the task, and the same pass does not push the stale block back',
      () async {
        final e = engine();
        await e.sync([t1()]);
        kit.userEdits(
          'ev-1',
          start: DateTime.utc(2030, 6, 1, 15),
          end: DateTime.utc(2030, 6, 1, 16, 30),
        );

        // The list handed in is the one from BEFORE the write — stale.
        await e.sync([t1()], readBack: true);

        expect(writes, hasLength(1));
        expect(writes.single.$1, 'T1');
        expect(writes.single.$2, DateTime.utc(2030, 6, 1, 15));
        expect(writes.single.$3, DateTime.utc(2030, 6, 1, 16, 30));
        expect(
          signatureAtWrite.single,
          appleSignatureWith(
            '[Task] İş',
            DateTime.utc(2030, 6, 1, 15),
            DateTime.utc(2030, 6, 1, 16, 30),
          ),
        );
        expect(kit.saved, hasLength(1)); // only the original create
        expect(kit.events['ev-1']!.start, DateTime.utc(2030, 6, 1, 15));

        // The write's own emit: the patched task reconciles to a no-op.
        await e.sync([
          _task(
            'T1',
            due: noon,
            scheduledStart: DateTime.utc(2030, 6, 1, 15),
            scheduledEnd: DateTime.utc(2030, 6, 1, 16, 30),
          ),
        ]);
        expect(kit.saved, hasLength(1));
      },
    );

    test('an event made all-day stays all-day after the round-trip', () async {
      final e = engine();
      await e.sync([t1()]);
      kit.userEdits(
        'ev-1',
        start: DateTime(2030, 6, 3),
        end: DateTime(2030, 6, 3, 23, 59, 59),
        allDay: true,
      );
      await e.sync([t1()], readBack: true);
      expect(writes.single.$2, DateTime(2030, 6, 3));
      expect(writes.single.$3, DateTime(2030, 6, 4));

      final patched = _task(
        'T1',
        due: noon,
        scheduledStart: DateTime(2030, 6, 3).toUtc(),
        scheduledEnd: DateTime(2030, 6, 4).toUtc(),
      );
      await e.sync([patched]);
      await e.sync([patched], readBack: true);
      expect(kit.saved, hasLength(1)); // never rewritten as a timed block
      expect(kit.events['ev-1']!.isAllDay, isTrue);
      expect(writes, hasLength(1)); // and the next read-back is an echo
    });

    test(
      'a deleted event stops the mirror; the task stays and it never comes back',
      () async {
        final e = engine();
        await e.sync([t1()]);
        kit.events.remove('ev-1');

        await e.sync([t1()], readBack: true);
        final link = await links.get('T1');
        expect(link!.suppressedAt, DateTime.utc(2030, 5, 20));
        expect(writes, isEmpty); // the task is not touched

        // Editing the task does not resurrect the event.
        await e.sync([
          _task('T1', title: 'Yeni ad', due: noon),
        ], readBack: true);
        await e.sync([_task('T1', title: 'Yeni ad', due: noon)]);
        expect(kit.saved, hasLength(1));

        // Choosing a different calendar is a fresh request: recreated there.
        kit.calendarIds = ['cal-1', 'cal-2'];
        await engine(calendar: 'cal-2').sync([t1()], readBack: true);
        expect(kit.saved, hasLength(2));
        expect(kit.saved.last.calendarId, 'cal-2');
        final fresh = await links.get('T1');
        expect(fresh!.calendarId, 'cal-2');
        expect(fresh.suppressedAt, isNull);
      },
    );

    test(
      'a re-identified event is found again by its url, not suppressed',
      () async {
        final e = engine();
        await e.sync([t1()]);
        kit.reidentify('ev-1', 'ev-icloud');

        await e.sync([t1()], readBack: true);
        final link = await links.get('T1');
        expect(link!.eventId, 'ev-icloud');
        expect(link.suppressedAt, isNull);
        expect(kit.saved, hasLength(1)); // no duplicate created
      },
    );

    test(
      'most events vanishing at once suppresses nothing (mass guard)',
      () async {
        final e = engine();
        final tasks = [
          for (var i = 0; i < 6; i++)
            _task('T$i', due: DateTime.utc(2030, 6, 1 + i, 12)),
        ];
        await e.sync(tasks);
        for (var i = 1; i <= 5; i++) {
          kit.events.remove('ev-$i');
        }
        await e.sync(tasks, readBack: true);
        for (final link in await links.all()) {
          expect(link.suppressedAt, isNull, reason: link.taskId);
        }
      },
    );

    test(
      'an unreachable calendar, or none at all, suppresses nothing',
      () async {
        final e = engine();
        await e.sync([t1()]);
        kit.events.remove('ev-1');

        kit.calendarIds = [];
        await e.sync([t1()], readBack: true);
        expect((await links.get('T1'))!.suppressedAt, isNull);

        kit.calendarIds = ['cal-other'];
        await e.sync([t1()], readBack: true);
        expect((await links.get('T1'))!.suppressedAt, isNull);
      },
    );

    test('a build that cannot read back suppresses nothing', () async {
      final e = engine();
      await e.sync([t1()]);
      kit.events.remove('ev-1');
      kit.canRead = false;
      await e.sync([t1()], readBack: true);
      expect((await links.get('T1'))!.suppressedAt, isNull);
    });

    group('the look before an outbound update', () {
      test('a newer drag wins over a pulled change', () async {
        final e = engine();
        await e.sync([t1()]);
        // The user dragged the event on the Mac at 10:05…
        kit.userEdits(
          'ev-1',
          start: DateTime.utc(2030, 6, 1, 15),
          end: DateTime.utc(2030, 6, 1, 16),
          modified: DateTime.utc(2030, 5, 10, 10, 5),
        );
        // …and a pull then brings an older change to the task's time.
        final pulled = _task(
          'T1',
          due: DateTime.utc(2030, 6, 2, 12),
          updated: DateTime.utc(2030, 5, 10, 10),
        );
        await e.sync([pulled]);
        expect(kit.saved, hasLength(1)); // not overwritten
        expect(writes.single.$2, DateTime.utc(2030, 6, 1, 15));
      });

      test('a newer task change is written over the event', () async {
        final e = engine();
        await e.sync([t1()]);
        kit.userEdits(
          'ev-1',
          start: DateTime.utc(2030, 6, 1, 15),
          end: DateTime.utc(2030, 6, 1, 16),
          modified: DateTime.utc(2030, 5, 10, 10),
        );
        final pulled = _task(
          'T1',
          due: DateTime.utc(2030, 6, 2, 12),
          updated: DateTime.utc(2030, 5, 10, 10, 5),
        );
        await e.sync([pulled]);
        expect(writes, isEmpty);
        expect(kit.saved, hasLength(2));
        expect(
          kit.saved.last.start.isAtSameMomentAs(DateTime.utc(2030, 6, 2, 12)),
          isTrue,
        );
      });

      test('a missing event is never rewritten; the full read-back settles it '
          '(deleted → suppressed, not resurrected)', () async {
        final e = engine();
        await e.sync([t1()]);
        kit.events.remove('ev-1');
        // A pull changes the task while the user has just deleted the event
        // (a Mac with Calendar.app in front): saving to the stale id would
        // CREATE the event again.
        await e.sync([_task('T1', due: DateTime.utc(2030, 6, 2, 12))]);
        expect(kit.saved, hasLength(1)); // not recreated
        expect(kit.events, isEmpty);
        expect((await links.get('T1'))!.suppressedAt, isNotNull);
        expect(writes, isEmpty); // and the task is untouched
      });

      test(
        'a re-identified event is updated in place, not duplicated',
        () async {
          final e = engine();
          await e.sync([t1()]);
          kit.reidentify('ev-1', 'ev-icloud');
          await e.sync([_task('T1', due: DateTime.utc(2030, 6, 2, 12))]);
          expect(kit.events.keys, ['ev-icloud']); // one event, no duplicate
          expect(kit.events['ev-icloud']!.start, DateTime.utc(2030, 6, 2, 12));
          final link = await links.get('T1');
          expect(link!.eventId, 'ev-icloud');
          expect(link.suppressedAt, isNull);
        },
      );

      test('a build that cannot read back keeps the one-way update', () async {
        final e = engine();
        await e.sync([t1()]);
        kit.events.remove('ev-1');
        kit.canRead = false;
        await e.sync([_task('T1', due: DateTime.utc(2030, 6, 2, 12))]);
        // The old one-way behaviour: no suppression on a build that cannot read.
        expect((await links.get('T1'))!.suppressedAt, isNull);
      });
    });

    test('a series is left alone on both sides', () async {
      final e = engine();
      await e.sync([t1()]);
      final ev = kit.events['ev-1']!;
      kit.userEdits('ev-1', start: ev.start, end: ev.end, recurrence: true);
      await e.sync([t1()], readBack: true);
      expect(writes, isEmpty);
      expect(kit.saved, hasLength(1));
    });

    test('does nothing on a platform without EventKit', () async {
      kit.supported = false;
      await engine().sync([t1()], readBack: true);
      expect(await links.all(), isEmpty);
      expect(writes, isEmpty);
    });

    test('passes never overlap, and a burst coalesces', () async {
      final e = engine();
      final tasks = [
        for (var i = 0; i < 4; i++)
          _task('T$i', due: DateTime.utc(2030, 6, 1 + i, 12)),
      ];
      await Future.wait([
        e.sync(tasks),
        e.sync(tasks, readBack: true),
        e.sync(tasks),
      ]);
      expect(kit.maxActive, 1);
      expect(kit.saved, hasLength(4)); // one event each, no duplicates
      expect((await links.all()).map((l) => l.eventId).toSet(), hasLength(4));
    });
  });
}
