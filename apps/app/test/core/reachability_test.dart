import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/reachability.dart';
import 'package:alliswell/src/features/auth/data/auth_interceptor.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/providers.dart';

/// OPH-342 — "did the server answer the last time anything asked?"
///
/// The signal a direct-to-server surface needs to grey itself out BEFORE it is
/// pressed. These pin what counts as an answer and what counts as silence,
/// because the costly mistake is in each direction: calling a 404 "offline"
/// would disable a working surface, and calling a refused connection an
/// answer would leave a dead button live.
class _Adapter implements HttpClientAdapter {
  Future<ResponseBody> Function(RequestOptions options)? next;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => next!(options);

  @override
  void close({bool force = false}) {}
}

void main() {
  late ProviderContainer container;
  late _Adapter adapter;
  late Dio dio;

  setUp(() {
    container = ProviderContainer();
    adapter = _Adapter();
    dio = Dio(BaseOptions(baseUrl: 'https://api.example'))
      ..httpClientAdapter = adapter
      ..interceptors.add(
        ReachabilityInterceptor(
          container.read(serverReachabilityProvider.notifier),
        ),
      );
  });

  tearDown(() => container.dispose());

  bool? reachable() => container.read(serverReachabilityProvider);

  Future<void> answer(int status) async {
    adapter.next = (_) async => ResponseBody.fromString(
      '{}',
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
    try {
      await dio.get<dynamic>('/x');
    } on DioException {
      // A 4xx is still thrown by Dio; the point is what the provider saw.
    }
  }

  Future<void> fail(DioExceptionType type) async {
    adapter.next = (options) async =>
        throw DioException(requestOptions: options, type: type);
    try {
      await dio.get<dynamic>('/x');
    } on DioException {
      // Expected.
    }
  }

  test('unknown until anything has been asked — unknown is not offline', () {
    expect(reachable(), isNull);
  });

  test('any answer, a 4xx included, means reachable', () async {
    await answer(404);
    expect(reachable(), isTrue, reason: '"no such thing" is an answer');
    await fail(DioExceptionType.connectionError);
    await answer(200);
    expect(reachable(), isTrue);
  });

  test(
    'no route, refused, or timed out while connecting is unreachable',
    () async {
      for (final type in [
        DioExceptionType.connectionError,
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
      ]) {
        await answer(200);
        await fail(type);
        expect(reachable(), isFalse, reason: '$type');
      }
    },
  );

  test('a cancelled request says nothing about the network', () async {
    await answer(200);
    await fail(DioExceptionType.cancel);
    expect(reachable(), isTrue);
  });

  test("the app's client carries it, before anything that retries", () {
    SharedPreferences.setMockInitialValues({});
    final app = ProviderContainer(
      overrides: [secretStoreProvider.overrideWithValue(InMemorySecretStore())],
    );
    addTearDown(app.dispose);
    final interceptors = app.read(apiClientProvider).interceptors.toList();
    final reach = interceptors.indexWhere((i) => i is ReachabilityInterceptor);
    final auth = interceptors.indexWhere((i) => i is AuthInterceptor);
    expect(reach, isNonNegative);
    expect(reach, lessThan(auth), reason: 'it must see the raw 401 too');
  });
}
