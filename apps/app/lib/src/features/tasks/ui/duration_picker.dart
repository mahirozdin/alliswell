import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../data/task_when.dart';

/// "How long will it take?" (OPH-372, DESIGN §38 W3): one-tap presets plus a
/// custom number of minutes, 1..[kAwMaxEstimatedMinutes].
///
/// Returns the minutes on Save, null on Cancel (= no change — clearing is the
/// row's own ✕, not this dialog's job).
Future<int?> showDurationPicker(BuildContext context, {int? current}) =>
    showDialog<int>(
      context: context,
      // The ROOT navigator: pushed into a shell branch a dialog renders under
      // the shell's glass bar and FAB (OPH-212).
      useRootNavigator: true,
      builder: (_) => _DurationDialog(current: current),
    );

class _DurationDialog extends StatefulWidget {
  const _DurationDialog({this.current});

  final int? current;

  @override
  State<_DurationDialog> createState() => _DurationDialogState();
}

class _DurationDialogState extends State<_DurationDialog> {
  // Owned for the dialog's whole life: disposing when showDialog returns
  // rebuilds the field mid-animation and throws (repeat dialog R5).
  final _custom = TextEditingController();
  int? _selected;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selected = widget.current;
    if (widget.current != null) _custom.text = '${widget.current}';
  }

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  void _pick(int minutes) => setState(() {
    _selected = minutes;
    _custom.text = '$minutes';
    _error = null;
  });

  void _typed(String raw) {
    final value = int.tryParse(raw.trim());
    setState(() {
      _selected = value;
      _error = null;
    });
  }

  void _save() {
    final value = _selected;
    if (value == null || value < 1 || value > kAwMaxEstimatedMinutes) {
      setState(() => _error = 'task.durationDialog.invalid'.tr());
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('duration-dialog'),
      title: Text('task.durationDialog.title'.tr()),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: AwSpace.x2,
              runSpacing: AwSpace.x2,
              children: [
                for (final minutes in kAwDurationPresets)
                  ChoiceChip(
                    key: Key('duration-preset-$minutes'),
                    label: Text(awFormatDuration(minutes)),
                    selected: _selected == minutes,
                    onSelected: (_) => _pick(minutes),
                  ),
              ],
            ),
            const SizedBox(height: AwSpace.x4),
            TextField(
              key: const Key('duration-custom'),
              controller: _custom,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'task.durationDialog.custom'.tr(),
                errorText: _error,
              ),
              onChanged: _typed,
              onSubmitted: (_) => _save(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('duration-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text('common.cancel'.tr()),
        ),
        FilledButton(
          key: const Key('duration-save'),
          onPressed: _save,
          child: Text('common.save'.tr()),
        ),
      ],
    );
  }
}
