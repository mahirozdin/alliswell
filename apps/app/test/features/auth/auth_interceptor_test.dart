import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';

import 'package:alliswell/src/features/auth/data/auth_interceptor.dart';

import 'test_support.dart';

void main() {
  Dio buildClient({
    required FakeHttpClientAdapter adapter,
    required String? Function() getAccessToken,
    required Future<String?> Function() refreshAccessToken,
  }) {
    final dio = fakeDio(adapter);
    dio.interceptors.add(
      AuthInterceptor(
        getAccessToken: getAccessToken,
        refreshAccessToken: refreshAccessToken,
        retryClient: fakeDio(adapter),
      ),
    );
    return dio;
  }

  test('attaches the bearer token to outgoing requests', () async {
    final adapter = FakeHttpClientAdapter((options, body) async {
      expect(options.headers['Authorization'], 'Bearer token-1');
      return jsonBody(200, {'ok': true});
    });
    final dio = buildClient(
      adapter: adapter,
      getAccessToken: () => 'token-1',
      refreshAccessToken: () async => fail('no refresh expected'),
    );

    final res = await dio.get<Map<String, dynamic>>('/api/v1/me');
    expect(res.data, {'ok': true});
  });

  test('on 401: refreshes once, retries with the new token', () async {
    var refreshCalls = 0;
    var currentToken = 'stale-token';
    final adapter = FakeHttpClientAdapter((options, body) async {
      if (options.headers['Authorization'] == 'Bearer fresh-token') {
        return jsonBody(200, {'ok': true});
      }
      return jsonBody(401, {'statusCode': 401, 'code': 'AUTH_TOKEN_EXPIRED'});
    });
    final dio = buildClient(
      adapter: adapter,
      getAccessToken: () => currentToken,
      refreshAccessToken: () async {
        refreshCalls++;
        currentToken = 'fresh-token';
        return currentToken;
      },
    );

    final res = await dio.get<Map<String, dynamic>>('/api/v1/me');

    expect(res.statusCode, 200);
    expect(refreshCalls, 1);
    expect(adapter.requests, hasLength(2), reason: 'original + one retry');
  });

  test('on 401 with a dead session: propagates the original error', () async {
    final adapter = FakeHttpClientAdapter(
      (options, body) async =>
          jsonBody(401, {'statusCode': 401, 'code': 'AUTH_INVALID_TOKEN'}),
    );
    final dio = buildClient(
      adapter: adapter,
      getAccessToken: () => 'stale-token',
      refreshAccessToken: () async => null,
    );

    await expectLater(
      dio.get<dynamic>('/api/v1/me'),
      throwsA(
        isA<DioException>().having(
          (e) => e.response?.statusCode,
          'status',
          401,
        ),
      ),
    );
    expect(adapter.requests, hasLength(1), reason: 'no retry without a token');
  });

  test('retries only once: a second 401 is surfaced, not looped', () async {
    var refreshCalls = 0;
    final adapter = FakeHttpClientAdapter(
      (options, body) async =>
          jsonBody(401, {'statusCode': 401, 'code': 'AUTH_INVALID_TOKEN'}),
    );
    final dio = buildClient(
      adapter: adapter,
      getAccessToken: () => 'stale-token',
      refreshAccessToken: () async {
        refreshCalls++;
        return 'still-rejected-token';
      },
    );

    await expectLater(
      dio.get<dynamic>('/api/v1/me'),
      throwsA(isA<DioException>()),
    );
    expect(refreshCalls, 1);
    expect(adapter.requests, hasLength(2));
  });

  test('non-401 errors pass through untouched', () async {
    final adapter = FakeHttpClientAdapter(
      (options, body) async => jsonBody(500, {'error': 'boom'}),
    );
    var refreshCalls = 0;
    final dio = buildClient(
      adapter: adapter,
      getAccessToken: () => 'token-1',
      refreshAccessToken: () async {
        refreshCalls++;
        return 'x';
      },
    );

    await expectLater(
      dio.get<dynamic>('/api/v1/me'),
      throwsA(
        isA<DioException>().having(
          (e) => e.response?.statusCode,
          'status',
          500,
        ),
      ),
    );
    expect(refreshCalls, 0);
  });
}
