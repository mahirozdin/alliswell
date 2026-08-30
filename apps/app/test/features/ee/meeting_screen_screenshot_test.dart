// The meeting screen, shot in both themes (EE-115's acceptance).
//
// Run locally with:
//
//   flutter test --update-goldens --dart-define=screenshots=true \
//       test/features/ee/meeting_screen_screenshot_test.dart
//
// Inert without the dart-define, like every other shot file here: goldens are
// generated output, not committed, so a plain CI run must not compare against
// pictures that are not in the repository.
//
// WHY TWO SHOTS, AND WHY THEY DIFFER ONLY IN NAMES. The first is the screen as
// the diarizer leaves it — "A" and "B", which is all a machine can honestly
// say. The second is the same meeting after a human answered "who is B?". The
// pair is the feature: one rename reaches the speaker rail, every line she
// said, AND the decision she owes, because nothing on the screen renders a raw
// label. A reviewer can check that by looking, which is worth more here than
// in most places — the alternative implementation (rewriting the transcript on
// rename) produces an identical first picture and a subtly wrong second one.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/data/meeting_models.dart';
import 'package:alliswell/src/features/ee/meetings_providers.dart';
import 'package:alliswell/src/features/ee/ui/meeting_screen.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';
import 'package:alliswell/src/widgets/glass.dart';

import '../../design_screenshots_test.dart' show loadRealFontsForStore;

const bool _enabled = bool.fromEnvironment('screenshots');

/// The theme's own fontFamily is null (platform font, DESIGN §3.3) and the
/// test engine draws that as BOX GLYPHS — every shot file here learned it the
/// same way.
const String _screenshotFamily = 'ScreenshotSans';

EeTranscriptSegment _seg(int i, String speaker, String text) =>
    EeTranscriptSegment(
      speaker: speaker,
      startMs: i * 47000,
      endMs: i * 47000 + 40000,
      text: text,
    );

EeMeetingDetail _detail(Map<String, String> names) => EeMeetingDetail(
  summary: EeMeetingSummary(
    id: 'M1',
    workspaceId: 'W1',
    status: EeMeetingStatus.ready,
    attempts: 1,
    decisionCount: 2,
    ideaCount: 1,
    createdAt: DateTime(2026, 8, 30, 9),
    title: 'Haftalık üretim toplantısı',
    summary:
        'Hat 3 vardiya boyunca iki kez durdu. Rulman sıcaklığı sebep olarak '
        'görüldü; bakım vardiyası bir saat öne alınacak ve yedek parça '
        'siparişi bugün girilecek.',
    durationMs: 3480000,
    noteId: 'N1',
  ),
  decisions: const [
    EeMeetingDecision(
      text: 'Bakım vardiyası bir saat öne alınacak',
      owner: 'B',
    ),
    EeMeetingDecision(
      text: 'Yedek rulman siparişi bugün girilecek',
      owner: 'A',
    ),
  ],
  ideas: const ['Rulmanlara titreşim sensörü denemesi yapılabilir'],
  speakerNames: names,
  transcript: EeTranscript(
    segments: [
      _seg(0, 'A', 'Toplantıya hoş geldiniz. Gündemde üç madde var.'),
      _seg(1, 'B', 'Hat 3 bu vardiyada iki kez durdu.'),
      _seg(2, 'A', 'Sebebi ne çıktı?'),
      _seg(3, 'B', 'Rulman ısındı. Bakımı bir saat öne alalım.'),
      _seg(4, 'C', 'Yedek parça stoğu iki takım kaldı, sipariş gerekiyor.'),
    ],
    speakers: const ['A', 'B', 'C'],
    durationMs: 3480000,
    language: 'tr',
  ),
);

void main() {
  if (!_enabled) return;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('tr'));
  });

  Future<void> shoot(
    WidgetTester tester,
    Brightness brightness,
    String name, {
    required Map<String, String> names,
  }) async {
    await loadRealFontsForStore();
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    debugDisableShadows = false;
    try {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            eeMeetingProvider(
              'M1',
            ).overrideWith((ref) => Future.value(_detail(names))),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildAwTheme(
              brightness,
              fontFamilyOverride: _screenshotFamily,
            ),
            home: const AwPageBackground(
              child: EeMeetingScreen(meetingId: 'M1'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../goldens/$name-${brightness.name}.png'),
      );
    } finally {
      debugDisableShadows = true;
    }
  }

  for (final brightness in Brightness.values) {
    testWidgets('meeting, speakers unnamed (${brightness.name})', (
      tester,
    ) async {
      await shoot(tester, brightness, 'ee-meeting', names: const {});
    });
    testWidgets('meeting, speakers named (${brightness.name})', (tester) async {
      await shoot(
        tester,
        brightness,
        'ee-meeting-named',
        names: const {'A': 'Ayşe', 'B': 'Barış', 'C': 'Cem'},
      );
    });
  }
}
