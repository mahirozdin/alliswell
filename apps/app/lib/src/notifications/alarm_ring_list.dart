import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/date_format.dart';
import '../core/date_input.dart';
import '../core/day_boundary.dart';
import '../core/persisted_prefs.dart';
import '../core/tr_locative.dart';
import '../features/tasks/data/task_store.dart';
import '../i18n/i18n.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/status_views.dart';
import '../widgets/word_safe_text.dart';
import 'alarm_action_tile.dart';
import 'alarm_edge_fade.dart';
import 'alarm_log.dart';
import 'alarm_minute_tick.dart';
import 'alarm_overlay.dart';
import 'alarm_ring_screen.dart';
import 'alarm_snooze_sheet.dart';
import 'planner.dart';
import 'providers.dart';
import 'reminder_profile.dart';
import 'urgent_minute.dart';

/// How long a row takes to leave the list, and the list to give way to the
/// single layout (spec §1.7). Reduced motion: at once.
const Duration kAlarmRowExit = Duration(milliseconds: 220);

/// The snooze presets the "Tümünü ertele" grid offers (#47, spec §1.4): the
/// user's first three, never "Tomorrow morning" — every alarm quietly moved
/// to tomorrow is too much for one tap. "Pick a time…" follows them.
List<String> alarmBulkPresets(List<String> order) =>
    order.where((p) => p != 'tomorrow_morning').take(3).toList();

/// Upper case that keeps the Turkish dotted capital: "ACİL", not "ACIL".
String alarmUpper(String value) =>
    (AwI18n.instance.locale.languageCode == 'tr'
            ? value.replaceAll('i', 'İ')
            : value)
        .toUpperCase();

/// The first ringing occurrence of each task, in list order: one row per
/// task, as [AlarmOverlayController.actOnRow] answers a task.
List<AlarmInput> alarmRowsByTask(List<AlarmInput> ringing) {
  final seen = <String>{};
  return [
    for (final a in ringing)
      if (seen.add(a.taskId)) a,
  ];
}

/// Whether every row rings in one minute (the planner's UTC minute, ADR-0068):
/// only then does the list header name a time (X-05). Rows of several
/// minutes — a list grown while it rang — each show their own time.
bool alarmRowsShareMinute(List<AlarmInput> rows) =>
    {
      for (final a in rows)
        alarmFireAt(a).toUtc().millisecondsSinceEpoch ~/ 60000,
    }.length <=
    1;

/// The ring screen's list mode (#47, OPH-443, mockups A3/A8/A9): two or more
/// tasks ring in one minute, so ONE screen lists them under one sound. A
/// header (badge + "3 ACİL HATIRLATMA · 09:00"), the rows scrolling in the
/// middle, and the bulk answers pinned to the bottom: "Tümünü ertele" as the
/// same tile grid as the single layout, then "Tümünü onayla (3)".
///
/// Every answer goes through [AlarmOverlayController] (OPH-441): it silences
/// and dismisses in the tap and applies one in-app event. When one row is
/// left the shell's layer cross-fades back to the single layout.
class AlarmRingList extends ConsumerStatefulWidget {
  const AlarmRingList({
    super.key,
    required this.rows,
    this.failed = const {},
    this.late = const {},
    this.alarms = const [],
  });

  /// [AlarmOverlayState.ringing]: every ringing occurrence, earliest first.
  final List<AlarmInput> rows;

  /// Occurrence keys whose write failed ([AlarmOverlayState.failed]).
  final Set<String> failed;

  /// Occurrence keys first shown late ([AlarmOverlayState.late]): the
  /// header's time says how late when its alarm is one of them.
  final Set<String> late;

  /// The planner's active alarms, for "… · with another alarm" (#47).
  final List<AlarmInput> alarms;

  @override
  ConsumerState<AlarmRingList> createState() => _AlarmRingListState();
}

class _AlarmRingListState extends ConsumerState<AlarmRingList>
    with AlarmMinuteTick {
  /// Rows on their way out (220 ms), by task id.
  final Map<String, AlarmInput> _leaving = {};

  /// Occurrences this list logged as shown.
  final Set<String> _logged = {};

  bool _reduceMotion = false;

  AlarmOverlayController get _controller =>
      ref.read(alarmOverlayControllerProvider.notifier);

  /// The bulk tiles' clock (W-03): they rebuild when its minute changes.
  @override
  DateTime Function() get minuteClock => ref.read(nowProvider);

  @override
  void initState() {
    super.initState();
    _logShown(widget.rows);
    // A screen reader hears how many ring, and when (spec §1.8).
    WidgetsBinding.instance.addPostFrameCallback((_) => _announce());
  }

  @override
  void didUpdateWidget(AlarmRingList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final now = {for (final a in widget.rows) a.taskId};
    _leaving.removeWhere((task, _) => now.contains(task));
    if (!_reduceMotion) {
      for (final a in alarmRowsByTask(oldWidget.rows)) {
        if (!now.contains(a.taskId)) _leaving[a.taskId] = a;
      }
    }
    _logShown(widget.rows);
  }

  /// The one alarm surface we can prove rang (OPH-176): each row, once.
  void _logShown(List<AlarmInput> rows) {
    for (final a in rows) {
      if (!_logged.add(alarmOccurrenceKey(a))) continue;
      unawaited(
        ref
            .read(alarmLogProvider)
            .record(
              event: AlarmLogEvent.ringShown,
              lane: AlarmLogLane.inapp,
              kind: a.kind,
              urgent: a.urgent,
              fireAt: alarmFireAt(a),
              taskId: a.taskId,
              reminderId: a.reminderId,
            )
            .catchError((Object _) {}),
      );
    }
  }

  /// W-05: the user's time format, as on the tiles and the confirmations.
  String _clock(DateTime at) =>
      awFormatTime(at.toLocal(), format: ref.read(dateFormatProvider));

  void _announce() {
    if (!mounted) return;
    final tasks = alarmRowsByTask(widget.rows);
    if (tasks.isEmpty) return;
    // X-05: a time only when the rows share it.
    final message = alarmRowsShareMinute(tasks)
        ? 'alarm.ringing.announceList'.tr(
            args: {
              'count': '${tasks.length}',
              'time': _clock(alarmFireAt(tasks.first)),
            },
          )
        : 'alarm.ringing.count'.tr(args: {'count': '${tasks.length}'});
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        message,
        Directionality.of(context),
      ).catchError((Object _) {}),
    );
  }

  // ── Answers ────────────────────────────────────────────────────────────

  /// Shows [message] on the messenger captured now, once the write landed —
  /// the screen is gone by then (spec §1.6 confirmations).
  void Function() _sayLater(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    return () => messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  /// "09:05’te" in Turkish, "09:05" elsewhere (#46, OPH-422).
  String _at(DateTime until) => awAt(
    awFormatTime(until, format: ref.read(dateFormatProvider)),
    languageCode: AwI18n.instance.locale.languageCode,
  );

  int get _count => alarmRowsByTask(widget.rows).length;

  void _snoozeAll(String preset) => _snoozeAllUntil(
    TaskStore.snoozeUntilFor(preset, now: ref.read(nowProvider)()),
  );

  void _snoozeAllUntil(DateTime until) {
    final say = _sayLater(
      'alarm.snoozedAllConfirmed'.tr(
        args: {'count': '$_count', 'time': _at(until)},
      ),
    );
    unawaited(_controller.snoozeAll(until, onSaved: say));
  }

  void _acknowledgeAll() {
    final say = _sayLater(
      'alarm.acknowledgedAll'.tr(args: {'count': '$_count'}),
    );
    unawaited(_controller.acknowledgeAll(onSaved: say));
  }

  void _row(
    AlarmInput row,
    AlarmRowAction action, {
    void Function()? onSaved,
  }) => unawaited(_controller.actOnRow(row.taskId, action, onSaved: onSaved));

  void _snoozeRow(AlarmInput row, DateTime until) => _row(
    row,
    AlarmRowAction.snooze(until),
    onSaved: _sayLater('alarm.snoozeConfirmed'.tr(args: {'time': _at(until)})),
  );

  /// The card and the sheet's "Aç": silence, dismiss this row, open the task.
  /// Nothing is acknowledged; the other rows wait for the way back.
  void _open(AlarmInput row) => _dismissToOpen(row)();

  /// Silences and dismisses [row] now; the returned call opens its task —
  /// at once from the card, once the sheet is closed from the sheet.
  void Function() _dismissToOpen(AlarmInput row) {
    final router = GoRouter.of(context);
    final controller = _controller;
    final occurrences = [
      for (final a in widget.rows)
        if (a.taskId == row.taskId) a,
    ];
    controller.silence();
    for (final a in occurrences) {
      controller.stopAlarmKit(a);
      controller.handled(a);
    }
    return () => router.push('/tasks/${row.taskId}');
  }

  /// Whether anything rings this list right now: the in-app sound, or an
  /// AlarmKit alert covering a row.
  bool _sounding() =>
      _controller.sounding || widget.rows.any(_controller.ringsOnLockScreen);

  /// The person is dealing with it — a sheet or the pickers open over the
  /// list: quiet now, every sound source. Returns what to do on a back-out.
  void Function() _quietFor() {
    final controller = _controller;
    final wasSounding = _sounding();
    controller.silence();
    for (final a in widget.rows) {
      controller.stopAlarmKit(a);
    }
    return () {
      // Nothing was answered: the list rings again.
      if (wasSounding && mounted) controller.startSound();
    };
  }

  Future<void> _openSheet(AlarmInput row) async {
    final backOut = _quietFor();
    void Function()? openTask;
    final chosen = await showAlarmSnoozeSheet(
      context,
      alarm: row,
      presets: ref.read(snoozePresetOrderProvider),
      now: ref.read(nowProvider),
      dateFormat: ref.read(dateFormatProvider),
      // X-04: a preset landing in a minute another task's urgent alarm
      // holds says so, as the single layout's tile does.
      alarms: widget.alarms,
      onChoose: (choice) => switch (choice) {
        AlarmSheetSnooze(:final until) => _snoozeRow(row, until),
        AlarmSheetCustom() => unawaited(_pickTime(row: row, backOut: backOut)),
        AlarmSheetMute() => _row(
          row,
          AlarmRowAction.mute,
          onSaved: _sayLater('task.alarmsMuted'.tr()),
        ),
        AlarmSheetComplete() => _row(row, AlarmRowAction.complete),
        AlarmSheetOpen() => openTask = _dismissToOpen(row),
      },
    );
    if (!chosen) backOut();
    // Pushed once the sheet's route is off the stack, not while it pops.
    openTask?.call();
  }

  /// "Saat seç…" for one row, or for every row when [row] is null: the same
  /// date and time pickers as the single layout, anchored on the same
  /// instant (half an hour from now).
  Future<void> _pickTime({
    AlarmInput? row,
    required void Function() backOut,
  }) async {
    final now = DateTime.now();
    final suggested = now.add(const Duration(minutes: 30));
    final date = await showDatePicker(
      context: context,
      initialDate: awInitialPickerDate(anchor: suggested, now: now),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (!mounted) return;
    if (date == null) return backOut();
    final time = await awShowTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(suggested),
    );
    if (!mounted) return;
    // Cancelling the time is backing out too: no snooze to a guessed minute.
    if (time == null) return backOut();
    final until = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (!until.isAfter(DateTime.now())) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text('alarm.snoozePast'.tr())));
      return backOut();
    }
    if (row == null) {
      _snoozeAllUntil(until);
    } else {
      _snoozeRow(row, until);
    }
  }

  // ── Layout ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.awTokens;
    final text = Theme.of(context).textTheme;
    final dateFormat = ref.watch(dateFormatProvider);
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    final screen = MediaQuery.sizeOf(context);
    final short = screen.height < kAlarmShortScreenHeight;
    final oneColumn =
        MediaQuery.textScalerOf(context).scale(14) / 14 >
        kAlarmOneColumnTextScale;

    final background = Color.alphaBlend(
      tokens.prioUrgent.withValues(alpha: 0.10),
      scheme.surface,
    );
    final tasks = alarmRowsByTask(widget.rows);
    final count = tasks.length;
    // X-05: the header named the oldest row's time for rows of several
    // minutes; then only the count, each card says its own time.
    final oneMinute = alarmRowsShareMinute(tasks);
    final clock = tasks.isEmpty ? '' : _clock(alarmFireAt(tasks.first));
    final time =
        tasks.isNotEmpty &&
            widget.late.contains(alarmOccurrenceKey(tasks.first))
        ? 'alarm.ringing.late'.tr(
            args: {
              'time': clock,
              'ago': awRelativePast(
                alarmFireAt(tasks.first),
                ref.read(alarmClockProvider)(),
              ),
            },
          )
        : clock;

    final headerStyle = awTabular(
      text.labelLarge!.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
      ),
    );
    // X-07: a heading node of its own — without `container` it merged into
    // the screen's node and named the whole list.
    final header = Semantics(
      container: true,
      header: true,
      child: Row(
        key: const Key('alarm-list-header'),
        children: [
          _PulseBadge(
            size: short ? 48 : 56,
            color: tokens.prioUrgent,
            pulse: !_reduceMotion,
          ),
          const SizedBox(width: AwSpace.x3),
          Expanded(
            // W-13, mockup A3: the count in the urgent ink, the time in
            // the page's own ink, as the single layout's label and time.
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: alarmUpper(
                      'alarm.ringing.count'.tr(args: {'count': '$count'}),
                    ),
                    style: headerStyle.copyWith(color: tokens.errorOnPage),
                  ),
                  if (oneMinute)
                    TextSpan(
                      text: ' · $time',
                      style: headerStyle.copyWith(color: scheme.onSurface),
                    ),
                ],
              ),
              key: const Key('alarm-list-header-text'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: headerStyle,
            ),
          ),
        ],
      ),
    );

    // The rows on screen: the ringing ones plus those still leaving.
    final shown = [...tasks, ..._leaving.values]
      ..sort((a, b) {
        final at = alarmFireAt(a).compareTo(alarmFireAt(b));
        if (at != 0) return at;
        final task = a.taskId.compareTo(b.taskId);
        return task != 0 ? task : a.reminderId.compareTo(b.reminderId);
      });
    final failedTasks = {
      for (final a in widget.rows)
        if (widget.failed.contains(alarmOccurrenceKey(a))) a.taskId,
    };
    Widget rowAt(int i) {
      final row = shown[i];
      final leaving = _leaving.containsKey(row.taskId);
      return _RowExit(
        key: ValueKey<String>('exit-${row.taskId}'),
        leaving: leaving,
        onGone: () {
          if (mounted) setState(() => _leaving.remove(row.taskId));
        },
        child: Padding(
          padding: const EdgeInsets.only(bottom: AwSpace.x2),
          child: _card(row, failed: failedTasks.contains(row.taskId)),
        ),
      );
    }

    final bulk = _bulk(
      count: count,
      dateFormat: dateFormat,
      oneColumn: oneColumn,
      failed: failedTasks.isNotEmpty,
    );
    final status = _status(oneColumn);

    // Desktop and web: the list column is centred as the single layout's.
    final wide = screen.width >= kAwWideBreakpoint;
    final Widget body;
    if (oneColumn) {
      // Past 1.3 the grid is one column and nothing fits pinned: the whole
      // screen scrolls as one page (spec §1.8).
      body = SingleChildScrollView(
        key: const Key('alarm-ring-rows'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            status,
            const SizedBox(height: AwSpace.x3),
            for (var i = 0; i < shown.length; i++) rowAt(i),
            const SizedBox(height: AwSpace.x2),
            bulk,
          ],
        ),
      );
    } else {
      // Only the rows scroll; the bulk answers stay where the thumb is. A
      // card cut by the edge fades out (W-15), so it reads as "more below".
      final rows = AlarmEdgeFade(
        child: ListView.builder(
          key: const Key('alarm-ring-rows'),
          padding: EdgeInsets.zero,
          shrinkWrap: wide,
          itemCount: shown.length,
          itemBuilder: (_, i) => rowAt(i),
        ),
      );
      body = Column(
        // Desktop: header, rows and answers centre together (W-13).
        mainAxisSize: wide ? MainAxisSize.min : MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          status,
          const SizedBox(height: AwSpace.x3),
          if (wide) Flexible(child: rows) else Expanded(child: rows),
          Divider(height: 1, thickness: 1, color: tokens.hairline),
          const SizedBox(height: AwSpace.x3),
          bulk,
        ],
      );
    }

    return PopScope(
      // Answered with a button; back does not dismiss it.
      canPop: false,
      // OPH-393 (E-20): nothing behind the list is in the semantics tree.
      child: BlockSemantics(
        // X-07: a group with no name of its own; the header, each card with
        // its two buttons, the tiles and "Acknowledge all" are nodes of their
        // own, in reading order (spec §1.8).
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          child: Material(
            key: const Key('alarm-ring-list'),
            color: background,
            child: CallbackShortcuts(
              bindings: _shortcuts(),
              child: SafeArea(
                // W-13: the single layout's 24 pt side margins and its column
                // (at most 440 wide, centred).
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AwSpace.x6,
                    AwSpace.x4,
                    AwSpace.x6,
                    AwSpace.x4,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: kAlarmRingMaxWidth,
                      ),
                      child: body,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Enter = Tümünü onayla, 1–3 = the bulk presets, Esc = nothing (A2).
  Map<ShortcutActivator, VoidCallback> _shortcuts() {
    const digits = [
      [LogicalKeyboardKey.digit1, LogicalKeyboardKey.numpad1],
      [LogicalKeyboardKey.digit2, LogicalKeyboardKey.numpad2],
      [LogicalKeyboardKey.digit3, LogicalKeyboardKey.numpad3],
    ];
    final presets = alarmBulkPresets(ref.read(snoozePresetOrderProvider));
    return {
      const SingleActivator(LogicalKeyboardKey.enter): _acknowledgeAll,
      const SingleActivator(LogicalKeyboardKey.numpadEnter): _acknowledgeAll,
      const SingleActivator(LogicalKeyboardKey.escape): () {},
      for (var i = 0; i < digits.length && i < presets.length; i++)
        for (final key in digits[i])
          SingleActivator(key): () => _snoozeAll(presets[i]),
    };
  }

  /// The silence line under the header — the same three cases as the single
  /// layout (OPH-316/393, #46), so a quiet list never looks like a failure.
  Widget _status(bool oneColumn) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final silent = ref.watch(
      alarmOverlayControllerProvider.select((s) => s.silentHere),
    );
    final onLockScreen =
        silent &&
        ref.watch(
          alarmOverlayControllerProvider.select((s) => s.ringsOnLockScreen),
        );
    final style = text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant);
    if (onLockScreen) {
      return Padding(
        padding: const EdgeInsets.only(top: AwSpace.x3),
        child: Text(
          'alarm.ringingOnLockScreen'.tr(),
          key: const Key('alarm-rings-on-lock-screen'),
          style: style,
        ),
      );
    }
    if (silent) {
      final chosen = ref.watch(alarmSilenceChosenProvider);
      return Padding(
        padding: const EdgeInsets.only(top: AwSpace.x3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              chosen
                  ? 'alarm.silentByChoice'.tr()
                  : 'alarm.silentByDefault'.tr(),
              key: chosen
                  ? const Key('alarm-silent-declared')
                  : const Key('alarm-silent-default'),
              style: style,
            ),
            const SizedBox(height: AwSpace.x2),
            _startSoundTile(oneColumn),
          ],
        ),
      );
    }
    return ValueListenableBuilder<bool>(
      valueListenable: _controller.soundBlocked,
      builder: (context, blocked, _) => blocked
          ? Padding(
              padding: const EdgeInsets.only(top: AwSpace.x3),
              child: _startSoundTile(oneColumn),
            )
          : const SizedBox.shrink(),
    );
  }

  Widget _startSoundTile(bool wrap) => AwAlarmActionTile(
    key: const Key('alarm-start-sound'),
    label: 'alarm.startSound'.tr(),
    icon: Icons.volume_up,
    wrap: wrap,
    minHeight: 48,
    onPressed: () => _controller.startSound(),
  );

  /// One row (spec §1.4): radius 20, `surface`, a hairline edge; the title
  /// (2 lines at most), its time, and two equal 44 pt pills. The card itself
  /// is "Aç".
  Widget _card(AlarmInput row, {required bool failed}) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.awTokens;
    final text = Theme.of(context).textTheme;
    final id = row.taskId;
    return Material(
      key: Key('alarm-row-$id'),
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AwRadius.l),
        side: BorderSide(color: tokens.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(row),
        child: Padding(
          padding: const EdgeInsets.all(AwSpace.x4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: AwWordSafeText(
                      row.taskTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyLarge?.copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (failed) ...[
                    const SizedBox(width: AwSpace.x2),
                    Tooltip(
                      message: 'alarm.row.failed'.tr(),
                      child: Icon(
                        Icons.error_outline,
                        key: Key('alarm-row-failed-$id'),
                        size: 20,
                        color: tokens.errorOnPage,
                        semanticLabel: 'alarm.row.failed'.tr(),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: AwSpace.x1),
              Text(
                _clock(alarmFireAt(row)),
                style: awTabular(
                  text.bodySmall!.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: AwSpace.x3),
              Row(
                children: [
                  Expanded(
                    child: _pill(
                      'alarm-row-snooze-$id',
                      label: 'alarm.ringing.snooze'.tr(),
                      icon: Icons.arrow_drop_down,
                      iconAtEnd: true,
                      onPressed: () => unawaited(_openSheet(row)),
                    ),
                  ),
                  const SizedBox(width: AwSpace.x2),
                  Expanded(
                    child: _pill(
                      'alarm-row-ack-$id',
                      label: 'notif.action.acknowledge'.tr(),
                      icon: Icons.check,
                      onPressed: () => _row(row, AlarmRowAction.acknowledge),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill(
    String key, {
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
    bool iconAtEnd = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return OutlinedButton.icon(
      key: Key(key),
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(kAwAlarmRowPillHeight),
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        side: BorderSide(color: scheme.outline),
        iconAlignment: iconAtEnd ? IconAlignment.end : IconAlignment.start,
      ),
      icon: Icon(icon, size: 18),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }

  /// "Tümünü ertele" (label, the 2×2 grid) and "Tümünü onayla (N)", with the
  /// failed-write error and "Tekrar dene" above them when a write failed.
  Widget _bulk({
    required int count,
    required String dateFormat,
    required bool oneColumn,
    required bool failed,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final now = ref.watch(nowProvider)();
    final members = {for (final a in widget.rows) a.taskId};
    final presets = alarmBulkPresets(ref.watch(snoozePresetOrderProvider));
    final tiles = <Widget>[
      for (final preset in presets)
        AwAlarmActionTile(
          key: Key('alarm-all-snooze-$preset'),
          label: kSnoozePresetLabels[preset]!.tr(),
          semanticLabel: kSnoozePresetSpokenLabels[preset]!.tr(),
          subline: () {
            final until = TaskStore.snoozeUntilFor(preset, now: now);
            final others = urgentAlarmsInMinute(
              widget.alarms,
              until,
              exceptTaskIds: members,
            );
            return snoozeTileSubline(
              until,
              joinsGroup: others > 0,
              format: dateFormat,
            );
          }(),
          wrap: oneColumn,
          onPressed: () => _snoozeAll(preset),
        ),
      AwAlarmActionTile(
        key: const Key('alarm-all-snooze-custom'),
        label: 'alarm.snoozeCustom'.tr(),
        icon: Icons.schedule,
        wrap: oneColumn,
        onPressed: () {
          final backOut = _quietFor();
          unawaited(_pickTime(backOut: backOut));
        },
      ),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (failed) ...[
          AwInlineError(
            message: 'alarm.actionFailed'.tr(),
            textKey: const Key('alarm-action-failed'),
          ),
          const SizedBox(height: AwSpace.x2),
          AwAlarmActionTile(
            key: const Key('alarm-retry'),
            label: 'alarm.retry'.tr(),
            icon: Icons.refresh,
            wrap: oneColumn,
            minHeight: 48,
            onPressed: () => unawaited(_controller.retryFailed()),
          ),
          const SizedBox(height: AwSpace.x3),
        ],
        Semantics(
          container: true,
          header: true,
          child: Text(
            'alarm.snoozeAll'.tr(),
            key: const Key('alarm-snooze-all-label'),
            style: text.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: AwSpace.x2),
        _grid(tiles, oneColumn: oneColumn),
        const SizedBox(height: AwSpace.x4),
        FilledButton.icon(
          key: const Key('alarm-acknowledge-all'),
          // Keyboard: the first focus is the primary answer (Enter, too).
          autofocus: true,
          onPressed: _acknowledgeAll,
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
            minimumSize: const Size.fromHeight(kAwAlarmTileHeight),
            textStyle: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          icon: const Icon(Icons.done_all),
          label: Text('alarm.acknowledgeAll'.tr(args: {'count': '$count'})),
        ),
      ],
    );
  }

  /// The single layout's grid: two equal columns, or one past 1.3.
  Widget _grid(List<Widget> tiles, {required bool oneColumn}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < tiles.length; i += oneColumn ? 1 : 2) ...[
          if (i > 0) const SizedBox(height: AwSpace.x2),
          if (oneColumn)
            tiles[i]
          else
            Row(
              children: [
                Expanded(child: tiles[i]),
                const SizedBox(width: AwSpace.x2),
                Expanded(
                  child: i + 1 < tiles.length
                      ? tiles[i + 1]
                      : const SizedBox.shrink(),
                ),
              ],
            ),
        ],
      ],
    );
  }
}

/// A row pill's height (G4: row pills 44).
const double kAwAlarmRowPillHeight = 44;

/// A row leaving the list: 220 ms size + fade (spec §1.7), untappable and
/// out of the semantics tree on its way.
class _RowExit extends StatefulWidget {
  const _RowExit({
    super.key,
    required this.leaving,
    required this.onGone,
    required this.child,
  });

  final bool leaving;
  final VoidCallback onGone;
  final Widget child;

  @override
  State<_RowExit> createState() => _RowExitState();
}

class _RowExitState extends State<_RowExit>
    with SingleTickerProviderStateMixin {
  late final AnimationController _exit = AnimationController(
    vsync: this,
    duration: kAlarmRowExit,
    value: widget.leaving ? 0 : 1,
  )..addStatusListener(_status);

  void _status(AnimationStatus status) {
    // In the frame that ends the exit, so the row is gone in the same frame.
    if (status == AnimationStatus.dismissed && widget.leaving) widget.onGone();
  }

  @override
  void didUpdateWidget(_RowExit oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.leaving && !oldWidget.leaving) {
      _exit.reverse();
    } else if (!widget.leaving && oldWidget.leaving) {
      _exit.value = 1;
    }
  }

  @override
  void dispose() {
    _exit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizeTransition(
    sizeFactor: _exit,
    alignment: Alignment.topCenter,
    child: FadeTransition(
      opacity: _exit,
      child: IgnorePointer(
        ignoring: widget.leaving,
        child: ExcludeSemantics(excluding: widget.leaving, child: widget.child),
      ),
    ),
  );
}

/// The list header's badge (56, 48 on a short screen) with the single
/// layout's pulse: a ring behind it growing to 4/3 and fading every 1200 ms;
/// none with reduced motion.
class _PulseBadge extends StatefulWidget {
  const _PulseBadge({
    required this.size,
    required this.color,
    required this.pulse,
  });

  final double size;
  final Color color;
  final bool pulse;

  @override
  State<_PulseBadge> createState() => _PulseBadgeState();
}

class _PulseBadgeState extends State<_PulseBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void initState() {
    super.initState();
    if (widget.pulse) _pulse.repeat();
  }

  @override
  void didUpdateWidget(_PulseBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulse && !_pulse.isAnimating) _pulse.repeat();
    if (!widget.pulse && _pulse.isAnimating) _pulse.stop();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final color = widget.color;
    final badge = Container(
      key: const Key('alarm-badge'),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color, width: 2),
      ),
      child: Icon(Icons.alarm, size: size / 2, color: color),
    );
    if (!widget.pulse) return badge;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          OverflowBox(
            maxWidth: size * 4 / 3,
            maxHeight: size * 4 / 3,
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) {
                final t = Curves.easeOut.transform(_pulse.value);
                final d = size + size / 3 * t;
                return Container(
                  width: d,
                  height: d,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: color.withValues(alpha: 0.4 * (1 - t)),
                      width: 2,
                    ),
                  ),
                );
              },
            ),
          ),
          badge,
        ],
      ),
    );
  }
}
