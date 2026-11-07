import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/ee/providers.dart';
import '../features/ee/team_origin.dart';
import '../features/ee/ui/approvals_entry.dart';
import '../features/onboarding/tour.dart';
import '../features/quick_access/ui/quick_access_rail_section.dart';
import '../search/ui/global_search_entry.dart';
import '../sections.dart';
import '../theme/tokens.dart';
import '../widgets/glass.dart';

/// Which sections are DRAWN (EE-084). Not the same list as the branches —
/// `sections.dart` says why that distinction exists.
///
/// EE-290: the service desk is drawn only in a TEAM's window. The license
/// is the instance's, the desk is a team's, and every request endpoint
/// answers only on the team's own address — which `teamOriginProvider`
/// reads from the address this person signed in to and the cached status,
/// so it is right offline. On the hosted service's own address somebody on
/// their own has no desk, no catalogue and nobody to ask: the tab opened
/// onto a list that could not load and a form that could not send.
List<AppSection> shellVisibleSections(WidgetRef ref) => visibleAppSections(
  itsm:
      ref.watch(eeFeatureProvider('itsm')) &&
      ref.watch(teamOriginProvider) != null,
);

/// The wide layout's glass rail panel (OPH-199), shared by the shell and —
/// from [kAwPaneBreakpoint] — every signed-in page opened over it
/// (OPH-405, U-08): Settings, a task opened by its address, a request.
///
/// [selected] is the drawn destination's position, or null on a page that
/// is no section. [navKeys] and [tourAnchors] belong to the shell's own
/// rail alone: the shell stays mounted under a pushed page, and a second
/// rail carrying the same keys or anchors would collide with it.
class AwShellRail extends StatelessWidget {
  const AwShellRail({
    super.key,
    required this.sections,
    required this.selected,
    required this.onSelected,
    required this.extended,
    this.navKeys,
    this.tourAnchors = false,
  });

  final List<AppSection> sections;
  final int? selected;
  final ValueChanged<int> onSelected;
  final bool extended;
  final Map<AppSection, ({GlobalKey icon, GlobalKey selected})>? navKeys;
  final bool tourAnchors;

  @override
  Widget build(BuildContext context) {
    final search = AwGlobalSearchRailEntry(extended: extended);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AwSpace.x3, AwSpace.x3, 0, AwSpace.x3),
      child: GlassSurface(
        floating: true,
        borderRadius: const BorderRadius.all(Radius.circular(AwRadius.xl)),
        child: SafeArea(
          right: false,
          child: NavigationRail(
            extended: extended,
            labelType: extended
                ? NavigationRailLabelType.none
                : NavigationRailLabelType.all,
            selectedIndex: selected,
            onDestinationSelected: onSelected,
            minWidth: kAwRailMinWidth,
            groupAlignment: -0.9,
            // OPH-374: search everywhere heads the rail — the first thing on
            // the left, as in every desktop app with a palette (DESIGN §40 P1).
            leading: tourAnchors
                ? TourAnchor(target: TourTarget.search, child: search)
                : search,
            // OPH-199: the shortcut section sits right under the
            // destinations. `scrollable` is not optional — a full rail on a
            // short window would otherwise overflow.
            scrollable: true,
            trailing: SizedBox(
              // The rail lives in an unbounded Row, and `minExtendedWidth` is
              // only a floor, so a long shortcut title would otherwise widen
              // the whole rail.
              width: extended ? 256 : kAwRailMinWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // EE-294: Approvals, directly under Requests — the rail's
                  // last destination. A link rather than a section
                  // (`approvals_entry.dart` says why), drawn only for
                  // approval authority.
                  EeApprovalsRailEntry(extended: extended),
                  extended
                      ? const QuickAccessRailSection()
                      : const QuickAccessRailButton(),
                ],
              ),
            ),
            destinations: [
              for (final section in sections)
                NavigationRailDestination(
                  icon: KeyedSubtree(
                    key: navKeys?[section]?.icon,
                    child: Tooltip(
                      message: section.description,
                      waitDuration: const Duration(milliseconds: 600),
                      child: Icon(section.icon),
                    ),
                  ),
                  selectedIcon: KeyedSubtree(
                    key: navKeys?[section]?.selected,
                    child: Icon(section.selectedIcon),
                  ),
                  label: Text(section.title),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A signed-in page opened over the shell keeps the rail from
/// [kAwPaneBreakpoint] (OPH-405, U-08): on a desktop, opening Settings or a
/// task by its link no longer drops the navigation. No destination is
/// selected — the page is not a section — and choosing one goes to it.
/// Below the breakpoint the page is drawn as before, with its own back
/// button the only way out.
class AwRailFrame extends ConsumerWidget {
  const AwRailFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < kAwPaneBreakpoint) return child;
    final sections = shellVisibleSections(ref);
    return Row(
      key: const Key('rail-frame'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AwShellRail(
          sections: sections,
          selected: null,
          extended: width >= kAwExtendedRailBreakpoint,
          onSelected: (i) => GoRouter.of(context).go(sections[i].path),
        ),
        // OPH-359's rule: the page is its own semantics container, or a
        // route barrier inside it would drop the rail from the tree.
        Expanded(child: Semantics(container: true, child: child)),
      ],
    );
  }
}
