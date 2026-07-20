import 'package:flutter/material.dart';

import '../../../i18n/i18n.dart';
import '../data/project.dart';
import 'project_edit_sheet.dart';

/// Sentinel dropdown value for the inline "+ Add project" entry (OPH-163).
/// Never a real id (ULIDs are 26 chars of Crockford base32).
const String kCreateProjectValue = '__create_project__';

/// Shared project-picker entries for the task create sheet and task detail
/// (OPH-106) so the two never drift. 'No project' plus one row per project
/// (its color dot leads the name).
///
/// Archived projects are excluded (OPH-110) — EXCEPT when one is the task's
/// current value, in which case it stays selectable, suffixed '(archived)', so
/// the value is never silently dropped and can still be cleared.
///
/// With [withCreate] the list ends in "+ Add project" (round 8, OPH-163):
/// creating a project must not require leaving the flow you are in.
List<DropdownMenuItem<String?>> projectDropdownItems(
  List<Project> projects, {
  String? currentValue,
  bool withCreate = false,
}) {
  final visible = projects.where(
    (p) => p.status != 'archived' || p.id == currentValue,
  );
  return [
    DropdownMenuItem<String?>(value: null, child: Text('project.none'.tr())),
    for (final project in visible)
      DropdownMenuItem<String?>(
        value: project.id,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(backgroundColor: project.color, radius: 6),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                project.status == 'archived'
                    ? 'project.archivedName'.tr(args: {'name': project.name})
                    : project.name,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    if (withCreate)
      DropdownMenuItem<String?>(
        value: kCreateProjectValue,
        child: Builder(
          builder: (context) {
            final color = Theme.of(context).colorScheme.primary;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, size: 18, color: color),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'project.addFromPicker'.tr(),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
  ];
}

/// The shared project field (create sheet + task detail, OPH-163): a dropdown
/// whose last entry creates a project inline via [ProjectEditSheet] and
/// selects it. [onChanged] only ever receives real values (an id or null) —
/// the sentinel is handled here.
///
/// `DropdownButtonFormField` is uncontrolled after its first build, so the
/// field re-seeds itself (epoch key) whenever the outer value changes or an
/// inline create is aborted — the sentinel must never stick as the shown
/// value.
class ProjectPickerField extends StatefulWidget {
  const ProjectPickerField({
    super.key,
    required this.projects,
    required this.value,
    required this.onChanged,
    this.decoration,
  });

  final List<Project> projects;
  final String? value;
  final ValueChanged<String?> onChanged;
  final InputDecoration? decoration;

  @override
  State<ProjectPickerField> createState() => _ProjectPickerFieldState();
}

class _ProjectPickerFieldState extends State<ProjectPickerField> {
  int _epoch = 0;

  @override
  void didUpdateWidget(ProjectPickerField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _epoch++;
  }

  Future<void> _handle(String? picked) async {
    if (picked != kCreateProjectValue) {
      widget.onChanged(picked);
      return;
    }
    final createdId = await showProjectEditSheet(context);
    if (!mounted) return;
    // Re-seed so an aborted create falls back to the previous selection
    // instead of displaying the sentinel row as if it were a project.
    setState(() => _epoch++);
    if (createdId != null) widget.onChanged(createdId);
  }

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String?>(
      key: ValueKey('aw-project-field-$_epoch-${widget.value}'),
      isExpanded: true,
      initialValue: widget.value,
      decoration: widget.decoration,
      items: projectDropdownItems(
        widget.projects,
        currentValue: widget.value,
        withCreate: true,
      ),
      onChanged: _handle,
    );
  }
}
