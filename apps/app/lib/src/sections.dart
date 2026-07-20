import 'package:flutter/material.dart';

import 'i18n/i18n.dart';

/// Top-level navigation sections of the app shell (feedback round 1: Home
/// replaces Today/Upcoming as the single chronological view; round 8/OPH-162:
/// the Calendar tab is GONE — Home's month grid + selected-day group carry its
/// whole job, and a second calendar surface was dead weight).
///
/// `title`/`description` are localized getters (OPH-122) — the enum stores i18n
/// keys so the labels follow the active language.
enum AppSection {
  home(
    titleKey: 'nav.home',
    descriptionKey: 'nav.homeDesc',
    path: '/home',
    icon: Icons.space_dashboard_outlined,
    selectedIcon: Icons.space_dashboard,
  ),
  inbox(
    titleKey: 'nav.inbox',
    descriptionKey: 'nav.inboxDesc',
    path: '/inbox',
    icon: Icons.inbox_outlined,
    selectedIcon: Icons.inbox,
  ),
  projects(
    titleKey: 'nav.projects',
    descriptionKey: 'nav.projectsDesc',
    path: '/projects',
    icon: Icons.folder_outlined,
    selectedIcon: Icons.folder,
  ),
  notes(
    titleKey: 'nav.notes',
    descriptionKey: 'nav.notesDesc',
    path: '/notes',
    icon: Icons.description_outlined,
    selectedIcon: Icons.description,
  );

  const AppSection({
    required this.titleKey,
    required this.descriptionKey,
    required this.path,
    required this.icon,
    required this.selectedIcon,
  });

  final String titleKey;
  final String descriptionKey;
  final String path;
  final IconData icon;
  final IconData selectedIcon;

  /// Localized nav label.
  String get title => titleKey.tr();

  /// Localized one-line description (used by the onboarding tour, OPH-111).
  String get description => descriptionKey.tr();
}
