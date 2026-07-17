import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'src/app.dart';
import 'src/core/retry.dart';
import 'src/i18n/i18n.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Loads the persisted/device locale + fallback synchronously into memory
  // before the first frame — no language flicker, and `.tr()` resolves at build
  // time (Epic 11, ADR-0009).
  await AwI18n.instance.boot();
  // Locale-aware date/number formatting (OPH-123 — task due dates, etc.).
  await initializeDateFormatting();
  // `retry`: without it Riverpod 3 retries every failed provider ten times
  // behind a spinner — including errors no retry can fix (core/retry.dart).
  runApp(const ProviderScope(retry: awRetry, child: AllisWellApp()));
}
