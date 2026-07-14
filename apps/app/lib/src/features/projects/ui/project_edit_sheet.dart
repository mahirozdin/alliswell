import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../data/project.dart';
import '../providers.dart';

/// Quick-pick palette; the trailing palette button opens the full color grid.
/// End users never see or type hex codes (feedback round 1).
const kProjectPalette = [
  '#2563EB',
  '#0EA5E9',
  '#14B8A6',
  '#10B981',
  '#F59E0B',
  '#F97316',
  '#EF4444',
  '#EC4899',
  '#8B5CF6',
  '#64748B',
];

const kProjectStatuses = ['active', 'paused', 'completed', 'archived'];

String _hexOf(Color color) =>
    '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

/// Opens the create (project == null) or edit sheet.
Future<void> showProjectEditSheet(BuildContext context, {Project? project}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => ProjectEditSheet(project: project),
  );
}

class ProjectEditSheet extends ConsumerStatefulWidget {
  const ProjectEditSheet({super.key, this.project});

  final Project? project;

  @override
  ConsumerState<ProjectEditSheet> createState() => _ProjectEditSheetState();
}

class _ProjectEditSheetState extends ConsumerState<ProjectEditSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late String _colorHex;
  late String _status;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.project != null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.project?.name ?? '');
    _colorHex = widget.project?.colorRgb.toUpperCase() ?? kProjectPalette.first;
    _status = widget.project?.status ?? 'active';
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickMoreColors() async {
    final picked = await showDialog<String>(
      context: context,
      builder: (_) => _ColorGridDialog(selectedHex: _colorHex),
    );
    if (picked != null) setState(() => _colorHex = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final controller = ref.read(projectsControllerProvider.notifier);
    final body = {
      'name': _name.text.trim(),
      'colorRgb': _colorHex,
      if (_isEdit) 'status': _status,
    };
    try {
      if (_isEdit) {
        await controller.updateProject(widget.project!.id, body);
      } else {
        await controller.createProject(body);
      }
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } on Object {
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    final knownColor = kProjectPalette.contains(_colorHex);
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _isEdit ? 'Edit project' : 'New project',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                autofocus: !_isEdit,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Give the project a name'
                    : null,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final swatch in kProjectPalette)
                    _ColorSwatchDot(
                      color: colorFromRgbHex(swatch),
                      selected: _colorHex == swatch,
                      onTap: () => setState(() => _colorHex = swatch),
                    ),
                  // A color picked from the full grid shows as its own swatch.
                  if (!knownColor)
                    _ColorSwatchDot(
                      color: colorFromRgbHex(_colorHex),
                      selected: true,
                      onTap: _pickMoreColors,
                    ),
                  _MoreColorsButton(
                    key: const Key('more-colors'),
                    onTap: _pickMoreColors,
                  ),
                ],
              ),
              if (_isEdit) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _status,
                  decoration: const InputDecoration(
                    labelText: 'Status',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final status in kProjectStatuses)
                      DropdownMenuItem(value: status, child: Text(status)),
                  ],
                  onChanged: (v) => setState(() => _status = v ?? _status),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  key: const Key('project-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_isEdit ? 'Save changes' : 'Create project'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full palette dialog — a Material color grid, still no hex in sight.
class _ColorGridDialog extends StatelessWidget {
  const _ColorGridDialog({required this.selectedHex});

  final String selectedHex;

  @override
  Widget build(BuildContext context) {
    final colors = <Color>[
      for (final primary in Colors.primaries) ...[
        primary.shade300,
        primary.shade600,
        primary.shade900,
      ],
      Colors.blueGrey.shade700,
      Colors.brown.shade600,
      Colors.grey.shade700,
    ];
    return AlertDialog(
      title: const Text('Pick a color'),
      content: SizedBox(
        width: 320,
        child: GridView.count(
          shrinkWrap: true,
          crossAxisCount: 6,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: [
            for (final color in colors)
              _ColorSwatchDot(
                color: color,
                selected: _hexOf(color) == selectedHex,
                onTap: () => Navigator.of(context).pop(_hexOf(color)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _MoreColorsButton extends StatelessWidget {
  const _MoreColorsButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
        child: const Icon(Icons.palette_outlined, size: 20),
      ),
    );
  }
}

class _ColorSwatchDot extends StatelessWidget {
  const _ColorSwatchDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: selected
              ? Border.all(
                  color: Theme.of(context).colorScheme.onSurface,
                  width: 3,
                )
              : null,
        ),
        child: selected
            ? const Icon(Icons.check, size: 18, color: Colors.white)
            : null,
      ),
    );
  }
}
