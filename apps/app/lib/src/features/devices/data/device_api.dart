import 'package:dio/dio.dart';

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
  });

  /// One of the six the route accepts. Never guessed — see `awDevicePlatform`.
  final String platform;
  final String appVersion;

  /// THIS device's language, which is not the account's: the fallback push
  /// renders a fixed string, and a phone can be in Turkish while the laptop
  /// signed into the same account is in English (ADR-0038).
  final String locale;

  Map<String, dynamic> toJson() => {
    'platform': platform,
    'appVersion': appVersion,
    'locale': locale,
  };
}

/// The two calls the registry needs. An interface because the registry's
/// behaviour — when to call, and what to do when a call fails — is what the
/// tests are about, and a fake is the honest way to watch it.
abstract class DeviceApi {
  Future<void> register(String deviceId, DeviceDescriptor device);
  Future<void> unregister(String deviceId);
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
}
