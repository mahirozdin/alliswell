import 'package:flutter/material.dart';

import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../data/external_event.dart';

/// One event from the user's calendar (OPH-083).
///
/// Visually a different species from [TaskTile] on purpose: no checkbox, no tap
/// target that implies editing, a leading time rail instead of a status icon.
/// You cannot complete a meeting, and the row should not suggest you can.
class ExternalEventTile extends StatelessWidget {
  const ExternalEventTile({required this.event, super.key});

  final ExternalEvent event;

  static String _hhmm(DateTime at) {
    final local = at.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    // "Not busy" (Google's `transparent`) is background noise — birthdays,
    // holidays — so it recedes instead of competing with the day's real work.
    final accent = event.isBusy ? scheme.primary : scheme.onSurfaceVariant;

    return Card(
      margin: const EdgeInsets.only(bottom: AwSpace.x2),
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
                          _hhmm(event.startsAt),
                          style: text.labelLarge?.copyWith(
                            color: accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          _hhmm(event.endsAt),
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
    );
  }
}
