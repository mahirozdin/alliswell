import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../sections.dart';

/// Adaptive shell: navigation rail on wide layouts (desktop/web/tablet),
/// bottom navigation bar on narrow ones (phones).
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
            body: Row(
              children: [
                SafeArea(
                  child: NavigationRail(
                    extended: constraints.maxWidth >= 1160,
                    labelType: constraints.maxWidth >= 1160
                        ? NavigationRailLabelType.none
                        : NavigationRailLabelType.all,
                    selectedIndex: navigationShell.currentIndex,
                    onDestinationSelected: _goBranch,
                    destinations: [
                      for (final section in AppSection.values)
                        NavigationRailDestination(
                          icon: Icon(section.icon),
                          selectedIcon: Icon(section.selectedIcon),
                          label: Text(section.title),
                        ),
                    ],
                  ),
                ),
                const VerticalDivider(thickness: 1, width: 1),
                Expanded(child: navigationShell),
              ],
            ),
          );
        }
        return Scaffold(
          body: navigationShell,
          bottomNavigationBar: NavigationBar(
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: _goBranch,
            destinations: [
              for (final section in AppSection.values)
                NavigationDestination(
                  icon: Icon(section.icon),
                  selectedIcon: Icon(section.selectedIcon),
                  label: section.title,
                ),
            ],
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
    ],
  );
}
