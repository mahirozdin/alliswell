import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import '../tool/mirror_noto_fallback.dart';

/// OPH-395 (E-27, T-04, ADR-0063 #7) — the web app makes no request to Google.
///
/// Two calls left every self-hosted browser before this:
///
/// - **Roboto.** CanvasKit needs a default font, and unless `FontManifest.json`
///   names a family called exactly `Roboto` it downloads one from
///   `fonts.gstatic.com` (`canvaskit/fonts.dart`, `loadedRoboto`). The app
///   already shipped Roboto for the PDF exporter, as a plain asset — so the
///   engine never saw it.
/// - **CanvasKit itself.** `flutter build web` defaults to the CDN
///   (`www.gstatic.com/flutter-canvaskit/<revision>`). The bootstrap now points
///   the loader at the `canvaskit/` folder every build already contains, so no
///   build flag can be forgotten.
///
/// - **Missing glyphs** (P-01). A title with 会议 or an emoji has no glyph in
///   Roboto, so the engine's fallback service fetches a Noto slice from
///   `fontFallbackBaseUrl` — `fonts.gstatic.com/s/` unless the bootstrap says
///   otherwise. The bootstrap now names the app's own `fonts/noto/`, and the
///   build fills it from the engine's own list (`tool/mirror_noto_fallback.dart`).
///
/// No Dart test can watch a browser's network tab, so this guards the two
/// rules; the browser check is a DEVICE-CHECKS row.
void main() {
  test('Roboto is a registered font family, with the weights the UI uses', () {
    final pubspec = loadYaml(File('pubspec.yaml').readAsStringSync()) as Map;
    final fonts = (pubspec['flutter'] as Map)['fonts'] as List?;
    expect(fonts, isNotNull, reason: 'no `fonts:` section in pubspec.yaml');
    final roboto = fonts!.cast<Map>().firstWhere(
      (f) => f['family'] == 'Roboto',
      orElse: () => const {},
    );
    expect(
      roboto,
      isNotEmpty,
      reason: 'the family must be named exactly "Roboto" for the web engine',
    );

    final weights = <int>{};
    for (final entry in (roboto['fonts'] as List).cast<Map>()) {
      final asset = entry['asset'] as String;
      expect(File(asset).existsSync(), isTrue, reason: asset);
      if (entry['style'] != 'italic') {
        weights.add(entry['weight'] as int? ?? 400);
      }
    }
    // 400 body, 500 row titles and labels, 700 headings. Without 500 the
    // engine draws every w500 label as a fake-bolded Regular.
    expect(weights, containsAll(<int>[400, 500, 700]));
  });

  test('the bootstrap loads CanvasKit from the app, not the CDN', () {
    final bootstrap = File('web/flutter_bootstrap.js').readAsStringSync();
    expect(bootstrap, contains('{{flutter_js}}'));
    expect(bootstrap, contains('{{flutter_build_config}}'));
    expect(bootstrap, contains('canvasKitBaseUrl: "canvaskit/"'));
    // The service worker the default template registers stays as it was.
    expect(bootstrap, contains('{{flutter_service_worker_version}}'));
  });

  test(
    'the bootstrap fetches fallback glyph fonts from the app, not Google',
    () {
      final bootstrap = File('web/flutter_bootstrap.js').readAsStringSync();
      final match = RegExp(
        r'fontFallbackBaseUrl:\s*"([^"]*)"',
      ).firstMatch(bootstrap);
      expect(match, isNotNull, reason: 'without it the engine uses gstatic');
      expect(match!.group(1), notoFallbackWebDir);
      // Relative, so it resolves against the page's own origin and base href
      // (`/app/` on the hosted instance) — never another host.
      expect(Uri.parse(match.group(1)!).hasScheme, isFalse);
      expect(match.group(1), isNot(startsWith('/')));
    },
  );

  test('the mirror tool reads the installed engine\'s fallback list', () {
    final data = fallbackDataFile(flutterRootFromEnvironment());
    expect(data.existsSync(), isTrue, reason: data.path);
    final paths = parseFallbackFontPaths(data.readAsStringSync());
    // The engine ships ~700 slices; a parser that silently matched nothing
    // would mirror nothing and every emoji would draw as a box.
    expect(paths.length, greaterThan(500));
    expect(paths.any((p) => p.startsWith('notocoloremoji/')), isTrue);
    expect(paths.any((p) => p.startsWith('notosanssc/')), isTrue);
    for (final p in paths) {
      expect(Uri.parse(p).hasScheme, isFalse, reason: p);
      expect(p, isNot(startsWith('/')), reason: p);
      expect(p, isNot(contains('..')), reason: p);
    }
  });

  test('parseFallbackFontPaths takes every font path, once, in order', () {
    const source = '''
List<NotoFont> getFallbackFontList() => <NotoFont>[
  NotoFont('Noto Color Emoji 0', 'notocoloremoji/v32/abc.0.woff2'),
  NotoFont(
    'Noto Sans SC 0',
    'notosanssc/v37/def.4.woff2',
  ),
  NotoFont('Noto Sans Symbols', 'notosanssymbols/v43/ghi.ttf'),
  NotoFont('Noto Color Emoji 0', 'notocoloremoji/v32/abc.0.woff2'),
];''';
    expect(parseFallbackFontPaths(source), [
      'notocoloremoji/v32/abc.0.woff2',
      'notosanssc/v37/def.4.woff2',
      'notosanssymbols/v43/ghi.ttf',
    ]);
  });

  for (final path in const [
    'Dockerfile',
    '../../.github/workflows/deploy.yml',
    // P-G1 review r1: the published web archive is built here too.
    '../../.github/workflows/release.yml',
  ]) {
    test('$path mirrors the fallback fonts after building the web bundle', () {
      final text = File(path).readAsStringSync();
      final build = text.indexOf('flutter build web');
      final mirror = text.indexOf('tool/mirror_noto_fallback.dart');
      expect(build, isNot(-1), reason: path);
      expect(mirror, greaterThan(build), reason: path);
    });
  }

  for (final path in const [
    'web/index.html',
    'web/flutter_bootstrap.js',
    'web/manifest.json',
  ]) {
    test('$path names no Google font or CDN host', () {
      final text = File(path).readAsStringSync();
      expect(text, isNot(contains('gstatic.com')));
      expect(text, isNot(contains('fonts.googleapis.com')));
    });
  }
}
