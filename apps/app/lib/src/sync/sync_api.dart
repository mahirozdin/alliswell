import 'package:dio/dio.dart';

import '../core/api_exception.dart';

/// One change row from `GET /sync/pull` — a snapshot (`data`) for
/// create/update or a tombstone (`data == null`, operation `delete`).
class SyncChange {
  const SyncChange({
    required this.revision,
    required this.entityType,
    required this.entityId,
    required this.operation,
    this.data,
  });

  factory SyncChange.fromJson(Map<String, dynamic> json) => SyncChange(
    revision: json['revision'] as int,
    entityType: json['entityType'] as String,
    entityId: json['entityId'] as String,
    operation: json['operation'] as String,
    data: json['data'] as Map<String, dynamic>?,
  );

  final int revision;
  final String entityType;
  final String entityId;
  final String operation;
  final Map<String, dynamic>? data;

  bool get isTombstone => data == null || operation == 'delete';
}

class SyncPullPage {
  const SyncPullPage({
    required this.fromRevision,
    required this.toRevision,
    required this.hasMore,
    required this.changes,
  });

  factory SyncPullPage.fromJson(Map<String, dynamic> json) => SyncPullPage(
    fromRevision: json['fromRevision'] as int,
    toRevision: json['toRevision'] as int,
    hasMore: json['hasMore'] as bool,
    changes: ((json['changes'] as List?) ?? const [])
        .map((c) => SyncChange.fromJson(c as Map<String, dynamic>))
        .toList(),
  );

  final int fromRevision;
  final int toRevision;
  final bool hasMore;
  final List<SyncChange> changes;
}

/// One mutation of a push batch (BLUEPRINT §6.3) — mirrors a pending_mutations
/// outbox row.
class SyncMutation {
  const SyncMutation({
    required this.clientMutationId,
    required this.entityType,
    required this.entityId,
    required this.operation,
    this.patch,
    this.localUpdatedAt,
    this.baseRevision,
  });

  final String clientMutationId;
  final String entityType;
  final String entityId;
  final String operation;
  final Map<String, dynamic>? patch;
  final DateTime? localUpdatedAt;

  /// OPH-268: the entity revision this write started from.
  final int? baseRevision;

  Map<String, dynamic> toJson() => {
    'clientMutationId': clientMutationId,
    'entityType': entityType,
    'entityId': entityId,
    'operation': operation,
    if (patch != null) 'patch': patch,
    if (localUpdatedAt != null)
      'localUpdatedAt': localUpdatedAt!.toUtc().toIso8601String(),
    if (baseRevision != null) 'baseRevision': baseRevision,
  };
}

class SyncPushResult {
  const SyncPushResult({
    required this.clientMutationId,
    required this.status,
    required this.replayed,
    this.revision,
    this.errorCode,
    this.discardedFields = const [],
    this.conflictVersionId,
    this.reason,
    this.mergedMarkdown,
    this.rebase,
  });

  factory SyncPushResult.fromJson(Map<String, dynamic> json) => SyncPushResult(
    clientMutationId: json['clientMutationId'] as String,
    status: json['status'] as String,
    replayed: (json['replayed'] as bool?) ?? false,
    revision: json['revision'] as int?,
    errorCode: json['errorCode'] as String?,
    discardedFields: ((json['discardedFields'] as List?) ?? const [])
        .cast<String>(),
    conflictVersionId: json['conflictVersionId'] as String?,
    reason: json['reason'] as String?,
    mergedMarkdown:
        (json['merged'] as Map<String, dynamic>?)?['contentMarkdown']
            as String?,
    rebase: json['rebase'] == null
        ? null
        : SyncRebase.fromJson(json['rebase'] as Map<String, dynamic>),
  );

  final String clientMutationId;
  final String status;
  final bool replayed;
  final int? revision;
  final String? errorCode;
  final List<String> discardedFields;

  /// OPH-268 — where the server kept the body it refused (nothing is lost),
  /// why it could not merge, and the merged body when it could.
  final String? conflictVersionId;
  final String? reason;
  final String? mergedMarkdown;

  /// EE-051 — what the row really looks like after a refusal. Present on
  /// rejections so the replica can stop showing a write nobody accepted.
  final SyncRebase? rebase;

  bool get applied => status == 'applied' || status == 'merged';
  bool get merged => status == 'merged';
}

/// The server's answer to "so what IS this row?" after it refused a write.
///
/// `present: false` means there is nothing there — which is the refused
/// CREATE, and the local row is a phantom that has to go. Otherwise `data` is
/// the same serialized shape `/sync/pull` delivers, so it goes through the
/// applier the client already has instead of a second, divergent code path.
class SyncRebase {
  const SyncRebase({
    required this.entityType,
    required this.entityId,
    required this.present,
    this.data,
  });

  factory SyncRebase.fromJson(Map<String, dynamic> json) => SyncRebase(
    entityType: json['entityType'] as String,
    entityId: json['entityId'] as String,
    present: (json['present'] as bool?) ?? false,
    data: json['data'] as Map<String, dynamic>?,
  );

  final String entityType;
  final String entityId;
  final bool present;
  final Map<String, dynamic>? data;
}

class SyncPushResponse {
  const SyncPushResponse({required this.toRevision, required this.results});

  factory SyncPushResponse.fromJson(Map<String, dynamic> json) =>
      SyncPushResponse(
        toRevision: json['toRevision'] as int,
        results: ((json['results'] as List?) ?? const [])
            .map((r) => SyncPushResult.fromJson(r as Map<String, dynamic>))
            .toList(),
      );

  final int toRevision;
  final List<SyncPushResult> results;
}

/// HTTP calls for `/api/v1/sync/*` (Epic 06 server core).
class SyncApi {
  const SyncApi(this._dio);

  final Dio _dio;

  Future<SyncPullPage> pull(
    String workspaceId, {
    required int sinceRevision,
    int? limit,
  }) async {
    final res = await _run(
      () => _dio.get<Map<String, dynamic>>(
        '/api/v1/sync/pull',
        queryParameters: {
          'workspaceId': workspaceId,
          'sinceRevision': '$sinceRevision',
          if (limit != null) 'limit': '$limit',
        },
      ),
    );
    return SyncPullPage.fromJson(res.data!);
  }

  Future<SyncPushResponse> push({
    required String clientId,
    required String workspaceId,
    required int baseRevision,
    required List<SyncMutation> mutations,
  }) async {
    final res = await _run(
      () => _dio.post<Map<String, dynamic>>(
        '/api/v1/sync/push',
        data: {
          'clientId': clientId,
          'workspaceId': workspaceId,
          'baseRevision': baseRevision,
          'mutations': mutations.map((m) => m.toJson()).toList(),
        },
      ),
    );
    return SyncPushResponse.fromJson(res.data!);
  }

  Future<T> _run<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }
}
