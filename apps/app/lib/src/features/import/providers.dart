import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/persisted_prefs.dart';
import '../../i18n/i18n.dart';
import '../../sync/providers.dart';
import '../auth/providers.dart';
import '../workspaces/workspaces.dart';
import 'data/import_api.dart';
import 'data/import_file_reader.dart';
import 'data/import_models.dart';

/// The import wizard's state machine (OPH-371, DESIGN §37).
///
///   source → file → preview → importing → done
///
/// The preview IS the import with `dryRun: true` (§37 I1): the counts the
/// person agrees to are the counts the server computed from the same request.
/// The import then runs in batches until the server says nothing remains.

final appImportApiProvider = Provider<AppImportApi>(
  (ref) => AppImportApi(ref.watch(apiClientProvider)),
);

/// "Pull now": what the import wrote reaches this device through the
/// ordinary sync — a seam so a test can see it asked.
final importSyncProvider = Provider<Future<void> Function()>(
  (ref) =>
      () async => ref.read(syncEngineProvider)?.syncNow(),
);

enum ImportStep { source, file, preview, importing, done }

@immutable
class ImportWizardState {
  const ImportWizardState({
    this.step = ImportStep.source,
    this.source,
    this.files = const [],
    this.includeCompleted = false,
    this.busy = false,
    this.error,
    this.preview,
    this.processed = 0,
    this.total = 0,
    this.report,
  });

  final ImportStep step;
  final ImportSource? source;
  final List<ImportFileText> files;
  final bool includeCompleted;

  /// A request (or a file read) is in flight on the current step.
  final bool busy;

  /// The last failure on the current step, shown inline (never a blank page).
  final Object? error;
  final ImportSummary? preview;
  final int processed;
  final int total;
  final ImportReport? report;

  ImportWizardState copyWith({
    ImportStep? step,
    ImportSource? source,
    List<ImportFileText>? files,
    bool? includeCompleted,
    bool? busy,
    Object? error,
    bool clearError = false,
    ImportSummary? preview,
    bool clearPreview = false,
    int? processed,
    int? total,
    ImportReport? report,
  }) => ImportWizardState(
    step: step ?? this.step,
    source: source ?? this.source,
    files: files ?? this.files,
    includeCompleted: includeCompleted ?? this.includeCompleted,
    busy: busy ?? this.busy,
    error: clearError ? null : (error ?? this.error),
    preview: clearPreview ? null : (preview ?? this.preview),
    processed: processed ?? this.processed,
    total: total ?? this.total,
    report: report ?? this.report,
  );
}

class ImportWizardController extends Notifier<ImportWizardState> {
  bool _disposed = false;

  @override
  ImportWizardState build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    return const ImportWizardState();
  }

  void _set(ImportWizardState next) {
    if (!_disposed) state = next;
  }

  void chooseSource(ImportSource source) {
    _set(
      ImportWizardState(step: ImportStep.file, source: source, files: const []),
    );
  }

  /// One step back; from the file step that is the source choice again.
  void back() {
    switch (state.step) {
      case ImportStep.file:
        _set(const ImportWizardState());
      case ImportStep.preview:
        _set(
          state.copyWith(
            step: ImportStep.file,
            clearPreview: true,
            clearError: true,
          ),
        );
      case ImportStep.source:
      case ImportStep.importing:
      case ImportStep.done:
        break;
    }
  }

  Future<void> pickFiles() async {
    final source = state.source;
    if (source == null) return;
    _set(state.copyWith(busy: true, clearError: true));
    try {
      final picked = await ref
          .read(importFilePickerProvider)
          .pick(multiple: source == ImportSource.todoist);
      if (picked == null) {
        _set(state.copyWith(busy: false));
        return;
      }
      final files = await readImportFiles(picked);
      _set(state.copyWith(busy: false, files: files));
    } on Object catch (e) {
      _set(state.copyWith(busy: false, error: e));
    }
  }

  /// Files chosen some other way (tests, a future share target).
  void setFiles(List<ImportFileText> files) {
    _set(state.copyWith(files: files, clearError: true));
  }

  Map<String, Object> _options({int? maxItems}) => {
    'includeCompleted': state.includeCompleted,
    'defaultTaskTime': ref.read(defaultTaskTimeProvider),
    'locale': AwI18n.instance.locale.languageCode == 'tr' ? 'tr' : 'en',
    'maxItems': ?maxItems,
    // No timezone: the server uses the profile's (LESSONS calendar) — a
    // device offset is not an IANA zone.
  };

  Future<String> _workspaceId() async {
    final id = await ref.read(activeWorkspaceIdProvider.future);
    if (id == null) throw StateError('no workspace');
    return id;
  }

  Future<void> loadPreview() async {
    final source = state.source;
    if (source == null || state.files.isEmpty) return;
    _set(state.copyWith(busy: true, clearError: true));
    try {
      final summary = await ref
          .read(appImportApiProvider)
          .run(
            await _workspaceId(),
            source: source,
            files: state.files,
            dryRun: true,
            options: _options(),
          );
      _set(
        state.copyWith(step: ImportStep.preview, busy: false, preview: summary),
      );
    } on Object catch (e) {
      _set(state.copyWith(busy: false, error: e));
    }
  }

  /// TickTick only: completed tasks are opt-in, and the counts change.
  Future<void> setIncludeCompleted(bool value) async {
    _set(state.copyWith(includeCompleted: value));
    await loadPreview();
  }

  /// Writes the import in batches until the server says nothing remains.
  /// Stops — rather than spinning — when a batch makes no progress.
  Future<void> runImport() async {
    final source = state.source;
    final preview = state.preview;
    if (source == null || preview == null) return;
    final total = preview.total;
    _set(
      state.copyWith(
        step: ImportStep.importing,
        processed: 0,
        total: total,
        clearError: true,
      ),
    );
    var created = const ImportCreated();
    final errors = <ImportItemError>[];
    int? lastRemaining;
    try {
      final workspaceId = await _workspaceId();
      final api = ref.read(appImportApiProvider);
      for (var call = 0; call < 200; call += 1) {
        final batch = await api.run(
          workspaceId,
          source: source,
          files: state.files,
          dryRun: false,
          options: _options(maxItems: 250),
        );
        created = created + batch.created;
        for (final e in batch.errors) {
          if (!errors.any((x) => x.file == e.file && x.row == e.row)) {
            errors.add(e);
          }
        }
        _set(
          state.copyWith(processed: (total - batch.remaining).clamp(0, total)),
        );
        final noProgress =
            batch.created.items == 0 && batch.remaining == lastRemaining;
        if (batch.remaining == 0 || noProgress) break;
        lastRemaining = batch.remaining;
      }
    } on Object catch (e) {
      _set(state.copyWith(step: ImportStep.preview, error: e));
      return;
    }
    // What was written arrives on this device the ordinary way.
    await ref.read(importSyncProvider)();
    _set(
      state.copyWith(
        step: ImportStep.done,
        processed: total,
        report: ImportReport(
          created: created,
          // What was there before this import began. A later batch counts the
          // earlier batches' rows as "already imported" too, so it is not summed.
          alreadyImported: preview.alreadyImported,
          completedSkipped: preview.completedSkipped,
          errors: errors,
        ),
      ),
    );
  }
}

final importWizardProvider =
    NotifierProvider.autoDispose<ImportWizardController, ImportWizardState>(
      ImportWizardController.new,
    );
