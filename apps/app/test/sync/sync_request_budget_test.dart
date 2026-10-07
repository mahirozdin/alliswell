import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/workspaces/workspaces.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/providers.dart';

import '../features/auth/test_support.dart';

/// OPH-357 / UI-AUDIT D3 — how many sync requests a member of NINE units
/// sends in a minute, measured against the real engines.
///
/// The audit saw a 429 storm on one shared IP and could not tell how much of
/// it was one person's sync loop. ADR-0045 now counts signed-in traffic per
/// user (RATE_LIMIT_MAX, 300/min by default), so the question is whether one
/// person's loop fits that budget with room to spare. This test answers it
/// with the engines the app builds (cadence included): the startup round is
/// COUNTED from a fake server, the steady rate is read off the timers the
/// engines were given. Measured on 2026-10-07: a first sign-in with 3 pages
/// per unit costs 27 pulls, a launch with nothing new 9, and the steady
/// loop ~2.6 pulls/min (the unit on screen every 60 s, the other eight every
/// 300 s) — an order of magnitude under the per-user budget.
const _units = 9;

String _id(int i) => '01WSUNIT${'$i' * 18}';

WorkspaceSummary _unit(int i) => WorkspaceSummary(
  id: _id(i),
  name: 'Unit $i',
  slug: 'unit-$i',
  colorRgb: '#2563EB',
  role: 'member',
  owned: false,
);

/// Counts every request; each unit has [pages] pages on its first pull.
class _Server {
  _Server({required this.pages});
  final int pages;
  int pulls = 0;
  int pushes = 0;

  Future<ResponseBody> handle(
    RequestOptions options,
    Map<String, dynamic>? body,
  ) async {
    final path = options.uri.path;
    if (path == '/api/v1/sync/pull') {
      pulls += 1;
      final ws = options.uri.queryParameters['workspaceId']!;
      final since = int.parse(options.uri.queryParameters['sinceRevision']!);
      final next = since < pages ? since + 1 : since;
      return jsonBody(200, {
        'workspaceId': ws,
        'fromRevision': since,
        'toRevision': next,
        'hasMore': next < pages,
        'changes': const [],
      });
    }
    if (path == '/api/v1/sync/push') {
      pushes += 1;
      return jsonBody(200, {
        'workspaceId': body?['workspaceId'],
        'toRevision': 0,
        'results': const [],
      });
    }
    return jsonBody(404, {'code': 'NOT_FOUND', 'message': path});
  }
}

void main() {
  late AwDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    for (var i = 1; i <= _units; i++) {
      await localKv.remove('$kCreatedByRepullPrefix${_id(i)}');
    }
    db = AwDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
  });

  tearDown(() => db.close());

  Future<ProviderContainer> start(_Server server) async {
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        apiClientProvider.overrideWithValue(
          fakeDio(FakeHttpClientAdapter(server.handle)),
        ),
        // The app's real cadence (not overridden): 60 s on screen, ×5 off it.
        syncDebounceProvider.overrideWithValue(Duration.zero),
        currentUserIdProvider.overrideWithValue('user-1'),
        workspacesProvider.overrideWith(
          (ref) async => [for (var i = 1; i <= _units; i++) _unit(i)],
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(workspacesProvider.future);
    container.listen(syncEnginesProvider, (_, _) {});
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
    return container;
  }

  /// Requests per minute once started, from the intervals the engines run on.
  double steadyPerMinute(ProviderContainer container) {
    var perMinute = 0.0;
    for (final engine in container.read(syncEnginesProvider).values) {
      final every = engine.pullInterval;
      expect(every, isNotNull);
      perMinute +=
          const Duration(minutes: 1).inMilliseconds / every!.inMilliseconds;
    }
    return perMinute;
  }

  test(
    'D3: a nine-unit member fits the per-user budget with room to spare',
    () async {
      final server = _Server(pages: 3);
      final container = await start(server);

      expect(container.read(syncEnginesProvider), hasLength(_units));
      // First sign-in: every unit pages through its 3 pages once.
      expect(server.pulls, _units * 3);
      expect(server.pushes, 0, reason: 'an empty outbox asks nothing');

      final steady = steadyPerMinute(container);
      expect(steady, closeTo(1 + 8 / 5, 0.001));

      // The worst minute: the whole first sync plus a minute of the loop.
      final worstMinute = server.pulls + steady.ceil();
      // ignore: avoid_print
      print(
        'D3 measured: first sign-in ${server.pulls} pulls, '
        'steady ${steady.toStringAsFixed(1)}/min, worst minute $worstMinute '
        '(RATE_LIMIT_MAX default 300 per user)',
      );
      expect(worstMinute, lessThan(300 ~/ 4));
    },
  );

  test('D3: an ordinary launch (nothing new) is one pull per unit', () async {
    final server = _Server(pages: 0);
    await start(server);
    expect(server.pulls, _units);
  });
}
