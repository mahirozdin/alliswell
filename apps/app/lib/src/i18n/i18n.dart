/// App-owned localization (Epic 11, ADR-0009).
///
/// A small, **synchronous** in-memory translation store loaded from JSON locale
/// files (`assets/i18n/<lang>.json`) once before `runApp`. Because lookups are
/// synchronous, `'home.title'.tr()` resolves at build time with no `FutureBuilder`
/// gymnastics — which is what keeps the widget-test suite simple (a full-app test
/// pumps and settles as before; nothing needs `runAsync`).
///
/// Behavior (ADR-0009): the device/browser locale is the default, a persisted
/// Settings override wins, English (`en.json`) is the fallback, and a key a
/// locale hasn't translated resolves to its English value instead of the raw key.
///
/// Widgets use the ergonomic `'key'.tr()`; the engine lives ONLY here, behind
/// that one seam, so it stays replaceable.
library;

import 'dart:convert';
import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../core/kv/local_kv.dart';
// Sets `<html lang>` on web; a no-op everywhere else (OPH-128).
import 'html_lang_stub.dart'
    if (dart.library.js_interop) 'html_lang_web.dart';

/// The locales AllisWell ships. Adding a language: drop `assets/i18n/<code>.json`
/// and add its [Locale] here — no other code change (ADR-0009).
const List<Locale> awSupportedLocales = [Locale('en'), Locale('tr')];

/// English is the base/fallback locale.
const Locale awFallbackLocale = Locale('en');

/// Each language shown in ITS OWN language (endonym), so someone who lands in a
/// language they can't read still recognizes their own in the Settings picker.
/// NOT translated — keep the value the same in every locale file.
const Map<String, String> awLanguageEndonyms = {
  'en': 'English',
  'tr': 'Türkçe',
};

/// Where the JSON locale files live (also declared as an asset dir in pubspec).
const String kAwI18nPath = 'assets/i18n';

/// The `localKv` key under which a persistent Settings language override lives.
const String kAwLocalePrefKey = 'alliswell_locale';

/// Reads a locale asset as a raw JSON string. Production uses `rootBundle`;
/// tests swap in a filesystem reader (`test/flutter_test_config.dart`) so the
/// store can be pre-loaded synchronously before the fake-async clock starts.
typedef AwAssetReader = Future<String> Function(String assetPath);

Future<String> _rootBundleReader(String assetPath) =>
    rootBundle.loadString(assetPath);

/// Swappable asset reader (test seam — see [AwAssetReader]).
AwAssetReader awI18nAssetReader = _rootBundleReader;

/// The live translation store. A [ChangeNotifier] so a language change rebuilds
/// the app (see `app.dart`, which wraps `MaterialApp` in a `ListenableBuilder`).
class AwI18n extends ChangeNotifier {
  AwI18n._();

  /// The singleton the `.tr()` extension reads.
  static final AwI18n instance = AwI18n._();

  final Map<String, Map<String, dynamic>> _cache = {};
  Map<String, dynamic> _active = const {};
  Map<String, dynamic> _fallback = const {};
  Locale _locale = awFallbackLocale;

  /// The active locale.
  Locale get locale => _locale;

  /// True while an explicit override is NOT set — i.e. we follow the device.
  bool get followsDevice => _override == null;
  Locale? _override;

  /// Picks the initial locale: a persisted [savedTag] override wins if supported;
  /// otherwise the first supported [deviceLocales] entry (browser languages on
  /// web); otherwise [awFallbackLocale]. Pure — unit tested.
  static Locale resolveInitialLocale({
    String? savedTag,
    List<Locale> deviceLocales = const [],
  }) {
    if (savedTag != null && savedTag.isNotEmpty) {
      final saved = _parseTag(savedTag);
      if (_supported(saved) != null) return _supported(saved)!;
    }
    for (final device in deviceLocales) {
      final match = _supported(device);
      if (match != null) return match;
    }
    return awFallbackLocale;
  }

  /// Boots the store: reads the persisted override (if any), resolves the
  /// initial locale against the device, and loads its translations + the
  /// fallback. Call once in `main()` before `runApp`.
  Future<void> boot() async {
    final saved = await localKv.get(kAwLocalePrefKey);
    _override = (saved == null || saved.isEmpty) ? null : _parseTag(saved);
    final initial = resolveInitialLocale(
      savedTag: saved,
      deviceLocales: PlatformDispatcher.instance.locales,
    );
    await _apply(initial);
  }

  /// Switches language at runtime and PERSISTS the choice (Settings picker).
  Future<void> setLocale(Locale locale) async {
    _override = _supported(locale) ?? awFallbackLocale;
    await localKv.set(kAwLocalePrefKey, _override!.languageCode);
    await _apply(_override!);
  }

  /// Clears the override ("System default") and follows the device again.
  Future<void> useSystemLocale() async {
    _override = null;
    await localKv.remove(kAwLocalePrefKey);
    await _apply(
      resolveInitialLocale(deviceLocales: PlatformDispatcher.instance.locales),
    );
  }

  /// Loads [locale] (+ fallback) into the active maps and notifies listeners.
  Future<void> _apply(Locale locale) async {
    _fallback = await _read(awFallbackLocale);
    _active = locale.languageCode == awFallbackLocale.languageCode
        ? _fallback
        : await _read(locale);
    _locale = locale;
    setHtmlLang(locale.languageCode);
    notifyListeners();
  }

  Future<Map<String, dynamic>> _read(Locale locale) async {
    final code = locale.languageCode;
    final cached = _cache[code];
    if (cached != null) return cached;
    final raw = await awI18nAssetReader('$kAwI18nPath/$code.json');
    final map = json.decode(raw) as Map<String, dynamic>;
    _cache[code] = map;
    return map;
  }

  /// The translation for [key] in the active locale (or the English fallback),
  /// or null if the key is defined in NEITHER — lets callers detect a miss and
  /// fall back to something other than the raw key (e.g. a server message).
  String? maybeTranslate(String key) =>
      _lookup(_active, key) ?? _lookup(_fallback, key);

  /// Resolves a dotted [key] in the active locale, falling back to English, then
  /// to the key itself. `{name}` placeholders are filled from [args].
  String translate(String key, {Map<String, String>? args}) {
    final value = maybeTranslate(key);
    if (value == null) {
      assert(() {
        debugPrint('[i18n] missing key: $key');
        return true;
      }());
      return key;
    }
    if (args == null || args.isEmpty) return value;
    var out = value;
    args.forEach((k, v) => out = out.replaceAll('{$k}', v));
    return out;
  }

  // ── Test/boot seams ───────────────────────────────────────────────────────

  /// Loads locales into the cache without changing the active one. Used by the
  /// test bootstrap so `.tr()` resolves synchronously from the first frame.
  @visibleForTesting
  Future<void> loadForTest(
    Locale active, {
    List<Locale> also = const [],
  }) async {
    for (final l in {awFallbackLocale, active, ...also}) {
      await _read(l);
    }
    _fallback = _cache[awFallbackLocale.languageCode] ?? const {};
    _active = _cache[active.languageCode] ?? _fallback;
    _locale = active;
    _override = null;
  }

  /// Synchronously switches to an ALREADY-CACHED locale (test-only — the app
  /// uses the async [setLocale]). Lets a widget test flip language mid-test
  /// without `runAsync`.
  @visibleForTesting
  void setActiveCached(Locale locale) {
    _active = _cache[locale.languageCode] ?? _fallback;
    _locale = locale;
    notifyListeners();
  }

  static Locale _parseTag(String tag) {
    final parts = tag.replaceAll('_', '-').split('-');
    return parts.length > 1 ? Locale(parts[0], parts[1]) : Locale(parts[0]);
  }

  /// The supported locale matching [candidate] by language code, or null.
  static Locale? _supported(Locale candidate) {
    for (final s in awSupportedLocales) {
      if (s.languageCode == candidate.languageCode) return s;
    }
    return null;
  }

  static String? _lookup(Map<String, dynamic> map, String dottedKey) {
    dynamic cursor = map;
    for (final part in dottedKey.split('.')) {
      if (cursor is Map<String, dynamic> && cursor.containsKey(part)) {
        cursor = cursor[part];
      } else {
        return null;
      }
    }
    return cursor is String ? cursor : null;
  }
}

/// The ergonomic call form used across the app: `'home.title'.tr()`.
extension AwTr on String {
  /// Translates this dotted key via [AwI18n]. `{name}` placeholders ← [args].
  String tr({Map<String, String>? args}) =>
      AwI18n.instance.translate(this, args: args);
}
