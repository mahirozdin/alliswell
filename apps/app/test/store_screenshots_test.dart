// Store screenshots (docs/STORE-LISTING.md §3): the SAME real app the design
// harness renders, at the exact pixel sizes the App Store and Play require.
// Run locally with:
//
//   flutter test --update-goldens --dart-define=screenshots=true \
//       test/store_screenshots_test.dart
//
// Then copy test/goldens/store_*.png into docs/store/ (goldens are generated
// output and stay untracked).
//
// Sizes are expressed as LOGICAL pixels at devicePixelRatio 2, so the PNG comes
// out at exactly twice the logical size — which is what the stores measure.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'design_screenshots_test.dart' as design;

const bool _enabled = bool.fromEnvironment('screenshots');

/// device → (logical size, required PNG size)
/// iPhone 6.9" 1290×2796 · iPhone 6.5" 1242×2688 · iPad 13" 2064×2752
/// Android phone 1080×1920 · Android 10" tablet 1600×2560
const _devices = <String, Size>{
  'iphone69': Size(645, 1398),
  'iphone65': Size(621, 1344),
  'ipad13': Size(1032, 1376),
  'android_phone': Size(540, 960),
  'android_tablet10': Size(800, 1280),
};

void main() {
  setUpAll(design.loadRealFontsForStore);

  for (final entry in _devices.entries) {
    final device = entry.key;
    final size = entry.value;

    testWidgets('store · $device · home', skip: !_enabled, (tester) async {
      await design.shootForStore(
        tester,
        size: size,
        name: 'store_${device}_1_home',
      );
    });

    testWidgets('store · $device · board', skip: !_enabled, (tester) async {
      await design.shootForStore(
        tester,
        size: size,
        name: 'store_${device}_2_board',
        openBoard: true,
      );
    });
  }
}
