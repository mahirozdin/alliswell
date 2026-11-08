{{flutter_js}}
{{flutter_build_config}}

// OPH-395 (E-27, ADR-0063 #7) — the web app makes no request to Google.
// `flutter build web` defaults to loading CanvasKit from Google's CDN;
// every build already carries its own copy
// in `canvaskit/`, so the loader is pointed there instead. Doing it here
// rather than with `--no-web-resources-cdn` means no build script can forget
// it. Roboto is the other half: pubspec.yaml registers it by family name.
// P-01: a character Roboto lacks (CJK, emoji) makes the engine fetch a Noto
// slice from fontFallbackBaseUrl, whose default is Google's font host. It now
// names the app's own folder, relative so it follows <base href>; the build
// fills it (tool/mirror_noto_fallback.dart). Unfilled, a glyph draws as a box
// and still no request leaves for Google.
// Guarded by test/web_fonts_offline_test.dart.
_flutter.loader.load({
  serviceWorkerSettings: {
    serviceWorkerVersion: {{flutter_service_worker_version}},
  },
  config: {
    canvasKitBaseUrl: "canvaskit/",
    fontFallbackBaseUrl: "fonts/noto/",
  },
});
