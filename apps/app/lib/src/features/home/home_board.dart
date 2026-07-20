import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/persisted_prefs.dart';
import '../../i18n/i18n.dart';
import '../../theme/tokens.dart';
import '../tasks/data/task.dart';
import '../tasks/providers.dart';
import '../tasks/ui/task_create_sheet.dart';
import '../tasks/ui/task_tile.dart';
import '../tasks/ui/task_visuals.dart';

/// Home's Pano (kanban) view — round 8, OPH-168, DESIGN §14 K1…K6.
///
/// Columns are task statuses the user chose to see (K2); cards are the task
/// row's DNA (K5). Moving is bimodal (K3): long-press drag onto any column
/// body (the WHOLE column accepts — no precise slot), or the card's explicit
/// move affordance → status sheet, which is also the accessibility path and
/// the only path that reaches HIDDEN statuses. Drops apply optimistically
/// with an undo snackbar (K5). Desktop/tablet lays classic fixed-width
/// columns; phones page one column at a time with a peek (K4).
class HomeBoard extends ConsumerStatefulWidget {
  const HomeBoard({super.key});

  @override
  ConsumerState<HomeBoard> createState() => _HomeBoardState();
}

class _HomeBoardState extends ConsumerState<HomeBoard> {
  static const _columnWidth = 320.0;

  PageController? _pager;

  @override
  void dispose() {
    _pager?.dispose();
    super.dispose();
  }

  Future<void> _setStatus(Task task, String status) async {
    if (status == task.status) return;
    final previous = task.status;
    final store = ref.read(taskStoreProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await store.update(task.id, {'status': status});
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text('task.couldNotSave'.tr())));
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'board.moved'.tr(
            args: {'title': task.title, 'status': taskStatusLabel(status)},
          ),
        ),
        action: SnackBarAction(
          label: 'board.undo'.tr(),
          onPressed: () => store.update(task.id, {'status': previous}),
        ),
      ),
    );
    // A polite announcement for screen readers (K5).
    if (mounted) {
      SemanticsService.sendAnnouncement(
        View.of(context),
        'board.moved'.tr(
          args: {'title': task.title, 'status': taskStatusLabel(status)},
        ),
        Directionality.of(context),
      );
    }
  }

  /// The explicit move path (K3b): every status, hidden columns included,
  /// current one checked. Works with taps alone — the a11y contract.
  Future<void> _showMoveSheet(Task task) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AwSpace.x4,
                0,
                AwSpace.x4,
                AwSpace.x2,
              ),
              child: Text(
                'board.moveTitle'.tr(),
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            for (final status in kTaskStatuses)
              ListTile(
                key: Key('board-move-$status'),
                leading: Icon(taskStatusIcon(status)),
                title: Text(taskStatusLabel(status)),
                trailing: status == task.status
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(status),
              ),
          ],
        ),
      ),
    );
    if (picked != null) await _setStatus(task, picked);
  }

  @override
  Widget build(BuildContext context) {
    final columns = parseBoardColumns(
      ref.watch(boardColumnsProvider),
      kTaskStatuses,
    );
    // The board's own source: every status, not just the planning set —
    // completed/cancelled/archived columns must have data to show.
    final tasks = ref.watch(boardTasksProvider).value ?? const <Task>[];
    final byStatus = <String, List<Task>>{for (final s in columns) s: []};
    for (final task in tasks) {
      byStatus[task.status]?.add(task);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 720;
        if (isWide) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: AwSpace.x3,
              vertical: AwSpace.x2,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final status in columns)
                  SizedBox(
                    width: _columnWidth,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AwSpace.x1,
                      ),
                      child: _BoardColumn(
                        status: status,
                        tasks: byStatus[status] ?? const [],
                        onDropped: _setStatus,
                        onMoveRequested: _showMoveSheet,
                      ),
                    ),
                  ),
              ],
            ),
          );
        }

        // Phone: one column ≈ 90% of the viewport so the neighbor peeks —
        // the "there's more" cue (K4). While a drag is live, the edge zones
        // below advance the pager.
        _pager ??= PageController(viewportFraction: 0.9);
        return Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: PageView(
                    key: const Key('board-pager'),
                    controller: _pager,
                    children: [
                      for (final status in columns)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AwSpace.x1,
                            vertical: AwSpace.x2,
                          ),
                          child: _BoardColumn(
                            status: status,
                            tasks: byStatus[status] ?? const [],
                            onDropped: _setStatus,
                            onMoveRequested: _showMoveSheet,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            _EdgeAdvanceZone(
              alignment: Alignment.centerLeft,
              onAdvance: () => _pager?.previousPage(
                duration: AwMotion.base,
                curve: Curves.easeOutCubic,
              ),
            ),
            _EdgeAdvanceZone(
              alignment: Alignment.centerRight,
              onAdvance: () => _pager?.nextPage(
                duration: AwMotion.base,
                curve: Curves.easeOutCubic,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// One status column: pinned header (name + count), the whole body one
/// [DragTarget] (K3a — magnetism, no precise slot), empty state that stays a
/// big drop target (K6).
class _BoardColumn extends StatelessWidget {
  const _BoardColumn({
    required this.status,
    required this.tasks,
    required this.onDropped,
    required this.onMoveRequested,
  });

  final String status;
  final List<Task> tasks;
  final void Function(Task task, String status) onDropped;
  final void Function(Task task) onMoveRequested;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DragTarget<Task>(
      onWillAcceptWithDetails: (details) => details.data.status != status,
      onAcceptWithDetails: (details) => onDropped(details.data, status),
      builder: (context, candidates, rejected) {
        final highlighted = candidates.isNotEmpty;
        return Container(
          key: Key('board-column-$status'),
          decoration: BoxDecoration(
            color: scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(AwRadius.l),
            border: highlighted
                ? Border.all(color: scheme.primary, width: 2)
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AwSpace.x3,
                  AwSpace.x3,
                  AwSpace.x3,
                  AwSpace.x1,
                ),
                child: Row(
                  children: [
                    Icon(
                      taskStatusIcon(status),
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: AwSpace.x2),
                    Expanded(
                      child: Text(
                        taskStatusLabel(status),
                        style: Theme.of(context).textTheme.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${tasks.length}',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: tasks.isEmpty
                    ? _EmptyColumn(status: status, dragging: highlighted)
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(
                          AwSpace.x2,
                          AwSpace.x1,
                          AwSpace.x2,
                          AwSpace.x2,
                        ),
                        itemCount: tasks.length,
                        itemBuilder: (context, index) => _BoardCard(
                          task: tasks[index],
                          onMoveRequested: onMoveRequested,
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A draggable task card: the task row's DNA (K5) plus an explicit move
/// affordance — the non-drag path is never hidden (K3b).
class _BoardCard extends StatelessWidget {
  const _BoardCard({required this.task, required this.onMoveRequested});

  final Task task;
  final void Function(Task task) onMoveRequested;

  @override
  Widget build(BuildContext context) {
    final card = Stack(
      children: [
        // No project badge on the board: a 320-px status column has no room
        // for it beside the title + status icons, and the column is already a
        // status grouping. (The move affordance sits where the badge would.)
        TaskTile(task: task, showProjectBadge: false),
        PositionedDirectional(
          top: 10,
          end: AwSpace.x1,
          child: IconButton(
            key: Key('board-move-button-${task.id}'),
            tooltip: 'board.move'.tr(),
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.swap_horiz, size: 18),
            onPressed: () => onMoveRequested(task),
          ),
        ),
      ],
    );
    return LongPressDraggable<Task>(
      data: task,
      delay: const Duration(milliseconds: 200),
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: 300,
          child: Opacity(
            opacity: 0.85,
            child: Transform.scale(scale: 1.04, child: TaskTile(task: task)),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: card),
      child: card,
    );
  }
}

/// K6 — an empty column is never zero-height: it stays a big drop target and
/// a creation affordance (status-preset create sheet).
class _EmptyColumn extends StatelessWidget {
  const _EmptyColumn({required this.status, required this.dragging});

  final String status;
  final bool dragging;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(AwSpace.x2),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AwRadius.m),
          border: Border.all(
            color: dragging ? scheme.primary : scheme.outlineVariant,
          ),
        ),
        child: Center(
          child: dragging
              ? Text(
                  'board.dropHere'.tr(),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                )
              : TextButton.icon(
                  key: Key('board-add-$status'),
                  onPressed: () =>
                      showTaskCreateSheet(context, initialStatus: status),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text('board.addTask'.tr()),
                ),
        ),
      ),
    );
  }
}

/// Phone drag helper (K4): hovering a drag over a screen edge advances the
/// pager one column. Invisible unless a drag is in flight over it.
class _EdgeAdvanceZone extends StatefulWidget {
  const _EdgeAdvanceZone({required this.alignment, required this.onAdvance});

  final Alignment alignment;
  final VoidCallback onAdvance;

  @override
  State<_EdgeAdvanceZone> createState() => _EdgeAdvanceZoneState();
}

class _EdgeAdvanceZoneState extends State<_EdgeAdvanceZone> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: widget.alignment,
      child: SizedBox(
        width: 48,
        height: double.infinity,
        child: DragTarget<Task>(
          // Never a real target: entering advances the pager after a beat,
          // the card still drops on a column.
          onWillAcceptWithDetails: (details) {
            if (!_hovering) {
              _hovering = true;
              Future<void>.delayed(const Duration(milliseconds: 400), () {
                if (mounted && _hovering) widget.onAdvance();
                _hovering = false;
              });
            }
            return false;
          },
          onLeave: (_) => _hovering = false,
          builder: (context, candidates, rejected) => IgnorePointer(
            ignoring: true,
            child: AnimatedContainer(
              duration: AwMotion.fast,
              color: _hovering
                  ? scheme.primary.withValues(alpha: 0.08)
                  : Colors.transparent,
            ),
          ),
        ),
      ),
    );
  }
}

/// "Görünümü düzenle" (K2): visibility toggles + drag-reorder of statuses;
/// the preference is device-local and permanent.
Future<void> showBoardColumnsSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => const _BoardColumnsSheet(),
  );
}

class _BoardColumnsSheet extends ConsumerStatefulWidget {
  const _BoardColumnsSheet();

  @override
  ConsumerState<_BoardColumnsSheet> createState() => _BoardColumnsSheetState();
}

class _BoardColumnsSheetState extends ConsumerState<_BoardColumnsSheet> {
  late List<String> _order;
  late Set<String> _visible;

  @override
  void initState() {
    super.initState();
    final visible = parseBoardColumns(
      ref.read(boardColumnsProvider),
      kTaskStatuses,
    );
    _visible = visible.toSet();
    // Visible statuses first in their saved order, hidden ones after in
    // canonical order — one list, reorderable.
    _order = [
      ...visible,
      for (final s in kTaskStatuses)
        if (!_visible.contains(s)) s,
    ];
  }

  Future<void> _persist() async {
    final value = [
      for (final s in _order)
        if (_visible.contains(s)) s,
    ].join(',');
    await ref
        .read(boardColumnsProvider.notifier)
        .set(value.isEmpty ? 'open' : value);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AwSpace.x4,
          0,
          AwSpace.x4,
          AwSpace.x4,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'board.editColumns'.tr(),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'board.editColumnsHint'.tr(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ReorderableListView(
                shrinkWrap: true,
                buildDefaultDragHandles: true,
                onReorderItem: (oldIndex, newIndex) {
                  setState(() {
                    final moved = _order.removeAt(oldIndex);
                    _order.insert(newIndex, moved);
                  });
                  _persist();
                },
                children: [
                  for (final status in _order)
                    SwitchListTile(
                      key: Key('board-column-toggle-$status'),
                      secondary: Icon(taskStatusIcon(status)),
                      title: Text(taskStatusLabel(status)),
                      value: _visible.contains(status),
                      onChanged: (on) {
                        setState(() {
                          on ? _visible.add(status) : _visible.remove(status);
                        });
                        _persist();
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
