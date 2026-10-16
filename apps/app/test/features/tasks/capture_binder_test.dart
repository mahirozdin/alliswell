import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/core/day_boundary.dart';
import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/tasks/data/capture_inbox.dart';
import 'package:alliswell/src/features/tasks/providers.dart';
import 'package:alliswell/src/features/tasks/ui/task_detail_screen.dart';
import 'package:alliswell/src/features/workspaces/workspaces.dart';
import 'package:alliswell/src/i18n/i18n.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/fake_capture_inbox.dart';
import '../../support/sync_overrides.dart';

/// OPH-376 — "Hey Siri, add a task in AllisWell". The App Intent parks the
/// words in a mailbox and brings the app forward; these drive the Dart half:
/// the binder drains the mailbox through the Inbox quick-add rule, HomeShell
/// confirms with a SnackBar (or opens today), and nothing is read twice.

/// Saturday 17 October 2026, 10:00.
final _now = DateTime(2026, 10, 17, 10);

Future<Widget> _app(FakeApi api, FakeCaptureInbox inbox) async {
  SharedPreferences.setMockInitialValues({});
  final store = InMemorySecretStore();
  await TokenStorage(store).save(fakeSession());
  return ProviderScope(
    retry: awRetry,
    overrides: [
      ...syncTestOverrides(captureInbox: inbox),
      secretStoreProvider.overrideWithValue(store),
      apiClientProvider.overrideWithValue(
        fakeDio(FakeHttpClientAdapter(api.handle)),
      ),
      nowProvider.overrideWithValue(() => _now),
    ],
    child: const AllisWellApp(),
  );
}

Future<void> _wide(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

DateTime _local(Object? iso) => DateTime.parse(iso as String).toLocal();

String _wall(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')} '
    '${d.hour.toString().padLeft(2, '0')}:'
    '${d.minute.toString().padLeft(2, '0')}';

AwCapture _add(String id, String text) =>
    AwCapture(id: id, kind: AwCaptureKind.add, text: text);

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));

void main() {
  setUp(() => localKv.remove('alliswell_default_task_time'));

  for (final brightness in Brightness.values) {
    testWidgets('a dated request becomes a dated task and a SnackBar '
        '(${brightness.name})', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await _wide(tester);
      final api = FakeApi();
      final inbox = FakeCaptureInbox(
        pending: [_add('a', "yarın saat 9'da kira #ev")],
      );
      addTearDown(inbox.dispose);
      await tester.pumpWidget(await _app(api, inbox));
      await tester.pumpAndSettle();

      final task = api.tasks.single;
      expect(task['title'], 'kira');
      expect(_wall(_local(task['dueAt'])), '2026-10-18 09:00');
      expect(_wall(_local(task['remindAt'])), '2026-10-18 08:00');
      expect(task['isUrgent'], true, reason: 'the quick-add defaults apply');
      expect(api.tags.single['name'], 'ev');
      expect(task['tagIds'], [api.tags.single['id']]);
      expect(inbox.pending, isEmpty);

      final bar = find.byKey(Key('capture-added-${task['id']}'));
      expect(bar, findsOneWidget);
      expect(
        find.descendant(of: bar, matching: find.textContaining('Added: kira')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: bar, matching: find.text('Open')),
        findsOneWidget,
      );
      expect(
        Theme.of(tester.element(bar)).brightness,
        brightness,
        reason: 'the confirmation is the theme SnackBar in both themes',
      );
    });
  }

  testWidgets('a dateless request lands in the Inbox; Open shows the task', (
    tester,
  ) async {
    await _wide(tester);
    final api = FakeApi();
    final inbox = FakeCaptureInbox(pending: [_add('b', 'süt al')]);
    addTearDown(inbox.dispose);
    await tester.pumpWidget(await _app(api, inbox));
    await tester.pumpAndSettle();

    final task = api.tasks.single;
    expect(task['title'], 'süt al');
    expect(task['status'], 'inbox');
    expect(task['dueAt'], isNull);
    expect(find.text('Added to Inbox: süt al'), findsOneWidget);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(TaskDetailScreen), findsOneWidget);
  });

  testWidgets('English words parse in a Turkish UI', (tester) async {
    await AwI18n.instance.setLocale(const Locale('tr'));
    addTearDown(() => AwI18n.instance.setLocale(const Locale('en')));
    await _wide(tester);
    final api = FakeApi();
    final inbox = FakeCaptureInbox(
      pending: [_add('c', 'tomorrow at 9am pay rent')],
    );
    addTearDown(inbox.dispose);
    await tester.pumpWidget(await _app(api, inbox));
    await tester.pumpAndSettle();

    final task = api.tasks.single;
    expect(task['title'], 'pay rent');
    expect(_wall(_local(task['dueAt'])), '2026-10-18 09:00');
    expect(find.textContaining('Eklendi: pay rent'), findsOneWidget);
  });

  testWidgets('"Show today" selects today on Home', (tester) async {
    await _wide(tester);
    final api = FakeApi();
    final inbox = FakeCaptureInbox();
    addTearDown(inbox.dispose);
    await tester.pumpWidget(await _app(api, inbox));
    await tester.pumpAndSettle();
    final container = _container(tester);
    container.read(selectedDayProvider.notifier).select(DateTime(2026, 10, 1));
    await tester.pumpAndSettle();

    inbox.deliver(const AwCapture(id: 't', kind: AwCaptureKind.today));
    await tester.pumpAndSettle();
    expect(container.read(selectedDayProvider), DateTime(2026, 10, 17));
    expect(api.tasks, isEmpty);
  });

  testWidgets('a warm request and a resume together make ONE task', (
    tester,
  ) async {
    await _wide(tester);
    final api = FakeApi();
    final inbox = FakeCaptureInbox();
    addTearDown(inbox.dispose);
    await tester.pumpWidget(await _app(api, inbox));
    await tester.pumpAndSettle();
    final before = inbox.takes;

    inbox.deliver(_add('d', 'çiçekleri sula'));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(
      api.tasks.where((t) => t['title'] == 'çiçekleri sula'),
      hasLength(1),
    );
    expect(inbox.takes, greaterThan(before));
    expect(find.text('Added to Inbox: çiçekleri sula'), findsOneWidget);
  });

  test('without a workspace the mailbox is not touched, then drains', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final inbox = FakeCaptureInbox(
      pending: [const AwCapture(id: 't', kind: AwCaptureKind.today)],
    );
    addTearDown(inbox.dispose);
    final workspace = _TestWorkspace();
    final container = ProviderContainer(
      overrides: [
        captureInboxProvider.overrideWithValue(inbox),
        activeWorkspaceIdProvider.overrideWith(
          (ref) async => ref.watch(workspace.provider),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(captureBinderProvider);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(inbox.takes, 0, reason: 'signed in nowhere: the request waits');
    expect(inbox.pending, hasLength(1));

    container.read(workspace.provider.notifier).set('ws-1');
    await container.read(activeWorkspaceIdProvider.future);
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(inbox.takes, 1);
    expect(inbox.pending, isEmpty);
    expect(
      container.read(pendingCaptureOutcomesProvider).single,
      isA<CaptureShowToday>(),
    );
  });
}

class _TestWorkspace {
  final provider = NotifierProvider<_Holder, String?>(_Holder.new);
}

class _Holder extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? value) => state = value;
}
