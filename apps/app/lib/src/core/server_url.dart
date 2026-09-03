/// Which AllisWell server this install talks to.
///
/// AllisWell is open source and self-hostable, so the address cannot be a
/// constant baked in at build time: the App Store build must reach ours out of
/// the box, and someone running their own instance must be able to point the
/// same binary at theirs. Resolution order, highest first:
///
/// 1. **The user's own choice** — persisted here, changeable from the sign-in
///    screen and from Settings.
/// 2. **Runtime config** (web only) — `window.ALLISWELL_API_URL`, which the
///    published `alliswell-web` container writes from its env.
/// 3. **`--dart-define=ALLISWELL_API_URL`** at build time.
/// 4. **The default below.**
///
/// The shipped default is production. It used to be `http://localhost:3000`,
/// which is right for `flutter run` and catastrophic for a store build — the
/// first TestFlight build could not reach any server at all. Debug builds keep
/// localhost so local development still works with no flags.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'persisted_prefs.dart';
import 'runtime_config.dart';

/// Where the hosted service lives.
const kHostedApiBaseUrl = 'https://api.alliswell.space';

/// Where a developer's API lives when they run one locally.
const kLocalApiBaseUrl = 'http://localhost:3000';

/// The public REST API reference (OPH-295).
///
/// Deliberately NOT derived from the server address above. A self-hoster's
/// instance serves the API, not the documentation site — pointing this at
/// their origin would send them to a 404 on their own box. The reference
/// describes the software, so it lives with the project, wherever the
/// install happens to run.
const kApiDocsUrl = 'https://alliswell.space/docs/api';

const _kServerUrlPrefKey = 'alliswell_server_url';

/// The address to use when the user has not chosen one.
String get compiledApiBaseUrl {
  const defined = String.fromEnvironment('ALLISWELL_API_URL');
  if (defined.isNotEmpty) return defined;
  return readRuntimeApiBaseUrl() ??
      (kReleaseMode ? kHostedApiBaseUrl : kLocalApiBaseUrl);
}

/// Cleans up what a human typed into something dio can use: trims, adds a
/// scheme when it is missing (people type `my.server.com`), and drops trailing
/// slashes so paths never double up. Returns null when it is not usable as a
/// server address — the caller shows an error rather than saving nonsense.
String? normalizeServerUrl(String input) {
  var value = input.trim();
  if (value.isEmpty) return null;
  if (!value.contains('://')) value = 'https://$value';
  while (value.endsWith('/')) {
    value = value.substring(0, value.length - 1);
  }
  final uri = Uri.tryParse(value);
  if (uri == null) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  if (uri.host.isEmpty) return null;
  // A path is fine (`https://host/alliswell`), a query or fragment is not.
  if (uri.hasQuery || uri.hasFragment) return null;
  return value;
}

/// Short form for display: `https://api.alliswell.space` → `api.alliswell.space`.
String prettyServerUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) return url;
  final path = uri.path.isEmpty || uri.path == '/' ? '' : uri.path;
  // The scheme only matters when it is the unusual one.
  return uri.scheme == 'https' ? '${uri.host}$path' : url;
}

/// The user's override, or an empty string when they are on the default.
/// Persisted, so it survives restarts — a self-hoster sets it once.
final serverUrlOverrideProvider = NotifierProvider<PersistedChoice, String>(
  () => PersistedChoice(_kServerUrlPrefKey, fallback: ''),
);

/// The address every API client uses.
final apiBaseUrlProvider = Provider<String>((ref) {
  final override = ref.watch(serverUrlOverrideProvider);
  return override.isEmpty ? compiledApiBaseUrl : override;
});

/// Whether this install is pointed somewhere other than the built-in default.
final usesCustomServerProvider = Provider<bool>(
  (ref) => ref.watch(serverUrlOverrideProvider).isNotEmpty,
);
