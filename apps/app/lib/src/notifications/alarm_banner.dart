import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/i18n.dart';
import '../theme/tokens.dart';
import 'alarm_fix_sheet.dart';
import 'providers.dart';

/// Honest degradation banner (OPH-143; NOTIFICATIONS.md §1 "never fail
/// silently"): when the OS can't ring urgent alarms reliably, say so at the top
/// of Home and offer the one-tap fix. Renders nothing when delivery is healthy
/// or still being probed — an alarm you *can* hear needs no warning.
class AlarmDegradationBanner extends ConsumerWidget {
  const AlarmDegradationBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final support = ref.watch(alarmSupportProvider).value;
    if (support == null) return const SizedBox.shrink();

    // Worst problem first — and the cascade itself now lives on [AlarmSupport]
    // (OPH-277), so this banner and the Settings row cannot drift apart. Until
    // round 19 they each carried their own copy of a two-branch `if`, and the
    // five conditions this round added would have been five chances to
    // disagree about which problem to name.
    final problem = support.worstProblem;
    if (problem == null) return const SizedBox.shrink();
    final message = 'alarm.problem.${problem.name}'.tr();

    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AwSpace.x4, AwSpace.x2, AwSpace.x4, 0),
      child: Material(
        color: scheme.errorContainer,
        borderRadius: const BorderRadius.all(Radius.circular(AwRadius.m)),
        child: InkWell(
          key: const Key('alarm-banner'),
          borderRadius: const BorderRadius.all(Radius.circular(AwRadius.m)),
          // Round 19: the banner used to re-run `requestPermissions()`, which
          // does NOTHING once the user has already answered — iOS never shows
          // the prompt twice, so the "Fix" button was a button that could not
          // fix anything. It opens the page that CAN, and says which switch to
          // look for on the way.
          onTap: () => showAlarmFixSheet(context, ref, problem),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AwSpace.x3,
              vertical: AwSpace.x3,
            ),
            child: Row(
              children: [
                Icon(Icons.alarm_off, size: 20, color: scheme.onErrorContainer),
                const SizedBox(width: AwSpace.x2),
                Expanded(
                  child: Text(
                    message,
                    style: text.bodyMedium?.copyWith(
                      color: scheme.onErrorContainer,
                    ),
                  ),
                ),
                const SizedBox(width: AwSpace.x2),
                Text(
                  'alarm.banner.fix'.tr(),
                  style: text.labelLarge?.copyWith(
                    color: scheme.onErrorContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
