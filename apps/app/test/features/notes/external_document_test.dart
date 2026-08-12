import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/notes/data/external_document.dart';
import 'package:alliswell/src/features/notes/data/external_recents.dart';
import 'package:alliswell/src/features/notes/data/markdown_source.dart';

import '../../support/fake_markdown_source.dart';

/// OPH-255 — the external-document layer (ADR-0030, DESIGN §29.5 W1–W6).
///
/// No disk, no platform channel. This is the whole point: the layer that can
/// destroy a user's data is decided here, in Dart, where every state it must
/// survive can be scripted.
void main() {
  /// What a UI does with a probe result. Written as an exhaustive switch
  /// because that is the shape W3 is enforced by: the save action can only be
  /// built in the arm that carries a saver.
  ExternalSaver? saverFor(ExternalAccess access) => switch (access) {
    ExternalWritable(:final saver) => saver,
    ExternalReadOnly() => null,
    ExternalUnreachable() => null,
  };

  group('W3 — a save action cannot exist where it would fail', () {
    test('a read-only file yields no saver at all', () async {
      final source = FakeMarkdownSource(
        external: {'a': FakeExternalFile.text('a.md', '# hi', writable: false)},
      );
      final access = await source.probe(_handle('a'));

      expect(access, isA<ExternalReadOnly>());
      expect(
        (access as ExternalReadOnly).reason,
        ReadOnlyReason.permissionReadOnly,
      );
      // Not "disabled" — absent. There is nothing to bind a button to.
      expect(saverFor(access), isNull);
    });

    test('an expired scope is unreachable, not read-only', () async {
      // The distinction matters to the reader: "this file is read-only" and
      // "we have lost our grip on this file" call for different actions.
      final source = FakeMarkdownSource(
        external: {'a': FakeExternalFile.text('a.md', '# hi')},
      )..expiredTokens.add('a');

      final access = await source.probe(_handle('a'));
      expect(access, isA<ExternalUnreachable>());
      expect(
        (access as ExternalUnreachable).reason,
        LostAccessReason.scopeExpired,
      );
      expect(saverFor(access), isNull);
    });

    test('a grant can die between the probe and the save', () async {
      final source = FakeMarkdownSource(
        external: {'a': FakeExternalFile.text('a.md', '# hi')},
      );
      final saver = saverFor(await source.probe(_handle('a')));
      expect(saver, isNotNull, reason: 'writable a moment ago');

      source.revokeOnSave.add('a');
      final outcome = await saver!.save(
        '# edited',
        expected: ExternalDocStamp.of(utf8.encode('# hi')),
        encoding: ExternalEncoding.utf8,
        intent: SaveIntent.ifUnchanged,
      );
      expect(outcome, isA<SaveLostAccess>());
      expect(source.writes, isEmpty);
    });
  });

  group('W5 — changed underneath is a choice, never a silent overwrite', () {
    test(
      'ifUnchanged refuses, force writes, and reload sees the other edit',
      () async {
        final source = FakeMarkdownSource(
          external: {'a': FakeExternalFile.text('a.md', 'ours')},
        );
        final opened = await source.open(_handle('a')) as ExternalOpened;
        final saver = saverFor(opened.access)!;

        // Somebody else's editor writes the file while ours is open.
        source.mutateBeforeNextSave['a'] = 'theirs';

        final refused = await saver.save(
          'ours edited',
          expected: opened.document.stamp,
          encoding: opened.document.encoding,
          intent: SaveIntent.ifUnchanged,
        );
        expect(refused, isA<SaveConflict>());
        expect(source.writes, isEmpty, reason: 'nothing was overwritten');
        expect(
          (refused as SaveConflict).onDisk.matches(opened.document.stamp),
          isFalse,
        );

        // Leg 1 of the three-way choice: reload.
        final reloaded = await source.open(_handle('a')) as ExternalOpened;
        expect(reloaded.document.markdown, 'theirs');

        // Leg 2: overwrite, which is reachable ONLY from here.
        final forced = await saver.save(
          'ours edited',
          expected: opened.document.stamp,
          encoding: opened.document.encoding,
          intent: SaveIntent.force,
        );
        expect(forced, isA<SaveSucceeded>());
        expect(source.writes.single.intent, SaveIntent.force);
        expect(
          (await source.open(_handle('a')) as ExternalOpened).document.markdown,
          'ours edited',
        );
      },
    );

    test('an untouched file saves on the first try', () async {
      final source = FakeMarkdownSource(
        external: {'a': FakeExternalFile.text('a.md', 'ours')},
      );
      final opened = await source.open(_handle('a')) as ExternalOpened;
      final outcome = await saverFor(opened.access)!.save(
        'ours edited',
        expected: opened.document.stamp,
        encoding: opened.document.encoding,
        intent: SaveIntent.ifUnchanged,
      );
      expect(outcome, isA<SaveSucceeded>());
    });

    test('the hash decides, not the mtime', () {
      // Android's SAF may report no mtime at all, and a file can be touched
      // without changing.
      final bytes = utf8.encode('same');
      final a = ExternalDocStamp.of(bytes, modifiedAt: DateTime(2026));
      final b = ExternalDocStamp.of(bytes, modifiedAt: DateTime(2027));
      expect(a.matches(b), isTrue);
      expect(a == b, isFalse, reason: 'equality is stricter than matches()');
      expect(a.matches(ExternalDocStamp.of(utf8.encode('other'))), isFalse);
    });
  });

  group('W4 — byte-faithful or refuse', () {
    test('a byte-order mark survives a round trip', () {
      final bytes = [...kUtf8Bom, ...utf8.encode('# Başlık')];
      final decoded = decodeExternalBytes(bytes);

      expect(decoded.encoding, ExternalEncoding.utf8Bom);
      expect(
        decoded.text,
        '# Başlık',
        reason: 'the BOM is not part of the text',
      );
      // Dropping it silently would be a byte change nobody asked for.
      expect(encodeExternalText(decoded.text, decoded.encoding), bytes);
    });

    test('CRLF is preserved and no trailing newline is invented', () {
      const text = 'bir\r\niki';
      final decoded = decodeExternalBytes(utf8.encode(text));
      expect(decoded.encoding, ExternalEncoding.utf8);
      expect(
        utf8.decode(encodeExternalText(decoded.text, decoded.encoding)),
        text,
      );
    });

    test('a non-UTF-8 file OPENS, lossily, and can never be written', () {
      // 0xFF is not valid UTF-8 anywhere.
      final decoded = decodeExternalBytes([0x68, 0x69, 0xFF]);
      expect(decoded.encoding, ExternalEncoding.notText);
      expect(decoded.text, startsWith('hi'), reason: 'readable enough to show');

      // Refusing to SHOW a file is worse than refusing to write it — but the
      // write is refused loudly rather than producing plausible bytes.
      expect(
        () => encodeExternalText(decoded.text, decoded.encoding),
        throwsStateError,
      );
    });

    test('the write gate asks both halves of the question', () {
      expect(
        canWriteBack(markdownCanonical: true, encoding: ExternalEncoding.utf8),
        isTrue,
      );
      // A Delta-canonical note would be written back as a REFLOW.
      expect(
        canWriteBack(markdownCanonical: false, encoding: ExternalEncoding.utf8),
        isFalse,
      );
      expect(
        canWriteBack(
          markdownCanonical: true,
          encoding: ExternalEncoding.notText,
        ),
        isFalse,
      );
    });

    test('encoding narrows a writable file to read-only', () async {
      // The OS says yes; W4 says no. The reason travels so the banner can be
      // specific instead of just refusing.
      final source = FakeMarkdownSource(
        external: {
          'a': FakeExternalFile(name: 'a.md', bytes: [0x68, 0xFF]),
        },
      );
      final opened = await source.open(_handle('a')) as ExternalOpened;
      expect(opened.document.encoding, ExternalEncoding.notText);
      expect(opened.access, isA<ExternalReadOnly>());
      expect(
        (opened.access as ExternalReadOnly).reason,
        ReadOnlyReason.notUtf8,
      );
      expect(saverFor(opened.access), isNull);
    });
  });

  group('W6 — a file handed to us once stays reachable', () {
    ExternalDocHandle h(String token, [String name = 'f.md']) =>
        ExternalDocHandle(
          token: token,
          kind: ExternalHandleKind.appleBookmark,
          displayName: name,
        );

    test('most-recent-first, deduplicated by token, capped', () {
      var list = <ExternalDocHandle>[];
      for (var i = 0; i < kExternalRecentsLimit + 3; i++) {
        list = pushExternalRecent(list, h('t$i'));
      }
      expect(list, hasLength(kExternalRecentsLimit));
      expect(list.first.token, 't${kExternalRecentsLimit + 2}');

      // Reopening an older file moves it up rather than duplicating it — and
      // the INCOMING handle wins, which is how a re-minted stale bookmark and
      // a renamed file both land correctly.
      list = pushExternalRecent(list, h('t5', 'renamed.md'));
      expect(list.first.token, 't5');
      expect(list.first.displayName, 'renamed.md');
      expect(list.where((e) => e.token == 't5'), hasLength(1));
      expect(list, hasLength(kExternalRecentsLimit));
    });

    test('a round trip through storage keeps the list', () {
      final list = [h('t1', 'a.md'), h('t2', 'b.md')];
      expect(parseExternalRecents(encodeExternalRecents(list)), list);
    });

    test('junk is dropped, never thrown', () {
      // One bad row must not cost the list.
      expect(parseExternalRecents(null), isEmpty);
      expect(parseExternalRecents('   '), isEmpty);
      expect(parseExternalRecents('not json at all'), isEmpty);
      expect(parseExternalRecents('{"not":"a list"}'), isEmpty);

      final mixed = jsonEncode([
        {'token': 't1', 'kind': 'appleBookmark', 'name': 'ok.md'},
        {'token': '', 'kind': 'appleBookmark', 'name': 'empty token'},
        {'token': 't2', 'kind': 'fromTheFuture', 'name': 'unknown kind'},
        {'token': 't3', 'name': 'no kind'},
        'a bare string',
        // Unknown keys are tolerated, which is what lets OPH-251 add its
        // project link without stranding the entries already on disk.
        {'token': 't4', 'kind': 'androidUri', 'name': 'x.md', 'projectId': 'p'},
      ]);
      final parsed = parseExternalRecents(mixed);
      expect(parsed.map((e) => e.token), ['t1', 't4']);
    });

    test('a file that turned out to be gone can be dropped', () {
      final list = [h('t1'), h('t2')];
      expect(dropExternalRecent(list, 't1').map((e) => e.token), ['t2']);
      expect(dropExternalRecent(list, 'nope'), hasLength(2));
    });
  });

  group('until OPH-256, every platform says so honestly', () {
    test('the production source refuses rather than pretending', () async {
      const source = PlatformMarkdownSource();
      expect(
        await source.pickExternal(),
        isA<ExternalRefused>().having(
          (r) => r.reason,
          'reason',
          ExternalOpenRefusal.unsupported,
        ),
      );
      final access = await source.probe(_handle('a'));
      expect(access, isA<ExternalUnreachable>());
      expect(
        (access as ExternalUnreachable).reason,
        LostAccessReason.unsupportedPlatform,
      );
      // The point of the honest answer: still no saver, so still no button.
      expect(saverFor(access), isNull);
    });
  });

  group('opening', () {
    test('a missing file is refused, not returned empty', () async {
      final source = FakeMarkdownSource();
      expect(
        await source.open(_handle('nope')),
        isA<ExternalRefused>().having(
          (r) => r.reason,
          'reason',
          ExternalOpenRefusal.gone,
        ),
      );
    });

    test('backing out of the picker is cancelled, not a failure', () async {
      final source = FakeMarkdownSource();
      expect(
        await source.pickExternal(),
        isA<ExternalRefused>().having(
          (r) => r.reason,
          'reason',
          ExternalOpenRefusal.cancelled,
        ),
      );
    });

    test('an adopted OS token becomes a handle we can come back to', () async {
      final source = FakeMarkdownSource(
        external: {'content://x/1': FakeExternalFile.text('plan.md', '# plan')},
      );
      final opened = await source.adopt('content://x/1') as ExternalOpened;
      expect(opened.document.name, 'plan.md');
      expect(opened.document.markdown, '# plan');

      // The handle is the thing recents stores — reopening must work from it
      // alone, with nothing else carried over.
      final again = await source.open(opened.document.handle);
      expect((again as ExternalOpened).document.markdown, '# plan');
    });
  });
}

ExternalDocHandle _handle(String token) => ExternalDocHandle(
  token: token,
  kind: ExternalHandleKind.plainPath,
  displayName: token,
);
