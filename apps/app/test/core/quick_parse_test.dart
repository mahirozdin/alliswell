import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/core/quick_parse.dart';
import 'package:alliswell/src/core/recurrence.dart';

/// OPH-373 (ADR-0054): the offline quick-add grammar. The JSON fixture is the
/// contract (and the seed of any future JS twin); the groups below pin what a
/// fixture row cannot say — offsets, chips, dismissals, the remainder rules.
///
/// Every assertion compares WALL components, so the suite passes in any
/// machine timezone.
void main() {
  final fixture =
      jsonDecode(
            File('test/fixtures/quick_parse_cases.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  final defaults = fixture['defaults'] as Map<String, dynamic>;

  DateTime local(String text) {
    final m = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})(?:T(\d{2}):(\d{2}))?$',
    ).firstMatch(text)!;
    int g(int i) => int.parse(m.group(i) ?? '0');
    return DateTime(g(1), g(2), g(3), g(4), g(5));
  }

  String wall(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}T'
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';

  String day(DateTime d) => wall(d).substring(0, 10);

  List<AwQuickProject> projects(Object? list) => [
    for (final p in (list as List))
      AwQuickProject(id: (p as Map)['id'] as String, name: p['name'] as String),
  ];

  AwQuickParseOptions optionsFor(Map<String, dynamic> c) {
    final o = (c['options'] as Map<String, dynamic>?) ?? const {};
    final time = ((o['defaultTime'] as String?) ?? '23:59').split(':');
    return AwQuickParseOptions(
      now: local((c['now'] as String?) ?? defaults['now'] as String),
      weekStart: (o['weekStart'] as int?) ?? DateTime.monday,
      defaultHour: int.parse(time[0]),
      defaultMinute: int.parse(time[1]),
      monthFirstSlash: (o['monthFirstSlash'] as bool?) ?? false,
      projects: projects(o['projects'] ?? defaults['projects']),
      parseProject: (o['parseProject'] as bool?) ?? true,
      ignored: {...((o['ignored'] as List?) ?? const []).cast<String>()},
    );
  }

  group('fixture', () {
    final cases = (fixture['cases'] as List).cast<Map<String, dynamic>>();
    test('carries the contract (120+ cases)', () {
      expect(cases.length, greaterThanOrEqualTo(120));
    });
    for (final c in cases) {
      final text = c['text'] as String;
      final e = c['expect'] as Map<String, dynamic>;
      final options = c['options'] == null
          ? ''
          : ' ${jsonEncode(c['options'])}';
      final now = c['now'] == null ? '' : ' @${c['now']}';
      test('[${c['group']}] "$text"$now$options', () {
        final p = awParseQuickAdd(text, optionsFor(c));
        expect(p.title, e['title'], reason: 'title');
        expect(
          p.dueAt == null ? null : wall(p.dueAt!),
          e['due'],
          reason: 'due',
        );
        expect(
          p.whenDay == null ? null : day(p.whenDay!),
          e['when'],
          reason: 'when',
        );
        if (p.whenDay != null) {
          expect(p.whenDay!.hour + p.whenDay!.minute, 0, reason: 'midnight');
        }
        expect(p.repeat?.toJson(), e['repeat'], reason: 'repeat');
        expect(p.tagNames, e['tags'], reason: 'tags');
        expect(p.project?.id, e['project'], reason: 'project');
        expect(p.priority, e['priority'], reason: 'priority');
        if (e.containsKey('kinds')) {
          expect(
            [for (final t in p.tokens) t.kind.name],
            e['kinds'],
            reason: 'kinds',
          );
        }
        if (e.containsKey('dueHasTime')) {
          expect(p.dueHasTime, e['dueHasTime'], reason: 'dueHasTime');
        }
        // Every repeat rule the parser emits is one the engine accepts.
        if (p.repeat != null) expect(awValidateRepeatRule(p.repeat!), isNull);
      });
    }
  });

  final friday = DateTime(2026, 10, 16, 10);
  AwQuickParse parse(
    String text, {
    DateTime? now,
    Set<String> ignored = const {},
    List<AwQuickProject> projects = const [],
  }) => awParseQuickAdd(
    text,
    AwQuickParseOptions(
      now: now ?? friday,
      ignored: ignored,
      projects: projects,
    ),
  );

  group('tokens', () {
    test('offsets cover the exact source substrings', () {
      const text = "Yarın  9'da kira #ev p1 her ayın 31'i";
      final p = parse(text);
      for (final t in p.tokens) {
        expect(text.substring(t.start, t.end), t.text);
      }
      expect(
        [for (final t in p.tokens) t.text],
        ['Yarın', "9'da", '#ev', 'p1', "her ayın 31'i"],
      );
    });

    test('keys are kind plus the folded source', () {
      final p = parse("Yarın 9’da kira #Ev");
      expect(
        [for (final t in p.tokens) t.key],
        ['due:yarin', "time:9'da", 'tag:#ev'],
      );
    });

    test('a deadline and its time are one chip', () {
      final p = parse("Yarın 9'da kira #ev p1");
      expect(
        [for (final c in p.chips) c.kind.name],
        ['due', 'tag', 'priority'],
      );
      expect(p.chips.first.keys, ['due:yarin', "time:9'da"]);
    });

    test('a time alone is the deadline chip', () {
      final p = parse("9'da kahvaltı");
      expect(p.chips.single.kind, AwQuickTokenKind.due);
      expect(p.chips.single.keys, ["time:9'da"]);
    });

    test('a time with a repeat rides on the repeat chip', () {
      final p = parse("her pazartesi 9'da spor");
      expect(p.chips.single.kind, AwQuickTokenKind.repeat);
      expect(p.chips.single.keys, ["repeat:her pazartesi", "time:9'da"]);
    });

    test('a time next to a when-day stays in the title', () {
      final p = parse("başla pazartesi 9'da rapor");
      expect(p.title, "9'da rapor");
      expect(p.dueAt, isNull);
      expect([for (final t in p.tokens) t.kind], [AwQuickTokenKind.when]);
    });
  });

  group('undo', () {
    test('dismissing the deadline chip gives every word back', () {
      final first = parse("Yarın 9'da kira");
      final again = parse(
        "Yarın 9'da kira",
        ignored: {...first.chips.first.keys},
      );
      expect(again.title, "Yarın 9'da kira");
      expect(again.dueAt, isNull);
      expect(again.chips, isEmpty);
    });

    test('a dismissed phrase lets a later one fill the slot', () {
      final p = parse('yarın kira cuma', ignored: {'due:yarin'});
      expect(p.title, 'yarın kira');
      expect(day(p.dueAt!), '2026-10-16');
    });

    test('dismissing one tag keeps the others', () {
      final p = parse('#ev #iş x', ignored: {'tag:#ev'});
      expect(p.tagNames, ['iş']);
      expect(p.title, '#ev x');
    });
  });

  group('remainder', () {
    test('nothing left → the whole text is the title, fields still apply', () {
      final p = parse("yarın 9'da");
      expect(p.title, "yarın 9'da");
      expect(wall(p.dueAt!), '2026-10-17T09:00');
    });

    test('the title keeps the original casing and drops dangling commas', () {
      expect(parse('Kira Öde, yarın').title, 'Kira Öde');
    });

    test('an empty text parses to nothing', () {
      final p = parse('   ');
      expect(p.tokens, isEmpty);
      expect(p.hasSchedule, isFalse);
    });
  });

  group('calendar edges', () {
    test('a weekday includes today until its time has passed', () {
      expect(wall(parse("cuma 11'de x").dueAt!), '2026-10-16T11:00');
      expect(wall(parse("cuma 9'da x").dueAt!), '2026-10-23T09:00');
      expect(wall(parse('cuma x').dueAt!), '2026-10-16T23:59');
    });

    test('a passed date without a year rolls to next year', () {
      expect(day(parse('10 ekim x').dueAt!), '2027-10-10');
      expect(
        day(parse('15 ocak x', now: DateTime(2026, 12, 20)).dueAt!),
        '2027-01-15',
      );
    });

    test('invalid days are not recognized', () {
      expect(parse('31.02 x').dueAt, isNull);
      expect(parse('29 şubat x').dueAt, isNull);
      expect(day(parse('29.02.2028 x').dueAt!), '2028-02-29');
    });

    test('month arithmetic clamps to the month end', () {
      final p = parse('1 ay sonra x', now: DateTime(2026, 1, 31, 9));
      expect(day(p.dueAt!), '2026-02-28');
    });

    test('a repeat is never born overdue', () {
      // Monday 10:00: "every Monday at 9" starts NEXT Monday.
      final p = parse("her pazartesi 9'da", now: DateTime(2026, 10, 19, 10));
      expect(wall(p.dueAt!), '2026-10-26T09:00');
    });

    test('week start moves "next week"', () {
      final sunday = awParseQuickAdd(
        'next week x',
        AwQuickParseOptions(now: friday, weekStart: DateTime.sunday),
      );
      expect(day(sunday.dueAt!), '2026-10-18');
      expect(day(parse('next week x').dueAt!), '2026-10-19');
    });
  });

  group('project', () {
    const projects = [
      AwQuickProject(id: 'a', name: 'Ev İşleri'),
      AwQuickProject(id: 'b', name: 'Ev Tadilatı'),
      AwQuickProject(id: 'c', name: 'Work'),
    ];
    test('an ambiguous prefix is not a match', () {
      final p = parse('+ev bulaşık', projects: projects);
      expect(p.project, isNull);
      expect(p.title, '+ev bulaşık');
    });
    test('the longest exact multi-word name wins', () {
      final p = parse('+ev tadilatı boya', projects: projects);
      expect(p.project?.id, 'b');
      expect(p.title, 'boya');
    });
  });
}
