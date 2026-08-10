import 'dart:convert';

import 'package:flutter/gestures.dart' show kDoubleTapMinTime;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/files/providers.dart';
import 'package:alliswell/src/features/files/ui/image_viewer.dart';
import 'package:alliswell/src/theme/theme.dart';

/// OPH-245 — the one image viewer, at component level.
///
/// These can assert on a REALLY rendered image because of the
/// [networkImageProvider] seam: `flutter_test`'s HTTP mock answers every
/// request with zero bytes, so before the seam every image in the app fell
/// straight into `errorBuilder` and "double-tap zooms" could only ever be
/// tested against a failure page.
void main() {
  // A 1×1 red PNG. Real bytes, so the decoder actually produces a frame.
  final onePixelPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ'
    'AAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
  );

  FileAttachment fileNamed(String id, String name) => FileAttachment(
    id: id,
    workspaceId: 'w1',
    targetType: 'task',
    targetId: 't1',
    name: name,
    mime: 'image/png',
    sizeBytes: 1024,
  );

  Widget host({
    required List<String> ids,
    int initialIndex = 0,
    Map<String, FileUrlResult>? urls,
    Map<String, FileAttachment?>? files,
    bool storageConfigured = true,
    bool brokenBytes = false,
  }) {
    return ProviderScope(
      overrides: [
        networkImageProvider.overrideWithValue(
          (url) => MemoryImage(
            // Three junk bytes are not a PNG: the codec throws and the
            // widget's errorBuilder is the honest path under test.
            brokenBytes ? Uint8List.fromList([1, 2, 3]) : onePixelPng,
          ),
        ),
        fileUrlResultProvider.overrideWith(
          (ref, String id) async =>
              urls?[id] ?? (url: 'https://cdn.test/$id.png', errorCode: null),
        ),
        fileByIdProvider.overrideWith(
          (ref, String id) async =>
              files != null ? files[id] : fileNamed(id, '$id.png'),
        ),
        storageStatusProvider.overrideWith(
          (ref) async => StorageStatus(
            configured: storageConfigured,
            maxUploadBytes: 1 << 20,
            presignTtlSec: 900,
          ),
        ),
      ],
      child: MaterialApp(
        theme: buildAwTheme(Brightness.light),
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => TextButton(
              key: const Key('open-viewer'),
              onPressed: () => showAwImageViewer(
                context,
                fileIds: ids,
                initialIndex: initialIndex,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> open(WidgetTester tester, Widget app) async {
    await tester.pumpWidget(app);
    await tester.tap(find.byKey(const Key('open-viewer')));
    await tester.pumpAndSettle();
  }

  double scaleOf(WidgetTester tester) => tester
      .widget<InteractiveViewer>(find.byType(InteractiveViewer).first)
      .transformationController!
      .value
      .getMaxScaleOnAxis();

  Matrix4 matrixOf(WidgetTester tester) => tester
      .widget<InteractiveViewer>(find.byType(InteractiveViewer).first)
      .transformationController!
      .value;

  group('zoom', () {
    testWidgets('double-tap zooms about the TAPPED point, not the centre', (
      tester,
    ) async {
      await open(tester, host(ids: ['a']));
      expect(scaleOf(tester), 1.0);

      // Deliberately off-centre: a viewer that zooms to the middle whatever you
      // tap passes a scale-only assertion and still feels wrong.
      final page = tester.getRect(find.byType(InteractiveViewer).first);
      final tapAt = page.topLeft + const Offset(60, 90);
      await tester.tapAt(tapAt);
      await tester.pump(kDoubleTapMinTime);
      await tester.tapAt(tapAt);
      await tester.pumpAndSettle();

      expect(scaleOf(tester), closeTo(kAwViewerDoubleTapScale, 0.001));
      // T(p)·S·T(-p) leaves p exactly where the finger was.
      final local = tapAt - page.topLeft;
      final m = matrixOf(tester);
      expect(
        m.entry(0, 3),
        closeTo(local.dx * (1 - kAwViewerDoubleTapScale), 0.5),
        reason: 'x translation must anchor the tapped point',
      );
      expect(
        m.entry(1, 3),
        closeTo(local.dy * (1 - kAwViewerDoubleTapScale), 0.5),
        reason: 'y translation must anchor the tapped point',
      );
    });

    testWidgets('a second double-tap returns to 1×', (tester) async {
      await open(tester, host(ids: ['a']));
      final centre = tester.getCenter(find.byType(InteractiveViewer).first);
      for (var i = 0; i < 2; i++) {
        await tester.tapAt(centre);
        await tester.pump(kDoubleTapMinTime);
        await tester.tapAt(centre);
        await tester.pumpAndSettle();
      }
      expect(scaleOf(tester), closeTo(1.0, 0.001));
    });

    testWidgets('zoomed in, the pager stops scrolling so a drag PANS', (
      tester,
    ) async {
      await open(tester, host(ids: ['a', 'b', 'c']));
      expect(
        tester.widget<PageView>(find.byType(PageView)).physics,
        isA<PageScrollPhysics>(),
      );

      final centre = tester.getCenter(find.byType(InteractiveViewer).first);
      await tester.tapAt(centre);
      await tester.pump(kDoubleTapMinTime);
      await tester.tapAt(centre);
      await tester.pumpAndSettle();

      expect(
        tester.widget<PageView>(find.byType(PageView)).physics,
        isA<NeverScrollableScrollPhysics>(),
      );
    });
  });

  group('the gallery', () {
    testWidgets('the counter tracks the page and the bar names the file', (
      tester,
    ) async {
      await open(tester, host(ids: ['a', 'b', 'c', 'd'], initialIndex: 1));
      expect(find.text('2 / 4'), findsOneWidget);
      expect(find.text('b.png'), findsOneWidget);

      await tester.drag(find.byType(PageView), const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(find.text('3 / 4'), findsOneWidget);
      expect(find.text('c.png'), findsOneWidget);
    });

    testWidgets('a single image has no counter and cannot be paged', (
      tester,
    ) async {
      await open(tester, host(ids: ['a']));
      expect(find.text('1 / 1'), findsNothing);
      expect(find.textContaining(' / '), findsNothing);
      expect(
        tester.widget<PageView>(find.byType(PageView)).physics,
        isA<PageScrollPhysics>(),
      );
      await tester.drag(find.byType(PageView), const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(find.text('a.png'), findsOneWidget);
    });

    testWidgets('arrow keys page and Escape closes', (tester) async {
      await open(tester, host(ids: ['a', 'b', 'c']));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(find.text('1 / 3'), findsOneWidget);

      // A fullscreen-dialog route does not pop on Escape by itself.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(AwImageViewer), findsNothing);
    });
  });

  group('failure states a reason (A8)', () {
    testWidgets('offline says the connection, not "could not get a link"', (
      tester,
    ) async {
      await open(
        tester,
        host(ids: ['a'], urls: {'a': (url: null, errorCode: 'NETWORK_ERROR')}),
      );
      expect(
        find.text("Can't reach the server — this image needs a connection."),
        findsOneWidget,
      );
    });

    testWidgets('a deleted file says it is gone', (tester) async {
      await open(
        tester,
        host(ids: ['a'], urls: {'a': (url: null, errorCode: 'FILE_NOT_FOUND')}),
      );
      expect(
        find.text('This file is no longer on the server.'),
        findsOneWidget,
      );
    });

    testWidgets('storage switched off says so, not "not ready"', (
      tester,
    ) async {
      await open(
        tester,
        host(
          ids: ['a'],
          urls: {'a': (url: null, errorCode: null)},
          storageConfigured: false,
        ),
      );
      expect(
        find.text("File storage isn't set up on this server"),
        findsOneWidget,
      );
    });

    testWidgets('no link yet, storage on → not ready', (tester) async {
      await open(
        tester,
        host(ids: ['a'], urls: {'a': (url: null, errorCode: null)}),
      );
      expect(
        find.text('The server has no download link for this file yet.'),
        findsOneWidget,
      );
    });

    testWidgets('a link that mints but will not decode is its own reason', (
      tester,
    ) async {
      await open(tester, host(ids: ['a'], brokenBytes: true));
      expect(
        find.text('The link worked, but the image could not be loaded.'),
        findsOneWidget,
        reason: 'bytes failing is a different fact from having no link',
      );
    });
  });

  testWidgets('no dead buttons: actions wait for the row (§22)', (
    tester,
  ) async {
    await open(tester, host(ids: ['a'], files: {'a': null}));
    // The row settled as "gone": the name is honest and neither action is live.
    expect(find.text('Attachment unavailable'), findsWidgets);
    for (final icon in [Icons.open_in_new, Icons.delete_outline]) {
      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, icon))
            .onPressed,
        isNull,
        reason: 'this action cannot act on a row that is not there',
      );
    }
  });
}
