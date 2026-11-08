import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/notes/ui/note_editor_screen.dart';
import 'package:alliswell/src/features/projects/ui/project_detail_screen.dart';
import 'package:alliswell/src/i18n/i18n.dart';

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
    expect(find.text('error.notFound'.tr()), findsOneWidget);

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
