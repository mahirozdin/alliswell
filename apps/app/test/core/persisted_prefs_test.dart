import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/core/persisted_prefs.dart';
import 'package:alliswell/src/features/auth/data/secure_secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';

import '../features/auth/test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('PersistedToggle hydrates from storage and persists changes', () async {
    SharedPreferences.setMockInitialValues({
      'alliswell_home_calendar_visible': 'false', // LocalKv stores strings
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(homeCalendarVisibleProvider), true); // fallback
    // Hydration hops through the kv timeout wrapper — give it a beat.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(container.read(homeCalendarVisibleProvider), false);

    await container.read(homeCalendarVisibleProvider.notifier).toggle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('alliswell_home_calendar_visible'), 'true');
  });

  test('PersistedChoice round-trips the notes view mode', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(notesViewModeProvider), 'list');
    await container.read(notesViewModeProvider.notifier).set('grid');
    expect(container.read(notesViewModeProvider), 'grid');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('alliswell_notes_view_mode'), 'grid');
  });

  test('LocalKvSecretStore persists sessions (web reload survival)', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = TokenStorage(LocalKvSecretStore(localKv));

    await storage.save(fakeSession(refreshToken: 'web-persisted'));
    // A "new page load" = a fresh TokenStorage over the same backing store.
    final restored = await TokenStorage(LocalKvSecretStore(localKv)).read();
    expect(restored?.tokens.refreshToken, 'web-persisted');

    await storage.clear();
    expect(await TokenStorage(LocalKvSecretStore(localKv)).read(), isNull);
  });
}
