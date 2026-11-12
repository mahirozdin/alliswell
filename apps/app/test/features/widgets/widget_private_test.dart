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
import 'package:alliswell/src/features/calendar/providers.dart';
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

import 'ios_widget_swift.dart';
import 'widget_app_group_fake.dart';

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
          scope: TaskScope.workspace(ws),
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
        scope: TaskScope.workspace(ws),
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

  // #50, PR2-04: in the running app the switch changed nothing in the App
  // Group, in either direction, until the next launch. Settings is a page
  // pushed over the shell, and a covered screen's watched providers are
  // paused (Riverpod 3 pauses a widget's `watch` while TickerMode is off) —
  // so the widget sync, watched by the shell, never saw the new value, and
  // the move to the background wrote the old one again.
  group('the switch takes effect at once, with Settings over the shell', () {
    const ws = '01WSAAAAAAAAAAAAAAAAAAAAAA';
    late FakeHomeWidgetChannel plugin;

    setUp(() => plugin = FakeHomeWidgetChannel()..install());
    tearDown(() => plugin.uninstall());

    /// A titled answer the extension stored for the profile before the
    /// switch.
    void storeTitledEnvelope() =>
        plugin.values[kWidgetServerSnapshotKey] = jsonEncode({
          'fetchedAtMs': 1,
          'etag': 'e1',
          'query': 'private=0',
          'body': {'title': '$secret from the server'},
        });

    Map<String, dynamic> stored(String key) =>
        jsonDecode(plugin.values[key]! as String) as Map<String, dynamic>;

    /// The app as it runs: the shell keeps the widget sync, and Settings ›
    /// General is pushed over it.
    Future<void> pumpShellUnderSettings(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1000, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            openTasksProvider.overrideWith((ref) => Stream.value(tasks)),
            projectsByIdProvider.overrideWithValue(const {}),
            externalEventsProvider.overrideWith(
              (ref) => Stream.value(const []),
            ),
            taskScopeProvider.overrideWith(
              (ref) async => TaskScope.workspace(ws),
            ),
            widgetFetchBaseUrlProvider.overrideWith(
              (ref) async => 'https://api.example.com',
            ),
            widgetPendingOutboxProvider.overrideWith((ref) => Stream.value(0)),
          ],
          child: MaterialApp(
            navigatorKey: navigator,
            theme: buildAwTheme(Brightness.light),
            home: const _Shell(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      unawaited(
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const SettingsGeneralScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> toggle(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('settings-widget-private')));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'turning private on rewrites the profile, removes the server envelope '
      'and republishes at once',
      (tester) async {
        await pumpShellUnderSettings(tester);
        expect(stored(kWidgetFetchProfileKey)['private'], isFalse);
        expect(plugin.values[kWidgetSnapshotKey], contains(secret));
        storeTitledEnvelope();
        plugin.log.clear();

        await toggle(tester);

        // In this order: the new profile (the extension refuses an answer
        // for another query from then on), the stored answer gone, the
        // snapshot title-free, and only then a redraw — the widget is never
        // asked to draw before every title is gone.
        expect(plugin.log.take(4), [
          kWidgetFetchProfileKey,
          kWidgetServerSnapshotKey,
          kWidgetSnapshotKey,
          'update',
        ]);
        expect(stored(kWidgetFetchProfileKey)['private'], isTrue);
        expect(plugin.isAbsent(kWidgetServerSnapshotKey), isTrue);
        for (final value in plugin.values.values) {
          expect(value, isNot(contains(secret)));
        }

        // The write on the way out keeps the new mode: no title comes back
        // when the app leaves the screen, nor when it returns.
        plugin.log.clear();
        for (final state in [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
          AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(state);
          await tester.pumpAndSettle();
        }
        expect(plugin.log, contains(kWidgetSnapshotKey));
        for (final value in plugin.values.values) {
          expect(value, isNot(contains(secret)));
        }

        // Off again: the titles are back at once, and the private answer the
        // extension stored is dropped too — it would draw placeholders.
        plugin.values[kWidgetServerSnapshotKey] = '{"query":"private=1"}';
        await toggle(tester);
        expect(stored(kWidgetFetchProfileKey)['private'], isFalse);
        expect(plugin.isAbsent(kWidgetServerSnapshotKey), isTrue);
        expect(plugin.values[kWidgetSnapshotKey], contains(secret));
        expect(plugin.log.last, 'update');
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );

    testWidgets('a new language or date format republishes at once too', (
      tester,
    ) async {
      await pumpShellUnderSettings(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SettingsGeneralScreen)),
      );
      expect(stored(kWidgetFetchProfileKey)['locale'], 'en');

      plugin.log.clear();
      AwI18n.instance.setActiveCached(const Locale('tr'));
      await tester.pumpAndSettle();
      expect(stored(kWidgetFetchProfileKey)['locale'], 'tr');
      expect(plugin.log, containsAllInOrder([kWidgetSnapshotKey, 'update']));
      // A language is not a new query: the server's answer stays.
      expect(plugin.log, isNot(contains(kWidgetServerSnapshotKey)));

      await container.read(dateFormatProvider.notifier).set('dmy_dot');
      await tester.pumpAndSettle();
      expect(
        stored(kWidgetFetchProfileKey)['patterns'],
        containsPair('relativeDays', false),
      );
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    test('the shell keeps the widget sync live, not watched', () {
      final shell = File('lib/src/screens/home_shell.dart').readAsStringSync();
      expect(shell.contains('keepWidgetSyncLive(ref);'), isTrue);
      expect(
        shell.contains('ref.watch(widgetSyncProvider)'),
        isFalse,
        reason: 'a watch is paused while a page covers the shell',
      );
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
    final swift = readIosWidgetSwift();
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

/// The shell as the app keeps it: it holds the widget sync while pages are
/// pushed over it.
class _Shell extends ConsumerWidget {
  const _Shell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    keepWidgetSyncLive(ref);
    return const Scaffold(body: SizedBox.expand());
  }
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
