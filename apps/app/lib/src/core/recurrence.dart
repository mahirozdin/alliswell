/// The recurrence engine, Dart side (OPH-207, ADR-0020 §6).
///
/// This is a PORT, not a second source of truth: the server
/// (`apps/api/src/lib/recurrence.js`) produces every occurrence that ever
/// becomes a row. This copy exists so the dialog can show "Sonraki 5" while the
/// user builds a rule — offline, on every keystroke, without a round trip.
///
/// Both implementations assert `test/fixtures/recurrence_parity.json`, so
/// changing one alone turns a suite red. The same arrangement pins the Turkish
/// fold (ADR-0013, `core/fold.dart`).
///
/// Two deliberate deviations from RFC 5545, decided in ADR-0020 §2:
/// 1. invalid days clamp BACKWARDS (the 31st lands on the 28th, never skipped),
///    per value and then deduplicated;
/// 2. the anchor is not automatically an occurrence — only matching days are.
library;

/// Monday-first: the rule model has no WKST and this is the ISO order.
const List<String> kAwWeekdays = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];

/// Per-series materialization ceiling (ADR-0020 §4) — mirrors the server.
const int kAwMaxOccurrences = 400;

const int _iterationGuard = 20000;

enum AwRepeatFreq { daily, weekly, monthly, yearly }

extension AwRepeatFreqName on AwRepeatFreq {
  String get wire => name;
  static AwRepeatFreq? parse(Object? value) {
    for (final freq in AwRepeatFreq.values) {
      if (freq.name == value) return freq;
    }
    return null;
  }
}

/// One entry of `byWeekday`: a weekday, optionally the Nth (or last) one.
class AwWeekdayPick {
  const AwWeekdayPick(this.day, {this.ordinal});

  /// `MO`…`SU`.
  final String day;

  /// null = every such weekday; 1..5 = the Nth; -1 = the last.
  final int? ordinal;

  Map<String, dynamic> toJson() => {'day': day, 'ordinal': ordinal};

  static AwWeekdayPick? fromJson(Object? value) {
    if (value is! Map) return null;
    final day = value['day'];
    if (day is! String || !kAwWeekdays.contains(day)) return null;
    final ordinal = value['ordinal'];
    return AwWeekdayPick(day, ordinal: ordinal is int ? ordinal : null);
  }

  @override
  bool operator ==(Object other) =>
      other is AwWeekdayPick && other.day == day && other.ordinal == ordinal;

  @override
  int get hashCode => Object.hash(day, ordinal);
}

/// When a series stops: never, on a date, or after N occurrences.
class AwRepeatEnd {
  const AwRepeatEnd.never() : type = 'never', until = null, count = null;
  const AwRepeatEnd.until(String this.until) : type = 'until', count = null;
  const AwRepeatEnd.count(int this.count) : type = 'count', until = null;

  final String type;

  /// `YYYY-MM-DD`, inclusive.
  final String? until;
  final int? count;

  bool get isNever => type == 'never';

  Map<String, dynamic> toJson() => switch (type) {
    'until' => {'type': 'until', 'until': until},
    'count' => {'type': 'count', 'count': count},
    _ => {'type': 'never'},
  };

  static AwRepeatEnd fromJson(Object? value) {
    if (value is! Map) return const AwRepeatEnd.never();
    final until = value['until'];
    final count = value['count'];
    return switch (value['type']) {
      'until' when until is String => AwRepeatEnd.until(until),
      'count' when count is int => AwRepeatEnd.count(count),
      _ => const AwRepeatEnd.never(),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is AwRepeatEnd &&
      other.type == type &&
      other.until == until &&
      other.count == count;

  @override
  int get hashCode => Object.hash(type, until, count);
}

/// The ADR-0020 rule object.
class AwRepeatRule {
  const AwRepeatRule({
    required this.freq,
    this.interval = 1,
    this.byWeekday = const [],
    this.byMonthDay = const [],
    this.byMonth = const [],
    this.end = const AwRepeatEnd.never(),
  });

  final AwRepeatFreq freq;
  final int interval;
  final List<AwWeekdayPick> byWeekday;

  /// 1..31, or -1 for "the last day of the month".
  final List<int> byMonthDay;

  /// Yearly only: 1..12.
  final List<int> byMonth;
  final AwRepeatEnd end;

  AwRepeatRule copyWith({
    AwRepeatFreq? freq,
    int? interval,
    List<AwWeekdayPick>? byWeekday,
    List<int>? byMonthDay,
    List<int>? byMonth,
    AwRepeatEnd? end,
  }) => AwRepeatRule(
    freq: freq ?? this.freq,
    interval: interval ?? this.interval,
    byWeekday: byWeekday ?? this.byWeekday,
    byMonthDay: byMonthDay ?? this.byMonthDay,
    byMonth: byMonth ?? this.byMonth,
    end: end ?? this.end,
  );

  Map<String, dynamic> toJson() => {
    'freq': freq.name,
    'interval': interval,
    if (byWeekday.isNotEmpty)
      'byWeekday': byWeekday.map((w) => w.toJson()).toList(),
    if (byMonthDay.isNotEmpty) 'byMonthDay': byMonthDay,
    if (byMonth.isNotEmpty) 'byMonth': byMonth,
    'end': end.toJson(),
  };

  static AwRepeatRule? fromJson(Object? value) {
    if (value is! Map) return null;
    final freq = AwRepeatFreqName.parse(value['freq']);
    if (freq == null) return null;
    final interval = value['interval'];
    return AwRepeatRule(
      freq: freq,
      interval: interval is int && interval >= 1 ? interval : 1,
      byWeekday: [
        for (final entry in (value['byWeekday'] as List? ?? const []))
          ?AwWeekdayPick.fromJson(entry),
      ],
      byMonthDay: [
        for (final day in (value['byMonthDay'] as List? ?? const []))
          if (day is int) day,
      ],
      byMonth: [
        for (final month in (value['byMonth'] as List? ?? const []))
          if (month is int) month,
      ],
      end: AwRepeatEnd.fromJson(value['end']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AwRepeatRule &&
      other.freq == freq &&
      other.interval == interval &&
      other.end == end &&
      _sameList(other.byWeekday, byWeekday) &&
      _sameList(other.byMonthDay, byMonthDay) &&
      _sameList(other.byMonth, byMonth);

  @override
  int get hashCode => Object.hash(
    freq,
    interval,
    end,
    Object.hashAll(byWeekday),
    Object.hashAll(byMonthDay),
    Object.hashAll(byMonth),
  );
}

bool _sameList<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i += 1) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// A wall date, with no timezone attached — the engine never sees a clock.
class _Day implements Comparable<_Day> {
  const _Day(this.year, this.month, this.day);

  final int year;
  final int month;
  final int day;

  @override
  int compareTo(_Day other) {
    if (year != other.year) return year - other.year;
    if (month != other.month) return month - other.month;
    return day - other.day;
  }

  String get key =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';
}

/// `YYYY-MM-DD` → parts, or null when the string is not a real date.
_Day? _parseDay(String? value) {
  if (value == null) return null;
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  if (month < 1 || month > 12) return null;
  if (day < 1 || day > awLastDayOfMonth(year, month)) return null;
  return _Day(year, month, day);
}

/// `YYYY-MM-DD` for a local [DateTime] — the app's way into the engine.
String awDayKey(DateTime date) => _Day(date.year, date.month, date.day).key;

int awLastDayOfMonth(int year, int month) =>
    DateTime.utc(year, month + 1, 0).day;

/// 0 = Monday … 6 = Sunday.
int _weekdayIndex(int year, int month, int day) =>
    DateTime.utc(year, month, day).weekday - 1;

_Day _addDays(_Day from, int delta) {
  final moved = DateTime.utc(from.year, from.month, from.day + delta);
  return _Day(moved.year, moved.month, moved.day);
}

_Day _startOfWeek(_Day day) =>
    _addDays(day, -_weekdayIndex(day.year, day.month, day.day));

/// Semantic validation on top of the model's own shape.
/// Returns null when the rule is usable, or a developer-facing reason.
String? awValidateRepeatRule(AwRepeatRule rule) {
  if (rule.interval < 1 || rule.interval > 366) {
    return 'interval must be an integer between 1 and 366';
  }
  if (rule.byWeekday.isNotEmpty) {
    if (rule.freq == AwRepeatFreq.daily) {
      return 'byWeekday is not allowed with freq=daily; use freq=weekly';
    }
    for (final pick in rule.byWeekday) {
      if (!kAwWeekdays.contains(pick.day)) return 'unknown weekday';
      final ordinal = pick.ordinal;
      if (ordinal == null) continue;
      if (rule.freq != AwRepeatFreq.monthly &&
          rule.freq != AwRepeatFreq.yearly) {
        return 'byWeekday.ordinal is only allowed with freq=monthly or yearly';
      }
      if (ordinal == 0 || ordinal > 5 || ordinal < -1) {
        return 'byWeekday.ordinal must be 1..5 or -1 (last)';
      }
    }
  }
  if (rule.byMonthDay.isNotEmpty) {
    if (rule.freq != AwRepeatFreq.monthly && rule.freq != AwRepeatFreq.yearly) {
      return 'byMonthDay is only allowed with freq=monthly or yearly';
    }
    for (final day in rule.byMonthDay) {
      if (day == 0 || day > 31 || day < -1) {
        return 'byMonthDay entries must be 1..31 or -1 (last day)';
      }
    }
  }
  if (rule.byMonth.isNotEmpty) {
    if (rule.freq != AwRepeatFreq.yearly) {
      return 'byMonth is only allowed with freq=yearly';
    }
    for (final month in rule.byMonth) {
      if (month < 1 || month > 12) return 'byMonth entries must be 1..12';
    }
  }
  if (rule.end.type == 'until' && _parseDay(rule.end.until) == null) {
    return 'end.until must be a YYYY-MM-DD date';
  }
  if (rule.end.type == 'count') {
    final count = rule.end.count ?? 0;
    if (count < 1 || count > 1000) {
      return 'end.count must be an integer between 1 and 1000';
    }
  }
  return null;
}

/// The day-of-month set a monthly/yearly rule selects in one concrete month —
/// where ADR-0020's "clamp per value, then dedupe" lives.
List<int> _daysInMonthFor(AwRepeatRule rule, int year, int month, _Day anchor) {
  final last = awLastDayOfMonth(year, month);
  final hasMonthDays = rule.byMonthDay.isNotEmpty;
  final hasWeekdays = rule.byWeekday.isNotEmpty;

  // No day selector at all: repeat the anchor's day-of-month, clamped.
  if (!hasMonthDays && !hasWeekdays) {
    return [anchor.day < last ? anchor.day : last];
  }

  Set<int>? monthDays;
  if (hasMonthDays) {
    monthDays = <int>{};
    for (final value in rule.byMonthDay) {
      // -1 is "the last day"; a positive day past the month end clamps
      // BACKWARD onto it (31 → 30/29/28). Duplicates collapse — the point of
      // using a Set.
      final day = value < 0 ? last + 1 + value : (value < last ? value : last);
      if (day >= 1 && day <= last) monthDays.add(day);
    }
  }

  Set<int>? weekdayDays;
  if (hasWeekdays) {
    weekdayDays = <int>{};
    for (final pick in rule.byWeekday) {
      final target = kAwWeekdays.indexOf(pick.day);
      final matches = <int>[];
      for (var day = 1; day <= last; day += 1) {
        if (_weekdayIndex(year, month, day) == target) matches.add(day);
      }
      final ordinal = pick.ordinal;
      if (ordinal == null) {
        weekdayDays.addAll(matches);
      } else if (ordinal == -1) {
        if (matches.isNotEmpty) weekdayDays.add(matches.last);
      } else if (matches.length >= ordinal) {
        // A 5th Tuesday simply does not exist in most months — no clamping
        // here: "the 5th Tuesday" is a real choice about which months count.
        weekdayDays.add(matches[ordinal - 1]);
      }
    }
  }

  final List<int> result;
  if (monthDays != null && weekdayDays != null) {
    // RFC 5545: with FREQ=MONTHLY, BYDAY *limits* BYMONTHDAY. This intersection
    // is how "the first Monday after the 22nd" is expressed (ADR-0020 §3).
    result = monthDays.where(weekdayDays.contains).toList();
  } else {
    result = (monthDays ?? weekdayDays)!.toList();
  }
  result.sort();
  return result;
}

List<_Day> _candidates(AwRepeatRule rule, _Day anchor, int step) {
  switch (rule.freq) {
    case AwRepeatFreq.daily:
      return [_addDays(anchor, step * rule.interval)];
    case AwRepeatFreq.weekly:
      final weekStart = _addDays(
        _startOfWeek(anchor),
        step * rule.interval * 7,
      );
      final targets = rule.byWeekday.isNotEmpty
          ? rule.byWeekday.map((w) => kAwWeekdays.indexOf(w.day)).toSet()
          : {_weekdayIndex(anchor.year, anchor.month, anchor.day)};
      final offsets = targets.toList()..sort();
      return [for (final offset in offsets) _addDays(weekStart, offset)];
    case AwRepeatFreq.monthly:
      final index =
          anchor.year * 12 + (anchor.month - 1) + step * rule.interval;
      final year = index ~/ 12;
      final month = (index % 12) + 1;
      return [
        for (final day in _daysInMonthFor(rule, year, month, anchor))
          _Day(year, month, day),
      ];
    case AwRepeatFreq.yearly:
      final year = anchor.year + step * rule.interval;
      final months = rule.byMonth.isNotEmpty
          ? (rule.byMonth.toSet().toList()..sort())
          : [anchor.month];
      return [
        for (final month in months)
          for (final day in _daysInMonthFor(rule, year, month, anchor))
            _Day(year, month, day),
      ];
  }
}

/// The first calendar day a period could possibly touch — the walk's exit
/// condition, so a rule that produces nothing for a stretch (there is no 5th
/// Monday in most months) does not step to the iteration guard.
_Day _periodStart(AwRepeatRule rule, _Day anchor, int step) {
  switch (rule.freq) {
    case AwRepeatFreq.daily:
      return _addDays(anchor, step * rule.interval);
    case AwRepeatFreq.weekly:
      return _addDays(_startOfWeek(anchor), step * rule.interval * 7);
    case AwRepeatFreq.monthly:
      final index =
          anchor.year * 12 + (anchor.month - 1) + step * rule.interval;
      return _Day(index ~/ 12, (index % 12) + 1, 1);
    case AwRepeatFreq.yearly:
      return _Day(anchor.year + step * rule.interval, 1, 1);
  }
}

/// Expand a rule into `YYYY-MM-DD` days.
///
/// Counting always starts at [anchor] — `end.count` means "the Nth occurrence
/// of this series", not "the Nth one currently visible".
///
/// Throws [ArgumentError] on an unusable rule or a malformed date, exactly
/// where the JS engine throws.
List<String> awExpandOccurrences(
  AwRepeatRule rule, {
  required String anchor,
  String? from,
  String? to,
  int max = kAwMaxOccurrences,
}) {
  final problem = awValidateRepeatRule(rule);
  if (problem != null) throw ArgumentError(problem);

  final anchorDay = _parseDay(anchor);
  if (anchorDay == null) {
    throw ArgumentError('anchor must be a YYYY-MM-DD date');
  }
  final fromDay = from == null ? anchorDay : _parseDay(from);
  if (fromDay == null) throw ArgumentError('from must be a YYYY-MM-DD date');
  final toDay = to == null ? null : _parseDay(to);
  if (to != null && toDay == null) {
    throw ArgumentError('to must be a YYYY-MM-DD date');
  }

  final untilDay = rule.end.type == 'until' ? _parseDay(rule.end.until) : null;
  final limit = rule.end.type == 'count' ? rule.end.count! : null;

  final out = <String>[];
  var emitted = 0; // occurrences since the anchor — what end.count counts

  for (var step = 0; step < _iterationGuard; step += 1) {
    if (toDay != null &&
        _periodStart(rule, anchorDay, step).compareTo(toDay) > 0) {
      return out;
    }
    final candidates = _candidates(rule, anchorDay, step)..sort();
    for (final candidate in candidates) {
      if (candidate.compareTo(anchorDay) < 0) continue; // before the series
      if (untilDay != null && candidate.compareTo(untilDay) > 0) return out;
      if (limit != null && emitted >= limit) return out;
      emitted += 1;

      if (toDay != null && candidate.compareTo(toDay) > 0) continue;
      if (candidate.compareTo(fromDay) < 0) continue;
      out.add(candidate.key);
      if (out.length >= max) return out;
    }
  }
  return out;
}
