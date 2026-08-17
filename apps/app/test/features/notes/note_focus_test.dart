import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/notes/data/note.dart';
import 'package:alliswell/src/features/notes/data/note_document.dart';
import 'package:markdown_forge/markdown_forge.dart';
import 'package:alliswell/src/theme/theme.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/sync_overrides.dart';

/// OPH-270 — the caret stays where the person put it.
///
/// Reported from a phone: type in the body, wait for autosave, and the moment
/// the "saved" tick appears the caret jumps into the TITLE, mid-word. Autosave
/// runs a `setState` (the save indicator), so this reproduces the editor's
/// shape — a title field above, the body below — and rebuilds the parent the
/// way autosave does.
NoteDetail _note() => const NoteDetail(
  id: 'n1',
  workspaceId: 'w1',
  title: 'Başlık burada',
  snippet: '',
  isPinned: false,
  isArchived: false,
  revision: 1,
  contentMarkdown: 'gövde',
);

class _Host extends StatefulWidget {
  const _Host({required this.doc, required this.trigger});

  final NoteDocument doc;
  final ValueNotifier<int> trigger;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  @override
  void initState() {
    super.initState();
    widget.trigger.addListener(_rebuild);
  }

  @override
  void dispose() {
    widget.trigger.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: buildAwTheme(Brightness.light),
    home: Scaffold(
      body: Column(
        children: [
          // Stands in for the save indicator: same shape as the real editor,
          // where an idle `SizedBox.shrink()` becomes a row of icon + text.
          Row(
            children: [
              const Expanded(child: SizedBox(height: 24)),
              if (widget.trigger.value > 0) const Text('Saved'),
            ],
          ),
          TextField(
            key: const Key('note-title'),
            controller: widget.doc.title,
            maxLines: null,
          ),
          Expanded(child: SourceMode(controller: widget.doc.source)),
        ],
      ),
    ),
  );
}

void main() {
  bool hasFocus(WidgetTester tester, Key key) => tester
      .widget<EditableText>(
        find.descendant(
          of: find.byKey(key),
          matching: find.byType(EditableText),
        ),
      )
      .focusNode
      .hasFocus;

  testWidgets('a parent rebuild leaves the caret in the body', (tester) async {
    final doc = NoteDocument(note: _note());
    addTearDown(doc.dispose);
    final trigger = ValueNotifier(0);
    addTearDown(trigger.dispose);

    await tester.pumpWidget(_Host(doc: doc, trigger: trigger));
    await tester.pumpAndSettle();

    await tester.showKeyboard(find.byKey(const Key('note-source-field')));
    await tester.pumpAndSettle();
    expect(hasFocus(tester, const Key('note-source-field')), isTrue);

    // What autosave does: one setState, nothing else.
    trigger.value++;
    await tester.pumpAndSettle();

    expect(
      hasFocus(tester, const Key('note-title')),
      isFalse,
      reason: 'nothing may pull the caret into the title while someone types',
    );
    expect(
      hasFocus(tester, const Key('note-source-field')),
      isTrue,
      reason: 'the caret belongs where the person put it',
    );
  });

  testWidgets('the rich editor keeps ONE focus node across rebuilds', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    // A note written in the app: Delta-canonical, so the body is the Quill
    // editor — which is what everyone actually types into.
    final api = FakeApi()..seedNote(title: 'Başlık burada', plainText: 'gövde');
    final secrets = InMemorySecretStore();
    await TokenStorage(secrets).save(fakeSession());

    await tester.pumpWidget(
      ProviderScope(
        retry: awRetry,
        overrides: [
          ...syncTestOverrides(),
          secretStoreProvider.overrideWithValue(secrets),
          apiClientProvider.overrideWithValue(
            fakeDio(FakeHttpClientAdapter(api.handle)),
          ),
        ],
        child: const AllisWellApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Notes').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Başlık burada'));
    await tester.pumpAndSettle();

    final editor = find.byKey(const Key('note-source-field'));
    expect(editor, findsOneWidget, reason: 'a note opens in its editor');
    final before = tester.widget<TextField>(editor).controller;

    // Exactly what autosave does: a setState, plus a write that comes back
    // through the replica. Pinning is those two things behind one tap, and it
    // leaves the body alone — so anything that happens to the caret here is
    // the rebuild's doing, not the edit's.
    await tester.tap(find.byIcon(Icons.star_border));
    await tester.pumpAndSettle();

    final after = tester.widget<TextField>(editor).controller;
    expect(
      identical(before, after),
      isTrue,
      reason:
          'OPH-270, restated for the markdown editor: the controller belongs '
          'to the document and outlives every rebuild (D3). Quill was worse — '
          'QuillEditor.basic MINTED a new FocusNode whenever one was not '
          'passed, so every autosave setState threw the caret away and the '
          'title, first focusable in the tree, caught the focus. A TextField '
          'owns its focus node in its State, so the failure mode is gone with '
          'the package; what has to stay true is that the CONTROLLER is not '
          'rebuilt underneath it.',
    );
    expect(
      hasFocus(tester, const Key('note-title')),
      isFalse,
      reason: 'saving must never move the caret into the title',
    );
  });

  testWidgets('typing in the body survives the autosave that follows it', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final api = FakeApi()
      ..seedNote(title: 'Başlık burada', contentMarkdown: 'gövde');
    final store = InMemorySecretStore();
    await TokenStorage(store).save(fakeSession());

    await tester.pumpWidget(
      ProviderScope(
        retry: awRetry,
        overrides: [
          ...syncTestOverrides(),
          secretStoreProvider.overrideWithValue(store),
          apiClientProvider.overrideWithValue(
            fakeDio(FakeHttpClientAdapter(api.handle)),
          ),
        ],
        child: const AllisWellApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Notes').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Başlık burada'));
    await tester.pumpAndSettle();
    // A markdown-canonical note opens in Reading; Source is its editor.
    await tester.tap(find.text('Source'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('note-source-field')),
      'gövdeye yazıyorum',
    );
    // Deliberately NOT pumpAndSettle: that would run the autosave timer, and
    // the point is to be mid-typing when it fires.
    await tester.pump();
    expect(hasFocus(tester, const Key('note-source-field')), isTrue);

    // The autosave debounce, the write, and the replica change coming back.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(
      hasFocus(tester, const Key('note-title')),
      isFalse,
      reason: 'saving must never move the caret into the title',
    );
    expect(
      hasFocus(tester, const Key('note-source-field')),
      isTrue,
      reason: 'the person is still typing; autosave is not an interruption',
    );
  });
}
