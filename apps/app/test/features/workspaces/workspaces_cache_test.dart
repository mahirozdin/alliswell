import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/api_exception.dart';
import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/workspaces/workspaces.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/providers.dart';

import '../auth/test_support.dart';

/// UI-AUDIT #27 — a passing `/me` failure keeps the last known list.
///
/// Home and the unit switcher are drawn from this list; the replica holds the
/// work. A 429 at a busy moment used to throw them away while everything the
/// screen needed was on the device.
void main() {
  const meJson = {
    'user': {'id': 'user-1'},
    'workspaces': [
      {
        'id': 'W1',
        'name': 'Bakım',
        'slug': 'bakim',
        'colorRgb': '#2563EB',
        'role': 'member',
        'owned': false,
      },
      {
        'id': 'W2',
        'name': 'Bilgi İşlem',
        'slug': 'bilgi-islem',
        'colorRgb': '#2563EB',
        'role': 'member',
        'owned': false,
      },
    ],
  };

  setUpAll(() => SharedPreferences.setMockInitialValues({}));

  setUp(() async {
    await localKv.removeWhere((_) => true);
  });

  /// A signed-in container whose `/me` answers with [answer], in order.
  Future<ProviderContainer> containerWith(
    List<Future<ResponseBody> Function(RequestOptions)> answers,
  ) async {
    final store = InMemorySecretStore();
    await TokenStorage(store).save(fakeSession());
    var call = 0;
    final db = AwDatabase(DatabaseConnection(NativeDatabase.memory()));
    final container = ProviderContainer(
      // No automatic retry: each case scripts exactly the answers it means.
      retry: (_, _) => null,
      overrides: [
        databaseProvider.overrideWithValue(db),
        secretStoreProvider.overrideWithValue(store),
        apiClientProvider.overrideWithValue(
          fakeDio(
            FakeHttpClientAdapter((options, _) {
              expect(options.path, '/api/v1/me');
              return answers[call++](options);
            }),
          ),
        ),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    await container.read(authControllerProvider.future);
    return container;
  }

  Future<ResponseBody> ok(RequestOptions _) async => jsonBody(200, meJson);
  Future<ResponseBody> status(int code) async =>
      jsonBody(code, {'statusCode': code, 'message': 'nope'});

  /// First read: a good answer, which fills the per-user cache. Second read:
  /// [failure], after the provider is asked again.
  Future<AsyncValue<List<WorkspaceSummary>>> afterFailure(
    Future<ResponseBody> Function(RequestOptions) failure,
  ) async {
    final container = await containerWith([ok, failure]);
    final first = await container.read(workspacesProvider.future);
    expect(first.map((w) => w.id), ['W1', 'W2']);
    container.invalidate(workspacesProvider);
    try {
      await container.read(workspacesProvider.future);
    } on Object {
      // Asserted on the AsyncValue below.
    }
    return container.read(workspacesProvider);
  }

  test('UI-AUDIT #27: a 429 keeps the last list', () async {
    final value = await afterFailure((_) => status(429));
    expect(value.hasError, isFalse);
    expect(value.value!.map((w) => w.id), ['W1', 'W2']);
  });

  test('UI-AUDIT #27: a 5xx keeps the last list', () async {
    for (final code in [500, 502, 503]) {
      final value = await afterFailure((_) => status(code));
      expect(value.hasError, isFalse, reason: '$code');
      expect(value.value!.map((w) => w.id), ['W1', 'W2'], reason: '$code');
    }
  });

  test('UI-AUDIT #27: a timeout keeps the last list', () async {
    final value = await afterFailure(
      (options) async => throw DioException.connectionTimeout(
        timeout: const Duration(seconds: 10),
        requestOptions: options,
      ),
    );
    expect(value.hasError, isFalse);
    expect(value.value!.map((w) => w.id), ['W1', 'W2']);
  });

  test(
    'UI-AUDIT #27: an answer about the account is not papered over',
    () async {
      for (final code in [401, 403, 404]) {
        final value = await afterFailure((_) => status(code));
        expect(value.hasError, isTrue, reason: '$code');
        expect(value.error, isA<ApiException>(), reason: '$code');
      }
    },
  );

  test(
    'UI-AUDIT #27: with no list ever seen, a 429 is still an error',
    () async {
      final container = await containerWith([(_) => status(429)]);
      await expectLater(
        container.read(workspacesProvider.future),
        throwsA(isA<ApiException>()),
      );
    },
  );

  test('isTransientMeFailure separates passing failures from answers', () {
    DioException withStatus(int? code) {
      final options = RequestOptions(path: '/api/v1/me');
      return DioException(
        requestOptions: options,
        response: code == null
            ? null
            : Response(requestOptions: options, statusCode: code),
      );
    }

    for (final code in [null, 408, 429, 500, 503, 504]) {
      expect(isTransientMeFailure(withStatus(code)), isTrue, reason: '$code');
    }
    for (final code in [400, 401, 403, 404, 410, 422]) {
      expect(isTransientMeFailure(withStatus(code)), isFalse, reason: '$code');
    }
  });
}
