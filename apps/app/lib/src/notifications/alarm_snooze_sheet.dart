import 'package:flutter/material.dart';

import '../core/date_format.dart';
import '../features/tasks/data/task_store.dart';
import '../i18n/i18n.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'planner.dart';
import 'reminder_profile.dart';

/// What the person picked in a row's snooze sheet (#47, OPH-443).
sealed class AlarmSheetChoice {
  const AlarmSheetChoice();
}

/// A preset: snooze the row to [until].
final class AlarmSheetSnooze extends AlarmSheetChoice {
  const AlarmSheetSnooze(this.until);
  final DateTime until;
}

/// "Saat seç…": the date and time pickers follow.
final class AlarmSheetCustom extends AlarmSheetChoice {
  const AlarmSheetCustom();
}

/// "Süresiz ertele": the task stays open, its alarms stay quiet.
final class AlarmSheetMute extends AlarmSheetChoice {
  const AlarmSheetMute();
}

final class AlarmSheetComplete extends AlarmSheetChoice {
  const AlarmSheetComplete();
}

/// "Aç": open the task; nothing is acknowledged.
final class AlarmSheetOpen extends AlarmSheetChoice {
  const AlarmSheetOpen();
}

/// The sheet's widest form (DESIGN §4: a sheet is at most 560 wide).
const double kAlarmSheetMaxWidth = 560;

/// A ring-screen row's "Ertele ▾" sheet (#47, spec §1.5, mockups A4/A5):
/// the user's four presets with the minute each lands on, "Saat seç…", then
/// under "Diğer" the ways out that are not a snooze — "Süresiz ertele",
/// "Tamamla" and "Aç". No cancel: the handle and the scrim close it, and a
/// closed sheet leaves the row ringing.
///
/// [onChoose] runs INSIDE the tap, before the sheet starts to close, so the
/// action silences in the same gesture (#46). Returns whether anything was
/// chosen.
///
/// [now] is a clock, read at the press: a preset counts from the moment it
/// is chosen, not from when the sheet opened — "5 min" picked six minutes
/// later must not land in the past and ring again at once.
Future<bool> showAlarmSnoozeSheet(
  BuildContext context, {
  required AlarmInput alarm,
  required List<String> presets,
  required DateTime Function() now,
  required String dateFormat,
  required void Function(AlarmSheetChoice choice) onChoose,
}) async {
  var chosen = false;
  final scheme = Theme.of(context).colorScheme;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    backgroundColor: scheme.surfaceContainerLow,
    constraints: const BoxConstraints(maxWidth: kAlarmSheetMaxWidth),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AwRadius.xl)),
    ),
    builder: (sheetContext) {
      void choose(AlarmSheetChoice choice) {
        if (chosen) return;
        chosen = true;
        // Close first, then answer in the same tap: "Saat seç…" opens its
        // pickers over the list, not under a sheet that is still on top.
        Navigator.of(sheetContext).pop();
        onChoose(choice);
      }

      return _AlarmSnoozeSheet(
        alarm: alarm,
        presets: presets,
        now: now,
        dateFormat: dateFormat,
        onChoose: choose,
      );
    },
  );
  return chosen;
}

class _AlarmSnoozeSheet extends StatelessWidget {
  const _AlarmSnoozeSheet({
    required this.alarm,
    required this.presets,
    required this.now,
    required this.dateFormat,
    required this.onChoose,
  });

  final AlarmInput alarm;
  final List<String> presets;
  final DateTime Function() now;
  final String dateFormat;
  final void Function(AlarmSheetChoice choice) onChoose;

  /// "09:05", or "tomorrow 09:00" when the preset lands on another day.
  String _lands(DateTime until, DateTime now) {
    final time = awFormatTime(until, format: dateFormat);
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(until.year, until.month, until.day);
    if (day == today) return time;
    return 'alarm.sheet.tomorrowAt'.tr(args: {'time': time});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final fireAt =
        (alarm.status == 'snoozed' ? alarm.snoozedUntil : null) ??
        alarm.remindAt;
    final time = awFormatTime(fireAt.toLocal(), format: dateFormat);
    final shownAt = now();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AwSpace.x4, 0, AwSpace.x4, AwSpace.x4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'alarm.ringing.snooze'.tr(),
            style: text.titleMedium?.copyWith(
              color: scheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AwSpace.x1),
          Text(
            '${alarm.taskTitle} · $time',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AwSpace.x3),
          for (final preset in presets) ...[
            _SheetRow(
              key: Key('alarm-sheet-snooze-$preset'),
              icon: Icons.schedule,
              label: kSnoozePresetLabels[preset]!.tr(),
              trailing: _lands(
                TaskStore.snoozeUntilFor(preset, now: shownAt),
                shownAt,
              ),
              // Counted from the press, never from the opening.
              onTap: () => onChoose(
                AlarmSheetSnooze(TaskStore.snoozeUntilFor(preset, now: now())),
              ),
            ),
            const SizedBox(height: AwSpace.x2),
          ],
          _SheetRow(
            key: const Key('alarm-sheet-custom'),
            icon: Icons.edit_calendar_outlined,
            label: 'alarm.snoozeCustom'.tr(),
            chevron: true,
            onTap: () => onChoose(const AlarmSheetCustom()),
          ),
          const SizedBox(height: AwSpace.x3),
          const Divider(height: 1),
          const SizedBox(height: AwSpace.x3),
          Text(
            'alarm.sheet.other'.tr(),
            style: text.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AwSpace.x2),
          _SheetRow(
            key: const Key('alarm-sheet-silence'),
            icon: Icons.notifications_off_outlined,
            label: 'alarm.silence'.tr(),
            hint: 'alarm.silenceHint'.tr(),
            onTap: () => onChoose(const AlarmSheetMute()),
          ),
          const SizedBox(height: AwSpace.x2),
          _SheetRow(
            key: const Key('alarm-sheet-complete'),
            icon: Icons.check_circle_outline,
            label: 'notif.action.complete'.tr(),
            onTap: () => onChoose(const AlarmSheetComplete()),
          ),
          const SizedBox(height: AwSpace.x2),
          _SheetRow(
            key: const Key('alarm-sheet-open'),
            icon: Icons.open_in_new,
            label: 'notif.action.open'.tr(),
            onTap: () => onChoose(const AlarmSheetOpen()),
          ),
        ],
      ),
    );
  }
}

/// One 56 pt row on `surfaceContainerHigh`, radius 16 (the sheet-tile
/// pattern): icon, label (and hint), the landing minute or a chevron.
class _SheetRow extends StatelessWidget {
  const _SheetRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.hint,
    this.trailing,
    this.chevron = false,
  });

  final IconData icon;
  final String label;
  final String? hint;
  final String? trailing;
  final bool chevron;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final trailing = this.trailing;
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(AwRadius.m),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: kAwAlarmSheetRowHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AwSpace.x4,
              vertical: AwSpace.x2,
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: scheme.onSurfaceVariant),
                const SizedBox(width: AwSpace.x3),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: text.bodyLarge?.copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (hint != null)
                        Text(
                          hint!,
                          style: text.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: AwSpace.x3),
                  Text(
                    trailing,
                    style: awTabular(
                      text.bodyMedium!.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
                if (chevron)
                  Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The sheet row's height (spec §1.5).
const double kAwAlarmSheetRowHeight = 56;
