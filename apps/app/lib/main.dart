import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app.dart';
import 'src/core/retry.dart';

void main() {
  // `retry`: without it Riverpod 3 retries every failed provider ten times
  // behind a spinner — including errors no retry can fix (core/retry.dart).
  runApp(const ProviderScope(retry: awRetry, child: AllisWellApp()));
}
