// The EE screenshot harness (EE-145).
//
// ── THE BUG THIS FILE EXISTS TO FIX ──────────────────────────────────────
//
// Every shot file wrote `'../../goldens/$name-${brightness.name}.png'`. That
// name carries the theme and NOT the language, so the `shotLocale=en` run
// overwrites the `shotLocale=tr` run byte for byte, in silence.
//
// docs/SCREENSHOTS.md §4b works around it by hand: run English, copy the files
// out with an `-en` suffix, run Turkish, copy again. With four screens that is
// eight copies and it survives. The enterprise page needs sixteen screens in
// two themes and two languages — sixty-four hand copies with a silent
// overwrite in the middle of every one. Forget a single copy and the English
// page ships Turkish pixels under an English filename, and nothing anywhere
// notices, because a golden is not compared in CI and a marketing page has no
// gate that reads the language of an image.
//
// So the language goes IN the filename, produced by the same run that chose
// it. `eeGolden` is the only place that name is spelled.
//
// ── AND THE FOUR COPIES OF `shoot()` BECOME ONE ──────────────────────────
//
// The four published shot files carried the same forty lines with three
// differences: the surface size, the overrides, and whether something is
// tapped after the first pump. Each copy also carried the same four hard-won
// details, and a fifth file would have had to rediscover them:
//
//   • `fontFamilyOverride` is MANDATORY. The theme's own fontFamily is null
//     (platform font, DESIGN §3.3) and the test engine draws that as box
//     glyphs. `loadRealFontsForStore()` also throws if it cannot find the
//     fonts, which it locates relative to the working directory — so every run
//     must start with `cd apps/app`.
//   • `physicalSize` is PHYSICAL. With devicePixelRatio 2.0 a Size(900, 1000)
//     lays out at 450x500 logical and writes a 900x1000 PNG. The screens are
//     therefore drawn at phone width; `kAwWideBreakpoint` is 800 and is never
//     crossed.
//   • `AwPageBackground` wraps the screen. A bare Scaffold renders the glass
//     veil against nothing — a flat grey that exists nowhere in the product.
//   • `debugDisableShadows = false` is restored in `finally`, not in
//     `addTearDown`: the binding's invariant check runs first.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';
import 'package:alliswell/src/widgets/glass.dart';

import '../../../design_screenshots_test.dart' show loadRealFontsForStore;

/// The theme's own fontFamily is null and the test engine draws that as box
/// glyphs. Every shot file learned this the same way; it is stated once now.
const String screenshotFamily = 'ScreenshotSans';

/// The golden's path, with the ACTIVE LANGUAGE in it.
///
/// The language is read from `AwI18n` rather than from the dart-define, so the
/// name can never disagree with the pixels: a file that pins `Locale('en')`
/// writes `-en` whatever `shotLocale` says, and a file that follows
/// `screenshotLocale()` writes what it was asked for.
///
/// `matchesGoldenFile` resolves a relative path against the directory of the
/// TEST FILE being run, not this helper — so the default is right for the shot
/// files in `test/features/ee/`, and `admin/` passes its own.
String eeGolden(
  String name,
  Brightness brightness, {
  String goldenDir = '../../goldens',
}) =>
    '$goldenDir/$name-${brightness.name}-'
    '${AwI18n.instance.locale.languageCode}.png';

/// Renders one EE screen and writes its golden.
///
/// [afterPump] covers the one thing the four copies did differently beyond
/// size and overrides: the portal file taps its create button to photograph a
/// dialog.
Future<void> eeShoot(
  WidgetTester tester, {
  required Brightness brightness,
  required String name,
  required Widget screen,
  List<Override> overrides = const [],
  Size size = const Size(900, 1000),
  Future<void> Function(WidgetTester tester)? afterPump,
  String goldenDir = '../../goldens',
}) async {
  await loadRealFontsForStore();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 2.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  debugDisableShadows = false;
  try {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAwTheme(brightness, fontFamilyOverride: screenshotFamily),
          home: AwPageBackground(child: screen),
        ),
      ),
    );
    await tester.pumpAndSettle();

    if (afterPump != null) {
      await afterPump(tester);
      await tester.pumpAndSettle();
    }

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile(eeGolden(name, brightness, goldenDir: goldenDir)),
    );
  } finally {
    debugDisableShadows = true;
  }
}
