import 'dart:async';

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

  // OPH-447 (#48) — a session family names the device it runs on, so removing
  // that device elsewhere can sign it out.
  const deviceId = '01JDEV1CE0000000000000000A';

  test('refresh sends the device id once it is known', () async {
    String? known;
    final bodies = <Map<String, dynamic>?>[];
    final adapter = FakeHttpClientAdapter((options, body) async {
      bodies.add(body);
      if (options.path == '/api/v1/auth/login') {
        return jsonBody(200, sessionJson());
      }
      final n = bodies.length;
      return jsonBody(
        200,
        sessionJson(accessToken: 'access-$n', refreshToken: 'refresh-$n'),
      );
    });
    final repo = AuthRepository(
      api: AuthApi(fakeDio(adapter)),
      storage: TokenStorage(InMemorySecretStore()),
      deviceId: () async => known,
    );

    await repo.login(email: 'mahir@example.com', password: 'pw-pw-pw-pw');
    // No client id yet (a fresh install before its first sync round).
    await repo.refreshAccessToken();
    known = deviceId;
    await repo.refreshAccessToken();

    expect(bodies[0], {
      'email': 'mahir@example.com',
      'password': 'pw-pw-pw-pw',
    });
    expect(bodies[1], {'refreshToken': 'refresh-1'});
    expect(bodies[2], {'refreshToken': 'refresh-2', 'deviceId': deviceId});
  });

  test('an old server that rejects deviceId still signs in', () async {
    final paths = <String>[];
    // A server from before OPH-434: every auth body is
    // additionalProperties:false, so the unknown field is Fastify's 400.
    final adapter = FakeHttpClientAdapter((options, body) async {
      paths.add('${options.path} ${body!.containsKey('deviceId')}');
      if (body.containsKey('deviceId')) {
        return jsonBody(400, {
          'statusCode': 400,
          'code': 'FST_ERR_VALIDATION',
          'error': 'Bad Request',
          'message': 'body must NOT have additional properties',
        });
      }
      return jsonBody(
        200,
        options.path == '/api/v1/auth/refresh'
            ? sessionJson(accessToken: 'access-2', refreshToken: 'refresh-2')
            : sessionJson(),
      );
    });
    final storage = TokenStorage(InMemorySecretStore());
    final repo = AuthRepository(
      api: AuthApi(fakeDio(adapter)),
      storage: storage,
      deviceId: () async => deviceId,
    );

    await repo.login(email: 'mahir@example.com', password: 'pw-pw-pw-pw');
    expect(repo.session?.user.id, 'user-1');
    // A refresh is not a sign-out either.
    expect(await repo.refreshAccessToken(), 'access-2');
    expect((await storage.read())?.tokens.refreshToken, 'refresh-2');

    expect(paths, [
      '/api/v1/auth/login true',
      '/api/v1/auth/login false',
      '/api/v1/auth/refresh true',
      '/api/v1/auth/refresh false',
    ]);
  });

  test('register and social sign-in name the device too', () async {
    final bodies = <Map<String, dynamic>?>[];
    final h = AuthRepository(
      api: AuthApi(
        fakeDio(
          FakeHttpClientAdapter((options, body) async {
            bodies.add(body);
            return jsonBody(200, sessionJson());
          }),
        ),
      ),
      storage: TokenStorage(InMemorySecretStore()),
      deviceId: () async => deviceId,
    );

    await h.register(email: 'mahir@example.com', password: 'correct-horse');
    await h.signInWithProvider(provider: 'google', idToken: 'id-token');

    expect(bodies.map((b) => b?['deviceId']), [deviceId, deviceId]);
  });

  test('a device id that cannot be read never blocks a sign-in', () async {
    final bodies = <Map<String, dynamic>?>[];
    final repo = AuthRepository(
      api: AuthApi(
        fakeDio(
          FakeHttpClientAdapter((options, body) async {
            bodies.add(body);
            return jsonBody(200, sessionJson());
          }),
        ),
      ),
      storage: TokenStorage(InMemorySecretStore()),
      deviceId: () async => throw StateError('database closed'),
    );

    await repo.login(email: 'mahir@example.com', password: 'pw-pw-pw-pw');

    expect(repo.session, isNotNull);
    expect(bodies.single!.containsKey('deviceId'), isFalse);
  });

  // The server marks a removed device's family revoked (revoked_at) and
  // answers its next refresh AUTH_REFRESH_REUSED. AUTH_INVALID_REFRESH_TOKEN
  // also means a token that merely expired (AUTH_REFRESH_TTL_DAYS) or a server
  // that forgot it: no proof of removal, so no wipe of unsent work for it.
  test('only a revoked family reports a revoked session; an expired token '
      'does not', () async {
    var revoked = 0;
    var answer = 'AUTH_INVALID_REFRESH_TOKEN';
    final repo = AuthRepository(
      api: AuthApi(
        fakeDio(
          FakeHttpClientAdapter((options, body) async {
            if (options.path == '/api/v1/auth/login') {
              return jsonBody(200, sessionJson());
            }
            if (answer == 'NETWORK_ERROR') {
              throw DioException.connectionError(
                requestOptions: options,
                reason: 'offline',
              );
            }
            return jsonBody(401, {'statusCode': 401, 'code': answer});
          }),
        ),
      ),
      storage: TokenStorage(InMemorySecretStore()),
      onSessionRevoked: (_, {required replaced}) async => revoked++,
    );

    for (final code in [
      'AUTH_INVALID_REFRESH_TOKEN',
      'AUTH_REFRESH_REUSED',
      'NETWORK_ERROR',
      'RATE_LIMITED',
    ]) {
      answer = code;
      await repo.login(email: 'mahir@example.com', password: 'pw-pw-pw-pw');
      expect(await repo.refreshAccessToken(), isNull);
    }

    // The other failures still end the session (as before) but say nothing
    // about this device having been removed: no wipe for them.
    expect(revoked, 1);
  });

  // revocation-cleanup-crosses-sessions: the cleanup a revoked family starts
  // (wipe the replica, drop the alarms) is for THAT session. A sign-in that
  // lands around it must neither be cleaned up as the revoked one nor start
  // before that cleanup finished with what the revoked session left.
  group('a revoked refresh and a sign-in around it', () {
    Map<String, dynamic> secondUser() => {
      ...sessionJson(accessToken: 'access-b', refreshToken: 'refresh-b'),
      'user': {'id': 'user-2', 'email': 'b@example.com', 'displayName': 'B'},
    };

    test('a sign-in that lands while the refresh is on the wire keeps its '
        'session and is never cleaned up', () async {
      final refreshAnswer = Completer<void>();
      final revoked = <String>[];
      var logins = 0;
      final storage = TokenStorage(InMemorySecretStore());
      final repo = AuthRepository(
        api: AuthApi(
          fakeDio(
            FakeHttpClientAdapter((options, body) async {
              if (options.path == '/api/v1/auth/login') {
                return jsonBody(
                  200,
                  logins++ == 0 ? sessionJson() : secondUser(),
                );
              }
              await refreshAnswer.future;
              return jsonBody(401, {
                'statusCode': 401,
                'code': 'AUTH_REFRESH_REUSED',
              });
            }),
          ),
        ),
        storage: storage,
        onSessionRevoked: (userId, {required replaced}) async =>
            revoked.add(userId),
      );
      await repo.login(email: 'mahir@example.com', password: 'pw-pw-pw-pw');

      final refreshing = repo.refreshAccessToken();
      await pumpEventQueue();
      await repo.login(email: 'b@example.com', password: 'pw-pw-pw-pw');
      refreshAnswer.complete();

      expect(await refreshing, isNull);
      await pumpEventQueue();
      expect(repo.session?.user.id, 'user-2');
      expect((await storage.read())?.user.id, 'user-2');
      expect(revoked, isEmpty);
    });

    test('a sign-in after the refusal starts only once the revoked session\'s '
        'cleanup finished, and the cleanup names the revoked person', () async {
      final cleanupDone = Completer<void>();
      final order = <String>[];
      final repo = AuthRepository(
        api: AuthApi(
          fakeDio(
            FakeHttpClientAdapter((options, body) async {
              if (options.path == '/api/v1/auth/login') {
                return jsonBody(
                  200,
                  order.isEmpty ? sessionJson() : secondUser(),
                );
              }
              return jsonBody(401, {
                'statusCode': 401,
                'code': 'AUTH_REFRESH_REUSED',
              });
            }),
          ),
        ),
        storage: TokenStorage(InMemorySecretStore()),
        onSessionUser: (userId, {required restored}) async =>
            order.add('session $userId'),
        onSessionRevoked: (userId, {required replaced}) async {
          order.add('cleanup $userId started');
          await cleanupDone.future;
          order.add('cleanup $userId done');
        },
      );
      await repo.login(email: 'mahir@example.com', password: 'pw-pw-pw-pw');
      expect(await repo.refreshAccessToken(), isNull);
      await pumpEventQueue();

      final signIn = repo.login(
        email: 'b@example.com',
        password: 'pw-pw-pw-pw',
      );
      await pumpEventQueue();
      expect(order, ['session user-1', 'cleanup user-1 started']);
      expect(repo.session, isNull);

      cleanupDone.complete();
      await signIn;
      expect(order, [
        'session user-1',
        'cleanup user-1 started',
        'cleanup user-1 done',
        'session user-2',
      ]);
      expect(repo.session?.user.id, 'user-2');
    });

    // The refusal comes while B's sign-in is inside its session hook: B has
    // passed the wait for a running cleanup, and the repository still holds
    // A. A cleanup started then would outlast the hook and halt B's engines
    // and cancel B's alarms once B is exposed.
    test('a refusal during a sign-in\'s session hook is cleaned up before '
        'that sign-in exposes its session', () async {
      final refreshAnswer = Completer<void>();
      final hookGate = Completer<void>();
      final cleanupGate = Completer<void>();
      final order = <String>[];
      var logins = 0;
      final repo = AuthRepository(
        api: AuthApi(
          fakeDio(
            FakeHttpClientAdapter((options, body) async {
              if (options.path == '/api/v1/auth/login') {
                return jsonBody(
                  200,
                  logins++ == 0 ? sessionJson() : secondUser(),
                );
              }
              await refreshAnswer.future;
              return jsonBody(401, {
                'statusCode': 401,
                'code': 'AUTH_REFRESH_REUSED',
              });
            }),
          ),
        ),
        storage: TokenStorage(InMemorySecretStore()),
        onSessionUser: (userId, {required restored}) async {
          order.add('hook $userId');
          if (userId == 'user-2') await hookGate.future;
        },
        onSessionRevoked: (userId, {required replaced}) async {
          order.add('cleanup $userId replaced=$replaced');
          await cleanupGate.future;
          order.add('cleanup $userId done');
        },
      );
      await repo.login(email: 'mahir@example.com', password: 'pw-pw-pw-pw');
      repo.sessionChanges.listen((s) => order.add('exposed ${s?.user.id}'));

      final refreshing = repo.refreshAccessToken();
      await pumpEventQueue();
      final signIn = repo.login(
        email: 'b@example.com',
        password: 'pw-pw-pw-pw',
      );
      await pumpEventQueue();
      refreshAnswer.complete();
      expect(await refreshing, isNull);
      await pumpEventQueue();
      // Nothing of A's cleanup may start while B can still be exposed
      // before it ends.
      expect(order, ['hook user-1', 'hook user-2', 'exposed null']);

      hookGate.complete();
      await pumpEventQueue();
      expect(repo.session, isNull, reason: 'B waits for A\'s cleanup');

      cleanupGate.complete();
      await signIn;
      await pumpEventQueue();
      expect(order, [
        'hook user-1',
        'hook user-2',
        'exposed null',
        'cleanup user-1 replaced=true',
        'cleanup user-1 done',
        'exposed user-2',
      ]);
      expect(repo.session?.user.id, 'user-2');
    });

    // signin-binds-discarded-client-id: the cleanup discards the replica and
    // the install's client id with it. A sign-in that read the id before the
    // cleanup ran would bind its family to an id nothing lists any more.
    test('a sign-in names the device only after a running cleanup discarded '
        'what it discards', () async {
      final cleanupGate = Completer<void>();
      String? clientId = 'client-x';
      final loginBodies = <Map<String, dynamic>?>[];
      final repo = AuthRepository(
        api: AuthApi(
          fakeDio(
            FakeHttpClientAdapter((options, body) async {
              if (options.path == '/api/v1/auth/login') {
                loginBodies.add(body);
                return jsonBody(
                  200,
                  loginBodies.length == 1 ? sessionJson() : secondUser(),
                );
              }
              return jsonBody(401, {
                'statusCode': 401,
                'code': 'AUTH_REFRESH_REUSED',
              });
            }),
          ),
        ),
        storage: TokenStorage(InMemorySecretStore()),
        deviceId: () async => clientId,
        onSessionRevoked: (userId, {required replaced}) async {
          await cleanupGate.future;
          // The wipe: sync_states and the carried-over id are gone.
          clientId = null;
        },
      );
      await repo.login(email: 'mahir@example.com', password: 'pw-pw-pw-pw');
      expect(await repo.refreshAccessToken(), isNull);

      final signIn = repo.login(
        email: 'b@example.com',
        password: 'pw-pw-pw-pw',
      );
      await pumpEventQueue();
      expect(loginBodies, hasLength(1), reason: 'no request before cleanup');

      cleanupGate.complete();
      await signIn;
      expect(loginBodies.last, {
        'email': 'b@example.com',
        'password': 'pw-pw-pw-pw',
      });
      expect(repo.session?.user.id, 'user-2');
    });

    // The other order: the sign-in already sent the id when the refusal
    // comes. The cleanup runs inside that sign-in, before its owner check,
    // and leaves the replica (and so the id) to that check.
    test('a refusal while a sign-in is on the wire is cleaned up inside it, '
        'as replaced, before its session hook', () async {
      final refreshAnswer = Completer<void>();
      final loginGate = Completer<void>();
      final order = <String>[];
      var logins = 0;
      final repo = AuthRepository(
        api: AuthApi(
          fakeDio(
            FakeHttpClientAdapter((options, body) async {
              if (options.path == '/api/v1/auth/login') {
                if (logins++ == 0) return jsonBody(200, sessionJson());
                order.add('login sent ${body?['deviceId']}');
                await loginGate.future;
                return jsonBody(200, secondUser());
              }
              await refreshAnswer.future;
              return jsonBody(401, {
                'statusCode': 401,
                'code': 'AUTH_REFRESH_REUSED',
              });
            }),
          ),
        ),
        storage: TokenStorage(InMemorySecretStore()),
        deviceId: () async => 'client-x',
        onSessionUser: (userId, {required restored}) async =>
            order.add('hook $userId'),
        onSessionRevoked: (userId, {required replaced}) async =>
            order.add('cleanup $userId replaced=$replaced'),
      );
      await repo.login(email: 'mahir@example.com', password: 'pw-pw-pw-pw');

      final refreshing = repo.refreshAccessToken();
      await pumpEventQueue();
      final signIn = repo.login(
        email: 'b@example.com',
        password: 'pw-pw-pw-pw',
      );
      await pumpEventQueue();
      refreshAnswer.complete();
      expect(await refreshing, isNull);
      await pumpEventQueue();
      expect(order, ['hook user-1', 'login sent client-x']);

      loginGate.complete();
      await signIn;
      expect(order, [
        'hook user-1',
        'login sent client-x',
        'cleanup user-1 replaced=true',
        'hook user-2',
      ]);
      expect(repo.session?.user.id, 'user-2');
    });

    test(
      'a sign-in that fails runs the cleanup it held back, in full',
      () async {
        final refreshAnswer = Completer<void>();
        final loginGate = Completer<void>();
        final revoked = <String>[];
        var logins = 0;
        final repo = AuthRepository(
          api: AuthApi(
            fakeDio(
              FakeHttpClientAdapter((options, body) async {
                if (options.path == '/api/v1/auth/login') {
                  if (logins++ == 0) return jsonBody(200, sessionJson());
                  await loginGate.future;
                  return jsonBody(401, {
                    'statusCode': 401,
                    'code': 'AUTH_INVALID_CREDENTIALS',
                  });
                }
                await refreshAnswer.future;
                return jsonBody(401, {
                  'statusCode': 401,
                  'code': 'AUTH_REFRESH_REUSED',
                });
              }),
            ),
          ),
          storage: TokenStorage(InMemorySecretStore()),
          onSessionRevoked: (userId, {required replaced}) async =>
              revoked.add('$userId replaced=$replaced'),
        );
        await repo.login(email: 'mahir@example.com', password: 'pw-pw-pw-pw');

        final refreshing = repo.refreshAccessToken();
        await pumpEventQueue();
        final signIn = repo.login(email: 'b@example.com', password: 'wrong-pw');
        await pumpEventQueue();
        refreshAnswer.complete();
        expect(await refreshing, isNull);
        await pumpEventQueue();
        expect(revoked, isEmpty);

        loginGate.complete();
        await expectLater(signIn, throwsA(isA<AuthException>()));
        await pumpEventQueue();
        expect(revoked, ['user-1 replaced=false']);
        expect(repo.session, isNull);
      },
    );

    test(
      'a refresh answered after a sign-out never brings the session back',
      () async {
        final refreshAnswer = Completer<void>();
        final storage = TokenStorage(InMemorySecretStore());
        final repo = AuthRepository(
          api: AuthApi(
            fakeDio(
              FakeHttpClientAdapter((options, body) async {
                if (options.path == '/api/v1/auth/login') {
                  return jsonBody(200, sessionJson());
                }
                if (options.path == '/api/v1/auth/logout') {
                  return jsonBody(204, {});
                }
                await refreshAnswer.future;
                return jsonBody(
                  200,
                  sessionJson(
                    accessToken: 'access-2',
                    refreshToken: 'refresh-2',
                  ),
                );
              }),
            ),
          ),
          storage: storage,
        );
        await repo.login(email: 'mahir@example.com', password: 'pw-pw-pw-pw');
        final refreshing = repo.refreshAccessToken();
        await pumpEventQueue();
        await repo.logout();
        refreshAnswer.complete();

        expect(await refreshing, isNull);
        expect(repo.session, isNull);
        expect(await storage.read(), isNull);
      },
    );
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
  test(
    'logout tolerates a 204 with an empty body (dio-web) and clears',
    () async {
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
    },
  );

  // Defense in depth for the broadened catch: even a non-AuthException from the
  // API must not prevent the local sign-out.
  test(
    'logout clears locally even if the API throws a non-AuthException',
    () async {
      final storage = TokenStorage(InMemorySecretStore());
      final repo = AuthRepository(api: _ThrowingLogoutApi(), storage: storage);
      await storage.save(fakeSession());
      await repo.restore();

      await repo.logout();

      expect(repo.session, isNull);
      expect(await storage.read(), isNull);
    },
  );

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
