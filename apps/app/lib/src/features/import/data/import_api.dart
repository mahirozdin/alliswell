import 'package:dio/dio.dart';

import '../../../core/api_exception.dart';
import 'import_models.dart';

/// REST client for the import wizard (OPH-371, ADR-0052).
///
/// Direct-to-API like `ApiKeysApi`, NOT the sync protocol: an import is a
/// server-side operation on a file, and what it creates reaches this device
/// the ordinary way — through the next /sync/pull.
class AppImportApi {
  const AppImportApi(this._dio);
  final Dio _dio;

  /// One preview (`dryRun`) or one import batch. A batch on a slow server can
  /// take a while: the receive timeout is generous on purpose.
  Future<ImportSummary> run(
    String workspaceId, {
    required ImportSource source,
    required List<ImportFileText> files,
    required bool dryRun,
    required Map<String, Object> options,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/api/v1/workspaces/$workspaceId/import/apps',
        data: {
          'source': source.wire,
          'files': [for (final f in files) f.toJson()],
          'dryRun': dryRun,
          'options': options,
        },
        options: Options(
          receiveTimeout: const Duration(seconds: 120),
          sendTimeout: const Duration(seconds: 120),
        ),
      );
      return ImportSummary.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map && data['code'] == 'IMPORT_SOURCE_MISMATCH') {
        throw ImportSourceMismatch(data['detected'] as String? ?? '');
      }
      throw asApiException(e);
    }
  }
}

/// The server read the file and it belongs to the OTHER app.
class ImportSourceMismatch implements Exception {
  const ImportSourceMismatch(this.detected);
  final String detected;
}
