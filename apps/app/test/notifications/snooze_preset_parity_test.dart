import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/tasks/data/task_store.dart';

/// OPH-424 — the Dart half of the snooze-preset pair (NOTIFICATIONS.md §2b.3,
/// "Native snooze" step 2). Dart is the fixture's author:
/// `UPDATE_FIXTURES=1 flutter test` writes
/// `test/fixtures/snooze_preset_cases.json`; every other run compares byte for
/// byte, and the Swift tests only read it.
///
/// Times are zone-free local wall-clock values (`YYYY-MM-DDTHH:MM:SS`). No case
/// sits on a DST change, so an offset preset reads the same as wall-clock
/// arithmetic and as instant arithmetic.
const _fixturePath = 'test/fixtures/snooze_preset_cases.json';

const List<(String, String, String)> _cases = [
  ('5 minutes', '5_min', '2026-07-15T12:00:00'),
  ('5 minutes keeps the seconds', '5_min', '2026-07-15T12:00:30'),
  ('5 minutes across midnight and a month end', '5_min', '2026-01-31T23:58:00'),
  ('30 minutes', '30_min', '2026-07-15T12:00:00'),
  ('30 minutes across midnight', '30_min', '2026-08-31T23:45:10'),
  ('1 hour', '1_hour', '2026-07-15T12:00:00'),
  ('1 hour across a year end', '1_hour', '2026-12-31T23:30:00'),
  (
    'tomorrow morning, pressed before 09:00',
    'tomorrow_morning',
    '2026-07-15T07:00:00',
  ),
  (
    'tomorrow morning, pressed one second before 09:00',
    'tomorrow_morning',
    '2026-07-15T08:59:59',
  ),
  (
    'tomorrow morning, pressed at 09:00',
    'tomorrow_morning',
    '2026-07-15T09:00:00',
  ),
  (
    'tomorrow morning, pressed after 09:00',
    'tomorrow_morning',
    '2026-07-15T21:15:42',
  ),
  (
    'tomorrow morning, just after midnight',
    'tomorrow_morning',
    '2026-07-16T00:00:01',
  ),
  (
    'tomorrow morning across a month end',
    'tomorrow_morning',
    '2026-01-31T22:00:00',
  ),
  (
    'tomorrow morning across a 30-day month end',
    'tomorrow_morning',
    '2026-06-30T08:00:00',
  ),
  (
    'tomorrow morning across a year end',
    'tomorrow_morning',
    '2026-12-31T23:59:59',
  ),
  (
    'tomorrow morning onto a leap day',
    'tomorrow_morning',
    '2028-02-28T10:00:00',
  ),
  (
    'tomorrow morning off a leap day',
    'tomorrow_morning',
    '2028-02-29T10:00:00',
  ),
];

String _two(int v) => v.toString().padLeft(2, '0');

String _wall(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-${_two(t.month)}-${_two(t.day)}'
    'T${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';

/// A zone-free wall-clock string as a UTC DateTime: a container for the
/// fields that no DST rule of the machine running the test can move.
DateTime _fields(String wall) => DateTime.parse('${wall}Z');

String _render() =>
    '${const JsonEncoder.withIndent('  ').convert({
      'contract': 'NOTIFICATIONS.md 2b.3 Native snooze, step 2',
      'note': 'Written by the Dart test (UPDATE_FIXTURES=1); every other reader only compares. Zone-free local wall-clock times; the target is then floored to the second.',
      'cases': [
        for (final (name, preset, now) in _cases) {'name': name, 'preset': preset, 'nowWall': now, 'untilWall': _wall(snoozeUntilWallClock(preset, _fields(now)))},
      ],
    })}\n';

void main() {
  test('snoozeUntilFor matches snooze_preset_cases.json', () {
    final file = File(_fixturePath);
    final rendered = _render();
    if (Platform.environment['UPDATE_FIXTURES'] == '1') {
      file.writeAsStringSync(rendered);
    }
    expect(file.existsSync(), isTrue, reason: 'run with UPDATE_FIXTURES=1');
    final cases =
        ((jsonDecode(file.readAsStringSync()) as Map)['cases'] as List)
            .cast<Map<String, dynamic>>();
    final presets = {for (final c in cases) c['preset']};
    expect(presets, {'5_min', '30_min', '1_hour', 'tomorrow_morning'});

    for (final c in cases) {
      final preset = c['preset'] as String;
      final now = _fields(c['nowWall'] as String);
      final reason = c['name'] as String;
      // The pure wall-clock rule …
      expect(
        _wall(snoozeUntilWallClock(preset, now)),
        c['untilWall'],
        reason: reason,
      );
      // … and the store's entry point, fed a real local "now".
      final localNow = DateTime(
        now.year,
        now.month,
        now.day,
        now.hour,
        now.minute,
        now.second,
      );
      expect(
        _wall(TaskStore.snoozeUntilFor(preset, now: localNow).toLocal()),
        c['untilWall'],
        reason: '$reason (TaskStore.snoozeUntilFor)',
      );
    }
    expect(file.readAsStringSync(), rendered);
  });

  test('tomorrow_morning is 09:00 on the next calendar day, never today', () {
    final early = snoozeUntilWallClock(
      'tomorrow_morning',
      DateTime.utc(2026, 7, 15, 7),
    );
    expect(early, DateTime.utc(2026, 7, 16, 9));
    expect(
      () => snoozeUntilWallClock('never', DateTime.utc(2026)),
      throwsArgumentError,
    );
  });
}
