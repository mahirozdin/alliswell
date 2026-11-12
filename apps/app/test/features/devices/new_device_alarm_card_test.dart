import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/features/devices/data/device_api.dart';
import 'package:alliswell/src/features/devices/device_registry.dart';
import 'package:alliswell/src/features/devices/new_device_alarm_card.dart';
import 'package:alliswell/src/features/devices/providers.dart';
import 'package:alliswell/src/features/workspaces/workspaces.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/notifications/device_gate.dart';
import 'package:alliswell/src/sync/providers.dart';
import 'package:alliswell/src/theme/theme.dart';

/// OPH-449 (#48, owner answer 5) — a device that joined the account switched
/// off hears once, without opening Settings, where its alarms ring instead.
const _thisId = '01HZTHISDEVICEAAAAAAAAAAAA';
const _phoneId = '01HZPHONEAAAAAAAAAAAAAAAAA';

Map<String, dynamic> _row(
  String id,
  String platform,
  String name,
  bool rings,
) => {
  'id': id,
  'platform': platform,
  'deviceName': name,
  'lastSeenAt': DateTime.now().toUtc().toIso8601String(),
  'createdAt': '2026-11-01T08:00:00.000Z',
  'ringsUrgent': rings,
  'ringsUrgentSource': 'auto',
  'hasSession': true,
};

class _FakeApi implements DeviceApi {
  _FakeApi(this.rows);

  List<Map<String, dynamic>> rows;
  final List<(String, bool?)> patches = [];

  @override
  Future<List<DeviceInfo>> list() async => [
    for (final row in rows) DeviceInfo.fromJson(row),
  ];

  @override
  Future<DevicePatchResult> patch(
    String deviceId, {
    bool? ringsUrgent,
    String? deviceName,
  }) async {
    patches.add((deviceId, ringsUrgent));
    final row = rows.firstWhere((r) => r['id'] == deviceId);
    if (ringsUrgent != null) row['ringsUrgent'] = ringsUrgent;
    return DevicePatchResult(device: DeviceInfo.fromJson(row));
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
  _FakeApi api,
  _MemoryKv kv, {
  String userId = 'user-1',
}) async {
  const child = NewDeviceAlarmCard();
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        deviceApiProvider.overrideWithValue(api),
        currentUserIdProvider.overrideWithValue(userId),
        syncClientIdProvider.overrideWith((ref) => Stream.value(_thisId)),
        ringsUrgentStoreProvider.overrideWithValue(RingsUrgentStore(kv: kv)),
        newDeviceCardKvProvider.overrideWithValue(kv),
      ],
      child: MaterialApp(
        theme: buildAwTheme(Brightness.light),
        home: const Scaffold(body: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byWidget(child)));
}

void main() {
  testWidgets('the card shows once, names the ringing device with the right '
      'suffix and turns this device on', (tester) async {
    AwI18n.instance.setActiveCached(const Locale('tr'));
    addTearDown(() => AwI18n.instance.setActiveCached(const Locale('en')));
    final kv = _MemoryKv();
    final api = _FakeApi([
      _row(_thisId, 'android', 'Pixel', false),
      _row(_phoneId, 'ios', 'iPhone 16', true),
    ]);

    await _pump(tester, api, kv);
    final card = find.byKey(const Key('new-device-alarm-card'));
    expect(card, findsOneWidget);
    // "iPhone 16’da", never a fixed "’de".
    expect(
      find.text(
        'Bu cihazda acil alarmlar kapalı. Alarmlar iPhone 16’da çalıyor.',
      ),
      findsOneWidget,
    );

    // "Tamam" closes it for good on this account and device.
    await tester.tap(find.byKey(const Key('new-device-card-ok')));
    await tester.pumpAndSettle();
    expect(card, findsNothing);
    expect(api.patches, isEmpty);
    await _pump(tester, api, kv);
    expect(card, findsNothing);

    // Another account on the same install sees it once too.
    await _pump(tester, api, kv, userId: 'user-2');
    expect(card, findsOneWidget);

    // "Bu cihazda da çal" switches this device on, and the gate follows.
    final container = await _pump(tester, api, kv, userId: 'user-3');
    await tester.tap(find.byKey(const Key('new-device-card-turn-on')));
    await tester.pumpAndSettle();
    expect(api.patches, [(_thisId, true)]);
    expect(card, findsNothing);
    expect(kv.values[kRingsUrgentKey], RingsUrgentHere.on.name);
    expect(
      await container.read(ringsUrgentHereProvider.future),
      RingsUrgentHere.on,
    );
  });

  testWidgets('no card when this device rings or nothing else does', (
    tester,
  ) async {
    final kv = _MemoryKv();
    // This device rings.
    await _pump(
      tester,
      _FakeApi([
        _row(_thisId, 'android', 'Pixel', true),
        _row(_phoneId, 'ios', 'iPhone 16', false),
      ]),
      kv,
    );
    expect(find.byKey(const Key('new-device-alarm-card')), findsNothing);

    // Nothing rings anywhere: that is the Devices screen's warning, not this
    // card's sentence.
    await _pump(
      tester,
      _FakeApi([
        _row(_thisId, 'android', 'Pixel', false),
        _row(_phoneId, 'ios', 'iPhone 16', false),
      ]),
      kv,
    );
    expect(find.byKey(const Key('new-device-alarm-card')), findsNothing);
    expect(
      kv.values.keys.where((k) => k.startsWith(kNewDeviceCardKeyPrefix)),
      isEmpty,
    );
  });
}
