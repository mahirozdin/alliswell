import 'dart:convert';

import 'package:drift/drift.dart';

import '../core/ulid.dart';
import 'db/database.dart';

/// Records one local write in the outbox (OPH-055). Call inside the same
/// drift transaction as the optimistic local row change so the replica and
/// its outbox can never disagree. Returns the client mutation id.
Future<String> enqueueMutation(
  AwDatabase db, {
  required String workspaceId,
  required String entityType,
  required String entityId,
  required String operation,
  Map<String, dynamic>? patch,
}) async {
  final id = newUlid();
  await db
      .into(db.pendingMutations)
      .insert(
        PendingMutationsCompanion.insert(
          id: id,
          workspaceId: workspaceId,
          entityType: entityType,
          entityId: entityId,
          operation: operation,
          patchJson: Value(patch == null ? null : jsonEncode(patch)),
          localUpdatedAt: DateTime.now().toUtc(),
          createdAt: DateTime.now().toUtc(),
        ),
      );
  return id;
}
