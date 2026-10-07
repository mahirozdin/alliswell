import 'package:dio/dio.dart';

/// Stable machine-readable failure from any AllisWell API call — mirrors the
/// server's `code` field (AGENTS.md §4).
///
/// [statusCode] and [retryAfter] (OPH-357) let a message say more than the
/// code alone: a codeless 404 from a proxy, a 5xx, or "try again in 42 s" on
/// the limiter's `RATE_LIMITED` 429.
class ApiException implements Exception {
  const ApiException(
    this.code,
    this.message, {
    this.statusCode,
    this.retryAfter,
  });

  final String code;
  final String message;

  /// The HTTP status, when there was a response.
  final int? statusCode;

  /// Seconds until a rate-limited request may be retried: the body's
  /// `retryAfter`, else the `Retry-After` header (an older server's codeless
  /// 429 still sends that).
  final int? retryAfter;

  @override
  String toString() => 'ApiException($code): $message';
}

/// The wait a 429 asks for, in whole seconds — or null.
int? retryAfterOf(Response<dynamic>? response) {
  if (response == null) return null;
  final data = response.data;
  if (data is Map && data['retryAfter'] is num) {
    final seconds = (data['retryAfter'] as num).ceil();
    return seconds > 0 ? seconds : null;
  }
  final header = response.headers.value('retry-after');
  final seconds = header == null ? null : int.tryParse(header.trim());
  return seconds != null && seconds > 0 ? seconds : null;
}

/// Maps a [DioException] to an [ApiException] (or rethrows cancellation).
ApiException asApiException(DioException e) {
  final response = e.response;
  final data = response?.data;
  if (data is Map<String, dynamic> && data['code'] is String) {
    final message = data['message'];
    return ApiException(
      data['code'] as String,
      message is String ? message : 'Request failed',
      statusCode: response?.statusCode,
      retryAfter: retryAfterOf(response),
    );
  }
  if (response != null) {
    // The message is for logs: [localizedError] reads the status, never
    // this text (UI-AUDIT #24 — it reached Turkish screens verbatim).
    return ApiException(
      'HTTP_${response.statusCode}',
      'Unexpected server response',
      statusCode: response.statusCode,
      retryAfter: retryAfterOf(response),
    );
  }
  return const ApiException(
    'NETWORK_ERROR',
    'Could not reach the AllisWell server',
  );
}
