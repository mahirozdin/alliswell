import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/assignments_providers.dart';
import 'package:alliswell/src/features/ee/changes_providers.dart';
import 'package:alliswell/src/features/ee/data/services_models.dart';
import 'package:alliswell/src/features/ee/data/ticket_links_models.dart';
import 'package:alliswell/src/features/ee/kb_providers.dart';
import 'package:alliswell/src/features/ee/problems_providers.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/services_providers.dart';
import 'package:alliswell/src/features/ee/ticket_links_providers.dart';
import 'package:alliswell/src/features/ee/ticket_write_providers.dart';
import 'package:alliswell/src/features/ee/tickets_providers.dart';
import 'package:alliswell/src/features/ee/ui/problem_detail_screen.dart';
import 'package:alliswell/src/features/ee/ui/ticket_detail_screen.dart';
import 'package:alliswell/src/features/ee/worklog_providers.dart';
import 'package:alliswell/src/features/files/providers.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/providers.dart';
import 'package:alliswell/src/theme/theme.dart';

/// EE-270 + EE-280 — a request and its problem, from the request's side.
///
/// The linked-problem card used to be an end: it showed the workaround and
/// went nowhere. It opens the record now. And "let's open the known-error
/// record" starts here — for somebody who holds both verbs the act takes
/// (`problems.manage` to keep the record, `tickets.link` to link the request).
const _ticketId = '01TKCCCCCCCCCCCCCCCCCCCCCC';
const _problemId = '01PRFROMTICKETAAAAAAAAAAAA';

TicketRecord _ticket() => TicketRecord(
  id: _ticketId,
  workspaceId: 'W1',
  subject: 'Hat 3 her vardiya iki kez duruyor',
  number: 1042,
  status: 'in_progress',
  priority: 'high',
  source: 'internal',
  revision: 1,
  createdAt: DateTime.utc(2026, 9, 25),
);

class _Catalogue extends EeServicesController {
  @override
  Future<List<EeService>?> build() async => const [];
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('tr'));
  });

  Future<void> pump(
    WidgetTester tester, {
    required EeTicketRelations relations,
    required bool canManage,
    required bool canLink,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          ticketProvider(
            _ticketId,
          ).overrideWith((ref) => Stream.value(_ticket())),
          ticketCommentsProvider(
            _ticketId,
          ).overrideWith((ref) => Stream.value(const [])),
          eeServicesProvider.overrideWith(_Catalogue.new),
          eeTicketActionsProvider(_ticketId).overrideWith((ref) async => null),
          targetFilesProvider((
            targetType: 'ticket',
            targetId: _ticketId,
          )).overrideWith((ref) => Stream.value(const [])),
          eeTicketExternalFilesProvider(
            _ticketId,
          ).overrideWith((ref) async => EeExternalFiles.none),
          eeTicketRelationsProvider(
            _ticketId,
          ).overrideWith((ref) async => relations),
          eeKbSuggestionsProvider(
            'Hat 3 her vardiya iki kez duruyor',
          ).overrideWith((ref) async => const []),
          eeKbOfTicketProvider(_ticketId).overrideWith((ref) async => const []),
          eeChangesRaisedFromProvider(
            _ticketId,
          ).overrideWith((ref) async => const []),
          canProvider('changes.create').overrideWith((ref) => false),
          canProvider('problems.manage').overrideWith((ref) => canManage),
          canProvider('tickets.link').overrideWith((ref) => canLink),
          // The record the card opens: quiet, so the test is about the card.
          eeProblemOnDeviceProvider(
            _problemId,
          ).overrideWith((ref) => Stream.value(null)),
          eeProblemLiveProvider(_problemId).overrideWith((ref) async => null),
          canProvider('kb.write').overrideWith((ref) => false),
          canProvider('tickets.convert').overrideWith((ref) => false),
          canProvider('tickets.create').overrideWith((ref) => false),
          canProvider('tickets.comment').overrideWith((ref) => false),
          eeWorklogProvider(_ticketId).overrideWith((ref) async => null),
          ticketAssigneesForProvider(
            _ticketId,
          ).overrideWith((ref) => Stream.value(const [])),
          workspaceRosterOfProvider.overrideWith(
            (ref, workspaceId) => Stream.value(const []),
          ),
          syncEngineProvider.overrideWithValue(null),
        ],
        child: MaterialApp(
          theme: buildAwTheme(Brightness.light),
          home: const EeTicketDetailScreen(ticketId: _ticketId),
        ),
      ),
    );
    tester.view.physicalSize = const Size(1170, 3600);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    // Fixed pumps: the history tab never settles in a test with no server.
    for (var i = 0; i < 3; i += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  const linked = EeTicketRelations(
    problems: [
      EeLinkedProblem(
        id: _problemId,
        title: 'Hat 3 PLC her vardiya kilitleniyor',
        status: 'known_error',
        hasUsableWorkaround: true,
        workaround: 'PLC panelinden yazılımı yeniden başlatın',
      ),
    ],
  );

  testWidgets('EE-270: the linked-problem card opens the record', (
    tester,
  ) async {
    await pump(tester, relations: linked, canManage: false, canLink: false);

    expect(
      find.text('PLC panelinden yazılımı yeniden başlatın'),
      findsOneWidget,
    );
    await tester.ensureVisible(
      find.byKey(const Key('ticket-problem-$_problemId')),
    );
    await tester.tap(find.byKey(const Key('ticket-problem-$_problemId')));
    for (var i = 0; i < 5; i += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(EeProblemDetailScreen), findsOneWidget);
  });

  testWidgets('EE-280: the record keeper without the right to link is not '
      'offered the known-error record', (tester) async {
    await pump(
      tester,
      relations: const EeTicketRelations(),
      canManage: true,
      canLink: false,
    );
    expect(find.byKey(const Key('ticket-raise-known-error')), findsNothing);
  });

  testWidgets('EE-280: with both verbs the known-error record is offered, and '
      'opens knowing its request', (tester) async {
    await pump(
      tester,
      relations: const EeTicketRelations(),
      canManage: true,
      canLink: true,
    );
    await tester.ensureVisible(
      find.byKey(const Key('ticket-raise-known-error')),
    );
    await tester.tap(find.byKey(const Key('ticket-raise-known-error')));
    for (var i = 0; i < 5; i += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      find.descendant(
        of: find.byKey(const Key('problem-new-source')),
        matching: find.textContaining('#1042'),
      ),
      findsOneWidget,
    );
    final title = tester.widget<TextField>(
      find.byKey(const Key('problem-new-title')),
    );
    expect(title.controller!.text, 'Hat 3 her vardiya iki kez duruyor');
  });
}
