import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/sync/db/database.dart';

/// OPH-421 (#49) — the device-local ledger that makes an alarm action apply
/// exactly once (NOTIFICATIONS §2b.3). A native action stays in its queue until
/// Dart acks it after the commit, so a crash between the two redelivers it;
/// the receipt, written in the same transaction as the model change, is what
/// turns that second delivery into a no-op.
void main() {
  late AwDatabase db;

  setUp(() {
    db = AwDatabase(DatabaseConnection(NativeDatabase.memory()));
  });

  tearDown(() async {
    await db.close();
  });

  final pressedAt = DateTime.utc(2026, 11, 12, 9, 0, 0, 250);

  test(
    'insertReceiptIfAbsent is true once and false on the second delivery',
    () async {
      expect(
        await db.insertReceiptIfAbsent(
          eventId: 'E-1',
          action: 'snooze',
          appliedAt: pressedAt,
        ),
        isTrue,
      );
      // The same event again — a redelivery after a crash before the ack.
      expect(
        await db.insertReceiptIfAbsent(
          eventId: 'E-1',
          action: 'snooze',
          appliedAt: pressedAt.add(const Duration(minutes: 1)),
        ),
        isFalse,
      );
      // Another event is its own receipt.
      expect(
        await db.insertReceiptIfAbsent(
          eventId: 'E-2',
          action: 'stop',
          appliedAt: pressedAt,
        ),
        isTrue,
      );

      final rows = await (db.select(
        db.actionReceipts,
      )..orderBy([(r) => OrderingTerm.asc(r.eventId)])).get();
      expect(rows.map((r) => r.eventId), ['E-1', 'E-2']);
      // The first delivery's row stands; the second changed nothing.
      expect(rows.first.action, 'snooze');
      expect(rows.first.appliedAt, pressedAt.millisecondsSinceEpoch);

      // Stored as UTC epoch milliseconds, the contract's INTEGER.
      final raw = await db
          .customSelect(
            "SELECT applied_at FROM action_receipts WHERE event_id = 'E-1'",
          )
          .getSingle();
      expect(raw.data['applied_at'], pressedAt.millisecondsSinceEpoch);
    },
  );

  test(
    'insertReceiptIfAbsent rolls back with its surrounding transaction',
    () async {
      // The model write after the receipt fails: the receipt must go with it,
      // or the redelivered action would be skipped and never applied.
      await expectLater(
        db.transaction(() async {
          expect(
            await db.insertReceiptIfAbsent(
              eventId: 'E-1',
              action: 'snooze',
              appliedAt: pressedAt,
            ),
            isTrue,
          );
          throw StateError('model write failed');
        }),
        throwsStateError,
      );
      expect(await db.select(db.actionReceipts).get(), isEmpty);

      // The redelivery applies, inside a transaction that commits.
      final applied = await db.transaction(
        () => db.insertReceiptIfAbsent(
          eventId: 'E-1',
          action: 'snooze',
          appliedAt: pressedAt,
        ),
      );
      expect(applied, isTrue);
      final again = await db.transaction(
        () => db.insertReceiptIfAbsent(
          eventId: 'E-1',
          action: 'snooze',
          appliedAt: pressedAt,
        ),
      );
      expect(again, isFalse);
    },
  );

  test('pruneActionReceipts drops only rows older than the cutoff', () async {
    final cutoff = DateTime.utc(2026, 10, 13);
    await db.insertReceiptIfAbsent(
      eventId: 'old',
      action: 'stop',
      appliedAt: cutoff.subtract(const Duration(milliseconds: 1)),
    );
    await db.insertReceiptIfAbsent(
      eventId: 'edge',
      action: 'snooze',
      appliedAt: cutoff,
    );
    await db.insertReceiptIfAbsent(
      eventId: 'new',
      action: 'complete',
      appliedAt: cutoff.add(const Duration(days: 29)),
    );

    // A local cutoff is the same instant as its UTC twin.
    expect(await db.pruneActionReceipts(olderThan: cutoff.toLocal()), 1);

    final left = await (db.select(
      db.actionReceipts,
    )..orderBy([(r) => OrderingTerm.asc(r.eventId)])).get();
    expect(left.map((r) => r.eventId), ['edge', 'new']);
    // Nothing older is left, so a second prune is a no-op.
    expect(await db.pruneActionReceipts(olderThan: cutoff), 0);
  });
}
