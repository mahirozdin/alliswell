import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/pending_deletes.dart';
import '../../core/persisted_prefs.dart';
import '../../i18n/i18n.dart';
import '../../sections.dart';
import '../../sync/refresh.dart';
import '../../theme/tokens.dart';
import '../../widgets/list_detail.dart';
import '../../widgets/refreshable.dart';
import '../../widgets/snackbars.dart';
import '../tasks/data/task.dart';
import 'board_series.dart';
import '../tasks/providers.dart';
import '../tasks/ui/task_create_sheet.dart';
import '../tasks/ui/task_tile.dart';
import '../tasks/ui/task_visuals.dart';

/// Sentinel the move sheet returns for "delete" — not a status, so it can
/// never be mistaken for one by `_setStatus`.
const String _kDeleteAction = '__delete__';

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
  PageController? _pager;
  final ScrollController _columnsScroll = ScrollController();

  /// Whether the wide board has columns past its right edge (the fade).
  final ValueNotifier<bool> _moreRight = ValueNotifier(true);

  bool _trackEdge(ScrollNotification notification) {
    final metrics = notification.metrics;
    if (notification.depth == 0 && metrics.axis == Axis.horizontal) {
      _moreRight.value = metrics.extentAfter > 0.5;
    }
    return false;
  }

  @override
  void dispose() {
    _pager?.dispose();
    _columnsScroll.dispose();
    _moreRight.dispose();
    super.dispose();
  }

  /// Pull-to-refresh inside a column (OPH-171): the board is a VIEW of Home, so
  /// it refreshes exactly what Home refreshes.
  Future<bool> _refresh() => refreshSection(ref, AppSection.home);

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
    showAwActionSnackBar(
      messenger,
      content: Text(
        'board.moved'.tr(
          args: {'title': task.title, 'status': taskStatusLabel(status)},
        ),
      ),
      actionLabel: 'board.undo'.tr(),
      onAction: () => store.update(task.id, {'status': previous}),
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
      // OPH-212: the ROOT navigator. Pushed into a shell branch, a sheet
      // renders UNDER the shell's own glass bar and FAB — they are painted by
      // the Scaffold that owns the branch, above its body.
      useRootNavigator: true,
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
            // OPH-184 (DESIGN §19 D6): the board is the one list with no swipe,
            // so delete has to be reachable from here or the board would be the
            // one place a task cannot be deleted.
            const Divider(indent: AwSpace.x4, endIndent: AwSpace.x4),
            ListTile(
              key: const Key('board-delete'),
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(sheetContext).colorScheme.error,
              ),
              title: Text(
                'common.delete'.tr(),
                style: TextStyle(
                  color: Theme.of(sheetContext).colorScheme.error,
                ),
              ),
              onTap: () => Navigator.of(sheetContext).pop(_kDeleteAction),
            ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    if (picked == _kDeleteAction) {
      await deleteTaskWithUndo(context, ref, task);
      return;
    }
    await _setStatus(task, picked);
  }

  @override
  Widget build(BuildContext context) {
    final columns = parseBoardColumns(
      ref.watch(boardColumnsProvider),
      kTaskStatuses,
    );
    // The board's own source: every status, not just the planning set —
    // completed/cancelled/archived columns must have data to show.
    //
    // OPH-184: filtered here, not by the card. Board cards are deliberately
    // NOT wrapped in `AwSwipeToDelete` (D6), so they have nothing that hides
    // them while a delete is undoable — a task deleted from the move sheet
    // would sit in its column until the window closed.
    final tasks = awWithoutPending(
      ref.watch(boardTasksProvider).value ?? const <Task>[],
      ref.watch(pendingDeletesProvider),
      (t) => t.id,
    );
    final byStatus = <String, List<Task>>{for (final s in columns) s: []};
    for (final task in tasks) {
      byStatus[task.status]?.add(task);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // OPH-405: a task open in the desktop pane narrows the board; it
        // keeps its columns (scrolling sideways) rather than turning into the
        // phone's pager.
        final paneOpen = AwListDetailScope.isOpen(context, kAwTaskPane);
        final isWide = paneOpen || awWideContent(context, constraints);
        if (isWide) {
          // U-36 (DESIGN §51 D5): four columns share the width, none narrower
          // than [kBoardMinColumnWidth]; a fifth — or a narrow window — scrolls
          // sideways under a visible bar, and the edge that has more fades.
          final available = constraints.maxWidth - 2 * AwSpace.x3;
          final columnWidth = boardColumnWidth(available);
          final overflowing = columns.length * columnWidth > available + 0.5;
          // Metrics, not only scrolling: a column added or a pane opened
          // changes what is past the edge without moving the scroll.
          final board = NotificationListener<ScrollNotification>(
            onNotification: _trackEdge,
            child: NotificationListener<ScrollMetricsNotification>(
              onNotification: (n) => _trackEdge(n.asScrollUpdate()),
              child: Scrollbar(
                controller: _columnsScroll,
                thumbVisibility: overflowing,
                trackVisibility: overflowing,
                child: SingleChildScrollView(
                  key: const Key('board-columns'),
                  controller: _columnsScroll,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(
                    AwSpace.x3,
                    AwSpace.x2,
                    AwSpace.x3,
                    AwSpace.x4,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final status in columns)
                        SizedBox(
                          width: columnWidth,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AwSpace.x1,
                            ),
                            child: _BoardColumn(
                              status: status,
                              tasks: byStatus[status] ?? const [],
                              onDropped: _setStatus,
                              onMoveRequested: _showMoveSheet,
                              onRefresh: _refresh,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
          return AwListOrder(
            // ↑/↓ in the pane walk the board as it reads: down a column,
            // then on to the next one.
            ids: [
              for (final status in columns)
                for (final entry in foldBoardSeries(
                  status,
                  byStatus[status] ?? const [],
                ))
                  entry.task.id,
            ],
            child: Stack(
              children: [
                board,
                if (overflowing) _ColumnsEdgeFade(more: _moreRight),
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
                            onRefresh: _refresh,
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
    required this.onRefresh,
  });

  final String status;
  final List<Task> tasks;
  final void Function(Task task, String status) onDropped;
  final void Function(Task task) onMoveRequested;
  final Future<bool> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // OPH-394 (E-25): a series shows its next occurrence once, and the count
    // is the cards the column shows.
    final entries = foldBoardSeries(status, tasks);
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
                      '${entries.length}',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                // OPH-171: each column's card list pulls to refresh (§15). The
                // horizontal pager is untouched, and a quick drag down beats
                // the card's 200 ms long-press drag, so both gestures live.
                child: entries.isEmpty
                    ? _EmptyColumn(status: status, dragging: highlighted)
                    : AwRefresh(
                        indicatorKey: Key('board-refresh-$status'),
                        onRefresh: onRefresh,
                        child: ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(
                            AwSpace.x2,
                            AwSpace.x1,
                            AwSpace.x2,
                            AwSpace.x2,
                          ),
                          itemCount: entries.length,
                          itemBuilder: (context, index) => _BoardCard(
                            task: entries[index].task,
                            moreOccurrences: entries[index].moreOccurrences,
                            onMoveRequested: onMoveRequested,
                          ),
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
  const _BoardCard({
    required this.task,
    required this.onMoveRequested,
    this.moreOccurrences = 0,
  });

  final Task task;
  final void Function(Task task) onMoveRequested;

  /// Later occurrences of this series the card stands for (OPH-394, E-25).
  final int moreOccurrences;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // No project badge on the board: a 320-px status column has no room for
    // it beside the title, and the column is already a status grouping. The
    // move affordance takes the row's one right-hand slot instead (DESIGN §46
    // R6), on the title's first line.
    //
    // No swipe-to-delete either (OPH-184, DESIGN §19 D6): the horizontal
    // gesture belongs to the phone pager, and a 200 ms long-press drag already
    // competes for this card. Delete lives in the move sheet.
    final tile = TaskTile(
      task: task,
      showProjectBadge: false,
      swipeToDelete: false,
      trailingAction: IconButton(
        key: Key('board-move-button-${task.id}'),
        tooltip: 'board.move'.tr(),
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.swap_horiz, size: 18),
        onPressed: () => onMoveRequested(task),
      ),
    );
    final card = moreOccurrences == 0
        ? tile
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              tile,
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  AwSpace.x4,
                  0,
                  AwSpace.x4,
                  AwSpace.x2,
                ),
                child: Text(
                  'board.moreOccurrences'.tr(
                    args: {'count': '$moreOccurrences'},
                  ),
                  key: Key('board-more-${task.id}'),
                  textAlign: TextAlign.end,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
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
          // opacity-ok: the card under the finger, and the one place §20 C3's
          // ban does not bite — 0.85 measures 5.22:1 at its worst pair (light
          // variant text), so it clears the 4.5:1 floor with the wrapper on.
          // It also has to be a layer rather than a colour: it floats over
          // whatever it is dragged across, so there is no second colour to
          // blend against.
          child: Opacity(
            opacity: 0.85,
            child: Transform.scale(scale: 1.04, child: TaskTile(task: task)),
          ),
        ),
      ),
      // opacity-ok: the HOLE the card left, not something to read. The card
      // itself is under the finger at full strength; this is the placeholder
      // saying "it came from here", and DESIGN §5's floors are about text a
      // user is asked to read.
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
    // OPH-212: the ROOT navigator. Pushed into a shell branch, a sheet
    // renders UNDER the shell's own glass bar and FAB — they are painted by
    // the Scaffold that owns the branch, above its body.
    useRootNavigator: true,
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

/// The narrowest a board column gets on a wide layout (U-36).
const double kBoardMinColumnWidth = 260;

/// A wide board column: a quarter of [available], never below
/// [kBoardMinColumnWidth] — so four columns fit a desktop window and a fifth
/// is one scroll away instead of a cut-off edge (OPH-405).
double boardColumnWidth(double available) =>
    math.max(kBoardMinColumnWidth, available / 4);

/// The 24 px fade on the edge of the board that has more columns past it
/// (consolidated §3: a horizontal row ends in a fade, so a cut card reads as
/// "more", not as a fault). Paint in the page colour, never glass (G1), and
/// it takes no touches.
class _ColumnsEdgeFade extends StatelessWidget {
  const _ColumnsEdgeFade({required this.more});

  /// Whether there are columns past the right edge.
  final ValueListenable<bool> more;

  @override
  Widget build(BuildContext context) {
    final tokens = context.awTokens;
    final page = Color.alphaBlend(tokens.veil, tokens.auroraBottom);
    return Positioned(
      top: 0,
      bottom: 0,
      right: 0,
      width: AwSpace.x6,
      child: IgnorePointer(
        child: ValueListenableBuilder<bool>(
          valueListenable: more,
          builder: (context, more, _) => more
              ? DecoratedBox(
                  key: const Key('board-edge-fade'),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [page.withValues(alpha: 0), page],
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ),
    );
  }
}
