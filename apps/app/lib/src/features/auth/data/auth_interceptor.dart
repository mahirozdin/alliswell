import 'package:dio/dio.dart';

/// Attaches `Authorization: Bearer <access token>` to every request and, on a
/// 401, performs one token refresh and retries the original request once.
///
/// Extends [QueuedInterceptor] so concurrent 401s are handled serially: the
/// first failure triggers the refresh, the queued ones then pick up the new
/// token (the repository additionally single-flights the rotation itself).
class AuthInterceptor extends QueuedInterceptor {
  AuthInterceptor({
    required this._getAccessToken,
    required this._refreshAccessToken,
    Dio? retryClient,
  }) : _retryClient = retryClient ?? Dio();

  static const _retriedFlag = 'alliswell_auth_retried';

  final String? Function() _getAccessToken;
  final Future<String?> Function() _refreshAccessToken;
  final Dio _retryClient;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = _getAccessToken();
    if (token != null && !options.headers.containsKey('Authorization')) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final status = err.response?.statusCode;
    final options = err.requestOptions;
    final alreadyRetried = options.extra[_retriedFlag] == true;

    if (status != 401 || alreadyRetried) {
      handler.next(err);
      return;
    }

    final newToken = await _refreshAccessToken();
    if (newToken == null) {
      // Session is gone (refresh failed) — surface the original 401.
      handler.next(err);
      return;
    }

    options.extra[_retriedFlag] = true;
    options.headers['Authorization'] = 'Bearer $newToken';
    try {
      handler.resolve(await _retryClient.fetch<dynamic>(options));
    } on DioException catch (retryErr) {
      handler.next(retryErr);
    }
  }
}
