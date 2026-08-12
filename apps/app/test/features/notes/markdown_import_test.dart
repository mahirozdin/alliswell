import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/ai/data/share_intent.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/notes/data/markdown_source.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/fake_share_intent.dart';
import '../../support/fake_markdown_source.dart';
import '../../support/sync_overrides.dart';

/// Round 16 follow-up: open a `.md` file with AllisWell and keep it as a note.

const _markdown = '''
# Yayla planı

Ağustos sonu için **Pokut** rotası.

- [x] kamp malzemeleri
- [ ] rezervasyon

> Sis çökerse Pokut'ta kal.
''';

Future<Widget> _app(
  FakeApi api, {
  MarkdownSource? markdown,
  FakeShareIntentSource? share,
}) async {
  SharedPreferences.setMockInitialValues({});
  final store = InMemorySecretStore();
  await TokenStorage(store).save(fakeSession());
  return ProviderScope(
    retry: awRetry,
    overrides: [
      ...syncTestOverrides(shareIntentSource: share, markdownSource: markdown),
      secretStoreProvider.overrideWithValue(store),
      apiClientProvider.overrideWithValue(
        fakeDio(FakeHttpClientAdapter(api.handle)),
      ),
    ],
    child: const AllisWellApp(),
  );
}

void main() {
  group('recognising a markdown file', () {
    test('by extension, in any case, and never by mime type alone', () {
      expect(isMarkdownPath('/tmp/notlar.md'), isTrue);
      expect(isMarkdownPath('/tmp/NOTLAR.MD'), isTrue);
      expect(isMarkdownPath('/tmp/a.markdown'), isTrue);
      expect(isMarkdownPath('/tmp/a.mkd'), isTrue);
      expect(isMarkdownPath('/tmp/a.txt'), isFalse);
      expect(isMarkdownPath('/tmp/mdfile'), isFalse);
      // A directory that merely CONTAINS "md" is not a markdown file.
      expect(isMarkdownPath('/md/notes/readme.pdf'), isFalse);
    });

    test('picks the markdown out of a mixed share', () {
      final media = [
        SharedMediaFile(path: '/tmp/photo.jpg', type: SharedMediaType.image),
        SharedMediaFile(path: '/tmp/plan.md', type: SharedMediaType.file),
      ];
      expect(markdownPathFromMedia(media), '/tmp/plan.md');
      // The AI path still sees nothing it can use — the two consumers do not
      // steal each other's traffic.
      expect(payloadFromMedia(media), isNull);
    });
  });

  testWidgets('the OS opens a .md file: it lands in the viewer, then a note', (
    tester,
  ) async {
    final api = FakeApi();
    final files = FakeMarkdownSource(files: {'/tmp/yayla.md': _markdown});
    final share = FakeShareIntentSource(initialDocumentPath: '/tmp/yayla.md');

    await tester.pumpWidget(await _app(api, markdown: files, share: share));
    await tester.pumpAndSettle();

    // The shell routed to the viewer on its own.
    expect(files.reads, ['/tmp/yayla.md']);
    expect(find.byKey(const Key('md-source-name')), findsOneWidget);
    expect(find.text('yayla.md'), findsOneWidget);
    // Rendered as a real document, not as raw text.
    expect(find.byType(QuillEditor), findsOneWidget);
    // The leading H1 became the title instead of repeating in the body.
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('md-title')))
          .controller!
          .text,
      'Yayla planı',
    );

    await tester.tap(find.byKey(const Key('md-import')));
    await tester.pumpAndSettle();

    expect(api.notes, hasLength(1));
    final created = api.notes.single;
    expect(created['title'], 'Yayla planı');
    // The structure survived the import — this is a note, not a wall of text.
    final delta = (created['contentDelta'] as List)
        .cast<Map<String, dynamic>>();
    expect(
      delta.any((op) => (op['attributes'] as Map?)?['list'] == 'checked'),
      isTrue,
    );
    expect(
      delta.any((op) => (op['attributes'] as Map?)?['blockquote'] == true),
      isTrue,
    );
    expect(
      delta.any((op) => (op['attributes'] as Map?)?['bold'] == true),
      isTrue,
    );
  });

  testWidgets('the Notes tab can open a file itself (reachability)', (
    tester,
  ) async {
    final api = FakeApi();
    final files = FakeMarkdownSource(
      picked: const MarkdownDocument(
        name: 'okuma.md',
        markdown: '# Okuma\n\nmetin\n',
      ),
    );

    await tester.pumpWidget(await _app(api, markdown: files));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Notes').last);
    await tester.pumpAndSettle();

    // OPH-251 turned the single button into a menu: editing the file itself
    // and importing it as a note are different jobs, and the import is this
    // one.
    await tester.tap(find.byKey(const Key('notes-open-markdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import as a note…'));
    await tester.pumpAndSettle();

    expect(files.pickCalls, 1);
    expect(find.text('okuma.md'), findsOneWidget);
  });

  testWidgets(
    'a file the OS names but cannot deliver does not strand the app',
    (tester) async {
      final api = FakeApi();
      // The path is announced but reading it yields nothing (an expired
      // permission-scoped URI, a file that moved).
      final files = FakeMarkdownSource(files: const {});
      final share = FakeShareIntentSource(initialDocumentPath: '/tmp/gone.md');

      await tester.pumpWidget(await _app(api, markdown: files, share: share));
      await tester.pumpAndSettle();

      expect(files.reads, ['/tmp/gone.md']);
      // No viewer was pushed, and the app is still usable where it was.
      expect(find.byKey(const Key('md-source-name')), findsNothing);
      expect(find.byType(AllisWellApp), findsOneWidget);
    },
  );
}
