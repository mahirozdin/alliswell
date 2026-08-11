import 'package:drift/drift.dart' show DatabaseConnection, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/notes/data/note.dart';
import 'package:alliswell/src/sync/db/database.dart';

/// OPH-248 — the replica records which field is canonical (ADR-0028 §1).
void main() {
  late AwDatabase db;

  setUp(() => db = AwDatabase(DatabaseConnection(NativeDatabase.memory())));
  tearDown(() => db.close());

  test("a note written without the column reads back as 'delta'", () async {
    // The whole reason the migration backfills nothing: the default IS the
    // right answer for every note the WYSIWYG ever wrote.
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: '01J0000000000000000000000A',
            workspaceId: '01J0000000000000000000000W',
            title: 'Eski not',
          ),
        );

    final row = await db.select(db.notes).getSingle();
    expect(row.contentFormat, 'delta');
  });

  test('a markdown-canonical note keeps its format', () async {
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: '01J0000000000000000000000B',
            workspaceId: '01J0000000000000000000000W',
            title: 'README',
            contentFormat: const Value('markdown'),
          ),
        );

    final row = await db.select(db.notes).getSingle();
    expect(row.contentFormat, 'markdown');
  });

  test('the schema version moved with the column', () {
    // A column added without bumping the version is a column existing devices
    // never get.
    expect(db.schemaVersion, greaterThanOrEqualTo(17));
  });

  group('NoteDetail', () {
    test("defaults to 'delta' when the server does not say", () {
      final note = NoteDetail.fromJson({
        'id': 'a',
        'workspaceId': 'w',
        'title': 't',
        'isPinned': false,
        'isArchived': false,
        'revision': 1,
      });

      expect(note.contentFormat, 'delta');
      expect(note.isMarkdownCanonical, isFalse);
    });

    test('reads the format the server sent', () {
      final note = NoteDetail.fromJson({
        'id': 'a',
        'workspaceId': 'w',
        'title': 't',
        'isPinned': false,
        'isArchived': false,
        'revision': 1,
        'contentFormat': 'markdown',
      });

      expect(note.isMarkdownCanonical, isTrue);
    });
  });
}
