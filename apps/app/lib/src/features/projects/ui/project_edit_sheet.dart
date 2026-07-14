import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../data/project.dart';
import '../providers.dart';

/// Brand-friendly starting palette; the hex field accepts any #RRGGBB.
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
  late final TextEditingController _description;
  late final TextEditingController _hex;
  late String _status;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.project != null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.project?.name ?? '');
    _description = TextEditingController(
      text: widget.project?.description ?? '',
    );
    _hex = TextEditingController(
      text: widget.project?.colorRgb ?? kProjectPalette.first,
    );
    _status = widget.project?.status ?? 'active';
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _hex.dispose();
    super.dispose();
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
      'colorRgb': _hex.text.trim().toUpperCase(),
      if (_description.text.trim().isNotEmpty)
        'description': _description.text.trim()
      else if (_isEdit)
        'description': null,
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
                textInputAction: TextInputAction.next,
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
                      selected:
                          _hex.text.trim().toUpperCase() ==
                          swatch.toUpperCase(),
                      onTap: () => setState(() => _hex.text = swatch),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _hex,
                decoration: const InputDecoration(
                  labelText: 'Color (#RRGGBB)',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(v?.trim() ?? '')
                    ? null
                    : 'Use the #RRGGBB format',
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _description,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  border: OutlineInputBorder(),
                ),
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
