import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../i18n/i18n.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';

/// How Home draws its calendar (OPH-401, DESIGN §47 W1).
enum AwCalendarMode { week, month }

/// Apple-Calendar-style month grid: weekday header, 6 rows of days, a dot
/// under days that have tasks, outlined today and a filled selected day.
/// Tapping the selected day again clears the selection.
///
/// OPH-401 (U-04, DESIGN §47 W1–W2): in [AwCalendarMode.week] it is one strip
/// of seven days (≈64 pt) instead of six rows; the header's arrows then move a
/// week, and its third button ([onModeChanged]) swaps strip and grid. Without
/// [onModeChanged] (the wide side panel) there is no swap — only the grid.
class MonthCalendar extends StatefulWidget {
  const MonthCalendar({
    super.key,
    required this.markedDays,
    required this.selectedDay,
    required this.onDaySelected,
    this.initialMonth,
    this.mode = AwCalendarMode.month,
    this.onModeChanged,
  });

  /// Local calendar days (midnight) that get a dot.
  final Set<DateTime> markedDays;
  final DateTime? selectedDay;
  final void Function(DateTime? day) onDaySelected;
  final DateTime? initialMonth;
  final AwCalendarMode mode;
  final ValueChanged<AwCalendarMode>? onModeChanged;

  @override
  State<MonthCalendar> createState() => _MonthCalendarState();
}

class _MonthCalendarState extends State<MonthCalendar> {
  late DateTime _month; // first day of the shown month
  late DateTime _week; // the Monday of the shown week (week mode)

  static DateTime _mondayOf(DateTime day) =>
      DateTime(day.year, day.month, day.day - (day.weekday - DateTime.monday));

  @override
  void initState() {
    super.initState();
    final base = widget.initialMonth ?? widget.selectedDay ?? DateTime.now();
    _month = DateTime(base.year, base.month);
    // The strip opens on the week you are working in: the selected day's,
    // else today's when the grid would open on this month, else the month's
    // first week.
    final now = DateTime.now();
    final weekBase =
        widget.selectedDay ??
        (widget.initialMonth == null ||
                (widget.initialMonth!.year == now.year &&
                    widget.initialMonth!.month == now.month)
            ? now
            : _month);
    _week = _mondayOf(weekBase);
  }

  @override
  void didUpdateWidget(MonthCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A day selected from OUTSIDE the grid (a widget's event row,
    // `alliswell://day/…`) may sit in another month: show the month it is in,
    // or the selection would be invisible.
    final day = widget.selectedDay;
    if (day != null &&
        day != oldWidget.selectedDay &&
        (day.year != _month.year || day.month != _month.month)) {
      setState(() => _month = DateTime(day.year, day.month));
    }
    if (day != null &&
        day != oldWidget.selectedDay &&
        _mondayOf(day) != _week) {
      setState(() => _week = _mondayOf(day));
    }
    // Swapping modes keeps you where you were: the grid opens on the strip's
    // month, the strip on the grid's selected day or today when it is in it.
    if (widget.mode != oldWidget.mode) {
      if (widget.mode == AwCalendarMode.month) {
        final thursday = _week.add(const Duration(days: 3));
        _month = DateTime(thursday.year, thursday.month);
      } else {
        final now = DateTime.now();
        final inMonth = now.year == _month.year && now.month == _month.month;
        _week = _mondayOf(day ?? (inMonth ? now : _month));
      }
    }
  }

  bool get _isWeek =>
      widget.mode == AwCalendarMode.week && widget.onModeChanged != null;

  void _shift(int delta) => setState(() {
    if (_isWeek) {
      _week = DateTime(_week.year, _week.month, _week.day + 7 * delta);
    } else {
      _month = DateTime(_month.year, _month.month + delta);
    }
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = DateTime.now();
    final todayDay = DateTime(today.year, today.month, today.day);

    // OPH-359 (UI-AUDIT #60): the month and the weekday names in the app's
    // language — they were fixed English arrays, so a Turkish screen said
    // "October 2026 / Mon Tue". The grid stays Monday-first.
    final locale = AwI18n.instance.locale.toLanguageTag();
    final week = _isWeek;
    // A week across two months is named by its Thursday's (ISO 8601).
    final monthTitle = DateFormat.yMMMM(
      locale,
    ).format(week ? _week.add(const Duration(days: 3)) : _month);
    final weekdays = [
      // 2024-01-01 was a Monday.
      for (var d = 1; d <= 7; d++)
        DateFormat.E(locale).format(DateTime(2024, 1, d)),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const SizedBox(width: 8),
            // Expanded + ellipsis so long month names (or mid-animation
            // widths) never overflow the header (DESIGN §9 L2).
            Expanded(
              child: Text(
                monthTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              tooltip: week
                  ? 'calendar.previousWeek'.tr()
                  : 'calendar.previousMonth'.tr(),
              icon: const Icon(Icons.chevron_left),
              color: theme.colorScheme.onSurfaceVariant,
              onPressed: () => _shift(-1),
            ),
            IconButton(
              tooltip: week
                  ? 'calendar.nextWeek'.tr()
                  : 'calendar.nextMonth'.tr(),
              icon: const Icon(Icons.chevron_right),
              color: theme.colorScheme.onSurfaceVariant,
              onPressed: () => _shift(1),
            ),
            if (widget.onModeChanged != null)
              IconButton(
                key: const Key('calendar-mode-toggle'),
                tooltip: week
                    ? 'calendar.showMonth'.tr()
                    : 'calendar.showWeek'.tr(),
                icon: Icon(week ? Icons.expand_more : Icons.expand_less),
                color: theme.colorScheme.onSurfaceVariant,
                onPressed: () => widget.onModeChanged!(
                  week ? AwCalendarMode.month : AwCalendarMode.week,
                ),
              ),
          ],
        ),
        if (week)
          Row(
            key: const Key('calendar-week-strip'),
            children: [
              for (var dow = 0; dow < 7; dow++)
                Expanded(
                  child: _WeekDayCell(
                    day: _week.add(Duration(days: dow)),
                    weekday: weekdays[dow],
                    isToday: _week.add(Duration(days: dow)) == todayDay,
                    selectedDay: widget.selectedDay,
                    hasTasks: widget.markedDays.contains(
                      _week.add(Duration(days: dow)),
                    ),
                    onTap: (day) => widget.onDaySelected(
                      day == widget.selectedDay ? null : day,
                    ),
                  ),
                ),
            ],
          ),
        if (!week) ..._grid(theme, weekdays, todayDay),
      ],
    );
  }

  List<Widget> _grid(
    ThemeData theme,
    List<String> weekdays,
    DateTime todayDay,
  ) {
    // Monday-first offset of the month's day 1.
    final leading = (_month.weekday - DateTime.monday) % 7;
    final firstCell = _month.subtract(Duration(days: leading));
    return [
      const SizedBox(height: 4),
      Row(
        children: [
          for (final label in weekdays)
            Expanded(
              child: Center(
                child: Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 4),
      for (var week = 0; week < 6; week++)
        Row(
          children: [
            for (var dow = 0; dow < 7; dow++)
              Expanded(
                child: _DayCell(
                  day: firstCell.add(Duration(days: week * 7 + dow)),
                  inMonth:
                      firstCell.add(Duration(days: week * 7 + dow)).month ==
                      _month.month,
                  isToday:
                      firstCell.add(Duration(days: week * 7 + dow)) == todayDay,
                  isSelected:
                      widget.selectedDay != null &&
                      firstCell.add(Duration(days: week * 7 + dow)) ==
                          widget.selectedDay,
                  hasTasks: widget.markedDays.contains(
                    firstCell.add(Duration(days: week * 7 + dow)),
                  ),
                  onTap: (day) => widget.onDaySelected(
                    day == widget.selectedDay ? null : day,
                  ),
                ),
              ),
          ],
        ),
    ];
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.inMonth,
    required this.isToday,
    required this.isSelected,
    required this.hasTasks,
    required this.onTap,
  });

  final DateTime day;
  final bool inMonth;
  final bool isToday;
  final bool isSelected;
  final bool hasTasks;
  final void Function(DateTime day) onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textColor = isSelected
        ? scheme.onPrimary
        : isToday
        ? scheme.primary
        : inMonth
        ? scheme.onSurface
        : scheme.onSurfaceVariant.withValues(alpha: 0.55);

    return InkWell(
      // A day number is NOT unique on this grid: a six-row month shows the
      // days either side of it, so "7" can be both the 7th of this month and
      // the 7th of the next one — dimmed, but there. A finder that goes by the
      // number picks between them by luck, and which month is even VISIBLE
      // depends on today's date. Found on 2026-09-02, when September's grid
      // reached 7 October and three tests that had been green for weeks went
      // ambiguous on the same morning.
      key: Key('calendar-day-${day.year}-${day.month}-${day.day}'),
      customBorder: const CircleBorder(),
      onTap: () => onTap(day),
      child: Semantics(
        button: true,
        selected: isSelected,
        // OPH-359 (UI-AUDIT #60): read in the app's language too, once —
        // the number under it is not read a second time.
        excludeSemantics: true,
        label: [
          '${day.day}',
          if (isToday) 'calendar.a11yToday'.tr(),
          if (hasTasks) 'calendar.a11yHasTasks'.tr(),
        ].join(', '),
        child: SizedBox(
          height: 46,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOutCubic,
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? scheme.primary : null,
                  border: isToday && !isSelected
                      ? Border.all(color: scheme.primary, width: 1.5)
                      : null,
                ),
                child: Text(
                  '${day.day}',
                  style: TextStyle(
                    color: textColor,
                    fontWeight: isToday || isSelected
                        ? FontWeight.w700
                        : FontWeight.w500,
                    fontSize: 13,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              SizedBox(
                height: 6,
                child: hasTasks
                    ? Icon(
                        Icons.circle,
                        size: 5,
                        color: isSelected ? scheme.primary : scheme.tertiary,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One day of the week strip (DESIGN §47 W2): weekday 11 pt w600 over the
/// day, 17 pt, in a 32 pt circle, and the task dot under it. The circle is
/// filled for the selected day — and for today while nothing is selected —
/// so the strip always says where "now" is without a second encoding.
class _WeekDayCell extends StatelessWidget {
  const _WeekDayCell({
    required this.day,
    required this.weekday,
    required this.isToday,
    required this.selectedDay,
    required this.hasTasks,
    required this.onTap,
  });

  final DateTime day;
  final String weekday;
  final bool isToday;
  final DateTime? selectedDay;
  final bool hasTasks;
  final void Function(DateTime day) onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isSelected = selectedDay == day;
    final filled = isSelected || (isToday && selectedDay == null);
    final ink = filled
        ? scheme.onPrimary
        : isToday
        ? scheme.primary
        : scheme.onSurface;
    return InkWell(
      key: Key('calendar-day-${day.year}-${day.month}-${day.day}'),
      borderRadius: BorderRadius.circular(AwRadius.s),
      onTap: () => onTap(day),
      child: Semantics(
        button: true,
        selected: isSelected,
        excludeSemantics: true,
        label: [
          '$weekday ${day.day}',
          if (isToday) 'calendar.a11yToday'.tr(),
          if (hasTasks) 'calendar.a11yHasTasks'.tr(),
        ].join(', '),
        child: SizedBox(
          height: 64,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                weekday,
                maxLines: 1,
                overflow: TextOverflow.clip,
                textScaler: MediaQuery.textScalerOf(
                  context,
                ).clamp(maxScaleFactor: 1.3),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isToday ? scheme.primary : scheme.onSurfaceVariant,
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOutCubic,
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: filled ? scheme.primary : null,
                  border: isToday && !filled
                      ? Border.all(color: scheme.primary, width: 1.5)
                      : null,
                ),
                child: Text(
                  '${day.day}',
                  maxLines: 1,
                  // Inside a fixed 32 pt circle: large text may not push the
                  // number out of it (U-12: "takvim hücresi clamp 1.3").
                  textScaler: MediaQuery.textScalerOf(
                    context,
                  ).clamp(maxScaleFactor: 1.3),
                  style: context.awText.dayNumber.copyWith(color: ink),
                ),
              ),
              SizedBox(
                height: 6,
                child: hasTasks
                    ? Icon(
                        Icons.circle,
                        size: 5,
                        color: filled ? scheme.primary : scheme.tertiary,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
