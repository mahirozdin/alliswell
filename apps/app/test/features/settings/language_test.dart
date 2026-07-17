import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/features/settings/account_locale.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/screens/settings_screen.dart';

/// OPH-121 — the Settings language picker persists an override, follows the
/// device again on "System default", and restores the choice on the next boot.
/// AwI18n is a shared singleton, so reset it (and localKv) before each test.
void main() {
  setUp(() async {
    await localKv.remove(kAwLocalePrefKey);
    await AwI18n.instance.loadForTest(const Locale('en'));
  });

  group('AwI18n override', () {
    test('setLocale switches and persists', () async {
      await AwI18n.instance.setLocale(const Locale('tr'));
      expect(AwI18n.instance.locale, const Locale('tr'));
      expect(AwI18n.instance.followsDevice, isFalse);
      expect(await localKv.get(kAwLocalePrefKey), 'tr');
    });

    test('useSystemLocale clears the override', () async {
      await AwI18n.instance.setLocale(const Locale('tr'));
      await AwI18n.instance.useSystemLocale();
      expect(AwI18n.instance.followsDevice, isTrue);
      expect(await localKv.get(kAwLocalePrefKey), isNull);
    });

    test('boot restores a persisted override over the device locale', () async {
      await localKv.set(kAwLocalePrefKey, 'tr');
      await AwI18n.instance.boot();
      expect(AwI18n.instance.locale, const Locale('tr'));
      expect(AwI18n.instance.followsDevice, isFalse);
    });
  });

  group('language picker sheet', () {
    Future<void> openPicker(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          // The picker pushes the choice to the account (OPH-126); stub it so the
          // test doesn't reach the auth/network stack.
          overrides: [
            accountLocaleSyncProvider.overrideWithValue((_) async {}),
          ],
          child: MaterialApp(
            supportedLocales: awSupportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    onPressed: () => showLanguagePicker(context),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('picking Türkçe sets the tr override', (tester) async {
      await openPicker(tester);
      // The current locale (en) carries a check; the picker lists both endonyms.
      expect(find.byKey(const Key('language-tr')), findsOneWidget);
      expect(find.byKey(const Key('language-system')), findsOneWidget);

      await tester.tap(find.byKey(const Key('language-tr')));
      await tester.pumpAndSettle();

      expect(AwI18n.instance.locale, const Locale('tr'));
      expect(AwI18n.instance.followsDevice, isFalse);
    });

    testWidgets('picking System default clears the override', (tester) async {
      await AwI18n.instance.setLocale(const Locale('tr'));
      await openPicker(tester);

      await tester.tap(find.byKey(const Key('language-system')));
      await tester.pumpAndSettle();

      expect(AwI18n.instance.followsDevice, isTrue);
    });
  });
}
