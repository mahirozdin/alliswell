import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/assignments_providers.dart';
import 'package:alliswell/src/features/ee/changes_providers.dart';
import 'package:alliswell/src/features/ee/data/changes_models.dart';
import 'package:alliswell/src/features/ee/data/services_models.dart';
import 'package:alliswell/src/features/ee/data/ticket_links_models.dart';
import 'package:alliswell/src/features/ee/kb_providers.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/services_providers.dart';
import 'package:alliswell/src/features/ee/ticket_links_providers.dart';
import 'package:alliswell/src/features/ee/ticket_write_providers.dart';
import 'package:alliswell/src/features/ee/tickets_providers.dart';
import 'package:alliswell/src/features/ee/ui/ticket_detail_screen.dart';
import 'package:alliswell/src/features/ee/worklog_providers.dart';
import 'package:alliswell/src/features/files/providers.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/providers.dart';
import 'package:alliswell/src/theme/theme.dart';

/// EE-279 — what planned work came of a request, and the door to raise some.
///
/// The request's detail lists the changes raised from it (read from the
/// server: the device's copy of a change does not carry its request) and,
/// for somebody who holds `changes.create`, offers to raise one — a form that
/// knows which request it comes from.
const _ticketId = '01TKCCCCCCCCCCCCCCCCCCCCCC';
const _changeId = '01CHFROMTICKETAAAAAAAAAAAA';

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
    required List<EeChange> raised,
    required bool canCreate,
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
          ).overrideWith((ref) async => const EeTicketRelations()),
          eeKbSuggestionsProvider(
            'Hat 3 her vardiya iki kez duruyor',
          ).overrideWith((ref) async => const []),
          eeKbOfTicketProvider(_ticketId).overrideWith((ref) async => const []),
          eeChangesRaisedFromProvider(
            _ticketId,
          ).overrideWith((ref) async => raised),
          canProvider('changes.create').overrideWith((ref) => canCreate),
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

  testWidgets('EE-279: a request lists the changes raised from it, and '
      'raising another opens a form that knows where it comes from', (
    tester,
  ) async {
    await pump(
      tester,
      raised: [
        EeChange(
          id: _changeId,
          workspaceId: 'W1',
          title: 'Hat 3 PLC yazılımı güncellemesi',
          type: 'normal',
          status: 'awaiting_approval',
          risk: 'medium',
          impact: 'Hat 3 bir vardiya durur',
          sourceTicketId: _ticketId,
          fromServer: true,
        ),
      ],
      canCreate: true,
    );

    expect(find.byKey(const Key('ticket-changes')), findsOneWidget);
    expect(find.text('Bu talepten açılan değişiklikler'), findsOneWidget);
    expect(find.byKey(const Key('change-$_changeId')), findsOneWidget);
    expect(find.text('Hat 3 PLC yazılımı güncellemesi'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('ticket-raise-change')));
    await tester.tap(find.byKey(const Key('ticket-raise-change')));
    for (var i = 0; i < 5; i += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // The form, prefilled from the request and saying so.
    expect(
      find.descendant(
        of: find.byKey(const Key('change-new-source')),
        matching: find.textContaining('#1042'),
      ),
      findsOneWidget,
    );
    final title = tester.widget<TextField>(
      find.byKey(const Key('change-new-title')),
    );
    expect(title.controller!.text, 'Hat 3 her vardiya iki kez duruyor');
  });

  testWidgets('nothing raised and no right to raise: the section is not '
      'drawn at all', (tester) async {
    await pump(tester, raised: const [], canCreate: false);

    expect(find.byKey(const Key('ticket-changes')), findsNothing);
    expect(find.byKey(const Key('ticket-raise-change')), findsNothing);
  });
}
