import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/date_format.dart';
import '../../../core/persisted_prefs.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../data/external_event.dart';

/// One event from the user's calendar (OPH-083).
///
/// Visually a different species from [TaskTile] on purpose: no checkbox, no tap
/// target that implies editing, a leading time rail instead of a status icon.
/// You cannot complete a meeting, and the row should not suggest you can.
class ExternalEventTile extends ConsumerWidget {
  const ExternalEventTile({required this.event, super.key});

  final ExternalEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The time rail follows the user's chosen clock (OPH-174 — a 12h format
    // must not leave meetings reading 23:00).
    final dateFormat = ref.watch(dateFormatProvider);
    String hhmm(DateTime at) => awFormatTime(at, format: dateFormat);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    // "Not busy" (Google's `transparent`) is background noise — birthdays,
    // holidays — so it recedes instead of competing with the day's real work.
    final accent = event.isBusy ? scheme.primary : scheme.onSurfaceVariant;

    // Round 13 #4: the SAME outer rhythm as a task row (task_tile.dart's
    // `vertical: 3`). This card used to carry `margin: only(bottom: 8)`, which
    // meant a calendar card following a task got 3 px of air above it and 11 px
    // below — so one gap read as "stuck together" and the next as a break.
    // Every gap in the list is now the same 6 px, whatever the two rows are.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AwSpace.x3,
            vertical: AwSpace.x3,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // A time rail, not a checkbox: this is when something happens TO
              // you, not something you tick off.
              SizedBox(
                width: 44,
                child: event.isAllDay
                    ? Icon(Icons.today_outlined, size: 18, color: accent)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            hhmm(event.startsAt),
                            style: text.labelLarge?.copyWith(
                              color: accent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            hhmm(event.endsAt),
                            style: text.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
              ),
              Container(
                width: 3,
                height: 32,
                margin: const EdgeInsets.only(right: AwSpace.x3),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(AwRadius.s),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      event.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (event.location != null && event.location!.isNotEmpty)
                      Text(
                        event.location!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              // Says "this came from your calendar, and it lives there" — the
              // read-only affordance, without a disabled-looking control.
              Tooltip(
                message: 'calendar.fromYourCalendar'.tr(),
                child: Icon(
                  Icons.event_outlined,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
