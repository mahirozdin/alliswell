import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/tasks/providers.dart';
import '../i18n/i18n.dart';
import '../theme/tokens.dart';
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

  void _snooze(String preset) => _run(
    () =>
        ref.read(taskStoreProvider).snooze(widget.alarm.taskId, preset: preset),
  );

  void _complete() =>
      _run(() => ref.read(taskStoreProvider).complete(widget.alarm.taskId));

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
                        for (final (preset, labelKey) in const [
                          ('5_min', 'notif.action.snooze5m'),
                          ('30_min', 'notif.action.snooze30m'),
                          ('1_hour', 'notif.action.snooze1h'),
                        ])
                          OutlinedButton(
                            key: Key('alarm-snooze-$preset'),
                            onPressed: _busy ? null : () => _snooze(preset),
                            child: Text(labelKey.tr()),
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
