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
//   • THE TWO DOORS (EE-224): the status sheet lists what the SERVER said
//     this agent may do — and the priority sheet derives from the desk's own
//     table. A picture of a list the app did not write is the argument that
//     the app carries no second lifecycle.
//   • HISTORY is the page's "who changed this" claim, and the claim is only
//     honest if the answer can be somebody other than a person. One entry is
//     `system`: an SLA sweep breached this ticket, and the widget says so
//     rather than blaming the last human who touched it.
//
// The team-wide audit screen is NOT photographed. EeAuditLogScreen is written
// and tested but reachable from nothing in router.dart, and a marketing page
// that shows a screen a customer cannot open is selling a picture.
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/assignments_providers.dart';
import 'package:alliswell/src/features/ee/data/ticket_links_models.dart';
import 'package:alliswell/src/features/ee/data/ticket_write_api.dart';
import 'package:alliswell/src/features/ee/history_providers.dart';
import 'package:alliswell/src/features/ee/kb_providers.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/data/services_models.dart';
import 'package:alliswell/src/features/ee/services_providers.dart';
import 'package:alliswell/src/features/ee/ticket_links_providers.dart';
import 'package:alliswell/src/features/ee/ticket_write_providers.dart';
import 'package:alliswell/src/features/ee/tickets_providers.dart';
import 'package:alliswell/src/features/ee/ui/ticket_detail_screen.dart';
import 'package:alliswell/src/features/files/providers.dart';
import 'package:alliswell/src/features/workspaces/workspaces.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/providers.dart';

import '../../design_screenshots_test.dart' show screenshotLocale;
import 'support/demo_corpus.dart';
import 'support/shot.dart';
import 'package:alliswell/src/features/ee/worklog_providers.dart';

const bool _enabled = bool.fromEnvironment('screenshots');

/// What the server says an AGENT on T5 may do (EE-224): the endings stay —
/// the default member role holds `tickets.close` — and the override does not.
/// T5 is a stopped paint shop, so its inputs are the whole site and high,
/// which the shipped table turns into the `urgent` the corpus already says.
class _ShotActionsApi extends Fake implements EeTicketWriteApi {
  @override
  Future<EeTicketActions?> actions(String ticketId) async =>
      const EeTicketActions(
        status: 'in_progress',
        priority: 'urgent',
        impact: 'site',
        urgency: 'high',
        allowedTransitions: ['waiting', 'resolved', 'cancelled'],
        waitingReasons: [
          'requester_info',
          'supplier',
          'spare_part',
          'approval',
          'planned_window',
        ],
        priorities: ['low', 'normal', 'high', 'urgent'],
        canAssignOthers: true,
      );

  @override
  Future<EePriorityMatrix?> priorityMatrix() async => const EePriorityMatrix(
    customised: true,
    cells: {
      'person': {'low': 'low', 'medium': 'low', 'high': 'normal'},
      'unit': {'low': 'normal', 'medium': 'normal', 'high': 'high'},
      'site': {'low': 'normal', 'medium': 'high', 'high': 'urgent'},
    },
  );
}

/// The second row of the SLA dashboard's missed-targets list, opened.
///
/// NOT the queue's top row, though that was the first draft: that row is `new`,
/// and a request carrying three messages has plainly been picked up. A picture
/// whose status contradicts its own conversation is exactly what the reader
/// this page is written for notices. T5 is in_progress, urgent and breached —
/// so the screens still link to each other and nothing has to be untrue.
const String _ticketId = 'T5';

List<Override> _overrides(
  DemoCorpus corpus, {
  bool canComment = false,
  TicketRecord? ticket,
  List<TicketCommentRecord>? comments,
}) {
  final shown = ticket ?? corpus.ticket(_ticketId);
  return [
    // EE-189/190/196/198 added sections to this screen after these shots were
    // last taken, and this file — inert without the dart-define — never
    // noticed: each section reached for the network or the device database,
    // and every shot here failed on a missing plugin (found in EE-223). They
    // are overridden to what the demo corpus holds for T5, which is nothing,
    // so the pictures stay about the conversation.
    targetFilesProvider.overrideWith((ref, target) => Stream.value(const [])),
    eeTicketExternalFilesProvider.overrideWith(
      (ref, id) async => EeExternalFiles.none,
    ),
    eeTicketRelationsProvider.overrideWith(
      (ref, id) async => const EeTicketRelations(),
    ),
    eeKbSuggestionsProvider.overrideWith((ref, subject) async => const []),
    eeKbOfTicketProvider.overrideWith((ref, id) async => const []),
    // Only the verb a shot is about — the permission cache would otherwise
    // go looking for a session.
    canProvider.overrideWith(
      (ref, permission) => canComment && permission == 'tickets.comment',
    ),
    ticketProvider.overrideWith((ref, id) => Stream.value(shown)),
    ticketCommentsProvider.overrideWith(
      (ref, id) => Stream.value(comments ?? corpus.commentsFor(_ticketId)),
    ),
    ticketAssigneesProvider.overrideWith(
      (ref) => Stream.value(corpus.assignees),
    ),
    // EE-258: who asked — the names a desk's device holds.
    eeMemberNamesProvider.overrideWith(
      (ref) => Stream.value(corpus.memberNames),
    ),
    // EE-224: the detail's own "who is on it" row, from the same corpus.
    ticketAssigneesForProvider(_ticketId).overrideWith(
      (ref) => Stream.value(corpus.assignees[_ticketId] ?? const []),
    ),
    // …and the unit's roster, so the row's door shows as it would on a desk.
    workspaceRosterOfProvider.overrideWith(
      (ref, workspaceId) => Stream.value(corpus.memberProfiles(workspaceId)),
    ),
    eeHistoryProvider.overrideWith((ref, target) async {
      return corpus.historyFor(_ticketId);
    }),
    // EE-208: the demo corpus has no hours, and a shot of an empty section
    // would teach a reader that this product does not record them.
    eeWorklogProvider.overrideWith((ref, id) async => null),
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

    // EE-254: a request that arrived as mail claiming a colleague's address,
    // and one reply that did the same — said on both, and on nothing else.
    testWidgets('and a sender that could not be checked — ${brightness.name}', (
      tester,
    ) async {
      final claimed = corpus
          .commentsFor(_ticketId)
          .firstWhere((c) => !c.internal)
          .id;
      // As the mail door files it: the request opened by mail for somebody
      // outside, and the claiming reply written by nobody on the team.
      final ticket = corpus
          .ticket(_ticketId)
          .copyWith(source: 'email', requesterId: const Value(null));
      final comments = [
        for (final c in corpus.commentsFor(_ticketId))
          c.id == claimed ? c.copyWith(authorId: const Value(null)) : c,
      ];
      await eeShoot(
        tester,
        brightness: brightness,
        name: 'ee-ticket-sender-unverified',
        size: const Size(900, 1300),
        overrides: [
          ..._overrides(corpus, ticket: ticket, comments: comments),
          eeTicketActionsProvider(_ticketId).overrideWith(
            (ref) async => EeTicketActions(
              status: 'in_progress',
              priority: 'urgent',
              senderUnverified: true,
              unverifiedCommentIds: {claimed},
            ),
          ),
        ],
        screen: const EeTicketDetailScreen(ticketId: _ticketId),
      );
    });

    // EE-258 (AW-E07): a customer with no account wrote in by mail — the desk
    // reads who, where the answer goes, and how it arrived, from the device.
    testWidgets('and who asked, by mail — ${brightness.name}', (tester) async {
      final ticket = corpus
          .ticket(_ticketId)
          .copyWith(
            source: 'email',
            requesterId: const Value(null),
            requesterName: const Value('Ada Lovelace'),
            requesterEmail: const Value('ada.lovelace@musteri.example'),
          );
      await eeShoot(
        tester,
        brightness: brightness,
        name: 'ee-ticket-requester',
        size: const Size(900, 1300),
        overrides: [
          ..._overrides(corpus, ticket: ticket),
          eeTicketActionsProvider(_ticketId).overrideWith(
            (ref) async => const EeTicketActions(
              status: 'in_progress',
              priority: 'urgent',
            ),
          ),
        ],
        screen: const EeTicketDetailScreen(ticketId: _ticketId),
      );
    });

    // EE-278: what the request was filed with — the service form's answers,
    // under the request, as the server returns them. Only asked for a request
    // whose service has a form, which the catalogue override says.
    testWidgets('and what it was filed with — ${brightness.name}', (
      tester,
    ) async {
      const serviceId = '01SVSHOTAAAAAAAAAAAAAAAAAA';
      final ticket = corpus
          .ticket(_ticketId)
          .copyWith(serviceId: const Value(serviceId));
      await eeShoot(
        tester,
        brightness: brightness,
        name: 'ee-ticket-answers',
        size: const Size(900, 1300),
        overrides: [
          ..._overrides(corpus, ticket: ticket),
          eeServicesProvider.overrideWith(
            () => _Catalogue(const [
              EeService(
                id: serviceId,
                name: 'Yatırım ve demirbaş alımı',
                formFields: [
                  EeServiceField(
                    key: 'tutar',
                    label: 'Tahmini tutar (TL)',
                    type: 'number',
                  ),
                ],
              ),
            ]),
          ),
          eeTicketActionsProvider(_ticketId).overrideWith(
            (ref) async => const EeTicketActions(
              status: 'in_progress',
              priority: 'urgent',
              answers: [
                EeTicketAnswer(
                  label: 'Tahmini tutar (TL)',
                  type: 'number',
                  value: '48500',
                ),
                EeTicketAnswer(
                  label: 'Gerekçe',
                  type: 'select',
                  value: 'Arıza',
                ),
                EeTicketAnswer(
                  label: 'İstenen teslim tarihi',
                  type: 'date',
                  value: '2026-09-29',
                ),
                EeTicketAnswer(
                  label: 'Bütçede var mı',
                  type: 'checkbox',
                  value: 'true',
                ),
              ],
            ),
          ),
        ],
        screen: const EeTicketDetailScreen(ticketId: _ticketId),
      );
    });

    // EE-223: the answer, being written — as an internal note, because that
    // is the one whose three signals have to be visible BEFORE the send.
    testWidgets('and the answer being written — ${brightness.name}', (
      tester,
    ) async {
      final turkish = AwI18n.instance.locale.languageCode == 'tr';
      await eeShoot(
        tester,
        brightness: brightness,
        name: 'ee-ticket-reply',
        size: const Size(900, 1300),
        overrides: [
          ..._overrides(corpus, canComment: true),
          eeTicketWriteApiProvider.overrideWithValue(EeTicketWriteApi(Dio())),
          syncEngineProvider.overrideWithValue(null),
        ],
        screen: const EeTicketDetailScreen(ticketId: _ticketId),
        afterPump: (t) async {
          final composer = find.byKey(const Key('ticket-composer'));
          await t.scrollUntilVisible(
            composer,
            400,
            scrollable: find.byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            ),
          );
          await t.tap(find.text('ee.tickets.composer.internal'.tr()));
          await t.pumpAndSettle();
          await t.enterText(
            find.byKey(const Key('ticket-composer-text')),
            turkish
                ? 'Parça yarın geliyor; müşteriye saat vermeyelim.'
                : "The part arrives tomorrow — let's not promise a time yet.",
          );
        },
      );
    });

    // EE-224: the three doors, opened. What is listed is the server's answer.
    // T5 has nobody on it yet — a breached, urgent request nobody has picked
    // up — so the third shot is the moment somebody takes it.
    for (final (door, name) in [
      ('ticket-status', 'ee-ticket-status'),
      ('ticket-priority', 'ee-ticket-priority'),
      ('ticket-assignees-open', 'ee-ticket-assign'),
    ]) {
      testWidgets('and its $door sheet — ${brightness.name}', (tester) async {
        await eeShoot(
          tester,
          brightness: brightness,
          name: name,
          size: const Size(900, 1300),
          overrides: [
            ..._overrides(corpus),
            eeFeatureProvider('teams').overrideWithValue(true),
            eeTicketWriteApiProvider.overrideWithValue(_ShotActionsApi()),
            syncEngineProvider.overrideWithValue(null),
            // The agent looking at it (the roster comes with the base set).
            currentUserIdProvider.overrideWithValue('P02'),
          ],
          screen: const EeTicketDetailScreen(ticketId: _ticketId),
          afterPump: (t) => t.tap(find.byKey(Key(door))),
        );
      });
    }

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

/// EE-278's shot: a catalogue that says which service has a form.
class _Catalogue extends EeServicesController {
  _Catalogue(this.services);

  final List<EeService> services;

  @override
  Future<List<EeService>?> build() async => services;
}
