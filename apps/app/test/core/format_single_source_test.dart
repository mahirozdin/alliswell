import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// OPH-408 (U-09): one formatter. Seven date shapes and three number shapes
/// reached the product because every screen could call `intl` on its own.
/// This scan keeps the figures in `core/format.dart` / `core/date_format.dart`:
/// a new `NumberFormat`, `DateFormat`, `toStringAsFixed` or hand-built "MB" in
/// `lib/` fails here, and the fix is an `awFormat*` call.
void main() {
  // Files that may touch `intl` directly, each for a reason that is not a
  // figure the reader compares: the formatter itself, and NAMES (a month's,
  // a weekday's) that have no order or separator to get wrong.
  const intlAllowed = {
    'lib/src/core/format.dart',
    'lib/src/core/format_region.dart',
    'lib/src/core/date_format.dart',
    // "Kasım 2026" over the grid and the weekday initials.
    'lib/src/features/home/month_calendar.dart',
    // "every March" — a month's name inside a recurrence sentence.
    'lib/src/core/recurrence_text.dart',
    // The home-screen widget's header words (weekday, day, month name).
    'lib/src/features/widgets/widget_snapshot.dart',
  };
  // A persisted key, not a figure anyone reads.
  const fixedAllowed = {'lib/src/features/quick_access/ui/bubble_physics.dart'};

  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'));

  test('no screen formats a date or a number on its own', () {
    final offenders = <String>[];
    final intlCall = RegExp(r'\b(NumberFormat|DateFormat)\s*[.(]');
    final fixed = RegExp(r'\.toStringAsFixed\(');
    final unit = RegExp(r'''[ '"](KB|MB|GB)['"]''');
    for (final file in files) {
      final path = file.path.replaceAll(r'\', '/');
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) continue;
        if (intlCall.hasMatch(line) && !intlAllowed.contains(path)) {
          offenders.add('$path:${i + 1}  $line');
        }
        if (fixed.hasMatch(line) && !fixedAllowed.contains(path)) {
          offenders.add('$path:${i + 1}  $line');
        }
        if (unit.hasMatch(line) && !path.startsWith('lib/src/core/format')) {
          offenders.add('$path:${i + 1}  $line');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'use awFormat* from core/format.dart:\n${offenders.join('\n')}',
    );
  });
}
