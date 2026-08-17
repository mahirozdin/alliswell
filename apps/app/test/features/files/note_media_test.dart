import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/files/providers.dart';
import 'package:alliswell/src/features/files/ui/image_viewer.dart';
import 'package:alliswell/src/features/files/ui/note_media.dart';
import 'package:markdown_forge/markdown_forge.dart';
import 'package:alliswell/src/features/notes/data/delta_markdown.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/fake_file_picker.dart';
import '../../support/sync_overrides.dart';

/// OPH-156 — inline note media: `alliswell://file/{id}` embeds render from
/// the replica (image placeholder/tile states, video tile with the file's
/// name), the toolbar insert uploads THEN embeds, and the Dart markdown
/// converter mirrors the server fixtures (OPH-152 parity contract).

Future<Widget> signedInAppWith(
  FakeApi api, {
  List<PickedUpload> picks = const [],
  RecordingFilePicker? picker,
}) async {
  SharedPreferences.setMockInitialValues({});
  final store = InMemorySecretStore();
  await TokenStorage(store).save(fakeSession());
  return ProviderScope(
    retry: awRetry,
    overrides: [
      ...syncTestOverrides(filePicker: picker?.call ?? (_) async => picks),
      secretStoreProvider.overrideWithValue(store),
      apiClientProvider.overrideWithValue(
        fakeDio(FakeHttpClientAdapter(api.handle)),
      ),
    ],
    child: const AllisWellApp(),
  );
}

Future<void> openNote(WidgetTester tester, String title) async {
  await tester.pumpAndSettle();
  await tester.tap(find.text('Notes').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
}

const uri = 'alliswell://file/';

void main() {
  group('deltaToMarkdown embeds (server parity — OPH-152 fixtures)', () {
    const id = 'FIL1000000000000000000000A';
    test('image → markdown image, video → link, mixed with text', () {
      final ops = [
        {'insert': 'Before\n'},
        {
          'insert': {'image': '$uri$id'},
        },
        {'insert': '\n'},
        {
          'insert': {'video': '$uri$id'},
        },
        {'insert': '\nAfter\n'},
      ];
      expect(
        deltaToMarkdown(ops),
        'Before\n![]($uri$id)\n[attachment]($uri$id)\nAfter',
      );
    });

    test('unknown embed shapes drop; foreign urls keep working', () {
      expect(
        deltaToMarkdown([
          {
            'insert': {'formula': 'x^2'},
          },
          {'insert': 'text\n'},
        ]),
        'text',
      );
      expect(
        deltaToMarkdown([
          {
            'insert': {'video': 'https://example.com/clip.mp4'},
          },
          {'insert': '\n'},
        ]),
        '[attachment](https://example.com/clip.mp4)',
      );
    });
  });

  test('fileIdFromEmbedSource parses only our scheme', () {
    expect(
      fileIdFromEmbedSource('$uri${'F'.padRight(26, '0')}'),
      'F'.padRight(26, '0'),
    );
    expect(fileIdFromEmbedSource('https://x/img.png'), isNull);
    expect(fileIdFromEmbedSource('${uri}too-short'), isNull);
  });

  testWidgets('an image embed without a URL renders the honest placeholder '
      'with the file name from the replica', (tester) async {
    final api = FakeApi();
    final note = api.seedNote(title: 'Görselli not', contentMarkdown: 'Şema:');
    final file = api.seedFile(
      name: 'mimari-şema.png',
      targetType: 'note',
      targetId: note['id'] as String,
      mime: 'image/png',
    );
    // ADR-0033: an embed is markdown now, and the alt text is what the
    // placeholder shows — the document's own words, not a filename the
    // renderer went and looked up.
    note['contentMarkdown'] = 'Şema:\n\n![mimari-şema.png]($uri${file['id']})';

    await tester.pumpWidget(await signedInAppWith(api));
    await openNote(tester, 'Görselli not');
    await tester.tap(find.text('Reading'));
    await tester.pumpAndSettle();

    expect(find.byType(MdImage), findsOneWidget);
    // No download URL from the fake server → placeholder naming the image.
    expect(find.text('mimari-şema.png'), findsOneWidget);
  });

  testWidgets('tapping an embed pages the note in DOCUMENT order, not upload '
      'order (OPH-245, DESIGN §30 A11)', (tester) async {
    final api = FakeApi();
    final note = api.seedNote(title: 'Üç görselli not', contentMarkdown: '');
    // Seeded C, B, A — so `created_at DESC` (what the attachment list would
    // give) is the exact REVERSE of body order. Wire the gallery to
    // targetFilesProvider instead of the delta walk and this goes red.
    final third = api.seedFile(
      name: 'ucuncu.png',
      targetType: 'note',
      targetId: note['id'] as String,
      mime: 'image/png',
    );
    final second = api.seedFile(
      name: 'ikinci.png',
      targetType: 'note',
      targetId: note['id'] as String,
      mime: 'image/png',
    );
    final first = api.seedFile(
      name: 'birinci.png',
      targetType: 'note',
      targetId: note['id'] as String,
      mime: 'image/png',
    );
    for (final file in [first, second, third]) {
      // The image is only tappable once a URL mints; the bytes themselves are
      // free to fail (the InkWell wraps the frame, not the Image).
      api.downloadUrls[file['id'] as String] =
          'https://cdn.test/${file['id']}.png';
    }
    note['contentMarkdown'] =
        'Başlangıç\n\n![birinci.png]($uri${first['id']})\n\n'
        'ara metin\n\n![ikinci.png]($uri${second['id']})\n\n'
        'daha fazla metin\n\n![ucuncu.png]($uri${third['id']})';

    await tester.pumpWidget(await signedInAppWith(api));
    await openNote(tester, 'Üç görselli not');
    await tester.tap(find.text('Reading'));
    await tester.pumpAndSettle();

    expect(find.byType(MdImage), findsNWidgets(3));
    // The MIDDLE one: index 2 of 3 only if the walk followed the body.
    await tester.tap(find.byType(MdImage).at(1));
    await tester.pumpAndSettle();

    expect(find.byType(AwImageViewer), findsOneWidget);
    expect(find.text('2 / 3'), findsOneWidget);
    expect(find.text('ikinci.png'), findsOneWidget);
  });

  testWidgets('a video becomes a clickable link, not a broken image', (
    tester,
  ) async {
    final api = FakeApi();
    final note = api.seedNote(title: 'Videolu not', contentMarkdown: '');
    final file = api.seedFile(
      name: 'toplantı-kaydı.mp4',
      targetType: 'note',
      targetId: note['id'] as String,
      mime: 'video/mp4',
    );
    // ADR-0033: markdown has no video node, so a video becomes a LINK — and
    // that is the point. An `![…]()` would draw as a broken image in every
    // renderer, i.e. the document would claim something untrue about itself.
    note['contentMarkdown'] =
        'Kayıt:\n\n[toplantı-kaydı.mp4]($uri${file['id']})';

    await tester.pumpWidget(await signedInAppWith(api));
    await openNote(tester, 'Videolu not');
    await tester.tap(find.text('Reading'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('toplantı-kaydı.mp4', findRichText: true),
      findsWidgets,
    );
  });

  testWidgets('toolbar insert uploads to the NOTE then embeds the file id', (
    tester,
  ) async {
    final api = FakeApi();
    api.seedNote(title: 'Eklemeli not', plainText: 'gövde');

    await tester.pumpWidget(
      await signedInAppWith(
        api,
        picks: [
          PickedUpload.fromBytes(
            name: 'çekim.png',
            bytes: Uint8List.fromList(List.filled(48, 3)),
          ),
        ],
      ),
    );
    await openNote(tester, 'Eklemeli not');

    await tester.tap(find.byIcon(Icons.image_outlined));
    await tester.pumpAndSettle();

    // The upload targeted the note and completed on the fake server…
    expect(api.files, hasLength(1));
    expect(api.files.single['targetType'], 'note');
    expect(api.files.single['mime'], 'image/png');
    // …and the embed landed in the document, as markdown, at the caret.
    final field = tester.widget<TextField>(
      find.byKey(const Key('note-source-field')),
    );
    expect(field.controller!.text, contains('![çekim.png](alliswell://file/'));
  });

  testWidgets('the toolbar buttons ask for the library they NAME (OPH-244)', (
    tester,
  ) async {
    // The highest-value assertion in this file. Both buttons used to call one
    // untyped picker, so on an iPhone "Insert image" opened the document
    // browser — the tooltip was a lie and nothing could see it, because the
    // tests only checked that a file came back.
    final api = FakeApi();
    api.seedNote(title: 'Eklemeli not', plainText: 'gövde');
    final picker = RecordingFilePicker();

    await tester.pumpWidget(await signedInAppWith(api, picker: picker));
    await openNote(tester, 'Eklemeli not');

    await tester.tap(find.byKey(const Key('note-insert-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('note-insert-video')));
    await tester.pumpAndSettle();

    expect(picker.calls, [
      AttachSource.imageLibrary,
      AttachSource.videoLibrary,
    ]);
  });

  testWidgets('a non-media pick uploads AND links, instead of vanishing', (
    tester,
  ) async {
    final api = FakeApi();
    api.seedNote(title: 'Arşivli not', plainText: 'gövde');

    await tester.pumpWidget(
      await signedInAppWith(
        api,
        picks: [
          PickedUpload.fromBytes(
            name: 'yedek.zip',
            bytes: Uint8List.fromList(List.filled(16, 5)),
          ),
        ],
      ),
    );
    await openNote(tester, 'Arşivli not');

    await tester.tap(find.byIcon(Icons.image_outlined));
    await tester.pumpAndSettle();

    expect(api.files, hasLength(1)); // attached (findable in Files tab)…
    // …and, unlike the rich editor, it left a trace you can click. The zip
    // used to vanish into the Files tab behind an apologetic snackbar, because
    // Delta had an image node, a video node and nothing else.
    final field = tester.widget<TextField>(
      find.byKey(const Key('note-source-field')),
    );
    expect(field.controller!.text, contains('[yedek.zip](alliswell://file/'));
    expect(field.controller!.text, isNot(contains('![yedek.zip]')));
  });
}
