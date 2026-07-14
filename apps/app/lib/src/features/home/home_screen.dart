import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/persisted_prefs.dart';
import '../../screens/home_shell.dart';
import '../tasks/providers.dart';
import '../tasks/ui/task_tile.dart';
import 'month_calendar.dart';
import 'task_grouping.dart';

/// Home (feedback round 1): the one place everything shows. Chronological
/// task list (overdue → today → tomorrow → this week → later → no date) with
/// an Apple-style month calendar — right panel on wide layouts, collapsible
/// top half on phones (visibility persisted). Picking a day pulls its tasks
/// to a highlighted first group and dims the rest.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(openTasksProvider);
    final selectedDay = ref.watch(selectedDayProvider);

    return Scaffold(
      appBar: buildSectionAppBar(context, 'Home'),
      body: tasks.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$error', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => ref.invalidate(openTasksProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (items) {
          final groups = groupTasksForHome(
            items,
            now: DateTime.now(),
            selectedDay: selectedDay,
          );
          final calendar = MonthCalendar(
            markedDays: daysWithTasks(items),
            selectedDay: selectedDay,
            onDaySelected: (day) =>
                ref.read(selectedDayProvider.notifier).select(day),
          );

          return LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 720;
              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _GroupedTaskList(groups: groups)),
                    const VerticalDivider(width: 1),
                    SizedBox(
                      width: 340,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(12),
                        child: calendar,
                      ),
                    ),
                  ],
                );
              }

              final calendarVisible = ref.watch(homeCalendarVisibleProvider);
              return Column(
                children: [
                  if (calendarVisible)
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: constraints.maxHeight * 0.5,
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: calendar,
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      key: const Key('toggle-calendar'),
                      onPressed: () => ref
                          .read(homeCalendarVisibleProvider.notifier)
                          .toggle(),
                      icon: Icon(
                        calendarVisible ? Icons.expand_less : Icons.expand_more,
                      ),
                      label: Text(
                        calendarVisible ? 'Hide calendar' : 'Show calendar',
                      ),
                    ),
                  ),
                  const Divider(height: 1),
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
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.beach_access_outlined,
              size: 64,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text('All caught up', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'No open tasks — capture one in the Inbox.',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }

    return ListView(
      children: [
        for (final group in groups) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Text(
              '${group.bucket.label} · ${group.tasks.length}',
              style: theme.textTheme.labelLarge?.copyWith(
                color: group.dimmed
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          for (final task in group.tasks)
            TaskTile(
              task: task,
              dimmed: group.dimmed,
              highlighted: group.bucket == HomeBucket.selectedDay,
            ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}
