import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState, Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/date_format.dart';
import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/core/persisted_prefs.dart';
import 'package:alliswell/src/features/projects/providers.dart';
import 'package:alliswell/src/features/tasks/data/task.dart';
import 'package:alliswell/src/features/tasks/providers.dart';
import 'package:alliswell/src/features/widgets/widget_bridge.dart';
import 'package:alliswell/src/features/widgets/widget_host.dart';
import 'package:alliswell/src/features/widgets/widget_snapshot.dart';
import 'package:alliswell/src/i18n/i18n.dart';

/// OPH-463 (#50, WIDGETS §3.2) — the fetch profile: what the iOS widget
/// extension needs to fetch its own days (`aw_widget_fetch_profile`). No
/// profile means the extension never fetches, so the profile follows
/// "Private widget"'s fail-closed rule (OPH-337): nothing is written until the
/// setting has been READ.
const secret = 'SECRET';

Task _task(String id, {DateTime? dueAt}) => Task(
  id: id,
  workspaceId: 'W1',
  title: '$secret $id',
  status: 'open',
  priority: 'none',
  timezone: 'Europe/Istanbul',
  isUrgent: false,
  requiresAcknowledgement: false,
  sortOrder: 0,
  revision: 1,
  dueAt: dueAt,
);

/// Records every write by key, and every removal.
class _KeyedHost implements WidgetHost, WidgetKeyRemover {
  final List<(String, String)> writes = [];
  final List<String> removed = [];
  int updates = 0;

  List<String> get keys => [for (final (key, _) in writes) key];

  Map<String, dynamic>? last(String key) {
    for (final (k, value) in writes.reversed) {
      if (k == key) return jsonDecode(value) as Map<String, dynamic>;
    }
    return null;
  }

  @override
  Future<void> configure() async {}

  @override
  Future<void> save(String key, String value) async => writes.add((key, value));

  @override
  Future<void> remove(String key) async => removed.add(key);

  @override
  Future<void> requestUpdate() async => updates++;
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

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 11, 12, 10);
  final tasks = [
    _task('today', dueAt: DateTime(2026, 11, 12, 14)),
    _task('someday'),
  ];
  const ws = '01WSAAAAAAAAAAAAAAAAAAAAAA';

  setUpAll(() => SharedPreferences.setMockInitialValues({}));

  setUp(() async {
    AwI18n.instance.setActiveCached(const Locale('en'));
    await localKv.remove(kWidgetPrivatePrefKey);
  });

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  group('the live app (iOS)', () {
    test(
      'profile is written only after Private widget has been read',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        final gate = Completer<void>();
        final host = _KeyedHost();
        final container = ProviderContainer(
          overrides: [
            openTasksProvider.overrideWith((ref) => Stream.value(tasks)),
            projectsByIdProvider.overrideWithValue(const {}),
            widgetHostProvider.overrideWithValue(host),
            widgetPrivateProvider.overrideWith(() => _SlowPrivacy(gate)),
            taskScopeProvider.overrideWith(
              (ref) async => TaskScope.workspace(ws),
            ),
            widgetFetchBaseUrlProvider.overrideWith(
              (ref) async => 'https://self.example.com/',
            ),
            widgetPendingOutboxProvider.overrideWith((ref) => Stream.value(2)),
          ],
        );
        addTearDown(container.dispose);
        container.listen(widgetSyncProvider, (_, _) {});
        // Kept alive the way the app keeps them: listened.
        container.listen(taskScopeProvider, (_, _) {});
        container.listen(widgetFetchBaseUrlProvider, (_, _) {});
        container.listen(widgetPendingOutboxProvider, (_, _) {});

        // Everything a profile needs has arrived — except the setting.
        await container.read(openTasksProvider.future);
        await container.read(taskScopeProvider.future);
        await container.read(widgetFetchBaseUrlProvider.future);
        await container.read(widgetPendingOutboxProvider.future);
        await pumpEventQueue();
        expect(
          host.keys,
          isNot(contains(kWidgetFetchProfileKey)),
          reason:
              'a profile is what lets the extension fetch: written on the '
              'default it would ask for titles the user has hidden',
        );

        gate.complete();
        await container.read(widgetPrivateProvider.future);
        await pumpEventQueue();
        final profile = host.last(kWidgetFetchProfileKey);
        expect(profile, isNotNull);
        expect(profile!['private'], isTrue);
        expect(profile['baseUrl'], 'https://self.example.com');
        expect(profile['scope'], {
          'workspaceIds': [ws],
        });
        expect(profile['pendingOutbox'], 2);
        // In the same publish as the snapshot, after it.
        expect(
          host.keys,
          containsAllInOrder([kWidgetSnapshotKey, kWidgetFetchProfileKey]),
        );
        for (final (_, value) in host.writes) {
          expect(value, isNot(contains(secret)));
        }
      },
    );

    test('no profile without a scope, and none off iOS', () async {
      Future<_KeyedHost> run({
        required TargetPlatform platform,
        TaskScope? scope,
      }) async {
        debugDefaultTargetPlatformOverride = platform;
        final host = _KeyedHost();
        final container = ProviderContainer(
          overrides: [
            openTasksProvider.overrideWith((ref) => Stream.value(tasks)),
            projectsByIdProvider.overrideWithValue(const {}),
            widgetHostProvider.overrideWithValue(host),
            widgetPrivateProvider.overrideWith(
              () => _SlowPrivacy(Completer<void>()..complete()),
            ),
            taskScopeProvider.overrideWith((ref) async => scope),
            widgetFetchBaseUrlProvider.overrideWith(
              (ref) async => 'https://api.example.com',
            ),
            widgetPendingOutboxProvider.overrideWith((ref) => Stream.value(0)),
          ],
        );
        addTearDown(container.dispose);
        container.listen(widgetSyncProvider, (_, _) {});
        // Kept alive the way the app keeps them: listened.
        container.listen(taskScopeProvider, (_, _) {});
        container.listen(widgetFetchBaseUrlProvider, (_, _) {});
        container.listen(widgetPendingOutboxProvider, (_, _) {});
        await container.read(openTasksProvider.future);
        await container.read(widgetPrivateProvider.future);
        await container.read(taskScopeProvider.future);
        await container.read(widgetFetchBaseUrlProvider.future);
        await container.read(widgetPendingOutboxProvider.future);
        await pumpEventQueue();
        return host;
      }

      final noScope = await run(platform: TargetPlatform.iOS);
      expect(noScope.keys, contains(kWidgetSnapshotKey));
      expect(noScope.keys, isNot(contains(kWidgetFetchProfileKey)));

      final android = await run(
        platform: TargetPlatform.android,
        scope: TaskScope.workspace(ws),
      );
      expect(android.keys, contains(kWidgetSnapshotKey));
      expect(android.keys, isNot(contains(kWidgetFetchProfileKey)));
    });
    test('going to the background keeps the outbox count sync left, not the '
        'one the last publish saw', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final host = _KeyedHost();
      final outbox = StreamController<int>();
      addTearDown(outbox.close);
      final container = ProviderContainer(
        overrides: [
          openTasksProvider.overrideWith((ref) => Stream.value(tasks)),
          projectsByIdProvider.overrideWithValue(const {}),
          widgetHostProvider.overrideWithValue(host),
          widgetPrivateProvider.overrideWith(
            () => _SlowPrivacy(Completer<void>()..complete()),
          ),
          taskScopeProvider.overrideWith(
            (ref) async => TaskScope.workspace(ws),
          ),
          widgetFetchBaseUrlProvider.overrideWith(
            (ref) async => 'https://api.example.com',
          ),
          widgetPendingOutboxProvider.overrideWith((ref) => outbox.stream),
        ],
      );
      addTearDown(container.dispose);
      container.listen(widgetSyncProvider, (_, _) {});
      container.listen(taskScopeProvider, (_, _) {});
      container.listen(widgetFetchBaseUrlProvider, (_, _) {});
      container.listen(widgetPendingOutboxProvider, (_, _) {});

      // One unsent note edit when the snapshot is published.
      outbox.add(1);
      await container.read(openTasksProvider.future);
      await container.read(widgetPrivateProvider.future);
      await container.read(taskScopeProvider.future);
      await container.read(widgetFetchBaseUrlProvider.future);
      await pumpEventQueue();
      expect(host.last(kWidgetFetchProfileKey)!['pendingOutbox'], 1);

      // Sync sends it: the profile alone is rewritten, no task changed.
      outbox.add(0);
      await pumpEventQueue();
      expect(host.last(kWidgetFetchProfileKey)!['pendingOutbox'], 0);

      // The way out republishes the same rows; the count must stay 0, or
      // the extension keeps preferring the local snapshot over the server.
      int snapshots() => host.keys.where((k) => k == kWidgetSnapshotKey).length;
      final before = snapshots();
      for (final state in const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        binding.handleAppLifecycleStateChanged(state);
      }
      await pumpEventQueue();
      expect(snapshots(), before + 1, reason: 'the background write');
      expect(host.last(kWidgetFetchProfileKey)!['pendingOutbox'], 0);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
  });

  group('the bridge', () {
    test(
      'profile carries scope, patterns, strings and pendingOutbox',
      () async {
        AwI18n.instance.setActiveCached(const Locale('tr'));
        final host = _KeyedHost();
        final written = DateTime.utc(2026, 11, 12, 7, 30);
        final bridge = WidgetBridge(host, clock: () => written);
        final scope = TaskScope.mine(['W1', 'W2'], 'U1');

        await bridge.publish(
          tasks,
          now: now,
          dateFormat: 'dmy_dot',
          hideTitles: false,
          fetch: WidgetFetchSource(
            baseUrl: ' https://api.alliswell.space// ',
            scope: scope,
            pendingOutbox: 3,
          ),
        );

        final profile = host.last(kWidgetFetchProfileKey)!;
        expect(profile['v'], 1);
        expect(profile['baseUrl'], 'https://api.alliswell.space');
        expect(profile['scope'], {
          'workspaceIds': ['W1', 'W2'],
          'mineFor': 'U1',
        });
        expect(profile['private'], isFalse);
        expect(profile['locale'], 'tr');
        expect(profile['patterns'], {
          'time': 'HH:mm',
          'day': 'd MMM',
          'dayYear': 'd MMM',
          'relativeDays': false,
        });
        expect(profile['strings'], {
          'bucket.overdue': 'widget.bucket.overdue'.tr(),
          'bucket.noDate': 'widget.bucket.noDate'.tr(),
          'bucket.today': 'widget.bucket.today'.tr(),
          'bucket.thisWeek': 'widget.bucket.thisWeek'.tr(),
          'bucket.thisMonth': 'widget.bucket.thisMonth'.tr(),
          'privateTitle': 'Gizli görev',
          'privateEvent': 'widget.privateEvent'.tr(),
          'allDay': 'widget.allDay'.tr(),
          'today': 'Bugün',
          'tomorrow': 'Yarın',
          'yesterday': 'Dün',
        });
        expect(profile['pendingOutbox'], 3);
        expect(profile['localWrittenAtMs'], written.millisecondsSinceEpoch);
        // No credential and no title rides in it.
        final raw = jsonEncode(profile);
        expect(raw, isNot(contains(secret)));
        expect(raw.toLowerCase(), isNot(contains('token')));

        // A sync push round changes the count only: the profile is rewritten,
        // its stamp still the snapshot's.
        await bridge.updatePendingOutbox(0);
        final after = host.last(kWidgetFetchProfileKey)!;
        expect(after['pendingOutbox'], 0);
        expect(after['localWrittenAtMs'], written.millisecondsSinceEpoch);
        expect(after['scope'], profile['scope']);
      },
    );

    test(
      'a count before any publish writes nothing; a publish uses it',
      () async {
        final host = _KeyedHost();
        final bridge = WidgetBridge(host, clock: () => now);
        await bridge.updatePendingOutbox(5);
        expect(host.writes, isEmpty);

        await bridge.publish(
          tasks,
          now: now,
          fetch: WidgetFetchSource(
            baseUrl: 'https://api.example.com',
            scope: TaskScope.workspace(ws),
          ),
        );
        expect(host.last(kWidgetFetchProfileKey)!['pendingOutbox'], 5);
      },
    );

    test('an unknown outbox count writes no profile', () async {
      final host = _KeyedHost();
      await WidgetBridge(host, clock: () => now).publish(
        tasks,
        now: now,
        fetch: WidgetFetchSource(
          baseUrl: 'https://api.example.com',
          scope: TaskScope.workspace(ws),
        ),
      );
      expect(host.keys, [kWidgetSnapshotKey]);
    });

    test('a new scope or privacy drops the server copy', () async {
      final host = _KeyedHost();
      final bridge = WidgetBridge(host, clock: () => now);
      Future<void> publish(TaskScope scope, {bool hide = false}) =>
          bridge.publish(
            tasks,
            now: now,
            hideTitles: hide,
            fetch: WidgetFetchSource(
              baseUrl: 'https://api.example.com',
              scope: scope,
              pendingOutbox: 0,
            ),
          );

      await publish(TaskScope.workspace('W1'));
      final first = host.removed.length;
      await publish(TaskScope.workspace('W1'));
      expect(host.removed.length, first, reason: 'nothing changed');

      await publish(TaskScope.workspace('W2'));
      expect(host.removed.length, first + 1);
      expect(host.removed.last, kWidgetServerSnapshotKey);

      await publish(TaskScope.workspace('W2'), hide: true);
      expect(host.removed.length, first + 2);
    });
  });

  group('patterns say what the rows say', () {
    // Pinned against the formatter the rows are written with, so the widget
    // extension and the app cannot word one date two ways.
    final samples = [
      DateTime(2026, 3, 7, 9, 5),
      DateTime(2026, 12, 31, 23, 59),
      DateTime(2027, 1, 2, 13, 0),
    ];

    for (final spec in kAwDateFormats) {
      for (final (language, region) in [
        ('en', 'US'),
        ('en', 'GB'),
        ('tr', 'TR'),
        ('ja', 'JP'),
      ]) {
        test('${spec.id} in $language-$region', () {
          AwI18n.instance.setActiveCached(Locale(language));
          final p = widgetDatePatterns(
            format: spec.id,
            locale: language,
            region: region,
          );
          for (final at in samples) {
            final view = DateTime(2026, 11, 12, 10);
            final pattern = at.year == view.year ? p.day : p.dayYear;
            expect(
              DateFormat(pattern, language).format(at),
              awFormatShort(
                at,
                format: spec.id,
                locale: language,
                region: region,
                now: view,
                withTime: false,
              ),
            );
            expect(
              DateFormat(p.time, language).format(at),
              awFormatTime(
                at,
                format: spec.id,
                locale: language,
                region: region,
              ),
            );
          }
          expect(p.relativeDays, spec.id == kAwSystemDateFormat);
        });
      }
    }
  });
}
