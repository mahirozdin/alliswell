import 'alert_cache.dart';

/// Everywhere that is not a browser (OPH-314).
///
/// Nothing reads this store off the web: a phone's notification already has its
/// text when the OS schedules it, and there is no service worker to look
/// anything up.
class _NoAlertCache implements AlertCache {
  const _NoAlertCache();

  @override
  Future<void> put(String reminderId, AlertText text) async {}

  @override
  Future<void> putFallback(AlertText text) async {}
}

AlertCache createAlertCache() => const _NoAlertCache();
