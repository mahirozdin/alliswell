import 'local_kv_io.dart'
    if (dart.library.js_interop) 'local_kv_web.dart'
    as impl;

/// Tiny string key/value persistence with a platform-appropriate backend:
/// browser localStorage on web (synchronous — plugins proved hangable there,
/// feedback round 1 item 2), SharedPreferences elsewhere. Implementations
/// must never hang or throw: worst case they degrade to no persistence.
abstract interface class LocalKv {
  Future<String?> get(String key);
  Future<void> set(String key, String value);
  Future<void> remove(String key);
}

/// Process-wide instance — persistence has no per-caller state.
final LocalKv localKv = impl.createLocalKv();
