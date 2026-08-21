import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/persisted_prefs.dart';
import '../features/ee/providers.dart';
import '../features/ee/ui/team_chip.dart';
import '../features/notes/ui/markdown_import_screen.dart';
import '../features/calendar/apple/providers.dart';
import '../features/ai/data/ai_context_builder.dart';
import '../features/ai/data/ai_models.dart';
import '../features/ai/data/share_intent.dart';
import '../features/ai/data/share_log.dart';
import '../features/ai/providers.dart';
import '../features/ai/ui/ai_bubble.dart';
import '../features/ai/ui/ai_bubble_controller.dart';
import '../features/ai/ui/ai_fab.dart';
import '../features/tasks/data/task_text.dart';
import '../features/workspaces/workspaces.dart';
import '../features/onboarding/tour.dart';
import '../features/onboarding/tour_overlay.dart';
import '../features/projects/ui/project_edit_sheet.dart';
import '../features/quick_access/ui/quick_access_rail_section.dart';
import '../features/tasks/providers.dart';
import '../features/tasks/ui/task_create_sheet.dart';
import '../features/widgets/widget_bridge.dart';
import '../i18n/i18n.dart';
import '../notifications/alarm_overlay.dart';
import '../notifications/alarm_ring_screen.dart';
import '../notifications/providers.dart';
import '../sections.dart';
import '../sync/providers.dart';
import '../sync/sync_engine.dart';
import '../theme/tokens.dart';
import '../widgets/document_surface.dart';
import '../widgets/glass.dart';
import '../widgets/refreshable.dart';

/// Adaptive shell: floating Liquid Glass chrome — a glass rail panel on wide
/// layouts (desktop/web/tablet), a glass capsule bottom bar on narrow ones
/// (phones). Navigation floats in its own functional layer above the content,
/// which scrolls beneath it (docs/DESIGN.md §4); content itself stays solid.
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
  /// action (Inbox) get none.
  /// OPH-223 (DESIGN §24 AI1): two FABs, two corners. The AI FAB sits
  /// bottom-left, the create FAB stays bottom-right; a full-width Row with
  /// space-between is the standard two-corner recipe. When AI is off, the
  /// section FAB is returned alone (unchanged behavior).
  Widget? _fabBar(BuildContext context, WidgetRef ref) {
    // OPH-271: the note editor takes the screen, so nothing floats over it —
    // neither "new note" nor the AI button. Someone writing is not shopping
    // for a second thing to start.
    if (awIsDocumentRoute(GoRouterState.of(context).uri.path)) return null;
    final section = _sectionFab(context, ref);
    if (!aiFabVisible(ref)) return section;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AwSpace.x2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const AiFab(),
          if (section != null) section else const SizedBox.shrink(),
        ],
      ),
    );
  }

  /// EE-052: a create button belongs to a verb, and a role that lacks the
  /// verb should not be shown the button at all.
  ///
  /// HIDDEN rather than disabled, and only here: a greyed-out "+" invites the
  /// question "why can't I?" every time the screen is drawn, while a create
  /// affordance that is simply absent reads as "this is not your job here".
  /// Controls that act on something already on screen are disabled instead
  /// (the urgent-alarm switch), because there the thing is visible and its
  /// unavailability is the information.
  Widget? _sectionFab(BuildContext context, WidgetRef ref) {
    return switch (AppSection.values[navigationShell.currentIndex]) {
      AppSection.home when !ref.watch(canProvider('tasks.create')) => null,
      AppSection.projects when !ref.watch(canProvider('projects.create')) =>
        null,
      AppSection.notes when !ref.watch(canProvider('notes.create')) => null,
      AppSection.home => FloatingActionButton(
        tooltip: 'shell.fabNewTask'.tr(),
        onPressed: () {
          // Day-only prefill lands on the user's default task time (OPH-161).
          final day = ref.read(selectedDayProvider);
          showTaskCreateSheet(
            context,
            initialDue: day == null
                ? null
                : applyDefaultTaskTime(day, ref.read(defaultTaskTimeProvider)),
          );
        },
        child: const Icon(Icons.add),
      ),
      AppSection.projects => FloatingActionButton(
        tooltip: 'shell.fabNewProject'.tr(),
        onPressed: () => showProjectEditSheet(context),
        child: const Icon(Icons.add),
      ),
      AppSection.notes => FloatingActionButton(
        tooltip: 'shell.fabNewNote'.tr(),
        onPressed: () => context.go('/notes/new'),
        child: const Icon(Icons.add),
      ),
      AppSection.inbox || AppSection.files => null,
    };
  }

  /// OPH-056: a sync push the server refused (or trimmed via LWW) surfaces
  /// as a snackbar — the replica already shows the server's version by the
  /// time the user reads it.
  String _conflictMessage(SyncConflict conflict) {
    if (conflict.conflictVersionId != null) {
      return 'sync.noteConflict'.tr();
    }
    if (conflict.discardedFields.isNotEmpty) {
      return 'sync.fieldsOverridden'.tr(
        args: {'fields': conflict.discardedFields.join(', ')},
      );
    }
    if (conflict.status == 'rejected') {
      return 'sync.rejected'.tr(
        args: {
          'code': conflict.errorCode != null ? ' (${conflict.errorCode})' : '',
        },
      );
    }
    return 'sync.conflicted'.tr();
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
    // OPH-130: republish the home-screen widget snapshot on task/project change
    // (self-disables off iOS/Android/macOS).
    ref.watch(widgetSyncProvider);
    ref.listen(syncConflictsProvider, (_, next) {
      final conflict = next.value;
      if (conflict == null) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(_conflictMessage(conflict))));
    });

    // Share target (OPH-225): keep the binder alive while the shell shows — it
    // only mounts signed in, so a cold-start share lands after the session
    // exists. When a payload arrives, take it (once) and route it.
    ref.watch(shareBinderProvider);
    ref.listen(pendingSharePayloadProvider, (_, next) {
      if (next == null) return;
      final payload = ref.read(pendingSharePayloadProvider.notifier).take();
      if (payload != null) unawaited(_routeShare(context, ref, payload));
    });

    // Round 16 follow-up: the OS opened a .md file with us. The viewer TAKES
    // the pending document itself, so this only has to get the user there —
    // and only when they are not already looking at it.
    ref.listen(pendingMarkdownProvider, (_, next) {
      if (next == null) return;
      final location = GoRouterState.of(context).uri.path;
      if (location == '/notes/import') return;
      GoRouter.of(context).push('/notes/import');
    });

    // First-run onboarding tour (OPH-111): try to auto-start once after the
    // first frame (no-op in tests / when already seen), and overlay it when
    // running.
    final tour = ref.watch(tourControllerProvider);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => ref.read(tourControllerProvider.notifier).maybeAutoStart(),
    );

    // Foreground alarm ring (OPH-143): when an urgent alarm comes due while the
    // app is open, it takes over the screen — desktop/web's only alarm surface,
    // and the companion to the OS notification on mobile. Gated OFF in tests
    // (alarmOverlayAutoShowProvider) so a due alarm never covers the app.
    final ringing = ref.watch(alarmOverlayControllerProvider).ringing;

    final shell = LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= kAwWideBreakpoint;
        final extendedRail = constraints.maxWidth >= kAwExtendedRailBreakpoint;
        if (isWide) {
          return Scaffold(
            backgroundColor: Colors.transparent,
            floatingActionButton: _fabBar(context, ref),
            floatingActionButtonLocation: aiFabVisible(ref)
                ? FloatingActionButtonLocation.centerFloat
                : FloatingActionButtonLocation.endFloat,
            body: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AwSpace.x3,
                    AwSpace.x3,
                    0,
                    AwSpace.x3,
                  ),
                  child: GlassSurface(
                    floating: true,
                    borderRadius: const BorderRadius.all(
                      Radius.circular(AwRadius.xl),
                    ),
                    child: SafeArea(
                      right: false,
                      child: NavigationRail(
                        extended: extendedRail,
                        labelType: extendedRail
                            ? NavigationRailLabelType.none
                            : NavigationRailLabelType.all,
                        selectedIndex: navigationShell.currentIndex,
                        onDestinationSelected: _goBranch,
                        minWidth: 84,
                        groupAlignment: -0.9,
                        // OPH-199: the shortcut section sits right under the
                        // destinations. `scrollable` is not optional — a full
                        // rail on a short window would otherwise overflow.
                        scrollable: true,
                        trailing: SizedBox(
                          // The rail lives in an unbounded Row, and
                          // `minExtendedWidth` is only a floor, so a long
                          // shortcut title would otherwise widen the whole rail.
                          width: extendedRail ? 256 : 84,
                          child: extendedRail
                              ? const QuickAccessRailSection()
                              : const QuickAccessRailButton(),
                        ),
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
                ),
                Expanded(child: navigationShell),
              ],
            ),
          );
        }
        return Scaffold(
          backgroundColor: Colors.transparent,
          extendBody: true,
          floatingActionButton: _fabBar(context, ref),
          floatingActionButtonLocation: aiFabVisible(ref)
              ? FloatingActionButtonLocation.centerFloat
              : FloatingActionButtonLocation.endFloat,
          body: navigationShell,
          bottomNavigationBar: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AwSpace.x3),
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.only(bottom: AwSpace.x3),
              child: GlassSurface(
                floating: true,
                borderRadius: const BorderRadius.all(
                  Radius.circular(AwRadius.pill),
                ),
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
          ),
        );
      },
    );

    if (!tour.running && ringing == null) return shell;
    return Stack(
      children: [
        shell,
        if (tour.running)
          Positioned.fill(
            child: TourOverlay(
              state: tour,
              anchorRect: _anchorRect(tour.current),
              onNext: () => ref.read(tourControllerProvider.notifier).next(),
              onSkip: () => ref.read(tourControllerProvider.notifier).skip(),
            ),
          ),
        // An urgent alarm outranks onboarding — layered last, so it is on top.
        if (ringing != null)
          Positioned.fill(
            child: AlarmRingScreen(
              alarm: ringing,
              onHandled: (id) =>
                  ref.read(alarmOverlayControllerProvider.notifier).handled(id),
            ),
          ),
      ],
    );
  }
}

/// Where shared text goes (OPH-243).
///
/// With AI configured, the bubble is the right destination: it can turn a
/// paragraph into a structured task and put it behind the confirm card.
///
/// Without it, sharing is a feature the account cannot use, and round 17's
/// second decision (owner, 2026-08-10) is to **say so** rather than quietly
/// offer a lesser version. That reverses this task's own first decision — the
/// pre-filled create sheet — deliberately and on both platforms, including
/// Android where the old path worked fine.
///
/// What it must NOT do is lose the text. The whole point of round 17 #1 was
/// that a share used to vanish, so the capture happens FIRST and the
/// explanation second: if the dialog is swallowed by a rotation or a route
/// change, the words are already an Inbox task. `captureToInbox` touches no AI.
Future<void> _routeShare(
  BuildContext context,
  WidgetRef ref,
  SharedPayload payload,
) async {
  final status = await _aiStatusForShare(ref);
  if (!context.mounted) return;

  if (status.configured) {
    ref
        .read(shareLogProvider)
        .record(
          event: ShareLogEvent.consumed,
          payloadKind: payload.url != null
              ? ShareLogKind.url
              : ShareLogKind.text,
          detail: 'bubble',
        );
    await showAiBubble(context, shared: payload);
    return;
  }

  await ref
      .read(aiBubbleControllerProvider.notifier)
      .captureToInbox(shareTextOf(payload.text, url: payload.url));
  ref
      .read(shareLogProvider)
      .record(
        event: ShareLogEvent.consumed,
        payloadKind: payload.url != null ? ShareLogKind.url : ShareLogKind.text,
        detail: 'no_provider',
      );
  if (!context.mounted) return;
  await _showNoAiProviderDialog(context);
}

/// "You need an AI provider" — a dialog, not a snackbar.
///
/// The user just performed a deliberate cross-app action and the app came up
/// for it; a four-second strip that a route change can swallow is how round 18
/// gets its own #1. It names the Inbox on purpose: a silent capture the user is
/// never told about is a black hole, not a safety net.
Future<void> _showNoAiProviderDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    // Round 13 #2 / OPH-212: inside a shell branch the Scaffold's own bar and
    // FAB paint over anything pushed on the branch navigator.
    useRootNavigator: true,
    builder: (dialogContext) => AlertDialog(
      key: const Key('share-no-provider'),
      title: Text('ai.share.noProviderTitle'.tr()),
      content: Text('ai.share.noProviderBody'.tr()),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text('ai.share.dismiss'.tr()),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            // The Inbox is a shell BRANCH, not a path — pushing it would stack
            // a second shell on top of the first one.
            context.go(AppSection.inbox.path);
          },
          child: Text('ai.share.openInbox'.tr()),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            context.push('/settings/ai');
          },
          child: Text('ai.settings.addProvider'.tr()),
        ),
      ],
    ),
  );
}

/// The status, without making the user wait on a network call.
///
/// The hazard that used to head this list — "`aiStatusProvider` returns
/// `disabled` while the workspace is still loading" — is fixed at the source
/// now (OPH-243: the provider reads its localKv cache BEFORE that guard), so a
/// returning AI user is recognised on the first frame instead of being told
/// they have no AI.
///
/// What remains: the provider awaits `/ai/status` with no timeout of its own,
/// so awaiting it blindly would let a slow network hold a share hostage. An
/// already-resolved value is used as-is; otherwise we wait briefly and then
/// treat AI as absent. Being wrong that way is one-directional and cheap — the
/// text still lands in the Inbox and the dialog says why.
Future<AiStatus> _aiStatusForShare(WidgetRef ref) async {
  try {
    await ref.read(workspacesProvider.future).timeout(_shareStatusBudget);
    final resolved = ref.read(aiStatusProvider).value;
    if (resolved != null) return resolved;
    return await ref.read(aiStatusProvider.future).timeout(_shareStatusBudget);
  } on Object {
    return AiStatus.disabled;
  }
}

const _shareStatusBudget = Duration(seconds: 2);

/// Shared app bar for section screens with quick access to Settings.
///
/// [onRefresh] adds the pointer-only refresh action (OPH-171, DESIGN §15 R5):
/// phones pull the list, but a mouse wheel cannot overscroll — so wide layouts
/// get the same capability as a button. Same handler as the gesture.
AppBar buildSectionAppBar(
  BuildContext context,
  String title, {
  Future<bool> Function()? onRefresh,
  List<Widget> leadingActions = const [],

  /// Section-specific controls, immediately left of the settings button
  /// (OPH-213, DESIGN §16 H1): the app bar earns its pin by carrying the view
  /// controls, instead of a second pinned row eating the phone screen.
  List<Widget> trailingActions = const [],
}) {
  final wide = MediaQuery.sizeOf(context).width >= kAwWideBreakpoint;
  return AppBar(
    title: Text(title),
    actions: [
      // EE-018: which team this window belongs to. Renders nothing on a CE
      // server or a plain host, so the community build is untouched.
      const AwTeamChip(),
      ...leadingActions,
      if (onRefresh != null && wide) AwRefreshAction(onRefresh: onRefresh),
      ...trailingActions,
      IconButton(
        icon: const Icon(Icons.settings_outlined),
        tooltip: 'shell.settingsTooltip'.tr(),
        onPressed: () => context.push('/settings'),
      ),
      const SizedBox(width: 4),
    ],
  );
}
