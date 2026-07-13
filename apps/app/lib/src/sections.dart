import 'package:flutter/material.dart';

/// Top-level navigation sections of the app shell.
///
/// Each section is a placeholder until its epic lands — `taskRef` points to the
/// backlog item in docs/TASKS.md that will implement it.
enum AppSection {
  inbox(
    title: 'Inbox',
    path: '/inbox',
    icon: Icons.inbox_outlined,
    selectedIcon: Icons.inbox,
    description: 'Capture tasks fast, organize them later.',
    taskRef: 'OPH-037',
  ),
  today(
    title: 'Today',
    path: '/today',
    icon: Icons.today_outlined,
    selectedIcon: Icons.today,
    description: 'Everything due, scheduled or urgent today.',
    taskRef: 'OPH-037',
  ),
  upcoming(
    title: 'Upcoming',
    path: '/upcoming',
    icon: Icons.calendar_month_outlined,
    selectedIcon: Icons.calendar_month,
    description: 'Plan ahead — deadlines and scheduled work.',
    taskRef: 'OPH-037',
  ),
  projects(
    title: 'Projects',
    path: '/projects',
    icon: Icons.folder_outlined,
    selectedIcon: Icons.folder,
    description: 'Projects with colors, tasks, notes and documents.',
    taskRef: 'OPH-036',
  ),
  notes(
    title: 'Notes',
    path: '/notes',
    icon: Icons.description_outlined,
    selectedIcon: Icons.description,
    description: 'Rich notes, linkable to tasks and projects.',
    taskRef: 'OPH-043',
  );

  const AppSection({
    required this.title,
    required this.path,
    required this.icon,
    required this.selectedIcon,
    required this.description,
    required this.taskRef,
  });

  final String title;
  final String path;
  final IconData icon;
  final IconData selectedIcon;
  final String description;
  final String taskRef;
}
