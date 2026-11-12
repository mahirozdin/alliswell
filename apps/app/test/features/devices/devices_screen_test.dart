import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
}) => {
  'id': id,
  'platform': platform,
  'deviceName': name,
  'lastSeenAt': DateTime.now().toUtc().subtract(seenAgo).toIso8601String(),
  'createdAt': '2026-11-01T08:00:00.000Z',
  'ringsUrgent': ?ringsUrgent,
  if (ringsUrgent != null) 'ringsUrgentSource': 'auto',
  'hasSession': true,
};

/// Four rows, in the order a server might return them: not the order the
/// screen shows them in.
List<Map<String, dynamic>> _rows({
  bool withFlag = true,
  bool macRings = false,
}) => [
  _row(
    _webId,
    'web',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
    const Duration(days: 3),
    ringsUrgent: withFlag ? false : null,
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
    ringsUrgent: withFlag ? true : null,
  ),
];

class _FakeApi implements DeviceApi {
  _FakeApi(this.rows);

  List<Map<String, dynamic>> rows;
  bool offline = false;
  bool failPatch = false;
  Completer<void>? patchGate;
  final List<(String, bool?)> patches = [];

  @override
  Future<List<DeviceInfo>> list() async {
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
    patches.add((deviceId, ringsUrgent));
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
    final ringing = rows.where((r) => r['ringsUrgent'] == true).length;
    return DevicePatchResult(
      device: DeviceInfo.fromJson({...row, 'ringsUrgentSource': 'user'}),
      warnings: [if (ringing == 0) 'NO_URGENT_DEVICE'],
    );
  }

  @override
  Future<DeviceInfo?> register(String deviceId, DeviceDescriptor device) =>
      throw UnimplementedError();

  @override
  Future<void> unregister(String deviceId) => throw UnimplementedError();

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
  Widget child = const DevicesScreen(),
  _MemoryKv? kv,
}) async {
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

Switch _switchOf(WidgetTester tester, String id) =>
    tester.widget<Switch>(find.byKey(Key('device-switch-$id')));

double _top(WidgetTester tester, String id) =>
    tester.getTopLeft(find.byKey(Key('device-card-$id'))).dy;

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
    expect(kv.values[kRingsUrgentKey], isNull);
    // Two ringing devices: the hint says what that means.
    expect(
      find.text('settings.devices.multiHint'.tr(args: {'count': '2'})),
      findsNWidgets(2),
    );

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

  testWidgets('a failed toggle reverts and says so', (tester) async {
    final api = _FakeApi(_rows())..failPatch = true;
    final kv = _MemoryKv();
    await _pump(tester, api, kv: kv);

    await tester.tap(find.byKey(const Key('device-switch-$_thisId')));
    await tester.pumpAndSettle();

    expect(api.patches, [(_thisId, false)]);
    expect(_switchOf(tester, _thisId).value, isTrue);
    expect(find.text('settings.devices.saveFailed'.tr()), findsOneWidget);
    // Nothing the server did not confirm reaches the local gate.
    expect(kv.values[kRingsUrgentKey], isNull);
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
}
