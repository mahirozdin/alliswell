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
  ),
  files(
    titleKey: 'nav.files',
    descriptionKey: 'nav.filesDesc',
    path: '/files',
    icon: Icons.folder_copy_outlined,
    selectedIcon: Icons.folder_copy,
  ),

  /// The service desk (EE-084). LAST on purpose: the branch list and this enum
  /// are index-identical, so appending is the one edit that cannot renumber a
  /// branch somebody's shell is currently sitting on.
  ///
  /// It is also the first section that is not always DRAWN. Whether it appears
  /// is decided per install, so the shell distinguishes "which sections exist"
  /// (this enum, and the branches) from "which sections are on screen"
  /// (`visibleSections`) — see [AppSection.hiddenWithoutEntitlement].
  tickets(
    titleKey: 'nav.tickets',
    descriptionKey: 'nav.ticketsDesc',
    path: '/tickets',
    icon: Icons.support_agent_outlined,
    selectedIcon: Icons.support_agent,
    hiddenWithoutEntitlement: true,
  );

  const AppSection({
    required this.titleKey,
    required this.descriptionKey,
    required this.path,
    required this.icon,
    required this.selectedIcon,
    this.hiddenWithoutEntitlement = false,
  });

  /// True for a section that exists in the app but is only DRAWN where the
  /// server offers the feature. The branch behind it still exists — removing
  /// one would renumber every branch after it — so this flag only ever changes
  /// what the navigation shows.
  final bool hiddenWithoutEntitlement;

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

// ── Drawn sections vs BRANCHES (EE-084) ──────────────────────────────────────
//
// These were one list until the service desk arrived, and several places relied
// on that: `NavigationBar.selectedIndex` is a position among the DESTINATIONS,
// `goBranch` takes a position among the BRANCHES, and both were
// `AppSection.values`.
//
// A section that is not always drawn breaks the identity — the i-th destination
// stops being the i-th branch — and the failure is SILENT: every tab after the
// hidden one opens the wrong screen, with no compiler error and no test that
// would notice, because index arithmetic is invisible to both.
//
// So the conversion is explicit, in one direction each, and lives here rather
// than inside the shell's build method: a pure function is the only shape this
// can have that a test can hold still.
//
// NOTE, and it is the honest half: `tickets` is the LAST enum member, so
// hiding it shifts nothing today and every mapping below is currently the
// identity. That is luck, not design — the functions exist so the next hidden
// section, wherever it lands, cannot quietly renumber the ones after it, and
// `sections_test.dart` pins that with a middle-hidden case rather than with
// today's list.

/// The sections this install draws, in enum order.
List<AppSection> visibleAppSections({required bool itsm}) => [
  for (final section in AppSection.values)
    if (!section.hiddenWithoutEntitlement || itsm) section,
];

/// Destination position → branch index.
int branchIndexFor(List<AppSection> visible, int destinationIndex) =>
    AppSection.values.indexOf(visible[destinationIndex]);

/// Branch index → destination position, or -1 while the shell sits on a branch
/// that is not drawn. `NavigationBar` renders -1 as "nothing selected" rather
/// than throwing, which is the honest look for a state that should not happen
/// but must not crash if it does.
int destinationIndexFor(List<AppSection> visible, int branchIndex) =>
    visible.indexOf(AppSection.values[branchIndex]);
