import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/api_exception.dart';

/// One downloaded export: the bytes exactly as the server wrote them (the
/// UTF-8 BOM that makes Excel read "Işık" right is the server's, EE-303), the
/// name it suggested, and whether it stopped at its row ceiling.
class EeCsvFile {
  const EeCsvFile({
    required this.bytes,
    required this.filename,
    this.truncated = false,
  });

  final Uint8List bytes;
  final String filename;
  final bool truncated;
}

/// The CSV doors (OPH-360, UI-AUDIT #56) — `tickets.csv` behind
/// `tickets.export`, `audit.csv` behind `team.view_audit`. Both existed on
/// the server with no button anywhere in the app.
///
/// Filters are OMITTED when empty, never sent blank: both querystrings are
/// typed and `additionalProperties: false`, so `status=` is a 400.
class EeCsvExportApi {
  const EeCsvExportApi(this._dio);
  final Dio _dio;

  Future<EeCsvFile> tickets({
    String? status,
    String? priority,
    String? source,
    String? slaStatus,
    String? serviceId,
    String? unitId,
  }) => _get('/api/v1/ee/team/tickets.csv', 'requests.csv', {
    'status': ?status,
    'priority': ?priority,
    'source': ?source,
    'slaStatus': ?slaStatus,
    'serviceId': ?serviceId,
    'unitId': ?unitId,
  });

  Future<EeCsvFile> audit({String? verb, String? entityType}) => _get(
    '/api/v1/ee/team/audit.csv',
    'audit.csv',
    {'verb': ?verb, 'entityType': ?entityType},
  );

  Future<EeCsvFile> _get(
    String path,
    String fallbackName,
    Map<String, Object> query,
  ) async {
    try {
      final res = await _dio.get<List<int>>(
        path,
        queryParameters: query,
        options: Options(responseType: ResponseType.bytes),
      );
      return EeCsvFile(
        bytes: Uint8List.fromList(res.data ?? const []),
        filename:
            filenameFromDisposition(res.headers.value('content-disposition')) ??
            fallbackName,
        truncated: res.headers.value('x-truncated') == 'true',
      );
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }
}

/// `attachment; filename="acme-requests-2026-10-07.csv"` → the name, or null.
/// Only a plain, path-free name is taken: the header is the server's, but a
/// file name is still not allowed to carry a directory.
String? filenameFromDisposition(String? header) {
  if (header == null) return null;
  final match = RegExp(r'filename="?([^";]+)"?').firstMatch(header);
  final name = match?.group(1)?.trim();
  if (name == null || name.isEmpty || name.contains(RegExp(r'[\\/]'))) {
    return null;
  }
  return name;
}
