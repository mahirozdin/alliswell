import 'alert_cache_stub.dart'
    if (dart.library.js_interop) 'alert_cache_web.dart'
    as impl;

/// What a notification should say, written by the app and read by the service
/// worker (OPH-314, ADR-0038).
///
/// ── WHY THE TEXT TRAVELS THIS WAY ─────────────────────────────────────────
///
/// A push payload carries identifiers and never a task's title: what crosses
/// Google's, Apple's or Mozilla's servers must not be somebody's work. But a
/// notification has to SAY something, and the service worker runs with no
/// Flutter engine around it — it cannot read the local database, translate a
/// string, or know what privacy mode is set to.
///
/// So the app writes the finished sentence here, already translated and already
/// privacy-resolved, and the worker only looks it up. The worker makes no
/// decision at all; that is the whole design.
class AlertText {
  const AlertText({
    required this.title,
    required this.body,
    this.fireAt,
    this.silent = true,
  });

  final String title;
  final String body;

  /// Whether the browser should show this without a sound. Decided by the app
  /// and stored with the words, because the worker must not be the place a
  /// preference lives. Default silent: the report this came from is somebody
  /// asking to be reached without disturbing the people around them.
  final bool silent;

  /// When this alert is for. Used to decide which of a reminder's slots wins
  /// (the earliest) and to prune entries nobody will look up again.
  final DateTime? fireAt;
}

abstract class AlertCache {
  /// Earliest `fireAt` wins: a reminder's chain has several slots and the push
  /// names only the reminder, so the text that belongs to it is the first
  /// alert it will produce.
  Future<void> put(String reminderId, AlertText text);

  /// What to show when the lookup misses — a reminder scheduled before this
  /// browser last synced, or an entry pruned. Deliberately the same pair
  /// privacy mode already produces, so a cache miss and a private device read
  /// identically instead of inventing a third voice.
  Future<void> putFallback(AlertText text);
}

AlertCache createAlertCache() => impl.createAlertCache();
