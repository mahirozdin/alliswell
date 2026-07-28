import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/date_format.dart';
import '../../../core/day_boundary.dart';
import '../../../core/error_messages.dart';
import '../../../core/pending_deletes.dart';
import '../../../core/persisted_prefs.dart';
import '../../../i18n/i18n.dart';
import '../../../sync/providers.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/refreshable.dart';
import '../../../widgets/status_views.dart';
import '../data/task.dart';
import '../providers.dart';
import 'task_tile.dart';

/// Everything the user has finished (OPH-186, DESIGN §20 C4).
///
/// Reverse-chronological, day-headed, and paged as you scroll — sorted by
/// **the task's own date when it has one, otherwise by when it was completed**.
/// Reads the local replica only: the rows are already there, and an archive
/// that needs the network is an archive you cannot trust.
class CompletedScreen extends ConsumerStatefulWidget {
  const CompletedScreen({super.key});

  @override
  ConsumerState<CompletedScreen> createState() => _CompletedScreenState();
}

class _CompletedScreenState extends ConsumerState<CompletedScreen> {
  final _scroll = ScrollController();

  /// Pages requested so far. Each step re-queries with a bigger LIMIT rather
  /// than appending a second list, so the rows can never duplicate across a
  /// page boundary and a task completed mid-scroll simply lands in place.
  int _pages = 1;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeGrow);
  }

  @override
  void dispose() {
    _scroll.removeListener(_maybeGrow);
    _scroll.dispose();
    super.dispose();
  }

  void _maybeGrow() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    // Grow before the user hits the end, so the next rows are already there.
    if (position.pixels < position.maxScrollExtent - 400) return;
    final loaded = ref.read(completedTasksProvider(_pages)).value?.length ?? 0;
    // Only ask for more when the last page came back FULL — a short page is
    // the end of the archive, and growing past it would re-run the query
    // forever against an unchanging result.
    if (loaded < _pages * kCompletedPageSize) return;
    setState(() => _pages++);
  }

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(completedTasksProvider(_pages));
    final pending = ref.watch(pendingDeletesProvider);
    final dateFormat = ref.watch(dateFormatProvider);
    final today =
        ref.watch(dayBoundaryProvider).value ?? awStartOfDay(DateTime.now());

    return Scaffold(
      appBar: AppBar(title: Text('completed.title'.tr())),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: AwRefresh(
            indicatorKey: const Key('completed-refresh'),
            onRefresh: () async =>
                await ref.read(syncEngineProvider)?.syncNow() ?? true,
            child: tasks.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => AwErrorState(
                message: localizedError(error),
                onRetry: () => ref.invalidate(completedTasksProvider(_pages)),
                physics: const AlwaysScrollableScrollPhysics(),
              ),
              data: (raw) {
                final items = awWithoutPending(raw, pending, (t) => t.id);
                if (items.isEmpty) {
                  return AwEmptyState(
                    icon: Icons.check_circle_outline,
                    title: 'completed.emptyTitle'.tr(),
                    message: 'completed.emptyBody'.tr(),
                    physics: const AlwaysScrollableScrollPhysics(),
                  );
                }
                final rows = _rowsFor(items, dateFormat, today);
                return ListView.builder(
                  key: const Key('completed-list'),
                  controller: _scroll,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: awListPadding(context, top: AwSpace.x2),
                  // +1 for the scope line, which sits ABOVE the data the way
                  // the alarm log's does — the reader learns what they are
                  // looking at before they read it.
                  itemCount: rows.length + 1,
                  itemBuilder: (context, index) => index == 0
                      ? const _ScopeLine()
                      : rows[index - 1].build(context, ref),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// Flattens the page into day headers + rows. Pure enough to reason about:
  /// the only inputs are the list, the format and today's boundary.
  List<_Row> _rowsFor(List<Task> items, String dateFormat, DateTime today) {
    final rows = <_Row>[];
    DateTime? currentDay;
    for (final task in items) {
      final at = (task.dueAt ?? task.completedAt)?.toLocal();
      final day = at == null ? null : DateTime(at.year, at.month, at.day);
      if (day != currentDay) {
        currentDay = day;
        rows.add(_HeaderRow(day: day, today: today, dateFormat: dateFormat));
      }
      rows.add(_TaskRow(task: task, dateFormat: dateFormat));
    }
    return rows;
  }
}

/// What this screen does and does not contain, said once, above the data.
class _ScopeLine extends StatelessWidget {
  const _ScopeLine();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AwSpace.x2,
        AwSpace.x1,
        AwSpace.x2,
        AwSpace.x3,
      ),
      child: Text(
        'completed.scope'.tr(),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

sealed class _Row {
  Widget build(BuildContext context, WidgetRef ref);
}

class _HeaderRow implements _Row {
  _HeaderRow({
    required this.day,
    required this.today,
    required this.dateFormat,
  });

  final DateTime? day;
  final DateTime today;
  final String dateFormat;

  String get _label {
    if (day == null) return 'task.notSet'.tr();
    final diff = day!.difference(today).inDays;
    if (diff == 0) return 'completed.today'.tr();
    if (diff == -1) return 'completed.yesterday'.tr();
    return awFormatDate(day!, format: dateFormat);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AwSpace.x2,
        AwSpace.x4,
        AwSpace.x2,
        AwSpace.x1,
      ),
      child: Text(
        _label,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _TaskRow implements _Row {
  _TaskRow({required this.task, required this.dateFormat});

  final Task task;
  final String dateFormat;

  @override
  Widget build(BuildContext context, WidgetRef ref) => TaskTile(
    key: Key('completed-${task.id}'),
    task: task,
    // The archive's own action: put it back on the planning lists. It leaves
    // this screen when it does — that is the screen's contract, not a bug.
    trailingAction: IconButton(
      key: Key('reopen-${task.id}'),
      tooltip: 'completed.reopen'.tr(),
      visualDensity: VisualDensity.compact,
      icon: const Icon(Icons.replay, size: 18),
      onPressed: () async {
        final messenger = ScaffoldMessenger.of(context);
        await ref.read(taskStoreProvider).reopen(task.id);
        messenger.showSnackBar(
          SnackBar(
            content: Text('completed.reopened'.tr(args: {'title': task.title})),
          ),
        );
      },
    ),
  );
}
