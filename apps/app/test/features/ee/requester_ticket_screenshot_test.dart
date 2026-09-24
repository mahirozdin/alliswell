// The person who ASKED, running their request from the app (EE-252).
//
// Run locally with:
//
//   flutter test --update-goldens --dart-define=screenshots=true \
//       test/features/ee/requester_ticket_screenshot_test.dart
//
// Inert without the dart-define, like every other shot file here.
//
// TWO SHOTS, the two moments the screen exists for:
//
//   • "Waiting for you": the desk asked a question, the card says the next
//     move is theirs, and the answer is being typed into the one box there
//     is — a visible reply, with no internal note to choose.
//   • Resolved: the desk says it is done, and the two answers the person who
//     asked may give — "yes, close it" and "no, it is not".
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/data/requester_ticket_api.dart';
import 'package:alliswell/src/features/ee/requester_ticket_providers.dart';
import 'package:alliswell/src/features/ee/ui/requester_ticket_screen.dart';
import 'package:alliswell/src/features/workspaces/workspaces.dart';
import 'package:alliswell/src/i18n/i18n.dart';

import '../../design_screenshots_test.dart' show screenshotLocale;
import 'support/shot.dart';

const bool _enabled = bool.fromEnvironment('screenshots');
const _id = '01TKAAAAAAAAAAAAAAAAAAAAAA';
const _me = 'U-ME';

EeRequesterTicket _ticket(bool turkish, {required bool resolved}) =>
    EeRequesterTicket(
      id: _id,
      subject: turkish ? 'Pres 2 yağ kaçırıyor' : 'Press 2 is leaking oil',
      status: resolved ? 'resolved' : 'waiting',
      viewer: 'requester',
      number: 1042,
      body: turkish
          ? 'Pres 2’nin altında sabahtan beri yağ birikiyor.'
          : 'Oil has been pooling under press 2 since this morning.',
      waitingReason: resolved ? null : 'requester_info',
      serviceName: turkish ? 'Hat duruşu' : 'Line stop',
      updatedAt: DateTime.utc(2026, 9, 24, 9, 30),
      allowedTransitions: resolved ? const ['closed', 'in_progress'] : const [],
    );

List<EeRequesterComment> _lines(bool turkish, {required bool resolved}) => [
  EeRequesterComment(
    id: 'C1',
    body: turkish
        ? 'Kaçak hortumdan mı, silindirden mi geliyor? Bir fotoğraf ekleyebilir misiniz?'
        : 'Is it the hose or the cylinder? Could you add a photo?',
    authorId: 'U-AGENT',
    createdAt: DateTime.utc(2026, 9, 24, 8, 10),
  ),
  if (resolved) ...[
    EeRequesterComment(
      id: 'C2',
      body: turkish
          ? 'Hortum, sol taraftaki bağlantıdan.'
          : 'The hose, at the left-hand coupling.',
      authorId: _me,
      createdAt: DateTime.utc(2026, 9, 24, 8, 25),
    ),
    EeRequesterComment(
      id: 'C3',
      body: turkish
          ? 'Hortum ve conta değişti, basınç testi temiz.'
          : 'Hose and seal replaced; the pressure test is clean.',
      authorId: 'U-AGENT',
      createdAt: DateTime.utc(2026, 9, 24, 9, 30),
    ),
  ],
];

void main() {
  if (!_enabled) return;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(screenshotLocale('tr'));
  });

  for (final brightness in Brightness.values) {
    for (final resolved in [false, true]) {
      final name = resolved
          ? 'ee-requester-ticket-resolved'
          : 'ee-requester-ticket';
      testWidgets('$name — ${brightness.name}', (tester) async {
        final turkish = AwI18n.instance.locale.languageCode == 'tr';
        await eeShoot(
          tester,
          brightness: brightness,
          name: name,
          size: const Size(900, 1500),
          overrides: <Override>[
            currentUserIdProvider.overrideWithValue(_me),
            eeRequesterTicketProvider.overrideWith(
              (ref, id) async => _ticket(turkish, resolved: resolved),
            ),
            eeRequesterCommentsProvider.overrideWith(
              (ref, id) async => _lines(turkish, resolved: resolved),
            ),
          ],
          screen: const EeRequesterTicketScreen(ticketId: _id),
          afterPump: resolved
              ? null
              : (t) async {
                  await t.enterText(
                    find.byKey(const Key('ee-requester-reply')),
                    turkish
                        ? 'Hortumdan, sol bağlantıdan. Fotoğrafı birazdan eklerim.'
                        : 'The hose, at the left coupling. Photo to follow.',
                  );
                },
        );
      });
    }
  }
}
