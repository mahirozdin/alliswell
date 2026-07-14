import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/secure_secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';

import 'test_support.dart';

void main() {
  group('TokenStorage (OPH-025)', () {
    test('round-trips a session through the store', () async {
      final storage = TokenStorage(InMemorySecretStore());
      final session = fakeSession(refreshToken: 'persisted-rt');

      await storage.save(session);
      final restored = await storage.read();

      expect(restored?.user.id, session.user.id);
      expect(restored?.user.displayName, 'Mahir');
      expect(restored?.tokens.refreshToken, 'persisted-rt');
      expect(
        restored?.tokens.refreshTokenExpiresAt.toIso8601String(),
        session.tokens.refreshTokenExpiresAt.toIso8601String(),
      );
    });

    test('clear removes the persisted session', () async {
      final store = InMemorySecretStore();
      final storage = TokenStorage(store);
      await storage.save(fakeSession());

      await storage.clear();

      expect(await storage.read(), isNull);
      expect(await store.read(TokenStorage.storageKey), isNull);
    });

    test('a corrupt blob is dropped instead of crashing the app', () async {
      final store = InMemorySecretStore();
      await store.write(TokenStorage.storageKey, '{not valid json');
      final storage = TokenStorage(store);

      expect(await storage.read(), isNull);
      expect(
        await store.read(TokenStorage.storageKey),
        isNull,
        reason: 'corrupt payloads are deleted so the next start is clean',
      );
    });

    test('an incompatible old schema is also dropped', () async {
      final store = InMemorySecretStore();
      await store.write(TokenStorage.storageKey, '{"someOldField": 1}');

      expect(await TokenStorage(store).read(), isNull);
    });
  });

  group('SecureSecretStore (OPH-025)', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    test('delegates read/write/delete to the platform keystore', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final store = SecureSecretStore();

      await store.write('alliswell_session', 'blob');
      expect(await store.read('alliswell_session'), 'blob');

      await store.delete('alliswell_session');
      expect(await store.read('alliswell_session'), isNull);
    });

    test('reading a missing key answers null', () async {
      FlutterSecureStorage.setMockInitialValues({});
      expect(await SecureSecretStore().read('alliswell_missing'), isNull);
    });
  });
}
