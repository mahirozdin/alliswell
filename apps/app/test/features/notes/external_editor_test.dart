import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/notes/data/external_document.dart';
import 'package:alliswell/src/features/notes/data/external_session.dart';
import 'package:alliswell/src/features/notes/ui/note_editor_screen.dart';
import 'package:alliswell/src/theme/theme.dart';

import '../../support/fake_markdown_source.dart';
import '../../support/sync_overrides.dart';

/// OPH-251 — somebody else's file, in our own editor (DESIGN §29.5).
///
/// The document opens in the SAME editor a note does. What these tests pin is
/// the part that must differ: it is marked, it is never autosaved, and the
/// save action exists only where writing is actually possible.
void main() {
  Future<ProviderContainer> openIn(
    WidgetTester tester,
    FakeMarkdownSource source,
    String token,
  ) async {
    final container = ProviderContainer(
      overrides: syncTestOverrides(markdownSource: source),
    );
    addTearDown(container.dispose);
    await container
        .read(externalSessionProvider.notifier)
        .openHandle(
          ExternalDocHandle(
            token: token,
            kind: ExternalHandleKind.plainPath,
            displayName: token,
          ),
        );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAwTheme(Brightness.light),
          home: const NoteEditorScreen(external: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('W1 — the band names the real file, and the editor holds it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final source = FakeMarkdownSource(
      external: {'plan.md': FakeExternalFile.text('plan.md', '# Yayla')},
    );
    await openIn(tester, source, 'plan.md');

    expect(find.byKey(const Key('external-doc-band')), findsOneWidget);
    expect(find.text('plan.md'), findsWidgets);
    // The same editor a note gets — the source surface, not a viewer.
    expect(find.byKey(const Key('note-source-field')), findsOneWidget);
  });

  testWidgets('W3 — a read-only file gets NO save button, not a disabled one', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final source = FakeMarkdownSource(
      external: {
        'ro.md': FakeExternalFile.text('ro.md', '# hi', writable: false),
      },
    );
    await openIn(tester, source, 'ro.md');

    // Absent, not disabled: there is no saver to bind it to.
    expect(find.byKey(const Key('external-save')), findsNothing);
    // Keeping the file is still possible — it just never touches the file.
    expect(find.byKey(const Key('external-save-as-note')), findsOneWidget);
    expect(find.byKey(const Key('external-doc-state')), findsOneWidget);
  });

  testWidgets('W4 — a non-UTF-8 file cannot be written and says why', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final source = FakeMarkdownSource(
      external: {
        'legacy.md': FakeExternalFile(name: 'legacy.md', bytes: [0x68, 0xFF]),
      },
    );
    final container = await openIn(tester, source, 'legacy.md');

    // The OS would allow the write; W4 does not.
    expect(
      container.read(externalSessionProvider)!.document.encoding,
      ExternalEncoding.notText,
    );
    expect(find.byKey(const Key('external-save')), findsNothing);
  });

  testWidgets('W3 — a writable file does get the save action', (tester) async {
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final source = FakeMarkdownSource(
      external: {'ok.md': FakeExternalFile.text('ok.md', '# hi')},
    );
    await openIn(tester, source, 'ok.md');

    expect(find.byKey(const Key('external-save')), findsOneWidget);
  });

  testWidgets('W2 — typing never writes the file, saving does', (tester) async {
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final source = FakeMarkdownSource(
      external: {'ok.md': FakeExternalFile.text('ok.md', 'before')},
    );
    await openIn(tester, source, 'ok.md');

    await tester.enterText(find.byKey(const Key('note-source-field')), 'after');
    // Well past the autosave debounce: an external document has no timer at
    // all, which is the mechanism rather than a lucky race.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(source.writes, isEmpty, reason: 'autosave must not touch the file');

    await tester.tap(find.byKey(const Key('external-save')));
    await tester.pumpAndSettle();
    expect(source.writes, hasLength(1));
    expect(String.fromCharCodes(source.writes.single.bytes), 'after');
    expect(source.writes.single.intent, SaveIntent.ifUnchanged);
  });

  testWidgets('W5 — a file changed underneath offers three choices', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final source = FakeMarkdownSource(
      external: {'ok.md': FakeExternalFile.text('ok.md', 'ours')},
    );
    await openIn(tester, source, 'ok.md');

    await tester.enterText(find.byKey(const Key('note-source-field')), 'mine');
    await tester.pumpAndSettle();
    source.mutateBeforeNextSave['ok.md'] = 'theirs';

    await tester.tap(find.byKey(const Key('external-save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('external-conflict-reload')), findsOneWidget);
    expect(find.byKey(const Key('external-conflict-copy')), findsOneWidget);
    expect(
      find.byKey(const Key('external-conflict-overwrite')),
      findsOneWidget,
    );
    expect(source.writes, isEmpty, reason: 'nothing was overwritten yet');

    // Overwrite is reachable only from here — and only now does force travel.
    await tester.tap(find.byKey(const Key('external-conflict-overwrite')));
    await tester.pumpAndSettle();
    expect(source.writes.single.intent, SaveIntent.force);
  });
}
