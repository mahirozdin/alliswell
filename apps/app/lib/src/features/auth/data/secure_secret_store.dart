import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// [SecretStore] over shared_preferences — on web that means localStorage.
/// Sessions survive reloads (product decision, feedback round 1); the XSS
/// exposure of localStorage is accepted for the self-hosted v1 and an
/// httpOnly refresh-cookie flow remains the future hardening (BLUEPRINT §15).
class PrefsSecretStore implements SecretStore {
  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  @override
  Future<String?> read(String key) async => (await _prefs).getString(key);

  @override
  Future<void> write(String key, String value) async {
    await (await _prefs).setString(key, value);
  }

  @override
  Future<void> delete(String key) async {
    await (await _prefs).remove(key);
  }
}

/// Platform default: keystore-backed on mobile/desktop, localStorage-backed
/// on web so a page reload does not sign the user out.
SecretStore defaultSecretStore() =>
    kIsWeb ? PrefsSecretStore() : SecureSecretStore();
