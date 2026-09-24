import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_messages.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../data/new_ticket_api.dart' show EeFormCondition, visibleFormFields;
import '../data/services_models.dart';
import '../form_design.dart';
import '../services_providers.dart';
import 'form_field_view.dart';

/// EE-229 — a service's request form, designed beside its own preview.
///
/// ── WHAT THE ADMIN EDITS IS A DRAFT; WHAT THEY PUBLISH IS A VERSION ──
///
/// Nothing here writes until "publish". The questions are a local list, and
/// publishing sends the whole of it in one PATCH that the server turns into
/// the next version (EE-214). That is the only honest shape for a form with a
/// history: saving each drag as it happened would mint a version per click,
/// and a request filed between two of them would be answered against a form
/// nobody had finished.
///
/// ── THE PREVIEW IS THE FORM ──
///
/// Each question is drawn by `EeFormFieldView`, the renderer the person
/// filing a request reads (EE-225), and conditional questions appear through
/// the same `visibleFormFields`. A second renderer would be a picture of the
/// form; this is the form, so what the admin tries here is what gets asked.
///
/// ── REORDERING HAS TWO DOORS ──
///
/// Drag by the handle, or use the up/down buttons on each row. The second is
/// the accessible door — a screen reader, a switch or a keyboard cannot
/// drag — and both run the same move.
class EeFormDesignerScreen extends ConsumerStatefulWidget {
  const EeFormDesignerScreen({super.key, required this.service});

  final EeService service;

  @override
  ConsumerState<EeFormDesignerScreen> createState() =>
      _EeFormDesignerScreenState();
}

class _EeFormDesignerScreenState extends ConsumerState<EeFormDesignerScreen> {
  /// What is live — what "unpublished changes" is measured against.
  late List<EeServiceField> _published = [...widget.service.formFields];
  late final List<EeServiceField> _fields = [...widget.service.formFields];
  late int _version = widget.service.formVersion;

  /// The preview's trial answers. Never sent anywhere: they exist so the
  /// admin can tick a box and watch the question behind it appear.
  final Map<String, Object?> _answers = {};
  bool _busy = false;
  String? _error;

  bool get _dirty => !sameFormDesign(_fields, _published);

  void _move(int from, int to) {
    if (_busy || from == to || to < 0 || to >= _fields.length) return;
    setState(() {
      _fields.insert(to, _fields.removeAt(from));
      _error = null;
    });
  }

  Future<void> _edit(int? index) async {
    final existing = index == null ? null : _fields[index];
    final result = await showDialog<EeServiceField>(
      context: context,
      builder: (_) => _FieldEditor(
        existing: existing,
        // A condition may only look backwards, so the editor is offered
        // exactly the questions above this one — all of them for a new one,
        // which lands at the end.
        earlier: index == null ? [..._fields] : _fields.sublist(0, index),
        takenKeys: {
          for (final field in _fields)
            if (field.key != existing?.key) field.key,
        },
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (index == null) {
        _fields.add(result);
      } else {
        _fields[index] = result;
        // A question that now answers differently drops its trial answer
        // rather than keeping one in a shape it can no longer take.
        if (existing!.type != result.type ||
            existing.options.join('\x00') != result.options.join('\x00')) {
          _answers.remove(result.key);
        }
      }
      _error = null;
    });
  }

  void _remove(int index) {
    if (_busy) return;
    setState(() {
      _answers.remove(_fields.removeAt(index).key);
      _error = null;
    });
  }

  Future<void> _publish() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    await ref
        .read(eeServicesProvider.notifier)
        .publishForm(widget.service.id, _fields);
    if (!mounted) return;
    final after = ref.read(eeServicesProvider);
    if (after.hasError) {
      // The server's own sentence, where the admin is — and the list is
      // asked again, so the catalogue behind this screen shows what is true.
      setState(() {
        _busy = false;
        _error = localizedError(after.error);
      });
      ref.invalidate(eeServicesProvider);
      return;
    }
    final now = after.value
        ?.where((service) => service.id == widget.service.id)
        .firstOrNull;
    setState(() {
      _busy = false;
      _published = [..._fields];
      // The number the SERVER minted, read back — never `_version + 1`,
      // which would be a guess the day a no-op publish mints nothing.
      _version = now?.formVersion ?? _version;
    });
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'ee.team.services.designer.published'.tr(
            args: {'version': '$_version'},
          ),
        ),
      ),
    );
  }

  Future<void> _leave() async {
    final navigator = Navigator.of(context);
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('ee.team.services.designer.discardTitle'.tr()),
        content: Text('ee.team.services.designer.discardBody'.tr()),
        actions: [
          TextButton(
            key: const Key('form-discard-keep'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('ee.team.services.designer.keep'.tr()),
          ),
          FilledButton(
            key: const Key('form-discard-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('ee.team.services.designer.discard'.tr()),
          ),
        ],
      ),
    );
    if (discard == true && mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final problems = formDesignProblems(_fields);
    final canPublish = _dirty && !_busy && problems.isEmpty;
    return PopScope(
      // Leaving with unpublished changes asks first: the draft lives only on
      // this screen, and a back gesture should not be how an afternoon of
      // form design disappears.
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'ee.team.services.designer.title'.tr(
              args: {'service': widget.service.name},
            ),
          ),
          actions: [
            TextButton(
              key: const Key('form-publish'),
              onPressed: canPublish ? _publish : null,
              child: Text('ee.team.services.designer.publish'.tr()),
            ),
            const SizedBox(width: AwSpace.x2),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            // Side by side where there is room; one column on a phone, with
            // the preview under the questions it previews.
            final wide = constraints.maxWidth >= 900;
            final editor = _editor(context, problems, withPreview: !wide);
            if (!wide) return editor;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: editor),
                SizedBox(
                  width: 420,
                  child: ListView(
                    padding: awListPadding(context, top: AwSpace.x4),
                    children: [_preview(context)],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _editor(
    BuildContext context,
    Map<String, FormDesignProblem> problems, {
    required bool withPreview,
  }) {
    final theme = Theme.of(context);
    final full = _fields.length >= kFormMaxFields;
    return ReorderableListView.builder(
      key: const Key('form-designer-list'),
      buildDefaultDragHandles: false,
      padding: awListPadding(context, top: AwSpace.x4),
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'ee.team.services.designer.intro'.tr(),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: AwSpace.x3),
          Text(
            [
              // Three states, not two: a service whose form predates EE-214
              // is live at version 0 until its next publish (the migration
              // left it so rather than invent a number). "Not published"
              // would be false about it, so it is named for what it is.
              switch ((_version, _published.isEmpty)) {
                (0, true) => 'ee.team.services.designer.versionNone'.tr(),
                (0, false) =>
                  'ee.team.services.designer.versionUnnumbered'.tr(),
                _ => 'ee.team.services.designer.version'.tr(
                  args: {'version': '$_version'},
                ),
              },
              _dirty
                  ? 'ee.team.services.designer.unpublished'.tr()
                  : 'ee.team.services.designer.upToDate'.tr(),
            ].join(' · '),
            key: const Key('form-status'),
            style: theme.textTheme.titleSmall,
          ),
          if (problems.isNotEmpty) ...[
            const SizedBox(height: AwSpace.x1),
            Text(
              'ee.team.services.designer.publishBlocked'.tr(),
              key: const Key('form-blocked'),
              style: theme.textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: AwSpace.x3),
          if (_fields.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AwSpace.x3),
              child: Text(
                'ee.team.services.fieldsNone'.tr(),
                key: const Key('form-empty'),
                style: theme.textTheme.bodyMedium,
              ),
            ),
        ],
      ),
      itemCount: _fields.length,
      // `onReorderItem` hands over the index the row ends up AT (the old
      // `onReorder` counted it before the row was removed), so a drag and
      // the up/down buttons are literally the same move.
      onReorderItem: _move,
      itemBuilder: (context, index) {
        final field = _fields[index];
        return _FieldRow(
          key: ValueKey('form-field-${field.key}'),
          field: field,
          index: index,
          last: index == _fields.length - 1,
          busy: _busy,
          problem: problems[field.key],
          dependsOn: _labelOf(field.showIf?.key),
          onEdit: () => _edit(index),
          onMove: (to) => _move(index, to),
          onRemove: () => _remove(index),
        );
      },
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AwSpace.x2),
          OutlinedButton.icon(
            key: const Key('form-field-add'),
            onPressed: _busy || full ? null : () => _edit(null),
            icon: const Icon(Icons.add),
            label: Text('ee.team.services.fieldAdd'.tr()),
          ),
          if (full)
            Padding(
              padding: const EdgeInsets.only(top: AwSpace.x1),
              child: Text(
                'ee.team.services.designer.limit'.tr(),
                key: const Key('form-limit'),
                style: theme.textTheme.bodySmall,
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: AwSpace.x4),
            AwInlineError(
              message: _error!,
              textKey: const Key('form-publish-error'),
            ),
          ],
          if (withPreview) ...[
            const SizedBox(height: AwSpace.x6),
            _preview(context),
          ],
        ],
      ),
    );
  }

  String? _labelOf(String? key) => key == null
      ? null
      : _fields.where((field) => field.key == key).firstOrNull?.label;

  Widget _preview(BuildContext context) {
    final theme = Theme.of(context);
    final shown = visibleFormFields([
      for (final field in _fields) field.toFormField(),
    ], _answers);
    return Card(
      key: const Key('form-preview'),
      child: Padding(
        padding: const EdgeInsets.all(AwSpace.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'ee.team.services.designer.preview'.tr(),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AwSpace.x1),
            Text(
              'ee.team.services.designer.previewHint'.tr(),
              style: theme.textTheme.bodySmall,
            ),
            if (shown.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AwSpace.x3),
                child: Text(
                  'ee.team.services.designer.previewEmpty'.tr(),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            for (final field in shown)
              Padding(
                padding: const EdgeInsets.only(top: AwSpace.x3),
                child: EeFormFieldView(
                  // Keyed by shape: a question that changed type or options
                  // is a new control, not the old one holding stale text.
                  key: ValueKey(
                    'preview/${field.key}/${field.type}/'
                    '${field.options.join('\x00')}',
                  ),
                  field: field,
                  value: _answers[field.key],
                  keyPrefix: 'form-preview',
                  onChanged: (value) => setState(() {
                    if (value == null) {
                      _answers.remove(field.key);
                    } else {
                      _answers[field.key] = value;
                    }
                  }),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    super.key,
    required this.field,
    required this.index,
    required this.last,
    required this.busy,
    required this.problem,
    required this.dependsOn,
    required this.onEdit,
    required this.onMove,
    required this.onRemove,
  });

  final EeServiceField field;
  final int index;
  final bool last;
  final bool busy;
  final FormDesignProblem? problem;

  /// The label of the question this one's condition looks at, if it exists.
  final String? dependsOn;
  final VoidCallback onEdit;
  final ValueChanged<int> onMove;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final condition = field.showIf;
    final facts = [
      'ee.team.services.fieldType.${field.type}'.tr(),
      if (field.required) 'ee.team.services.fieldRequired'.tr(),
      if (condition != null && dependsOn != null)
        condition.equals == kCheckboxTicked
            ? 'ee.team.services.designer.conditionSummaryTicked'.tr(
                args: {'label': dependsOn!},
              )
            : 'ee.team.services.designer.conditionSummary'.tr(
                args: {'label': dependsOn!, 'value': condition.equals},
              ),
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: AwSpace.x2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: const EdgeInsetsDirectional.only(end: AwSpace.x1),
            leading: ReorderableDragStartListener(
              index: index,
              enabled: !busy,
              child: SizedBox(
                key: Key('form-field-drag-${field.key}'),
                width: 48,
                height: 48,
                child: Icon(
                  Icons.drag_indicator,
                  semanticLabel: 'ee.team.services.designer.drag'.tr(),
                ),
              ),
            ),
            title: Text(field.label),
            subtitle: Text(facts.join(' · '), style: theme.textTheme.bodySmall),
            onTap: busy ? null : onEdit,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: Key('form-field-up-${field.key}'),
                  tooltip: 'ee.team.services.designer.moveUp'.tr(),
                  icon: const Icon(Icons.arrow_upward),
                  onPressed: busy || index == 0
                      ? null
                      : () => onMove(index - 1),
                ),
                IconButton(
                  key: Key('form-field-down-${field.key}'),
                  tooltip: 'ee.team.services.designer.moveDown'.tr(),
                  icon: const Icon(Icons.arrow_downward),
                  onPressed: busy || last ? null : () => onMove(index + 1),
                ),
                IconButton(
                  key: Key('form-field-remove-${field.key}'),
                  tooltip: 'ee.team.services.fieldRemove'.tr(),
                  icon: const Icon(Icons.delete_outline),
                  onPressed: busy ? null : onRemove,
                ),
              ],
            ),
          ),
          if (problem != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AwSpace.x3,
                0,
                AwSpace.x3,
                AwSpace.x3,
              ),
              child: AwInlineError(
                message: switch (problem!) {
                  FormDesignProblem.conditionTargetMissing =>
                    'ee.team.services.designer.problemMissing'.tr(),
                  FormDesignProblem.conditionLooksForward =>
                    'ee.team.services.designer.problemForward'.tr(),
                  FormDesignProblem.conditionValueGone =>
                    'ee.team.services.designer.problemValue'.tr(),
                },
                textKey: Key('form-field-problem-${field.key}'),
              ),
            ),
        ],
      ),
    );
  }
}

/// One question, added or edited.
///
/// Every refusal is said beside the input that caused it rather than by a
/// button that silently does nothing — the old add dialog returned without a
/// word when a picker had no options.
class _FieldEditor extends StatefulWidget {
  const _FieldEditor({
    required this.existing,
    required this.earlier,
    required this.takenKeys,
  });

  final EeServiceField? existing;

  /// The questions above this one: the only ones a condition may look at.
  final List<EeServiceField> earlier;
  final Set<String> takenKeys;

  @override
  State<_FieldEditor> createState() => _FieldEditorState();
}

class _FieldEditorState extends State<_FieldEditor> {
  late final _label = TextEditingController(text: widget.existing?.label);
  late final _key = TextEditingController();
  late final _options = TextEditingController(
    text: widget.existing?.options.join('\n'),
  );
  late final _help = TextEditingController(text: widget.existing?.help);
  late final _equalsText = TextEditingController(
    text: widget.existing?.showIf?.equals,
  );
  late String _type = widget.existing?.type ?? 'text';
  late bool _required = widget.existing?.required ?? false;
  late bool _conditional = widget.existing?.showIf != null;
  // A condition whose question is no longer above this one is shown unset,
  // not as a value the dropdown cannot hold — the row already said why.
  late String? _conditionKey =
      widget.earlier.any((f) => f.key == widget.existing?.showIf?.key)
      ? widget.existing!.showIf!.key
      : null;
  late String? _equalsPick = widget.existing?.showIf?.equals;
  Map<String, String> _errors = const {};

  @override
  void dispose() {
    _label.dispose();
    _key.dispose();
    _options.dispose();
    _help.dispose();
    _equalsText.dispose();
    super.dispose();
  }

  EeServiceField? get _target =>
      widget.earlier.where((field) => field.key == _conditionKey).firstOrNull;

  List<String> get _optionList => [
    for (final line in _options.text.split('\n'))
      if (line.trim().isNotEmpty) line.trim(),
  ];

  /// The value the condition will name, from whichever control the target's
  /// type draws.
  String? get _equals => switch (_target?.type) {
    null => null,
    'checkbox' => kCheckboxTicked,
    'select' => _equalsPick,
    _ => _equalsText.text.trim(),
  };

  void _submit() {
    final errors = <String, String>{};
    final label = _label.text.trim();
    if (label.isEmpty || label.length > kFormLabelMax) {
      errors['label'] = 'ee.team.services.designer.errorLabel'.tr();
    }
    final key =
        widget.existing?.key ??
        (_key.text.trim().isEmpty
            ? fieldKeyFromLabel(label)
            : _key.text.trim());
    if (widget.existing == null) {
      if (!kFieldKeyPattern.hasMatch(key)) {
        errors['key'] = 'ee.team.services.designer.errorKey'.tr();
      } else if (widget.takenKeys.contains(key)) {
        // Two questions under one key: the second answer would overwrite the
        // first when the form is sent — a lost answer, not an error.
        errors['key'] = 'ee.team.services.fieldDuplicate'.tr();
      }
    }
    final options = _optionList;
    if (_type == 'select') {
      if (options.isEmpty ||
          options.length > kFormMaxOptions ||
          options.any((o) => o.length > kFormLabelMax)) {
        errors['options'] = 'ee.team.services.designer.errorOptions'.tr();
      } else if (options.toSet().length != options.length) {
        errors['options'] = 'ee.team.services.designer.errorOptionTwice'.tr();
      }
    }
    final help = _help.text.trim();
    if (help.length > kFormHelpMax) {
      errors['help'] = 'ee.team.services.designer.errorHelp'.tr();
    }
    EeFormCondition? condition;
    if (_conditional) {
      final target = _target;
      final equals = _equals;
      if (target == null ||
          equals == null ||
          !conditionValueAccepted(target, equals)) {
        errors['condition'] = 'ee.team.services.designer.errorCondition'.tr();
      } else {
        condition = EeFormCondition(key: target.key, equals: equals);
      }
    }
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      return;
    }
    Navigator.of(context).pop(
      EeServiceField(
        key: key,
        label: label,
        type: _type,
        required: _required,
        options: _type == 'select' ? options : const [],
        help: help.isEmpty ? null : help,
        showIf: condition,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final target = _target;
    final editing = widget.existing != null;
    final answerLabel = 'ee.team.services.designer.conditionEquals'.tr();
    final exactHint = 'ee.team.services.designer.conditionExact'.tr();
    return AlertDialog(
      title: Text(
        (editing
                ? 'ee.team.services.designer.edit'
                : 'ee.team.services.fieldAdd')
            .tr(),
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const Key('field-label'),
                controller: _label,
                autofocus: true,
                maxLength: kFormLabelMax,
                decoration: InputDecoration(
                  labelText: 'ee.team.services.fieldLabel'.tr(),
                  errorText: _errors['label'],
                  errorMaxLines: 3,
                ),
              ),
              if (editing)
                // The key is the question's identity across versions: the
                // answers already given are stored under it, so it is shown
                // and never offered for editing.
                Text(
                  'ee.team.services.designer.keyLocked'.tr(
                    args: {'key': widget.existing!.key},
                  ),
                  key: const Key('field-key-locked'),
                  style: theme.textTheme.bodySmall,
                )
              else
                TextField(
                  key: const Key('field-key'),
                  controller: _key,
                  decoration: InputDecoration(
                    labelText: 'ee.team.services.fieldKey'.tr(),
                    helperText: 'ee.team.services.fieldKeyHint'.tr(),
                    helperMaxLines: 3,
                    errorText: _errors['key'],
                    errorMaxLines: 3,
                  ),
                ),
              const SizedBox(height: AwSpace.x3),
              DropdownButtonFormField<String>(
                key: const Key('field-type'),
                initialValue: _type,
                isExpanded: true,
                decoration: InputDecoration(
                  // `fieldType` is a MAP of the five type names, so the
                  // picker's own label needs a separate key.
                  labelText: 'ee.team.services.fieldTypeLabel'.tr(),
                ),
                items: [
                  for (final type in EeServiceField.types)
                    DropdownMenuItem(
                      value: type,
                      child: Text('ee.team.services.fieldType.$type'.tr()),
                    ),
                ],
                onChanged: (type) => setState(() => _type = type ?? 'text'),
              ),
              if (_type == 'select')
                TextField(
                  key: const Key('field-options'),
                  controller: _options,
                  minLines: 3,
                  maxLines: 8,
                  decoration: InputDecoration(
                    labelText: 'ee.team.services.fieldOptions'.tr(),
                    helperText: 'ee.team.services.fieldOptionsHint'.tr(),
                    errorText: _errors['options'],
                    errorMaxLines: 3,
                  ),
                ),
              TextField(
                key: const Key('field-help'),
                controller: _help,
                maxLength: kFormHelpMax,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'ee.team.services.designer.help'.tr(),
                  helperText: 'ee.team.services.designer.helpHint'.tr(),
                  helperMaxLines: 3,
                  errorText: _errors['help'],
                ),
              ),
              SwitchListTile(
                key: const Key('field-required'),
                contentPadding: EdgeInsets.zero,
                value: _required,
                title: Text('ee.team.services.fieldRequired'.tr()),
                onChanged: (value) => setState(() => _required = value),
              ),
              SwitchListTile(
                key: const Key('field-conditional'),
                contentPadding: EdgeInsets.zero,
                value: _conditional,
                title: Text('ee.team.services.designer.conditional'.tr()),
                subtitle: widget.earlier.isEmpty
                    ? Text('ee.team.services.designer.conditionalNone'.tr())
                    : null,
                onChanged: widget.earlier.isEmpty
                    ? null
                    : (value) => setState(() => _conditional = value),
              ),
              if (_conditional && widget.earlier.isNotEmpty) ...[
                DropdownButtonFormField<String>(
                  key: const Key('field-condition-key'),
                  initialValue: _conditionKey,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'ee.team.services.designer.conditionOn'.tr(),
                  ),
                  items: [
                    for (final field in widget.earlier)
                      DropdownMenuItem(
                        value: field.key,
                        child: Text(field.label),
                      ),
                  ],
                  onChanged: (key) => setState(() {
                    _conditionKey = key;
                    _equalsPick = null;
                  }),
                ),
                if (target?.type == 'select')
                  DropdownButtonFormField<String>(
                    // Keyed by the question, so picking another one starts
                    // this picker empty instead of holding a stale option.
                    key: ValueKey('field-condition-value-${target!.key}'),
                    initialValue: target.options.contains(_equalsPick)
                        ? _equalsPick
                        : null,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: answerLabel),
                    items: [
                      for (final option in target.options)
                        DropdownMenuItem(value: option, child: Text(option)),
                    ],
                    onChanged: (value) => setState(() => _equalsPick = value),
                  )
                else if (target?.type == 'checkbox')
                  Padding(
                    padding: const EdgeInsets.only(top: AwSpace.x2),
                    child: Text(
                      'ee.team.services.designer.conditionTicked'.tr(),
                      key: const Key('field-condition-ticked'),
                      style: theme.textTheme.bodySmall,
                    ),
                  )
                else if (target != null)
                  TextField(
                    key: const Key('field-condition-text'),
                    controller: _equalsText,
                    maxLength: kFormLabelMax,
                    decoration: InputDecoration(
                      labelText: answerLabel,
                      helperText: exactHint,
                    ),
                  ),
                if (_errors['condition'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AwSpace.x2),
                    child: AwInlineError(
                      message: _errors['condition']!,
                      textKey: const Key('field-condition-error'),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('common.cancel'.tr()),
        ),
        FilledButton(
          key: const Key('field-save'),
          onPressed: _submit,
          child: Text((editing ? 'common.save' : 'common.add').tr()),
        ),
      ],
    );
  }
}
