import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/kv/local_kv.dart';
import 'secret_store.dart';

/// [SecretStore] backed by the platform keystore: Keychain on iOS/macOS,
/// Keystore/EncryptedSharedPreferences on Android, libsecret on Linux,
/// DPAPI on Windows (OPH-025).
class SecureSecretStore implements SecretStore {
  SecureSecretStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// [SecretStore] over [LocalKv] — on web that is synchronous localStorage.
/// Sessions survive reloads (product decision, feedback round 1); the XSS
/// exposure of localStorage is accepted for the self-hosted v1 and an
/// httpOnly refresh-cookie flow remains the future hardening (BLUEPRINT §15).
class LocalKvSecretStore implements SecretStore {
  const LocalKvSecretStore(this._kv);

  final LocalKv _kv;

  @override
  Future<String?> read(String key) => _kv.get(key);

  @override
  Future<void> write(String key, String value) => _kv.set(key, value);

  @override
  Future<void> delete(String key) => _kv.remove(key);
}

/// Platform default: keystore-backed on mobile/desktop, localStorage-backed
/// on web so a page reload does not sign the user out.
SecretStore defaultSecretStore() =>
    kIsWeb ? LocalKvSecretStore(localKv) : SecureSecretStore();
