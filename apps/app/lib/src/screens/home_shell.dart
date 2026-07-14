import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../sections.dart';
import '../widgets/glass.dart';

/// Adaptive shell: frosted-glass navigation rail on wide layouts
/// (desktop/web/tablet), frosted-glass bottom bar on narrow ones (phones).
/// Glass lives only here, in the chrome layer — content stays solid
/// (docs/DESIGN.md).
class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _goBranch(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 800;
        if (isWide) {
          return Scaffold(
            backgroundColor: Colors.transparent,
            body: Row(
              children: [
                GlassSurface(
                  edge: GlassEdge.right,
                  child: SafeArea(
                    child: NavigationRail(
                      extended: constraints.maxWidth >= 1160,
                      labelType: constraints.maxWidth >= 1160
                          ? NavigationRailLabelType.none
                          : NavigationRailLabelType.all,
                      selectedIndex: navigationShell.currentIndex,
                      onDestinationSelected: _goBranch,
                      minWidth: 84,
                      groupAlignment: -0.9,
                      destinations: [
                        for (final section in AppSection.values)
                          NavigationRailDestination(
                            icon: Tooltip(
                              message: section.description,
                              waitDuration: const Duration(milliseconds: 600),
                              child: Icon(section.icon),
                            ),
                            selectedIcon: Icon(section.selectedIcon),
                            label: Text(section.title),
                          ),
                      ],
                    ),
                  ),
                ),
                Expanded(child: navigationShell),
              ],
            ),
          );
        }
        return Scaffold(
          backgroundColor: Colors.transparent,
          extendBody: true,
          body: navigationShell,
          bottomNavigationBar: GlassSurface(
            edge: GlassEdge.top,
            child: SafeArea(
              top: false,
              child: NavigationBar(
                selectedIndex: navigationShell.currentIndex,
                onDestinationSelected: _goBranch,
                destinations: [
                  for (final section in AppSection.values)
                    NavigationDestination(
                      icon: Icon(section.icon),
                      selectedIcon: Icon(section.selectedIcon),
                      label: section.title,
                      tooltip: section.title,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Shared app bar for section screens with quick access to Settings.
AppBar buildSectionAppBar(BuildContext context, String title) {
  return AppBar(
    title: Text(title),
    actions: [
      IconButton(
        icon: const Icon(Icons.settings_outlined),
        tooltip: 'Settings',
        onPressed: () => context.push('/settings'),
      ),
      const SizedBox(width: 4),
    ],
  );
}
