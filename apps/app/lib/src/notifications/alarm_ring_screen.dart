import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/date_format.dart';
import '../core/persisted_prefs.dart';
import '../features/tasks/data/task_store.dart';
import '../features/tasks/providers.dart';
import '../i18n/i18n.dart';
import '../theme/tokens.dart';
import 'alarm_log.dart';
import 'reminder_profile.dart';
import 'alarm_overlay.dart';
import 'planner.dart';
import 'providers.dart';

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
  });

  final AlarmInput alarm;

  /// Called after any action so the host dismisses the overlay at once.
  final void Function(String reminderId) onHandled;

  @override
  ConsumerState<AlarmRingScreen> createState() => _AlarmRingScreenState();
}

class _AlarmRingScreenState extends ConsumerState<AlarmRingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);
  // Held in a field so dispose() never touches `ref` (unsafe once unmounting).
  AlarmFeedback? _feedback;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final feedback = ref.read(alarmFeedbackProvider);
    _feedback = feedback;
    feedback.start();
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
  void dispose() {
    _feedback?.stop();
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      widget.onHandled(widget.alarm.reminderId);
    }
  }

  void _acknowledge() => _run(
    () => ref.read(reminderStoreProvider).acknowledge(widget.alarm.reminderId),
  );

  void _snooze(String preset) {
    // Say what will happen, in the moment it happens (OPH-177, round 9 #6.5:
    // "5 dk sonra ne olacak?" should not be a question the user has to ask).
    final until = TaskStore.snoozeUntilFor(preset);
    _confirm(until);
    _run(
      () => ref
          .read(taskStoreProvider)
          .snooze(widget.alarm.taskId, preset: preset),
    );
  }

  /// Round 9's "Özel ertele" (BLUEPRINT §8.2, unimplemented until now): pick the
  /// exact minute instead of picking from four presets.
  Future<void> _snoozeCustom() async {
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
    if (date == null || !mounted) return;
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
      return;
    }
    _confirm(until, format: format);
    _run(
      () =>
          ref.read(taskStoreProvider).snooze(widget.alarm.taskId, until: until),
    );
  }

  void _confirm(DateTime until, {String? format}) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          'alarm.snoozeConfirmed'.tr(
            args: {
              'time': awFormatTime(
                until,
                format: format ?? ref.read(dateFormatProvider),
              ),
            },
          ),
        ),
      ),
    );
  }

  void _complete() =>
      _run(() => ref.read(taskStoreProvider).complete(widget.alarm.taskId));

  /// Silence this task's alarms for good (OPH-178). The task stays OPEN, and the
  /// snackbar says what just happened — a silent silence would be the worst of
  /// both worlds.
  void _silence() {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text('task.alarmsMuted'.tr())));
    _run(() => ref.read(taskStoreProvider).muteAlarms(widget.alarm.taskId));
  }

  void _open() {
    final router = GoRouter.of(context);
    final taskId = widget.alarm.taskId;
    widget.onHandled(widget.alarm.reminderId);
    router.push('/tasks/$taskId');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.awTokens;
    final text = Theme.of(context).textTheme;
    final dateFormat = ref.watch(dateFormatProvider);
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
      canPop: false,
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
                      'alarm.ringing.label'.tr().toUpperCase(),
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
                          time,
                          style: text.titleMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    // OPH-180: when the platform refused to make noise (a
                    // browser's autoplay policy, no audio device), say so and
                    // offer to start it — never pretend the room is loud.
                    ValueListenableBuilder<bool>(
                      valueListenable: _feedback!.soundBlocked,
                      builder: (context, blocked, _) => blocked
                          ? Padding(
                              padding: const EdgeInsets.only(top: AwSpace.x4),
                              child: OutlinedButton.icon(
                                key: const Key('alarm-start-sound'),
                                onPressed: () => _feedback?.start(),
                                icon: const Icon(Icons.volume_up, size: 18),
                                label: Text('alarm.startSound'.tr()),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    const SizedBox(height: AwSpace.x6),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        key: const Key('alarm-acknowledge'),
                        onPressed: _busy ? null : _acknowledge,
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
                        letterSpacing: 0.4,
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
                            onPressed: _busy ? null : () => _snooze(preset),
                            // The offset AND the instant it lands on: "5 dk"
                            // alone made the user ask what happens next.
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(kSnoozePresetLabels[preset]!.tr()),
                                Text(
                                  'alarm.snoozeRingsAt'.tr(
                                    args: {
                                      'time': awFormatTime(
                                        TaskStore.snoozeUntilFor(preset),
                                        format: dateFormat,
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
                          onPressed: _busy ? null : _snoozeCustom,
                          child: Text('alarm.snoozeCustom'.tr()),
                        ),
                        // OPH-178: the way out that does NOT require lying
                        // about the task being done.
                        OutlinedButton.icon(
                          key: const Key('alarm-silence'),
                          onPressed: _busy ? null : _silence,
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
                          onPressed: _busy ? null : _complete,
                          icon: const Icon(
                            Icons.check_circle_outline,
                            size: 18,
                          ),
                          label: Text('notif.action.complete'.tr()),
                        ),
                        const SizedBox(width: AwSpace.x2),
                        TextButton.icon(
                          key: const Key('alarm-open'),
                          onPressed: _busy ? null : _open,
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
    );
  }
}
