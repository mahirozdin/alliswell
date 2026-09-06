// One request, opened — and its history (EE-148).
//
// Run locally with:
//
//   flutter test --update-goldens --dart-define=screenshots=true \
//       test/features/ee/ticket_detail_screenshot_test.dart
//
// Inert without the dart-define, like every other shot file here.
//
// WHY TWO SHOTS, AND WHY THIS SCREEN AT ALL.
//
//   • THE THREAD exists for the internal note. An agent who mistakes it for a
//     reply to the customer has said the wrong thing to the wrong person, and
//     the screen carries the distinction three ways at once — a tinted card, a
//     lock, and the word — because any one alone fails somebody: colour fails
//     a colour-blind reader, the icon fails at a glance on a dirty screen, and
//     the word fails nobody but is the easiest to skim past. A picture of that
//     is a picture of the argument.
//   • HISTORY is the page's "who changed this" claim, and the claim is only
//     honest if the answer can be somebody other than a person. One entry is
//     `system`: an SLA sweep breached this ticket, and the widget says so
//     rather than blaming the last human who touched it.
//
// The team-wide audit screen is NOT photographed. EeAuditLogScreen is written
// and tested but reachable from nothing in router.dart, and a marketing page
// that shows a screen a customer cannot open is selling a picture.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/history_providers.dart';
import 'package:alliswell/src/features/ee/tickets_providers.dart';
import 'package:alliswell/src/features/ee/ui/ticket_detail_screen.dart';
import 'package:alliswell/src/i18n/i18n.dart';

import '../../design_screenshots_test.dart' show screenshotLocale;
import 'support/demo_corpus.dart';
import 'support/shot.dart';

const bool _enabled = bool.fromEnvironment('screenshots');

/// The second row of the SLA dashboard's missed-targets list, opened.
///
/// NOT the queue's top row, though that was the first draft: that row is `new`,
/// and a request carrying three messages has plainly been picked up. A picture
/// whose status contradicts its own conversation is exactly what the reader
/// this page is written for notices. T5 is in_progress, urgent and breached —
/// so the screens still link to each other and nothing has to be untrue.
const String _ticketId = 'T5';

List<Override> _overrides(DemoCorpus corpus) {
  final ticket = corpus.ticket(_ticketId);
  return [
    ticketProvider.overrideWith((ref, id) => Stream.value(ticket)),
    ticketCommentsProvider.overrideWith(
      (ref, id) => Stream.value(corpus.commentsFor(_ticketId)),
    ),
    ticketAssigneesProvider.overrideWith(
      (ref) => Stream.value(corpus.assignees),
    ),
    eeHistoryProvider.overrideWith((ref, target) async {
      return corpus.historyFor(_ticketId);
    }),
  ];
}

void main() {
  if (!_enabled) return;

  late DemoCorpus corpus;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // Order matters: the corpus reads the active language and asserts rather
    // than falling back to one.
    AwI18n.instance.setActiveCached(screenshotLocale('tr'));
    corpus = DemoCorpus.active();
  });

  for (final brightness in Brightness.values) {
    testWidgets('one request, with an internal note — ${brightness.name}', (
      tester,
    ) async {
      await eeShoot(
        tester,
        brightness: brightness,
        name: 'ee-ticket-detail',
        size: const Size(900, 1300),
        overrides: _overrides(corpus),
        screen: const EeTicketDetailScreen(ticketId: _ticketId),
      );
    });

    testWidgets('and what happened to it — ${brightness.name}', (tester) async {
      await eeShoot(
        tester,
        brightness: brightness,
        name: 'ee-ticket-history',
        // Shorter than the thread's frame: five entries do not fill 1300, and
        // a picture that is 40% empty reads as a screen with nothing in it.
        size: const Size(900, 950),
        overrides: _overrides(corpus),
        screen: const EeTicketDetailScreen(ticketId: _ticketId),
        // The second tab is the shot. Tapping it rather than rendering the tab
        // body directly keeps the tab bar in frame, which is what tells a
        // reader the history lives beside the conversation.
        afterPump: (t) => t.tap(find.byType(Tab).at(1)),
      );
    });
  }
}
