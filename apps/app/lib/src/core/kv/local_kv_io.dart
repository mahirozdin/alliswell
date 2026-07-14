import 'package:shared_preferences/shared_preferences.dart';

import 'local_kv.dart';

/// Mobile/desktop backend: SharedPreferences, guarded by a timeout so a
/// misbehaving platform channel can never brick startup.
class _PrefsLocalKv implements LocalKv {
  SharedPreferences? _cached;

  Future<SharedPreferences?> get _prefs async {
    if (_cached != null) return _cached;
    try {
      _cached = await SharedPreferences.getInstance().timeout(
        const Duration(seconds: 3),
      );
    } on Object {
      return null;
    }
    return _cached;
  }

  @override
  Future<String?> get(String key) async => (await _prefs)?.getString(key);

  @override
  Future<void> set(String key, String value) async {
    try {
      await (await _prefs)?.setString(key, value);
    } on Object {
      // Non-persistent session; in-memory state still applies.
    }
  }

  @override
  Future<void> remove(String key) async {
    try {
      await (await _prefs)?.remove(key);
    } on Object {
      // Ignore.
    }
  }
}

LocalKv createLocalKv() => _PrefsLocalKv();
