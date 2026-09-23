import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/app_liveness.dart';
import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/features/widgets/widget_bridge.dart';
import 'package:alliswell/src/features/widgets/widget_host.dart';
import 'package:alliswell/src/notifications/headless.dart';
import 'package:alliswell/src/sync/db/database.dart';

import '../../support/fake_widget_host.dart';

const ws = '01WSAAAAAAAAAAAAAAAAAAAAAA';
String id(String prefix) => prefix.padRight(26, '0');

/// OPH-334 — the widget's day turns over without the app.
///
/// The buckets are computed in Dart from the replica (ADR-0010), so a native
/// redraw can only re-render yesterday's snapshot. The background turn now ends
/// by republishing it, and a one-time midnight worker (Android) asks for that
/// turn when the periodic one — every six hours — would come too late.
void main() {
  late AwDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AwDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
  });

  tearDown(() => db.close());

  // Day N is 1 June 2030, local time; "tomorrow" is 2 June.
  final lateEvening = DateTime(2030, 6, 1, 22);
  final pastMidnight = DateTime(2030, 6, 2, 0, 5);
  final tomorrowMorning = DateTime(2030, 6, 2, 10);

  Future<void> seedTask(
    String tid, {
    DateTime? dueAt,
    String status = 'open',
    DateTime? completedAt,
    String? projectId,
  }) => db
      .into(db.tasks)
      .insert(
        TasksCompanion.insert(
          id: id(tid),
          workspaceId: ws,
          title: 'Görev $tid',
          status: Value(status),
          dueAt: Value(dueAt),
          completedAt: Value(completedAt),
          projectId: Value(projectId),
        ),
      );

  Map<String, dynamic> snapshotOf(FakeWidgetHost host) =>
      jsonDecode(host.lastSaved!) as Map<String, dynamic>;

  Map<String, dynamic>? rowOf(Map<String, dynamic> snapshot, String taskId) {
    for (final bucket in snapshot['buckets'] as List) {
      for (final item in (bucket as Map)['items'] as List) {
        if ((item as Map)['id'] == taskId) {
          return {...item.cast<String, dynamic>(), 'bucket': bucket['key']};
        }
      }
    }
    return null;
  }

  test('the same rows, a new day: the buckets move at midnight', () async {
    await seedTask('T1', dueAt: tomorrowMorning);
    final host = FakeWidgetHost();

    expect(
      await publishWidgetFromReplica(
        db,
        workspaceId: ws,
        now: lateEvening,
        host: host,
      ),
      isTrue,
    );
    expect(rowOf(snapshotOf(host), id('T1'))!['bucket'], 'thisWeek');
    expect(snapshotOf(host).containsKey('openToday'), isFalse);

    // Nothing in the replica changed. Only the clock did — which is exactly
    // what a native-only redraw cannot see.
    expect(
      await publishWidgetFromReplica(
        db,
        workspaceId: ws,
        now: pastMidnight,
        host: host,
      ),
      isTrue,
    );
    expect(rowOf(snapshotOf(host), id('T1'))!['bucket'], 'today');
    expect(snapshotOf(host)['openToday'], 1);
    expect(host.updates, 2);
  });

  test('it asks the replica the LIVE question, not a second one', () async {
    // `watchOpen(completedSince: start of today)` — OPH-185's dimmed rows. A
    // task finished today stays on the widget; one finished yesterday is gone.
    await db
        .into(db.projects)
        .insert(
          ProjectsCompanion.insert(
            id: id('P1'),
            workspaceId: ws,
            name: 'Ev',
            colorRgb: const Value('#10B981'),
          ),
        );
    await seedTask('OPEN', dueAt: tomorrowMorning, projectId: id('P1'));
    await seedTask(
      'DONE-TODAY',
      dueAt: DateTime(2030, 6, 2, 9),
      status: 'completed',
      completedAt: DateTime(2030, 6, 2, 0, 1),
    );
    await seedTask(
      'DONE-YESTERDAY',
      dueAt: DateTime(2030, 6, 1, 9),
      status: 'completed',
      completedAt: DateTime(2030, 6, 1, 23),
    );
    final host = FakeWidgetHost();

    await publishWidgetFromReplica(
      db,
      workspaceId: ws,
      now: pastMidnight,
      host: host,
    );

    final snapshot = snapshotOf(host);
    expect(rowOf(snapshot, id('OPEN'))!['projectColor'], '#10B981');
    expect(rowOf(snapshot, id('DONE-TODAY'))!['done'], isTrue);
    expect(rowOf(snapshot, id('DONE-YESTERDAY')), isNull);
  });

  test(
    'never throws: a host that fails reports false and nothing else',
    () async {
      await seedTask('T1', dueAt: tomorrowMorning);

      expect(
        await publishWidgetFromReplica(
          db,
          workspaceId: ws,
          now: pastMidnight,
          host: _BrokenHost(),
        ),
        isFalse,
      );
    },
  );

  test(
    'the background turn ends by redrawing — even with no session',
    () async {
      // On a test VM there is no Keychain, so the turn cannot restore a session
      // — the same answer a locked iPhone gives (ADR-0038 §8). The widget is
      // redrawn anyway: the rows may be stale, the day is not.
      await db
          .into(db.syncStates)
          .insert(SyncStatesCompanion.insert(workspaceId: ws, clientId: 'C1'));
      // The turn reads the REAL clock, so the row must sit inside the widget's
      // 30-day horizon from today — a 2030 date would be dropped, not drawn.
      await seedTask('T1', dueAt: DateTime.now().add(const Duration(days: 2)));
      final host = FakeWidgetHost();

      await runHeadlessRefresh(
        openDatabase: () => db,
        liveness: AppLiveness(_NeverKv()),
        widgetHost: host,
      );

      expect(host.updates, 1);
      expect(rowOf(snapshotOf(host), id('T1')), isNotNull);
    },
  );

  test('...and declines outright while the app is in front', () async {
    // The running app republishes on every change already (OPH-318's stamp).
    await db
        .into(db.syncStates)
        .insert(SyncStatesCompanion.insert(workspaceId: ws, clientId: 'C1'));
    final host = FakeWidgetHost();

    await runHeadlessRefresh(
      openDatabase: () => db,
      liveness: AppLiveness(_ForegroundKv()),
      widgetHost: host,
    );

    expect(host.updates, 0);
  });
}

/// A host whose platform side is missing — what a background isolate without
/// the plugin would look like.
class _BrokenHost implements WidgetHost {
  @override
  Future<void> configure() async => throw StateError('no plugin here');

  @override
  Future<void> save(String key, String value) async {}

  @override
  Future<void> requestUpdate() async {}
}

/// A store that remembers nothing — the ordinary "app is not running" state.
class _NeverKv implements LocalKv {
  @override
  Future<String?> get(String key) async => null;

  @override
  Future<void> set(String key, String value) async {}

  @override
  Future<void> remove(String key) async {}
}

/// A store holding a foreground stamp from a minute ago (see
/// headless_parity_test.dart for why a minute and not now).
class _ForegroundKv implements LocalKv {
  @override
  Future<String?> get(String key) async => DateTime.now()
      .toUtc()
      .subtract(const Duration(minutes: 1))
      .toIso8601String();

  @override
  Future<void> set(String key, String value) async {}

  @override
  Future<void> remove(String key) async {}
}
