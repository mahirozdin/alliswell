import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/foundation.dart';

/// Firebase, as an **optional** dependency (ADR-0025).
///
/// AllisWell's source is public and its credentials are not: the platform config
/// files (`google-services.json`, `GoogleService-Info.plist`) are gitignored, so
/// on a fresh clone — and on every self-hoster's machine — they simply are not
/// there. Everything in this file is therefore written to *degrade*, never to
/// throw: `Firebase.initializeApp()` fails, [isConfigured] stays false, and the
/// rest of the app never learns Firebase exists.
///
/// Note what this does NOT do: initialise from a generated `firebase_options.dart`.
/// That file embeds the project's identifiers in Dart, which would put them back
/// in the repository — the exact thing being avoided. On Android, iOS and macOS
/// the native SDK reads its own config file; on web the values come from
/// `--dart-define`, so a build that does not pass them simply has no Firebase.
class AwFirebase {
  AwFirebase._();

  static bool _configured = false;
  static bool _attempted = false;

  /// True once Firebase initialised successfully. False on a build with no
  /// config file, which is a supported state and not an error.
  static bool get isConfigured => _configured;

  static FirebaseAnalytics? _analytics;

  /// Analytics, or null when Firebase is not configured. Prefer [logEvent] and
  /// [setUser] over touching this — they are null-safe by construction.
  static FirebaseAnalytics? get analytics => _analytics;

  /// The observer to hand to `MaterialApp.router`, or null. Null is fine:
  /// `observers: [?AwFirebase.navigatorObserver]` drops it.
  static FirebaseAnalyticsObserver? navigatorObserver;

  /// Initialise Firebase and wire crash + performance reporting.
  ///
  /// Returns whether Firebase came up. Safe to call more than once; safe to call
  /// on a platform with no config. Never throws.
  static Future<bool> bootstrap({
    FirebaseOptions? options,
    bool collectionEnabled = true,
  }) async {
    if (_attempted) return _configured;
    _attempted = true;

    try {
      // On web the SDK cannot discover anything by itself, so absent options
      // mean absent Firebase — an explicit skip, not a caught failure.
      if (kIsWeb && options == null) return false;
      await Firebase.initializeApp(options: options);
      _configured = true;
    } on Object catch (error) {
      // A missing config file lands here (`FirebaseException`/`PlatformException`,
      // and on some platforms a plain `Exception`), which is the ordinary state
      // for a fork. Anything else lands here too — a broken Firebase must not be
      // able to stop the app from starting.
      debugPrint(
        'AllisWell: Firebase not configured — continuing without it ($error)',
      );
      return false;
    }

    await _wireCrashlytics(collectionEnabled: collectionEnabled);
    await _wireAnalytics(collectionEnabled: collectionEnabled);
    await _wirePerformance(collectionEnabled: collectionEnabled);
    return true;
  }

  static Future<void> _wireCrashlytics({
    required bool collectionEnabled,
  }) async {
    try {
      final crashlytics = FirebaseCrashlytics.instance;
      // Crashlytics is unsupported on web and Linux/Windows; the plugin throws
      // rather than no-ops on those, so the whole block is guarded.
      await crashlytics.setCrashlyticsCollectionEnabled(collectionEnabled);

      // Framework errors: keep the console output in debug (losing the red
      // screen makes UI work miserable) and report in release.
      final previousOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        previousOnError?.call(details);
        if (!kDebugMode) crashlytics.recordFlutterFatalError(details);
      };

      // Everything the framework does not catch — async gaps, isolate errors.
      PlatformDispatcher.instance.onError = (error, stack) {
        crashlytics.recordError(error, stack, fatal: true);
        return true;
      };
    } on Object catch (error) {
      debugPrint('AllisWell: Crashlytics unavailable ($error)');
    }
  }

  static Future<void> _wireAnalytics({required bool collectionEnabled}) async {
    try {
      final analytics = FirebaseAnalytics.instance;
      await analytics.setAnalyticsCollectionEnabled(collectionEnabled);
      _analytics = analytics;
      navigatorObserver = FirebaseAnalyticsObserver(analytics: analytics);
    } on Object catch (error) {
      debugPrint('AllisWell: Analytics unavailable ($error)');
    }
  }

  static Future<void> _wirePerformance({
    required bool collectionEnabled,
  }) async {
    try {
      await FirebasePerformance.instance.setPerformanceCollectionEnabled(
        collectionEnabled,
      );
    } on Object catch (error) {
      debugPrint('AllisWell: Performance monitoring unavailable ($error)');
    }
  }

  /// Turn every collector on or off at once — what the privacy toggle calls.
  static Future<void> setCollectionEnabled(bool enabled) async {
    if (!_configured) return;
    try {
      await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(enabled);
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
        enabled,
      );
      await FirebasePerformance.instance.setPerformanceCollectionEnabled(
        enabled,
      );
    } on Object catch (error) {
      debugPrint('AllisWell: could not change collection state ($error)');
    }
  }

  /// Attach the signed-in user to future reports. Pass null on sign-out.
  ///
  /// The id is AllisWell's own ULID — never an e-mail address, and never
  /// anything a user typed. Crash reports and analytics must not become a place
  /// personal data leaks into (docs/PRIVACY.md).
  static Future<void> setUser(String? userId) async {
    if (!_configured) return;
    try {
      await FirebaseAnalytics.instance.setUserId(id: userId);
      await FirebaseCrashlytics.instance.setUserIdentifier(userId ?? '');
    } on Object catch (error) {
      debugPrint('AllisWell: could not set the analytics user ($error)');
    }
  }

  /// Log a product event. A no-op when Firebase is absent, so call sites need no
  /// guard of their own.
  static Future<void> logEvent(
    String name, {
    Map<String, Object>? parameters,
  }) async {
    final analytics = _analytics;
    if (analytics == null) return;
    try {
      await analytics.logEvent(name: name, parameters: parameters);
    } on Object catch (error) {
      debugPrint('AllisWell: analytics event "$name" dropped ($error)');
    }
  }

  /// Test seam: forget that bootstrap ran.
  @visibleForTesting
  static void resetForTest() {
    _configured = false;
    _attempted = false;
    _analytics = null;
    navigatorObserver = null;
  }
}
