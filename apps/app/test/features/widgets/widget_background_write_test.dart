import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/core/persisted_prefs.dart';
import 'package:alliswell/src/features/projects/providers.dart';
import 'package:alliswell/src/features/tasks/data/task.dart';
import 'package:alliswell/src/features/tasks/providers.dart';
import 'package:alliswell/src/features/widgets/widget_bridge.dart';
import 'package:alliswell/src/features/widgets/widget_host.dart';
import 'package:alliswell/src/i18n/i18n.dart';

import '../../support/fake_widget_host.dart';

/// OPH-438 (#50) — the last fresh write happens on the way out. While the app
/// is in front, every widget reload is outside WidgetKit's budget; once it is
/// in the background, the widget only moves when the OS grants it a reload.
/// So the moment the app leaves the screen, the live graph writes the snapshot
/// once more (a fresh `now`, the same rows) and asks for a reload — the widget
/// is never older than the last app session.
Task _task(String id, {DateTime? dueAt}) => Task(
  id: id,
  workspaceId: 'W1',
  title: 'Task $id',
  status: 'open',
  priority: 'high',
  timezone: 'Europe/Istanbul',
  isUrgent: false,
  requiresAcknowledgement: false,
  sortOrder: 0,
  revision: 1,
  dueAt: dueAt,
);

class _OpenPrivacy extends WidgetPrivacy {
  @override
  Future<bool> build() async => false;
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => SharedPreferences.setMockInitialValues({}));

  setUp(() async {
    AwI18n.instance.setActiveCached(const Locale('en'));
    await localKv.remove(kWidgetPrivatePrefKey);
    await localKv.remove(kWidgetCompactPrefKey);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  void go(List<AppLifecycleState> states) {
    for (final state in states) {
      binding.handleAppLifecycleStateChanged(state);
    }
  }

  const toBackground = [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ];
  const toForeground = [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ];

  Future<FakeWidgetHost> live() async {
    final host = FakeWidgetHost();
    final container = ProviderContainer(
      overrides: [
        openTasksProvider.overrideWith(
          (ref) => Stream.value([
            _task('a', dueAt: DateTime.now().add(const Duration(hours: 1))),
            _task('b'),
          ]),
        ),
        projectsByIdProvider.overrideWithValue(const {}),
        widgetHostProvider.overrideWithValue(host),
        widgetPrivateProvider.overrideWith(_OpenPrivacy.new),
      ],
    );
    addTearDown(container.dispose);
    container.listen(widgetSyncProvider, (_, _) {});
    await container.read(openTasksProvider.future);
    await container.read(widgetPrivateProvider.future);
    await pumpEventQueue();
    return host;
  }

  test(
    'going to the background writes the snapshot and requests a widget reload',
    () async {
      final host = await live();
      expect(host.saved, isNotEmpty, reason: 'the foreground publish');
      final saves = host.saved.length;
      final updates = host.updates;

      go(toBackground);
      await pumpEventQueue();
      expect(
        host.saved.length,
        saves + 1,
        reason:
            'one write per trip out — hidden and paused both arrive, '
            'the snapshot is written once',
      );
      expect(host.updates, updates + 1);
      expect(host.lastSaved, contains('Task a'));

      // Back in front and out again: the next trip writes again.
      go(toForeground);
      await pumpEventQueue();
      expect(host.saved.length, saves + 1, reason: 'resuming writes nothing');
      go(toBackground);
      await pumpEventQueue();
      expect(host.saved.length, saves + 2);
      expect(host.updates, updates + 2);
      go(toForeground);
    },
  );

  test('inactive alone (a sheet, a call banner) writes nothing', () async {
    final host = await live();
    final saves = host.saved.length;
    go([AppLifecycleState.inactive]);
    await pumpEventQueue();
    expect(host.saved.length, saves);
    go([AppLifecycleState.resumed]);
  });
}
