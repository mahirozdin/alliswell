import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/theme/tokens.dart';

import '../projects/fake_api.dart';
import 'ai_fab_test.dart' show signedInApp;

/// OPH-397 (polish 3, J-07 + HK-2; DESIGN §47 F3) — the microphone is the
/// QUIET half of the action cluster: a `secondaryContainer` fill, lower than
/// the "+", still a 48 pt target. The lavender fill measures 1.27:1 on a white
/// card, so on its own it has no visible edge (I-11 asks ≥ 3:1 for a control's
/// boundary). The edge is a 1 px `outline` ring, and this test measures that
/// ring against every ground the floating button can sit on — the page (veil
/// over each aurora blob peak and the flat wash) and every solid surface a
/// list scrolls under it — in both themes.
double _lum(Color c) {
  double f(double v) =>
      v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
}

double _ratio(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Every ground under the floating cluster, opaque.
Map<String, Color> _grounds(ColorScheme s, AwTokens t) {
  final g = <String, Color>{
    'surface': s.surface,
    'surfaceDim': s.surfaceDim,
    'surfaceBright': s.surfaceBright,
    'surfaceContainerLowest': s.surfaceContainerLowest,
    'surfaceContainerLow': s.surfaceContainerLow,
    'surfaceContainer': s.surfaceContainer,
    'surfaceContainerHigh': s.surfaceContainerHigh,
    'surfaceContainerHighest': s.surfaceContainerHighest,
  };
  for (final end in {
    'auroraTop': t.auroraTop,
    'auroraBottom': t.auroraBottom,
  }.entries) {
    g['${end.key} flat'] = Color.alphaBlend(t.veil, end.value);
    for (final blob in {
      'blobA': t.blobA,
      'blobB': t.blobB,
      'blobC': t.blobC,
    }.entries) {
      g['${blob.key} peak on ${end.key}'] = Color.alphaBlend(
        t.veil,
        Color.alphaBlend(blob.value, end.value),
      );
    }
  }
  return g;
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('the microphone is a quiet secondaryContainer with a '
        '>= 3:1 edge (${brightness.name})', (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      final api = FakeApi()..seedAiConnection(provider: 'anthropic');
      await tester.pumpWidget(await signedInApp(api));
      await tester.pumpAndSettle();

      final fab = find.byKey(const Key('ai-fab'));
      expect(fab, findsOneWidget);
      final ctx = tester.element(fab);
      final scheme = Theme.of(ctx).colorScheme;
      final tokens = Theme.of(ctx).extension<AwTokens>()!;
      expect(scheme.brightness, brightness);

      // Still the full 48 pt target (G4).
      expect(tester.getSize(fab), const Size(kAwMicFabSize, kAwMicFabSize));

      final material = tester.widget<Material>(
        find.descendant(of: fab, matching: find.byType(Material)).first,
      );
      // Quiet surface: the secondary container, never the primary fill.
      expect(material.color, scheme.secondaryContainer);

      // Quieter than the "+": a lower resting elevation.
      final plus = tester.widget<FloatingActionButton>(
        find.widgetWithIcon(FloatingActionButton, Icons.add),
      );
      final plusElevation =
          plus.elevation ??
          Theme.of(ctx).floatingActionButtonTheme.elevation ??
          6;
      expect(material.elevation, lessThan(plusElevation));

      // The glyph: >= 4.5:1 on the fill (stricter than the 3:1 an icon needs).
      final icon = tester.widget<IconTheme>(
        find
            .ancestor(
              of: find.byIcon(Icons.mic_none_outlined),
              matching: find.byType(IconTheme),
            )
            .first,
      );
      expect(
        _ratio(icon.data.color!, material.color!),
        greaterThanOrEqualTo(4.5),
      );

      // The edge: a visible ring whose colour clears 3:1 on every ground.
      final shape = material.shape;
      expect(shape, isA<CircleBorder>());
      final side = (shape! as CircleBorder).side;
      expect(side.style, BorderStyle.solid);
      expect(side.width, greaterThanOrEqualTo(1));
      final failures = <String>[];
      for (final g in _grounds(scheme, tokens).entries) {
        final r = _ratio(side.color, g.value);
        if (r < 3.0) failures.add('${g.key}: ${r.toStringAsFixed(2)}');
      }
      expect(failures, isEmpty, reason: 'ring below 3:1 on: $failures');
    });
  }
}
