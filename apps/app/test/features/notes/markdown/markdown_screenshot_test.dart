// The reading view, shot over the conformance fixture (OPH-247 acceptance).
//
// Run locally with:
//
//   flutter test --update-goldens --dart-define=screenshots=true \
//       test/features/notes/markdown/markdown_screenshot_test.dart
//
// Skipped without the dart-define, exactly like `design_screenshots_test.dart`:
// goldens are generated output, not committed, so plain CI runs must not try to
// compare against them. The two PNGs are copied into `docs/screenshots/` by
// hand — the acceptance criterion is a picture a person looks at, not a
// pixel-diff gate.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/files/providers.dart';
import 'package:alliswell/src/features/notes/markdown/aw_markdown.dart';
import 'package:alliswell/src/features/notes/markdown/md_parse.dart';
import 'package:alliswell/src/theme/theme.dart';

import '../../../design_screenshots_test.dart' show loadRealFontsForStore;

const bool _enabled = bool.fromEnvironment('screenshots');

/// The family `loadRealFontsForStore` pins the real sans under.
///
/// The theme's own `fontFamily` is deliberately null (platform system font,
/// DESIGN §3.3) and the test engine maps that to BOX GLYPHS — the first run of
/// this file proved it: perfect callouts, perfect tables, and every word a
/// black rectangle. Loading the font is only half the job; the theme has to
/// ask for it.
const String _screenshotFamily = 'ScreenshotSans';

/// Real code fonts. `MdStyles.code` asks for `monospace`, which the test engine
/// has no glyphs for — the second run of this file showed correct syntax
/// COLOURS over black rectangles, which is a strange thing to publish as proof
/// that a README reads well.
Future<void> _loadMonospace() async {
  const candidates = [
    '/System/Library/Fonts/Supplemental/Courier New.ttf',
    '/System/Library/Fonts/Supplemental/Courier New Bold.ttf',
  ];
  final loader = FontLoader('monospace');
  var any = false;
  for (final path in candidates) {
    final file = File(path);
    if (!file.existsSync()) continue;
    any = true;
    loader.addFont(Future.value(ByteData.view(file.readAsBytesSync().buffer)));
  }
  if (any) await loader.load();
}

/// The KaTeX faces, straight out of the package that ships them.
///
/// They are declared in `flutter_math_fork`'s pubspec and resolve fine in a
/// real build; a test binary does not pull another package's font assets, so
/// the formulas came out as boxes too. Loading them by family name here is the
/// screenshot's problem, not the product's.
Future<void> _loadKatexFonts() async {
  final dir = Directory(
    '${Platform.environment['HOME']}/.pub-cache/hosted/pub.dev/'
    'flutter_math_fork-0.7.4/lib/katex_fonts/fonts',
  );
  if (!dir.existsSync()) return;

  final byFamily = <String, FontLoader>{};
  for (final entry in dir.listSync().whereType<File>()) {
    final name = entry.uri.pathSegments.last;
    if (!name.endsWith('.ttf')) continue;
    // `KaTeX_Main-Bold.ttf` -> family `KaTeX_Main`. Registered under BOTH the
    // bare name and Flutter's package-scoped form, because a font declared by
    // a dependency resolves as `packages/<pkg>/<family>` and it is cheaper to
    // cover both than to guess which one the engine asks for.
    final family = name.split('-').first;
    final bytes = ByteData.view(entry.readAsBytesSync().buffer);
    for (final key in [family, 'packages/flutter_math_fork/$family']) {
      byFamily
          .putIfAbsent(key, () => FontLoader(key))
          .addFont(Future.value(bytes));
    }
  }
  for (final loader in byFamily.values) {
    await loader.load();
  }
}

void main() {
  if (!_enabled) return;

  setUpAll(() async {
    await loadRealFontsForStore();
    await _loadMonospace();
    await _loadKatexFonts();
  });

  final fixture = File(
    'test/fixtures/markdown_conformance.md',
  ).readAsStringSync();

  for (final brightness in Brightness.values) {
    testWidgets('reading view — ${brightness.name}', (tester) async {
      // Tall enough for the whole document: the point of the shot is that a
      // reader can scroll it like a README, so a cropped screen would prove
      // less than nothing.
      tester.view.physicalSize = const Size(900, 5200) * 2;
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      debugDisableShadows = false;
      try {
        await tester.pumpWidget(
          ProviderScope(
            // The fixture's images point at real repository files that a test
            // process cannot fetch; the shot is about typography and blocks,
            // so they resolve to a flat placeholder rather than error cards
            // that would dominate the picture.
            overrides: [
              networkImageProvider.overrideWithValue(
                (_) => const AssetImage('assets/branding/icon.png'),
              ),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: buildAwTheme(
                brightness,
                fontFamilyOverride: _screenshotFamily,
              ),
              home: Scaffold(
                body: SafeArea(
                  child: SingleChildScrollView(
                    child: AwMarkdown(
                      document: parseMarkdown(fixture),
                      shrinkWrap: true,
                      onOpenLink: (_) {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            '../../../goldens/markdown-reading-${brightness.name}.png',
          ),
        );
      } finally {
        debugDisableShadows = true;
      }
    });
  }
}
