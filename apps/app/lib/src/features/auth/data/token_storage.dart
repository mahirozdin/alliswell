import 'dart:convert';

import 'models.dart';
import 'secret_store.dart';

/// Persists the whole [AuthSession] as one JSON blob under an
/// `alliswell_*`-prefixed key (naming per docs/adr/0003).
class TokenStorage {
  const TokenStorage(this._store);

  static const storageKey = 'alliswell_session';

  final SecretStore _store;

  Future<AuthSession?> read() async {
    final raw = await _store.read(storageKey);
    if (raw == null) return null;
    try {
      return AuthSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      // Corrupt or from an incompatible old version — drop it, force re-login.
      await _store.delete(storageKey);
      return null;
    }
  }

  Future<void> save(AuthSession session) =>
      _store.write(storageKey, jsonEncode(session.toJson()));

  Future<void> clear() => _store.delete(storageKey);
}
