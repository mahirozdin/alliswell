import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

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
