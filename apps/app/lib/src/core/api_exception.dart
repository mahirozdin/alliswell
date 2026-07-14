import 'package:dio/dio.dart';

/// Stable machine-readable failure from any AllisWell API call — mirrors the
/// server's `code` field (AGENTS.md §4).
class ApiException implements Exception {
  const ApiException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'ApiException($code): $message';
}

/// Maps a [DioException] to an [ApiException] (or rethrows cancellation).
ApiException asApiException(DioException e) {
  final data = e.response?.data;
  if (data is Map<String, dynamic> && data['code'] is String) {
    final message = data['message'];
    return ApiException(
      data['code'] as String,
      message is String ? message : 'Request failed',
    );
  }
  if (e.response != null) {
    return ApiException(
      'HTTP_${e.response!.statusCode}',
      'Unexpected server response',
    );
  }
  return const ApiException(
    'NETWORK_ERROR',
    'Could not reach the AllisWell server',
  );
}
