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

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/sync_overrides.dart';

/// OPH-170 — the global Dosyalar section (BLUEPRINT §12.12, DESIGN F7…F9).
Future<Widget> app(FakeApi api, {List<PickedUpload> picks = const []}) async {
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

Future<void> wideSurface(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> openFiles(WidgetTester tester) async {
  await tester.tap(find.text('Files').last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('folders browse one level at a time with a breadcrumb (F8)', (
    tester,
  ) async {
    await wideSurface(tester);
    final api = FakeApi();
    final docs = api.seedFolder(name: 'Belgeler');
    api.seedFolder(name: 'Faturalar', parentId: docs['id'] as String);
    api.seedFile(
      name: 'kök-dosya.txt',
      targetType: 'workspace',
      targetId: api.workspaceId,
    );
    api.seedFile(
      name: 'içerideki.txt',
      targetType: 'workspace',
      targetId: api.workspaceId,
      folderId: docs['id'] as String,
    );
    await tester.pumpWidget(await app(api));
    await tester.pumpAndSettle();

    await openFiles(tester);
    // Root level: the folder + the folderless file — NOT the foldered one.
    expect(find.text('Belgeler'), findsOneWidget);
    expect(find.text('kök-dosya.txt'), findsOneWidget);
    expect(find.text('içerideki.txt'), findsNothing);

    // Descend: the child folder + the foldered file; breadcrumb grows.
    await tester.tap(find.text('Belgeler'));
    await tester.pumpAndSettle();
    expect(find.text('Faturalar'), findsOneWidget);
    expect(find.text('içerideki.txt'), findsOneWidget);
    expect(find.text('kök-dosya.txt'), findsNothing);

    // Root crumb returns to the top.
    await tester.tap(find.byKey(const Key('crumb-root')));
    await tester.pumpAndSettle();
    expect(find.text('kök-dosya.txt'), findsOneWidget);
  });

  testWidgets('creating a folder and uploading into the current level', (
    tester,
  ) async {
    await wideSurface(tester);
    final api = FakeApi();
    await tester.pumpWidget(
      await app(
        api,
        picks: [
          PickedUpload.fromBytes(
            name: 'rapor.pdf',
            bytes: Uint8List.fromList(List.filled(32, 1)),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await openFiles(tester);

    // New folder via the prompt.
    await tester.tap(find.byKey(const Key('files-new-folder')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('folder-name-field')),
      'Yeni Klasör',
    );
    await tester.tap(find.byKey(const Key('folder-name-save')));
    await tester.pumpAndSettle();
    expect(find.text('Yeni Klasör'), findsOneWidget);
    expect(api.folders.single['name'], 'Yeni Klasör'); // pushed offline-first

    // Enter it and upload — the file lands IN the folder.
    await tester.tap(find.text('Yeni Klasör'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('files-upload')));
    await tester.pumpAndSettle();
    expect(api.files.single['name'], 'rapor.pdf');
    expect(api.files.single['folderId'], api.folders.single['id']);
    expect(find.text('rapor.pdf'), findsOneWidget);
  });

  testWidgets('deleting a folder names the blast radius and clears the level '
      '(F9)', (tester) async {
    await wideSurface(tester);
    final api = FakeApi();
    final folder = api.seedFolder(name: 'Silinecek');
    api.seedFile(
      name: 'gidecek.txt',
      targetType: 'workspace',
      targetId: api.workspaceId,
      folderId: folder['id'] as String,
    );
    await tester.pumpWidget(await app(api));
    await tester.pumpAndSettle();
    await openFiles(tester);

    await tester.tap(find.byKey(Key('folder-menu-${folder['id']}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    // The confirm counts what dies: 1 folder, 1 file.
    expect(find.textContaining('1 folder'), findsOneWidget);
    await tester.tap(find.byKey(const Key('folder-delete-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('Silinecek'), findsNothing);
    expect(api.folders, isEmpty); // the pushed root delete reached the server
  });

  testWidgets('Kaynaklar lists attached files with source badges and '
      'navigates to the owner (F7)', (tester) async {
    await wideSurface(tester);
    final api = FakeApi();
    final task = api.seedTask(
      title: 'Ekli görev',
      dueAt: DateTime.now()
          .add(const Duration(days: 2))
          .toUtc()
          .toIso8601String(),
    );
    api.seedFile(
      name: 'görev-eki.png',
      mime: 'image/png',
      targetType: 'task',
      targetId: task['id'] as String,
    );
    await tester.pumpWidget(await app(api));
    await tester.pumpAndSettle();
    await openFiles(tester);

    await tester.tap(find.text('Sources'));
    await tester.pumpAndSettle();
    expect(find.text('görev-eki.png'), findsOneWidget);
    expect(find.textContaining('Ekli görev'), findsOneWidget); // the badge

    // Go to source opens the owning task's detail.
    await tester.tap(find.text('görev-eki.png'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Go to source'));
    await tester.pumpAndSettle();
    expect(find.text('Task'), findsWidgets); // detail app bar
    expect(find.text('Ekli görev'), findsOneWidget);
  });
}
