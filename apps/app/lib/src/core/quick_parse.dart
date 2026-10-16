/// Offline natural-language quick add (OPH-373, ADR-0054).
///
/// "Yarın 9'da kira #ev" → title "kira", due tomorrow 09:00, tag "ev". Pure
/// Dart and deterministic: no Flutter, no i18n, no clock of its own (`now` is
/// injected), so the quick-add bars, the headless capture paths (OPH-376) and
/// the unit tests all run the same code. Turkish and English are BOTH always
/// active, whatever the UI language — the words are matched on the ADR-0013
/// fold, so "yarin", "carsamba" and "persembe" typed without Turkish letters
/// work as well.
///
/// The grammar is a contract (ADR-0054, DESIGN §39, the in-app help sheet,
/// `test/fixtures/quick_parse_cases.json`); change all four together.
///
/// - A date phrase with no keyword is the DEADLINE (dueAt). "son"/"bitiş"/
///   "DATE'(y)a kadar"/"due"/"by"/"deadline" say it explicitly.
/// - "başla"/"başlangıç" (before or right after the date) and "start"/
///   "starts"/"starting" (before) make it the WHEN day (startAt, no time).
/// - `#tag`, `+Project` (existing projects only), `p1`..`p4` / `!1`..`!4`
///   (Todoist's mapping, as the importer: p1 = high … p4 = none) and the
///   words `!acil` `!urgent` `!yüksek` `!high` `!orta` `!medium` `!düşük`
///   `!low`.
/// - Recurrence maps onto the ADR-0020 rule model; the deadline becomes the
///   rule's first occurrence after now.
///
/// All day arithmetic is `DateTime(y, m, d + n)` (never `add(Duration)`,
/// which drifts across DST — LESSONS flutter-app); every result is a LOCAL
/// wall time the caller converts.
library;

import 'fold.dart';
import 'recurrence.dart';

/// A project the `+Name` token may resolve to.
class AwQuickProject {
  const AwQuickProject({required this.id, required this.name});

  final String id;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is AwQuickProject && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}

/// Everything the parser needs from the outside world.
class AwQuickParseOptions {
  const AwQuickParseOptions({
    required this.now,
    this.weekStart = DateTime.monday,
    this.defaultHour = 23,
    this.defaultMinute = 59,
    this.monthFirstSlash = false,
    this.projects = const [],
    this.parseProject = true,
    this.ignored = const {},
  });

  /// Device-local "now".
  final DateTime now;

  /// `DateTime.monday` … `DateTime.sunday`; "next week" / "haftaya cuma"
  /// count weeks from it. The app is Monday-first today (ADR-0020).
  final int weekStart;

  /// The time a day-only deadline lands on (the default task time).
  final int defaultHour;
  final int defaultMinute;

  /// `5/11` is May 11 instead of 5 November (US date format preference).
  final bool monthFirstSlash;

  final List<AwQuickProject> projects;

  /// Off where the project is fixed (the project's own Tasks tab).
  final bool parseProject;

  /// Dismissed recognitions ([AwQuickToken.key]): their words stay text.
  final Set<String> ignored;

  AwQuickParseOptions copyWith({Set<String>? ignored}) => AwQuickParseOptions(
    now: now,
    weekStart: weekStart,
    defaultHour: defaultHour,
    defaultMinute: defaultMinute,
    monthFirstSlash: monthFirstSlash,
    projects: projects,
    parseProject: parseProject,
    ignored: ignored ?? this.ignored,
  );
}

enum AwQuickTokenKind { due, when, time, repeat, tag, project, priority }

/// One recognized phrase: a contiguous run of words of the ORIGINAL text.
class AwQuickToken {
  const AwQuickToken({
    required this.kind,
    required this.start,
    required this.end,
    required this.key,
    required this.text,
  });

  final AwQuickTokenKind kind;

  /// Offsets into the original text, `end` exclusive.
  final int start;
  final int end;

  /// `<kind>:<folded source>` — the dismissal identity.
  final String key;

  /// The source substring, as typed.
  final String text;

  @override
  String toString() => '${kind.name}($start..$end "$text")';
}

/// What the bar shows as one chip: a deadline and its time are ONE chip, so
/// undoing "yarın" also gives "9'da" back to the title.
class AwQuickChip {
  const AwQuickChip({required this.kind, required this.tokens});

  /// due, when, repeat, tag, project or priority (never time).
  final AwQuickTokenKind kind;
  final List<AwQuickToken> tokens;

  List<String> get keys => [for (final t in tokens) t.key];

  /// Stable identity for widgets.
  String get id => keys.join('|');
}

class AwQuickParse {
  const AwQuickParse({
    required this.title,
    required this.tokens,
    required this.chips,
    this.dueAt,
    this.dueHasTime = false,
    this.whenDay,
    this.repeat,
    this.tagNames = const [],
    this.project,
    this.priority,
  });

  /// The words nothing recognized, in their original casing — or the whole
  /// text when nothing would be left.
  final String title;
  final List<AwQuickToken> tokens;
  final List<AwQuickChip> chips;

  /// Local deadline, with the default task time when no time was typed.
  final DateTime? dueAt;
  final bool dueHasTime;

  /// Local midnight of the "when" day.
  final DateTime? whenDay;
  final AwRepeatRule? repeat;

  /// As typed (no '#'), deduplicated on the fold.
  final List<String> tagNames;
  final AwQuickProject? project;

  /// One of `kTaskPriorities`.
  final String? priority;

  bool get hasSchedule => dueAt != null || whenDay != null || repeat != null;

  bool get isEmpty => tokens.isEmpty;
}

// ─── tokenizing ─────────────────────────────────────────────────────────────

class _Word {
  _Word(this.raw, this.start, this.end)
    : norm = _normWord(raw),
      bare = _normWord(raw).replaceAll("'", '');

  /// As typed.
  final String raw;
  final int start;
  final int end;

  /// Folded, apostrophes unified, trailing punctuation dropped.
  final String norm;

  /// [norm] without apostrophes ("9'da" → "9da").
  final String bare;
}

final RegExp _apostrophes = RegExp('[’ʼ`´‘]');
final RegExp _trailingPunct = RegExp(r'[,;.!?:)\]]+$');
final RegExp _leadingPunct = RegExp(r'^[(\[]+');

String _unifyApostrophes(String s) => s.replaceAll(_apostrophes, "'");

String _normWord(String raw) {
  var s = foldSearchText(_unifyApostrophes(raw));
  // Keep a leading '!' (priority) and the inner dots of 15.11.2026.
  s = s.replaceFirst(_leadingPunct, '');
  if (!RegExp(r'^!\w+$').hasMatch(s)) s = s.replaceFirst(_trailingPunct, '');
  return s;
}

List<_Word> _tokenize(String text) => [
  for (final m in RegExp(r'\S+').allMatches(text))
    _Word(m.group(0)!, m.start, m.end),
];

// ─── vocabulary ─────────────────────────────────────────────────────────────

const Map<String, int> _numberWords = {
  'bir': 1, 'iki': 2, 'uc': 3, 'dort': 4, 'bes': 5, //
  'alti': 6, 'yedi': 7, 'sekiz': 8, 'dokuz': 9, 'on': 10,
  'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, //
  'six': 6, 'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10, 'a': 1,
};

int? _count(String norm) {
  final n = RegExp(r'^\d{1,3}$').hasMatch(norm) ? int.parse(norm) : null;
  if (n != null) return n >= 1 ? n : null;
  return _numberWords[norm];
}

// Turkish weekday stems (folded); suffixes are checked separately.
const List<(String, int)> _trWeekdays = [
  ('pazartesi', DateTime.monday),
  ('pzt', DateTime.monday),
  ('sali', DateTime.tuesday),
  ('carsamba', DateTime.wednesday),
  ('persembe', DateTime.thursday),
  ('cumartesi', DateTime.saturday),
  ('cmt', DateTime.saturday),
  ('cuma', DateTime.friday),
  ('pazar', DateTime.sunday),
];

// Plural "every <weekday>" forms: "cumaları", "pazartesileri".
const Map<String, int> _trWeekdayPlurals = {
  'pazartesileri': DateTime.monday,
  'salilari': DateTime.tuesday,
  'carsambalari': DateTime.wednesday,
  'persembeleri': DateTime.thursday,
  'cumalari': DateTime.friday,
  'cumartesileri': DateTime.saturday,
  'pazarlari': DateTime.sunday,
};

const Map<String, int> _enWeekdays = {
  'monday': DateTime.monday,
  'mon': DateTime.monday,
  'tuesday': DateTime.tuesday,
  'tue': DateTime.tuesday,
  'tues': DateTime.tuesday,
  'wednesday': DateTime.wednesday,
  'wed': DateTime.wednesday,
  'thursday': DateTime.thursday,
  'thu': DateTime.thursday,
  'thur': DateTime.thursday,
  'thurs': DateTime.thursday,
  'friday': DateTime.friday,
  'fri': DateTime.friday,
  'saturday': DateTime.saturday,
  'sunday': DateTime.sunday,
};

/// Only after a keyword ("next sat", "every sun"): bare they are words.
const Map<String, int> _enWeekdaysKeyworded = {
  'sat': DateTime.saturday,
  'sun': DateTime.sunday,
};

/// Words after "pazar" that make it the market, not Sunday.
const Set<String> _pazarNouns = {
  'listesi',
  'alisverisi',
  'yeri',
  'tezgahi',
  'arabasi',
};

const Set<String> _trDative = {'a', 'e', 'ya', 'ye'};
const Set<String> _trLocative = {'da', 'de', 'ta', 'te'};

// (stem, month); k→ğ softening ("ocağa", "aralığa") as extra stems.
const List<(String, int)> _trMonths = [
  ('ocak', 1), ('ocag', 1), ('subat', 2), ('mart', 3), ('nisan', 4), //
  ('mayis', 5), ('haziran', 6), ('temmuz', 7), ('agustos', 8), //
  ('eylul', 9), ('ekim', 10), ('kasim', 11), ('aralik', 12), ('aralig', 12),
];

const Map<String, int> _enMonths = {
  'january': 1, 'jan': 1, 'february': 2, 'feb': 2, 'march': 3, 'mar': 3, //
  'april': 4, 'apr': 4, 'may': 5, 'june': 6, 'jun': 6, 'july': 7, 'jul': 7,
  'august': 8, 'aug': 8, 'september': 9, 'sep': 9, 'sept': 9, //
  'october': 10, 'oct': 10, 'november': 11, 'nov': 11, 'december': 12,
  'dec': 12,
};

const Set<String> _dueKeywords = {'son', 'bitis', 'due', 'by', 'deadline'};
const Set<String> _whenBefore = {
  'basla',
  'baslangic',
  'start',
  'starts',
  'starting',
};
const Set<String> _whenAfter = {'basla', 'baslangic'};

const Map<String, String> _priorityWords = {
  'p1': 'high',
  'p2': 'medium',
  'p3': 'low',
  'p4': 'none',
  '!1': 'high',
  '!2': 'medium',
  '!3': 'low',
  '!4': 'none',
  '!acil': 'urgent',
  '!urgent': 'urgent',
  '!yuksek': 'high',
  '!high': 'high',
  '!orta': 'medium',
  '!medium': 'medium',
  '!dusuk': 'low',
  '!low': 'low',
};

// ─── candidates ─────────────────────────────────────────────────────────────

/// A date phrase starting at some word.
class _DateHit {
  const _DateHit(
    this.day,
    this.len, {
    this.dative = false,
    this.weekdayToday = false,
  });

  final DateTime day;
  final int len;

  /// Its last word carries a Turkish dative ("cumaya") — "kadar" may follow.
  final bool dative;

  /// A bare weekday that resolved to today: a passed time moves it +7.
  final bool weekdayToday;
}

class _Cand {
  _Cand(
    this.kind,
    this.len, {
    this.date,
    this.hour,
    this.minute,
    this.rule,
    this.tag,
    this.project,
    this.priority,
  });

  final AwQuickTokenKind kind;
  final int len;
  final _DateHit? date;
  final int? hour;
  final int? minute;
  final AwRepeatRule? rule;
  final String? tag;
  final AwQuickProject? project;
  final String? priority;
}

class _Parser {
  _Parser(this.text, this.o)
    : words = _tokenize(text),
      today = DateTime(o.now.year, o.now.month, o.now.day);

  final String text;
  final AwQuickParseOptions o;
  final List<_Word> words;
  final DateTime today;

  String n(int i) => i < words.length ? words[i].norm : '';
  String b(int i) => i < words.length ? words[i].bare : '';

  DateTime _plusDays(DateTime d, int days) =>
      DateTime(d.year, d.month, d.day + days);

  DateTime _plusMonths(DateTime d, int months) {
    final first = DateTime(d.year, d.month + months, 1);
    final last = awLastDayOfMonth(first.year, first.month);
    return DateTime(first.year, first.month, d.day > last ? last : d.day);
  }

  DateTime get _weekStartDay =>
      _plusDays(today, -((today.weekday - o.weekStart + 7) % 7));

  DateTime _nextWeek(int weekday) {
    final start = _plusDays(_weekStartDay, 7);
    return _plusDays(start, (weekday - o.weekStart + 7) % 7);
  }

  // ── words ──

  /// (weekday, dative) for "cuma", "cumaya", "cuma'ya", "friday".
  (int, bool)? _weekday(int i, {bool keyworded = false}) {
    final word = b(i);
    if (word.isEmpty) return null;
    final en =
        _enWeekdays[word] ?? (keyworded ? _enWeekdaysKeyworded[word] : null);
    if (en != null) return (en, false);
    for (final (stem, day) in _trWeekdays) {
      if (!word.startsWith(stem)) continue;
      final rest = word.substring(stem.length);
      if (rest.isEmpty || _trDative.contains(rest)) {
        if (stem == 'pazar' && rest.isEmpty && _pazarNouns.contains(n(i + 1))) {
          return null;
        }
        return (day, rest.isNotEmpty);
      }
    }
    return null;
  }

  /// Weekday in its plain form only (recurrence lists).
  int? _plainWeekday(int i) {
    final word = b(i);
    final en = _enWeekdays[word] ?? _enWeekdaysKeyworded[word];
    if (en != null) return en;
    for (final (stem, day) in _trWeekdays) {
      if (word == stem) return day;
    }
    return null;
  }

  /// (month, dative) for "kasım", "kasım'da", "kasıma", "nov".
  (int, bool, bool)? _month(int i) {
    final word = b(i);
    if (word.isEmpty) return null;
    final en = _enMonths[word];
    if (en != null) return (en, false, false);
    for (final (stem, month) in _trMonths) {
      if (!word.startsWith(stem)) continue;
      final rest = word.substring(stem.length);
      if (rest.isEmpty) return (month, false, false);
      if (_trDative.contains(rest)) return (month, true, true);
      if (_trLocative.contains(rest)) return (month, false, true);
    }
    return null;
  }

  int? _dayNum(int i) {
    final m = RegExp(r'^(\d{1,2})(?:st|nd|rd|th)?$').firstMatch(n(i));
    if (m == null) return null;
    final d = int.parse(m.group(1)!);
    return d >= 1 && d <= 31 ? d : null;
  }

  int? _year(int i) {
    if (!RegExp(r'^\d{4}$').hasMatch(n(i))) return null;
    final y = int.parse(n(i));
    return y >= 1970 && y <= 2199 ? y : null;
  }

  /// A concrete day, or null when it does not exist. No year → this year,
  /// or next year once the day has passed.
  DateTime? _resolve(int day, int month, int? year) {
    if (month < 1 || month > 12 || day < 1) return null;
    if (year != null) {
      if (day > awLastDayOfMonth(year, month)) return null;
      return DateTime(year, month, day);
    }
    var y = today.year;
    if (day > awLastDayOfMonth(y, month)) return null;
    if (DateTime(y, month, day).isBefore(today)) {
      y += 1;
      if (day > awLastDayOfMonth(y, month)) return null;
    }
    return DateTime(y, month, day);
  }

  // ── date phrases ──

  List<_DateHit> _dates(int i, {bool keyworded = false}) {
    final out = <_DateHit>[];
    final numeric = _numericDate(i);
    if (numeric != null) out.add(numeric);
    out.addAll(_namedDates(i));
    out.addAll(_relative(i, keyworded: keyworded));
    out.addAll(_weekdayDates(i, keyworded: keyworded));
    return out;
  }

  _DateHit? _numericDate(int i) {
    final word = n(i);
    if (word.isEmpty) return null;
    final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(word);
    if (iso != null) {
      final day = _resolve(
        int.parse(iso.group(3)!),
        int.parse(iso.group(2)!),
        int.parse(iso.group(1)!),
      );
      return day == null ? null : _DateHit(day, 1);
    }
    final m = RegExp(
      r"^(\d{1,2})([./])(\d{1,2})(?:[./](\d{4}|\d{2}))?(?:'?([a-z]+))?$",
    ).firstMatch(word);
    if (m == null) return null;
    final first = m.group(1)!;
    final sep = m.group(2)!;
    final second = m.group(3)!;
    final yearText = m.group(4);
    final suffix = m.group(5);
    // The separator must not change within one date ("15.11/26").
    if (yearText != null && !word.contains('$sep$yearText')) return null;
    if (suffix != null &&
        !_trDative.contains(suffix) &&
        !_trLocative.contains(suffix)) {
      return null;
    }
    // "3.5 kg", "1/2": with no year, one part must have two digits.
    if (yearText == null && first.length < 2 && second.length < 2) return null;
    final a = int.parse(first);
    final c = int.parse(second);
    int? year;
    if (yearText != null) {
      year = int.parse(yearText);
      if (yearText.length == 2) year += 2000;
    }
    DateTime? day;
    if (sep == '.') {
      day = _resolve(a, c, year);
    } else if (a > 12 && c <= 12) {
      day = _resolve(a, c, year);
    } else if (c > 12 && a <= 12) {
      day = _resolve(c, a, year);
    } else {
      day = o.monthFirstSlash ? _resolve(c, a, year) : _resolve(a, c, year);
    }
    if (day == null) return null;
    return _DateHit(
      day,
      1,
      dative: suffix != null && _trDative.contains(suffix),
    );
  }

  List<_DateHit> _namedDates(int i) {
    final out = <_DateHit>[];
    // "15 Kasım [2026]", "15th of November", "15. Kasım'da"
    final d = _dayNum(i);
    if (d != null) {
      var at = i + 1;
      if (n(at) == 'of') at += 1;
      final month = _month(at);
      if (month != null) {
        final (m, dative, suffixed) = month;
        final year = suffixed ? null : _year(at + 1);
        final day = _resolve(d, m, year);
        if (day != null) {
          out.add(
            _DateHit(day, at - i + 1 + (year != null ? 1 : 0), dative: dative),
          );
        }
      }
    }
    // "Nov 15[, 2026]", "Kasım 15"
    final month = _month(i);
    if (month != null && !month.$3) {
      final day2 = _dayNum(i + 1);
      if (day2 != null) {
        final year = _year(i + 2);
        final day = _resolve(day2, month.$1, year);
        if (day != null) out.add(_DateHit(day, year != null ? 3 : 2));
      }
    }
    return out;
  }

  List<_DateHit> _relative(int i, {bool keyworded = false}) {
    final out = <_DateHit>[];
    final w = n(i);
    final w1 = n(i + 1);
    final w2 = n(i + 2);
    final bw = b(i);
    void add(DateTime day, int len, {bool dative = false}) =>
        out.add(_DateHit(day, len, dative: dative));

    if (bw == 'bugun' || w == 'today') add(today, 1);
    if (bw == 'bugune') add(today, 1, dative: true);
    if (bw == 'yarin' || w == 'tomorrow') add(_plusDays(today, 1), 1);
    if (bw == 'yarina') add(_plusDays(today, 1), 1, dative: true);
    if (bw == 'oburgun') add(_plusDays(today, 2), 1);
    if (bw == 'oburgune') add(_plusDays(today, 2), 1, dative: true);
    if (w == 'obur' && b(i + 1) == 'gun') add(_plusDays(today, 2), 2);
    if (w == 'obur' && b(i + 1) == 'gune') {
      add(_plusDays(today, 2), 2, dative: true);
    }
    if (w == 'yarindan' && w1 == 'sonra') add(_plusDays(today, 2), 2);
    if (w == 'day' && w1 == 'after' && w2 == 'tomorrow') {
      add(_plusDays(today, 2), 3);
    }
    if (w == 'haftaya') add(_plusDays(today, 7), 1, dative: true);

    // "3 gün sonra", "iki hafta sonra", "1 ay sonra"
    final count = _count(w);
    if (count != null && w2 == 'sonra') {
      if (w1 == 'gun') add(_plusDays(today, count), 3);
      if (w1 == 'hafta') add(_plusDays(today, count * 7), 3);
      if (w1 == 'ay') add(_plusMonths(today, count), 3);
    }
    // "in 3 days", "in a week", "in 2 months"
    if (w == 'in') {
      final c = _count(w1);
      if (c != null) {
        if (w2 == 'day' || w2 == 'days') add(_plusDays(today, c), 3);
        if (w2 == 'week' || w2 == 'weeks') add(_plusDays(today, c * 7), 3);
        if (w2 == 'month' || w2 == 'months') add(_plusMonths(today, c), 3);
      }
    }

    // "gelecek hafta", "önümüzdeki hafta", "next week"
    if ((w == 'gelecek' || w == 'onumuzdeki' || w == 'next') &&
        (w1 == 'hafta' || w1 == 'week')) {
      add(_nextWeek(o.weekStart), 2);
    }
    if ((w == 'gelecek' || w == 'onumuzdeki') && b(i + 1) == 'haftaya') {
      add(_nextWeek(o.weekStart), 2, dative: true);
    }

    // The weekend: the coming Saturday, today if it is one.
    final saturday = _plusDays(
      today,
      (DateTime.saturday - today.weekday + 7) % 7,
    );
    var at = i;
    if (w == 'bu' || w == 'this') at += 1;
    if (n(at) == 'hafta' && (b(at + 1) == 'sonu' || b(at + 1) == 'sonuna')) {
      add(saturday, at - i + 2, dative: b(at + 1) == 'sonuna');
    }
    if (b(at) == 'haftasonu' || b(at) == 'haftasonuna') {
      add(saturday, at - i + 1, dative: b(at) == 'haftasonuna');
    }
    if (n(at) == 'weekend' && (at > i || keyworded || n(i) == 'weekend')) {
      add(saturday, at - i + 1);
    }

    // End of the month.
    final monthEnd = DateTime(
      today.year,
      today.month,
      awLastDayOfMonth(today.year, today.month),
    );
    if ((w == 'ay' || w == 'ayin') &&
        (b(i + 1) == 'sonu' || b(i + 1) == 'sonuna')) {
      add(monthEnd, 2, dative: b(i + 1) == 'sonuna');
    }
    if (w == 'end' && w1 == 'of') {
      if (w2 == 'month') add(monthEnd, 3);
      if (w2 == 'the' && n(i + 3) == 'month') add(monthEnd, 4);
    }
    return out;
  }

  List<_DateHit> _weekdayDates(int i, {bool keyworded = false}) {
    final out = <_DateHit>[];
    // (prefix length, mode): 0 nearest incl. today, 1 next week, 2 strictly after
    final prefixes = <(int, int)>[(0, 0)];
    final w = n(i);
    final w1 = n(i + 1);
    if (w == 'bu' || w == 'this' || w == 'on') prefixes.add((1, 0));
    if (w == 'next' || w == 'haftaya') prefixes.add((1, 1));
    if ((w == 'gelecek' || w == 'onumuzdeki') && w1 == 'hafta') {
      prefixes.add((2, 1));
    }
    if (w == 'gelecek' || w == 'onumuzdeki') prefixes.add((1, 2));
    for (final (plen, mode) in prefixes) {
      final at = i + plen;
      final hit = _weekday(at, keyworded: keyworded || plen > 0);
      if (hit == null) continue;
      final (weekday, dativeWord) = hit;
      var len = plen + 1;
      var dative = dativeWord;
      // "pazartesi günü", "cuma gününe"
      if (!dativeWord && (b(at + 1) == 'gunu' || b(at + 1) == 'gunune')) {
        dative = b(at + 1) == 'gunune';
        len += 1;
      }
      final DateTime day;
      var isToday = false;
      switch (mode) {
        case 1:
          day = _nextWeek(weekday);
        case 2:
          final delta = (weekday - today.weekday + 7) % 7;
          day = _plusDays(today, delta == 0 ? 7 : delta);
        default:
          final delta = (weekday - today.weekday + 7) % 7;
          day = _plusDays(today, delta);
          isToday = delta == 0;
      }
      out.add(_DateHit(day, len, dative: dative, weekdayToday: isToday));
    }
    return out;
  }

  // ── due / when ──

  List<_Cand> _schedule(int i) {
    final out = <_Cand>[];
    final w = n(i);
    // Explicit deadline: "son cuma", "son gün 15 kasım", "due friday".
    if (_dueKeywords.contains(w)) {
      final skip = (w == 'son' && b(i + 1) == 'gun') ? 2 : 1;
      for (final hit in _dates(i + skip, keyworded: true)) {
        var len = skip + hit.len;
        if (hit.dative && n(i + len) == 'kadar') len += 1;
        out.add(_Cand(AwQuickTokenKind.due, len, date: hit));
      }
    }
    // Explicit when: "başla pazartesi", "start mon".
    if (_whenBefore.contains(w)) {
      for (final hit in _dates(i + 1, keyworded: true)) {
        out.add(_Cand(AwQuickTokenKind.when, 1 + hit.len, date: hit));
      }
    }
    // "on Nov 15", "on 15.11" (weekdays take their "on" themselves).
    if (w == 'on') {
      for (final hit in [?_numericDate(i + 1), ..._namedDates(i + 1)]) {
        out.add(_Cand(AwQuickTokenKind.due, 1 + hit.len, date: hit));
      }
    }
    for (final hit in _dates(i)) {
      final next = n(i + hit.len);
      if (_whenAfter.contains(next)) {
        out.add(_Cand(AwQuickTokenKind.when, hit.len + 1, date: hit));
      } else if (hit.dative && next == 'kadar') {
        out.add(_Cand(AwQuickTokenKind.due, hit.len + 1, date: hit));
      } else {
        out.add(_Cand(AwQuickTokenKind.due, hit.len, date: hit));
      }
    }
    return out;
  }

  // ── time ──

  /// (hour, minute, words) for one time form at [i].
  (int, int, int)? _timeForm(
    int i, {
    bool allowBare = false,
    bool allowDot = false,
    bool allowSuffix = true,
  }) {
    final word = n(i);
    if (word.isEmpty) return null;
    final ampm = RegExp(
      r'^(\d{1,2})(?::(\d{2}))?(am|pm|a\.m|p\.m)$',
    ).firstMatch(word);
    if (ampm != null) {
      return _ampm(ampm.group(1)!, ampm.group(2), ampm.group(3)!, 1);
    }
    final m = RegExp(
      r"^(\d{1,2})(?:([:.])(\d{2}))?(?:'?(da|de|ta|te))?$",
    ).firstMatch(word);
    if (m == null) return null;
    final sep = m.group(2);
    final suffix = m.group(4);
    if (sep == '.' && !allowDot) return null;
    if (suffix != null && !allowSuffix) return null;
    // "3 pm", "3:30 pm"
    final next = n(i + 1);
    if (suffix == null &&
        sep != '.' &&
        RegExp(r'^(am|pm|a\.m|p\.m)$').hasMatch(next)) {
      return _ampm(m.group(1)!, m.group(3), next, 2);
    }
    if (sep == null && suffix == null && !allowBare) return null;
    final hour = int.parse(m.group(1)!);
    final minute = m.group(3) == null ? 0 : int.parse(m.group(3)!);
    if (hour > 23 || minute > 59) return null;
    return (hour, minute, 1);
  }

  (int, int, int)? _ampm(String h, String? mm, String marker, int len) {
    var hour = int.parse(h);
    final minute = mm == null ? 0 : int.parse(mm);
    if (hour < 1 || hour > 12 || minute > 59) return null;
    final pm = marker.startsWith('p');
    if (hour == 12) hour = 0;
    if (pm) hour += 12;
    return (hour, minute, len);
  }

  List<_Cand> _times(int i) {
    final out = <_Cand>[];
    void add(int h, int m, int len) =>
        out.add(_Cand(AwQuickTokenKind.time, len, hour: h, minute: m));
    final w = n(i);
    final w1 = n(i + 1);

    final plain = _timeForm(i);
    if (plain != null) add(plain.$1, plain.$2, plain.$3);

    if (w == 'saat') {
      final t = _timeForm(i + 1, allowBare: true, allowDot: true);
      if (t != null) add(t.$1, t.$2, 1 + t.$3);
    }
    if (w == 'at') {
      final t = _timeForm(i + 1, allowBare: true, allowSuffix: false);
      if (t != null) add(t.$1, t.$2, 1 + t.$3);
      if (w1 == 'noon') add(12, 0, 2);
      if (w1 == 'midnight') add(0, 0, 2);
    }

    // sabah / öğleden sonra / akşam / gece [saat] N
    var modLen = 0;
    String? mod;
    if (w == 'sabah' || w == 'aksam' || w == 'gece') {
      mod = w;
      modLen = 1;
    } else if (w == 'ogleden' && w1 == 'sonra') {
      mod = 'ogleden';
      modLen = 2;
    }
    if (mod != null) {
      var at = i + modLen;
      if (n(at) == 'saat') at += 1;
      final t = _timeForm(at, allowBare: true, allowDot: true);
      if (t != null) {
        var (h, m, len) = t;
        switch (mod) {
          case 'ogleden' || 'aksam':
            if (h < 12) h += 12;
          case 'gece':
            if (h >= 6 && h <= 11) h += 12;
            if (h == 12) h = 0;
        }
        add(h, m, at - i + len);
      }
    }

    // öğlen — but not "öğle yemeği" / "öğlen arası" (lunch, not 12:00).
    if ({'oglen', 'ogle', 'ogleyin', 'oglende'}.contains(b(i))) {
      if (!b(i + 1).startsWith('yemeg') && !b(i + 1).startsWith('aras')) {
        add(12, 0, 1);
      }
    }
    if (w == 'noon' || w == 'midday') add(12, 0, 1);
    if (w == 'midnight') add(0, 0, 1);
    return out;
  }

  // ── recurrence ──

  AwRepeatRule? _valid(AwRepeatRule rule) =>
      awValidateRepeatRule(rule) == null ? rule : null;

  List<_Cand> _repeats(int i) {
    final out = <_Cand>[];
    void add(AwRepeatRule rule, int len) {
      final valid = _valid(rule);
      if (valid != null) {
        out.add(_Cand(AwQuickTokenKind.repeat, len, rule: valid));
      }
    }

    const daily = AwRepeatRule(freq: AwRepeatFreq.daily);
    const weekly = AwRepeatRule(freq: AwRepeatFreq.weekly);
    const monthly = AwRepeatRule(freq: AwRepeatFreq.monthly);
    const yearly = AwRepeatRule(freq: AwRepeatFreq.yearly);
    AwRepeatRule days(List<int> weekdays) => AwRepeatRule(
      freq: AwRepeatFreq.weekly,
      byWeekday: [for (final d in weekdays) AwWeekdayPick(kAwWeekdays[d - 1])],
    );
    final weekdays = days(const [1, 2, 3, 4, 5]);
    final weekend = days(const [6, 7]);

    final w = n(i);
    final w1 = n(i + 1);
    final w2 = n(i + 2);
    final bw1 = b(i + 1);

    AwRepeatFreq? unit(String s, {required bool tr}) => switch (s) {
      'gunde' when tr => AwRepeatFreq.daily,
      'haftada' when tr => AwRepeatFreq.weekly,
      'ayda' when tr => AwRepeatFreq.monthly,
      'yilda' when tr => AwRepeatFreq.yearly,
      'day' || 'days' when !tr => AwRepeatFreq.daily,
      'week' || 'weeks' when !tr => AwRepeatFreq.weekly,
      'month' || 'months' when !tr => AwRepeatFreq.monthly,
      'year' || 'years' when !tr => AwRepeatFreq.yearly,
      _ => null,
    };

    /// "pazartesi, perşembe ve cuma" — a list of plain weekdays at [at].
    (List<int>, int)? weekdayList(int at) {
      final first = _plainWeekday(at);
      if (first == null) return null;
      final picked = <int>[first];
      var end = at + 1;
      if (b(end) == 'gunu') end += 1;
      while (true) {
        var next = end;
        if (n(next) == 've' || n(next) == 'and' || n(next) == '&') next += 1;
        final day = _plainWeekday(next);
        if (day == null) break;
        if (!picked.contains(day)) picked.add(day);
        end = next + 1;
        if (b(end) == 'gunu') end += 1;
      }
      picked.sort();
      return (picked, end - at);
    }

    // ── Turkish ──
    if (b(i) == 'hergun') add(daily, 1);
    if (w == 'her') {
      if (bw1 == 'gun') add(daily, 2);
      if (w1 == 'hafta') {
        add(weekly, 2);
        if (b(i + 2) == 'ici') add(weekdays, 3);
        if (b(i + 2) == 'sonu') add(weekend, 3);
      }
      if (w1 == 'ay') add(monthly, 2);
      if (w1 == 'yil' || w1 == 'sene') add(yearly, 2);
      if (w1 == 'ayin') {
        final dm = RegExp(r"^(\d{1,2})(?:'?[a-z]{1,6})?$").firstMatch(w2);
        if (dm != null) {
          final day = int.parse(dm.group(1)!);
          var len = 3;
          if (b(i + 3) == 'gunu') len += 1;
          add(AwRepeatRule(freq: AwRepeatFreq.monthly, byMonthDay: [day]), len);
        }
        if (w2 == 'son' && b(i + 3) == 'gunu') {
          add(
            const AwRepeatRule(freq: AwRepeatFreq.monthly, byMonthDay: [-1]),
            4,
          );
        }
      }
      final list = weekdayList(i + 1);
      if (list != null) add(days(list.$1), 1 + list.$2);
    }
    if (w == 'hafta' && b(i + 1) == 'ici' && w2 == 'her' && b(i + 3) == 'gun') {
      add(weekdays, 4);
    }
    // "[her] [N] günde/haftada/ayda/yılda bir"
    {
      var at = i;
      if (n(at) == 'her') at += 1;
      final c = _count(n(at));
      if (c != null && n(at) != 'bir') at += 1;
      final f = unit(n(at), tr: true);
      if (f != null && n(at + 1) == 'bir' && (at > i)) {
        add(AwRepeatRule(freq: f, interval: c ?? 1), at - i + 2);
      } else if (f != null &&
          n(at + 1) == 'bir' &&
          at == i &&
          f != AwRepeatFreq.daily) {
        // "haftada bir", "ayda bir" — not "günde bir" (once a day, any day).
        add(AwRepeatRule(freq: f), 2);
      }
    }
    final plural = _trWeekdayPlurals[b(i)];
    if (plural != null) add(days([plural]), 1);

    // ── English ──
    if (w == 'daily') add(daily, 1);
    if (w == 'weekly') add(weekly, 1);
    if (w == 'yearly' || w == 'annually') add(yearly, 1);
    if (w == 'monthly') {
      add(monthly, 1);
      if (w1 == 'on' && w2 == 'the') {
        final d = _dayNum(i + 3);
        if (d != null) {
          add(AwRepeatRule(freq: AwRepeatFreq.monthly, byMonthDay: [d]), 4);
        }
      }
    }
    if (w == 'every') {
      final f1 = unit(w1, tr: false);
      if (f1 != null && !w1.endsWith('s')) {
        add(AwRepeatRule(freq: f1), 2);
        if (f1 == AwRepeatFreq.monthly && w2 == 'on' && n(i + 3) == 'the') {
          final d = _dayNum(i + 4);
          if (d != null) {
            add(AwRepeatRule(freq: AwRepeatFreq.monthly, byMonthDay: [d]), 5);
          }
        }
      }
      final c = w1 == 'other' ? 2 : _count(w1);
      final f2 = unit(w2, tr: false);
      if (c != null && f2 != null && w1 != 'a') {
        add(AwRepeatRule(freq: f2, interval: c), 3);
      }
      if (w1 == 'weekday') add(weekdays, 2);
      if (w1 == 'weekend') add(weekend, 2);
      // "every 15th [of the month]"
      final nth = RegExp(r'^\d{1,2}(st|nd|rd|th)$').hasMatch(w1)
          ? _dayNum(i + 1)
          : null;
      if (nth != null) {
        final d = nth;
        var len = 2;
        if (w2 == 'of' && n(i + 3) == 'the' && n(i + 4) == 'month') len = 5;
        if (w2 == 'of' && n(i + 3) == 'month') len = 4;
        add(AwRepeatRule(freq: AwRepeatFreq.monthly, byMonthDay: [d]), len);
      }
      if (w1 == 'last' &&
          w2 == 'day' &&
          n(i + 3) == 'of' &&
          n(i + 4) == 'the' &&
          n(i + 5) == 'month') {
        add(
          const AwRepeatRule(freq: AwRepeatFreq.monthly, byMonthDay: [-1]),
          6,
        );
      }
      final list = weekdayList(i + 1);
      if (list != null) add(days(list.$1), 1 + list.$2);
    }
    // "mondays", "on fridays"
    {
      var at = i;
      if (w == 'on') at += 1;
      final word = n(at);
      // Full names only: "thurs" is one Thursday, "thursdays" is every.
      if (word.endsWith('days')) {
        final day = _enWeekdays[word.substring(0, word.length - 1)];
        if (day != null) add(days([day]), at - i + 1);
      }
    }
    return out;
  }

  // ── tags, project, priority ──

  List<_Cand> _marks(int i) {
    final out = <_Cand>[];
    final raw = _unifyApostrophes(
      words[i].raw,
    ).replaceFirst(_trailingPunct, '');
    final tag = RegExp(r'^#([\p{L}\p{N}_\-]+)$', unicode: true).firstMatch(raw);
    if (tag != null &&
        RegExp(r'\p{L}', unicode: true).hasMatch(tag.group(1)!)) {
      out.add(_Cand(AwQuickTokenKind.tag, 1, tag: tag.group(1)));
    }
    final priority = _priorityWords[n(i)];
    if (priority != null) {
      out.add(_Cand(AwQuickTokenKind.priority, 1, priority: priority));
    }
    if (o.parseProject && raw.startsWith('+') && raw.length > 1) {
      final folded = <String>[];
      for (final p in o.projects) {
        folded.add(foldSearchText(p.name));
      }
      // The longest run of words (up to 4) that IS a project name.
      final parts = <String>[n(i).substring(1)];
      for (var k = 1; k < 4 && i + k < words.length; k++) {
        parts.add(n(i + k));
      }
      var matched = false;
      for (var len = parts.length; len >= 1; len--) {
        final name = parts.take(len).join(' ');
        final hits = [
          for (var p = 0; p < o.projects.length; p++)
            if (folded[p] == name) o.projects[p],
        ];
        if (hits.length == 1) {
          out.add(_Cand(AwQuickTokenKind.project, len, project: hits.single));
          matched = true;
          break;
        }
      }
      if (!matched && parts.first.isNotEmpty) {
        final hits = [
          for (var p = 0; p < o.projects.length; p++)
            if (folded[p].startsWith(parts.first)) o.projects[p],
        ];
        if (hits.length == 1) {
          out.add(_Cand(AwQuickTokenKind.project, 1, project: hits.single));
        }
      }
    }
    return out;
  }

  // ── the walk ──

  AwQuickParse run() {
    final consumed = List<AwQuickTokenKind?>.filled(words.length, null);
    final tokens = <(AwQuickToken, _Cand, int)>[]; // token, cand, first word
    final filled = <AwQuickTokenKind>{};

    String keyOf(AwQuickTokenKind kind, int from, int len) {
      final src = _unifyApostrophes(
        text.substring(words[from].start, words[from + len - 1].end),
      );
      return '${kind.name}:${foldSearchText(src)}';
    }

    var i = 0;
    while (i < words.length) {
      final cands =
          <_Cand>[
            ..._repeats(i),
            ..._schedule(i),
            ..._times(i),
            ..._marks(i),
          ].where((c) {
            if (i + c.len > words.length) return false;
            if (c.kind != AwQuickTokenKind.tag && filled.contains(c.kind)) {
              return false;
            }
            return true;
          }).toList();
      if (cands.isEmpty) {
        i += 1;
        continue;
      }
      // Longest first; ties keep the order above (repeat, schedule, time…).
      var best = cands.first;
      for (final c in cands) {
        if (c.len > best.len) best = c;
      }
      final key = keyOf(best.kind, i, best.len);
      if (o.ignored.contains(key)) {
        // Dismissed: its words stay text, and nothing else may take them.
        i += best.len;
        continue;
      }
      final start = words[i].start;
      final end = words[i + best.len - 1].end;
      tokens.add((
        AwQuickToken(
          kind: best.kind,
          start: start,
          end: end,
          key: key,
          text: text.substring(start, end),
        ),
        best,
        i,
      ));
      for (var k = i; k < i + best.len; k++) {
        consumed[k] = best.kind;
      }
      if (best.kind != AwQuickTokenKind.tag) filled.add(best.kind);
      i += best.len;
    }

    // A time next to a "when" (and not next to a deadline) is not ours: a
    // when-day has no time (ADR-0053), so the words go back to the title.
    final when = tokens.where((t) => t.$1.kind == AwQuickTokenKind.when);
    final due = tokens.where((t) => t.$1.kind == AwQuickTokenKind.due);
    bool adjacent((AwQuickToken, _Cand, int) a, (AwQuickToken, _Cand, int) b) =>
        a.$3 + a.$2.len == b.$3 || b.$3 + b.$2.len == a.$3;
    tokens.removeWhere((t) {
      if (t.$1.kind != AwQuickTokenKind.time) return false;
      final nearWhen = when.any((w) => adjacent(t, w));
      final nearDue = due.any((d) => adjacent(t, d));
      if (nearWhen && !nearDue) {
        for (var k = t.$3; k < t.$3 + t.$2.len; k++) {
          consumed[k] = null;
        }
        return true;
      }
      return false;
    });

    _Cand? of(AwQuickTokenKind kind) {
      for (final t in tokens) {
        if (t.$1.kind == kind) return t.$2;
      }
      return null;
    }

    AwQuickToken? tokenOf(AwQuickTokenKind kind) {
      for (final t in tokens) {
        if (t.$1.kind == kind) return t.$1;
      }
      return null;
    }

    final dueCand = of(AwQuickTokenKind.due);
    final whenCand = of(AwQuickTokenKind.when);
    final timeCand = of(AwQuickTokenKind.time);
    final repeatCand = of(AwQuickTokenKind.repeat);

    final hour = timeCand?.hour ?? o.defaultHour;
    final minute = timeCand?.minute ?? o.defaultMinute;
    DateTime at(DateTime day) =>
        DateTime(day.year, day.month, day.day, hour, minute);

    DateTime? dueAt;
    final rule = repeatCand?.rule;
    if (rule != null) {
      final anchor = dueCand?.date?.day ?? today;
      final days = awExpandOccurrences(rule, anchor: awDayKey(anchor), max: 3);
      for (final key in days) {
        final p = key.split('-').map(int.parse).toList();
        final candidate = at(DateTime(p[0], p[1], p[2]));
        if (candidate.isAfter(o.now)) {
          dueAt = candidate;
          break;
        }
      }
      dueAt ??= at(anchor);
    } else if (dueCand != null) {
      dueAt = at(dueCand.date!.day);
      if (timeCand != null &&
          dueCand.date!.weekdayToday &&
          !dueAt.isAfter(o.now)) {
        dueAt = at(_plusDays(dueCand.date!.day, 7));
      }
    } else if (timeCand != null) {
      dueAt = at(today);
      if (!dueAt.isAfter(o.now)) dueAt = at(_plusDays(today, 1));
    }

    // Chips: the time rides on the deadline's chip, else on the repeat's,
    // else it is the deadline itself.
    final chips = <AwQuickChip>[];
    final timeToken = tokenOf(AwQuickTokenKind.time);
    final dueToken = tokenOf(AwQuickTokenKind.due);
    final repeatToken = tokenOf(AwQuickTokenKind.repeat);
    if (dueToken != null) {
      chips.add(
        AwQuickChip(kind: AwQuickTokenKind.due, tokens: [dueToken, ?timeToken]),
      );
    } else if (timeToken != null && repeatToken == null) {
      chips.add(AwQuickChip(kind: AwQuickTokenKind.due, tokens: [timeToken]));
    }
    for (final (token, _, _) in tokens) {
      switch (token.kind) {
        case AwQuickTokenKind.due || AwQuickTokenKind.time:
          break;
        case AwQuickTokenKind.repeat:
          chips.add(
            AwQuickChip(
              kind: AwQuickTokenKind.repeat,
              tokens: [token, if (dueToken == null) ?timeToken],
            ),
          );
        default:
          chips.add(AwQuickChip(kind: token.kind, tokens: [token]));
      }
    }

    final tagNames = <String>[];
    final seenTags = <String>{};
    for (final (_, cand, _) in tokens) {
      if (cand.kind == AwQuickTokenKind.tag &&
          seenTags.add(foldSearchText(cand.tag!))) {
        tagNames.add(cand.tag!);
      }
    }

    var title = [
      for (var k = 0; k < words.length; k++)
        if (consumed[k] == null) words[k].raw,
    ].join(' ');
    title = title
        .replaceFirst(RegExp(r'^[\s,;:\-–—]+'), '')
        .replaceFirst(RegExp(r'[\s,;:\-–—]+$'), '');
    if (title.isEmpty) title = text.trim().replaceAll(RegExp(r'\s+'), ' ');

    final whenDay = whenCand?.date?.day;
    return AwQuickParse(
      title: title,
      tokens: [for (final t in tokens) t.$1],
      chips: chips,
      dueAt: dueAt,
      dueHasTime: dueAt != null && timeCand != null,
      whenDay: whenDay,
      repeat: rule,
      tagNames: tagNames,
      project: of(AwQuickTokenKind.project)?.project,
      priority: of(AwQuickTokenKind.priority)?.priority,
    );
  }
}

/// Parse [text] (see the library doc for the grammar).
AwQuickParse awParseQuickAdd(String text, AwQuickParseOptions options) =>
    _Parser(text, options).run();
