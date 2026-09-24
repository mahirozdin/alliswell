// The service desk's screens, shot in both themes (EE-084 acceptance).
//
// Run locally with:
//
//   flutter test --update-goldens --dart-define=screenshots=true \
//       test/features/ee/tickets_screenshot_test.dart
//
// Inert without the dart-define, like every other shot file here: goldens are
// generated output, not committed, so a plain CI run must not compare against
// pictures that are not in the repository.
//
// WHY THREE SHOTS. The acceptance names three queue states, and each fails in a
// way the other two cannot show. (This header said FIVE and described a fourth,
// DETAIL shot for the internal note — a shot that has never existed in this
// file or anywhere else in the repo. EE-148 adds it; until then the comment was
// describing a picture nobody could find, which is the same defect as a
// marketing page describing a feature nobody shipped.)
//
//   • FULL is where priority has to read at a glance, finished work has to sit
//     apart without disappearing, and an urgent row has to be findable in a
//     photograph of a screen taken in a plant.
//   • EMPTY and FILTERED-EMPTY are the same absence with opposite meanings —
//     "nothing came in" is good news, "your filters exclude everything" is a
//     mistake somebody is one tap from fixing — and a screen that drew one
//     message for both would be wrong exactly when it matters.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/data/ticket_write_api.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/ticket_write_providers.dart';
import 'package:alliswell/src/features/ee/tickets_providers.dart';
import 'package:alliswell/src/features/ee/ui/ticket_queue_screen.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/providers.dart';

import '../../design_screenshots_test.dart' show screenshotLocale;
import 'support/demo_corpus.dart';
import 'support/shot.dart';

const bool _enabled = bool.fromEnvironment('screenshots');

List<Override> _overrides(
  DemoCorpus corpus,
  List<TicketRecord> rows, {
  TicketFilter? filter,
}) => [
  ticketQueueProvider.overrideWith((ref) => Stream.value(rows)),
  ticketAssigneesProvider.overrideWith((ref) => Stream.value(corpus.assignees)),
  // EE-258: who asked, on each row — the names a desk's device holds.
  eeMemberNamesProvider.overrideWith((ref) => Stream.value(corpus.memberNames)),
  // EE-225: an agent who may file one sees the way in, as on a real desk —
  // and the permission cache is not sent looking for a session.
  canProvider.overrideWith((ref, permission) => permission == 'tickets.create'),
  if (filter != null)
    ticketFilterProvider.overrideWith(() => _FixedFilter(filter)),
];

/// EE-227's pictures: the server offers the moves and answers the batch — one
/// row moved, one already was, one held by an approval — so the result sheet
/// shows every kind of line it can show.
class _ShotWrite extends Fake implements EeTicketWriteApi {
  @override
  Future<EeTicketActions?> actions(String ticketId) async =>
      const EeTicketActions(
        status: 'new',
        priority: 'normal',
        allowedTransitions: ['triage', 'in_progress', 'waiting', 'cancelled'],
        waitingReasons: ['requester_info', 'supplier', 'spare_part'],
        priorities: ['low', 'normal', 'high', 'urgent'],
      );

  @override
  Future<EeBulkResult> bulk(
    List<String> ticketIds,
    Map<String, Object> action,
  ) async => EeBulkResult(
    changed: 1,
    skipped: ticketIds.length - 1,
    rows: [
      for (var i = 0; i < ticketIds.length; i += 1)
        EeBulkRow(
          ticketId: ticketIds[i],
          changed: i == 0,
          reason: switch (i) {
            0 => null,
            1 => 'TICKET_APPROVAL_PENDING',
            _ => 'NO_CHANGE',
          },
        ),
    ],
  );
}

class _FixedFilter extends TicketFilterController {
  _FixedFilter(this._value);
  final TicketFilter _value;

  @override
  TicketFilter build() => _value;
}

void main() {
  if (!_enabled) return;

  // The rows come from the shared corpus (EE-146), so the queue, the SLA
  // dashboard and the units screen are pictures of the SAME company. They were
  // not: two subjects here existed as a second copy inside the dashboard's own
  // fixture, which is how the two happened to agree while the units screen
  // described a third company entirely.
  late DemoCorpus corpus;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // Order matters: the corpus reads the active language, and asserts rather
    // than falling back.
    AwI18n.instance.setActiveCached(screenshotLocale('tr'));
    corpus = DemoCorpus.active();
  });

  for (final brightness in Brightness.values) {
    testWidgets('the unit queue, with work in it — ${brightness.name}', (
      tester,
    ) async {
      await eeShoot(
        tester,
        brightness: brightness,
        name: 'ee-ticket-queue',
        overrides: _overrides(corpus, corpus.queue),
        screen: const EeTicketQueueScreen(),
      );
    });

    testWidgets('nothing came in — ${brightness.name}', (tester) async {
      await eeShoot(
        tester,
        brightness: brightness,
        name: 'ee-ticket-queue-empty',
        overrides: _overrides(corpus, const []),
        screen: const EeTicketQueueScreen(),
      );
    });

    // EE-227: three requests ticked — the bar is the batch's, the boxes take
    // the dots' place, and "new request" has stepped aside.
    for (final result in [false, true]) {
      final name = result ? 'ee-ticket-bulk-result' : 'ee-ticket-queue-bulk';
      testWidgets('$name — ${brightness.name}', (tester) async {
        await eeShoot(
          tester,
          brightness: brightness,
          name: name,
          overrides: [
            ..._overrides(corpus, corpus.queue),
            eeFeatureProvider.overrideWith((ref, feature) => true),
            eeTicketWriteApiProvider.overrideWithValue(_ShotWrite()),
            syncEngineProvider.overrideWithValue(null),
          ],
          screen: const EeTicketQueueScreen(),
          afterPump: (t) async {
            final cards = find.byType(Card);
            await t.longPress(cards.at(0));
            await t.pumpAndSettle();
            await t.tap(cards.at(1));
            await t.tap(cards.at(2));
            await t.pumpAndSettle();
            if (result) {
              await t.tap(find.byKey(const Key('bulk-status')));
              await t.pumpAndSettle();
              await t.tap(find.byKey(const Key('bulk-status-triage')));
              await t.pumpAndSettle();
            }
          },
        );
      });
    }

    // The SAME emptiness, the opposite meaning. Two shots because one message
    // for both states would be wrong exactly when somebody is stuck.
    testWidgets('the filter excludes everything — ${brightness.name}', (
      tester,
    ) async {
      await eeShoot(
        tester,
        brightness: brightness,
        name: 'ee-ticket-queue-filtered',
        overrides: _overrides(
          corpus,
          const [],
          filter: const TicketFilter(statuses: {'waiting'}),
        ),
        screen: const EeTicketQueueScreen(),
      );
    });
  }
}
