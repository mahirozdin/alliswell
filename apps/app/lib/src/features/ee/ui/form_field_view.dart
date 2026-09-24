import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/date_format.dart';
import '../../../core/persisted_prefs.dart';
import '../../../i18n/i18n.dart';
import '../data/new_ticket_api.dart';

/// One question of a service's form, drawn the ONE way it is drawn.
///
/// Two screens show a form: the person filing a request (EE-225) and the
/// admin's designer, whose preview is that same form (EE-229). A preview drawn
/// by a second renderer would be a picture of what somebody thinks the form
/// looks like; this is the form, so what the admin sees is what gets asked.
///
/// [onChanged] hands back the answer in the shape the server takes — a
/// string, a number (a number field's text when it parses), `true`/`false`
/// for a checkbox, `yyyy-mm-dd` for a date — or null when it was emptied.
class EeFormFieldView extends ConsumerStatefulWidget {
  const EeFormFieldView({
    super.key,
    required this.field,
    required this.value,
    required this.onChanged,
    required this.keyPrefix,
    this.enabled = true,
  });

  final EeFormField field;
  final Object? value;
  final ValueChanged<Object?> onChanged;

  /// Test keys are `<prefix>-<field key>` (and `…-pick` on a date).
  final String keyPrefix;
  final bool enabled;

  @override
  ConsumerState<EeFormFieldView> createState() => _EeFormFieldViewState();
}

class _EeFormFieldViewState extends ConsumerState<EeFormFieldView> {
  late final TextEditingController _text = TextEditingController(
    text: widget.value == null ? '' : '${widget.value}',
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final current = widget.value as String?;
    final picked = await showDatePicker(
      context: context,
      initialDate: current == null ? now : DateTime.parse(current),
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null || !mounted) return;
    // The day, as the server's date answers are written: yyyy-mm-dd.
    widget.onChanged(
      '${picked.year.toString().padLeft(4, '0')}-'
      '${picked.month.toString().padLeft(2, '0')}-'
      '${picked.day.toString().padLeft(2, '0')}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final field = widget.field;
    final theme = Theme.of(context);
    final label = field.required
        ? 'ee.tickets.new.requiredLabel'.tr(args: {'label': field.label})
        : field.label;
    final key = Key('${widget.keyPrefix}-${field.key}');
    final help = field.help;
    switch (field.type) {
      case 'checkbox':
        return CheckboxListTile(
          key: key,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: widget.value == true,
          title: Text(label),
          subtitle: help == null ? null : Text(help),
          onChanged: widget.enabled
              ? (value) => widget.onChanged(value ?? false)
              : null,
        );
      case 'select':
        return DropdownButtonFormField<String>(
          key: key,
          initialValue: field.options.contains(widget.value)
              ? widget.value as String
              : null,
          isExpanded: true,
          decoration: InputDecoration(labelText: label, helperText: help),
          hint: Text('ee.tickets.new.selectHint'.tr()),
          items: [
            for (final option in field.options)
              DropdownMenuItem(value: option, child: Text(option)),
          ],
          onChanged: widget.enabled ? widget.onChanged : null,
        );
      case 'date':
        final picked = widget.value as String?;
        final format = ref.watch(dateFormatProvider);
        return InputDecorator(
          key: key,
          decoration: InputDecoration(labelText: label, helperText: help),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: Key('${widget.keyPrefix}-${field.key}-pick'),
              onPressed: widget.enabled ? _pickDate : null,
              icon: const Icon(Icons.event_outlined),
              label: Text(
                picked == null
                    ? 'ee.tickets.new.pickDate'.tr()
                    : awFormatDate(DateTime.parse(picked), format: format),
              ),
            ),
          ),
        );
      default:
        final number = field.type == 'number';
        final raw = _text.text.trim();
        return TextField(
          key: key,
          controller: _text,
          enabled: widget.enabled,
          keyboardType: number
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          decoration: InputDecoration(
            labelText: label,
            helperText: help,
            errorText: number && raw.isNotEmpty && num.tryParse(raw) == null
                ? 'ee.tickets.new.invalidNumber'.tr()
                : null,
          ),
          style: theme.textTheme.bodyLarge,
          onChanged: (text) {
            final trimmed = text.trim();
            setState(() {});
            if (trimmed.isEmpty) {
              widget.onChanged(null);
            } else if (number) {
              widget.onChanged(num.tryParse(trimmed) ?? trimmed);
            } else {
              widget.onChanged(trimmed);
            }
          },
        );
    }
  }
}
