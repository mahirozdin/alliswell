import '../../i18n/i18n.dart';
import 'data/device_api.dart';

/// The name a person reads for one of their devices (#48, OPH-448).
///
/// The server fills `device_name` with the request's raw User-Agent when a
/// row is first inserted (OPH-284), and the app sends no name of its own, so
/// an unnamed phone arrives as "Dart/3.13 (dart:io)" and a browser as a
/// two-hundred-character string. Neither is something anybody recognises.
///
/// - A name the person set is kept as it is (trimmed).
/// - No name, a blank one, or one that is plainly a User-Agent (starts with
///   `Dart/` or `Mozilla/`) becomes the platform's own word: iPhone, Android,
///   Mac, Windows, Linux. A browser is named by what its User-Agent says —
///   "Chrome · Windows" — or by the generic word when it says nothing usable.
///
/// Every place that names a device uses this: the Devices list, the settings
/// row, the detail sheet, its dialogs and the new-device card.
String deviceDisplayName(DeviceInfo device) {
  final name = device.name?.trim() ?? '';
  if (name.isNotEmpty && !_looksLikeUserAgent(name)) return name;
  if (device.platform == 'web') return _browserLabel(name);
  return switch (device.platform) {
    'ios' => 'iPhone',
    'android' => 'Android',
    'macos' => 'Mac',
    'windows' => 'Windows',
    'linux' => 'Linux',
    // A platform this build has no word for: the stored value is still more
    // honest than nothing, but never a User-Agent.
    _ => name.isNotEmpty ? _browserLabel(name) : device.platform,
  };
}

/// The platform as the meta line names it: "iOS · 2 h ago".
String devicePlatformLabel(String platform) => switch (platform) {
  'ios' => 'iOS',
  'android' => 'Android',
  'macos' => 'macOS',
  'windows' => 'Windows',
  'linux' => 'Linux',
  'web' => 'Web',
  _ => platform,
};

bool _looksLikeUserAgent(String name) =>
    name.startsWith('Dart/') || name.startsWith('Mozilla/');

/// "{browser} · {OS}" from a browser's User-Agent; the generic word when
/// neither can be read.
String _browserLabel(String userAgent) {
  final browser = _browserOf(userAgent);
  final os = _osOf(userAgent);
  final named = browser ?? 'settings.devices.unknownBrowser'.tr();
  return os == null ? named : '$named · $os';
}

/// Order matters: Edge and Opera also say "Chrome", Chrome also says
/// "Safari", so the more specific tokens are tried first.
String? _browserOf(String ua) {
  if (ua.contains('Edg/') || ua.contains('EdgA/') || ua.contains('EdgiOS/')) {
    return 'Edge';
  }
  if (ua.contains('OPR/') || ua.contains('Opera')) return 'Opera';
  if (ua.contains('SamsungBrowser/')) return 'Samsung Internet';
  if (ua.contains('Firefox/') || ua.contains('FxiOS/')) return 'Firefox';
  if (ua.contains('Chrome/') ||
      ua.contains('CriOS/') ||
      ua.contains('Chromium/')) {
    return 'Chrome';
  }
  if (ua.contains('Safari/')) return 'Safari';
  return null;
}

/// Android before Linux (an Android UA says both), iPhone before Mac (an
/// iPhone UA says "like Mac OS X").
String? _osOf(String ua) {
  if (ua.contains('iPhone') || ua.contains('iPod')) return 'iOS';
  if (ua.contains('iPad')) return 'iPadOS';
  if (ua.contains('Android')) return 'Android';
  if (ua.contains('CrOS')) return 'ChromeOS';
  if (ua.contains('Windows')) return 'Windows';
  if (ua.contains('Macintosh') || ua.contains('Mac OS X')) return 'macOS';
  if (ua.contains('Linux')) return 'Linux';
  return null;
}
