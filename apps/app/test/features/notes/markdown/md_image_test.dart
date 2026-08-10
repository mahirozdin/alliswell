import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/files/providers.dart';
import 'package:alliswell/src/features/notes/markdown/aw_markdown.dart';
import 'package:alliswell/src/features/notes/markdown/md_parse.dart';
import 'package:alliswell/src/theme/theme.dart';

/// OPH-247 — images in a document (DESIGN §29 D6, §30 A7/A11).
///
/// `flutter_test`'s HTTP mock answers every request with zero bytes, so a test
/// that just pumps a `NetworkImage` can only ever assert the failure path
/// (OPH-245 found this). The `networkImageProvider` seam is why a real image
/// can be drawn here at all.
void main() {
  // A 1×1 transparent PNG — the smallest thing that decodes.
  final onePixelPng = Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
    0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
    0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
    0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
    0x42, 0x60, 0x82,
  ]);

  final requested = <String>[];

  Widget host(String markdown) => ProviderScope(
    overrides: [
      networkImageProvider.overrideWithValue((url) {
        requested.add(url);
        return MemoryImage(onePixelPng);
      }),
    ],
    child: MaterialApp(
      theme: buildAwTheme(Brightness.light),
      home: Scaffold(
        body: AwMarkdown(document: parseMarkdown(markdown), shrinkWrap: true),
      ),
    ),
  );

  setUp(requested.clear);

  testWidgets('an absolute url is drawn, not described', (tester) async {
    await tester.pumpWidget(host('![kedi](https://example.dev/kedi.png)'));
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
    expect(requested, ['https://example.dev/kedi.png']);
  });

  testWidgets('the alt text becomes the semantic label', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(host('![bir kedi](https://example.dev/k.png)'));
    await tester.pump();

    expect(find.bySemanticsLabel('bir kedi'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('a relative path says WHY it cannot be drawn', (tester) async {
    // Not a broken image: the file may be perfectly fine, we just do not know
    // which folder it is relative to until OPH-251 gives documents a base.
    await tester.pumpWidget(host('![yerel](./resim.png)'));
    await tester.pump();

    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.link_off_outlined), findsOneWidget);
    expect(requested, isEmpty, reason: 'nothing should be fetched');
  });

  testWidgets('a data: image is not fetched either', (tester) async {
    await tester.pumpWidget(
      host('![x](data:image/svg+xml;base64,PHN2Zz48L3N2Zz4=)'),
    );
    await tester.pump();

    expect(requested, isEmpty);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('bytes that will not decode fall back where they stand', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          networkImageProvider.overrideWithValue(
            (_) => MemoryImage(Uint8List.fromList([1, 2, 3])),
          ),
        ],
        child: MaterialApp(
          theme: buildAwTheme(Brightness.light),
          home: Scaffold(
            body: AwMarkdown(
              document: parseMarkdown('![bozuk](https://example.dev/x.png)'),
              shrinkWrap: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // The exception belongs to the image codec, not to us; what matters is
    // that the reader is left with a labelled placeholder rather than a gap.
    tester.takeException();
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
  });

  testWidgets('tapping opens the gallery in document order', (tester) async {
    final tapped = <String>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          networkImageProvider.overrideWithValue(
            (_) => MemoryImage(onePixelPng),
          ),
        ],
        child: MaterialApp(
          theme: buildAwTheme(Brightness.light),
          home: Scaffold(
            body: AwMarkdown(
              document: parseMarkdown(
                '![bir](https://e.dev/1.png)\n\n'
                '![iki](https://e.dev/2.png)\n\n'
                '![üç](https://e.dev/3.png)',
              ),
              shrinkWrap: true,
              onTapImage: tapped.add,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byType(Image).at(1));
    expect(tapped, ['https://e.dev/2.png']);
  });
}
