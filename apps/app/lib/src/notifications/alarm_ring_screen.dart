import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/date_format.dart';
import '../core/day_boundary.dart';
import '../core/persisted_prefs.dart';
import '../core/tr_locative.dart';
import '../features/tasks/data/task_store.dart';
import '../features/tasks/providers.dart';
import '../i18n/i18n.dart';
import '../theme/tokens.dart';
import 'alarm_action_tile.dart';
import 'alarm_log.dart';
import 'reminder_profile.dart';
import 'alarm_overlay.dart';
import 'alarm_ring_list.dart';
import 'planner.dart';
import 'providers.dart';
import 'urgent_minute.dart';
import '../theme/typography.dart';
import '../widgets/status_views.dart';
import '../widgets/word_safe_text.dart';

/// Under this screen height the ring screen takes its short form (A6/A7):
/// badge 64, title at most 2 lines, no "Snooze" section label.
const double kAlarmShortScreenHeight = 700;

/// Past this text scale the snooze grid is one column and the screen scrolls.
const double kAlarmOneColumnTextScale = 1.3;

/// The ring screen's column: screen − 2 × 24, at most 440 (2 × 216 + 8).
const double kAlarmRingMaxWidth = 440;

/// The shell's alarm layer. One ringing task: the single layout, keyed by
/// [alarmOccurrenceKey] (#46) — unkeyed, the next alarm inherited the previous
/// screen's State, its pulse, its log entry and a "busy" flag that left every
/// button dead. Two or more tasks: the list (#47, OPH-443), in place, under
/// the same one sound; list and single cross-fade in 220 ms (at once with
/// reduced motion), so the last row left comes back as the full layout.
class AlarmOverlayLayer extends ConsumerWidget {
  const AlarmOverlayLayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overlay = ref.watch(alarmOverlayControllerProvider);
    if (overlay.ringing.isEmpty) return const SizedBox.shrink();
    final alarms = ref.watch(alarmFeedProvider).value ?? const <AlarmInput>[];
    final Widget child;
    if (alarmRowsByTask(overlay.ringing).length > 1) {
      child = AlarmRingList(
        key: const ValueKey<String>('alarm-ring-list-mode'),
        rows: overlay.ringing,
        failed: overlay.failed,
        alarms: alarms,
      );
    } else {
      final alarm = overlay.ringing.first;
      // One switcher key for every single occurrence: only list ⇄ single
      // cross-fades; the occurrence key inside still re-creates the screen.
      child = KeyedSubtree(
        key: const ValueKey<String>('alarm-ring-single'),
        child: AlarmRingScreen(
          key: ValueKey<String>(alarmOccurrenceKey(alarm)),
          alarm: alarm,
          failed: overlay.isFailed(alarm),
          // The snooze tiles say when a target minute already rings (#47).
          alarms: alarms,
          onHandled: (_) =>
              ref.read(alarmOverlayControllerProvider.notifier).handled(alarm),
        ),
      );
    }
    return AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : kAlarmRowExit,
      child: child,
    );
  }
}

/// Full-screen "alarm ringing" surface (OPH-143). Shown while an URGENT alarm is
/// due and the app is open — desktop/web's only alarm surface, and the
/// foreground companion to the OS notification on mobile. Solid surface (DESIGN
/// G1: glass is chrome-only), urgency-colored, insistent (haptic pulse + a
/// pulsing ring) until acted on: Acknowledge, snooze presets, or open/complete
/// the task. `PopScope` blocks a silent back-out — the alarm must be answered.
class AlarmRingScreen extends ConsumerStatefulWidget {
  const AlarmRingScreen({
    super.key,
    required this.alarm,
    required this.onHandled,
    this.missed = false,
    this.failed = false,
    this.alarms = const [],
  });

  final AlarmInput alarm;

  /// Called after any action so the host dismisses the overlay at once.
  final void Function(String reminderId) onHandled;

  /// Opened from Home's missed-alarm card rather than by the alarm coming due
  /// (round 19 #2).
  ///
  /// Same screen, same buttons — an alarm from Tuesday still has to be
  /// acknowledged, snoozed or completed. What changes is that it does not make
  /// a sound, does not buzz, and says how long ago it was instead of
  /// announcing itself as happening now. Ringing an alarm whose moment passed
  /// three days ago is the bug; hiding it would be a different one.
  final bool missed;

  /// Shown again because the write behind the last action failed (#46): the
  /// sound stays off, the screen says so and offers the same action again.
  final bool failed;

  /// The active alarms the planner sees (the shell's [alarmFeedProvider]):
  /// a snooze tile whose target minute already holds another task's urgent
  /// alarm says it rings together with it (#47, owner answer 3). Empty: no
  /// tile claims company.
  final List<AlarmInput> alarms;

  @override
  ConsumerState<AlarmRingScreen> createState() => _AlarmRingScreenState();
}

class _AlarmRingScreenState extends ConsumerState<AlarmRingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  /// A second tap while the first action is on its way is ignored. Never
  /// painted: a disabled button on an alarm reads as "this alarm is stuck".
  bool _busy = false;

  /// The tile the running action came from, and the one showing a spinner
  /// because that action has run for more than 300 ms (#46: only there).
  String? _pressedTile;
  String? _spinning;
  Timer? _spinTimer;

  AlarmOverlayController get _controller =>
      ref.read(alarmOverlayControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    if (!widget.missed) _pulse.repeat();
    // The sound is not this screen's: AlarmOverlayController starts and stops
    // it (#46). A missed alarm is reviewed, not answered under pressure, and
    // never makes a sound.
    // The one alarm surface we can prove rang (OPH-176): this screen.
    ref
        .read(alarmLogProvider)
        .record(
          event: AlarmLogEvent.ringShown,
          lane: AlarmLogLane.inapp,
          kind: widget.alarm.kind,
          urgent: widget.alarm.urgent,
          fireAt: alarmFireAt(widget.alarm),
          taskId: widget.alarm.taskId,
          reminderId: widget.alarm.reminderId,
        );
    // A screen reader hears what rings the moment it opens (DESIGN §11 A2).
    WidgetsBinding.instance.addPostFrameCallback((_) => _announce());
  }

  void _announce() {
    if (!mounted) return;
    final fireAt = alarmFireAt(widget.alarm).toLocal();
    final message = 'alarm.ringing.announce'.tr(
      args: {
        'label': widget.missed
            ? 'alarm.missed.label'.tr()
            : 'alarm.ringing.label'.tr(),
        'title': widget.alarm.taskTitle,
        'time': MaterialLocalizations.of(
          context,
        ).formatTimeOfDay(TimeOfDay.fromDateTime(fireAt)),
      },
    );
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        message,
        Directionality.of(context),
      ).catchError((Object _) {}),
    );
  }

  @override
  void didUpdateWidget(AlarmRingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (alarmOccurrenceKey(oldWidget.alarm) !=
        alarmOccurrenceKey(widget.alarm)) {
      _busy = false;
      _stopSpinner();
    }
  }

  @override
  void dispose() {
    _spinTimer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  /// The action contract (#46): silence synchronously, dismiss at once, then
  /// await the write. Nothing here awaits before the screen is gone; a failed
  /// write brings the alarm back through the controller, with the error.
  void _run(Future<void> Function() write, {void Function()? onSaved}) =>
      _runAction(AlarmPendingAction(write, onSaved: onSaved));

  void _runAction(AlarmPendingAction action) {
    final tile = _pressedTile;
    _pressedTile = null;
    if (_busy) return;
    _busy = true;
    final controller = _controller;
    final alarm = widget.alarm;
    if (tile != null) {
      _spinTimer?.cancel();
      _spinTimer = Timer(const Duration(milliseconds: 300), () {
        if (mounted && _busy) setState(() => _spinning = tile);
      });
    }
    controller.silence();
    // iOS 26+: the AlarmKit alert of this occurrence goes quiet too (#46).
    controller.stopAlarmKit(alarm);
    widget.onHandled(alarm.reminderId);
    unawaited(
      controller.commit(alarm, action).then((saved) {
        // The failed occurrence can come back before a frame ever removed
        // this screen (same key, same State): it is no longer busy then.
        if (!saved && mounted) _busy = false;
        _stopSpinner();
      }),
    );
  }

  void _stopSpinner() {
    _spinTimer?.cancel();
    _spinTimer = null;
    if (_spinning != null && mounted) setState(() => _spinning = null);
  }

  void _retry() {
    final action = _controller.failedAction(widget.alarm);
    if (action != null) _runAction(action);
  }

  /// Shows [message] on the messenger captured now, once the write landed —
  /// the screen is gone by then.
  void Function() _sayLater(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    return () => messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  void _acknowledge() {
    final store = ref.read(reminderStoreProvider);
    final reminderId = widget.alarm.reminderId;
    _run(() => store.acknowledge(reminderId));
  }

  void _snooze(String preset) {
    // Say what will happen, in the moment it happens (OPH-177, round 9 #6.5:
    // "5 dk sonra ne olacak?" should not be a question the user has to ask).
    final until = TaskStore.snoozeUntilFor(
      preset,
      now: ref.read(nowProvider)(),
    );
    final store = ref.read(taskStoreProvider);
    final taskId = widget.alarm.taskId;
    _run(() => store.snooze(taskId, preset: preset), onSaved: _confirm(until));
  }

  /// Round 9's "Özel ertele" (BLUEPRINT §8.2, unimplemented until now): pick the
  /// exact minute instead of picking from four presets.
  Future<void> _snoozeCustom() async {
    if (_busy) return;
    // The person is dealing with it: quiet now, before the pickers open. If
    // they back out, the alarm is still unanswered and its sound comes back.
    final controller = _controller;
    // An occurrence the AlarmKit alert rings counts as sounding: that alert
    // stops now, so backing out has to ring it here instead (#46).
    final wasSounding =
        controller.sounding || controller.ringsOnLockScreen(widget.alarm);
    controller.silence();
    controller.stopAlarmKit(widget.alarm);
    void backOut() {
      // No snooze ran: a later key press must not spin this tile.
      _pressedTile = null;
      if (wasSounding) controller.startSound();
    }

    final now = DateTime.now();
    // Both pickers are anchored on the SAME instant — "half an hour from now" —
    // because that instant is TOMORROW whenever the alarm rings after 23:30.
    // Anchoring the date on `now` while suggesting a time taken from
    // `now + 30m` composed today-at-00:10: roughly a day in the past, which the
    // guard below then threw away without a word. An alarm ringing at 23:40 is
    // exactly when somebody reaches for snooze, and it did nothing.
    final suggested = now.add(const Duration(minutes: 30));
    final format = ref.read(dateFormatProvider);
    final date = await showDatePicker(
      context: context,
      initialDate: awInitialPickerDate(anchor: suggested, now: now),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (!mounted) return;
    if (date == null) return backOut();
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(suggested),
    );
    if (!mounted) return;
    final until = DateTime(
      date.year,
      date.month,
      date.day,
      time?.hour ?? suggested.hour,
      time?.minute ?? suggested.minute,
    );
    // A past snooze is not a snooze — but saying nothing is worse than
    // refusing (OPH-177: a snooze must always state what will happen).
    if (!until.isAfter(DateTime.now())) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text('alarm.snoozePast'.tr())));
      return backOut();
    }
    final store = ref.read(taskStoreProvider);
    final taskId = widget.alarm.taskId;
    _run(
      () => store.snooze(taskId, until: until),
      onSaved: _confirm(until, format: format),
    );
  }

  /// "Rings again at 09:05" — said after the screen closed and the snooze
  /// landed (OPH-177, #46): before the write it could be a promise broken.
  void Function() _confirm(DateTime until, {String? format}) => _sayLater(
    'alarm.snoozeConfirmed'.tr(
      args: {
        // Turkish takes the suffix of the spoken time (#46):
        // "09:05’te", "09:30’da"; the catalogue no longer hard-codes it.
        'time': awAt(
          awFormatTime(until, format: format ?? ref.read(dateFormatProvider)),
          languageCode: AwI18n.instance.locale.languageCode,
        ),
      },
    ),
  );

  void _complete() {
    final store = ref.read(taskStoreProvider);
    final taskId = widget.alarm.taskId;
    _run(() => store.complete(taskId));
  }

  /// Silence this task's alarms for good (OPH-178). The task stays OPEN, and the
  /// snackbar says what just happened — a silent silence would be the worst of
  /// both worlds.
  void _silence() {
    final store = ref.read(taskStoreProvider);
    final taskId = widget.alarm.taskId;
    _run(
      () => store.muteAlarms(taskId),
      onSaved: _sayLater('task.alarmsMuted'.tr()),
    );
  }

  /// "Aç" silences and dismisses but does not acknowledge (fix-spec §2.2):
  /// the person went to look, the answer comes from the task.
  void _open() {
    if (_busy) return;
    _busy = true;
    final router = GoRouter.of(context);
    final taskId = widget.alarm.taskId;
    _controller.silence();
    _controller.stopAlarmKit(widget.alarm);
    widget.onHandled(widget.alarm.reminderId);
    router.push('/tasks/$taskId');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.awTokens;
    final text = Theme.of(context).textTheme;
    final dateFormat = ref.watch(dateFormatProvider);
    // OPH-316: the person asked this browser to be quiet, so the alarm opens
    // and says nothing out loud — declared, with the sound one press away.
    // OPH-393: "you set this" only when the person did (E-20).
    final silent =
        !widget.missed &&
        ref.watch(alarmOverlayControllerProvider.select((s) => s.silentHere));
    // #46, iOS 26+: the system alert is the sound. Said in one line, with no
    // "start the sound" that would ring it twice.
    final onLockScreen =
        silent &&
        ref.watch(
          alarmOverlayControllerProvider.select((s) => s.ringsOnLockScreen),
        );
    final silenceChosen = silent && ref.watch(alarmSilenceChosenProvider);
    final fireAt = alarmFireAt(widget.alarm).toLocal();
    final time = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(fireAt));

    // Direction A (#46, DESIGN §11): the screen's three layout switches.
    final screen = MediaQuery.sizeOf(context);
    // A6/A7: under 700 pt the 96 badge and the section label do not fit.
    final short = screen.height < kAlarmShortScreenHeight;
    // Past 1.3 two tiles no longer fit a row: one column, the screen scrolls.
    final oneColumn =
        MediaQuery.textScalerOf(context).scale(14) / 14 >
        kAlarmOneColumnTextScale;
    // Desktop and web have no thumb zone: content and actions centre together.
    final wide = screen.width >= kAwWideBreakpoint;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    // Solid, opaque takeover with a faint urgency wash (DESIGN G1: no glass
    // under text). High-contrast ink stays on the near-surface background.
    final background = Color.alphaBlend(
      tokens.prioUrgent.withValues(alpha: 0.10),
      scheme.surface,
    );

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _badge(
          size: short ? 64 : 96,
          color: tokens.prioUrgent,
          pulse: !widget.missed && !reduceMotion,
        ),
        SizedBox(height: short ? AwSpace.x3 : AwSpace.x5),
        // Text on the wash takes errorOnPage: prioUrgent is a 3:1 flag colour
        // and measured 3.94 / 4.36 here (contrast.py, DESIGN §11 A9).
        Text(
          alarmUpper(
            widget.missed
                ? 'alarm.missed.label'.tr()
                : 'alarm.ringing.label'.tr(),
          ),
          key: const Key('alarm-ringing-label'),
          textAlign: TextAlign.center,
          style: text.labelLarge?.copyWith(
            color: tokens.errorOnPage,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: AwSpace.x1),
        // A missed alarm says how long ago, in the same line as its time.
        Text(
          widget.missed
              ? 'alarm.missed.ago'.tr(
                  args: {
                    'time': time,
                    'ago': awRelativePast(
                      alarmFireAt(widget.alarm),
                      ref.read(alarmClockProvider)(),
                    ),
                  },
                )
              : time,
          key: const Key('alarm-time'),
          textAlign: TextAlign.center,
          style: awTabular(
            (widget.missed ? text.titleLarge! : text.displaySmall!).copyWith(
              color: scheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: AwSpace.x2),
        Tooltip(
          message: widget.alarm.taskTitle,
          excludeFromSemantics: true,
          child: AwWordSafeText(
            widget.alarm.taskTitle,
            textAlign: TextAlign.center,
            maxLines: short ? 2 : 3,
            overflow: TextOverflow.ellipsis,
            style: text.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
        ),
        // OPH-316: a silence the settings asked for, declared. Without this
        // line the screen is indistinguishable from an alarm that failed to
        // ring — which is the one outcome NOTIFICATIONS §3 forbids. OPH-393:
        // "you set this" only when the person did; a fresh browser is silent
        // by default and says that instead (E-20).
        if (onLockScreen)
          Padding(
            padding: const EdgeInsets.only(top: AwSpace.x4),
            child: Text(
              'alarm.ringingOnLockScreen'.tr(),
              key: const Key('alarm-rings-on-lock-screen'),
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          )
        else if (silent)
          Padding(
            padding: const EdgeInsets.only(top: AwSpace.x4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  silenceChosen
                      ? 'alarm.silentByChoice'.tr()
                      : 'alarm.silentByDefault'.tr(),
                  key: silenceChosen
                      ? const Key('alarm-silent-declared')
                      : const Key('alarm-silent-default'),
                  textAlign: TextAlign.center,
                  style: text.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AwSpace.x2),
                _startSoundTile(oneColumn),
              ],
            ),
          )
        else if (!widget.missed)
          // OPH-180: when the platform refused to make noise (a browser's
          // autoplay policy, no audio device), say so and offer to start it —
          // never pretend the room is loud.
          ValueListenableBuilder<bool>(
            valueListenable: _controller.soundBlocked,
            builder: (context, blocked, _) => blocked
                ? Padding(
                    padding: const EdgeInsets.only(top: AwSpace.x4),
                    child: SizedBox(
                      width: double.infinity,
                      child: _startSoundTile(oneColumn),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
      ],
    );

    final now = ref.watch(nowProvider)();
    // Who else rings in a snooze's target minute (#47): the tile says the
    // snooze joins that alarm instead of pretending it rings alone.
    final feed = widget.alarms;
    final presets = ref.watch(snoozePresetOrderProvider);
    final tiles = <Widget>[
      // The user's own order (OPH-179 N4); keys 1–4 follow it.
      for (final preset in presets)
        _tile(
          'alarm-snooze-$preset',
          label: kSnoozePresetLabels[preset]!.tr(),
          // The offset AND the instant it lands on: "5 dk" alone made the
          // user ask what happens next (OPH-177).
          subline: _subline(
            TaskStore.snoozeUntilFor(preset, now: now),
            feed,
            dateFormat,
          ),
          wrap: oneColumn,
          onPressed: () => _snooze(preset),
        ),
      _tile(
        'alarm-snooze-custom',
        label: 'alarm.snoozeCustom'.tr(),
        icon: Icons.schedule,
        wrap: oneColumn,
        onPressed: _snoozeCustom,
      ),
      // OPH-178: the way out that does NOT require lying about the task
      // being done.
      _tile(
        'alarm-silence',
        label: 'alarm.silence'.tr(),
        subline: 'alarm.silenceHint'.tr(),
        icon: Icons.notifications_off,
        wrap: oneColumn,
        onPressed: _silence,
      ),
    ];

    final actions = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // #46: the write behind the last action failed. The sound stays off;
        // the screen says so above the actions and offers the same action
        // again — no snackbar behind the overlay.
        if (widget.failed) ...[
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
            onPressed: _retry,
          ),
          const SizedBox(height: AwSpace.x4),
        ],
        if (!short) ...[
          Text(
            'alarm.ringing.snooze'.tr(),
            key: const Key('alarm-snooze-label'),
            style: text.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AwSpace.x2),
        ],
        _grid(tiles, oneColumn: oneColumn),
        const SizedBox(height: AwSpace.x4),
        FilledButton.icon(
          key: const Key('alarm-acknowledge'),
          // Keyboard: the first focus is the primary answer (Enter, too).
          autofocus: true,
          onPressed: _acknowledge,
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
            minimumSize: const Size.fromHeight(kAwAlarmTileHeight),
            textStyle: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          icon: const Icon(Icons.check),
          label: Text('notif.action.acknowledge'.tr()),
        ),
        const SizedBox(height: AwSpace.x2),
        Row(
          children: [
            Expanded(
              child: _textAction(
                'alarm-complete',
                icon: Icons.check_circle_outline,
                label: 'notif.action.complete'.tr(),
                onPressed: _complete,
              ),
            ),
            const SizedBox(width: AwSpace.x2),
            Expanded(
              child: _textAction(
                'alarm-open',
                icon: Icons.open_in_new,
                label: 'notif.action.open'.tr(),
                onPressed: _open,
              ),
            ),
          ],
        ),
      ],
    );

    return PopScope(
      // The alarm must be answered with a button; back does not dismiss it.
      // A MISSED one may be backed out of — it is history being reviewed, and
      // trapping someone in a screen about Tuesday would be its own bug.
      canPop: widget.missed,
      // OPH-393 (E-20): the shell layers this screen OVER Home in a Stack
      // (`home_shell.dart`), and Home's controls stayed in the semantics tree
      // underneath — a screen reader could land behind a ringing alarm. This
      // drops everything painted before it, as a route's barrier does.
      child: BlockSemantics(
        child: Material(
          key: const Key('alarm-ring'),
          color: background,
          child: CallbackShortcuts(
            bindings: _shortcuts(presets),
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const padding = EdgeInsets.fromLTRB(
                    AwSpace.x6,
                    AwSpace.x6,
                    AwSpace.x6,
                    AwSpace.x4,
                  );
                  // The column fills the screen so the actions pin to its
                  // bottom; content taller than that scrolls as one page.
                  final minHeight = constraints.maxHeight.isFinite
                      ? (constraints.maxHeight - padding.vertical)
                            .clamp(0, double.infinity)
                            .toDouble()
                      : 0.0;
                  return SingleChildScrollView(
                    padding: padding,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: kAlarmRingMaxWidth,
                          minHeight: minHeight,
                        ),
                        child: Column(
                          mainAxisAlignment: wide
                              ? MainAxisAlignment.center
                              : MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            content,
                            SizedBox(height: wide ? AwSpace.x8 : AwSpace.x6),
                            actions,
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Enter = Onayla, 1–4 = the first four snooze tiles in the user's order,
  /// Esc = nothing (DESIGN §11 A2: the alarm is answered, not dismissed).
  Map<ShortcutActivator, VoidCallback> _shortcuts(List<String> presets) {
    const digits = [
      [LogicalKeyboardKey.digit1, LogicalKeyboardKey.numpad1],
      [LogicalKeyboardKey.digit2, LogicalKeyboardKey.numpad2],
      [LogicalKeyboardKey.digit3, LogicalKeyboardKey.numpad3],
      [LogicalKeyboardKey.digit4, LogicalKeyboardKey.numpad4],
    ];
    return {
      const SingleActivator(LogicalKeyboardKey.enter): _acknowledge,
      const SingleActivator(LogicalKeyboardKey.numpadEnter): _acknowledge,
      const SingleActivator(LogicalKeyboardKey.escape): () {},
      for (var i = 0; i < digits.length && i < presets.length; i++)
        for (final key in digits[i])
          SingleActivator(key): () => _snooze(presets[i]),
    };
  }

  /// "rings at 09:05", or "… · with another alarm" when the target minute
  /// already holds another task's urgent alarm (OPH-442, owner answer 3).
  String _subline(DateTime until, List<AlarmInput> feed, String format) {
    final others = urgentAlarmsInMinute(
      feed,
      until,
      exceptTaskIds: {widget.alarm.taskId},
    );
    return snoozeTileSubline(until, joinsGroup: others > 0, format: format);
  }

  Widget _tile(
    String key, {
    required String label,
    required VoidCallback onPressed,
    String? subline,
    IconData? icon,
    bool wrap = false,
  }) => AwAlarmActionTile(
    key: Key(key),
    label: label,
    subline: subline,
    icon: icon,
    wrap: wrap,
    busy: _spinning == key,
    onPressed: () {
      _pressedTile = key;
      onPressed();
    },
  );

  Widget _startSoundTile(bool wrap) => AwAlarmActionTile(
    key: const Key('alarm-start-sound'),
    label: 'alarm.startSound'.tr(),
    icon: Icons.volume_up,
    wrap: wrap,
    minHeight: 48,
    onPressed: () => _controller.startSound(),
  );

  /// ONE grid (#46): two equal columns with an [AwSpace.x2] gap, or one
  /// column past 1.3 text scale. Every cell is the same width.
  Widget _grid(List<Widget> tiles, {required bool oneColumn}) {
    if (oneColumn) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const SizedBox(height: AwSpace.x2),
            tiles[i],
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < tiles.length; i += 2) ...[
          if (i > 0) const SizedBox(height: AwSpace.x2),
          Row(
            children: [
              Expanded(child: tiles[i]),
              const SizedBox(width: AwSpace.x2),
              // An odd last tile keeps its column's width.
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

  Widget _textAction(
    String key, {
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) => TextButton.icon(
    key: Key(key),
    onPressed: onPressed,
    style: TextButton.styleFrom(
      foregroundColor: context.awTokens.link,
      minimumSize: const Size.fromHeight(48),
    ),
    icon: Icon(icon, size: 18),
    label: Text(label),
  );

  /// The alarm badge (96, 64 on a short screen) with its pulse: a ring
  /// BEHIND it that grows to 4/3 of the badge and fades from 40 % to nothing
  /// every 1200 ms (0.8 Hz, far under WCAG 2.3.1's 3 Hz). The badge and the
  /// text never scale; reduced motion and a missed alarm get no ring.
  Widget _badge({
    required double size,
    required Color color,
    required bool pulse,
  }) {
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
    if (!pulse) return Center(child: badge);
    return Center(
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            // Painted outside the badge's box, so the pulse costs no layout.
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
      ),
    );
  }
}
