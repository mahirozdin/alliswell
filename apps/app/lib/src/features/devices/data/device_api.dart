import 'package:dio/dio.dart';

/// How a sender can reach this install (OPH-313). Null until a browser has
/// subscribed, or on a platform whose token arrives later (OPH-319).
class DevicePushCredentials {
  const DevicePushCredentials.webPush({
    required this.endpoint,
    required this.p256dh,
    required this.auth,
  }) : provider = 'webpush',
       token = null;

  const DevicePushCredentials.fcm(this.token)
    : provider = 'fcm',
      endpoint = null,
      p256dh = null,
      auth = null;

  final String provider;
  final String? endpoint;
  final String? p256dh;
  final String? auth;
  final String? token;

  Map<String, dynamic> toJson() => {
    'pushProvider': provider,
    if (endpoint != null) 'pushEndpoint': endpoint,
    if (p256dh != null) 'pushP256dh': p256dh,
    if (auth != null) 'pushAuth': auth,
    if (token != null) 'pushToken': token,
  };
}

/// What this install is, in the three facts the registry route stores
/// (OPH-309, `PUT /api/v1/notification-devices/:deviceId`).
///
/// No device NAME. There is no honest source for one without a new plugin, and
/// the column is nullable by design — OPH-284 settled that a guess in a device
/// list is worse than a blank, so the server fills it from the request's
/// User-Agent on first registration instead of the app inventing something.
class DeviceDescriptor {
  const DeviceDescriptor({
    required this.platform,
    required this.appVersion,
    required this.locale,
    this.push,
  });

  /// One of the six the route accepts. Never guessed — see `awDevicePlatform`.
  final String platform;
  final String appVersion;

  /// THIS device's language, which is not the account's: the fallback push
  /// renders a fixed string, and a phone can be in Turkish while the laptop
  /// signed into the same account is in English (ADR-0038).
  final String locale;

  /// Sent only once there is something to send. A heartbeat that carries no
  /// credentials leaves the stored ones alone — the route reads key PRESENCE,
  /// not null (OPH-309), which is what lets this stay optional.
  final DevicePushCredentials? push;

  Map<String, dynamic> toJson() => {
    'platform': platform,
    'appVersion': appVersion,
    'locale': locale,
    ...?push?.toJson(),
  };
}

/// One row of `notification_devices` as the routes return it (OPH-446).
///
/// Every #48 field is nullable: an older server does not send them, and
/// "the server did not say" must stay distinguishable from `false`.
class DeviceInfo {
  const DeviceInfo({
    required this.id,
    required this.platform,
    this.name,
    this.appVersion,
    this.lastSeenAt,
    this.createdAt,
    this.ringsUrgent,
    this.ringsUrgentSource,
    this.hasSession,
  });

  /// Tolerant on purpose: a field of the wrong type reads as absent rather
  /// than failing the registration that carried it.
  factory DeviceInfo.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final platform = json['platform'];
    return DeviceInfo(
      id: id is String ? id : '',
      platform: platform is String ? platform : '',
      name: _string(json['deviceName']),
      appVersion: _string(json['appVersion']),
      lastSeenAt: _date(json['lastSeenAt']),
      createdAt: _date(json['createdAt']),
      ringsUrgent: _bool(json['ringsUrgent']),
      ringsUrgentSource: _string(json['ringsUrgentSource']),
      hasSession: _bool(json['hasSession']),
    );
  }

  final String id;
  final String platform;
  final String? name;
  final String? appVersion;
  final DateTime? lastSeenAt;
  final DateTime? createdAt;

  /// Whether urgent alarms ring on this device; null from an older server.
  final bool? ringsUrgent;

  /// `auto` · `user` · `backfill`; null from an older server.
  final String? ringsUrgentSource;

  /// Whether the device still holds a signed-in session (list only).
  final bool? hasSession;

  static String? _string(Object? value) => value is String ? value : null;
  static bool? _bool(Object? value) => value is bool ? value : null;
  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;
}

/// What `PATCH /api/v1/notification-devices/:id` answered: the row after the
/// change, and warnings such as `NO_URGENT_DEVICE` (the last ringing device
/// was switched off — allowed, but the person should hear about it).
class DevicePatchResult {
  const DevicePatchResult({required this.device, this.warnings = const []});

  final DeviceInfo device;
  final List<String> warnings;
}

/// The calls the registry and the devices screen need. An interface because
/// the registry's behaviour — when to call, and what to do when a call fails —
/// is what the tests are about, and a fake is the honest way to watch it.
abstract class DeviceApi {
  /// Registers or heartbeats this install; returns the row the server holds,
  /// or null when the answer carried none.
  Future<DeviceInfo?> register(String deviceId, DeviceDescriptor device);
  Future<void> unregister(String deviceId);

  /// Every device of the signed-in person.
  Future<List<DeviceInfo>> list();

  /// Changes one device. Only the arguments given are sent.
  Future<DevicePatchResult> patch(
    String deviceId, {
    bool? ringsUrgent,
    String? deviceName,
  });

  /// The instance's VAPID public key, and whether the server does browser push
  /// at all — the route is registered only when it has keys, so a 404 is the
  /// same answer as "no key" and the app never offers a setting that could
  /// not work (OPH-310). Anything else is a server we could not ask (OPH-393).
  Future<PushKeyLookup> lookupPushKey();
}

/// What `GET /api/v1/push/public-key` answered (OPH-393, E-14).
///
/// Two facts, because "no key in hand" has two causes that need two different
/// sentences: a server that has no keys (its admin's job) and a server that
/// could not be asked (nobody's fault, try later).
class PushKeyLookup {
  const PushKeyLookup.key(String this.key) : configured = true;

  /// The 404: the server says it does not do browser push.
  const PushKeyLookup.notConfigured() : key = null, configured = false;

  /// Offline, a 5xx, a body without a key: we do not know.
  const PushKeyLookup.unknown() : key = null, configured = null;

  final String? key;
  final bool? configured;
}

class HttpDeviceApi implements DeviceApi {
  const HttpDeviceApi(this._dio);

  final Dio _dio;

  @override
  Future<DeviceInfo?> register(String deviceId, DeviceDescriptor device) async {
    final response = await _dio.put(
      '/api/v1/notification-devices/$deviceId',
      data: device.toJson(),
    );
    final body = response.data;
    return body is Map<String, dynamic> ? DeviceInfo.fromJson(body) : null;
  }

  @override
  Future<void> unregister(String deviceId) =>
      _dio.delete('/api/v1/notification-devices/$deviceId');

  @override
  Future<List<DeviceInfo>> list() async {
    final response = await _dio.get('/api/v1/notification-devices');
    final items = (response.data as Map?)?['items'];
    return [
      if (items is List)
        for (final item in items)
          if (item is Map<String, dynamic>) DeviceInfo.fromJson(item),
    ];
  }

  @override
  Future<DevicePatchResult> patch(
    String deviceId, {
    bool? ringsUrgent,
    String? deviceName,
  }) async {
    final response = await _dio.patch(
      '/api/v1/notification-devices/$deviceId',
      data: {'ringsUrgent': ?ringsUrgent, 'deviceName': ?deviceName},
    );
    final body = response.data;
    if (body is! Map<String, dynamic>) {
      throw const FormatException('PATCH answered without a device');
    }
    final warnings = body['warnings'];
    return DevicePatchResult(
      device: DeviceInfo.fromJson(body),
      warnings: [
        if (warnings is List)
          for (final warning in warnings)
            if (warning is String) warning,
      ],
    );
  }

  @override
  Future<PushKeyLookup> lookupPushKey() async {
    try {
      final response = await _dio.get('/api/v1/push/public-key');
      final key = (response.data as Map?)?['publicKey'];
      return key is String && key.isNotEmpty
          ? PushKeyLookup.key(key)
          : const PushKeyLookup.unknown();
    } on DioException catch (error) {
      // A 404 is the documented "this server does not do push"; anything else
      // is a server we cannot ask right now. Both mean: do not subscribe — but
      // only the first is the admin's to fix (OPH-393).
      return error.response?.statusCode == 404
          ? const PushKeyLookup.notConfigured()
          : const PushKeyLookup.unknown();
    } on Object {
      return const PushKeyLookup.unknown();
    }
  }
}
