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
}
