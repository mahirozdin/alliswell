import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/i18n/i18n.dart';

/// OPH-120 — the i18n store resolves keys per locale (synchronously, so no
/// `runAsync`), falls back to English for untranslated keys, and picks the
/// initial locale from a persisted override → device → fallback (ADR-0009).
///
/// `flutter_test_config.dart` pre-loads `en` + `tr`; reset to `en` before each
/// test since the store is a shared singleton.
void main() {
  setUp(() => AwI18n.instance.setActiveCached(const Locale('en')));

  group('resolveInitialLocale', () {
    test('a supported persisted override wins over the device', () {
      final locale = AwI18n.resolveInitialLocale(
        savedTag: 'tr',
        deviceLocales: const [Locale('en')],
      );
      expect(locale, const Locale('tr'));
    });

    test('falls back to the first supported device locale', () {
      final locale = AwI18n.resolveInitialLocale(
        deviceLocales: const [Locale('fr'), Locale('tr'), Locale('en')],
      );
      expect(locale, const Locale('tr'));
    });

    test('unsupported everywhere → English fallback', () {
      final locale = AwI18n.resolveInitialLocale(
        savedTag: 'de',
        deviceLocales: const [Locale('fr'), Locale('es')],
      );
      expect(locale, awFallbackLocale);
    });

    test('a device region variant (tr-TR) maps to the tr locale', () {
      final locale = AwI18n.resolveInitialLocale(
        deviceLocales: const [Locale('tr', 'TR')],
      );
      expect(locale.languageCode, 'tr');
    });
  });

  group('translate', () {
    test('resolves a key in English', () {
      expect('common.save'.tr(), 'Save');
    });

    test('resolves the same key in Turkish', () {
      AwI18n.instance.setActiveCached(const Locale('tr'));
      expect('common.save'.tr(), 'Kaydet');
    });

    test('a key missing from tr falls back to the English value', () {
      // `common.help` exists only in en.json (a partial tr translation is the
      // intended behavior — ADR-0009).
      AwI18n.instance.setActiveCached(const Locale('tr'));
      expect('common.help'.tr(), 'Help');
    });

    test('an entirely unknown key resolves to itself, not a crash', () {
      expect('nope.not.here'.tr(), 'nope.not.here');
    });

    test('fills {name} placeholders from args', () {
      expect('common.greeting'.tr(args: {'name': 'Mahir'}), 'Hi, Mahir');
    });
  });

  testWidgets(
    'renders a translated key with a plain pumpAndSettle (no runAsync)',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: _SaveLabel())),
      );
      await tester.pumpAndSettle();
      expect(find.text('Save'), findsOneWidget);
    },
  );

  testWidgets('a language switch rebuilds translated text', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: AwI18n.instance,
            // Built inside the builder (not a const child) so it rebuilds.
            builder: (context, _) => Text('common.save'.tr()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Save'), findsOneWidget);

    AwI18n.instance.setActiveCached(const Locale('tr'));
    await tester.pumpAndSettle();
    expect(find.text('Kaydet'), findsOneWidget);
  });
}

class _SaveLabel extends StatelessWidget {
  const _SaveLabel();
  @override
  Widget build(BuildContext context) => Text('common.save'.tr());
}
