import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/files/providers.dart';

/// Taps an [AttachButton] and chooses a named way in (OPH-244).
///
/// Under `flutter_test`, `defaultTargetPlatform` is forced to android, so every
/// widget test sees the three-item menu and the sheet interposes itself between
/// the tap and the picker. This walks both steps so the tests that only care
/// about "a file got attached" stay one line long.
Future<void> tapAttach(
  WidgetTester tester,
  Finder button, {
  AttachSource via = AttachSource.anyFile,
}) async {
  await tester.tap(button);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key(attachSourceSheetKey(via))));
  await tester.pumpAndSettle();
}
