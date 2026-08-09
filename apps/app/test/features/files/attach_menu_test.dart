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
import '../../support/fake_file_picker.dart';
import '../../support/sync_overrides.dart';

/// OPH-244 — the attach menu itself: which named way the user chose, and what
/// the app then asked the OS for.
///
/// The round-17 bug was invisible precisely because nothing asserted INTENT —
/// the old tests only checked that some file came back. These check the source.
Future<Widget> _app(
  FakeApi api, {
  required RecordingFilePicker picker,
  List<AttachSource>? sources,
}) async {
  SharedPreferences.setMockInitialValues({});
  final store = InMemorySecretStore();
  await TokenStorage(store).save(fakeSession());
  return ProviderScope(
    retry: awRetry,
    overrides: [
      ...syncTestOverrides(filePicker: picker.call),
      if (sources != null) attachSourcesProvider.overrideWithValue(sources),
      secretStoreProvider.overrideWithValue(store),
      apiClientProvider.overrideWithValue(
        fakeDio(FakeHttpClientAdapter(api.handle)),
      ),
    ],
    child: const AllisWellApp(),
  );
}

final _soon = DateTime.now()
    .add(const Duration(days: 3))
    .toUtc()
    .toIso8601String();

Future<void> _openTaskDetail(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.tap(find.text('Ek deneyi'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => TestWidgetsFlutterBinding.ensureInitialized());

  Future<void> wide(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  testWidgets('the menu names three ways in, and Photos asks for Photos', (
    tester,
  ) async {
    await wide(tester);
    final api = FakeApi()..seedTask(title: 'Ek deneyi', dueAt: _soon);
    final picker = RecordingFilePicker(picks: [filePick('foto.png')]);

    await tester.pumpWidget(await _app(api, picker: picker));
    await _openTaskDetail(tester);

    await tester.tap(find.byKey(const Key('attach-button')));
    await tester.pumpAndSettle();

    // A1: three named ways, each saying what it opens.
    expect(find.byKey(const Key('attach-source-photos')), findsOneWidget);
    expect(find.byKey(const Key('attach-source-camera')), findsOneWidget);
    expect(find.byKey(const Key('attach-source-files')), findsOneWidget);

    await tester.tap(find.byKey(const Key('attach-source-photos')));
    await tester.pumpAndSettle();

    // The assertion that matters: the app asked for the PHOTO LIBRARY. Before
    // OPH-244 every path asked for `anyFile`, which is the document browser.
    expect(picker.calls, [AttachSource.photoLibrary]);
    expect(api.files.single['name'], 'foto.png');
  });

  testWidgets('one source means no sheet — a one-item menu is a dead tap', (
    tester,
  ) async {
    await wide(tester);
    final api = FakeApi()..seedTask(title: 'Ek deneyi', dueAt: _soon);
    final picker = RecordingFilePicker(picks: [filePick('rapor.pdf')]);

    await tester.pumpWidget(
      // Web/desktop: only the document browser exists.
      await _app(api, picker: picker, sources: const [AttachSource.anyFile]),
    );
    await _openTaskDetail(tester);

    await tester.tap(find.byKey(const Key('attach-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('attach-source-files')), findsNothing);
    expect(picker.calls, [AttachSource.anyFile]);
  });

  testWidgets('a picker that blows up says so instead of vanishing (A8)', (
    tester,
  ) async {
    await wide(tester);
    final api = FakeApi()..seedTask(title: 'Ek deneyi', dueAt: _soon);
    final picker = RecordingFilePicker(throws: true);

    await tester.pumpWidget(
      await _app(api, picker: picker, sources: const [AttachSource.anyFile]),
    );
    await _openTaskDetail(tester);

    // Nothing anywhere used to catch a PlatformException: it escaped
    // pickAndUpload as an unhandled async error and the tap simply died.
    await tester.tap(find.byKey(const Key('attach-button')));
    await tester.pumpAndSettle();

    expect(picker.calls, [AttachSource.anyFile]);
    expect(find.text('Could not open the picker'), findsOneWidget);
    expect(api.files, isEmpty);
  });

  testWidgets('the description area carries its own attach button (A4)', (
    tester,
  ) async {
    await wide(tester);
    final api = FakeApi()..seedTask(title: 'Ek deneyi', dueAt: _soon);
    final picker = RecordingFilePicker(picks: [filePick('kroki.png')]);

    await tester.pumpWidget(await _app(api, picker: picker));
    await _openTaskDetail(tester);

    final button = find.byKey(const Key('task-description-attach'));
    expect(
      button,
      findsOneWidget,
      reason:
          'round 17 #2: this is where the owner looked for it first, because '
          'it is where notes put it',
    );

    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('attach-source-photos')));
    await tester.pumpAndSettle();

    expect(picker.calls, [AttachSource.photoLibrary]);
    // One destination, two doors: it lands in the task's own attachment list.
    expect(api.files.single['name'], 'kroki.png');
  });
}
