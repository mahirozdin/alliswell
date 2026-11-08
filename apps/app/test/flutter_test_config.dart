import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/format_region.dart';
import 'package:alliswell/src/i18n/i18n.dart';

/// Flutter's official per-suite hook (auto-discovered at `test/`): it wraps every
/// test file. Epic 11 (ADR-0009) loads translations synchronously before the
/// first frame; here we do the same for tests — read the JSON straight off disk
/// (`flutter test` runs on the VM) and pre-load `en` (+ `tr`, so a language-switch
/// test can flip locale synchronously). After this, `'key'.tr()` resolves at
/// build time and widget tests pump/settle exactly as before — no `runAsync`.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  awI18nAssetReader = (assetPath) => File(assetPath).readAsString();
  await AwI18n.instance.loadForTest(
    const Locale('en'),
    also: const [Locale('tr')],
  );
  await initializeDateFormatting();
  // OPH-408: dates and numbers follow the device REGION. A suite must not
  // depend on the machine running it, so by default "the device says
  // nothing" and the app language's own conventions apply (tr → 24h, "6,3";
  // en → US). Region tests pass `region:` or set this hook themselves.
  awDeviceRegionOverride = () => null;
  await testMain();
}
