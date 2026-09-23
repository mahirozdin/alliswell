import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/core/persisted_prefs.dart';
import 'package:alliswell/src/features/projects/data/project.dart';
import 'package:alliswell/src/features/projects/providers.dart';
import 'package:alliswell/src/features/tasks/data/task.dart';
import 'package:alliswell/src/features/tasks/providers.dart';
import 'package:alliswell/src/features/widgets/widget_bridge.dart';
import 'package:alliswell/src/features/widgets/widget_host.dart';
import 'package:alliswell/src/features/widgets/widget_snapshot.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/screens/settings_screen.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/theme/theme.dart';

import '../../support/fake_widget_host.dart';

/// OPH-337 — "Private widget": no task's title reaches the widget's shared
/// storage. Measured the only way that counts, by reading every string the
/// host was handed — a check on a key set would pass a title hiding in a
/// field nobody thought to look at (AGENTS: the leak that gets through a
/// key-set check is a declared key holding prose).
///
/// Every title here starts with [secret], so "no leak" is one substring test
/// over the raw JSON.
const secret = 'SECRET';

Task _task(String id, {DateTime? dueAt, String? projectId}) => Task(
  id: id,
  workspaceId: 'W1',
  title: '$secret $id',
  status: 'open',
  priority: 'high',
  timezone: 'Europe/Istanbul',
  isUrgent: false,
  requiresAcknowledgement: false,
  sortOrder: 0,
  revision: 1,
  dueAt: dueAt,
  projectId: projectId,
);

Project _project(String id) => Project(
  id: id,
  workspaceId: 'W1',
  name: 'Project $id',
  colorRgb: '#0A5CFF',
  status: 'active',
  sortOrder: 0,
  isFavorite: false,
  revision: 1,
);

void main() {
  final now = DateTime(2026, 7, 17, 10);
  // Every place a title can land: overdue (the lock screen's `next`), today,
  // this week, no date, a project's own view.
  final tasks = [
    _task('late', dueAt: DateTime(2026, 7, 10, 9), projectId: 'p1'),
    _task('today', dueAt: DateTime(2026, 7, 17, 14)),
    _task('week', dueAt: DateTime(2026, 7, 20, 9), projectId: 'p1'),
    _task('someday'),
  ];

  setUpAll(() => SharedPreferences.setMockInitialValues({}));

  setUp(() async {
    AwI18n.instance.setActiveCached(const Locale('en'));
    // `localKv` keeps the SharedPreferences instance it got first, so mock
    // values set after that never reach it — measured: the stored "private"
    // of one test leaked into the next. Reset the two keys THROUGH it.
    await localKv.remove(kWidgetPrivatePrefKey);
    await localKv.remove(kWidgetCompactPrefKey);
  });

  group('the snapshot', () {
    test('private: no title anywhere in the JSON — placeholders instead', () {
      final raw = jsonEncode(
        buildWidgetSnapshot(
          tasks,
          now: now,
          projects: [_project('p1')],
          hideTitles: true,
        ).toJson(),
      );
      expect(raw, isNot(contains(secret)));
      // Still a widget: every row is there under the placeholder, with the
      // id the circle and the deep link need, and the lock screen still
      // names a next task.
      expect('Private task'.allMatches(raw).length, greaterThan(tasks.length));
      for (final task in tasks) {
        expect(raw, contains(task.id));
      }
      final json = jsonDecode(raw) as Map<String, dynamic>;
      expect(json['next']['title'], 'Private task');
      expect(json['views']['p1']['next']['title'], 'Private task');
    });

    test('private changes the words, not the numbers', () {
      final open = buildWidgetSnapshot(tasks, now: now).toJson();
      final private = buildWidgetSnapshot(
        tasks,
        now: now,
        hideTitles: true,
      ).toJson();
      expect(private['openToday'], open['openToday']);
      expect(
        [for (final b in private['buckets'] as List) b['count']],
        [for (final b in open['buckets'] as List) b['count']],
      );
    });

    test('not private is exactly what it was', () {
      final raw = jsonEncode(buildWidgetSnapshot(tasks, now: now).toJson());
      expect(raw, contains('$secret late'));
      expect(raw, isNot(contains('Private task')));
    });

    test('density rides in the JSON only when it is not the default', () {
      expect(
        buildWidgetSnapshot(tasks, now: now).toJson().containsKey('density'),
        isFalse,
      );
      expect(
        buildWidgetSnapshot(tasks, now: now, compact: true).toJson()['density'],
        'compact',
      );
    });

    test('the placeholder is the app’s word, in the app’s language', () {
      AwI18n.instance.setActiveCached(const Locale('tr'));
      final raw = jsonEncode(
        buildWidgetSnapshot(tasks, now: now, hideTitles: true).toJson(),
      );
      expect(raw, contains('Gizli görev'));
      expect(raw, isNot(contains(secret)));
    });
  });

  test('the bridge hands the host no title', () async {
    final host = FakeWidgetHost();
    await WidgetBridge(host).publish(tasks, now: now, hideTitles: true);
    expect(host.saved, isNotEmpty);
    for (final written in host.saved) {
      expect(written, isNot(contains(secret)));
    }
  });

  group('the background turn (OPH-334) hides what the app hides', () {
    const ws = '01WSAAAAAAAAAAAAAAAAAAAAAA';
    late AwDatabase db;

    setUp(() async {
      db = AwDatabase(
        DatabaseConnection(
          NativeDatabase.memory(),
          closeStreamsSynchronously: true,
        ),
      );
      await db
          .into(db.tasks)
          .insert(
            TasksCompanion.insert(
              id: 'T1'.padRight(26, '0'),
              workspaceId: ws,
              title: '$secret from the replica',
              dueAt: Value(DateTime.now()),
            ),
          );
    });

    tearDown(() => db.close());

    test('stored "private" is read, and no title is written', () async {
      await localKv.set(kWidgetPrivatePrefKey, 'true');
      await localKv.set(kWidgetCompactPrefKey, 'true');
      final host = FakeWidgetHost();
      expect(
        await publishWidgetFromReplica(
          db,
          workspaceId: ws,
          now: DateTime.now(),
          host: host,
        ),
        isTrue,
      );
      expect(host.lastSaved, isNot(contains(secret)));
      expect(host.lastSaved, contains('Private task'));
      expect(jsonDecode(host.lastSaved!)['density'], 'compact');
    });

    test('never set: the replica’s titles, as before', () async {
      final host = FakeWidgetHost();
      await publishWidgetFromReplica(
        db,
        workspaceId: ws,
        now: DateTime.now(),
        host: host,
      );
      expect(host.lastSaved, contains('$secret from the replica'));
    });
  });

  group('the live app waits for the setting before its first publish', () {
    test('nothing goes out while "private" is still being read', () async {
      final gate = Completer<void>();
      final host = FakeWidgetHost();
      final container = ProviderContainer(
        overrides: [
          openTasksProvider.overrideWith((ref) => Stream.value(tasks)),
          projectsByIdProvider.overrideWithValue(const {}),
          widgetHostProvider.overrideWithValue(host),
          widgetPrivateProvider.overrideWith(() => _SlowPrivacy(gate)),
        ],
      );
      addTearDown(container.dispose);
      container.listen(widgetSyncProvider, (_, _) {});

      // The tasks arrive; the setting has not.
      await container.read(openTasksProvider.future);
      await pumpEventQueue();
      expect(
        host.saved,
        isEmpty,
        reason:
            'a publish on the default would write every title once per '
            'start, before the stored "private" arrived',
      );

      gate.complete();
      await container.read(widgetPrivateProvider.future);
      await pumpEventQueue();
      expect(host.saved, isNotEmpty);
      for (final written in host.saved) {
        expect(written, isNot(contains(secret)));
      }
    });
  });

  group('Settings › General', () {
    Future<void> pumpGeneral(
      WidgetTester tester, {
      Brightness brightness = Brightness.light,
      Size size = const Size(1000, 1800),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildAwTheme(brightness),
            home: const SettingsGeneralScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    // Rule 11: every UI change is looked at in light AND dark — and on a phone,
    // where the Turkish subtitle is the longest line on the card.
    for (final brightness in Brightness.values) {
      testWidgets('the card renders in ${brightness.name}, phone-wide, in '
          'Turkish', (tester) async {
        AwI18n.instance.setActiveCached(const Locale('tr'));
        await pumpGeneral(
          tester,
          brightness: brightness,
          size: const Size(360, 1800),
        );
        expect(find.byKey(const Key('settings-widget')), findsOneWidget);
        expect(find.text('Gizli widget'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('"Private widget" is a switch that remembers', (tester) async {
      await pumpGeneral(tester);
      final row = find.byKey(const Key('settings-widget-private'));
      expect(row, findsOneWidget);
      expect(tester.widget<SwitchListTile>(row).value, isFalse);

      await tester.tap(row);
      await tester.pumpAndSettle();

      expect(tester.widget<SwitchListTile>(row).value, isTrue);
      expect(await localKv.get(kWidgetPrivatePrefKey), 'true');
    });

    testWidgets('"Compact widget" is a switch that remembers', (tester) async {
      await pumpGeneral(tester);
      final row = find.byKey(const Key('settings-widget-compact'));
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(row).value, isTrue);
      expect(await localKv.get(kWidgetCompactPrefKey), 'true');
    });
  });

  // The native readers cannot run here; this pins what they must keep saying.
  group('density is drawn on both platforms', () {
    final swift = File(
      'ios/AllisWellWidget/AllisWellWidget.swift',
    ).readAsStringSync();
    final kotlin = File(
      'android/app/src/main/kotlin/com/alliswell/alliswell/TasksWidgetService.kt',
    ).readAsStringSync();

    test('iOS reads it, and tightens the gap — not the circle', () {
      expect(swift, contains('var isCompact: Bool { density == "compact" }'));
      expect(swift, contains('spacing: compact ? 1 : 4'));
      // W4: the circle's 28 pt frame is not conditional on anything.
      expect(swift, contains('.frame(width: 28, height: 28)'));
    });

    test('Android reads it, and sets both directions on recycled rows', () {
      expect(kotlin, contains('optString("density") == "compact"'));
      expect(kotlin, contains('dp(if (compact) 0 else 2)'));
    });
  });
}

/// A privacy setting that answers only when the test says so.
class _SlowPrivacy extends WidgetPrivacy {
  _SlowPrivacy(this.gate);

  final Completer<void> gate;

  @override
  Future<bool> build() async {
    await gate.future;
    return true;
  }
}
