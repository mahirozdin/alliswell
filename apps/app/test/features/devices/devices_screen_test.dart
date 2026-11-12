import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/features/devices/data/device_api.dart';
import 'package:alliswell/src/features/devices/device_registry.dart';
import 'package:alliswell/src/features/devices/devices_screen.dart';
import 'package:alliswell/src/features/devices/providers.dart';
import 'package:alliswell/src/features/workspaces/workspaces.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/notifications/device_gate.dart';
import 'package:alliswell/src/sync/providers.dart';
import 'package:alliswell/src/theme/theme.dart';

/// OPH-448 (#48) — Settings ▸ Devices: which of my installs ring urgent
/// alarms, and a switch per device that the server keeps.
const _thisId = '01HZTHISDEVICEAAAAAAAAAAAA';
const _macId = '01HZMACAAAAAAAAAAAAAAAAAAA';
const _webId = '01HZWEBAAAAAAAAAAAAAAAAAAA';
const _oldId = '01HZOLDAAAAAAAAAAAAAAAAAAA';

Map<String, dynamic> _row(
  String id,
  String platform,
  String? name,
  Duration seenAgo, {
  bool? ringsUrgent,
  bool hasSession = true,
}) => {
  'id': id,
  'platform': platform,
  'deviceName': name,
  'lastSeenAt': DateTime.now().toUtc().subtract(seenAgo).toIso8601String(),
  'createdAt': '2026-11-01T08:00:00.000Z',
  'ringsUrgent': ?ringsUrgent,
  if (ringsUrgent != null) 'ringsUrgentSource': 'auto',
  'hasSession': hasSession,
};

/// Four rows, in the order a server might return them: not the order the
/// screen shows them in.
List<Map<String, dynamic>> _rows({
  bool withFlag = true,
  bool macRings = false,
  bool thisRings = true,
  bool webHasSession = true,
}) => [
  _row(
    _webId,
    'web',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
    const Duration(days: 3),
    ringsUrgent: withFlag ? false : null,
    hasSession: webHasSession,
  ),
  _row(
    _oldId,
    'android',
    'Old phone',
    const Duration(days: 200),
    ringsUrgent: withFlag ? false : null,
  ),
  _row(
    _macId,
    'macos',
    'MacBook Air',
    const Duration(hours: 2),
    ringsUrgent: withFlag ? macRings : null,
  ),
  _row(
    _thisId,
    'ios',
    'Dart/3.13 (dart:io)',
    const Duration(minutes: 1),
    ringsUrgent: withFlag ? thisRings : null,
  ),
];

class _FakeApi implements DeviceApi {
  _FakeApi(this.rows);

  List<Map<String, dynamic>> rows;
  bool offline = false;
  bool failPatch = false;
  Completer<void>? patchGate;

  /// What a heartbeat (the register PUT) answers for this device, and a gate
  /// that holds the answer on the wire.
  bool? registerRings;
  Completer<void>? registerGate;
  final List<(String, bool?)> patches = [];
  final List<(String, String)> names = [];
  final List<String> deleted = [];

  /// How many times the list was asked for.
  int listCalls = 0;

  @override
  Future<List<DeviceInfo>> list() async {
    listCalls++;
    if (offline) {
      throw DioException(
        requestOptions: RequestOptions(path: '/api/v1/notification-devices'),
        type: DioExceptionType.connectionError,
      );
    }
    return [for (final row in rows) DeviceInfo.fromJson(row)];
  }

  @override
  Future<DevicePatchResult> patch(
    String deviceId, {
    bool? ringsUrgent,
    String? deviceName,
  }) async {
    if (ringsUrgent != null) patches.add((deviceId, ringsUrgent));
    if (deviceName != null) names.add((deviceId, deviceName));
    await patchGate?.future;
    if (failPatch) {
      throw DioException(
        requestOptions: RequestOptions(path: '/api/v1/notification-devices'),
        response: Response(
          requestOptions: RequestOptions(path: ''),
          statusCode: 500,
        ),
        type: DioExceptionType.badResponse,
      );
    }
    final row = rows.firstWhere((r) => r['id'] == deviceId);
    if (ringsUrgent != null) row['ringsUrgent'] = ringsUrgent;
    if (deviceName != null) row['deviceName'] = deviceName;
    final ringing = rows.where((r) => r['ringsUrgent'] == true).length;
    return DevicePatchResult(
      device: DeviceInfo.fromJson({...row, 'ringsUrgentSource': 'user'}),
      warnings: [if (ringing == 0) 'NO_URGENT_DEVICE'],
    );
  }

  @override
  Future<DeviceInfo?> register(String deviceId, DeviceDescriptor device) async {
    final answer = registerRings;
    await registerGate?.future;
    return DeviceInfo.fromJson({
      'id': deviceId,
      'platform': device.platform,
      'ringsUrgent': ?answer,
    });
  }

  /// The server's DELETE (ADR-0069 §6): revokes the device's session, drops
  /// the row and, when that was the last ringing one, promotes the most
  /// recently seen non-web device.
  @override
  Future<void> unregister(String deviceId) async {
    deleted.add(deviceId);
    final removed = rows.firstWhere((r) => r['id'] == deviceId);
    rows = [
      for (final r in rows)
        if (r['id'] != deviceId) r,
    ];
    if (removed['ringsUrgent'] != true) return;
    if (rows.any((r) => r['ringsUrgent'] == true)) return;
    final candidates = [
      for (final r in rows)
        if (r['platform'] != 'web') r,
    ]..sort((a, b) => (b['lastSeenAt'] as String).compareTo(a['lastSeenAt']));
    if (candidates.isNotEmpty) candidates.first['ringsUrgent'] = true;
  }

  @override
  Future<PushKeyLookup> lookupPushKey() async => const PushKeyLookup.unknown();
}

class _MemoryKv implements LocalKv {
  final Map<String, String> values = {};

  @override
  Future<String?> get(String key) async => values[key];

  @override
  Future<void> set(String key, String value) async => values[key] = value;

  @override
  Future<void> remove(String key) async => values.remove(key);

  @override
  Future<void> removeWhere(bool Function(String key) test) async =>
      values.removeWhere((key, _) => test(key));
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  _FakeApi api, {
  Widget? child,
  _MemoryKv? kv,
  Future<void> Function(BuildContext, WidgetRef)? signOut,
}) async {
  child ??= DevicesScreen(signOut: signOut);
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = RingsUrgentStore(kv: kv ?? _MemoryKv());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        deviceApiProvider.overrideWithValue(api),
        currentUserIdProvider.overrideWithValue('user-1'),
        syncClientIdProvider.overrideWith((ref) => Stream.value(_thisId)),
        ringsUrgentStoreProvider.overrideWithValue(store),
      ],
      child: MaterialApp(
        theme: buildAwTheme(Brightness.light),
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byWidget(child)));
}

/// Stands in for Home: its card and band (OPH-453) keep the device list alive
/// for the whole session, and Settings opens the Devices screen on top.
class _HomeHoldingTheList extends ConsumerWidget {
  const _HomeHoldingTheList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(devicesProvider).value?.devices.length;
    return Scaffold(
      key: const Key('test-home'),
      body: TextButton(
        key: const Key('test-open-devices'),
        onPressed: () => context.push('/settings/devices'),
        child: Text('devices: $count'),
      ),
    );
  }
}

/// The app's way in: a router, so the screen can be opened by its address
/// (a web reload on /settings/devices) or pushed from Home.
Future<ProviderContainer> _pumpRouted(
  WidgetTester tester,
  _FakeApi api, {
  String initialLocation = '/settings/devices',
}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/home',
        builder: (context, state) => const _HomeHoldingTheList(),
      ),
      GoRoute(
        path: '/settings/devices',
        builder: (context, state) => const DevicesScreen(),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        deviceApiProvider.overrideWithValue(api),
        currentUserIdProvider.overrideWithValue('user-1'),
        syncClientIdProvider.overrideWith((ref) => Stream.value(_thisId)),
        ringsUrgentStoreProvider.overrideWithValue(
          RingsUrgentStore(kv: _MemoryKv()),
        ),
      ],
      child: MaterialApp.router(
        theme: buildAwTheme(Brightness.light),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(Router<Object>)));
}

Future<void> _openSheet(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(Key('device-top-$id')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('device-detail-sheet')), findsOneWidget);
}

Switch _switchOf(WidgetTester tester, String id) =>
    tester.widget<Switch>(find.byKey(Key('device-switch-$id')));

double _top(WidgetTester tester, String id) =>
    tester.getTopLeft(find.byKey(Key('device-card-$id'))).dy;

/// The app goes to the background and comes back, through every state the
/// engine reports on the way.
Future<void> _backAndForth(WidgetTester tester) async {
  for (final state in const [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'lists this device first with its badge, then the others by last seen',
    (tester) async {
      await _pump(tester, _FakeApi(_rows()));

      // Readable names, never a raw User-Agent.
      expect(find.text('iPhone'), findsOneWidget);
      expect(find.text('MacBook Air'), findsOneWidget);
      expect(find.text('Chrome · Windows'), findsOneWidget);
      expect(find.textContaining('Dart/'), findsNothing);
      expect(find.textContaining('Mozilla/'), findsNothing);

      // This device is marked, and only this one.
      expect(
        find.descendant(
          of: find.byKey(const Key('device-card-$_thisId')),
          matching: find.byKey(const Key('device-this-badge')),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('device-this-badge')), findsOneWidget);
      expect(
        find.text('iOS · ${'settings.devices.activeNow'.tr()}'),
        findsOneWidget,
      );

      // This device, then the others newest first.
      expect(_top(tester, _thisId), lessThan(_top(tester, _macId)));
      expect(_top(tester, _macId), lessThan(_top(tester, _webId)));

      // A device unseen for > 90 days is folded away until asked for.
      expect(find.byKey(const Key('device-card-$_oldId')), findsNothing);
      final fold = find.byKey(const Key('devices-stale-toggle'));
      expect(fold, findsOneWidget);
      expect(
        find.text('settings.devices.stale'.tr(args: {'count': '1'})),
        findsOneWidget,
      );
      await tester.tap(fold);
      await tester.pumpAndSettle();
      expect(find.text('Old phone'), findsOneWidget);
      expect(_top(tester, _webId), lessThan(_top(tester, _oldId)));

      // The web row is a tab, and says what that means.
      expect(find.text('settings.devices.ringSwitchWeb'.tr()), findsOneWidget);
      expect(find.text('settings.devices.webHint'.tr()), findsOneWidget);

      // Touch targets: the switch row ≥ 48, the top region ≥ 56.
      expect(
        tester
            .getSize(find.byKey(const Key('device-switch-row-$_macId')))
            .height,
        greaterThanOrEqualTo(48),
      );
      expect(
        tester.getSize(find.byKey(const Key('device-top-$_macId'))).height,
        greaterThanOrEqualTo(56),
      );
    },
  );

  testWidgets('toggle patches the server and caches the flag for this device', (
    tester,
  ) async {
    final api = _FakeApi(_rows());
    final kv = _MemoryKv();
    final container = await _pump(tester, api, kv: kv);

    // Another device on: the server is told, nothing local changes.
    expect(_switchOf(tester, _macId).value, isFalse);
    final gateBefore = kv.values[kRingsUrgentKey];
    api.patchGate = Completer<void>();
    await tester.tap(find.byKey(const Key('device-switch-$_macId')));
    await tester.pump();
    // Optimistic, with a small progress ring while the server answers.
    expect(_switchOf(tester, _macId).value, isTrue);
    expect(find.byKey(const Key('device-saving-$_macId')), findsOneWidget);
    api.patchGate!.complete();
    api.patchGate = null;
    await tester.pumpAndSettle();
    expect(api.patches, [(_macId, true)]);
    expect(find.byKey(const Key('device-saving-$_macId')), findsNothing);
    expect(_switchOf(tester, _macId).value, isTrue);
    expect(kv.values[kRingsUrgentKey], gateBefore);
    // Two ringing devices: what that means is said once, under the intro
    // (X-06) — not as a long second line under every ringing row.
    final multi = find.text(
      'settings.devices.multiHint'.tr(args: {'count': '2'}),
    );
    expect(multi, findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('devices-intro')),
        matching: multi,
      ),
      findsOneWidget,
    );
    for (final id in [_thisId, _macId]) {
      expect(
        find.descendant(
          of: find.byKey(Key('device-switch-row-$id')),
          matching: multi,
        ),
        findsNothing,
      );
    }

    // This device off: the server is told AND the alarm gate here follows.
    await tester.tap(find.byKey(const Key('device-switch-$_thisId')));
    await tester.pumpAndSettle();
    expect(api.patches.last, (_thisId, false));
    expect(kv.values[kRingsUrgentKey], RingsUrgentHere.off.name);
    expect(
      await container.read(ringsUrgentHereProvider.future),
      RingsUrgentHere.off,
    );
    expect(_switchOf(tester, _thisId).value, isFalse);
    expect(find.text('settings.devices.offHint'.tr()), findsWidgets);
  });

  // listed-flag-does-not-update-gate: the list is the server's answer for
  // this device too. A switch turned elsewhere since the last heartbeat must
  // reach this device's alarm gate when the list shows it, not only at the
  // next launch or resume.
  testWidgets('the list carries a switch changed elsewhere to this device\'s '
      'alarm gate', (tester) async {
    final kv = _MemoryKv()..values[kRingsUrgentKey] = RingsUrgentHere.on.name;
    final api = _FakeApi(_rows(thisRings: false, macRings: true));
    final container = await _pump(tester, api, kv: kv);
    final gate = container.listen(ringsUrgentHereProvider, (_, _) {});
    addTearDown(gate.close);
    await tester.pumpAndSettle();

    expect(_switchOf(tester, _thisId).value, isFalse);
    expect(kv.values[kRingsUrgentKey], RingsUrgentHere.off.name);
    expect(gate.read().value, RingsUrgentHere.off);

    // And back: switched on elsewhere, read again on the next list.
    api.rows = _rows(thisRings: true);
    container.invalidate(devicesProvider);
    await tester.pumpAndSettle();
    expect(_switchOf(tester, _thisId).value, isTrue);
    expect(kv.values[kRingsUrgentKey], RingsUrgentHere.on.name);
    expect(gate.read().value, RingsUrgentHere.on);
  });

  // late-heartbeat-overwrites-switch: a heartbeat that left before this
  // device was switched off answers with the old value; it must not switch
  // the gate back on under an off switch.
  testWidgets('a heartbeat older than this device\'s switch change does not '
      'undo it', (tester) async {
    final api = _FakeApi(_rows(macRings: true))
      ..registerRings = true
      ..registerGate = Completer<void>();
    final kv = _MemoryKv();
    final container = await _pump(tester, api, kv: kv);
    final registry = DeviceRegistry(
      api: api,
      readClientId: () async => _thisId,
      describe: () => const DeviceDescriptor(
        platform: 'ios',
        appVersion: '1',
        locale: 'en',
      ),
      ringsUrgent: container.read(ringsUrgentStoreProvider),
      onRingsUrgentChanged: () => container.invalidate(ringsUrgentHereProvider),
    );
    final heartbeat = registry.sync(signedIn: true);
    await tester.pump();

    await tester.tap(find.byKey(const Key('device-switch-$_thisId')));
    await tester.pumpAndSettle();
    expect(api.patches, [(_thisId, false)]);
    expect(kv.values[kRingsUrgentKey], RingsUrgentHere.off.name);

    api.registerGate!.complete();
    await tester.pumpAndSettle();
    await heartbeat;
    expect(kv.values[kRingsUrgentKey], RingsUrgentHere.off.name);
    expect(
      await container.read(ringsUrgentHereProvider.future),
      RingsUrgentHere.off,
    );
    expect(_switchOf(tester, _thisId).value, isFalse);
  });

  testWidgets('a failed toggle reverts and says so', (tester) async {
    final api = _FakeApi(_rows())..failPatch = true;
    final kv = _MemoryKv();
    await _pump(tester, api, kv: kv);

    await tester.tap(find.byKey(const Key('device-switch-$_thisId')));
    await tester.pumpAndSettle();
    // The only ringing device: the warning comes first (OPH-449).
    await tester.tap(find.byKey(const Key('devices-last-off-confirm')));
    await tester.pumpAndSettle();

    expect(api.patches, [(_thisId, false)]);
    expect(_switchOf(tester, _thisId).value, isTrue);
    expect(find.text('settings.devices.saveFailed'.tr()), findsOneWidget);
    // Nothing the server did not confirm reaches the local gate: it keeps
    // what the list said.
    expect(kv.values[kRingsUrgentKey], RingsUrgentHere.on.name);
  });

  testWidgets('an old server hides the switches and explains why', (
    tester,
  ) async {
    await _pump(tester, _FakeApi(_rows(withFlag: false)));

    expect(find.byType(Switch), findsNothing);
    expect(find.text('settings.devices.unsupported'.tr()), findsOneWidget);
    // The list itself still shows.
    expect(find.text('iPhone'), findsOneWidget);
    expect(find.text('MacBook Air'), findsOneWidget);
  });

  testWidgets('offline shows the cached list with inactive switches', (
    tester,
  ) async {
    final api = _FakeApi(_rows());
    final container = await _pump(tester, api);
    expect(find.byKey(const Key('devices-offline')), findsNothing);

    api.offline = true;
    container.invalidate(devicesProvider);
    await tester.pumpAndSettle();

    expect(find.text('MacBook Air'), findsOneWidget);
    expect(find.text('settings.devices.offline'.tr()), findsOneWidget);
    expect(_switchOf(tester, _macId).onChanged, isNull);
    expect(_switchOf(tester, _thisId).onChanged, isNull);
    await tester.tap(find.byKey(const Key('device-switch-$_macId')));
    await tester.pumpAndSettle();
    expect(api.patches, isEmpty);
  });

  testWidgets('offline with nothing cached is an error with a retry', (
    tester,
  ) async {
    final api = _FakeApi(_rows())..offline = true;
    await _pump(tester, api);
    expect(find.byType(Switch), findsNothing);
    final retry = find.text('common.retry'.tr());
    expect(retry, findsOneWidget);

    api.offline = false;
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(find.text('MacBook Air'), findsOneWidget);
  });

  testWidgets('a single device says where others will appear', (tester) async {
    await _pump(tester, _FakeApi([_rows().last]));
    expect(find.text('iPhone'), findsOneWidget);
    expect(_switchOf(tester, _thisId).value, isTrue);
    expect(find.text('settings.devices.single'.tr()), findsOneWidget);
    expect(find.text('settings.devices.sectionOther'.tr()), findsNothing);
  });

  testWidgets('the settings row subtitle names the ringing device', (
    tester,
  ) async {
    final api = _FakeApi(_rows());
    final container = await _pump(
      tester,
      api,
      child: const DevicesSettingsRow(),
    );
    expect(
      find.text('settings.devices.subtitleOne'.tr(args: {'device': 'iPhone'})),
      findsOneWidget,
    );

    api.rows = _rows(macRings: true);
    container.invalidate(devicesProvider);
    await tester.pumpAndSettle();
    expect(
      find.text('settings.devices.subtitleMany'.tr(args: {'count': '2'})),
      findsOneWidget,
    );

    api.rows = [
      for (final row in _rows()) {...row, 'ringsUrgent': false},
    ];
    container.invalidate(devicesProvider);
    await tester.pumpAndSettle();
    expect(find.text('settings.devices.subtitleNone'.tr()), findsOneWidget);
  });

  // ── OPH-449: detail sheet, removal = sign out, last-ringing warning ──────

  testWidgets('rename saves through PATCH and an empty name falls back to '
      'the platform', (tester) async {
    final api = _FakeApi(_rows());
    await _pump(tester, api);

    await _openSheet(tester, _thisId);
    final field = find.byKey(const Key('device-name-field'));
    // Prefilled with the readable name, never the stored User-Agent.
    expect(tester.widget<TextField>(field).controller!.text, 'iPhone');
    expect(find.textContaining('Dart/'), findsNothing);
    // Read-only facts; the ring switch is not repeated in the sheet.
    expect(
      find.descendant(
        of: find.byKey(const Key('device-detail-sheet')),
        matching: find.byType(Switch),
      ),
      findsNothing,
    );
    expect(find.byKey(const Key('device-detail-platform')), findsOneWidget);
    expect(find.byKey(const Key('device-detail-seen')), findsOneWidget);
    expect(find.byKey(const Key('device-detail-added')), findsOneWidget);

    // At most 40 characters.
    await tester.enterText(field, 'x' * 50);
    expect(tester.widget<TextField>(field).controller!.text.length, 40);

    await tester.enterText(field, '  İş telefonu ');
    await tester.tap(find.byKey(const Key('device-name-save')));
    await tester.pumpAndSettle();
    expect(api.names, [(_thisId, 'İş telefonu')]);
    expect(find.byKey(const Key('device-detail-sheet')), findsNothing);
    expect(find.text('İş telefonu'), findsOneWidget);

    // Empty: the platform's own word is saved and shown.
    await _openSheet(tester, _thisId);
    await tester.enterText(field, '   ');
    await tester.tap(find.byKey(const Key('device-name-save')));
    await tester.pumpAndSettle();
    expect(api.names.last, (_thisId, 'iPhone'));
    expect(find.text('iPhone'), findsOneWidget);
    expect(find.text('İş telefonu'), findsNothing);
    // Renaming never touches the ring switch.
    expect(api.patches, isEmpty);
  });

  testWidgets('removing another device asks first, deletes it and drops the '
      'row', (tester) async {
    final api = _FakeApi(_rows(webHasSession: false));
    var signedOut = 0;
    await _pump(tester, api, signOut: (_, _) async => signedOut++);

    // The list says what removal means for alarms already set there.
    expect(find.text('settings.devices.footer'.tr()), findsOneWidget);
    expect(find.text('settings.devices.footerAlarms'.tr()), findsOneWidget);

    await _openSheet(tester, _macId);
    expect(find.byKey(const Key('device-sign-out-here')), findsNothing);
    await tester.tap(find.byKey(const Key('device-remove')));
    await tester.pumpAndSettle();
    final title = 'settings.devices.removeConfirm'.tr(
      args: {'device': 'MacBook Air'},
    );
    expect(find.text(title), findsOneWidget);
    expect(find.text('settings.devices.removeBody'.tr()), findsOneWidget);

    // Cancel: nothing is deleted.
    await tester.tap(find.byKey(const Key('device-remove-cancel')));
    await tester.pumpAndSettle();
    expect(api.deleted, isEmpty);

    await tester.tap(find.byKey(const Key('device-remove')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('device-remove-confirm')));
    await tester.pumpAndSettle();
    expect(api.deleted, [_macId]);
    expect(find.byKey(const Key('device-detail-sheet')), findsNothing);
    expect(find.byKey(const Key('device-card-$_macId')), findsNothing);
    expect(find.text('MacBook Air'), findsNothing);
    // Mac did not ring: nothing to pick.
    expect(find.byKey(const Key('pick-alarm-device-page')), findsNothing);
    expect(signedOut, 0);

    // A device whose session the server could not match says so honestly.
    await _openSheet(tester, _webId);
    await tester.tap(find.byKey(const Key('device-remove')));
    await tester.pumpAndSettle();
    expect(find.text('settings.devices.removeNoSession'.tr()), findsOneWidget);
    expect(find.text('settings.devices.removeBody'.tr()), findsNothing);
  });

  testWidgets('the current device offers sign out, not remote removal', (
    tester,
  ) async {
    final api = _FakeApi(_rows());
    var signedOut = 0;
    await _pump(tester, api, signOut: (_, _) async => signedOut++);

    await _openSheet(tester, _thisId);
    expect(find.byKey(const Key('device-remove')), findsNothing);
    expect(find.text('settings.devices.remove'.tr()), findsNothing);
    final signOut = find.byKey(const Key('device-sign-out-here'));
    expect(signOut, findsOneWidget);
    expect(find.text('settings.devices.signOutHere'.tr()), findsOneWidget);

    await tester.tap(signOut);
    await tester.pumpAndSettle();
    expect(signedOut, 1);
    expect(api.deleted, isEmpty);
    expect(find.byKey(const Key('device-detail-sheet')), findsNothing);
  });

  testWidgets('switching off the last ringing device warns and still allows '
      'it', (tester) async {
    final api = _FakeApi(_rows());
    final kv = _MemoryKv();
    await _pump(tester, api, kv: kv);

    // This device is the only one ringing: switching it off asks first.
    await tester.tap(find.byKey(const Key('device-switch-$_thisId')));
    await tester.pumpAndSettle();
    expect(find.text('settings.devices.lastOffTitle'.tr()), findsOneWidget);
    expect(find.text('settings.devices.lastOffBody'.tr()), findsOneWidget);

    await tester.tap(find.byKey(const Key('devices-last-off-cancel')));
    await tester.pumpAndSettle();
    expect(api.patches, isEmpty);
    expect(_switchOf(tester, _thisId).value, isTrue);

    // Warned, never blocked.
    await tester.tap(find.byKey(const Key('device-switch-$_thisId')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('devices-last-off-confirm')));
    await tester.pumpAndSettle();
    expect(api.patches, [(_thisId, false)]);
    expect(_switchOf(tester, _thisId).value, isFalse);
    expect(kv.values[kRingsUrgentKey], RingsUrgentHere.off.name);
    expect(find.text('settings.devices.lastOffTitle'.tr()), findsNothing);

    // With another device still ringing there is nothing to warn about.
    await tester.tap(find.byKey(const Key('device-switch-$_macId')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('device-switch-$_thisId')));
    await tester.pumpAndSettle();
    expect(find.text('settings.devices.lastOffTitle'.tr()), findsNothing);
    expect(api.patches, [(_thisId, false), (_macId, true), (_thisId, true)]);
  });

  testWidgets('a NO_URGENT_DEVICE answer the list did not foresee still '
      'warns, and Cancel turns the device back on', (tester) async {
    // The list is stale: it still shows the Mac ringing, the server knows
    // it does not.
    final api = _FakeApi(_rows(macRings: true));
    await _pump(tester, api);
    api.rows.firstWhere((r) => r['id'] == _macId)['ringsUrgent'] = false;

    await tester.tap(find.byKey(const Key('device-switch-$_thisId')));
    await tester.pumpAndSettle();
    expect(find.text('settings.devices.lastOffTitle'.tr()), findsOneWidget);
    await tester.tap(find.byKey(const Key('devices-last-off-cancel')));
    await tester.pumpAndSettle();
    expect(api.patches, [(_thisId, false), (_thisId, true)]);
    expect(_switchOf(tester, _thisId).value, isTrue);
  });

  testWidgets('removing the ringing device opens the pick page with the '
      'promoted device selected', (tester) async {
    // The Mac rings, this phone does not.
    final api = _FakeApi(_rows(macRings: true, thisRings: false));
    final kv = _MemoryKv();
    final container = await _pump(tester, api, kv: kv);

    await _openSheet(tester, _macId);
    await tester.tap(find.byKey(const Key('device-remove')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('device-remove-confirm')));
    await tester.pumpAndSettle();
    expect(api.deleted, [_macId]);

    // The server promoted this phone (most recently seen, not web); the page
    // asks, with that answer already selected.
    expect(find.byKey(const Key('pick-alarm-device-page')), findsOneWidget);
    expect(find.text('settings.devices.pickTitle'.tr()), findsOneWidget);
    RadioGroup<String> group() =>
        tester.widget<RadioGroup<String>>(find.byType(RadioGroup<String>));
    expect(group().groupValue, _thisId);
    // The promotion already reached this device's alarm gate.
    expect(kv.values[kRingsUrgentKey], RingsUrgentHere.on.name);
    expect(
      await container.read(ringsUrgentHereProvider.future),
      RingsUrgentHere.on,
    );

    // Choosing another device moves the alarm there, on before off so no
    // moment has none.
    await tester.tap(find.byKey(const Key('pick-device-$_webId')));
    await tester.pumpAndSettle();
    expect(group().groupValue, _webId);
    await tester.tap(find.byKey(const Key('pick-device-save')));
    await tester.pumpAndSettle();
    expect(api.patches, [(_webId, true), (_thisId, false)]);
    expect(find.byKey(const Key('pick-alarm-device-page')), findsNothing);
    expect(kv.values[kRingsUrgentKey], RingsUrgentHere.off.name);
    expect(_switchOf(tester, _webId).value, isTrue);
    expect(_switchOf(tester, _thisId).value, isFalse);
  });

  testWidgets('confirming the promoted device on the pick page changes '
      'nothing', (tester) async {
    final api = _FakeApi(_rows(macRings: true, thisRings: false));
    await _pump(tester, api);

    await _openSheet(tester, _macId);
    await tester.tap(find.byKey(const Key('device-remove')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('device-remove-confirm')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pick-device-save')));
    await tester.pumpAndSettle();
    expect(api.patches, isEmpty);
    expect(find.byKey(const Key('pick-alarm-device-page')), findsNothing);
    expect(_switchOf(tester, _thisId).value, isTrue);
  });

  // ── Walkthrough polish (W-08, W-10, W-11, W-12) ─────────────────────────
  testWidgets('opened by its address the Devices screen still has a way '
      'back, also after the pick page', (tester) async {
    // A web reload on /settings/devices: the screen is the only page. The
    // Mac rings, this phone does not.
    final api = _FakeApi(_rows(macRings: true, thisRings: false));
    await _pumpRouted(tester, api);
    final home = find.byKey(const Key('aw-route-home'));
    expect(home, findsOneWidget);

    // The list changes while the detail sheet sits on top of the screen
    // (renamed elsewhere, read again on the way back to the foreground).
    await _openSheet(tester, _macId);
    api.rows.firstWhere((r) => r['id'] == _macId)['deviceName'] = 'Ofis Mac';
    await _backAndForth(tester);
    expect(find.byKey(const Key('device-detail-sheet')), findsOneWidget);
    Navigator.of(
      tester.element(find.byKey(const Key('device-detail-sheet'))),
    ).pop();
    await tester.pumpAndSettle();
    expect(find.text('Ofis Mac'), findsOneWidget);
    expect(home, findsOneWidget);

    // Removing the ringing device changes the list and opens the pick page
    // on top, which has its own way back; keeping the promoted device there
    // changes nothing more.
    await _openSheet(tester, _macId);
    await tester.tap(find.byKey(const Key('device-remove')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('device-remove-confirm')));
    await tester.pumpAndSettle();
    final pick = find.byKey(const Key('pick-alarm-device-page'));
    expect(pick, findsOneWidget);
    expect(
      find.descendant(of: pick, matching: find.byType(BackButton)),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('pick-device-save')));
    await tester.pumpAndSettle();
    expect(pick, findsNothing);
    expect(api.patches, isEmpty);

    // Back on the list: the Home button is still there, and it works.
    expect(home, findsOneWidget);
    await tester.tap(home);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('test-home')), findsOneWidget);
  });

  testWidgets('the pick page leaves the way back in place after it saves a '
      'change', (tester) async {
    final api = _FakeApi(_rows(macRings: true, thisRings: false));
    await _pumpRouted(tester, api);
    await _openSheet(tester, _macId);
    await tester.tap(find.byKey(const Key('device-remove')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('device-remove-confirm')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pick-device-$_webId')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pick-device-save')));
    await tester.pumpAndSettle();
    expect(api.patches, [(_webId, true), (_thisId, false)]);
    expect(find.byKey(const Key('pick-alarm-device-page')), findsNothing);
    expect(find.byKey(const Key('aw-route-home')), findsOneWidget);
  });

  testWidgets('the list reloads on open and on resume', (tester) async {
    final api = _FakeApi(_rows());
    await _pumpRouted(tester, api, initialLocation: '/home');
    // Home holds the list for the whole session.
    expect(api.listCalls, 1);
    expect(find.text('devices: 4'), findsOneWidget);

    // Meanwhile the server moved the alarm: this device off, the Mac on.
    api.rows.firstWhere((r) => r['id'] == _thisId)['ringsUrgent'] = false;
    api.rows.firstWhere((r) => r['id'] == _macId)['ringsUrgent'] = true;

    // Opening the screen asks the server again instead of showing what Home
    // read at launch.
    await tester.tap(find.byKey(const Key('test-open-devices')));
    await tester.pumpAndSettle();
    expect(find.byType(DevicesScreen), findsOneWidget);
    expect(api.listCalls, 2);
    expect(_switchOf(tester, _thisId).value, isFalse);
    expect(_switchOf(tester, _macId).value, isTrue);

    // Leaving and opening it again asks again.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(DevicesScreen), findsNothing);
    await tester.tap(find.byKey(const Key('test-open-devices')));
    await tester.pumpAndSettle();
    expect(api.listCalls, 3);

    // Back from the background: the list is read again while the screen is
    // open, and a change made elsewhere shows.
    api.rows.firstWhere((r) => r['id'] == _webId)['ringsUrgent'] = true;
    await _backAndForth(tester);
    expect(api.listCalls, 4);
    expect(_switchOf(tester, _webId).value, isTrue);
  });

  testWidgets('the last-ringing-device dialog offers Vazgeç and colours '
      '"Yine de kapat" as the destructive action', (tester) async {
    AwI18n.instance.setActiveCached(const Locale('tr'));
    addTearDown(() => AwI18n.instance.setActiveCached(const Locale('en')));
    final api = _FakeApi(_rows());
    await _pump(tester, api);

    await tester.tap(find.byKey(const Key('device-switch-$_thisId')));
    await tester.pumpAndSettle();
    final cancel = find.byKey(const Key('devices-last-off-cancel'));
    final confirm = find.byKey(const Key('devices-last-off-confirm'));
    expect(
      find.descendant(of: cancel, matching: find.text('Vazgeç')),
      findsOneWidget,
    );
    expect(find.text('İptal'), findsNothing);
    expect(
      find.descendant(of: confirm, matching: find.text('Yine de kapat')),
      findsOneWidget,
    );
    // DESIGN §19 D5: the error-role FilledButton, not the primary one.
    final scheme = Theme.of(tester.element(confirm)).colorScheme;
    final style = tester.widget<FilledButton>(confirm).style;
    expect(style?.backgroundColor?.resolve({}), scheme.error);
    expect(style?.foregroundColor?.resolve({}), scheme.onError);

    await tester.tap(cancel);
    await tester.pumpAndSettle();
    expect(api.patches, isEmpty);
    expect(_switchOf(tester, _thisId).value, isTrue);

    // The remove dialog speaks the same words (mobbin-alarm §2.4).
    await _openSheet(tester, _macId);
    await tester.tap(find.byKey(const Key('device-remove')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('device-remove-cancel')),
        matching: find.text('Vazgeç'),
      ),
      findsOneWidget,
    );
    expect(find.text('İptal'), findsNothing);
  });

  testWidgets('a web row that is off says only that it rings while the tab '
      'is open', (tester) async {
    await _pump(tester, _FakeApi(_rows()));
    Finder inCard(String id, String text) => find.descendant(
      of: find.byKey(Key('device-card-$id')),
      matching: find.text(text),
    );
    final webHint = 'settings.devices.webHint'.tr();
    final offHint = 'settings.devices.offHint'.tr();

    // The web tab is off: one honest line, not a promise of a notification
    // the server may not be able to send.
    expect(inCard(_webId, webHint), findsOneWidget);
    expect(inCard(_webId, offHint), findsNothing);
    // A device that is off gets the same reminder as a notification.
    expect(inCard(_macId, offHint), findsOneWidget);
    expect(inCard(_macId, webHint), findsNothing);
    // A device that rings needs neither.
    expect(inCard(_thisId, offHint), findsNothing);
    expect(inCard(_thisId, webHint), findsNothing);
  });
}
