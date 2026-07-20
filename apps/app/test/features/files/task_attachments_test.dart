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
import 'package:alliswell/src/features/files/ui/file_widgets.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/sync_overrides.dart';

/// OPH-154 — the task detail "Attachments" section, end to end over the fake
/// server: seeded files render from the replica, uploads run the real
/// controller (init → fake PUT → complete → pull), delete confirms honestly,
/// and a storage-less server degrades to one quiet explainer row.
Future<void> wideSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

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

final soon = DateTime.now()
    .add(const Duration(days: 3))
    .toUtc()
    .toIso8601String();

Future<void> openTaskDetail(WidgetTester tester, String title) async {
  await tester.pumpAndSettle();
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
}

Future<void> scrollToAttachments(WidgetTester tester) async {
  await tester.dragUntilVisible(
    find.text('Attachments'),
    find.byType(ListView).last,
    const Offset(0, -200),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('seeded attachments render with name, size and date', (
    tester,
  ) async {
    await wideSurface(tester);
    final api = FakeApi();
    final task = api.seedTask(title: 'Ekli iş', dueAt: soon);
    api.seedFile(
      name: 'Sunum taslağı.pdf',
      targetType: 'task',
      targetId: task['id'] as String,
      mime: 'application/pdf',
      sizeBytes: 3 * 1024 * 1024,
    );

    await tester.pumpWidget(await signedInAppWith(api));
    await openTaskDetail(tester, 'Ekli iş');
    await scrollToAttachments(tester);

    expect(find.text('Sunum taslağı.pdf'), findsOneWidget);
    expect(find.textContaining('3.0 MB'), findsOneWidget);
    expect(find.byType(FileRowTile), findsOneWidget);
  });

  testWidgets('picking a file uploads it and the synced row appears', (
    tester,
  ) async {
    await wideSurface(tester);
    final api = FakeApi();
    api.seedTask(title: 'Yüklemeli iş', dueAt: soon);

    await tester.pumpWidget(
      await signedInAppWith(
        api,
        picks: [
          PickedUpload.fromBytes(
            name: 'foto.png',
            bytes: Uint8List.fromList(List.filled(64, 1)),
          ),
        ],
      ),
    );
    await openTaskDetail(tester, 'Yüklemeli iş');
    await scrollToAttachments(tester);

    await tester.tap(find.text('Add file'));
    await tester.pumpAndSettle();

    // The full handshake ran against the fake server…
    expect(
      api.requests.where((r) => r.contains('/files')),
      isNotEmpty,
      reason: 'init+complete must reach the API',
    );
    expect(api.files, hasLength(1));
    expect(api.files.single['name'], 'foto.png');
    expect(api.files.single['mime'], 'image/png'); // mimeForName filled the gap
    // …and the pulled replica row rendered (the upload row is gone).
    expect(find.byType(FileRowTile), findsOneWidget);
    expect(find.text('foto.png'), findsOneWidget);
    expect(find.byType(UploadRowTile), findsNothing);
  });

  testWidgets('deleting via the action sheet confirms with the filename', (
    tester,
  ) async {
    await wideSurface(tester);
    final api = FakeApi();
    final task = api.seedTask(title: 'Silmeli iş', dueAt: soon);
    api.seedFile(
      name: 'eski-plan.txt',
      targetType: 'task',
      targetId: task['id'] as String,
      mime: 'text/plain',
    );

    await tester.pumpWidget(await signedInAppWith(api));
    await openTaskDetail(tester, 'Silmeli iş');
    await scrollToAttachments(tester);

    await tester.tap(find.text('eski-plan.txt'));
    await tester.pumpAndSettle();
    expect(find.text('Open / Download'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.textContaining('eski-plan.txt'), findsWidgets); // named confirm

    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(api.files, isEmpty);
    expect(find.byType(FileRowTile), findsNothing); // tombstone pulled
  });

  testWidgets('storage off → one quiet explainer, no dead add button', (
    tester,
  ) async {
    await wideSurface(tester);
    final api = FakeApi()..storageConfigured = false;
    api.seedTask(title: 'Depsiz iş', dueAt: soon);

    await tester.pumpWidget(await signedInAppWith(api));
    await openTaskDetail(tester, 'Depsiz iş');
    await scrollToAttachments(tester);

    expect(
      find.text("File storage isn't set up on this server"),
      findsOneWidget,
    );
    expect(find.text('Add file'), findsNothing);
  });

  testWidgets('create sheet picks files and uploads them to the new task '
      '(OPH-166)', (tester) async {
    await wideSurface(tester);
    final api = FakeApi();
    await tester.pumpWidget(
      await signedInAppWith(
        api,
        picks: [
          PickedUpload.fromBytes(
            name: 'plan.pdf',
            bytes: Uint8List.fromList(List.filled(96, 7)),
          ),
          PickedUpload.fromBytes(
            name: 'silinecek.txt',
            bytes: Uint8List.fromList(List.filled(8, 2)),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('task-sheet-title')),
      'Ekli doğan iş',
    );

    // Pick: both selections appear as removable pending rows — no upload yet
    // (there is no task to own one).
    await tester.tap(find.byKey(const Key('task-sheet-attach')));
    await tester.pumpAndSettle();
    expect(find.text('plan.pdf'), findsOneWidget);
    expect(find.text('silinecek.txt'), findsOneWidget);
    expect(api.files, isEmpty);

    // Changed my mind about one.
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('pending-file-1')),
        matching: find.byIcon(Icons.close),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('silinecek.txt'), findsNothing);

    await tester.tap(find.byKey(const Key('task-sheet-create')));
    await tester.pumpAndSettle();

    // The kept file uploaded against the NEW task.
    expect(api.files, hasLength(1));
    expect(api.files.single['name'], 'plan.pdf');
    expect(api.files.single['targetType'], 'task');
    expect(api.files.single['targetId'], api.tasks.single['id']);
  });
}
