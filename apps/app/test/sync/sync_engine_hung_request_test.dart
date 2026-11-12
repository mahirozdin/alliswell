import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/core/http_timeouts.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/outbox.dart';
import 'package:alliswell/src/sync/sync_api.dart';
import 'package:alliswell/src/sync/sync_engine.dart';

import '../features/auth/test_support.dart';

/// OPH-427 (#46/#48): the engine runs one round at a time, so one push or pull
/// that never answers used to stop every later round — no push for a later
/// write, no periodic pull — until the app restarted. Each request now has a
/// deadline that ends in the ordinary offline/backoff path.
const ws = '01WSAAAAAAAAAAAAAAAAAAAAAA';
const _deadline = Duration(milliseconds: 150);

/// Answers at once, except for the calls the test tells it to leave hanging.
class _HangingApi implements SyncApi {
  int pullCalls = 0;
  int pushCalls = 0;
  bool hangNextPull = false;
  bool hangNextPush = false;
  Duration pullDelay = Duration.zero;
  final List<List<String>> pushedIds = [];

  @override
  Future<SyncPullPage> pull(
    String workspaceId, {
    required int sinceRevision,
    int? limit,
  }) async {
    pullCalls += 1;
    if (hangNextPull) {
      hangNextPull = false;
      return Completer<SyncPullPage>().future; // the request that never ends
    }
    if (pullDelay > Duration.zero) await Future<void>.delayed(pullDelay);
    return SyncPullPage(
      fromRevision: sinceRevision,
      toRevision: sinceRevision,
      hasMore: false,
      changes: const [],
    );
  }

  @override
  Future<SyncPushResponse> push({
    required String clientId,
    required String workspaceId,
    required int baseRevision,
    required List<SyncMutation> mutations,
  }) {
    pushCalls += 1;
    pushedIds.add([for (final m in mutations) m.clientMutationId]);
    if (hangNextPush) {
      hangNextPush = false;
      return Completer<SyncPushResponse>().future;
    }
    return Future.value(
      SyncPushResponse(
        toRevision: baseRevision + mutations.length,
        results: [
          for (final (i, m) in mutations.indexed)
            SyncPushResult(
              clientMutationId: m.clientMutationId,
              status: 'applied',
              replayed: false,
              revision: baseRevision + i + 1,
            ),
        ],
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _queueAck(AwDatabase db) => enqueueMutation(
  db,
  workspaceId: ws,
  entityType: 'reminder',
  entityId: '01RMAAAAAAAAAAAAAAAAAAAAAA',
  operation: 'update',
  patch: {'status': 'acknowledged'},
);

SyncEngine _engine(AwDatabase db, SyncApi api, {Duration? pullInterval}) =>
    SyncEngine(
      db: db,
      api: api,
      workspaceId: ws,
      debounce: const Duration(milliseconds: 20),
      pullInterval: pullInterval,
      requestTimeout: _deadline,
    );

Future<void> _until(
  FutureOr<bool> Function() done, {
  required String reason,
}) async {
  final end = DateTime.now().add(const Duration(seconds: 5));
  while (!await done()) {
    if (DateTime.now().isAfter(end)) fail(reason);
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late AwDatabase db;
  setUp(() => db = AwDatabase(DatabaseConnection(NativeDatabase.memory())));
  tearDown(() => db.close());

  test('a pull that never answers times out; a later write is pushed and '
      'periodic pulls continue', () async {
    final api = _HangingApi()..hangNextPull = true;
    final engine = _engine(
      db,
      api,
      pullInterval: const Duration(milliseconds: 100),
    );
    addTearDown(engine.dispose);
    unawaited(engine.start()); // its first round hangs in pull()
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await _queueAck(db); // the local write is not blocked
    engine.notifyLocalWrite();
    await _until(
      () => api.pushCalls >= 1 && api.pullCalls > 3,
      reason:
          'push ${api.pushCalls}, pull ${api.pullCalls}: the rounds after '
          'the unanswered pull never ran',
    );
    await _until(
      () async => (await db.select(db.pendingMutations).get()).isEmpty,
      reason: 'the pushed write never left the outbox',
    );
  });

  test('the same after a first round that answered (a request lost later '
      'in the session)', () async {
    final api = _HangingApi();
    final engine = _engine(
      db,
      api,
      pullInterval: const Duration(milliseconds: 100),
    );
    addTearDown(engine.dispose);
    await engine.start(); // first round: answered
    api.hangNextPull = true;
    final pullsBefore = api.pullCalls;
    await _until(
      () => api.pullCalls > pullsBefore,
      reason: 'a pull on the wire',
    );
    await db.transaction(() => _queueAck(db));
    engine.notifyLocalWrite();
    await _until(
      () => api.pushCalls >= 1 && api.pullCalls > pullsBefore + 2,
      reason: 'no push and ${api.pullCalls} pull(s) after the lost request',
    );
  });

  test('a push that never answers times out; the write stays queued and goes '
      'again under the same clientMutationId', () async {
    final api = _HangingApi()..hangNextPush = true;
    final engine = _engine(db, api);
    addTearDown(engine.dispose);
    await engine.start();
    await _queueAck(db);
    expect(await engine.syncNow(), isFalse, reason: 'a timed-out round fails');
    final row = (await db.select(db.pendingMutations).get()).single;
    expect(row.attempts, 1);
    expect(row.lastError, 'network');
    // The backoff retry (1 s) resends it; the server dedupes a resend of a
    // push that did land by (clientId, clientMutationId).
    await _until(
      () => api.pushCalls >= 2,
      reason: 'the backoff never resent the write',
    );
    expect(api.pushedIds[1], api.pushedIds[0]);
    await _until(
      () async => (await db.select(db.pendingMutations).get()).isEmpty,
      reason: 'the resend never left the outbox',
    );
  });

  test(
    'an answer that comes inside the deadline is applied, not cut',
    () async {
      final api = _HangingApi()
        ..pullDelay = const Duration(milliseconds: 60); // < 150 ms
      final engine = _engine(db, api);
      addTearDown(engine.dispose);
      await engine.start();
      await _queueAck(db);
      expect(await engine.syncNow(), isTrue);
      expect(await db.select(db.pendingMutations).get(), isEmpty);
    },
  );

  test('without an override the deadline is the app-wide backstop', () {
    final engine = SyncEngine(db: db, api: _HangingApi(), workspaceId: ws);
    addTearDown(engine.dispose);
    expect(engine.requestTimeout, kApiCallDeadline);
  });

  group('the sync calls carry their own bounds on the shared client', () {
    late FakeHttpClientAdapter adapter;
    late SyncApi api;
    setUp(() {
      adapter = FakeHttpClientAdapter(
        (options, _) async => options.path.endsWith('/pull')
            ? jsonBody(200, {
                'fromRevision': 0,
                'toRevision': 0,
                'hasMore': false,
                'changes': <Object>[],
              })
            : jsonBody(200, {'toRevision': 0, 'results': <Object>[]}),
      );
      // The shared client itself has no timeouts (long transfers use it).
      api = SyncApi(
        Dio(BaseOptions(baseUrl: 'http://api.test'))
          ..httpClientAdapter = adapter,
      );
    });

    test('pull', () async {
      await api.pull(ws, sinceRevision: 0);
      final sent = adapter.requests.single;
      expect(sent.connectTimeout, kApiPhaseTimeout);
      expect(sent.receiveTimeout, kApiPhaseTimeout);
    });

    test('push', () async {
      await api.push(
        clientId: 'c',
        workspaceId: ws,
        baseRevision: 0,
        mutations: const [],
      );
      final sent = adapter.requests.single;
      expect(sent.connectTimeout, kApiPhaseTimeout);
      expect(sent.receiveTimeout, kApiPhaseTimeout);
      expect(sent.sendTimeout, kApiPhaseTimeout);
    });
  });
}
