import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/notes/ui/note_editor_screen.dart';
import 'package:alliswell/src/features/projects/ui/project_detail_screen.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/providers.dart';

import '../projects/fake_api.dart';
import '../tasks/tasks_flow_test.dart' show signedInAppWith;

/// R-05 (OPH-392) — the task link's "not found" answer, applied to notes.
///
/// A link to a note deleted since (or never this person's, or mistyped) kept
/// the editor on a bare spinner forever: no app bar, no answer, no way out.
/// The note's detail stream drops a missing row, so it never emitted. Now the
/// editor asks the server once and says "not found" with a way home; and the
/// project page's dead end gets the same way home.
void main() {
  void coldStartAt(WidgetTester tester, String location) {
    tester.binding.platformDispatcher.defaultRouteNameTestValue = location;
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
  }

  testWidgets('a cold start on /notes/<id> still opens that note', (
    tester,
  ) async {
    final api = FakeApi();
    final note = api.seedNote(title: 'Grocery list');
    coldStartAt(tester, '/notes/${note['id']}');
    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();
    expect(find.byType(NoteEditorScreen), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byKey(const Key('note-detail-gone')), findsNothing);
  });

  testWidgets('a link to a deleted note says not found with an app bar and '
      'a way home, not an endless spinner', (tester) async {
    final api = FakeApi()..seedNote(title: 'Something else');
    coldStartAt(tester, '/notes/NTE0000000000000000000GONE');
    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();
    expect(find.byType(NoteEditorScreen), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byKey(const Key('note-detail-gone')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(NoteEditorScreen),
        matching: find.byType(AppBar),
      ),
      findsOneWidget,
    );
    // T-02: it names what is missing — "Note not found" with a matching
    // icon — instead of the connection error's "Something went wrong" and
    // cloud-off badge, which read as a network fault.
    expect(find.text('note.notFoundTitle'.tr()), findsOneWidget);
    expect(find.text('note.notFoundBody'.tr()), findsOneWidget);
    expect(find.text('state.somethingWrong'.tr()), findsNothing);
    expect(find.byIcon(Icons.cloud_off_outlined), findsNothing);
    expect(find.byIcon(Icons.search_off_outlined), findsOneWidget);

    await tester.tap(find.text('error.goHome'.tr()));
    await tester.pumpAndSettle();
    expect(find.byType(NoteEditorScreen), findsNothing);
  });

  testWidgets('a mistyped note link (400 from the API) says not found too', (
    tester,
  ) async {
    final api = FakeApi()..seedNote(title: 'Something else');
    coldStartAt(tester, '/notes/typo');
    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byKey(const Key('note-detail-gone')), findsOneWidget);
  });

  testWidgets('a note link the server cannot answer (offline, 5xx) says so, '
      'with retry', (tester) async {
    final api = FakeApi()..seedNote(title: 'Something else');
    coldStartAt(tester, '/notes/NTE0000000000000000000GONE');
    await tester.pumpWidget(await signedInAppWith(api));
    api.offline = true;
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byKey(const Key('note-detail-unreachable')), findsOneWidget);

    api.offline = false;
    await tester.tap(find.text('common.retry'.tr()));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('note-detail-gone')), findsOneWidget);
  });

  group('T-02: a note deleted on the server while it is open', () {
    /// What the sync applier does with a pulled note tombstone.
    Future<void> deleteRowAsAPullWould(WidgetTester tester, String id) async {
      final db = ProviderScope.containerOf(
        tester.element(find.byType(NoteEditorScreen)),
      ).read(databaseProvider);
      await tester.runAsync(() async {
        await (db.delete(db.notes)..where((n) => n.id.equals(id))).go();
      });
    }

    Future<String> openNote(WidgetTester tester, FakeApi api) async {
      final note = api.seedNote(title: 'Grocery list', contentMarkdown: 'milk');
      final id = note['id'] as String;
      coldStartAt(tester, '/notes/$id');
      await tester.pumpWidget(await signedInAppWith(api));
      await tester.pumpAndSettle();
      expect(find.byType(NoteEditorScreen), findsOneWidget);
      expect(find.byKey(const Key('note-deleted-banner')), findsNothing);
      return id;
    }

    testWidgets('turns read-only with a "this note was deleted" notice and '
        'stops saving', (tester) async {
      final api = FakeApi();
      final id = await openNote(tester, api);

      // Unsaved typing at the moment the tombstone lands.
      await tester.enterText(
        find.byKey(const Key('note-title')),
        'Grocery list, typed',
      );
      await deleteRowAsAPullWould(tester, id);
      await tester.pumpAndSettle();
      final pushedBefore = api.pushedMutations.length;
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('note-deleted-banner')), findsOneWidget);
      expect(find.text('note.deletedNotice'.tr()), findsOneWidget);
      // Read-only: the title no longer edits, no source editor or mode
      // switch, and none of the actions that name a note that is gone.
      final title = tester.widget<TextField>(
        find.byKey(const Key('note-title')),
      );
      expect(title.readOnly, isTrue);
      expect(find.text('Grocery list, typed'), findsOneWidget);
      expect(find.byTooltip('note.deleteTooltip'.tr()), findsNothing);
      expect(find.byTooltip('note.pin'.tr()), findsNothing);
      expect(find.byTooltip('note.archive'.tr()), findsNothing);
      // The typing is never sent after the note: no update for a gone row.
      expect(
        api.pushedMutations
            .skip(pushedBefore)
            .where((m) => m['entityType'] == 'note'),
        isEmpty,
      );
    });

    testWidgets('the notice closes the editor', (tester) async {
      final api = FakeApi();
      final id = await openNote(tester, api);
      await deleteRowAsAPullWould(tester, id);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('note-deleted-close')));
      await tester.pumpAndSettle();
      expect(find.byType(NoteEditorScreen), findsNothing);
    });

    testWidgets('a remote edit (row still there) shows no notice', (
      tester,
    ) async {
      final api = FakeApi();
      final id = await openNote(tester, api);
      final db = ProviderScope.containerOf(
        tester.element(find.byType(NoteEditorScreen)),
      ).read(databaseProvider);
      await tester.runAsync(() async {
        await (db.update(db.notes)..where((n) => n.id.equals(id))).write(
          const NotesCompanion(title: Value('Grocery list (edited)')),
        );
      });
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('note-deleted-banner')), findsNothing);
    });
  });

  testWidgets('a link to a missing project offers the same way home', (
    tester,
  ) async {
    final api = FakeApi()..seedProject(name: 'Garden');
    coldStartAt(tester, '/projects/PRJ0000000000000000000GONE');
    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();
    expect(find.byType(ProjectDetailScreen), findsOneWidget);
    expect(find.text('project.notFound'.tr()), findsOneWidget);

    await tester.tap(find.text('error.goHome'.tr()));
    await tester.pumpAndSettle();
    expect(find.byType(ProjectDetailScreen), findsNothing);
  });
}
