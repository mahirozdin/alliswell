import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/api_exception.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/ee/assignments_providers.dart';
import 'package:alliswell/src/features/ee/changes_providers.dart';
import 'package:alliswell/src/features/ee/data/changes_models.dart';
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
    Future<EeTicketRelations> Function()? loadRelations,
    Future<List<EeChange>> Function()? loadChanges,
    bool canCreateChange = false,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        retry: awRetry,
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
          ).overrideWith((ref) => loadRelations?.call() ?? relations),
          eeKbSuggestionsProvider(
            'Hat 3 her vardiya iki kez duruyor',
          ).overrideWith((ref) async => const []),
          eeKbOfTicketProvider(_ticketId).overrideWith((ref) async => const []),
          eeChangesRaisedFromProvider(
            _ticketId,
          ).overrideWith((ref) => loadChanges?.call() ?? const <EeChange>[]),
          canProvider('changes.create').overrideWith((ref) => canCreateChange),
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

  const limited = ApiException(
    'RATE_LIMITED',
    'Rate limit exceeded, retry in 30 seconds',
    statusCode: 429,
    retryAfter: 30,
  );

  testWidgets('UI-AUDIT #26: a refused relations read is said inline, and '
      'Retry brings the equipment and the known-error card back', (
    tester,
  ) async {
    var calls = 0;
    await pump(
      tester,
      relations: const EeTicketRelations(),
      canManage: false,
      canLink: false,
      loadRelations: () async {
        calls += 1;
        if (calls == 1) throw limited;
        return const EeTicketRelations(
          problems: [
            EeLinkedProblem(
              id: _problemId,
              title: 'Hat 3 PLC her vardiya kilitleniyor',
              status: 'known_error',
              hasUsableWorkaround: true,
              workaround: 'PLC panelinden yazılımı yeniden başlatın',
            ),
          ],
          assets: [
            EeTicketAsset(
              assetId: '01ASSETAAAAAAAAAAAAAAAAAAA',
              tag: 'PLC-03',
              name: 'Hat 3 PLC',
              status: 'faulty',
            ),
          ],
        );
      },
    );

    final error = find.byKey(const Key('ticket-relations-error'));
    expect(error, findsOneWidget);
    expect(
      find.descendant(
        of: error,
        matching: find.text('error.RATE_LIMITED'.tr(args: {'seconds': '30'})),
      ),
      findsOneWidget,
    );
    // Not drawn as "nothing linked": the empty line stays away too.
    expect(find.text('ee.tickets.linkedTasksEmpty'.tr()), findsNothing);
    expect(find.byKey(const Key('ticket-problem-$_problemId')), findsNothing);

    await tester.ensureVisible(
      find.descendant(of: error, matching: find.byType(TextButton)),
    );
    await tester.tap(
      find.descendant(of: error, matching: find.byType(TextButton)),
    );
    for (var i = 0; i < 3; i += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(calls, 2);
    expect(error, findsNothing);
    expect(find.byKey(const Key('ticket-problem-$_problemId')), findsOneWidget);
    expect(find.text('ee.tickets.affectedAssets'.tr()), findsOneWidget);
    expect(find.textContaining('PLC-03'), findsOneWidget);
  });

  testWidgets('UI-AUDIT #26: a refused read of the changes raised from it is '
      'said inline, not drawn as none', (tester) async {
    var calls = 0;
    await pump(
      tester,
      relations: const EeTicketRelations(),
      canManage: false,
      canLink: false,
      loadChanges: () async {
        calls += 1;
        throw limited;
      },
    );
    final error = find.byKey(const Key('ticket-changes-error'));
    expect(error, findsOneWidget);
    expect(find.byKey(const Key('ticket-changes')), findsNothing);
    await tester.ensureVisible(
      find.descendant(of: error, matching: find.byType(TextButton)),
    );
    await tester.tap(
      find.descendant(of: error, matching: find.byType(TextButton)),
    );
    for (var i = 0; i < 3; i += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(calls, 2);
  });
}
