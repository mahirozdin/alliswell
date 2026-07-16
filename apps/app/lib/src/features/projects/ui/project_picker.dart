import 'package:flutter/material.dart';

import '../data/project.dart';

/// Shared project-picker entries for the task create sheet and task detail
/// (OPH-106) so the two never drift. 'No project' plus one row per project
/// (its color dot leads the name).
///
/// Archived projects are excluded (OPH-110) — EXCEPT when one is the task's
/// current value, in which case it stays selectable, suffixed '(archived)', so
/// the value is never silently dropped and can still be cleared.
List<DropdownMenuItem<String?>> projectDropdownItems(
  List<Project> projects, {
  String? currentValue,
}) {
  final visible = projects.where(
    (p) => p.status != 'archived' || p.id == currentValue,
  );
  return [
    const DropdownMenuItem<String?>(value: null, child: Text('No project')),
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
                    ? '${project.name} (archived)'
                    : project.name,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
  ];
}
