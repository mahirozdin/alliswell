import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/files/ui/image_viewer.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/sync_overrides.dart';

/// OPH-245 / DESIGN §30 A7 — "one viewer, everywhere".
///
/// The failure this pins down is not a crash, it is a DISAGREEMENT: before
/// this round, tapping an image opened the actions sheet in Dosyalar and the
/// viewer in a project's Files tab, because `FileRowTile` let a caller's
/// `onMore` swallow the tap for every kind. The fix had to give those injected
/// actions their own affordance rather than delete them, so the pair
/// "row opens the viewer" + "⋯ still reaches Move to…" is asserted together.
Future<Widget> signedInAppWith(FakeApi api) async {
  SharedPreferences.setMockInitialValues({});
  final store = InMemorySecretStore();
  await TokenStorage(store).save(fakeSession());
  return ProviderScope(
    retry: awRetry,
    overrides: [
      ...syncTestOverrides(),
      secretStoreProvider.overrideWithValue(store),
      apiClientProvider.overrideWithValue(
        fakeDio(FakeHttpClientAdapter(api.handle)),
      ),
    ],
    child: const AllisWellApp(),
  );
}

Future<void> wideSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Future<void> openFiles(WidgetTester tester) async {
  await tester.tap(find.text('Files').last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a task attachment row opens the viewer, paging its siblings', (
    tester,
  ) async {
    await wideSurface(tester);
    final api = FakeApi();
    final task = api.seedTask(title: 'Ekli görev');
    for (final name in ['bir.png', 'iki.png']) {
      api.seedFile(
        name: name,
        mime: 'image/png',
        targetType: 'task',
        targetId: task['id'] as String,
      );
    }
    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ekli görev'));
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.text('bir.png'),
      find.byType(ListView).last,
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('bir.png'));
    await tester.pumpAndSettle();

    expect(find.byType(AwImageViewer), findsOneWidget);
    // Both images of this target are in the gallery, not just the tapped one.
    expect(find.textContaining(' / 2'), findsOneWidget);
  });

  testWidgets(
    'Dosyalar: the row opens the viewer AND ⋯ still reaches Move to…',
    (tester) async {
      await wideSurface(tester);
      final api = FakeApi();
      final file = api.seedFile(
        name: 'kapak.png',
        mime: 'image/png',
        targetType: 'workspace',
        targetId: 'ws-1',
      );
      await tester.pumpWidget(await signedInAppWith(api));
      await tester.pumpAndSettle();
      await openFiles(tester);

      // The tap follows the KIND — this surface passes onMore, which used to
      // win for images too.
      await tester.tap(find.text('kapak.png'));
      await tester.pumpAndSettle();
      expect(find.byType(AwImageViewer), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      // And nothing this surface injected became unreachable.
      await tester.tap(find.byKey(Key('file-menu-${file['id']}')));
      await tester.pumpAndSettle();
      expect(find.text('Move to…'), findsOneWidget);
    },
  );

  testWidgets('a non-image row still opens the actions sheet', (tester) async {
    await wideSurface(tester);
    final api = FakeApi();
    api.seedFile(
      name: 'sözleşme.pdf',
      mime: 'application/pdf',
      targetType: 'workspace',
      targetId: 'ws-1',
    );
    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();
    await openFiles(tester);

    await tester.tap(find.text('sözleşme.pdf'));
    await tester.pumpAndSettle();
    expect(find.byType(AwImageViewer), findsNothing);
    expect(find.text('Open / Download'), findsOneWidget);
  });
}
