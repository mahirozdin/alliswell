import 'dart:async';

import 'package:flutter/material.dart';
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
import 'alarm_log.dart';
import 'reminder_profile.dart';
import 'alarm_overlay.dart';
import 'planner.dart';
import 'providers.dart';
import '../theme/typography.dart';
import '../widgets/status_views.dart';

/// The shell's alarm layer: the first ringing occurrence, keyed by
/// [alarmOccurrenceKey] (#46). Unkeyed, the next alarm inherited the previous
/// screen's State — its pulse, its log entry and a "busy" flag that left every
/// button dead.
class AlarmOverlayLayer extends ConsumerWidget {
  const AlarmOverlayLayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overlay = ref.watch(alarmOverlayControllerProvider);
    if (overlay.ringing.isEmpty) return const SizedBox.shrink();
    final alarm = overlay.ringing.first;
    return AlarmRingScreen(
      key: ValueKey<String>(alarmOccurrenceKey(alarm)),
      alarm: alarm,
      failed: overlay.isFailed(alarm),
      onHandled: (_) =>
          ref.read(alarmOverlayControllerProvider.notifier).handled(alarm),
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

  @override
  ConsumerState<AlarmRingScreen> createState() => _AlarmRingScreenState();
}

class _AlarmRingScreenState extends ConsumerState<AlarmRingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  /// A second tap while the first action is on its way is ignored. Never
  /// painted: a disabled button on an alarm reads as "this alarm is stuck".
  bool _busy = false;

  AlarmOverlayController get _controller =>
      ref.read(alarmOverlayControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    if (!widget.missed) _pulse.repeat(reverse: true);
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
  }

  @override
  void didUpdateWidget(AlarmRingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (alarmOccurrenceKey(oldWidget.alarm) !=
        alarmOccurrenceKey(widget.alarm)) {
      _busy = false;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  /// The action contract (#46): silence synchronously, dismiss at once, then
  /// await the write. Nothing here awaits before the screen is gone; a failed
  /// write brings the alarm back through the controller, with the error.
  void _run(Future<void> Function() write, {void Function()? onSaved}) =>
      _runAction(AlarmPendingAction(write, onSaved: onSaved));

  void _runAction(AlarmPendingAction action) {
    if (_busy) return;
    _busy = true;
    final controller = _controller;
    final alarm = widget.alarm;
    controller.silence();
    widget.onHandled(alarm.reminderId);
    unawaited(
      controller.commit(alarm, action).then((saved) {
        // The failed occurrence can come back before a frame ever removed
        // this screen (same key, same State): it is no longer busy then.
        if (!saved && mounted) _busy = false;
      }),
    );
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
    final wasSounding = controller.sounding;
    controller.silence();
    void backOut() {
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
    final silenceChosen = silent && ref.watch(alarmSilenceChosenProvider);
    final fireAt = alarmFireAt(widget.alarm).toLocal();
    final time = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(fireAt));

    // Solid, opaque takeover with a faint urgency wash (DESIGN G1: no glass
    // under text). High-contrast ink stays on the near-surface background.
    final background = Color.alphaBlend(
      tokens.prioUrgent.withValues(alpha: 0.10),
      scheme.surface,
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
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AwSpace.x6),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ScaleTransition(
                        scale: Tween<double>(begin: 0.92, end: 1.08).animate(
                          CurvedAnimation(
                            parent: _pulse,
                            curve: Curves.easeInOut,
                          ),
                        ),
                        child: Container(
                          width: 108,
                          height: 108,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: tokens.prioUrgent.withValues(alpha: 0.14),
                            border: Border.all(
                              color: tokens.prioUrgent,
                              width: 2,
                            ),
                          ),
                          child: Icon(
                            Icons.alarm,
                            size: 52,
                            color: tokens.prioUrgent,
                          ),
                        ),
                      ),
                      const SizedBox(height: AwSpace.x5),
                      Text(
                        (widget.missed
                                ? 'alarm.missed.label'.tr()
                                : 'alarm.ringing.label'.tr())
                            .toUpperCase(),
                        style: text.labelLarge?.copyWith(
                          color: tokens.prioUrgent,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: AwSpace.x2),
                      Text(
                        widget.alarm.taskTitle,
                        textAlign: TextAlign.center,
                        style: text.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: AwSpace.x2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.schedule,
                            size: 18,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: AwSpace.x1),
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
                            style: awTabular(
                              text.titleMedium!.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                      // OPH-316: a silence the settings asked for, declared.
                      // Without this line the screen is indistinguishable from
                      // an alarm that failed to ring — which is the one outcome
                      // NOTIFICATIONS §3 forbids. OPH-393: "you set this" only
                      // when the person did; a fresh browser is silent by
                      // default and says that instead (E-20).
                      if (silent)
                        Padding(
                          padding: const EdgeInsets.only(top: AwSpace.x4),
                          child: Column(
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
                              OutlinedButton.icon(
                                key: const Key('alarm-start-sound'),
                                onPressed: () => _controller.startSound(),
                                icon: const Icon(Icons.volume_up, size: 18),
                                label: Text('alarm.startSound'.tr()),
                              ),
                            ],
                          ),
                        )
                      else if (!widget.missed)
                        // OPH-180: when the platform refused to make noise (a
                        // browser's autoplay policy, no audio device), say so and
                        // offer to start it — never pretend the room is loud.
                        ValueListenableBuilder<bool>(
                          valueListenable: _controller.soundBlocked,
                          builder: (context, blocked, _) => blocked
                              ? Padding(
                                  padding: const EdgeInsets.only(
                                    top: AwSpace.x4,
                                  ),
                                  child: OutlinedButton.icon(
                                    key: const Key('alarm-start-sound'),
                                    onPressed: () => _controller.startSound(),
                                    icon: const Icon(Icons.volume_up, size: 18),
                                    label: Text('alarm.startSound'.tr()),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      // #46: the write behind the last action failed. The
                      // sound stays off; the screen says so and offers the
                      // same action again — no snackbar behind the overlay.
                      if (widget.failed) ...[
                        const SizedBox(height: AwSpace.x5),
                        AwInlineError(
                          message: 'alarm.actionFailed'.tr(),
                          textKey: const Key('alarm-action-failed'),
                        ),
                        const SizedBox(height: AwSpace.x2),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            key: const Key('alarm-retry'),
                            onPressed: _retry,
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                            ),
                            icon: const Icon(Icons.refresh, size: 18),
                            label: Text('alarm.retry'.tr()),
                          ),
                        ),
                      ],
                      const SizedBox(height: AwSpace.x6),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          key: const Key('alarm-acknowledge'),
                          onPressed: _acknowledge,
                          style: FilledButton.styleFrom(
                            backgroundColor: scheme.error,
                            foregroundColor: scheme.onError,
                            padding: const EdgeInsets.symmetric(
                              vertical: AwSpace.x4,
                            ),
                            textStyle: text.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          icon: const Icon(Icons.notifications_active),
                          label: Text('notif.action.acknowledge'.tr()),
                        ),
                      ),
                      const SizedBox(height: AwSpace.x5),
                      Text(
                        'alarm.ringing.snooze'.tr(),
                        style: text.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AwSpace.x2),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: AwSpace.x2,
                        runSpacing: AwSpace.x2,
                        children: [
                          // The user's own order (OPH-179 N4).
                          for (final preset in ref.watch(
                            snoozePresetOrderProvider,
                          ))
                            OutlinedButton(
                              key: Key('alarm-snooze-$preset'),
                              onPressed: () => _snooze(preset),
                              // The offset AND the instant it lands on: "5 dk"
                              // alone made the user ask what happens next.
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(kSnoozePresetLabels[preset]!.tr()),
                                  Text(
                                    'alarm.snoozeRingsAt'.tr(
                                      args: {
                                        'time': awAt(
                                          awFormatTime(
                                            TaskStore.snoozeUntilFor(
                                              preset,
                                              now: ref.watch(nowProvider)(),
                                            ),
                                            format: dateFormat,
                                          ),
                                          languageCode: AwI18n
                                              .instance
                                              .locale
                                              .languageCode,
                                        ),
                                      },
                                    ),
                                    style: text.labelSmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          OutlinedButton(
                            key: const Key('alarm-snooze-custom'),
                            onPressed: _snoozeCustom,
                            child: Text('alarm.snoozeCustom'.tr()),
                          ),
                          // OPH-178: the way out that does NOT require lying
                          // about the task being done.
                          OutlinedButton.icon(
                            key: const Key('alarm-silence'),
                            onPressed: _silence,
                            icon: const Icon(Icons.notifications_off, size: 18),
                            label: Text('alarm.silence'.tr()),
                          ),
                        ],
                      ),
                      const SizedBox(height: AwSpace.x4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TextButton.icon(
                            key: const Key('alarm-complete'),
                            onPressed: _complete,
                            icon: const Icon(
                              Icons.check_circle_outline,
                              size: 18,
                            ),
                            label: Text('notif.action.complete'.tr()),
                          ),
                          const SizedBox(width: AwSpace.x2),
                          TextButton.icon(
                            key: const Key('alarm-open'),
                            onPressed: _open,
                            icon: const Icon(Icons.open_in_new, size: 18),
                            label: Text('notif.action.open'.tr()),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
