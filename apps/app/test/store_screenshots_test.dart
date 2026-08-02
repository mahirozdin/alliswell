// Store screenshots (docs/STORE-LISTING.md §3): the SAME real app the design
// harness renders, at the exact pixel sizes the App Store and Play require.
// Run locally with:
//
//   flutter test --update-goldens --dart-define=screenshots=true \
//       test/store_screenshots_test.dart
//
// Then copy test/goldens/store_*.png into docs/store/ (goldens are generated
// output and stay untracked), or run `npm run shots:store` which composes the
// iPad ones straight into store/ios/ipad-13/.
//
// Sizes are expressed as LOGICAL pixels at devicePixelRatio 2, so the PNG comes
// out at exactly twice the logical size — which is what the stores measure.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/sections.dart';

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

/// Devices whose store set is generated here rather than captured on real
/// hardware, and which therefore need the WHOLE story, not just a reference
/// pair. The iPhone and Android phone listings are built from real simulator
/// and emulator captures (docs/SCREENSHOTS.md §2–3); no iPad or Android tablet
/// is on hand, so these renders are the listing.
const _fullSet = {'ipad13', 'android_tablet10'};

class _Shot {
  const _Shot(this.name, {this.navigate, this.brightness = Brightness.light});

  final String name;
  final Future<void> Function(WidgetTester tester)? navigate;
  final Brightness brightness;
}

/// The order the listing tells its story in — the same one the composed phone
/// slides use (STORE-LISTING §3): Home → Board → Projects → Notes → Files →
/// dark. The numeric prefix is the slide order, so the compositor can just
/// sort by filename.
List<_Shot> _shots({required bool full}) => [
  const _Shot('1_home'),
  _Shot('2_board', navigate: design.openBoard),
  if (full) ...[
    _Shot(
      '3_projects',
      navigate: (t) => design.openSection(t, AppSection.projects),
    ),
    _Shot('4_notes', navigate: (t) => design.openSection(t, AppSection.notes)),
    _Shot('5_files', navigate: design.openFilesFolder),
    const _Shot('6_home_dark', brightness: Brightness.dark),
  ],
];

void main() {
  setUpAll(design.loadRealFontsForStore);

  for (final entry in _devices.entries) {
    final device = entry.key;
    final size = entry.value;

    for (final shot in _shots(full: _fullSet.contains(device))) {
      testWidgets('store · $device · ${shot.name}', skip: !_enabled, (
        tester,
      ) async {
        await design.shootForStore(
          tester,
          size: size,
          name: 'store_${device}_${shot.name}',
          brightness: shot.brightness,
          navigate: shot.navigate,
        );
      });
    }
  }
}
