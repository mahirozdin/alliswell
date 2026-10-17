import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/tasks/data/capture_inbox.dart';

/// OPH-376 — the Siri/Shortcuts mailbox decoder and its channel.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('capturesFromMailbox', () {
    test('anything but a list is an empty mailbox', () {
      expect(capturesFromMailbox(null), isEmpty);
      expect(capturesFromMailbox('add'), isEmpty);
      expect(capturesFromMailbox({'kind': 'add', 'text': 'x'}), isEmpty);
    });

    test('a malformed entry is skipped and the rest survive', () {
      final out = capturesFromMailbox([
        'nonsense',
        42,
        {'id': 'a', 'kind': 'add', 'text': 'süt al'},
        {'id': 'b', 'kind': 'add', 'text': 7},
      ]);
      expect(out, [
        const AwCapture(id: 'a', kind: AwCaptureKind.add, text: 'süt al'),
      ]);
    });

    test('an unknown kind is dropped — the sender may be newer', () {
      expect(
        capturesFromMailbox([
          {'id': 'a', 'kind': 'complete', 'text': 'x'},
          {'id': 'b', 'kind': 'today'},
        ]),
        [const AwCapture(id: 'b', kind: AwCaptureKind.today)],
      );
    });

    test('an add without words is nothing to add', () {
      expect(
        capturesFromMailbox([
          {'id': 'a', 'kind': 'add', 'text': ''},
          {'id': 'b', 'kind': 'add', 'text': '   \n '},
          {'id': 'c', 'kind': 'add'},
        ]),
        isEmpty,
      );
    });

    test('text is trimmed and capped at the API title limit', () {
      final out = capturesFromMailbox([
        {'id': 'a', 'kind': 'add', 'text': '  kira  '},
        {'id': 'b', 'kind': 'add', 'text': 'x' * 900},
      ]);
      expect(out[0].text, 'kira');
      expect(out[1].text, hasLength(kAwCaptureTextMax));
    });

    test('today needs no text', () {
      expect(
        capturesFromMailbox([
          {'id': 't', 'kind': 'today', 'at': '2026-10-17T10:00:00Z'},
        ]).single.kind,
        AwCaptureKind.today,
      );
    });

    test('at most 32 entries are accepted', () {
      final raw = [
        for (var i = 0; i < 40; i++) {'id': '$i', 'kind': 'today'},
      ];
      expect(capturesFromMailbox(raw), hasLength(kAwCaptureMax));
    });
  });

  group('MethodChannelCaptureInbox', () {
    const channel = MethodChannel(MethodChannelCaptureInbox.channelName);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('take decodes what the native side hands over', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'take');
        return [
          {'id': 'a', 'kind': 'add', 'text': "yarın 9'da kira"},
          {'id': 'b', 'kind': 'today'},
        ];
      });
      final inbox = MethodChannelCaptureInbox();
      addTearDown(inbox.dispose);
      final out = await inbox.take();
      expect(out.map((c) => c.kind), [AwCaptureKind.add, AwCaptureKind.today]);
      expect(out.first.text, "yarın 9'da kira");
    });

    test('a missing plugin or a platform error is an empty mailbox', () async {
      final inbox = MethodChannelCaptureInbox();
      addTearDown(inbox.dispose);
      expect(await inbox.take(), isEmpty); // no handler: MissingPlugin
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'boom');
      });
      expect(await inbox.take(), isEmpty);
    });

    test('a native "changed" call wakes the drain', () async {
      final inbox = MethodChannelCaptureInbox();
      addTearDown(inbox.dispose);
      var fired = 0;
      final sub = inbox.changes.listen((_) => fired++);
      addTearDown(sub.cancel);
      await messenger.handlePlatformMessage(
        MethodChannelCaptureInbox.channelName,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('changed'),
        ),
        (_) {},
      );
      await Future<void>.delayed(Duration.zero);
      expect(fired, 1);
    });
  });
}
