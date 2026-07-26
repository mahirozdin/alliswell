import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Web build: read the API base URL that `web/alliswell-config.js` may define
/// as `window.ALLISWELL_API_URL`.
///
/// Why this exists: the compile-time `--dart-define` bakes the API address into
/// the bundle, so a PREBUILT image could only ever talk to the host it was
/// built for. Self-hosters run the published `alliswell-web` container against
/// their own API, and its entrypoint rewrites that one small script from
/// `ALLISWELL_API_URL` at container start. Nothing else in the bundle changes,
/// so the image stays byte-identical across deployments.
///
/// Returns null when the value is absent, blank, or still the placeholder — the
/// caller then falls back to the compile-time default, which keeps
/// `flutter run`/`flutter build web` behaving exactly as before.
String? readRuntimeApiBaseUrl() {
  const key = 'ALLISWELL_API_URL';
  try {
    if (!globalContext.has(key)) return null;
    final value = globalContext.getProperty<JSAny?>(key.toJS);
    if (value == null) return null;
    final url = value.dartify();
    if (url is! String) return null;
    final trimmed = url.trim();
    // The Docker entrypoint substitutes this token; an unsubstituted file must
    // not become the API address.
    if (trimmed.isEmpty || trimmed.startsWith('__')) return null;
    return trimmed;
  } catch (_) {
    // A malformed config file must never stop the app from booting: fall back.
    return null;
  }
}
