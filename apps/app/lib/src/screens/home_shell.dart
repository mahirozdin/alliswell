import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/ee/providers.dart';
import '../features/ee/team_origin.dart';
import '../features/ee/ui/approvals_entry.dart';
import '../features/ee/ui/team_chip.dart';
import '../features/workspaces/ui/workspace_switcher.dart';
import '../features/notes/ui/markdown_import_screen.dart';
import '../features/calendar/apple/providers.dart';
import '../features/devices/providers.dart';
import '../features/home/home_create.dart';
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
import '../widgets/fab_clearance.dart';
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

  /// Destination position → branch index (EE-084). The two lists stopped being
  /// the same one when the service desk arrived; `sections.dart` holds the
  /// conversion and says why.
  void _goVisible(List<AppSection> visible, int index) =>
      _goBranch(branchIndexFor(visible, index));

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
      // EE-084: no "new request" button on the agent's queue. Opening a ticket
      // means naming a SERVICE, and the catalogue is admin-gated — an agent
      // cannot read it. The requester's own filing surface is EE-087's, and
      // giving this screen a button that could not resolve a destination would
      // be exactly the "greyed-out affordance" this method exists to avoid.
      AppSection.tickets => null,
      AppSection.home when !ref.watch(canProvider('tasks.create')) => null,
      AppSection.projects when !ref.watch(canProvider('projects.create')) =>
        null,
      AppSection.notes when !ref.watch(canProvider('notes.create')) => null,
      AppSection.home => FloatingActionButton(
        tooltip: 'shell.fabNewTask'.tr(),
        // The widget's "+" opens this same sheet (OPH-333) — one function.
        onPressed: () => showHomeTaskCreateSheet(context, ref),
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keep the live sync:changed socket (OPH-057) and the OS notification
    // scheduler (OPH-061) alive while the shell shows — and every engine: in
    // an organisation the device syncs each of the person's units (EE-296).
    ref.watch(syncEnginesProvider);
    ref.watch(syncSocketProvider);
    ref.watch(notificationSchedulerProvider);
    // OPH-309: keep this install's notification-registry row fresh — Epic 30's
    // staleness test reads `last_seen_at` and nothing else.
    ref.watch(deviceRegistrationProvider);
    // OPH-078: keep the Apple calendar mirror reconciling while signed in
    // (self-disables off Apple platforms and until access + a calendar exist).
    ref.watch(appleMirrorProvider);
    // OPH-130: republish the home-screen widget snapshot on task/project change
    // (self-disables off iOS/Android/macOS).
    ref.watch(widgetSyncProvider);
    // EE-225's draft courier and "sent" listener live on the app itself
    // (`AllisWellApp`), not here: a page opened by its address has no shell.
    // EE-084: which sections are DRAWN. Not the same list as the branches —
    // `sections.dart` says why that distinction exists.
    //
    // EE-290: the service desk is drawn only in a TEAM's window. The license
    // is the instance's, the desk is a team's, and every request endpoint
    // answers only on the team's own address — which `teamOriginProvider`
    // reads from the address this person signed in to and the cached status,
    // so it is right offline. On the hosted service's own address somebody on
    // their own has no desk, no catalogue and nobody to ask: the tab opened
    // onto a list that could not load and a form that could not send.
    final visibleSections = visibleAppSections(
      itsm:
          ref.watch(eeFeatureProvider('itsm')) &&
          ref.watch(teamOriginProvider) != null,
    );
    // …and a shell sitting on a branch it does not draw (an address typed or
    // restored on the web, a license that lapsed) moves to Home — once the
    // answer is SETTLED. While the status is still loading, the tab is hidden
    // only because nothing is known yet, and moving a desk agent off their
    // queue for that would be a guess dressed as a fact.
    if (ref.watch(eeStatusProvider).hasValue &&
        destinationIndexFor(visibleSections, navigationShell.currentIndex) <
            0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) _goBranch(AppSection.home.index);
      });
    }
    ref.listen(syncConflictsProvider, (_, next) {
      final conflict = next.value;
      if (conflict == null) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(syncConflictMessage(conflict))));
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
    // OPH-298: …and one that arrived while this shell was NOT on screen.
    // `ref.listen` only ever fires on CHANGE, and the binder outlives the
    // shell (it is not auto-disposed), so a payload remembered while the user
    // sat on a pushed screen — or on the error screen the share callback used
    // to produce — was held in memory and shown to nobody. Sweeping the holder
    // after the frame closes that: `take()` is read-and-clear, so it can never
    // double-deliver with the listener above.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      final waiting = ref.read(pendingSharePayloadProvider.notifier).take();
      if (waiting != null) unawaited(_routeShare(context, ref, waiting));
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

    // OPH-359 (UI-AUDIT #58): what the floating buttons cover, said once for
    // every list inside the shell (see [AwFabClearance]).
    final fabClearance = _fabBar(context, ref) == null
        ? 0.0
        : AwFabClearance.lane;
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
                        selectedIndex: destinationIndexFor(
                          visibleSections,
                          navigationShell.currentIndex,
                        ).clamp(0, visibleSections.length - 1),
                        onDestinationSelected: (i) =>
                            _goVisible(visibleSections, i),
                        minWidth: kAwRailMinWidth,
                        groupAlignment: -0.9,
                        // OPH-199: the shortcut section sits right under the
                        // destinations. `scrollable` is not optional — a full
                        // rail on a short window would otherwise overflow.
                        scrollable: true,
                        trailing: SizedBox(
                          // The rail lives in an unbounded Row, and
                          // `minExtendedWidth` is only a floor, so a long
                          // shortcut title would otherwise widen the whole rail.
                          width: extendedRail ? 256 : kAwRailMinWidth,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // EE-294: Approvals, directly under Requests —
                              // the rail's last destination. A link rather
                              // than a section (`approvals_entry.dart` says
                              // why), drawn only for approval authority.
                              EeApprovalsRailEntry(extended: extendedRail),
                              extendedRail
                                  ? const QuickAccessRailSection()
                                  : const QuickAccessRailButton(),
                            ],
                          ),
                        ),
                        destinations: [
                          for (final section in visibleSections)
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
                // OPH-359 (UI-AUDIT #12): the content is its own semantics
                // container. The section's Navigator paints its page route's
                // ModalBarrier, and a barrier is a `BlockSemantics`: it hides
                // every node painted BEFORE it in the same container. Without
                // a boundary here that container was the shell's, and the
                // rail — painted first in this Row — vanished from the
                // accessibility tree: no screen reader, no Tab on the web.
                // The phone's bar is painted after the body, which is why
                // only the wide layout lost it.
                Expanded(
                  child: Semantics(
                    container: true,
                    child: AwFabClearance(
                      extent: fabClearance,
                      child: navigationShell,
                    ),
                  ),
                ),
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
          body: _ShellBody(fabClearance: fabClearance, child: navigationShell),
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
                // OPH-359 (UI-AUDIT #58): the capsule's pill corners clipped
                // the outermost labels ("Ana Sayfa", "Talepler"), so the bar
                // sits inside the curve; and six labels do not fit a phone,
                // so past five only the selected one is written — the rest
                // keep their icon and tooltip.
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AwSpace.x3),
                  child: NavigationBar(
                    labelBehavior: visibleSections.length > 5
                        ? NavigationDestinationLabelBehavior.onlyShowSelected
                        : NavigationDestinationLabelBehavior.alwaysShow,
                    selectedIndex: destinationIndexFor(
                      visibleSections,
                      navigationShell.currentIndex,
                    ).clamp(0, visibleSections.length - 1),
                    onDestinationSelected: (i) =>
                        _goVisible(visibleSections, i),
                    destinations: [
                      for (final section in visibleSections)
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
    // OPH-361 moved the workspace list's first load to the app's root (the
    // draft courier), so on a cold start the provider's FIRST build usually
    // has a workspace already and goes straight to the network — it no longer
    // passes through the guard that answers from the cache. The cache is
    // still the only cold-start signal there is: ask it before waiting.
    final cached = await ref.read(aiStatusProvider.notifier).lastKnown();
    if (cached != null) return cached;
    return await ref.read(aiStatusProvider.future).timeout(_shareStatusBudget);
  } on Object {
    return AiStatus.disabled;
  }
}

const _shareStatusBudget = Duration(seconds: 2);

/// The phone shell's body (OPH-359, UI-AUDIT #10).
///
/// `extendBody` lets the content scroll under the glass bar, and Scaffold
/// says so to the body through `padding.bottom` — which a list reads. A
/// section's OWN Scaffold places its FAB by `viewPadding.bottom` instead, so
/// the request queue's "new request" sat exactly under the bar: invisible,
/// and a tap on it opened Files. Copying the bar's height into the view
/// padding puts every inner FAB (and floating snackbar) above the bar, for
/// every section, without each screen having to know the shell exists.
class _ShellBody extends StatelessWidget {
  const _ShellBody({required this.fabClearance, required this.child});

  final double fabClearance;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final covered = media.padding.bottom;
    return MediaQuery(
      data: media.copyWith(
        viewPadding: media.viewPadding.copyWith(
          bottom: math.max(media.viewPadding.bottom, covered),
        ),
      ),
      child: AwFabClearance(extent: fabClearance, child: child),
    );
  }
}

/// Below this width a section's app bar puts the team and unit under its
/// title (OPH-359) — the switcher's own compact width, so the two agree.
const double kAwCompactAppBarWidth = 600;

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
  final width = MediaQuery.sizeOf(context).width;
  final wide = width >= kAwWideBreakpoint;
  // OPH-359 (UI-AUDIT #58): on a phone the team dot and the unit switcher go
  // UNDER the title instead of beside the actions. In the action row they ate
  // the room the title needed ("A…"), and the switcher could only be an icon
  // there — so nobody could see WHICH unit was on screen. Under the title it
  // has the width to say its name.
  final compact = width < kAwCompactAppBarWidth;
  return AppBar(
    title: compact
        ? AwWorkspaceSwitcher(title: title, leading: const AwTeamChip())
        : Text(title),
    actions: [
      // EE-018: which team this window belongs to. Renders nothing on a CE
      // server or a plain host, so the community build is untouched.
      // EE-061: which unit this window is showing, next to which team it
      // belongs to — the two identity questions live in one corner.
      if (!compact) ...[const AwWorkspaceSwitcher(), const AwTeamChip()],
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

/// OPH-056: a sync push the server refused (or trimmed via LWW) surfaces
/// as a snackbar — the replica already shows the server's version by the
/// time the user reads it.
String syncConflictMessage(SyncConflict conflict) {
  if (conflict.conflictVersionId != null) {
    return 'sync.noteConflict'.tr();
  }
  if (conflict.discardedFields.isNotEmpty) {
    return 'sync.fieldsOverridden'.tr(
      args: {'fields': conflict.discardedFields.join(', ')},
    );
  }
  if (conflict.status == 'rejected') {
    // A refusal the app has words for says what happened — "this request is
    // closed", "this task is a request's work" — in the words every other
    // screen uses for that code (EE-297). The generic line with the code is
    // for a refusal nobody wrote a sentence for yet.
    final code = conflict.errorCode;
    final known = code == null
        ? null
        : AwI18n.instance.maybeTranslate('error.$code');
    if (known != null) return known;
    return 'sync.rejected'.tr(args: {'code': code != null ? ' ($code)' : ''});
  }
  return 'sync.conflicted'.tr();
}
