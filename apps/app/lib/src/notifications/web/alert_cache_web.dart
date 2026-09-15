import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'alert_cache.dart';

/// IndexedDB, because the service worker has to be able to read it (OPH-314).
///
/// `localStorage` is not an option: it is synchronous and a worker has no
/// access to it. IndexedDB is the one store both a page and its service worker
/// can open, which is the entire reason this file exists rather than reusing
/// `core/kv/local_kv_web.dart`.
///
/// Everything is best effort. A browser in private mode, with storage blocked
/// or with a full quota must leave the app working — a missing entry costs the
/// fallback text, not a crash.
const String kAwAlertDbName = 'alliswell_alerts';
const String kAwAlertStoreName = 'alerts';

/// The key the fallback text lives under. A reminder id is a ULID, so a key
/// with two underscores cannot collide with one.
const String kAwAlertFallbackKey = '__fallback';

/// Entries older than this are dropped on the next write. A delivery that is a
/// week late is not a delivery, and an unbounded store in somebody's browser is
/// rude.
const Duration kAwAlertRetention = Duration(days: 7);

class _IndexedDbAlertCache implements AlertCache {
  Future<web.IDBDatabase?>? _opening;

  Future<web.IDBDatabase?> _db() => _opening ??= _open();

  Future<web.IDBDatabase?> _open() async {
    final completer = Completer<web.IDBDatabase?>();
    try {
      final request = web.window.indexedDB.open(kAwAlertDbName, 1);
      request.onupgradeneeded = (web.Event _) {
        final db = request.result as web.IDBDatabase;
        if (!db.objectStoreNames.contains(kAwAlertStoreName)) {
          db.createObjectStore(kAwAlertStoreName);
        }
      }.toJS;
      request.onsuccess = (web.Event _) {
        if (!completer.isCompleted) {
          completer.complete(request.result as web.IDBDatabase);
        }
      }.toJS;
      request.onerror = (web.Event _) {
        if (!completer.isCompleted) completer.complete(null);
      }.toJS;
    } on Object {
      return null;
    }
    return completer.future;
  }

  Future<void> _write(String key, AlertText text, {bool prune = false}) async {
    final db = await _db();
    if (db == null) return;
    try {
      final transaction = db.transaction(kAwAlertStoreName.toJS, 'readwrite');
      final store = transaction.objectStore(kAwAlertStoreName);
      store.put(
        {
          'title': text.title,
          'body': text.body,
          'fireAt': text.fireAt?.toUtc().toIso8601String(),
          'silent': text.silent,
        }.jsify(),
        key.toJS,
      );
      if (prune) _prune(store);
    } on Object {
      // Blocked, closed, or over quota. The fallback text covers it.
    }
  }

  /// Drops what nobody will look up again. Runs inside the same transaction as
  /// the write that triggered it, so it costs no extra round trip.
  void _prune(web.IDBObjectStore store) {
    final cutoff = DateTime.now().toUtc().subtract(kAwAlertRetention);
    final request = store.openCursor();
    request.onsuccess = (web.Event _) {
      final cursor = request.result as web.IDBCursorWithValue?;
      if (cursor == null) return;
      final value = cursor.value.dartify();
      final fireAt = value is Map ? value['fireAt'] : null;
      final at = fireAt is String ? DateTime.tryParse(fireAt) : null;
      if (at != null && at.isBefore(cutoff)) cursor.delete();
      cursor.continue_();
    }.toJS;
  }

  @override
  Future<void> put(String reminderId, AlertText text) =>
      _write(reminderId, text, prune: true);

  @override
  Future<void> putFallback(AlertText text) => _write(kAwAlertFallbackKey, text);
}

AlertCache createAlertCache() => _IndexedDbAlertCache();
