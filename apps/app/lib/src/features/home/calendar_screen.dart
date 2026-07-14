import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../screens/home_shell.dart';
import '../tasks/providers.dart';
import '../tasks/ui/task_tile.dart';
import 'month_calendar.dart';
import 'task_grouping.dart';

/// Calendar tab (feedback round 1): just the month view — tapping a day lists
/// that day's tasks below. Selection is shared with Home.
class CalendarScreen extends ConsumerWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(openTasksProvider);
    final selectedDay = ref.watch(selectedDayProvider);

    return Scaffold(
      appBar: buildSectionAppBar(context, 'Calendar'),
      body: tasks.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (items) {
          final day = selectedDay ?? dayOf(DateTime.now());
          final dayTasks = [
            for (final task in items)
              if (task.dueAt != null && dayOf(task.dueAt!) == day) task,
          ]..sort((a, b) => a.dueAt!.compareTo(b.dueAt!));

          return Column(
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: MonthCalendar(
                      markedDays: daysWithTasks(items),
                      selectedDay: selectedDay,
                      onDaySelected: (d) =>
                          ref.read(selectedDayProvider.notifier).select(d),
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}'
                    ' · ${dayTasks.length} task${dayTasks.length == 1 ? '' : 's'}',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
              ),
              Expanded(
                child: dayTasks.isEmpty
                    ? Center(
                        child: Text(
                          'Nothing due this day.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      )
                    : ListView(
                        children: [
                          for (final task in dayTasks) TaskTile(task: task),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
