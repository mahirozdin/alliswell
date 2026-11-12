import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/http_timeouts.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/providers.dart';

/// OPH-427: which calls are bounded, and which must not be.
void main() {
  test('a bounded call limits connect, send and receive on native', () {
    final options = boundedApiCall(web: false);
    expect(options.connectTimeout, kApiPhaseTimeout);
    expect(options.sendTimeout, kApiPhaseTimeout);
    expect(options.receiveTimeout, kApiPhaseTimeout);
  });

  test('on the web it sets no send bound (dio warns on every GET)', () {
    final options = boundedApiCall(web: true);
    expect(options.connectTimeout, kApiPhaseTimeout);
    expect(options.sendTimeout, isNull);
    expect(options.receiveTimeout, kApiPhaseTimeout);
    expect(
      boundedBaseOptions('http://api.test', web: true).sendTimeout,
      isNull,
    );
  });

  test('the whole-call backstop never undercuts the phases it covers', () {
    expect(kApiCallDeadline, greaterThanOrEqualTo(kApiPhaseTimeout * 3));
  });

  test('the auth client is bounded: a refresh that never answers cannot hold '
      'every queued request behind it', () {
    final dio = authHttpClient('http://api.test');
    expect(dio.options.baseUrl, 'http://api.test');
    expect(dio.options.connectTimeout, kApiPhaseTimeout);
    expect(dio.options.receiveTimeout, kApiPhaseTimeout);
  });

  test("the app's shared client stays unbounded: AI streams, imports, "
      'transcription uploads and exports run long on it', () {
    SharedPreferences.setMockInitialValues({});
    final app = ProviderContainer(
      overrides: [secretStoreProvider.overrideWithValue(InMemorySecretStore())],
    );
    addTearDown(app.dispose);
    final options = app.read(apiClientProvider).options;
    expect(options.connectTimeout, isNull);
    expect(options.sendTimeout, isNull);
    expect(options.receiveTimeout, isNull);
  });
}
