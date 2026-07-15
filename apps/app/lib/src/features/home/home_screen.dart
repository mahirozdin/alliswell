import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/persisted_prefs.dart';
import '../../screens/home_shell.dart';
import '../../theme/tokens.dart';
import '../../widgets/status_views.dart';
import '../calendar/providers.dart';
import '../calendar/ui/external_event_tile.dart';
import '../tasks/providers.dart';
import '../tasks/ui/quick_add_bar.dart';
import '../tasks/ui/task_create_sheet.dart';
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

    return Scaffold(
      appBar: buildSectionAppBar(context, 'Home'),
      floatingActionButton: FloatingActionButton(
        tooltip: 'New task with options',
        onPressed: () => showTaskCreateSheet(
          context,
          initialDue: selectedDay?.add(const Duration(hours: 9)),
        ),
        child: const Icon(Icons.add),
      ),
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
              return Column(
                children: [
                  quickAdd,
                  if (calendarVisible)
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: constraints.maxHeight * 0.5,
                      ),
                      child: SingleChildScrollView(
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
                  Align(
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
                          calendarVisible ? 'Hide calendar' : 'Show calendar',
                        ),
                      ),
                    ),
                  ),
                  Expanded(child: _GroupedTaskList(groups: groups)),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _GroupedTaskList extends StatelessWidget {
  const _GroupedTaskList({required this.groups});

  final List<HomeGroup> groups;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (groups.isEmpty) {
      return const AwEmptyState(
        icon: Icons.beach_access_outlined,
        title: 'All caught up',
        message: 'No open tasks — capture one in the Inbox.',
      );
    }

    return ListView(
      padding: awListPadding(context, extraBottom: 72),
      children: [
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
          // One chronological stream (§12): a 10:00 meeting sits above a 16:00
          // task, and each row renders as what it actually is.
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
      ],
    );
  }
}
