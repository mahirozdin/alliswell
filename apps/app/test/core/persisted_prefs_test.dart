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

  group('default task time (OPH-161)', () {
    test('parseTaskTime reads HH:mm and falls back to 23:59 on junk', () {
      expect(parseTaskTime('23:59'), (23, 59));
      expect(parseTaskTime('07:15'), (7, 15));
      expect(parseTaskTime('9:05'), (9, 5)); // single-digit hour tolerated
      // A corrupted preference must never crash task creation.
      expect(parseTaskTime(''), (23, 59));
      expect(parseTaskTime('gibberish'), (23, 59));
      expect(parseTaskTime('25:00'), (23, 59));
      expect(parseTaskTime('12:75'), (23, 59));
      expect(parseTaskTime('12:5'), (23, 59)); // minutes must be two digits
    });

    test('applyDefaultTaskTime keeps the calendar date, sets the time', () {
      final day = DateTime(2026, 7, 21);
      expect(applyDefaultTaskTime(day, '23:59'), DateTime(2026, 7, 21, 23, 59));
      expect(applyDefaultTaskTime(day, '07:15'), DateTime(2026, 7, 21, 7, 15));
      expect(applyDefaultTaskTime(day, 'bad'), DateTime(2026, 7, 21, 23, 59));
    });

    test('defaultTaskTimeProvider defaults to 23:59 and round-trips', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(defaultTaskTimeProvider), '23:59');
      await container.read(defaultTaskTimeProvider.notifier).set('07:15');
      expect(container.read(defaultTaskTimeProvider), '07:15');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('alliswell_default_task_time'), '07:15');
    });
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
