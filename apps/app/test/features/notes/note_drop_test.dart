import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/files/ui/note_drop_target.dart';
import 'package:alliswell/src/features/notes/data/note.dart';
import 'package:alliswell/src/features/notes/data/note_document.dart';

/// OPH-250 — a file dropped onto the editor.
///
/// The OS drop EVENT itself is a platform channel and is verified on a device,
/// not here (the same boundary the native bridges keep). What is testable is
/// everything the drop decides once the file is in hand: how it becomes an
/// upload, and where the document puts it.
void main() {
  NoteDocument docWith({String markdown = ''}) {
    final doc = NoteDocument(
      note: NoteDetail(
        id: 'n',
        workspaceId: 'w',
        title: 't',
        snippet: '',
        isPinned: false,
        isArchived: false,
        revision: 1,
        contentMarkdown: markdown,
      ),
    );
    addTearDown(doc.dispose);
    return doc;
  }

  group('one insert path, because there is one surface', () {
    test('an image embeds, anything else links', () {
      // Markdown has no video embed. `![…]()` for a video would draw a broken
      // image in every renderer — the document would be claiming something
      // untrue about its own contents.
      final doc = docWith(markdown: 'before ');
      doc.source.selection = const TextSelection.collapsed(offset: 7);

      expect(
        doc.insertFile(fileId: 'F1', name: 'cat.png', mime: 'image/png'),
        NoteInsert.embedded,
      );
      expect(doc.source.text, 'before ![cat.png](alliswell://file/F1)');

      expect(
        doc.insertFile(fileId: 'F2', name: 'clip.mp4', mime: 'video/mp4'),
        NoteInsert.linked,
      );
      expect(doc.source.text, contains('[clip.mp4](alliswell://file/F2)'));
      expect(doc.source.text, isNot(contains('![clip.mp4]')));
    });

    test('a file the document cannot show is still attached, and says so', () {
      // Markdown has no video embed and no attachment node. A zip really is
      // attached to the note — it shows up in the project Files tab — but the
      // body has no way to draw it, and silence there reads as a failed
      // upload. The caller owes the reader a word, so it must be told.
      final doc = docWith();

      expect(
        doc.insertFile(fileId: 'F3', name: 'a.zip', mime: 'application/zip'),
        NoteInsert.linked,
      );
      expect(doc.source.text, contains('[a.zip](alliswell://file/F3)'));
    });

    test('an invalid selection appends instead of throwing', () {
      // A drop does not move the caret first, so the selection may never have
      // been set at all.
      final doc = docWith(markdown: 'text');
      expect(doc.source.selection.isValid, isFalse);
      doc.insertFile(fileId: 'F1', name: 'a.png', mime: 'image/png');
      expect(doc.source.text, 'text![a.png](alliswell://file/F1)');
    });
  });

  group('a dropped file becomes an upload', () {
    test('a path-backed drop keeps the path, and re-opens', () async {
      final dir = await Directory.systemTemp.createTemp('aw_drop');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/note.png')
        ..writeAsBytesSync(Uint8List.fromList([1, 2, 3, 4, 5]));

      final pick = await pickedFromDrop(
        XFile(file.path, mimeType: 'image/png'),
      );

      expect(pick.name, 'note.png');
      expect(pick.mime, 'image/png');
      expect(pick.sizeBytes, 5);
      // RE-openable is the contract: a retry after a failed PUT reads again.
      expect(await pick.open().expand((c) => c).toList(), [1, 2, 3, 4, 5]);
      expect(await pick.open().expand((c) => c).toList(), [1, 2, 3, 4, 5]);
    });

    test('a pathless drop (the web) falls back to bytes', () async {
      // `XFile.fromData` does not carry `name` on the VM (io derives it from
      // the path), which is exactly the nameless case the fallback is for —
      // an empty name would upload a blank row and leave `mimeForName`
      // nothing to guess from.
      final pick = await pickedFromDrop(
        XFile.fromData(Uint8List.fromList([9, 9]), mimeType: 'image/png'),
      );
      expect(pick.name, 'dropped');
      expect(pick.mime, 'image/png');
      expect(pick.sizeBytes, 2);
      expect(await pick.open().expand((c) => c).toList(), [9, 9]);
    });
  });

  group('platforms that cannot drop are not pretended at', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('iOS has no drop plugin, so it reports no support', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(supportsFileDrop, isFalse);
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(supportsFileDrop, isTrue);
    });

    testWidgets('on iOS the target is a plain pass-through', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await tester.pumpWidget(
        MaterialApp(
          home: NoteDropTarget(
            onFiles: (_) async {},
            child: const Text('body'),
          ),
        ),
      );
      // The child is there; the overlay machinery is not built at all, rather
      // than built around a channel nobody answers.
      expect(find.text('body'), findsOneWidget);
      expect(find.byKey(const Key('note-drop-overlay')), findsNothing);
      // Reset INSIDE the body: the framework asserts on a leaked foundation
      // debug variable before tearDown runs.
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
