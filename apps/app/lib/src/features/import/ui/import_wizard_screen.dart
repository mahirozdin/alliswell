import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api_exception.dart';
import '../../../core/error_messages.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/route_leading.dart';
import '../../../widgets/status_views.dart';
import '../../tasks/ui/task_visuals.dart';
import '../data/import_api.dart';
import '../data/import_file_reader.dart';
import '../data/import_models.dart';
import '../providers.dart';

/// Moving in from Todoist or TickTick (OPH-371, DESIGN §37).
///
/// One screen, four steps: choose the app, choose its export, look at what
/// will happen, import. The preview is the server's own dry run of the same
/// request (§37 I1), and everything the import cannot carry over exactly is a
/// counted warning with examples (§37 I2) — never a silent loss.
class ImportWizardScreen extends ConsumerWidget {
  const ImportWizardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(importWizardProvider);
    final controller = ref.read(importWizardProvider.notifier);
    final step = switch (state.step) {
      ImportStep.source => 1,
      ImportStep.file => 2,
      ImportStep.preview => 3,
      ImportStep.importing || ImportStep.done => 4,
    };

    final body = switch (state.step) {
      ImportStep.source => _SourceStep(onChoose: controller.chooseSource),
      ImportStep.file => _FileStep(state: state, controller: controller),
      ImportStep.preview => _PreviewStep(state: state, controller: controller),
      ImportStep.importing => _ImportingStep(state: state),
      ImportStep.done => _ResultStep(state: state),
    };

    return Scaffold(
      appBar: AppBar(
        leading: awRouteLeading(context),
        title: Text('import.title'.tr()),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            key: const Key('import-wizard'),
            padding: awListPadding(context, top: AwSpace.x2),
            children: [
              _StepHeader(step: step, state: state),
              const SizedBox(height: AwSpace.x3),
              body,
            ],
          ),
        ),
      ),
    );
  }
}

/// The message for any failure the wizard can meet — local refusals first,
/// then the server's codes, then the generic mapping.
String importErrorText(Object error) {
  if (error is ImportTooLarge) return 'import.error.tooLarge'.tr();
  if (error is ImportNoCsv) return 'import.error.noCsv'.tr();
  if (error is ImportSourceMismatch) {
    return error.detected == 'ticktick'
        ? 'import.error.looksTicktick'.tr()
        : 'import.error.looksTodoist'.tr();
  }
  if (error is ApiException &&
      (error.statusCode == 413 || error.code == 'FST_ERR_CTP_BODY_TOO_LARGE')) {
    return 'import.error.proxyLimit'.tr();
  }
  if (error is ApiException && error.code == 'NETWORK_ERROR') {
    return 'import.error.offline'.tr();
  }
  if (error is ApiException || error is StateError) {
    return error is ApiException ? localizedError(error) : 'error.unknown'.tr();
  }
  return 'import.error.read'.tr();
}

class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.step, required this.state});

  final int step;
  final ImportWizardState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final title = switch (state.step) {
      ImportStep.source => 'import.step.source'.tr(),
      ImportStep.file => 'import.step.file'.tr(
        args: {'app': state.source?.label ?? ''},
      ),
      ImportStep.preview => 'import.step.preview'.tr(),
      ImportStep.importing => 'import.step.importing'.tr(),
      ImportStep.done => 'import.step.done'.tr(),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AwSpace.x1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'import.stepOf'.tr(args: {'n': '$step', 'total': '4'}),
            key: const Key('import-step-of'),
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AwSpace.x1),
          Text(title, style: theme.textTheme.titleLarge),
        ],
      ),
    );
  }
}

/// A plain card with a padded column — the wizard's one container.
class _Panel extends StatelessWidget {
  const _Panel({required this.children, this.panelKey});

  final List<Widget> children;
  final Key? panelKey;

  @override
  Widget build(BuildContext context) => Padding(
    padding: kAwListRowPadding,
    child: Card(
      key: panelKey,
      child: Padding(
        padding: const EdgeInsets.all(AwSpace.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    ),
  );
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text, this.iconColor});

  final IconData icon;
  final String text;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 20,
          color: iconColor ?? theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: AwSpace.x3),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Step 1: which app ─────────────────────────────────────────────────────

class _SourceStep extends StatelessWidget {
  const _SourceStep({required this.onChoose});

  final void Function(ImportSource) onChoose;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AwSpace.x1,
            0,
            AwSpace.x1,
            AwSpace.x2,
          ),
          child: Text('import.intro'.tr()),
        ),
        for (final source in ImportSource.values)
          Padding(
            padding: kAwListRowPadding,
            child: Card(
              child: ListTile(
                key: Key('import-source-${source.wire}'),
                minVerticalPadding: AwSpace.x3,
                leading: const Icon(Icons.move_down_outlined),
                title: Text(source.label),
                subtitle: Text('import.how.${source.wire}'.tr()),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => onChoose(source),
              ),
            ),
          ),
        const SizedBox(height: AwSpace.x2),
        _Panel(
          children: [
            _Note(icon: Icons.info_outline, text: 'import.appleNote'.tr()),
          ],
        ),
      ],
    );
  }
}

// ── Step 2: which file ────────────────────────────────────────────────────

String _size(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class _FileStep extends StatelessWidget {
  const _FileStep({required this.state, required this.controller});

  final ImportWizardState state;
  final ImportWizardController controller;

  @override
  Widget build(BuildContext context) {
    final source = state.source!;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Panel(
          children: [
            Text(
              'import.export.${source.wire}'.tr(),
              style: theme.textTheme.bodyMedium,
            ),
            if (source == ImportSource.todoist) ...[
              const SizedBox(height: AwSpace.x3),
              _Note(
                icon: Icons.info_outline,
                text: 'import.todoistNoCompleted'.tr(),
              ),
            ],
            const SizedBox(height: AwSpace.x4),
            FilledButton.tonalIcon(
              key: const Key('import-pick'),
              onPressed: state.busy ? null : controller.pickFiles,
              icon: const Icon(Icons.upload_file_outlined),
              label: Text(
                state.files.isEmpty
                    ? 'import.pick'.tr()
                    : 'import.pickAgain'.tr(),
              ),
            ),
          ],
        ),
        if (state.files.isNotEmpty) ...[
          const SizedBox(height: AwSpace.x2),
          for (final f in state.files)
            Padding(
              padding: kAwListRowPadding,
              child: Card(
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.description_outlined),
                  title: Text(f.name),
                  trailing: Text(
                    _size(f.bytes),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
        ],
        if (state.error != null) ...[
          const SizedBox(height: AwSpace.x3),
          AwInlineError(
            textKey: const Key('import-error'),
            message: importErrorText(state.error!),
          ),
        ],
        const SizedBox(height: AwSpace.x4),
        _Actions(
          onBack: state.busy ? null : controller.back,
          primary: FilledButton(
            key: const Key('import-preview'),
            onPressed: state.busy || state.files.isEmpty
                ? null
                : controller.loadPreview,
            child: state.busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text('import.previewButton'.tr()),
          ),
        ),
      ],
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.primary, this.onBack});

  final Widget primary;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.end,
    spacing: AwSpace.x2,
    runSpacing: AwSpace.x2,
    children: [
      TextButton(
        key: const Key('import-back'),
        onPressed: onBack,
        child: Text('import.back'.tr()),
      ),
      primary,
    ],
  );
}

// ── Step 3: what will happen ──────────────────────────────────────────────

class _Count extends StatelessWidget {
  const _Count({required this.value, required this.label, this.countKey});

  final int value;
  final String label;
  final Key? countKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 132,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$value', key: countKey, style: theme.textTheme.headlineSmall),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

String warningText(String code) =>
    AwI18n.instance.maybeTranslate('import.warning.$code') ??
    'import.warning.other'.tr();

class _PreviewStep extends StatelessWidget {
  const _PreviewStep({required this.state, required this.controller});

  final ImportWizardState state;
  final ImportWizardController controller;

  @override
  Widget build(BuildContext context) {
    final p = state.preview!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tokens = context.awTokens;
    final completed = p.completedIncluded + p.completedSkipped;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Panel(
          panelKey: const Key('import-counts'),
          children: [
            Text(
              'import.fromFiles'.tr(args: {'count': '${state.files.length}'}),
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AwSpace.x3),
            Wrap(
              spacing: AwSpace.x3,
              runSpacing: AwSpace.x3,
              children: [
                _Count(
                  countKey: const Key('import-count-tasks'),
                  value: p.tasks,
                  label: 'import.count.tasks'.tr(),
                ),
                _Count(value: p.series, label: 'import.count.series'.tr()),
                _Count(
                  value: p.checklistItems,
                  label: 'import.count.checklist'.tr(),
                ),
                _Count(value: p.notes, label: 'import.count.notes'.tr()),
                _Count(
                  value: p.projectsNew,
                  label: 'import.count.projectsNew'.tr(),
                ),
                _Count(
                  value: p.projectsExisting,
                  label: 'import.count.projectsExisting'.tr(),
                ),
                _Count(
                  value: p.tagsNew + p.tagsExisting,
                  label: 'import.count.tags'.tr(),
                ),
                _Count(
                  countKey: const Key('import-count-already'),
                  value: p.alreadyImported,
                  label: 'import.count.already'.tr(),
                ),
              ],
            ),
          ],
        ),
        if (state.source == ImportSource.ticktick && completed > 0)
          Padding(
            padding: kAwListRowPadding,
            child: Card(
              child: SwitchListTile(
                key: const Key('import-include-completed'),
                value: state.includeCompleted,
                onChanged: state.busy ? null : controller.setIncludeCompleted,
                title: Text(
                  'import.includeCompleted'.tr(args: {'count': '$completed'}),
                ),
                subtitle: Text('import.includeCompletedSub'.tr()),
              ),
            ),
          ),
        _Panel(
          panelKey: const Key('import-mapping'),
          children: [
            Text(
              'import.mapping.title'.tr(),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: AwSpace.x2),
            for (final row in p.priority)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AwSpace.x1),
                child: Row(
                  children: [
                    SizedBox(
                      width: 96,
                      child: Text(
                        // Todoist's own words (P1…P4) stay as they are.
                        RegExp(r'^p\d$').hasMatch(row.from)
                            ? row.from.toUpperCase()
                            : 'task.priority.${row.from}'.tr(),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: AwSpace.x2),
                    Icon(
                      Icons.flag,
                      size: 16,
                      color:
                          taskPriorityColorOf(context, row.to) ??
                          scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: AwSpace.x1),
                    Text(
                      'task.priority.${row.to}'.tr(),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            const SizedBox(height: AwSpace.x2),
            _Note(
              icon: Icons.label_outline,
              text: state.source == ImportSource.todoist
                  ? 'import.mapping.sectionsTodoist'.tr()
                  : 'import.mapping.sectionsTicktick'.tr(),
            ),
            const SizedBox(height: AwSpace.x2),
            _Note(
              icon: Icons.checklist_outlined,
              text: 'import.mapping.subItems'.tr(),
            ),
            const SizedBox(height: AwSpace.x2),
            _Note(
              icon: Icons.notifications_off_outlined,
              text: 'import.mapping.noAlarms'.tr(),
            ),
          ],
        ),
        if (p.warnings.isNotEmpty)
          Padding(
            padding: kAwListRowPadding,
            child: Card(
              key: const Key('import-warnings'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AwSpace.x4,
                      AwSpace.x4,
                      AwSpace.x4,
                      AwSpace.x1,
                    ),
                    child: Text(
                      'import.warnings.title'.tr(),
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  for (final w in p.warnings)
                    ExpansionTile(
                      key: Key('import-warning-${w.code}'),
                      // No hairlines when it opens: the card is the frame.
                      shape: const Border(),
                      collapsedShape: const Border(),
                      leading: Icon(
                        Icons.warning_amber_rounded,
                        color: tokens.warning,
                      ),
                      title: Text(warningText(w.code)),
                      subtitle: Text(
                        'import.warnings.count'.tr(
                          args: {'count': '${w.count}'},
                        ),
                      ),
                      childrenPadding: const EdgeInsets.fromLTRB(
                        AwSpace.x4,
                        0,
                        AwSpace.x4,
                        AwSpace.x3,
                      ),
                      expandedCrossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final e in w.examples)
                          Padding(
                            padding: const EdgeInsets.only(bottom: AwSpace.x1),
                            child: Text(
                              [
                                if (e.file != null)
                                  e.row == null
                                      ? e.file!
                                      : '${e.file}:${e.row}',
                                if (e.title != null) e.title!,
                                if (e.value != null) '“${e.value}”',
                              ].join(' · '),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        if (p.googleConnected && p.googleTasks > 0)
          _Panel(
            panelKey: const Key('import-google-notice'),
            children: [
              _Note(
                icon: Icons.event_outlined,
                iconColor: scheme.primary,
                text: p.googleUndated > 0
                    ? 'import.google.withUndated'.tr(
                        args: {
                          'count': '${p.googleTasks}',
                          'undated': '${p.googleUndated}',
                        },
                      )
                    : 'import.google.plain'.tr(
                        args: {'count': '${p.googleTasks}'},
                      ),
              ),
            ],
          ),
        if (p.total == 0)
          _Panel(
            children: [
              _Note(
                icon: Icons.check_circle_outline,
                text: 'import.nothingNew'.tr(),
              ),
            ],
          ),
        if (state.error != null) ...[
          const SizedBox(height: AwSpace.x3),
          AwInlineError(
            textKey: const Key('import-error'),
            message: importErrorText(state.error!),
          ),
        ],
        const SizedBox(height: AwSpace.x4),
        _Actions(
          onBack: state.busy ? null : controller.back,
          primary: FilledButton(
            key: const Key('import-run'),
            onPressed: state.busy || p.total == 0 ? null : controller.runImport,
            child: Text('import.run'.tr(args: {'count': '${p.total}'})),
          ),
        ),
      ],
    );
  }
}

// ── Step 4: importing, then the report ───────────────────────────────────

class _ImportingStep extends StatelessWidget {
  const _ImportingStep({required this.state});

  final ImportWizardState state;

  @override
  Widget build(BuildContext context) {
    final total = state.total == 0 ? 1 : state.total;
    return _Panel(
      children: [
        Text(
          'import.progress'.tr(
            args: {'done': '${state.processed}', 'total': '${state.total}'},
          ),
          key: const Key('import-progress-text'),
        ),
        const SizedBox(height: AwSpace.x3),
        LinearProgressIndicator(
          key: const Key('import-progress'),
          value: state.processed / total,
        ),
        const SizedBox(height: AwSpace.x3),
        _Note(icon: Icons.info_outline, text: 'import.progressNote'.tr()),
      ],
    );
  }
}

class _ResultStep extends StatelessWidget {
  const _ResultStep({required this.state});

  final ImportWizardState state;

  @override
  Widget build(BuildContext context) {
    final r = state.report!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = r.created;
    String line(String key, int n) => '${'import.result.$key'.tr()}: $n';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Panel(
          panelKey: const Key('import-result'),
          children: [
            _Note(
              icon: Icons.check_circle_outline,
              iconColor: context.awTokens.success,
              text: 'import.result.headline'.tr(args: {'count': '${c.items}'}),
            ),
            const SizedBox(height: AwSpace.x3),
            for (final text in [
              line('tasks', c.tasks),
              line('series', c.series),
              line('checklist', c.checklistItems),
              line('notes', c.notes),
              line('projects', c.projects),
              line('tags', c.tags),
              if (r.alreadyImported > 0) line('already', r.alreadyImported),
              if (r.completedSkipped > 0)
                line('completedSkipped', r.completedSkipped),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: AwSpace.x1),
                child: Text(text, style: theme.textTheme.bodyMedium),
              ),
          ],
        ),
        if (r.errors.isNotEmpty)
          _Panel(
            panelKey: const Key('import-result-errors'),
            children: [
              Text(
                'import.result.errors'.tr(
                  args: {'count': '${r.errors.length}'},
                ),
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: AwSpace.x2),
              for (final e in r.errors)
                Padding(
                  padding: const EdgeInsets.only(bottom: AwSpace.x2),
                  child: _Note(
                    icon: Icons.error_outline,
                    iconColor: scheme.error,
                    text:
                        '${e.file ?? ''}${e.row == null ? '' : ':${e.row}'} — '
                        '${localizedErrorCode(e.code, e.message)}',
                  ),
                ),
            ],
          ),
        const SizedBox(height: AwSpace.x4),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: AwSpace.x2,
          runSpacing: AwSpace.x2,
          children: [
            TextButton(
              key: const Key('import-open-home'),
              onPressed: () => GoRouter.maybeOf(context)?.go('/'),
              child: Text('import.openHome'.tr()),
            ),
            FilledButton(
              key: const Key('import-done'),
              onPressed: () {
                final router = GoRouter.maybeOf(context);
                if (router == null) {
                  Navigator.of(context).maybePop();
                } else if (router.canPop()) {
                  router.pop();
                } else {
                  router.go('/settings/data');
                }
              },
              child: Text('import.done'.tr()),
            ),
          ],
        ),
      ],
    );
  }
}
