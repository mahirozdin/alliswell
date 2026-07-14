import 'package:flutter/material.dart';

/// Apple-Calendar-style month grid: weekday header, 6 rows of days, a dot
/// under days that have tasks, outlined today and a filled selected day.
/// Tapping the selected day again clears the selection.
class MonthCalendar extends StatefulWidget {
  const MonthCalendar({
    super.key,
    required this.markedDays,
    required this.selectedDay,
    required this.onDaySelected,
    this.initialMonth,
  });

  /// Local calendar days (midnight) that get a dot.
  final Set<DateTime> markedDays;
  final DateTime? selectedDay;
  final void Function(DateTime? day) onDaySelected;
  final DateTime? initialMonth;

  @override
  State<MonthCalendar> createState() => _MonthCalendarState();
}

class _MonthCalendarState extends State<MonthCalendar> {
  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  late DateTime _month; // first day of the shown month

  @override
  void initState() {
    super.initState();
    final base = widget.initialMonth ?? widget.selectedDay ?? DateTime.now();
    _month = DateTime(base.year, base.month);
  }

  void _shiftMonth(int delta) =>
      setState(() => _month = DateTime(_month.year, _month.month + delta));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = DateTime.now();
    final todayDay = DateTime(today.year, today.month, today.day);

    // Monday-first offset of the month's day 1.
    final leading = (_month.weekday - DateTime.monday) % 7;
    final firstCell = _month.subtract(Duration(days: leading));

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const SizedBox(width: 4),
            Text(
              '${_months[_month.month - 1]} ${_month.year}',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Previous month',
              icon: const Icon(Icons.chevron_left),
              onPressed: () => _shiftMonth(-1),
            ),
            IconButton(
              tooltip: 'Next month',
              icon: const Icon(Icons.chevron_right),
              onPressed: () => _shiftMonth(1),
            ),
          ],
        ),
        Row(
          children: [
            for (final label in _weekdays)
              Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
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
                        firstCell.add(Duration(days: week * 7 + dow)) ==
                        todayDay,
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
      ],
    );
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
        : inMonth
        ? scheme.onSurface
        : scheme.onSurfaceVariant.withValues(alpha: 0.5);

    return InkWell(
      customBorder: const CircleBorder(),
      onTap: () => onTap(day),
      child: SizedBox(
        height: 44,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? scheme.primary : null,
                border: isToday && !isSelected
                    ? Border.all(color: scheme.primary)
                    : null,
              ),
              child: Text(
                '${day.day}',
                style: TextStyle(
                  color: textColor,
                  fontWeight: isToday || isSelected ? FontWeight.bold : null,
                  fontSize: 13,
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
    );
  }
}
