import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/notes/data/external_docref.dart';
import 'package:alliswell/src/features/notes/data/external_document.dart';

/// OPH-256 — the channel mapping (ADR-0030).
///
/// The native code itself is verified on a device with `shasum`; what is
/// testable here is the layer that turns its maps into the sealed types. That
/// layer is where a wrong answer would be MOST dangerous: a stray string
/// becoming a writable file means offering to overwrite something we cannot
/// write, which is the exact failure W3 exists to prevent.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('alliswell/docref');
  final calls = <MethodCall>[];
  Map<Object?, Object?>? reply;
  var missing = false;

  setUp(() {
    calls.clear();
    reply = null;
    missing = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (missing) throw MissingPluginException();
          return reply;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  const source = DocRefSource(maxBytes: 2048);
  final handle = ExternalDocHandle(
    token: 'tok',
    kind: ExternalHandleKind.appleBookmark,
    displayName: 'a.md',
  );

  ExternalSaver? saverFor(ExternalAccess access) => switch (access) {
    ExternalWritable(:final saver) => saver,
    ExternalReadOnly() => null,
    ExternalUnreachable() => null,
  };

  group('a platform with no plugin is unavailable, not writable', () {
    test('a missing plugin never yields a saver', () async {
      missing = true;
      final access = await source.probe(handle);
      expect(access, isA<ExternalUnreachable>());
      expect(
        (access as ExternalUnreachable).reason,
        LostAccessReason.unsupportedPlatform,
      );
      expect(saverFor(access), isNull);
      expect(
        await source.pickExternal(),
        isA<ExternalRefused>().having(
          (r) => r.reason,
          'reason',
          ExternalOpenRefusal.unsupported,
        ),
      );
    });
  });

  group('an unrecognised answer falls to the safe side', () {
    test('an unknown probe state is unreachable, never writable', () async {
      // A native build that grows a new state must not be able to hand back
      // something the mapping optimistically treats as permission to write.
      reply = {'state': 'somethingNew', 'reason': 'whatever'};
      final access = await source.probe(handle);
      expect(access, isA<ExternalUnreachable>());
      expect(saverFor(access), isNull);
    });

    test('an unknown save outcome is a failure, never a success', () async {
      reply = {'state': 'writable', 'reason': ''};
      final saver = saverFor(await source.probe(handle))!;
      reply = {'outcome': 'somethingNew'};
      final outcome = await saver.save(
        'text',
        expected: ExternalDocStamp.of(utf8.encode('old')),
        encoding: ExternalEncoding.utf8,
        intent: SaveIntent.ifUnchanged,
      );
      expect(outcome, isA<SaveFailed>());
    });

    test('a reply with no bytes is refused rather than opened empty', () async {
      reply = {'token': 't', 'kind': 'appleBookmark', 'name': 'a.md'};
      expect(await source.open(handle), isA<ExternalRefused>());
    });
  });

  group('opening', () {
    test('a writable file arrives with its stamp and a saver', () async {
      final bytes = Uint8List.fromList(utf8.encode('# hi'));
      reply = {
        'token': 'tok2',
        'kind': 'androidUri',
        'name': 'plan.md',
        'bytes': bytes,
        'writable': true,
        'modifiedAtMs': 1770000000000,
      };
      final opened = await source.open(handle) as ExternalOpened;

      expect(opened.document.name, 'plan.md');
      expect(opened.document.markdown, '# hi');
      expect(opened.document.handle.kind, ExternalHandleKind.androidUri);
      expect(opened.document.stamp.sha256, ExternalDocStamp.of(bytes).sha256);
      expect(
        opened.document.stamp.modifiedAt?.millisecondsSinceEpoch,
        1770000000000,
      );
      expect(saverFor(opened.access), isNotNull);

      // The byte ceiling travels from Dart, so `kMarkdownMaxBytes` stays the
      // single source rather than being duplicated in three native files.
      expect(calls.single.arguments['maxBytes'], 2048);
    });

    test(
      'a non-UTF-8 file opens read-only even when the OS says writable',
      () async {
        // The OS answers what it can: may this process write these bytes. It
        // cannot answer whether writing them back would corrupt them.
        reply = {
          'token': 't',
          'kind': 'appleBookmark',
          'name': 'legacy.md',
          'bytes': Uint8List.fromList([0x68, 0x69, 0xFF]),
          'writable': true,
        };
        final opened = await source.open(handle) as ExternalOpened;
        expect(opened.document.encoding, ExternalEncoding.notText);
        expect(opened.access, isA<ExternalReadOnly>());
        expect(
          (opened.access as ExternalReadOnly).reason,
          ReadOnlyReason.notUtf8,
        );
        expect(saverFor(opened.access), isNull);
      },
    );

    test('every refusal keeps its own name', () async {
      for (final entry in {
        'cancelled': ExternalOpenRefusal.cancelled,
        'tooLarge': ExternalOpenRefusal.tooLarge,
        'denied': ExternalOpenRefusal.denied,
        'gone': ExternalOpenRefusal.gone,
      }.entries) {
        reply = {'refused': entry.key};
        expect(
          (await source.pickExternal() as ExternalRefused).reason,
          entry.value,
          reason: entry.key,
        );
      }
    });
  });

  group('saving', () {
    Future<ExternalSaver> writableSaver() async {
      reply = {'state': 'writable', 'reason': ''};
      return saverFor(await source.probe(handle))!;
    }

    test('the expected hash and the force flag reach the platform', () async {
      final saver = await writableSaver();
      final expected = ExternalDocStamp.of(utf8.encode('old'));
      reply = {'outcome': 'ok', 'sha256': 'abc', 'sizeBytes': 4};

      await saver.save(
        'new',
        expected: expected,
        encoding: ExternalEncoding.utf8,
        intent: SaveIntent.ifUnchanged,
      );
      final args = calls.last.arguments as Map;
      // The comparison happens natively because it is the only place
      // check-then-write is atomic — so the hash has to travel.
      expect(args['expectedSha256'], expected.sha256);
      expect(args['force'], isFalse);

      await saver.save(
        'new',
        expected: expected,
        encoding: ExternalEncoding.utf8,
        intent: SaveIntent.force,
      );
      expect((calls.last.arguments as Map)['force'], isTrue);
    });

    test('a byte-order mark is put back on the way out', () async {
      final saver = await writableSaver();
      reply = {'outcome': 'ok', 'sha256': 'abc'};
      await saver.save(
        'hi',
        expected: ExternalDocStamp.of(utf8.encode('x')),
        encoding: ExternalEncoding.utf8Bom,
        intent: SaveIntent.ifUnchanged,
      );
      expect(
        (calls.last.arguments as Map)['bytes'],
        Uint8List.fromList([...kUtf8Bom, ...utf8.encode('hi')]),
      );
    });

    test('a conflict carries what is on disk', () async {
      final saver = await writableSaver();
      reply = {'outcome': 'conflict', 'sha256': 'theirs', 'sizeBytes': 9};
      final outcome = await saver.save(
        'ours',
        expected: ExternalDocStamp.of(utf8.encode('base')),
        encoding: ExternalEncoding.utf8,
        intent: SaveIntent.ifUnchanged,
      );
      expect(outcome, isA<SaveConflict>());
      expect((outcome as SaveConflict).onDisk.sha256, 'theirs');
      expect(outcome.onDisk.sizeBytes, 9);
    });

    test('a grant that died mid-save says so, by name', () async {
      final saver = await writableSaver();
      reply = {'outcome': 'lostAccess', 'reason': 'grantRevoked'};
      final outcome = await saver.save(
        'ours',
        expected: ExternalDocStamp.of(utf8.encode('base')),
        encoding: ExternalEncoding.utf8,
        intent: SaveIntent.ifUnchanged,
      );
      expect(outcome, isA<SaveLostAccess>());
      expect((outcome as SaveLostAccess).reason, LostAccessReason.grantRevoked);
    });
  });

  group('the mailbox for a document the OS opened', () {
    test('an empty mailbox is null, not an error', () async {
      reply = null;
      expect(await source.takeOpenedDocument(), isNull);
      expect(calls.single.method, 'takeOpenedDocument');
    });

    test('a waiting document comes back as its OS token', () async {
      reply = {'osToken': 'file:///Users/x/plan.md'};
      expect(await source.takeOpenedDocument(), 'file:///Users/x/plan.md');
    });
  });

  group('the clipboard half Flutter does not implement', () {
    test('html and an image both come through', () async {
      final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);
      reply = {
        'html': '<b>hi</b>',
        'imageBytes': png,
        'imageMime': 'image/png',
      };
      final board = await source.clipboardRead();
      expect(board.html, '<b>hi</b>');
      expect(board.imageBytes, png);
      expect(board.imageMime, 'image/png');
    });

    test(
      'a platform with no clipboard bridge answers empty, not null-crash',
      () async {
        missing = true;
        final board = await source.clipboardRead();
        expect(board.html, isNull);
        expect(board.imageBytes, isNull);
      },
    );
  });
}
