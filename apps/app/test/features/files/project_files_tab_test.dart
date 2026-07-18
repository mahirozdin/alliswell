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

/// OPH-155 — the project "Files" tab: the aggregated file manager (project ∪
/// task ∪ note files with source badges), filters, sort, uploads targeting
/// the project, and the honest empty/not-configured states.
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

Future<void> openFilesTab(WidgetTester tester, String projectName) async {
  await tester.pumpAndSettle();
  await tester.tap(find.text('Projects').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text(projectName));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Files'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('aggregates project, task and note files with source badges', (
    tester,
  ) async {
    await wideSurface(tester);
    final api = FakeApi();
    final project = api.seedProject(name: 'Depo projesi');
    final projectId = project['id'] as String;
    final task = api.seedTask(title: 'Dosyalı görev');
    task['projectId'] = projectId;
    final note = api.seedNote(title: 'Dosyalı not', projectId: projectId);
    api.seedFile(
      name: 'proje-dosyası.bin',
      targetType: 'project',
      targetId: projectId,
    );
    api.seedFile(
      name: 'görev-dosyası.bin',
      targetType: 'task',
      targetId: task['id'] as String,
    );
    api.seedFile(
      name: 'not-dosyası.bin',
      targetType: 'note',
      targetId: note['id'] as String,
    );

    await tester.pumpWidget(await signedInAppWith(api));
    await openFilesTab(tester, 'Depo projesi');

    expect(find.byType(FileRowTile), findsNWidgets(3));
    expect(find.text('proje-dosyası.bin'), findsOneWidget);
    expect(find.text('görev-dosyası.bin'), findsOneWidget);
    expect(find.text('not-dosyası.bin'), findsOneWidget);
    // Source badges name their origin (F4).
    expect(find.text('Dosyalı görev'), findsOneWidget);
    expect(find.text('Dosyalı not'), findsOneWidget);

    // The source filter narrows the list.
    await tester.tap(find.widgetWithText(FilterChip, 'Tasks'));
    await tester.pumpAndSettle();
    expect(find.byType(FileRowTile), findsOneWidget);
    expect(find.text('görev-dosyası.bin'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, 'All'));
    await tester.pumpAndSettle();
    expect(find.byType(FileRowTile), findsNWidgets(3));
  });

  testWidgets('sort by name reorders the rows', (tester) async {
    await wideSurface(tester);
    final api = FakeApi();
    final project = api.seedProject(name: 'Sıralı proje');
    final projectId = project['id'] as String;
    api.seedFile(name: 'b-son.bin', targetType: 'project', targetId: projectId);
    api.seedFile(
      name: 'a-önce.bin',
      targetType: 'project',
      targetId: projectId,
    );

    await tester.pumpWidget(await signedInAppWith(api));
    await openFilesTab(tester, 'Sıralı proje');

    await tester.tap(find.byIcon(Icons.sort));
    await tester.pumpAndSettle();
    await tester.tap(find.text('By name'));
    await tester.pumpAndSettle();

    final rows = tester
        .widgetList<FileRowTile>(find.byType(FileRowTile))
        .map((w) => w.file.name)
        .toList();
    expect(rows, ['a-önce.bin', 'b-son.bin']);
  });

  testWidgets('uploading from the tab targets the PROJECT', (tester) async {
    await wideSurface(tester);
    final api = FakeApi();
    api.seedProject(name: 'Yükleme projesi');

    await tester.pumpWidget(
      await signedInAppWith(
        api,
        picks: [
          PickedUpload.fromBytes(
            name: 'brief.pdf',
            bytes: Uint8List.fromList(List.filled(32, 9)),
          ),
        ],
      ),
    );
    await openFilesTab(tester, 'Yükleme projesi');

    await tester.tap(find.byKey(const Key('project-add-file')));
    await tester.pumpAndSettle();

    expect(api.files, hasLength(1));
    expect(api.files.single['targetType'], 'project');
    expect(find.text('brief.pdf'), findsOneWidget);
    expect(find.byType(FileRowTile), findsOneWidget);
  });

  testWidgets('an empty (but configured) project says so', (tester) async {
    await wideSurface(tester);
    final api = FakeApi();
    api.seedProject(name: 'Boş proje');

    await tester.pumpWidget(await signedInAppWith(api));
    await openFilesTab(tester, 'Boş proje');
    expect(find.text('No files yet'), findsOneWidget);
  });

  testWidgets('a storage-less server gets the explainer, no dead button', (
    tester,
  ) async {
    await wideSurface(tester);
    final off = FakeApi()..storageConfigured = false;
    off.seedProject(name: 'Depsiz proje');

    await tester.pumpWidget(await signedInAppWith(off));
    await openFilesTab(tester, 'Depsiz proje');
    expect(
      find.text("File storage isn't set up on this server"),
      findsOneWidget,
    );
    final addButton = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('Add file'),
        matching: find.byType(OutlinedButton),
      ),
    );
    expect(addButton.onPressed, isNull); // disabled, honestly
  });
}
