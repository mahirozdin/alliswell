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
    // OPH-396 (U-46): a light bulb — the section is "Fikirler" (ideas) in
    // Turkish, and a tray read as an e-mail inbox to two personas.
    icon: Icons.lightbulb_outline,
    selectedIcon: Icons.lightbulb,
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
    // OPH-396 (U-46): a paperclip, not a second folder — Projects' folder
    // and this one were the same silhouette at 24 px in an unlabelled bar.
    icon: Icons.attach_file,
    selectedIcon: Icons.attach_file,
  ),

  /// The service desk (EE-084). LAST on purpose: the branch list and this enum
  /// are index-identical, so appending is the one edit that cannot renumber a
  /// branch somebody's shell is currently sitting on.
  ///
  /// It is also the first section that is not always DRAWN. Whether it appears
  /// is decided per install, so the shell distinguishes "which sections exist"
  /// (this enum, and the branches) from "which sections are on screen"
  /// (`visibleSections`) — see [AppSection.hiddenWithoutEntitlement]. Since
  /// EE-290 the license is not enough: the desk is a team's, so it is drawn
  /// only in a team's window (the shell's `itsm` argument says both).
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

/// The sections this install draws, in enum order. [itsm] is whether THIS
/// window offers the service desk — the license and a team's address together
/// (EE-290), not the license alone.
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

// ── The phone capsule's slots (OPH-396, ADR-0062 §2) ─────────────────────────

/// The phone capsule never holds more than five slots: past five sections
/// each slot would fall under DESIGN G4's 48 dp at 360 dp.
const int kAwMaxPhoneTabs = 5;

/// Which drawn sections get their own slot on a phone, and which move behind
/// the last slot, "More". Up to five every section is a slot; past five the
/// first four keep theirs and the rest open from "More" — in enum order, so
/// the sections people use most (Home, Inbox, Projects, Notes) never move.
({List<AppSection> direct, List<AppSection> overflow}) phoneTabLayout(
  List<AppSection> visible,
) {
  if (visible.length <= kAwMaxPhoneTabs) {
    return (direct: visible, overflow: const []);
  }
  return (
    direct: visible.sublist(0, kAwMaxPhoneTabs - 1),
    overflow: visible.sublist(kAwMaxPhoneTabs - 1),
  );
}
