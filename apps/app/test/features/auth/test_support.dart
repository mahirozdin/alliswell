import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:alliswell/src/features/auth/data/models.dart';

/// Handler signature for [FakeHttpClientAdapter]: `body` is the decoded JSON
/// request payload (dio keeps the original object on [RequestOptions.data]).
typedef FakeHandler =
    Future<ResponseBody> Function(
      RequestOptions options,
      Map<String, dynamic>? body,
    );

/// In-process replacement for dio's HTTP layer — no sockets, full control.
class FakeHttpClientAdapter implements HttpClientAdapter {
  FakeHttpClientAdapter(this.handler);

  final FakeHandler handler;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final data = options.data;
    final body = data is Map<String, dynamic>
        ? data
        : data is String && data.isNotEmpty
        ? jsonDecode(data) as Map<String, dynamic>
        : null;
    return handler(options, body);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonBody(int status, Object data) => ResponseBody.fromString(
  jsonEncode(data),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

/// A response with a completely empty body — what a `204 No Content` (e.g.
/// logout) looks like on dio-web, where `res.data` comes back as the empty
/// STRING '' (not null). Reproduces the OPH-100 sign-out crash on the old
/// `as Map` cast.
ResponseBody emptyBody(int status) => ResponseBody.fromString(
  '',
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

Dio fakeDio(FakeHttpClientAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'http://alliswell.test'));
  dio.httpClientAdapter = adapter;
  return dio;
}

AuthSession fakeSession({
  String accessToken = 'access-1',
  String refreshToken = 'refresh-1',
  DateTime? refreshExpiresAt,
}) => AuthSession(
  user: const AuthUser(
    id: 'user-1',
    email: 'mahir@example.com',
    displayName: 'Mahir',
  ),
  tokens: AuthTokens(
    accessToken: accessToken,
    accessTokenExpiresInSec: 900,
    refreshToken: refreshToken,
    refreshTokenExpiresAt:
        refreshExpiresAt ?? DateTime.now().add(const Duration(days: 30)),
  ),
);

/// The JSON shape `/api/v1/auth/{register,login,refresh}` responds with.
Map<String, dynamic> sessionJson({
  String accessToken = 'access-1',
  String refreshToken = 'refresh-1',
}) => {
  'user': {
    'id': 'user-1',
    'email': 'mahir@example.com',
    'displayName': 'Mahir',
  },
  'tokens': {
    'accessToken': accessToken,
    'accessTokenExpiresInSec': 900,
    'refreshToken': refreshToken,
    'refreshTokenExpiresAt': DateTime.now()
        .add(const Duration(days: 30))
        .toIso8601String(),
  },
};
