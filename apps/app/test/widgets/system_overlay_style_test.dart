import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/theme/theme.dart';

/// OPH-391 (U-43): the status bar follows the THEME, not the colour under it.
///
/// The app bars are transparent, so Flutter guessed the status bar's style
/// from a transparent colour — read as dark — and drew white clock and signal
/// icons on the light theme's pale aurora (~1.2:1 on iOS).
void main() {
  Future<SystemUiOverlayStyle?> styleOf(
    WidgetTester tester,
    Brightness brightness, {
    required bool appBar,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAwTheme(brightness),
        builder: (context, child) => AwSystemOverlay(child: child!),
        home: Scaffold(
          appBar: appBar ? AppBar(title: const Text('Task')) : null,
          body: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pump();
    return SystemChrome.latestStyle;
  }

  for (final appBar in [true, false]) {
    final where = appBar ? 'under an app bar' : 'on a page without one';

    testWidgets('light theme: dark status bar content $where', (tester) async {
      final style = await styleOf(tester, Brightness.light, appBar: appBar);
      expect(style?.statusBarBrightness, Brightness.light); // iOS
      expect(style?.statusBarIconBrightness, Brightness.dark); // Android
    });

    testWidgets('dark theme: light status bar content $where', (tester) async {
      final style = await styleOf(tester, Brightness.dark, appBar: appBar);
      expect(style?.statusBarBrightness, Brightness.dark);
      expect(style?.statusBarIconBrightness, Brightness.light);
    });
  }

  test('the theme carries the same style its app bars use', () {
    for (final brightness in Brightness.values) {
      expect(
        buildAwTheme(brightness).appBarTheme.systemOverlayStyle,
        awSystemOverlayStyle(brightness),
      );
    }
  });
}
