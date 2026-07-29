import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/date_format.dart';
import '../../core/error_messages.dart';
import '../../core/fold.dart';
import '../../core/pending_deletes.dart';
import '../../core/persisted_prefs.dart';
import '../../i18n/i18n.dart';
import '../../notifications/alarm_banner.dart';
import '../../screens/home_shell.dart';
import '../../sections.dart';
import '../../sync/refresh.dart';
import '../../theme/tokens.dart';
import '../../widgets/refreshable.dart';
import '../../widgets/status_views.dart';
import '../../search/providers.dart';
import '../../search/search.dart';
import '../../widgets/search_field.dart';
import '../quick_access/ui/quick_access_rail_section.dart';
import '../calendar/providers.dart';
import '../calendar/ui/external_event_tile.dart';
import '../tags/tags.dart';
import '../tasks/data/task.dart';
import '../tasks/providers.dart';
import '../tasks/ui/quick_add_bar.dart';
import '../tasks/ui/task_tile.dart';
import '../workspaces/workspaces.dart';
import 'home_board.dart';
import 'month_calendar.dart';
import 'task_grouping.dart';

/// Home (feedback round 1): the one place everything shows. Chronological
/// task list (overdue → today → tomorrow → this week → later → no date) with
/// an Apple-style month calendar — right panel on wide layouts, collapsible
/// top half on phones (visibility persisted). Picking a day pulls its tasks
/// to a highlighted first group and dims the future groups (Overdue/Today/
/// No-date stay lit); hiding the calendar drops the selection so an invisible
/// filter can never keep dimming the list (feedback round 6).
///
/// **Round 9 (OPH-172, DESIGN §16):** on phones exactly ONE thing is pinned —
/// the app bar. The degradation banner, the Liste | Pano toggle, quick add, the
/// search field, the calendar and the calendar toggle are all slivers of the
/// one scroll view, so chrome never narrows the list it sits above. Wide
/// layouts keep their pinned chrome and side calendar (there is room), and the
/// phone BOARD keeps its toggle pinned — a horizontal pager cannot scroll it
/// away, and losing it would strand the user in the board (H3).
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  /// Quick add's text lives HERE, not in the bar (OPH-172/H4): the bar is a
  /// sliver now, and a sliver scrolled past the cache extent is disposed —
  /// which would silently eat what the user had typed.
  final _quickAddController = TextEditingController();
  final _quickAddFocus = FocusNode();
  final _quickAddKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _quickAddFocus.addListener(_keepQuickAddVisible);
  }

  @override
  void dispose() {
    _quickAddFocus.removeListener(_keepQuickAddVisible);
    _quickAddController.dispose();
    _quickAddFocus.dispose();
    super.dispose();
  }

  /// Focusing a bar that is half off the top edge (or about to sit behind the
  /// keyboard) must not leave the user typing blind — scroll it back (H4).
  void _keepQuickAddVisible() {
    if (!_quickAddFocus.hasFocus) return;
    final context = _quickAddKey.currentContext;
    if (context == null) return; // wide layout: nothing can scroll it away
    if (Scrollable.maybeOf(context) == null) return;
    Scrollable.ensureVisible(
      context,
      duration: AwMotion.base,
      alignment: 0.1,
      curve: Curves.easeOutCubic,
    );
  }

  /// Quick add from Home: lands on the selected calendar day at the user's
  /// default task time (Settings; factory 23:59 — OPH-161) when one is picked,
  /// otherwise dateless — either way it appears in the list right away
  /// (feedback round 2).
  Future<void> _quickAdd(String title) async {
    final workspaces = await ref.read(workspacesProvider.future);
    if (workspaces.isEmpty) throw StateError('No workspace available');
    final selectedDay = ref.read(selectedDayProvider);
    final dueAt = selectedDay == null
        ? null
        : applyDefaultTaskTime(
            selectedDay,
            ref.read(defaultTaskTimeProvider),
          ).toUtc().toIso8601String();
    await ref.read(taskStoreProvider).create(workspaces.first.id, {
      'title': title,
      'dueAt': ?dueAt,
    });
  }

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(openTasksProvider);
    final selectedDay = ref.watch(selectedDayProvider);
    // A workspace with no calendar connected has none — not an error state.
    final events =
        ref.watch(externalEventsProvider).value ?? const <ExternalEvent>[];

    // OPH-167 (DESIGN §12): per-screen search — tasks, captures and the
    // user's calendar in one ranked list. Never mutates the list state it
    // covers (S5). Watched at build top, NOT inside the async when-branch.
    final searching = ref.watch(homeSearchQueryProvider).trim().isNotEmpty;
    // OPH-168 (K1): Liste | Pano — the board is a VIEW of the same task set,
    // device-local and persistent. Search belongs to the list view.
    final isBoard = ref.watch(homeViewProvider) == 'board';
    // Watched here (not inside the LayoutBuilder) so a layout pass never
    // subscribes providers.
    final calendarVisible = ref.watch(homeCalendarVisibleProvider);
    final dateFormat = ref.watch(dateFormatProvider);

    // OPH-213 (DESIGN §16 H1, revised): the view controls left the scroll and
    // became app-bar icons — the Notes pattern. An icon shows the view it will
    // SWITCH TO, so what you tap is what you get. The board's column editor
    // stays beside it, since it only means anything in the board.
    final viewActions = <Widget>[
      // Round 13 #5: search is an app-bar action too, so the list keeps its
      // line. Closing it clears the query (see AwSearchAction).
      AwSearchAction(
        fieldKey: const Key('home-search'),
        hintText: 'home.searchHint'.tr(),
        onQuery: (q) => ref.read(homeSearchQueryProvider.notifier).set(q),
      ),
      IconButton(
        key: const Key('home-view-toggle'),
        tooltip: isBoard ? 'board.viewList'.tr() : 'board.viewBoard'.tr(),
        icon: Icon(
          isBoard ? Icons.view_agenda_outlined : Icons.view_kanban_outlined,
        ),
        onPressed: () =>
            ref.read(homeViewProvider.notifier).set(isBoard ? 'list' : 'board'),
      ),
      if (isBoard)
        IconButton(
          key: const Key('board-edit-columns'),
          tooltip: 'board.editColumns'.tr(),
          icon: const Icon(Icons.tune),
          onPressed: () => showBoardColumnsSheet(context, ref),
        ),
      if (!isBoard)
        IconButton(
          key: const Key('toggle-calendar'),
          tooltip: calendarVisible
              ? 'home.hideCalendar'.tr()
              : 'home.showCalendar'.tr(),
          icon: Icon(
            calendarVisible
                ? Icons.calendar_month
                : Icons.calendar_month_outlined,
          ),
          onPressed: () {
            // Hiding the calendar clears the selection: a filter you can no
            // longer see must not keep dimming Home (feedback round 6).
            if (calendarVisible) {
              ref.read(selectedDayProvider.notifier).select(null);
            }
            ref.read(homeCalendarVisibleProvider.notifier).toggle();
          },
        ),
    ];

    // The create FAB is rendered by HomeShell's own Scaffold (OPH-101), so it
    // clears the glass bottom bar; this screen only supplies the list + quick
    // add + calendar.
    return Scaffold(
      appBar: buildSectionAppBar(
        context,
        'nav.home'.tr(),
        onRefresh: () => refreshSection(ref, AppSection.home),
        // OPH-200: the entry point when the floating button is switched off —
        // the widget hides itself everywhere else (DESIGN §23 Q5).
        leadingActions: const [QuickAccessAppBarButton()],
        // OPH-213: the view + calendar controls, left of settings.
        trailingActions: viewActions,
      ),
      body: tasks.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AwErrorState(
          message: localizedError(error),
          onRetry: () => ref.invalidate(openTasksProvider),
        ),
        data: (rawItems) {
          // OPH-184: rows hide themselves while undoable, but the GROUPING is
          // computed from the raw list — without this a group whose only task
          // was just deleted would render a header above nothing.
          final items = awWithoutPending(
            rawItems,
            ref.watch(pendingDeletesProvider),
            (t) => t.id,
          );
          final groups = groupTasksForHome(
            items,
            now: DateTime.now(),
            selectedDay: selectedDay,
            events: events,
          );
          final calendar = MonthCalendar(
            // A day with a meeting is not an empty day.
            markedDays: {...daysWithTasks(items), ...daysWithEvents(events)},
            selectedDay: selectedDay,
            onDaySelected: (day) =>
                ref.read(selectedDayProvider.notifier).select(day),
          );

          final quickAdd = QuickAddBar(
            key: const Key('home-quick-add'),
            // Hoisted state (H4) — see [_quickAddController].
            controller: _quickAddController,
            focusNode: _quickAddFocus,
            hintText: selectedDay == null
                ? 'home.quickAddHint'.tr()
                : 'home.quickAddForDay'.tr(
                    args: {
                      'date': awFormatDate(selectedDay, format: dateFormat),
                    },
                  ),
            onAdd: _quickAdd,
          );

          // Honest alarm-degradation banner (OPH-143): only shown when the OS
          // can't ring urgent alarms reliably; nothing otherwise.
          const banner = AlarmDegradationBanner();

          return LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 720;

              // H2 — wide layouts are unchanged: there is room for pinned
              // chrome, and the calendar is a side panel.
              if (isWide) {
                return Column(
                  children: [
                    banner,
                    if (isBoard)
                      const Expanded(child: HomeBoard())
                    else
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                children: [
                                  quickAdd,
                                  Expanded(
                                    // OPH-171: the list pulls here too; the
                                    // calendar panel beside it is not a list.
                                    child: AwRefresh(
                                      indicatorKey: const Key('home-refresh'),
                                      onRefresh: () =>
                                          refreshSection(ref, AppSection.home),
                                      child: searching
                                          // Search renders slivers (so phones
                                          // can pull it too) — give them a
                                          // scroll view of their own here.
                                          ? const CustomScrollView(
                                              physics:
                                                  AlwaysScrollableScrollPhysics(),
                                              slivers: [_HomeSearchResults()],
                                            )
                                          : _GroupedTaskList(groups: groups),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: 356,
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.fromLTRB(
                                  AwSpace.x1,
                                  AwSpace.x2,
                                  AwSpace.x4,
                                  AwSpace.x4,
                                ),
                                child: Card(
                                  child: Padding(
                                    padding: const EdgeInsets.all(AwSpace.x3),
                                    child: calendar,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              }

              // H3 — phone + board: the board is a horizontal pager, so the
              // toggle CANNOT ride a vertical scroll. It stays pinned, or the
              // way back to Liste disappears.
              if (isBoard) {
                return Column(
                  children: [
                    banner,
                    const Expanded(child: HomeBoard()),
                  ],
                );
              }

              // H1 — phone + list: ONE scroll view. Everything above the rows
              // scrolls with them (OPH-103's philosophy, finished); only the
              // app bar is pinned. The search field's sliver position is the
              // same in both modes, so it never remounts mid-typing (OPH-167).
              return AwRefresh(
                indicatorKey: const Key('home-refresh'),
                onRefresh: () => refreshSection(ref, AppSection.home),
                child: CustomScrollView(
                  key: const Key('home-scroll'),
                  // A short list (or the empty state) must still be pullable.
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    const SliverToBoxAdapter(child: banner),
                    SliverToBoxAdapter(
                      // The key rides a KeyedSubtree so `ensureVisible` has a
                      // context INSIDE the scroll view (H4).
                      child: KeyedSubtree(key: _quickAddKey, child: quickAdd),
                    ),
                    if (searching) const _HomeSearchResults(),
                    if (!searching && calendarVisible)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AwSpace.x4,
                          ),
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(AwSpace.x2),
                              child: calendar,
                            ),
                          ),
                        ),
                      ),
                    if (!searching && groups.isEmpty)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        // Inside the scroll view already: its own scroll view
                        // must not eat the pull.
                        child: _HomeEmpty(
                          physics: NeverScrollableScrollPhysics(),
                        ),
                      ),
                    if (!searching && groups.isNotEmpty)
                      SliverPadding(
                        padding: awListPadding(context, extraBottom: 72),
                        sliver: SliverList(
                          delegate: SliverChildListDelegate(
                            buildHomeGroupRows(context, groups),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// The wide-layout task list: a plain ListView of the shared group rows.
/// (The narrow layout renders the same rows inside a CustomScrollView so the
/// calendar scrolls with them — OPH-103.)
class _GroupedTaskList extends StatelessWidget {
  const _GroupedTaskList({required this.groups});

  final List<HomeGroup> groups;

  @override
  Widget build(BuildContext context) {
    // Both branches are the scrollable the pull gesture needs (OPH-171).
    if (groups.isEmpty) {
      return const _HomeEmpty(physics: AlwaysScrollableScrollPhysics());
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: awListPadding(context, extraBottom: 72),
      children: buildHomeGroupRows(context, groups),
    );
  }
}

/// Home's "nothing to do" state — shared by both layouts so it reads the same
/// in the wide ListView and the narrow SliverFillRemaining.
class _HomeEmpty extends StatelessWidget {
  const _HomeEmpty({this.physics});

  /// See [AwEmptyState.physics]: always-scrollable in the wide layout (it IS
  /// the scrollable), never-scrollable inside the narrow sliver (the
  /// CustomScrollView above it owns the gesture).
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) => AwEmptyState(
    icon: Icons.beach_access_outlined,
    title: 'home.allCaughtUp'.tr(),
    message: 'home.allCaughtUpBody'.tr(),
    physics: physics,
  );
}

/// The header + row widgets for Home's groups, shared by the wide ListView and
/// the narrow CustomScrollView (OPH-103) so the group/row logic lives in ONE
/// place. Each group is a labelled header followed by its chronological rows
/// (§12): a 10:00 meeting sits above a 16:00 task, each rendered as what it is.
List<Widget> buildHomeGroupRows(BuildContext context, List<HomeGroup> groups) {
  final theme = Theme.of(context);
  return [
    for (final group in groups) ...[
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AwSpace.x1,
          AwSpace.x4,
          AwSpace.x1,
          AwSpace.x2,
        ),
        child: Text(
          '${group.bucket.label} · ${group.items.length}',
          style: theme.textTheme.labelLarge?.copyWith(
            color: group.dimmed
                ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7)
                : switch (group.bucket) {
                    HomeBucket.overdue => theme.colorScheme.error,
                    HomeBucket.selectedDay => context.awTokens.link,
                    _ => theme.colorScheme.onSurfaceVariant,
                  },
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
      ),
      for (final item in group.items)
        switch (item) {
          TaskItem(:final task) => TaskTile(
            task: task,
            dimmed: group.dimmed,
            highlighted: group.bucket == HomeBucket.selectedDay,
          ),
          EventItem(:final event) => Opacity(
            opacity: group.dimmed ? 0.45 : 1,
            child: ExternalEventTile(event: event),
          ),
        },
    ],
  ];
}

/// Search-mode body (OPH-167): one ranked list — tasks (planning + inbox
/// captures) and calendar events — ordered by tier (title > tag > body),
/// each row its screen-normal self (S3/S5). The context line under a row
/// says WHERE a non-title hit matched.
///
/// **Returns a SLIVER** (OPH-172): search results are part of Home's one scroll
/// view, so pull-to-refresh works over them on phones too — a nested scrollable
/// would have swallowed the drag.
class _HomeSearchResults extends ConsumerWidget {
  const _HomeSearchResults();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(homeSearchQueryProvider).trim();
    final results = ref.watch(homeSearchResultsProvider);
    final open = ref.watch(openTasksProvider).value ?? const [];
    final inbox = ref.watch(inboxTasksProvider).value ?? const [];
    final events =
        ref.watch(externalEventsProvider).value ?? const <ExternalEvent>[];
    final tasksById = {
      for (final t in [...open, ...inbox]) t.id: t,
    };
    final eventsById = {for (final e in events) e.id: e};
    final words = SearchService.queryWords(query);

    return results.when(
      loading: () => const SliverToBoxAdapter(child: _DelayedProgress()),
      error: (error, _) => SliverFillRemaining(
        hasScrollBody: false,
        child: AwErrorState(
          message: localizedError(error),
          onRetry: () => ref.invalidate(homeSearchResultsProvider),
          physics: const NeverScrollableScrollPhysics(),
        ),
      ),
      data: (data) {
        if (data == null) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }
        final rows = <(int, Widget)>[];
        for (final hit in data.tasks) {
          final task = tasksById[hit.id];
          if (task == null) continue;
          rows.add((hit.tier, _TaskResult(task: task, hit: hit, words: words)));
        }
        for (final hit in data.events) {
          final event = eventsById[hit.id];
          if (event == null) continue;
          rows.add((
            hit.tier,
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: ExternalEventTile(event: event),
            ),
          ));
        }
        if (rows.isEmpty) {
          return SliverFillRemaining(
            hasScrollBody: false,
            child: AwEmptyState(
              icon: Icons.search_off,
              title: 'home.searchEmptyTitle'.tr(),
              message: 'home.searchEmptyBody'.tr(args: {'query': query}),
              physics: const NeverScrollableScrollPhysics(),
            ),
          );
        }
        // Stable merge by tier: tasks already tier-ordered, events too.
        rows.sort((a, b) => a.$1.compareTo(b.$1));
        return SliverPadding(
          key: const Key('home-search-results'),
          padding: awListPadding(context),
          sliver: SliverList(
            delegate: SliverChildListDelegate([for (final row in rows) row.$2]),
          ),
        );
      },
    );
  }
}

/// A task hit + its honest match context (S3): `#tag` for a tag hit, a
/// description snippet for a body hit; a title hit needs no explanation.
class _TaskResult extends ConsumerWidget {
  const _TaskResult({
    required this.task,
    required this.hit,
    required this.words,
  });

  final Task task;
  final SearchHit hit;
  final List<String> words;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    String? contextLine;
    if (hit.tier == 1) {
      final tagsById = ref.watch(tagsByIdProvider);
      for (final id in task.tagIds) {
        final tag = tagsById[id];
        if (tag == null) continue;
        final folded = foldSearchText(tag.name);
        if (words.every(folded.contains)) {
          contextLine = '#${tag.name}';
          break;
        }
      }
    } else if (hit.tier == 2 && (task.description?.isNotEmpty ?? false)) {
      contextLine = searchSnippet(task.description!, words.first);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TaskTile(task: task),
        if (contextLine != null)
          Padding(
            padding: const EdgeInsets.only(
              left: AwSpace.x6,
              right: AwSpace.x4,
              bottom: 6,
            ),
            child: Text(
              contextLine,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

/// S4: loading only when it's real — the bar appears after 150 ms, so a
/// millisecond-fast local query never flashes chrome.
class _DelayedProgress extends StatefulWidget {
  const _DelayedProgress();

  @override
  State<_DelayedProgress> createState() => _DelayedProgressState();
}

class _DelayedProgressState extends State<_DelayedProgress> {
  bool _show = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _show = true);
    });
  }

  @override
  Widget build(BuildContext context) => _show
      ? const Align(
          alignment: Alignment.topCenter,
          child: LinearProgressIndicator(minHeight: 2),
        )
      : const SizedBox.shrink();
}
