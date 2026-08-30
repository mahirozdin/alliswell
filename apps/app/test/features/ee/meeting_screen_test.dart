import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/data/meeting_models.dart';
import 'package:alliswell/src/features/ee/meetings_providers.dart';
import 'package:alliswell/src/features/ee/ui/meeting_screen.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';

/// EE-115 — the transcript viewer, asserted where it would mislead.
///
/// The claim this file exists for is the rename: naming speaker "B" has to
/// reach every line she said, and it does because nothing on the screen
/// renders `segment.speaker` directly — everything goes through
/// `displayName`. So the test renames one speaker and checks a line she said
/// NEAR THE END, not the first one: a rename that only reached the top would
/// pass a lazier assertion.
///
/// The second is `transcribed`. It is a WAITING state — the words are safe and
/// the note is missing — and drawing it as finished would tell somebody their
/// meeting is ready when half of it is not there. It gets the warning mark and
/// a sentence that says so.
///
/// Finders are keyed by INDEX throughout. Four speakers share 1 800 rows
/// between them, so "the row where B speaks" matches 450 of them — E11 lost
/// three CI runs to exactly that shape of finder.

EeTranscriptSegment _seg(int i, String speaker, String text) =>
    EeTranscriptSegment(
      speaker: speaker,
      startMs: i * 65000,
      endMs: i * 65000 + 60000,
      text: text,
    );

EeMeetingDetail _detail({
  EeMeetingStatus status = EeMeetingStatus.ready,
  Map<String, String> names = const {},
  bool withTranscript = true,
  String? failureMessage,
}) => EeMeetingDetail(
  summary: EeMeetingSummary(
    id: 'M1',
    workspaceId: 'W1',
    status: status,
    attempts: 1,
    decisionCount: 1,
    ideaCount: 1,
    createdAt: DateTime(2026, 8, 30, 9),
    title: 'Haftalık üretim toplantısı',
    summary: 'Hat 3 iki kez durdu; bakım vardiyası öne alınacak.',
    durationMs: 3600000,
    noteId: 'N1',
    failureMessage: failureMessage,
  ),
  decisions: const [
    EeMeetingDecision(
      text: 'Bakım vardiyası bir saat öne alınacak',
      owner: 'B',
    ),
  ],
  ideas: const ['Titreşim sensörü denemesi'],
  speakerNames: names,
  transcript: withTranscript
      ? EeTranscript(
          segments: [
            _seg(0, 'A', 'Toplantıya hoş geldiniz.'),
            _seg(1, 'B', 'Hat 3 iki kez durdu.'),
            _seg(2, 'A', 'Sebebi ne?'),
            _seg(3, 'B', 'Rulman ısındı; bakımı öne alalım.'),
          ],
          speakers: const ['A', 'B'],
          durationMs: 3600000,
          language: 'tr',
        )
      : null,
);

Future<void> _pump(
  WidgetTester tester,
  EeMeetingDetail? value, {
  Brightness brightness = Brightness.light,
  // A meeting still working draws a spinner, and a spinner never stops — so
  // `pumpAndSettle` waits for an animation that has no end and times out.
  // Those cases pump a frame instead, which is enough: the claim is what the
  // screen SAYS, not that it has stopped moving.
  bool settle = true,
}) async {
  // A TALL surface, on purpose. The transcript is a lazy list: a row that has
  // not been laid out has no element, so on the default 800x600 canvas the
  // later segments simply are not in the tree and "the rename did not reach
  // row 3" would be indistinguishable from "row 3 is off screen". The claim
  // under test is about content, so the viewport is made big enough for the
  // content rather than the assertions being weakened to fit it.
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        eeMeetingProvider('M1').overrideWith((ref) => Future.value(value)),
      ],
      child: MaterialApp(
        theme: buildAwTheme(brightness),
        home: const EeMeetingScreen(meetingId: 'M1'),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Finder _inRow(int index, String text) => find.descendant(
  of: find.byKey(Key('meeting-segment-$index')),
  matching: find.textContaining(text),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('en'));
  });

  testWidgets('unnamed speakers show the vendor label, everywhere', (
    tester,
  ) async {
    await _pump(tester, _detail());
    expect(_inRow(0, 'A'), findsWidgets);
    expect(_inRow(3, 'B'), findsWidgets);
    // The decision's owner is a label too, and reads as one until it is named.
    expect(
      find.descendant(
        of: find.byKey(const Key('meeting-decision-0')),
        matching: find.text('B'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'a name reaches every line that speaker said — including the last',
    (tester) async {
      await _pump(tester, _detail(names: const {'B': 'Ayşe'}));

      // Row 3 is the LAST thing B said. A rename that only reached the first
      // occurrence would pass an assertion about row 1 and fail this one.
      expect(_inRow(1, 'Ayşe'), findsOneWidget);
      expect(_inRow(3, 'Ayşe'), findsOneWidget);
      // And the other speaker is untouched.
      expect(_inRow(0, 'A'), findsWidgets);
      // The chip carries the name too, so "who is B?" is answered where it was
      // asked.
      expect(
        find.descendant(
          of: find.byKey(const Key('meeting-speaker-B')),
          matching: find.text('Ayşe'),
        ),
        findsOneWidget,
      );
      // And the decision it belongs to now names a person rather than a letter.
      expect(
        find.descendant(
          of: find.byKey(const Key('meeting-decision-0')),
          matching: find.text('Ayşe'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('every segment carries its position in the recording', (
    tester,
  ) async {
    await _pump(tester, _detail());
    // 0:00, 1:05, 2:10, 3:15 — the link between the text and the audio.
    expect(_inRow(0, '0:00'), findsOneWidget);
    expect(_inRow(1, '1:05'), findsOneWidget);
    expect(_inRow(3, '3:15'), findsOneWidget);
  });

  testWidgets('an hour reads as 1:00:00, not 60:00', (tester) async {
    await _pump(tester, _detail());
    // The duration beside the status: past an hour the clock grows a field.
    expect(find.textContaining('1:00:00'), findsOneWidget);
  });

  testWidgets('transcribed is drawn as WAITING, not as done', (tester) async {
    await _pump(tester, _detail(status: EeMeetingStatus.transcribed));
    expect(find.byKey(const Key('meeting-status-mark')), findsOneWidget);
    // The word does the work; the colour only marks it.
    expect(
      find.textContaining('the note is still being written'),
      findsOneWidget,
    );
  });

  testWidgets('a meeting still working says so and shows it', (tester) async {
    await _pump(
      tester,
      _detail(status: EeMeetingStatus.transcribing),
      settle: false,
    );
    expect(find.textContaining('Transcribing'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('no transcript yet: the summary still reads', (tester) async {
    await _pump(
      tester,
      _detail(status: EeMeetingStatus.summarizing, withTranscript: false),
      settle: false,
    );
    expect(find.textContaining('Hat 3 iki kez durdu'), findsOneWidget);
    // No transcript section, and no speaker rail to name nobody with.
    expect(find.byKey(const Key('meeting-segment-0')), findsNothing);
    expect(find.byKey(const Key('meeting-speaker-A')), findsNothing);
  });

  testWidgets('no licence, no screen: the door says why', (tester) async {
    await _pump(tester, null);
    expect(find.textContaining('not available here'), findsOneWidget);
  });

  testWidgets('the dark theme renders the same claims', (tester) async {
    await _pump(
      tester,
      _detail(names: const {'B': 'Ayşe'}),
      brightness: Brightness.dark,
    );
    expect(_inRow(3, 'Ayşe'), findsOneWidget);
    expect(_inRow(1, '1:05'), findsOneWidget);
  });
}
