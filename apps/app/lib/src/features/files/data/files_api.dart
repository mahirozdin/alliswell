import 'package:dio/dio.dart';

import '../../../core/api_exception.dart';

/// File attachment client (OPH-153) over the Epic 14 endpoints
/// (`apps/api/src/routes/files.js`, ATTACHMENTS.md §6).
///
/// Deliberately REST, not the sync protocol: an upload is inherently online
/// (the bytes go to object storage), so queueing one in the outbox would be a
/// lie (ADR-0011). Reads still come from the replica (`FileStore`) — after
/// every successful write, callers `syncNow()` so the replica converges (the
/// archive-flow pattern).

/// `GET /api/v1/storage` — is the feature on, and what are the limits.
class StorageStatus {
  const StorageStatus({
    required this.configured,
    required this.maxUploadBytes,
    required this.presignTtlSec,
  });

  factory StorageStatus.fromJson(Map<String, dynamic> json) => StorageStatus(
    configured: json['configured'] as bool? ?? false,
    maxUploadBytes: (json['maxUploadBytes'] as num?)?.toInt() ?? 0,
    presignTtlSec: (json['presignTtlSec'] as num?)?.toInt() ?? 0,
  );

  final bool configured;
  final int maxUploadBytes;
  final int presignTtlSec;
}

/// What upload-init answers: the file id plus exactly where and how to PUT.
class UploadTicket {
  const UploadTicket({
    required this.fileId,
    required this.url,
    required this.headers,
  });

  final String fileId;
  final String url;

  /// Signed headers the PUT MUST carry (content-type today).
  final Map<String, String> headers;
}

/// A minted download: expires, so never cache beyond [expiresAt].
class FileDownload {
  const FileDownload({required this.url, this.expiresAt});

  final String url;
  final DateTime? expiresAt;
}

class FilesApi {
  FilesApi(this._dio);

  final Dio _dio;

  Future<StorageStatus> storageStatus() => _run(() async {
    final res = await _dio.get<Map<String, dynamic>>('/api/v1/storage');
    return StorageStatus.fromJson(res.data ?? const {});
  });

  /// Step 1 of the upload handshake (ATTACHMENTS.md §2.1).
  Future<UploadTicket> initUpload({
    required String workspaceId,
    required String targetType,
    required String targetId,
    required String name,
    required int sizeBytes,
    String? mime,
  }) => _run(() async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/api/v1/workspaces/$workspaceId/files',
      data: {
        'targetType': targetType,
        'targetId': targetId,
        'name': name,
        'sizeBytes': sizeBytes,
        'mime': ?mime,
      },
    );
    final file = res.data!['file'] as Map<String, dynamic>;
    final upload = res.data!['upload'] as Map<String, dynamic>;
    return UploadTicket(
      fileId: file['id'] as String,
      url: upload['url'] as String,
      headers: ((upload['headers'] as Map?) ?? const {}).map(
        (k, v) => MapEntry(k.toString(), v.toString()),
      ),
    );
  });

  /// Step 3: the server verifies the bytes and publishes the file.
  Future<void> complete(String fileId) =>
      _run(() => _dio.post<void>('/api/v1/files/$fileId/complete'));

  /// A fresh short-lived download URL, or null while not downloadable.
  Future<FileDownload?> download(String fileId) => _run(() async {
    final res = await _dio.get<Map<String, dynamic>>('/api/v1/files/$fileId');
    final url = res.data?['downloadUrl'] as String?;
    if (url == null) return null;
    final expires = res.data?['downloadExpiresAt'] as String?;
    return FileDownload(
      url: url,
      expiresAt: expires == null ? null : DateTime.tryParse(expires),
    );
  });

  Future<void> rename(String fileId, String name) => _run(
    () => _dio.patch<void>('/api/v1/files/$fileId', data: {'name': name}),
  );

  /// Workspace-wide storage footprint (ready files only) — the Files tab
  /// footer (OPH-157). Display data; quota enforcement is v2.
  Future<({int totalBytes, int fileCount})> usage(String workspaceId) =>
      _run(() async {
        final res = await _dio.get<Map<String, dynamic>>(
          '/api/v1/workspaces/$workspaceId/files/usage',
        );
        return (
          totalBytes: (res.data?['totalBytes'] as num?)?.toInt() ?? 0,
          fileCount: (res.data?['fileCount'] as num?)?.toInt() ?? 0,
        );
      });

  /// Abort (uploading) or delete (ready) — the server picks the right path.
  Future<void> delete(String fileId) =>
      _run(() => _dio.delete<void>('/api/v1/files/$fileId'));

  Future<T> _run<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }
}
