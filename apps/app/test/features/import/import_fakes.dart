import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'package:alliswell/src/features/import/data/import_api.dart';
import 'package:alliswell/src/features/import/data/import_file_reader.dart';
import 'package:alliswell/src/features/import/data/import_models.dart';
import 'package:alliswell/src/features/import/providers.dart';
import 'package:alliswell/src/features/import/ui/import_wizard_screen.dart';
import 'package:alliswell/src/features/workspaces/workspaces.dart';
import 'package:alliswell/src/theme/theme.dart';

/// Shared fakes for the import wizard's tests and shots (OPH-371).

class FakeImportApi implements AppImportApi {
  FakeImportApi({required this.preview, this.batches = const [], this.error});

  ImportSummary Function(bool includeCompleted) preview;
  List<ImportSummary> batches;
  Object? error;
  final calls = <({bool dryRun, Map<String, Object> options, int files})>[];

  @override
  Future<ImportSummary> run(
    String workspaceId, {
    required ImportSource source,
    required List<ImportFileText> files,
    required bool dryRun,
    required Map<String, Object> options,
  }) async {
    calls.add((dryRun: dryRun, options: options, files: files.length));
    if (error != null) throw error!;
    if (dryRun) return preview(options['includeCompleted'] == true);
    final index = calls.where((c) => !c.dryRun).length - 1;
    return batches[index.clamp(0, batches.length - 1)];
  }
}

class FakeImportPicker implements ImportFilePicker {
  FakeImportPicker(this.files);
  final List<PickedImportFile> files;

  @override
  Future<List<PickedImportFile>?> pick({required bool multiple}) async => files;
}

PickedImportFile csvFile(String name, String content, {int padding = 1200}) {
  final bytes = Uint8List.fromList(utf8.encode(content));
  return PickedImportFile(
    name: name,
    // A real export is bigger than this two-line stand-in; the size is what
    // the file list shows.
    size: bytes.length + padding,
    read: () async => bytes,
  );
}

ImportSummary sampleSummary({
  bool includeCompleted = false,
  bool google = true,
  int already = 0,
  bool ticktick = false,
}) => ImportSummary(
  total: includeCompleted ? 44 : 42,
  projectsNew: 2,
  projectsExisting: 1,
  tagsNew: 5,
  tagsExisting: 2,
  tasks: includeCompleted ? 36 : 34,
  series: 6,
  checklistItems: 18,
  notes: 2,
  completedIncluded: includeCompleted ? 2 : 0,
  completedSkipped: includeCompleted ? 0 : 2,
  alreadyImported: already,
  googleConnected: google,
  googleTasks: 34,
  googleUndated: 9,
  priority: ticktick
      ? const [
          (from: 'high', to: 'high'),
          (from: 'medium', to: 'medium'),
          (from: 'low', to: 'low'),
          (from: 'none', to: 'none'),
        ]
      : const [
          (from: 'p1', to: 'high'),
          (from: 'p2', to: 'medium'),
          (from: 'p3', to: 'low'),
          (from: 'p4', to: 'none'),
        ],
  warnings: const [
    ImportWarningGroup(
      code: 'IMPORT_RECURRENCE_KEPT_IN_NOTE',
      count: 2,
      examples: [
        ImportWarningExample(
          file: 'Ev İşleri [2203306142].csv',
          row: 13,
          title: 'Faturaları öde',
          value: 'every 2nd weekday at 9am',
        ),
      ],
    ),
    ImportWarningGroup(code: 'IMPORT_DEEP_SUBTASK_FLATTENED', count: 3),
    ImportWarningGroup(code: 'IMPORT_ATTACHMENT_LINKED', count: 1),
  ],
);

ImportSummary batch({
  required int tasks,
  required int remaining,
  int errors = 0,
}) => ImportSummary(
  total: 0,
  created: ImportCreated(
    tasks: tasks,
    checklistItems: tasks ~/ 2,
    series: remaining == 0 ? 0 : 6,
    notes: remaining == 0 ? 0 : 2,
    projects: remaining == 0 ? 0 : 2,
    tags: remaining == 0 ? 0 : 5,
  ),
  remaining: remaining,
  errors: [
    for (var i = 0; i < errors; i += 1)
      ImportItemError(
        code: 'TASK_SERIES_TOO_DENSE',
        message: 'too dense',
        file: 'Ev İşleri [2203306142].csv',
        row: 40 + i,
      ),
  ],
);

List<Override> importOverrides({
  required FakeImportApi api,
  FakeImportPicker? picker,
  void Function()? onSync,
}) => [
  appImportApiProvider.overrideWithValue(api),
  importFilePickerProvider.overrideWithValue(
    picker ??
        FakeImportPicker([
          csvFile('Inbox [2203306141].csv', 'TYPE,CONTENT\ntask,Süt\n'),
          csvFile('Ev İşleri [2203306142].csv', 'TYPE,CONTENT\ntask,Çim\n'),
        ]),
  ),
  activeWorkspaceIdProvider.overrideWith((ref) async => 'ws-import'),
  importSyncProvider.overrideWithValue(() async => onSync?.call()),
];

Widget wizardApp(
  List<Override> overrides, {
  Brightness brightness = Brightness.light,
}) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(
    theme: buildAwTheme(brightness),
    home: const ImportWizardScreen(),
  ),
);
