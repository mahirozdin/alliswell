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
  });

  final String clientMutationId;
  final String entityType;
  final String entityId;
  final String operation;
  final Map<String, dynamic>? patch;
  final DateTime? localUpdatedAt;

  Map<String, dynamic> toJson() => {
    'clientMutationId': clientMutationId,
    'entityType': entityType,
    'entityId': entityId,
    'operation': operation,
    if (patch != null) 'patch': patch,
    if (localUpdatedAt != null)
      'localUpdatedAt': localUpdatedAt!.toUtc().toIso8601String(),
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
  });

  factory SyncPushResult.fromJson(Map<String, dynamic> json) => SyncPushResult(
    clientMutationId: json['clientMutationId'] as String,
    status: json['status'] as String,
    replayed: (json['replayed'] as bool?) ?? false,
    revision: json['revision'] as int?,
    errorCode: json['errorCode'] as String?,
    discardedFields: ((json['discardedFields'] as List?) ?? const [])
        .cast<String>(),
  );

  final String clientMutationId;
  final String status;
  final bool replayed;
  final int? revision;
  final String? errorCode;
  final List<String> discardedFields;

  bool get applied => status == 'applied';
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
