import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';

import 'package:alliswell/src/features/auth/data/auth_api.dart';
import 'package:alliswell/src/features/auth/data/auth_repository.dart';
import 'package:alliswell/src/features/auth/data/models.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';

import 'test_support.dart';

({AuthRepository repo, TokenStorage storage, FakeHttpClientAdapter adapter})
harness(FakeHandler handler) {
  final adapter = FakeHttpClientAdapter(handler);
  final storage = TokenStorage(InMemorySecretStore());
  final repo = AuthRepository(api: AuthApi(fakeDio(adapter)), storage: storage);
  return (repo: repo, storage: storage, adapter: adapter);
}

/// An [AuthApi] whose logout blows up with a non-AuthException — proves the
/// repository still clears local state (OPH-100 broadened catch).
class _ThrowingLogoutApi extends AuthApi {
  _ThrowingLogoutApi() : super(Dio());

  @override
  Future<void> logout(String refreshToken, {bool allDevices = false}) async {
    throw StateError('unexpected decode failure');
  }
}

void main() {
  test('register stores the session and exposes the access token', () async {
    final h = harness((options, body) async {
      expect(options.path, '/api/v1/auth/register');
      expect(body, {
        'email': 'mahir@example.com',
        'password': 'correct-horse-battery',
        'displayName': 'Mahir',
      });
      return jsonBody(201, sessionJson());
    });

    final session = await h.repo.register(
      email: 'mahir@example.com',
      password: 'correct-horse-battery',
      displayName: 'Mahir',
    );

    expect(session.user.email, 'mahir@example.com');
    expect(h.repo.accessToken, 'access-1');
    expect((await h.storage.read())?.tokens.refreshToken, 'refresh-1');
  });

  test('login failure maps the API error code and stores nothing', () async {
    final h = harness(
      (options, body) async => jsonBody(401, {
        'statusCode': 401,
        'code': 'AUTH_INVALID_CREDENTIALS',
        'error': 'Unauthorized',
        'message': 'Invalid email or password',
      }),
    );

    await expectLater(
      h.repo.login(email: 'mahir@example.com', password: 'nope-nope-nope'),
      throwsA(
        isA<AuthException>().having(
          (e) => e.code,
          'code',
          'AUTH_INVALID_CREDENTIALS',
        ),
      ),
    );
    expect(h.repo.session, isNull);
    expect(await h.storage.read(), isNull);
  });

  test('network failure surfaces as NETWORK_ERROR', () async {
    final h = harness((options, body) async {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'refused',
      );
    });

    await expectLater(
      h.repo.login(email: 'mahir@example.com', password: 'whatever-pw'),
      throwsA(
        isA<AuthException>().having((e) => e.code, 'code', 'NETWORK_ERROR'),
      ),
    );
  });

  test('refreshAccessToken rotates once for concurrent callers', () async {
    var refreshCalls = 0;
    final h = harness((options, body) async {
      if (options.path == '/api/v1/auth/login') {
        return jsonBody(200, sessionJson());
      }
      refreshCalls++;
      expect(body, {'refreshToken': 'refresh-1'});
      return jsonBody(
        200,
        sessionJson(accessToken: 'access-2', refreshToken: 'refresh-2'),
      );
    });
    await h.repo.login(email: 'mahir@example.com', password: 'pw-pw-pw-pw');

    final tokens = await Future.wait([
      h.repo.refreshAccessToken(),
      h.repo.refreshAccessToken(),
      h.repo.refreshAccessToken(),
    ]);

    expect(refreshCalls, 1, reason: 'rotation must be single-flight');
    expect(tokens, ['access-2', 'access-2', 'access-2']);
    expect((await h.storage.read())?.tokens.refreshToken, 'refresh-2');
  });

  test('a failed refresh force-signs-out and notifies listeners', () async {
    final h = harness((options, body) async {
      if (options.path == '/api/v1/auth/login') {
        return jsonBody(200, sessionJson());
      }
      return jsonBody(401, {
        'statusCode': 401,
        'code': 'AUTH_REFRESH_REUSED',
        'error': 'Unauthorized',
        'message': 'reuse detected',
      });
    });
    await h.repo.login(email: 'mahir@example.com', password: 'pw-pw-pw-pw');

    final events = <AuthSession?>[];
    final sub = h.repo.sessionChanges.listen(events.add);

    expect(await h.repo.refreshAccessToken(), isNull);
    expect(h.repo.session, isNull);
    expect(await h.storage.read(), isNull);
    await Future<void>.delayed(Duration.zero);
    expect(events, [null]);

    await sub.cancel();
  });

  test('refreshAccessToken without a session is null (no API call)', () async {
    final h = harness((options, body) async => fail('no request expected'));
    expect(await h.repo.refreshAccessToken(), isNull);
  });

  test('logout revokes remotely (all=true) and clears locally', () async {
    String? logoutQuery;
    final h = harness((options, body) async {
      if (options.path == '/api/v1/auth/login') {
        return jsonBody(200, sessionJson());
      }
      expect(options.path, '/api/v1/auth/logout');
      expect(body, {'refreshToken': 'refresh-1'});
      logoutQuery = options.uri.query;
      return jsonBody(204, {});
    });
    await h.repo.login(email: 'mahir@example.com', password: 'pw-pw-pw-pw');

    await h.repo.logout(allDevices: true);

    expect(logoutQuery, 'all=true');
    expect(h.repo.session, isNull);
    expect(await h.storage.read(), isNull);
  });

  test(
    'logout clears local state even when the server is unreachable',
    () async {
      final h = harness((options, body) async {
        if (options.path == '/api/v1/auth/login') {
          return jsonBody(200, sessionJson());
        }
        throw DioException.connectionError(
          requestOptions: options,
          reason: 'offline',
        );
      });
      await h.repo.login(email: 'mahir@example.com', password: 'pw-pw-pw-pw');

      await h.repo.logout();
      expect(h.repo.session, isNull);
      expect(await h.storage.read(), isNull);
    },
  );

  // OPH-100: a 204 logout on web returns res.data == '' (empty string). The
  // old `res.data as Map` cast threw a TypeError that was NOT an AuthException,
  // so it escaped logout's catch and the session was never cleared locally.
  test('logout tolerates a 204 with an empty body (dio-web) and clears', () async {
    var loggedOut = false;
    final h = harness((options, body) async {
      if (options.path == '/api/v1/auth/login') {
        return jsonBody(200, sessionJson());
      }
      expect(options.path, '/api/v1/auth/logout');
      loggedOut = true;
      return emptyBody(204); // the real dio-web shape, not jsonBody(204, {})
    });
    await h.repo.login(email: 'mahir@example.com', password: 'pw-pw-pw-pw');

    await h.repo.logout();

    expect(loggedOut, isTrue);
    expect(h.repo.session, isNull);
    expect(await h.storage.read(), isNull);
  });

  // Defense in depth for the broadened catch: even a non-AuthException from the
  // API must not prevent the local sign-out.
  test('logout clears locally even if the API throws a non-AuthException', () async {
    final storage = TokenStorage(InMemorySecretStore());
    final repo = AuthRepository(api: _ThrowingLogoutApi(), storage: storage);
    await storage.save(fakeSession());
    await repo.restore();

    await repo.logout();

    expect(repo.session, isNull);
    expect(await storage.read(), isNull);
  });

  test('restore returns the stored session and drops expired ones', () async {
    final h = harness((options, body) async => fail('no request expected'));

    await h.storage.save(fakeSession());
    expect((await h.repo.restore())?.user.id, 'user-1');

    await h.storage.save(
      fakeSession(
        refreshExpiresAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
    );
    expect(await h.repo.restore(), isNull);
    expect(await h.storage.read(), isNull, reason: 'expired blob is deleted');
  });
}
