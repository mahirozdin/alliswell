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

/// The two calls the registry needs. An interface because the registry's
/// behaviour — when to call, and what to do when a call fails — is what the
/// tests are about, and a fake is the honest way to watch it.
abstract class DeviceApi {
  Future<void> register(String deviceId, DeviceDescriptor device);
  Future<void> unregister(String deviceId);

  /// The instance's VAPID public key, or null when this server does not do
  /// push — the route is registered only when it has keys, so a 404 is the
  /// same answer as "no key" and the app never offers a setting that could
  /// not work (OPH-310).
  Future<String?> pushPublicKey();
}

class HttpDeviceApi implements DeviceApi {
  const HttpDeviceApi(this._dio);

  final Dio _dio;

  @override
  Future<void> register(String deviceId, DeviceDescriptor device) =>
      _dio.put('/api/v1/notification-devices/$deviceId', data: device.toJson());

  @override
  Future<void> unregister(String deviceId) =>
      _dio.delete('/api/v1/notification-devices/$deviceId');

  @override
  Future<String?> pushPublicKey() async {
    try {
      final response = await _dio.get('/api/v1/push/public-key');
      final key = (response.data as Map?)?['publicKey'];
      return key is String && key.isNotEmpty ? key : null;
    } on Object {
      // A 404 is the documented "this server does not do push"; anything else
      // is a server we cannot ask right now. Both mean: do not subscribe.
      return null;
    }
  }
}
