/// Tiny key/value abstraction over platform secret storage so the auth layer
/// is testable and web-safe. OPH-025 provides the Keychain/Keystore-backed
/// implementation; this file stays free of platform plugins.
abstract interface class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Non-persistent store: the default for web (tokens must not touch
/// localStorage — a refresh cookie flow is the planned web hardening, see
/// docs/TASKS.md OPH-025) and the workhorse for tests.
class InMemorySecretStore implements SecretStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}
