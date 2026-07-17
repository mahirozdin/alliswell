import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/calendar/apple/providers.dart';
import '../features/onboarding/tour.dart';
import '../features/onboarding/tour_overlay.dart';
import '../features/projects/ui/project_edit_sheet.dart';
import '../features/tasks/providers.dart';
import '../features/tasks/ui/task_create_sheet.dart';
import '../notifications/providers.dart';
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

  // Per-destination anchors for the tour spotlight (feedback round 5): two keys
  // per section — the unselected `icon` and the `selectedIcon` — because only
  // one of them is mounted at a time. Static so they stay stable across
  // rebuilds (there is one shell).
  static final Map<AppSection, ({GlobalKey icon, GlobalKey selected})>
  _navKeys = {
    for (final s in AppSection.values)
      s: (
        icon: GlobalKey(debugLabel: 'nav-${s.name}'),
        selected: GlobalKey(debugLabel: 'nav-sel-${s.name}'),
      ),
  };

  static Rect? _rectOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// The on-screen rect of the step's specific nav destination — works for both
  /// the bottom bar and the rail (whichever icon is mounted). Null for
  /// welcome/farewell cards or an anchor that isn't laid out yet (graceful).
  static Rect? _anchorRect(TourStep step) {
    final section = step.section;
    if (section == null) return null;
    final keys = _navKeys[section]!;
    return _rectOf(keys.icon) ?? _rectOf(keys.selected);
  }

  void _goBranch(int index) {
    // Selecting a tab always returns to that section's root (OPH-108): tabs are
    // sections, not stacks, so re-tapping AND switching-back both reset to the
    // list. Task detail / settings are pushed on the root navigator (above the
    // shell), so they are unaffected; the note editor flushes its autosave in
    // dispose(), so resetting the Notes branch never loses an edit.
    navigationShell.goBranch(index, initialLocation: true);
  }

  /// The current section's create action, rendered by the shell's OWN Scaffold
  /// so Flutter positions it above the glass bottom bar. The section screens
  /// used to own these FABs, but as nested Scaffolds their FAB was painted
  /// behind the bar and could not be tapped (OPH-101). Sections with no create
  /// action (Inbox, Calendar) get none.
  Widget? _sectionFab(BuildContext context, WidgetRef ref) {
    return switch (AppSection.values[navigationShell.currentIndex]) {
      AppSection.home => FloatingActionButton(
        tooltip: 'New task with options',
        onPressed: () => showTaskCreateSheet(
          context,
          initialDue: ref.read(selectedDayProvider)?.add(
            const Duration(hours: 9),
          ),
        ),
        child: const Icon(Icons.add),
      ),
      AppSection.projects => FloatingActionButton(
        tooltip: 'New project',
        onPressed: () => showProjectEditSheet(context),
        child: const Icon(Icons.add),
      ),
      AppSection.notes => FloatingActionButton(
        tooltip: 'New note',
        onPressed: () => context.go('/notes/new'),
        child: const Icon(Icons.add),
      ),
      AppSection.inbox || AppSection.calendar => null,
    };
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
    // Keep the live sync:changed socket (OPH-057) and the OS notification
    // scheduler (OPH-061) alive while the shell shows.
    ref.watch(syncSocketProvider);
    ref.watch(notificationSchedulerProvider);
    // OPH-078: keep the Apple calendar mirror reconciling while signed in
    // (self-disables off Apple platforms and until access + a calendar exist).
    ref.watch(appleMirrorProvider);
    ref.listen(syncConflictsProvider, (_, next) {
      final conflict = next.value;
      if (conflict == null) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(_conflictMessage(conflict))));
    });

    // First-run onboarding tour (OPH-111): try to auto-start once after the
    // first frame (no-op in tests / when already seen), and overlay it when
    // running.
    final tour = ref.watch(tourControllerProvider);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => ref.read(tourControllerProvider.notifier).maybeAutoStart(),
    );

    final shell = LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 800;
        if (isWide) {
          return Scaffold(
            backgroundColor: Colors.transparent,
            floatingActionButton: _sectionFab(context, ref),
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
                            icon: KeyedSubtree(
                              key: _navKeys[section]!.icon,
                              child: Tooltip(
                                message: section.description,
                                waitDuration: const Duration(
                                  milliseconds: 600,
                                ),
                                child: Icon(section.icon),
                              ),
                            ),
                            selectedIcon: KeyedSubtree(
                              key: _navKeys[section]!.selected,
                              child: Icon(section.selectedIcon),
                            ),
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
          floatingActionButton: _sectionFab(context, ref),
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
                      icon: KeyedSubtree(
                        key: _navKeys[section]!.icon,
                        child: Icon(section.icon),
                      ),
                      selectedIcon: KeyedSubtree(
                        key: _navKeys[section]!.selected,
                        child: Icon(section.selectedIcon),
                      ),
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

    if (!tour.running) return shell;
    return Stack(
      children: [
        shell,
        Positioned.fill(
          child: TourOverlay(
            state: tour,
            anchorRect: _anchorRect(tour.current),
            onNext: () => ref.read(tourControllerProvider.notifier).next(),
            onSkip: () => ref.read(tourControllerProvider.notifier).skip(),
          ),
        ),
      ],
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
