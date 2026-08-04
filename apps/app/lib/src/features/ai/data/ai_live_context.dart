import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import '../../../core/day_boundary.dart';
import '../../../core/fold.dart';
import '../../../core/persisted_prefs.dart';
import '../../../i18n/i18n.dart';
import '../../calendar/providers.dart';
import '../../projects/providers.dart';
import '../../tasks/data/task.dart';
import '../../tasks/providers.dart';
import 'ai_context_builder.dart';

/// Round 15: the bubble finally PACKS what AI.md §7 promised. The pure builder
/// existed since OPH-221; nothing ever fed it for a typed chat turn, so the
/// model truthfully answered "takvimine erişemem" — the live screenshots that
/// opened this round. This is the one impure edge: it reads the replica
/// providers and hands plain lists to the pure `buildAiContext`.
///
/// T0 meta+projects always · T1 overdue/today/upcoming tasks (lean rows) and
/// the user's own calendar events · T2 fold-matched task excerpts for the
/// current input. Notes excerpts are a deliberate follow-up (the notes list
/// provider is query-coupled; wiring it here would drag UI filter state into
/// the packer).
///
/// `read` is a tear-off (`ref.read`) so both widgets (WidgetRef) and
/// providers (Ref) can call this without caring which ref family they hold.
AiContextBundle buildLiveAiContext({
  required R Function<R>(ProviderListenable<R> provider) read,
  String query = '',
  SharedPayload? sharedBlock,
}) {
  final now = DateTime.now();
  final startOfToday = awStartOfDay(now);
  final startOfTomorrow = startOfToday.add(const Duration(days: 1));
  final upcomingHorizon = startOfToday.add(const Duration(days: 8));

  final tasks = read(openTasksProvider).value ?? const <Task>[];
  final projects = read(projectsControllerProvider).value ?? const [];
  final events = read(externalEventsProvider).value ?? const [];

  final openByProject = <String, int>{};
  for (final task in tasks) {
    final id = task.projectId;
    if (id != null) openByProject[id] = (openByProject[id] ?? 0) + 1;
  }

  String dueLabel(DateTime due) =>
      awIsoWithOffset(due.toLocal()).replaceFirst('T', ' ').substring(0, 16);

  final overdue = <TaskLite>[];
  final today = <TaskLite>[];
  final upcoming = <TaskLite>[];
  for (final task in tasks) {
    final due = task.dueAt?.toLocal();
    if (due == null) continue;
    final lite = TaskLite(title: task.title, dueLabel: dueLabel(due));
    if (due.isBefore(now)) {
      overdue.add(lite);
    } else if (due.isBefore(startOfTomorrow)) {
      today.add(lite);
    } else if (due.isBefore(upcomingHorizon)) {
      upcoming.add(lite);
    }
  }

  final eventLites = <EventLite>[
    for (final event in events)
      if (!event.endsAt.toLocal().isBefore(startOfToday) &&
          event.startsAt.toLocal().isBefore(upcomingHorizon))
        EventLite(
          title: event.title,
          timeLabel: event.isAllDay
              ? '${dueLabel(event.startsAt).substring(0, 10)} (all day)'
              : dueLabel(event.startsAt),
        ),
  ];

  // T2 — fold-matched excerpts over task titles/descriptions for this input:
  // the same accent-insensitive fold search the product uses everywhere.
  final excerpts = <SearchExcerpt>[];
  final terms = foldSearchText(
    query,
  ).split(' ').where((t) => t.length >= 3).toList();
  if (terms.isNotEmpty) {
    for (final task in tasks) {
      if (excerpts.length >= 5) break;
      final haystack = foldSearchText(
        '${task.title} ${task.description ?? ''}',
      );
      if (!terms.any(haystack.contains)) continue;
      final body = (task.description ?? '').trim();
      final text = body.isEmpty
          ? task.title
          : '${task.title}\n${body.length > 200 ? '${body.substring(0, 199)}…' : body}';
      excerpts.add(SearchExcerpt(source: 'task', id: task.id, text: text));
    }
  }

  return buildAiContext(
    meta: AiContextMeta(
      locale: AwI18n.instance.locale.languageCode,
      timezone: now.timeZoneName,
      nowIso: awIsoWithOffset(now),
      weekday: const [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ][now.weekday - 1],
      defaultTaskTime: read(defaultTaskTimeProvider),
    ),
    projects: [
      for (final p in projects)
        ProjectLite(
          id: p.id,
          name: p.name,
          openCount: openByProject[p.id] ?? 0,
        ),
    ],
    overdue: overdue,
    today: today,
    upcoming: upcoming,
    events: eventLites,
    excerpts: excerpts,
    sharedBlock: sharedBlock,
  );
}
