import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/persisted_prefs.dart';
import '../../i18n/i18n.dart';
import '../../screens/home_shell.dart';
import '../../theme/tokens.dart';
import '../../widgets/status_views.dart';
import '../calendar/providers.dart';
import '../calendar/ui/external_event_tile.dart';
import '../tasks/providers.dart';
import '../tasks/ui/quick_add_bar.dart';
import '../tasks/ui/task_tile.dart';
import '../workspaces/workspaces.dart';
import 'month_calendar.dart';
import 'task_grouping.dart';

/// Home (feedback round 1): the one place everything shows. Chronological
/// task list (overdue → today → tomorrow → this week → later → no date) with
/// an Apple-style month calendar — right panel on wide layouts, collapsible
/// top half on phones (visibility persisted). Picking a day pulls its tasks
/// to a highlighted first group and dims the rest.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  /// Quick add from Home: lands on the selected calendar day (09:00) when one
  /// is picked, otherwise dateless — either way it appears in the list right
  /// away (feedback round 2).
  Future<void> _quickAdd(WidgetRef ref, String title) async {
    final workspaces = await ref.read(workspacesProvider.future);
    if (workspaces.isEmpty) throw StateError('No workspace available');
    final selectedDay = ref.read(selectedDayProvider);
    final dueAt = selectedDay
        ?.add(const Duration(hours: 9))
        .toUtc()
        .toIso8601String();
    await ref.read(taskStoreProvider).create(workspaces.first.id, {
      'title': title,
      'dueAt': ?dueAt,
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(openTasksProvider);
    final selectedDay = ref.watch(selectedDayProvider);
    // A workspace with no calendar connected has none — not an error state.
    final events =
        ref.watch(externalEventsProvider).value ?? const <ExternalEvent>[];

    // The create FAB is rendered by HomeShell's own Scaffold (OPH-101), so it
    // clears the glass bottom bar; this screen only supplies the list + quick
    // add + calendar.
    return Scaffold(
      appBar: buildSectionAppBar(context, 'nav.home'.tr()),
      body: tasks.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AwErrorState(
          message: '$error',
          onRetry: () => ref.invalidate(openTasksProvider),
        ),
        data: (items) {
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
            hintText: selectedDay == null
                ? 'Quick add a task…'
                : 'Quick add for '
                      '${selectedDay.year}-${selectedDay.month.toString().padLeft(2, '0')}-${selectedDay.day.toString().padLeft(2, '0')}…',
            onAdd: (title) => _quickAdd(ref, title),
          );

          return LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 720;
              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          quickAdd,
                          Expanded(child: _GroupedTaskList(groups: groups)),
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
                );
              }

              final calendarVisible = ref.watch(homeCalendarVisibleProvider);
              // The calendar is the FIRST item of one scroll view, so it slides
              // off-screen as the list scrolls (OPH-103) instead of staying
              // pinned and eating half the screen. Quick add stays fixed above.
              return Column(
                children: [
                  quickAdd,
                  Expanded(
                    child: CustomScrollView(
                      key: const Key('home-scroll'),
                      slivers: [
                        if (calendarVisible)
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
                        SliverToBoxAdapter(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Padding(
                              padding: const EdgeInsets.only(right: AwSpace.x2),
                              child: TextButton.icon(
                                key: const Key('toggle-calendar'),
                                onPressed: () => ref
                                    .read(homeCalendarVisibleProvider.notifier)
                                    .toggle(),
                                icon: Icon(
                                  calendarVisible
                                      ? Icons.expand_less
                                      : Icons.expand_more,
                                ),
                                label: Text(
                                  calendarVisible
                                      ? 'Hide calendar'
                                      : 'Show calendar',
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (groups.isEmpty)
                          const SliverFillRemaining(
                            hasScrollBody: false,
                            child: _HomeEmpty(),
                          )
                        else
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
                  ),
                ],
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
    if (groups.isEmpty) return const _HomeEmpty();
    return ListView(
      padding: awListPadding(context, extraBottom: 72),
      children: buildHomeGroupRows(context, groups),
    );
  }
}

/// Home's "nothing to do" state — shared by both layouts so it reads the same
/// in the wide ListView and the narrow SliverFillRemaining.
class _HomeEmpty extends StatelessWidget {
  const _HomeEmpty();

  @override
  Widget build(BuildContext context) => const AwEmptyState(
    icon: Icons.beach_access_outlined,
    title: 'All caught up',
    message: 'No open tasks — capture one in the Inbox.',
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
