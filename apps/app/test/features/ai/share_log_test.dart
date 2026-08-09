import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/ai/data/share_log.dart';
import 'package:alliswell/src/sync/db/database.dart';

/// OPH-242 — the share pipeline's diagnostic trail. Round 17 opened with a
/// report nothing could confirm or deny ("I shared a text and nothing
/// happened"); this log is what makes the next one measurable.
///
/// Two properties matter more than the rest and both are asserted here: the log
/// **never stores content**, and it **never grows without bound**.
void main() {
  late AwDatabase db;
  late ShareLog log;

  setUp(() {
    db = AwDatabase(DatabaseConnection(NativeDatabase.memory()));
    log = ShareLog(db);
  });

  tearDown(() => db.close());

  test(
    'records an arrival with its shape and size, never its content',
    () async {
      await log.record(
        event: ShareLogEvent.warmShare,
        payloadKind: ShareLogKind.url,
        bytes: 128,
      );

      final rows = await log.recent();
      expect(rows, hasLength(1));
      expect(rows.single.event, ShareLogEvent.warmShare);
      expect(rows.single.payloadKind, ShareLogKind.url);
      expect(rows.single.bytes, 128);

      // The table has nowhere to PUT content — this asserts the shape of the
      // row, which is the actual privacy guarantee.
      expect(rows.single.toJson().keys, <String>{
        'id',
        'at',
        'event',
        'payloadKind',
        'bytes',
        'detail',
      });
    },
  );

  test('newest first', () async {
    final base = DateTime.utc(2026, 8, 9, 10);
    await log.record(event: ShareLogEvent.initialShare, at: base);
    await log.record(
      event: ShareLogEvent.warmShare,
      at: base.add(const Duration(minutes: 5)),
    );

    final rows = await log.recent();
    expect(rows.map((r) => r.event), [
      ShareLogEvent.warmShare,
      ShareLogEvent.initialShare,
    ]);
  });

  test('is a ring buffer: the oldest rows fall off at the limit', () async {
    final base = DateTime.utc(2026, 8, 9);
    for (var i = 0; i < kShareLogLimit + 10; i++) {
      await log.record(
        event: ShareLogEvent.warmShare,
        bytes: i,
        at: base.add(Duration(minutes: i)),
      );
    }

    final rows = await log.recent(limit: kShareLogLimit + 50);
    expect(rows, hasLength(kShareLogLimit));
    // The newest survived; row 0 (the oldest) did not.
    expect(rows.first.bytes, kShareLogLimit + 9);
    expect(rows.map((r) => r.bytes), isNot(contains(0)));
  });

  test(
    'never throws — a broken diagnostic must not break the pipeline',
    () async {
      await db.close(); // every write from here on fails
      await expectLater(log.record(event: ShareLogEvent.warmShare), completes);
      // Re-open so tearDown's close() is harmless.
      db = AwDatabase(DatabaseConnection(NativeDatabase.memory()));
    },
  );

  test('formats one copy-pasteable line per row', () async {
    await log.record(
      event: ShareLogEvent.readFailed,
      payloadKind: ShareLogKind.markdown,
      detail: 'PathAccessException',
      at: DateTime.utc(2026, 8, 9, 14, 30),
    );

    final line = formatShareLogLine((await log.recent()).single);
    expect(line, contains('2026-08-09T14:30:00.000Z'));
    expect(line, contains(ShareLogEvent.readFailed));
    expect(line, contains('PathAccessException'));
    expect(line, contains(' · '));
  });
}
