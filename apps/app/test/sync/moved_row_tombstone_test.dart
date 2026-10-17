import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/sync_api.dart';
import 'package:alliswell/src/sync/sync_applier.dart';

/// OPH-378 — a row the server moved to another workspace is deleted in the
/// stream it left and created in the one it landed in. A device that belongs
/// to both may pull the NEW stream first; the old stream's tombstone that
/// arrives afterwards must not take the row it now holds for the new one.
const wsA = '01WSAAAAAAAAAAAAAAAAAAAAAA';
const wsB = '01WSBBBBBBBBBBBBBBBBBBBBBB';
String id(String prefix) => prefix.padRight(26, '0');

void main() {
  late AwDatabase db;

  setUp(() {
    db = AwDatabase(DatabaseConnection(NativeDatabase.memory()));
  });

  tearDown(() => db.close());

  SyncChange upsert(String type, Map<String, dynamic> data) => SyncChange(
    revision: 1,
    entityType: type,
    entityId: data['id'] as String,
    operation: 'create',
    data: data,
  );

  SyncChange tombstone(String type, String entityId) => SyncChange(
    revision: 2,
    entityType: type,
    entityId: entityId,
    operation: 'delete',
  );

  Future<void> pulled(String ws, List<SyncChange> changes) =>
      applyPulledChanges(db, workspaceId: ws, changes: changes, toRevision: 2);

  /// The request as the workspace it moved INTO delivers it.
  Future<void> holdMovedRequest() => pulled(wsB, [
    upsert('ee_ticket', {
      'id': id('T1'),
      'workspaceId': wsB,
      'serviceId': null,
      'requesterId': null,
      'subject': 'Pano',
      'body': null,
      'status': 'open',
      'priority': 'normal',
      'source': 'internal',
      'terminalAt': null,
      'revision': 1,
      'createdAt': '2026-10-01T08:00:00.000Z',
      'updatedAt': '2026-10-01T08:00:00.000Z',
    }),
    upsert('ee_ticket_comment', {
      'id': id('C1'),
      'workspaceId': wsB,
      'ticketId': id('T1'),
      'authorId': null,
      'body': 'not',
      'internal': true,
      'revision': 1,
      'createdAt': '2026-10-01T09:00:00.000Z',
      'updatedAt': '2026-10-01T09:00:00.000Z',
    }),
    upsert('ee_ticket_assignment', {
      'id': id('A1'),
      'workspaceId': wsB,
      'ticketId': id('T1'),
      'userId': id('U1'),
      'assignedBy': id('U9'),
      'assignedAt': '2026-10-01T09:00:00.000Z',
      'revision': 1,
      'updatedAt': '2026-10-01T09:00:00.000Z',
    }),
    upsert('file', {
      'id': id('F1'),
      'workspaceId': wsB,
      'targetType': 'ticket',
      'targetId': id('T1'),
      'name': 'pano.jpg',
      'mime': 'image/jpeg',
      'sizeBytes': 12,
      'status': 'ready',
      'revision': 1,
      'createdAt': '2026-10-01T09:00:00.000Z',
      'updatedAt': '2026-10-01T09:00:00.000Z',
    }),
  ]);

  Future<List<int>> counts() async => [
    (await db.select(db.tickets).get()).length,
    (await db.select(db.ticketComments).get()).length,
    (await db.select(db.ticketAssignments).get()).length,
    (await db.select(db.fileRows).get()).length,
  ];

  List<SyncChange> leftStream() => [
    tombstone('ee_ticket', id('T1')),
    tombstone('ee_ticket_comment', id('C1')),
    tombstone('ee_ticket_assignment', id('A1')),
    tombstone('file', id('F1')),
  ];

  test('the stream it LEFT cannot delete what the new stream holds', () async {
    await holdMovedRequest();
    expect(await counts(), [1, 1, 1, 1]);

    await pulled(wsA, leftStream());

    expect(await counts(), [1, 1, 1, 1]);
  });

  test('the stream that holds it still deletes it, thread and all', () async {
    await holdMovedRequest();

    await pulled(wsB, leftStream());

    expect(await counts(), [0, 0, 0, 0]);
  });

  test('a refused push in the old workspace rebases nothing away', () async {
    await holdMovedRequest();

    for (final type in [
      ('ee_ticket', id('T1')),
      ('ee_ticket_comment', id('C1')),
      ('ee_ticket_assignment', id('A1')),
      ('file', id('F1')),
    ]) {
      await applyRebase(
        db,
        entityType: type.$1,
        entityId: type.$2,
        present: false,
        workspaceId: wsA,
      );
    }
    expect(await counts(), [1, 1, 1, 1]);

    // Without a workspace (older callers) the id alone still decides.
    await applyRebase(
      db,
      entityType: 'ee_ticket',
      entityId: id('T1'),
      present: false,
    );
    expect((await counts()).first, 0);
  });
}
