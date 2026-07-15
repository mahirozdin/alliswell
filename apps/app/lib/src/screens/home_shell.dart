import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../sections.dart';
import '../sync/providers.dart';
import '../sync/sync_engine.dart';
import '../widgets/glass.dart';

/// Adaptive shell: frosted-glass navigation rail on wide layouts
/// (desktop/web/tablet), frosted-glass bottom bar on narrow ones (phones).
/// Glass lives only here, in the chrome layer — content stays solid
/// (docs/DESIGN.md).
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _goBranch(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  /// OPH-056: a sync push the server refused (or trimmed via LWW) surfaces
  /// as a snackbar — the replica already shows the server's version by the
  /// time the user reads it.
  String _conflictMessage(SyncConflict conflict) {
    if (conflict.conflictCopyNoteId != null) {
      return 'Note edited elsewhere — your version was kept as a conflicted copy.';
    }
    if (conflict.discardedFields.isNotEmpty) {
      return 'Some changes were overridden by a newer edit '
          '(${conflict.discardedFields.join(', ')}).';
    }
    if (conflict.status == 'rejected') {
      return 'A change was rejected by the server'
          '${conflict.errorCode != null ? ' (${conflict.errorCode})' : ''}.';
    }
    return 'A change conflicted with a newer edit and was not applied.';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(syncConflictsProvider, (_, next) {
      final conflict = next.value;
      if (conflict == null) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(_conflictMessage(conflict))));
    });
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
