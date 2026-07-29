import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../i18n/i18n.dart';
import '../../../widgets/color_swatch_dot.dart';
import '../../../widgets/status_views.dart';
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

// OPH-193 (round 10 #8): there is no status picker here any more.
//
// It existed only in EDIT mode — the same object had two different forms — and
// it printed the raw server enum ('active' / 'paused' / 'completed') at the
// user in whatever language they were reading. It also offered a second way to
// change a project's state that skipped the archive flow's cascade question.
//
// A user has two project states: OPEN and ARCHIVED, and archiving is its own
// flow (OPH-110). `paused`/`completed` stay valid in the server enum — no
// migration, nothing breaks — but the app neither produces nor shows them, and
// anything not archived simply behaves as open (BLUEPRINT §4.2).

String _hexOf(Color color) =>
    '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

/// Opens the create (project == null) or edit sheet. Resolves to the CREATED
/// project's id (OPH-163 — the picker selects it inline); null on edit/cancel.
Future<String?> showProjectEditSheet(BuildContext context, {Project? project}) {
  return showModalBottomSheet<String>(
    context: context,
    // OPH-212: the ROOT navigator. Pushed into a shell branch, a sheet
    // renders UNDER the shell's own glass bar and FAB — they are painted by
    // the Scaffold that owns the branch, above its body.
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 560),
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
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.project != null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.project?.name ?? '');
    _colorHex = widget.project?.colorRgb.toUpperCase() ?? kProjectPalette.first;
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
    // No `status`: a project's state changes through the archive flow only.
    final body = {'name': _name.text.trim(), 'colorRgb': _colorHex};
    try {
      String? createdId;
      if (_isEdit) {
        await controller.updateProject(widget.project!.id, body);
      } else {
        createdId = await controller.createProject(body);
      }
      if (mounted) Navigator.of(context).pop(createdId);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } on Object {
      setState(() => _error = 'project.genericError'.tr());
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
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _isEdit ? 'project.edit'.tr() : 'project.new'.tr(),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                autofocus: !_isEdit,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(labelText: 'project.name'.tr()),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'project.nameRequired'.tr()
                    : null,
              ),
              const SizedBox(height: 16),
              Text(
                'project.color'.tr(),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final swatch in kProjectPalette)
                    AwColorSwatchDot(
                      color: colorFromRgbHex(swatch),
                      selected: _colorHex == swatch,
                      onTap: () => setState(() => _colorHex = swatch),
                    ),
                  // A color picked from the full grid shows as its own swatch.
                  if (!knownColor)
                    AwColorSwatchDot(
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
              if (_error != null) ...[
                const SizedBox(height: 12),
                AwInlineError(
                  message: _error!,
                  textKey: const Key('project-error'),
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
                    : Text(
                        _isEdit
                            ? 'project.saveChanges'.tr()
                            : 'project.create'.tr(),
                      ),
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
      title: Text('project.pickColor'.tr()),
      content: SizedBox(
        width: 320,
        child: GridView.count(
          shrinkWrap: true,
          crossAxisCount: 6,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: [
            for (final color in colors)
              AwColorSwatchDot(
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
          child: Text('common.cancel'.tr()),
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
      child: Tooltip(
        message: 'project.moreColors'.tr(),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Theme.of(context).colorScheme.outline),
          ),
          child: Icon(
            Icons.palette_outlined,
            size: 20,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
