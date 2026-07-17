import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/error_messages.dart';
import '../../i18n/i18n.dart';
import '../../screens/home_shell.dart';
import '../../theme/tokens.dart';
import '../../widgets/status_views.dart';
import '../calendar/providers.dart';
import '../calendar/ui/external_event_tile.dart';
import '../tasks/providers.dart';
import '../tasks/ui/task_tile.dart';
import 'month_calendar.dart';
import 'task_grouping.dart';

/// Calendar tab (feedback round 1): the month view — tapping a day lists that
/// day below. Selection is shared with Home.
///
/// Since OPH-083 it shows the user's OWN calendar too (ADR-0008): tasks alone
/// could never answer "what does my day look like".
class CalendarScreen extends ConsumerWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(openTasksProvider);
    final selectedDay = ref.watch(selectedDayProvider);
    // A missing calendar is not an error — most workspaces have none connected.
    final events =
        ref.watch(externalEventsProvider).value ?? const <ExternalEvent>[];

    return Scaffold(
      appBar: buildSectionAppBar(context, 'nav.calendar'.tr()),
      body: tasks.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AwErrorState(
          message: localizedError(error),
          onRetry: () => ref.invalidate(openTasksProvider),
        ),
        data: (items) {
          final day = selectedDay ?? dayOf(DateTime.now());
          final dayTasks = [
            for (final task in items)
              if (task.dueAt != null && dayOf(task.dueAt!) == day) task,
          ]..sort((a, b) => a.dueAt!.compareTo(b.dueAt!));
          final dayEvents = eventsOn(events, day);
          final total = dayTasks.length + dayEvents.length;

          return Column(
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AwSpace.x4,
                      AwSpace.x2,
                      AwSpace.x4,
                      AwSpace.x3,
                    ),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(AwSpace.x3),
                        child: MonthCalendar(
                          // A day with a meeting is not an empty day.
                          markedDays: {
                            ...daysWithTasks(items),
                            ...daysWithEvents(events),
                          },
                          selectedDay: selectedDay,
                          onDaySelected: (d) =>
                              ref.read(selectedDayProvider.notifier).select(d),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AwSpace.x5,
                  AwSpace.x2,
                  AwSpace.x5,
                  AwSpace.x1,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}'
                    ' · $total item${total == 1 ? '' : 's'}',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: total == 0
                    ? const AwEmptyState(
                        icon: Icons.event_available_outlined,
                        title: 'Free day',
                        message: 'Nothing due and nothing scheduled.',
                      )
                    : ListView(
                        padding: awListPadding(context),
                        children: [
                          // Events first: they are fixed points, the tasks fit
                          // around them.
                          for (final event in dayEvents)
                            ExternalEventTile(event: event),
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
