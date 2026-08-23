/// The alarm that went off while nobody was looking (round 19 #2).
///
/// The report: *"when I open the app a long-gone alarm suddenly goes off in
/// red — but its time is long past."* `ringingAlarm` had no lower bound, so an
/// urgent alarm from three days ago still counted as ringing, seized the
/// screen and sounded the bed. Worse than merely wrong: it made a device whose
/// alarms had stopped working look like they finally had.
///
/// Bounding the ring window fixes the wrong half. This card is the other half —
/// the user still needs to know Tuesday's alarm was never answered, and they
/// still need somewhere to acknowledge, snooze or complete it. They just should
/// not be woken by it on Friday.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/date_format.dart';
import '../i18n/i18n.dart';
import '../theme/tokens.dart';
import 'alarm_overlay.dart';
import 'alarm_ring_screen.dart';

class MissedAlarmCard extends ConsumerWidget {
  const MissedAlarmCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final missed = ref.watch(missedAlarmsProvider);
    if (missed.isEmpty) return const SizedBox.shrink();

    final first = missed.first;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final tokens = context.awTokens;
    final fireAt = alarmFireAt(first).toLocal();
    final time = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(fireAt));

    return Padding(
      padding: const EdgeInsets.fromLTRB(AwSpace.x4, AwSpace.x2, AwSpace.x4, 0),
      child: Material(
        // The urgency wash, not `errorContainer`: the degradation banner owns
        // the error colour, and a missed alarm is not a broken app — it is a
        // task still waiting. Two red cards stacked would say the same thing
        // twice with different meanings.
        color: Color.alphaBlend(
          tokens.prioUrgent.withValues(alpha: 0.12),
          scheme.surfaceContainerHigh,
        ),
        borderRadius: const BorderRadius.all(Radius.circular(AwRadius.m)),
        child: InkWell(
          key: const Key('missed-alarm-card'),
          borderRadius: const BorderRadius.all(Radius.circular(AwRadius.m)),
          onTap: () => Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute<void>(
              fullscreenDialog: true,
              builder: (_) => AlarmRingScreen(
                alarm: first,
                missed: true,
                onHandled: (_) {
                  ref
                      .read(alarmOverlayControllerProvider.notifier)
                      .handled(first.reminderId);
                  Navigator.of(context, rootNavigator: true).maybePop();
                },
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AwSpace.x3,
              vertical: AwSpace.x3,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.notifications_paused_outlined,
                  size: 20,
                  color: tokens.prioUrgent,
                ),
                const SizedBox(width: AwSpace.x2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'alarm.missed.cardTitle'.tr(),
                        style: text.labelMedium?.copyWith(
                          color: tokens.prioUrgent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        first.taskTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodyMedium?.copyWith(
                          color: scheme.onSurface,
                        ),
                      ),
                      Text(
                        'alarm.missed.ago'.tr(
                          args: {
                            'time': time,
                            'ago': awRelativePast(
                              alarmFireAt(first),
                              ref.read(alarmClockProvider)(),
                            ),
                          },
                        ),
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (missed.length > 1) ...[
                  const SizedBox(width: AwSpace.x2),
                  Text(
                    'alarm.missed.cardMore'.tr(
                      args: {'n': '${missed.length - 1}'},
                    ),
                    style: text.labelLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
