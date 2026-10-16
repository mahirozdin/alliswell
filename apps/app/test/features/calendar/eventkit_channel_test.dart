import 'package:alliswell_eventkit/alliswell_eventkit.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// OPH-077 — the EventKit channel contract, driven from the Dart side against
/// a stubbed platform. The Swift is device-verified (there is no way to unit
/// test EventKit itself); what IS testable is that we translate Apple's states
/// faithfully — which is the part that decides what the UI says.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('alliswell/eventkit');
  final calls = <MethodCall>[];
  late Object? Function(MethodCall) handler;

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return handler(call);
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  const eventKit = AlliswellEventKit();

  test('every EventKit state survives the trip, including write-only', () {
    // writeOnly is the one that matters: it can CREATE events but not read
    // them back, so treating it as "granted" would break re-linking silently.
    expect(EventKitAccess.parse('writeOnly'), EventKitAccess.writeOnly);
    expect(EventKitAccess.writeOnly.canMirror, isFalse);
    expect(EventKitAccess.fullAccess.canMirror, isTrue);

    // Denied and restricted are dead ends the app cannot argue with — only the
    // user, in Settings.
    expect(EventKitAccess.denied.isFinal, isTrue);
    expect(EventKitAccess.restricted.isFinal, isTrue);
    expect(EventKitAccess.notDetermined.isFinal, isFalse);

    // An unknown name from a future OS must not throw in a screen's build().
    expect(EventKitAccess.parse('somethingNew'), EventKitAccess.notDetermined);
    expect(EventKitAccess.parse(null), EventKitAccess.notDetermined);
  });

  test('requesting access answers with the resulting status', () async {
    handler = (_) => 'fullAccess';
    expect(await eventKit.requestAccess(), EventKitAccess.fullAccess);
    expect(calls.single.method, 'requestFullAccess');

    // The second call prompts nothing — the OS just restates its record, which
    // is why this returns a status rather than "did they say yes".
    handler = (_) => 'denied';
    expect(await eventKit.requestAccess(), EventKitAccess.denied);
  });

  test('calendars map across, colour and account included', () async {
    handler = (_) => [
      {
        'id': 'CAL-1',
        'title': 'Kişisel',
        'isWritable': true,
        'isDefault': true,
        'colorArgb': 0xFF2563EB,
        'accountName': 'iCloud',
      },
      {
        'id': 'CAL-2',
        'title': 'Resmî Tatiller',
        'isWritable': false, // subscribed → mirroring into it always fails
        'isDefault': false,
        'colorArgb': null,
        'accountName': null,
      },
    ];

    final calendars = await eventKit.calendars();

    expect(calendars.map((c) => c.id), ['CAL-1', 'CAL-2']);
    expect(calendars.first.isDefault, isTrue);
    expect(calendars.first.accountName, 'iCloud');
    expect(calendars.last.isWritable, isFalse);
    expect(calendars.last.colorArgb, isNull); // fall back to the theme
  });

  test('an untitled calendar is named, not blank', () async {
    handler = (_) => [
      {'id': 'CAL-3', 'title': null, 'isWritable': true, 'isDefault': false},
    ];
    expect((await eventKit.calendars()).single.title, '(Untitled)');
  });

  test('a platform without EventKit is restricted, not broken', () async {
    // Android/web/Windows/Linux: the channel has no receiver at all. That is
    // not an error to surface — the feature simply does not exist there.
    handler = (_) => throw MissingPluginException();
    expect(await eventKit.status(), EventKitAccess.restricted);
    expect(await eventKit.calendars(), isEmpty);
  });

  test('a real platform failure surfaces instead of being swallowed', () async {
    handler = (_) => throw PlatformException(code: 'EKError', message: 'boom');
    expect(
      () => eventKit.status(),
      throwsA(
        isA<EventKitException>().having((e) => e.message, 'message', 'boom'),
      ),
    );
  });

  // ── Event CRUD (OPH-078) ────────────────────────────────────────────────────

  test('saving an event sends the full spec and returns the id', () async {
    handler = (_) => {'id': 'ev-42'};
    final id = await eventKit.saveEvent(
      AppleEventSpec(
        calendarId: 'cal-1',
        title: '[Task] Sunum',
        url: 'alliswell://task/T1',
        notes: 'AllisWell • alliswell://task/T1',
        start: DateTime.utc(2030, 6, 1, 9),
        end: DateTime.utc(2030, 6, 1, 10),
      ),
    );
    expect(id, 'ev-42');
    final args = calls.single.arguments as Map;
    expect(args['calendarId'], 'cal-1');
    expect(args['title'], '[Task] Sunum');
    expect(args['url'], 'alliswell://task/T1');
    expect(args['startMs'], DateTime.utc(2030, 6, 1, 9).millisecondsSinceEpoch);
    expect(args.containsKey('id'), isFalse); // create → no id sent
  });

  test('updating sends the stored event id', () async {
    handler = (_) => {'id': 'ev-1'};
    await eventKit.saveEvent(
      AppleEventSpec(
        eventId: 'ev-1',
        calendarId: 'cal-1',
        title: '[Task] Sunum v2',
        url: 'alliswell://task/T1',
        start: DateTime.utc(2030, 6, 1, 9),
        end: DateTime.utc(2030, 6, 1, 10),
      ),
    );
    expect((calls.single.arguments as Map)['id'], 'ev-1');
  });

  test('deleting an already-gone event is not an error', () async {
    handler = (_) => true; // native returns true even when nothing was there
    await eventKit.deleteEvent('ev-gone');
    expect(calls.single.method, 'deleteEvent');
    expect((calls.single.arguments as Map)['id'], 'ev-gone');
  });

  test('findEventByUrl returns the match, or null off-platform', () async {
    handler = (_) => 'ev-orphan';
    final found = await eventKit.findEventByUrl(
      calendarId: 'cal-1',
      url: 'alliswell://task/T1',
      from: DateTime.utc(2030, 5, 31),
      to: DateTime.utc(2030, 6, 2),
    );
    expect(found, 'ev-orphan');

    handler = (_) => throw MissingPluginException();
    expect(
      await eventKit.findEventByUrl(
        calendarId: 'cal-1',
        url: 'alliswell://task/T1',
        from: DateTime.utc(2030, 5, 31),
        to: DateTime.utc(2030, 6, 2),
      ),
      isNull,
    );
  });

  // ── Read-back (OPH-369) ─────────────────────────────────────────────────────

  test('readEvents asks for the ids and maps every field', () async {
    handler = (_) => [
      {
        'id': 'ev-1',
        'calendarId': 'cal-1',
        'url': 'alliswell://task/T1',
        'startMs': DateTime.utc(2030, 6, 1, 15).millisecondsSinceEpoch,
        'endMs': DateTime.utc(2030, 6, 1, 16, 30).millisecondsSinceEpoch,
        'isAllDay': false,
        'hasRecurrence': true,
        'lastModifiedMs': DateTime.utc(2030, 5, 10).millisecondsSinceEpoch,
      },
      {
        // An event in a calendar EventKit cannot name, with no modified date.
        'id': 'ev-2',
        'calendarId': null,
        'url': null,
        'startMs': DateTime.utc(2030, 6, 2).millisecondsSinceEpoch,
        'endMs': DateTime.utc(2030, 6, 3).millisecondsSinceEpoch,
        'isAllDay': true,
        'hasRecurrence': false,
        'lastModifiedMs': null,
      },
    ];
    final events = await eventKit.readEvents(['ev-1', 'ev-2', 'ev-gone']);

    expect(calls.single.method, 'readEvents');
    expect((calls.single.arguments as Map)['ids'], ['ev-1', 'ev-2', 'ev-gone']);
    // A missing id is simply absent — deciding what that means is Dart's.
    expect(events!.map((e) => e.id), ['ev-1', 'ev-2']);
    final first = events.first;
    expect(first.calendarId, 'cal-1');
    expect(first.url, 'alliswell://task/T1');
    expect(first.start, DateTime.utc(2030, 6, 1, 15));
    expect(first.end, DateTime.utc(2030, 6, 1, 16, 30));
    expect(first.isAllDay, isFalse);
    expect(first.hasRecurrence, isTrue);
    expect(first.lastModified, DateTime.utc(2030, 5, 10));
    final second = events.last;
    expect(second.calendarId, isNull);
    expect(second.url, isNull);
    expect(second.isAllDay, isTrue);
    expect(second.lastModified, isNull);
  });

  test('readEvents with no ids does not cross the channel', () async {
    handler = (_) => fail('must not be called');
    expect(await eventKit.readEvents(const []), isEmpty);
    expect(calls, isEmpty);
  });

  test('a build that cannot read back says so with null, not []', () async {
    // [] would read as "every event was deleted" and suppress the mirror.
    handler = (_) => throw MissingPluginException();
    expect(await eventKit.readEvents(['ev-1']), isNull);
  });

  test('a real read failure surfaces as EventKitException', () async {
    handler = (_) => throw PlatformException(code: 'EKError', message: 'boom');
    expect(
      () => eventKit.readEvents(['ev-1']),
      throwsA(isA<EventKitException>()),
    );
  });
}
