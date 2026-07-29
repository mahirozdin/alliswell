import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persisted_prefs.dart';
import '../../../core/recurrence.dart';
import '../../../core/recurrence_text.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../data/task.dart';
import '../providers.dart';
import 'repeat_dialog.dart';

/// The Repeat switch and the sentence under it (OPH-207, DESIGN §25 R1/R2/R7).
///
/// Turning the switch on opens the dialog immediately, and cancelling turns it
/// back off — a switch that can leave a half-configured rule behind is a lie
/// about state. Once a rule exists the row reads as one sentence with
/// **Değiştir** beside it, never as a form summary.
class RepeatRow extends ConsumerWidget {
  const RepeatRow({super.key, required this.task});

  final Task task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seriesId = task.seriesId;
    final series = seriesId == null
        ? null
        : ref.watch(taskSeriesProvider(seriesId)).value;
    final on = seriesId != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          key: const Key('repeat-switch'),
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.repeat),
          title: Text('repeat.switchTitle'.tr()),
          subtitle: Text('repeat.switchSubtitle'.tr()),
          value: on,
          onChanged: (wanted) =>
              wanted ? _start(context, ref) : _stop(context, ref),
        ),
        if (series != null)
          Padding(
            padding: const EdgeInsets.only(
              left: AwSpace.x8,
              bottom: AwSpace.x2,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    awRepeatSentence(
                      series.rule,
                      dateFormat: ref.watch(dateFormatProvider),
                      locale: AwI18n.instance.locale.languageCode,
                    ),
                    key: const Key('repeat-summary'),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                TextButton(
                  key: const Key('repeat-change'),
                  onPressed: () => _change(context, ref, series.rule),
                  child: Text('repeat.change'.tr()),
                ),
              ],
            ),
          ),
      ],
    );
  }

  DateTime get _anchor => (task.dueAt ?? DateTime.now()).toLocal();

  Future<void> _start(BuildContext context, WidgetRef ref) async {
    final rule = await showRepeatDialog(context, anchor: _anchor);
    // R1: cancelling leaves nothing behind — the switch simply goes back off,
    // which it already is, because the series is what turns it on.
    if (rule == null) return;
    await ref
        .read(seriesStoreProvider)
        .create(
          workspaceId: task.workspaceId,
          rule: rule,
          template: {
            'title': task.title,
            'description': task.description,
            'projectId': task.projectId,
            'priority': task.priority,
            'colorRgb': task.colorRgb,
            'isUrgent': task.isUrgent,
            'requiresAcknowledgement': task.requiresAcknowledgement,
            'tagIds': task.tagIds,
          },
          anchorAt: _anchor,
          timezone: task.timezone,
          fromTaskId: task.id,
        );
  }

  Future<void> _change(
    BuildContext context,
    WidgetRef ref,
    AwRepeatRule current,
  ) async {
    final rule = await showRepeatDialog(
      context,
      anchor: _anchor,
      initial: current,
    );
    if (rule == null || rule == current) return;
    await ref
        .read(seriesStoreProvider)
        .updateRule(
          workspaceId: task.workspaceId,
          seriesId: task.seriesId!,
          rule: rule,
        );
  }

  /// R7: stopping is honest about the past — the copy says what survives, and
  /// the server keeps every finished occurrence.
  Future<void> _stop(BuildContext context, WidgetRef ref) async {
    final seriesId = task.seriesId;
    if (seriesId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        key: const Key('repeat-stop-dialog'),
        title: Text('repeat.stop'.tr()),
        content: Text('repeat.stopConfirm'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            key: const Key('repeat-stop-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('repeat.stop'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref
        .read(seriesStoreProvider)
        .stop(workspaceId: task.workspaceId, seriesId: seriesId);
  }
}

/// The scope question (DESIGN §25 R8): which occurrences an edit reaches.
///
/// Preselects **"Bu ve gelecektekiler"** — the owner's rule — except when the
/// edit is a date, where rescheduling one appointment is not rescheduling the
/// series. Returns null when the user backs out, and the caller writes nothing.
Future<String?> showSeriesScopeDialog(
  BuildContext context, {
  bool isDateEdit = false,
}) => showDialog<String>(
  context: context,
  useRootNavigator: true,
  builder: (dialogContext) => _ScopeDialog(isDateEdit: isDateEdit),
);

class _ScopeDialog extends StatefulWidget {
  const _ScopeDialog({required this.isDateEdit});

  final bool isDateEdit;

  @override
  State<_ScopeDialog> createState() => _ScopeDialogState();
}

class _ScopeDialogState extends State<_ScopeDialog> {
  late String _scope = widget.isDateEdit ? 'this' : 'future';

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const Key('series-scope-dialog'),
    title: Text('repeat.scope.title'.tr()),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('repeat.scope.question'.tr()),
        const SizedBox(height: AwSpace.x2),
        RadioGroup<String>(
          groupValue: _scope,
          onChanged: (picked) => setState(() => _scope = picked ?? _scope),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final scope in const ['this', 'future', 'all'])
                RadioListTile<String>(
                  key: Key('scope-$scope'),
                  contentPadding: EdgeInsets.zero,
                  value: scope,
                  title: Text('repeat.scope.$scope'.tr()),
                ),
            ],
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text('common.cancel'.tr()),
      ),
      FilledButton(
        key: const Key('scope-apply'),
        onPressed: () => Navigator.of(context).pop(_scope),
        child: Text('repeat.scope.apply'.tr()),
      ),
    ],
  );
}
