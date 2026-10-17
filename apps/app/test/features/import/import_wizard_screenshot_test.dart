// The import wizard, every step in both themes (OPH-371, DESIGN §37 I6).
//
// Run locally with:
//
//   cd apps/app
//   flutter test --update-goldens --dart-define=screenshots=true \
//       --dart-define=shotLocale=en test/features/import/import_wizard_screenshot_test.dart
//
// and again with shotLocale=tr. Inert without the dart-define: goldens are
// generated output (test/goldens is gitignored), so a plain CI run must not
// compare against pictures that are not in the repository.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/import/data/import_models.dart';
import 'package:alliswell/src/features/import/ui/import_wizard_screen.dart';
import 'package:alliswell/src/i18n/i18n.dart';

import '../../design_screenshots_test.dart' show screenshotLocale;
import '../ee/support/shot.dart';
import 'import_fakes.dart';

const bool _enabled = bool.fromEnvironment('screenshots');

/// Batches for the "importing" shot: the first lands at ~60 %, the second
/// never answers, so the picture holds the progress bar mid-way.
class _HangingApi extends FakeImportApi {
  _HangingApi() : super(preview: (_) => sampleSummary());

  @override
  Future<ImportSummary> run(
    String workspaceId, {
    required ImportSource source,
    required List<ImportFileText> files,
    required bool dryRun,
    required Map<String, Object> options,
  }) {
    calls.add((dryRun: dryRun, options: options, files: files.length));
    if (dryRun) return Future.value(sampleSummary());
    if (calls.where((c) => !c.dryRun).length == 1) {
      return Future.value(batch(tasks: 25, remaining: 17));
    }
    return Completer<ImportSummary>().future;
  }
}

Future<void> _to(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

void main() {
  if (!_enabled) return;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AwI18n.instance.setLocale(screenshotLocale('en'));
  });

  const size = Size(900, 1800);

  for (final brightness in Brightness.values) {
    testWidgets('1 source — ${brightness.name}', (tester) async {
      await eeShoot(
        tester,
        brightness: brightness,
        name: 'import-1-source',
        size: size,
        screen: const ImportWizardScreen(),
        overrides: importOverrides(
          api: FakeImportApi(preview: (_) => sampleSummary()),
        ),
      );
    });

    testWidgets('2 file — ${brightness.name}', (tester) async {
      await eeShoot(
        tester,
        brightness: brightness,
        name: 'import-2-file',
        size: size,
        screen: const ImportWizardScreen(),
        overrides: importOverrides(
          api: FakeImportApi(preview: (_) => sampleSummary()),
        ),
        afterPump: (tester) async {
          await _to(tester, 'import-source-todoist');
          await _to(tester, 'import-pick');
        },
      );
    });

    testWidgets('3 preview — ${brightness.name}', (tester) async {
      await eeShoot(
        tester,
        brightness: brightness,
        name: 'import-3-preview',
        size: size,
        screen: const ImportWizardScreen(),
        overrides: importOverrides(
          api: FakeImportApi(preview: (_) => sampleSummary()),
        ),
        afterPump: (tester) async {
          await _to(tester, 'import-source-todoist');
          await _to(tester, 'import-pick');
          await _to(tester, 'import-preview');
        },
      );
    });

    testWidgets('3b preview TickTick, scrolled — ${brightness.name}', (
      tester,
    ) async {
      await eeShoot(
        tester,
        brightness: brightness,
        name: 'import-3b-preview-ticktick',
        size: size,
        screen: const ImportWizardScreen(),
        overrides: importOverrides(
          api: FakeImportApi(
            preview: (inc) =>
                sampleSummary(includeCompleted: inc, ticktick: true),
          ),
        ),
        afterPump: (tester) async {
          await _to(tester, 'import-source-ticktick');
          await _to(tester, 'import-pick');
          await _to(tester, 'import-preview');
          await tester.drag(
            find.byKey(const Key('import-wizard')),
            const Offset(0, -700),
          );
          await tester.pumpAndSettle();
          // One warning group open, so its examples are in the picture.
          await _to(tester, 'import-warning-IMPORT_RECURRENCE_KEPT_IN_NOTE');
        },
      );
    });

    testWidgets('4 importing — ${brightness.name}', (tester) async {
      await eeShoot(
        tester,
        brightness: brightness,
        name: 'import-4-importing',
        size: size,
        screen: const ImportWizardScreen(),
        overrides: importOverrides(api: _HangingApi()),
        afterPump: (tester) async {
          await _to(tester, 'import-source-todoist');
          await _to(tester, 'import-pick');
          await _to(tester, 'import-preview');
          await _to(tester, 'import-run');
        },
      );
    });

    testWidgets('5 result — ${brightness.name}', (tester) async {
      await eeShoot(
        tester,
        brightness: brightness,
        name: 'import-5-result',
        size: size,
        screen: const ImportWizardScreen(),
        overrides: importOverrides(
          api: FakeImportApi(
            preview: (_) => sampleSummary(),
            batches: [
              batch(tasks: 25, remaining: 17),
              batch(tasks: 16, remaining: 0, errors: 1),
            ],
          ),
        ),
        afterPump: (tester) async {
          await _to(tester, 'import-source-todoist');
          await _to(tester, 'import-pick');
          await _to(tester, 'import-preview');
          await _to(tester, 'import-run');
        },
      );
    });
  }
}
