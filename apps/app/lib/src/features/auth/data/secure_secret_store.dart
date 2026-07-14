import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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

/// Platform default: keystore-backed everywhere except web. On web, tokens
/// stay in memory only (a signed-out state after every reload) — persisting
/// them in localStorage would expose them to XSS; the planned hardening is an
/// httpOnly refresh cookie flow (BLUEPRINT §15, tracked for the web build).
SecretStore defaultSecretStore() =>
    kIsWeb ? InMemorySecretStore() : SecureSecretStore();
