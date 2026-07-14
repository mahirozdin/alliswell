import 'package:flutter/material.dart';

/// Top-level navigation sections of the app shell (feedback round 1:
/// Home replaces Today/Upcoming as the single chronological view, and
/// Calendar gets its own tab).
enum AppSection {
  home(
    title: 'Home',
    path: '/home',
    icon: Icons.space_dashboard_outlined,
    selectedIcon: Icons.space_dashboard,
    description: 'Everything at a glance — overdue, today and beyond.',
  ),
  inbox(
    title: 'Inbox',
    path: '/inbox',
    icon: Icons.inbox_outlined,
    selectedIcon: Icons.inbox,
    description: 'Capture tasks fast, organize them later.',
  ),
  calendar(
    title: 'Calendar',
    path: '/calendar',
    icon: Icons.calendar_month_outlined,
    selectedIcon: Icons.calendar_month,
    description: 'Your month, one day at a time.',
  ),
  projects(
    title: 'Projects',
    path: '/projects',
    icon: Icons.folder_outlined,
    selectedIcon: Icons.folder,
    description: 'Projects with colors, tasks, notes and documents.',
  ),
  notes(
    title: 'Notes',
    path: '/notes',
    icon: Icons.description_outlined,
    selectedIcon: Icons.description,
    description: 'Rich notes, linkable to tasks and projects.',
  );

  const AppSection({
    required this.title,
    required this.path,
    required this.icon,
    required this.selectedIcon,
    required this.description,
  });

  final String title;
  final String path;
  final IconData icon;
  final IconData selectedIcon;
  final String description;
}
