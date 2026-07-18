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
import 'package:alliswell/src/features/files/ui/note_media.dart';
import 'package:alliswell/src/features/notes/data/delta_markdown.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/sync_overrides.dart';

/// OPH-156 — inline note media: `alliswell://file/{id}` embeds render from
/// the replica (image placeholder/tile states, video tile with the file's
/// name), the toolbar insert uploads THEN embeds, and the Dart markdown
/// converter mirrors the server fixtures (OPH-152 parity contract).

Future<Widget> signedInAppWith(
  FakeApi api, {
  List<PickedUpload> picks = const [],
}) async {
  SharedPreferences.setMockInitialValues({});
  final store = InMemorySecretStore();
  await TokenStorage(store).save(fakeSession());
  return ProviderScope(
    retry: awRetry,
    overrides: [
      ...syncTestOverrides(filePicker: () async => picks),
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
    final note = api.seedNote(
      title: 'Görselli not',
      contentDelta: [
        {'insert': 'Şema:\n'},
        {
          'insert': {'image': ''},
        },
        {'insert': '\n'},
      ],
    );
    final file = api.seedFile(
      name: 'mimari-şema.png',
      targetType: 'note',
      targetId: note['id'] as String,
      mime: 'image/png',
    );
    // Point the embed at the seeded file id.
    (note['contentDelta'] as List)[1] = {
      'insert': {'image': '$uri${file['id']}'},
    };

    await tester.pumpWidget(await signedInAppWith(api));
    await openNote(tester, 'Görselli not');

    expect(find.byType(AwNoteImageEmbed), findsOneWidget);
    // No download URL from the fake server → placeholder naming the file.
    expect(find.text('mimari-şema.png'), findsOneWidget);
  });

  testWidgets('a video embed renders a tile with the file name and open icon', (
    tester,
  ) async {
    final api = FakeApi();
    final note = api.seedNote(
      title: 'Videolu not',
      contentDelta: [
        {'insert': 'Kayıt:\n'},
        {
          'insert': {'video': ''},
        },
        {'insert': '\n'},
      ],
    );
    final file = api.seedFile(
      name: 'toplantı-kaydı.mp4',
      targetType: 'note',
      targetId: note['id'] as String,
      mime: 'video/mp4',
    );
    (note['contentDelta'] as List)[1] = {
      'insert': {'video': '$uri${file['id']}'},
    };

    await tester.pumpWidget(await signedInAppWith(api));
    await openNote(tester, 'Videolu not');

    expect(find.byType(AwNoteMediaTile), findsOneWidget);
    expect(find.text('toplantı-kaydı.mp4'), findsOneWidget);
    expect(find.byIcon(Icons.open_in_new), findsOneWidget);
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
    // …and the embed landed in the document, rendering our builder.
    expect(find.byType(AwNoteImageEmbed), findsOneWidget);
    expect(find.text('çekim.png'), findsOneWidget); // placeholder names it
  });

  testWidgets('a non-media pick uploads but explains it will not embed', (
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
    expect(find.byType(AwNoteImageEmbed), findsNothing); // …but not embedded
    expect(
      find.textContaining("doesn't embed inline"),
      findsOneWidget, // the honest snackbar
    );
  });
}
