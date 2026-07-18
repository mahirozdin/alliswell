// Design-review screenshot harness (docs/DESIGN.md §5): renders the REAL
// signed-in app (real router, theme, seeded replica) in light + dark, phone +
// desktop, with real shadows and a real font, and writes PNGs to
// test/goldens/. Run locally with:
//
//   flutter test --update-goldens --dart-define=screenshots=true \
//       test/design_screenshots_test.dart
//
// Skipped without the dart-define (goldens are generated output, not
// committed, so plain CI runs must not try to compare against them).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/router.dart';
import 'package:alliswell/src/theme/theme.dart';
import 'package:alliswell/src/widgets/glass.dart';

import 'features/auth/test_support.dart';
import 'features/projects/fake_api.dart';
import 'support/sync_overrides.dart';

const bool _enabled = bool.fromEnvironment('screenshots');

/// The theme's `fontFamily` is deliberately null (platform system font,
/// DESIGN §3.3) — the test engine maps that to box glyphs, so screenshots
/// pin a real sans under an explicit family instead.
const String _family = 'ScreenshotSans';

Future<void> _loadRealFonts() async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    final icons = File(
      '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (icons.existsSync()) {
      final bytes = icons.readAsBytesSync();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(Future.value(ByteData.view(bytes.buffer)))).load();
    }
  }
  final loader = FontLoader(_family);
  for (final path in [
    '/System/Library/Fonts/Supplemental/Arial.ttf',
    '/System/Library/Fonts/Supplemental/Arial Bold.ttf',
  ]) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final bytes = file.readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}

/// The real app (router + aurora + theme), with only the screenshot font
/// pinned — mirrors AllisWellApp in app.dart.
class _ScreenshotApp extends ConsumerWidget {
  const _ScreenshotApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      theme: buildAwTheme(Brightness.light, fontFamilyOverride: _family),
      darkTheme: buildAwTheme(Brightness.dark, fontFamilyOverride: _family),
      themeMode: ThemeMode.system,
      locale: AwI18n.instance.locale,
      supportedLocales: awSupportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        ...FlutterQuillLocalizations.localizationsDelegates,
      ],
      builder: (context, child) =>
          AuroraBackground(child: child ?? const SizedBox.shrink()),
      routerConfig: router,
    );
  }
}

Future<Widget> _signedInScreenshotApp(FakeApi api) async {
  SharedPreferences.setMockInitialValues({});
  final store = InMemorySecretStore();
  await TokenStorage(store).save(fakeSession());
  return ProviderScope(
    retry: awRetry,
    overrides: [
      ...syncTestOverrides(),
      secretStoreProvider.overrideWithValue(store),
      apiClientProvider.overrideWithValue(
        fakeDio(FakeHttpClientAdapter(api.handle)),
      ),
    ],
    child: const _ScreenshotApp(),
  );
}

FakeApi _seededApi() {
  final api = FakeApi();
  api.seedProject(name: 'Launch v1', colorRgb: '#8E44EC', isFavorite: true);
  api.seedProject(name: 'Home reno', colorRgb: '#0C7D6C');
  final now = DateTime.now();
  String iso(DateTime d) => d.toUtc().toIso8601String();
  api.seedTask(
    title: 'Ship the new Liquid Glass theme',
    priority: 'high',
    dueAt: iso(DateTime(now.year, now.month, now.day, 18)),
  );
  api.seedTask(
    title: 'Review contrast report',
    priority: 'urgent',
    isUrgent: true,
    dueAt: iso(now.subtract(const Duration(days: 1))),
  );
  api.seedTask(
    title: 'Water the plants',
    priority: 'low',
    dueAt: iso(now.add(const Duration(days: 2))),
  );
  api.seedTask(
    title: 'Book dentist appointment',
    priority: 'medium',
    dueAt: iso(now.add(const Duration(days: 4))),
  );
  api.seedTask(title: 'Sketch onboarding ideas');
  return api;
}

/// Pump the seeded app and write `test/goldens/<name>.png` — with REAL
/// shadows (the binding otherwise paints elevations as black outlines).
/// The flag is restored inside the test body: the binding's invariant check
/// runs before addTearDown callbacks would. [size] is LOGICAL pixels; the
/// PNG is written at 2× for crispness.
Future<void> _shoot(
  WidgetTester tester, {
  required Size size,
  required Brightness brightness,
  required String name,
  bool openSheet = false,
}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2.0;
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearPlatformBrightnessTestValue();
  });
  debugDisableShadows = false;
  try {
    await tester.pumpWidget(await _signedInScreenshotApp(_seededApi()));
    await tester.pumpAndSettle();
    if (openSheet) {
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
    }
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/$name.png'),
    );
  } finally {
    debugDisableShadows = true;
  }
}

void main() {
  setUpAll(_loadRealFonts);

  testWidgets('phone home — light', skip: !_enabled, (tester) async {
    await _shoot(
      tester,
      size: const Size(390, 844),
      brightness: Brightness.light,
      name: 'phone_home_light',
    );
  });

  testWidgets('phone home — dark', skip: !_enabled, (tester) async {
    await _shoot(
      tester,
      size: const Size(390, 844),
      brightness: Brightness.dark,
      name: 'phone_home_dark',
    );
  });

  testWidgets('phone create sheet — light', skip: !_enabled, (tester) async {
    await _shoot(
      tester,
      size: const Size(390, 844),
      brightness: Brightness.light,
      name: 'phone_sheet_light',
      openSheet: true,
    );
  });

  testWidgets('phone create sheet — dark', skip: !_enabled, (tester) async {
    await _shoot(
      tester,
      size: const Size(390, 844),
      brightness: Brightness.dark,
      name: 'phone_sheet_dark',
      openSheet: true,
    );
  });

  testWidgets('desktop home — light', skip: !_enabled, (tester) async {
    await _shoot(
      tester,
      size: const Size(1280, 800),
      brightness: Brightness.light,
      name: 'desktop_home_light',
    );
  });

  testWidgets('desktop home — dark', skip: !_enabled, (tester) async {
    await _shoot(
      tester,
      size: const Size(1280, 800),
      brightness: Brightness.dark,
      name: 'desktop_home_dark',
    );
  });
}
