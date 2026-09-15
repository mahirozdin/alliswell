import 'push_host.dart';

/// Everywhere that is not a browser (OPH-313).
///
/// It exists so the conditional import has a partner, and it supports nothing —
/// which is the truth on a phone, where the OS schedules alarms locally and no
/// part of this is wanted. `providers.dart` never reaches for it anyway.
class _NoWebPushHost implements WebPushHost {
  const _NoWebPushHost();

  @override
  bool get isSupported => false;

  @override
  bool get ignoresSilence => false;

  @override
  Future<WebPushPermission> permission() async => WebPushPermission.denied;

  @override
  Future<WebPushPermission> requestPermission() async =>
      WebPushPermission.denied;

  @override
  Future<WebPushSubscription?> currentSubscription() async => null;

  @override
  Future<WebPushSubscription?> subscribe(String key) async => null;

  @override
  Stream<String> get notificationClicks => const Stream.empty();

  @override
  Future<void> unsubscribe() async {}

  @override
  Future<void> showNotification(
    String title, {
    String? body,
    bool silent = true,
  }) async {}
}

WebPushHost createWebPushHost() => const _NoWebPushHost();
