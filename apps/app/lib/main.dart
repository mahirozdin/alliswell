import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'src/app.dart';
import 'src/core/firebase/firebase_bootstrap.dart';
import 'src/core/retry.dart';
import 'src/features/widgets/widget_callback.dart';
import 'src/features/widgets/widget_host.dart';
import 'src/i18n/i18n.dart';

/// The home-screen widget's background entry point (OPH-188).
///
/// `vm:entry-point` is MANDATORY: this is invoked from a background isolate the
/// app never started, so tree-shaking would otherwise remove it and the widget's
/// buttons would silently do nothing in release builds only.
@pragma('vm:entry-point')
Future<void> widgetCallback(Uri? uri) async {
  final changed = await handleWidgetAction(uri);
  if (!changed) return;
  // Redraw with the new state. The app is not running, so nothing else will.
  await HomeWidget.updateWidget(
    iOSName: kWidgetIosName,
    androidName: kWidgetAndroidProvider,
    qualifiedAndroidName: 'com.alliswell.alliswell.$kWidgetAndroidProvider',
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Registered before the first frame so a press that arrives during launch is
  // not dropped. No-op off mobile.
  if (!kIsWeb) {
    HomeWidget.registerInteractivityCallback(widgetCallback);
  }
  // Loads the persisted/device locale + fallback synchronously into memory
  // before the first frame — no language flicker, and `.tr()` resolves at build
  // time (Epic 11, ADR-0009).
  await AwI18n.instance.boot();
  // Locale-aware date/number formatting (OPH-123 — task due dates, etc.).
  await initializeDateFormatting();
  // Optional, and awaited on purpose: Crashlytics can only report the errors
  // that happen AFTER its handlers are installed, so a crash during the first
  // frame is exactly what would be lost by firing this off unawaited. It
  // returns false — quickly — on any build without a Firebase config file, so
  // this costs a fork nothing (ADR-0025).
  await AwFirebase.bootstrap();
  // `retry`: without it Riverpod 3 retries every failed provider ten times
  // behind a spinner — including errors no retry can fix (core/retry.dart).
  runApp(const ProviderScope(retry: awRetry, child: AllisWellApp()));
}
