import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/assignments_providers.dart';
import 'package:alliswell/src/features/ee/changes_providers.dart';
import 'package:alliswell/src/features/ee/data/ticket_links_models.dart';
import 'package:alliswell/src/features/ee/data/ticket_write_api.dart';
import 'package:alliswell/src/features/ee/kb_providers.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/ticket_links_providers.dart';
import 'package:alliswell/src/features/ee/ticket_write_providers.dart';
import 'package:alliswell/src/features/ee/tickets_providers.dart';
import 'package:alliswell/src/features/ee/ui/ticket_detail_screen.dart';
import 'package:alliswell/src/features/ee/worklog_providers.dart';
import 'package:alliswell/src/features/files/providers.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/theme/theme.dart';

/// EE-254 (ADR-0017 D17.2) — the desk sees that a sender could not be
/// checked. The mail door files a mail that claimed a colleague's address
/// and could not prove it as an OUTSIDE sender; this is the screen saying so,
/// on the request and on exactly the replies that did it.
///
/// The fact is the server's (the replica has no column for it), read with the
/// request's actions — so a server that says nothing draws nothing.
const _ticketId = '01TKAAAAAAAAAAAAAAAAAAAAAA';

TicketRecord _ticket() => TicketRecord(
  id: _ticketId,
  workspaceId: 'W1',
  subject: 'Pres 2 yağ kaçırıyor',
  status: 'new',
  priority: 'normal',
  source: 'email',
  revision: 1,
  createdAt: DateTime.utc(2026, 9, 24),
);

TicketCommentRecord _comment(String id, String body) => TicketCommentRecord(
  id: id,
  workspaceId: 'W1',
  ticketId: _ticketId,
  body: body,
  internal: false,
  revision: 1,
  createdAt: DateTime.utc(2026, 9, 24, 9),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('tr'));
  });

  Future<void> pump(WidgetTester tester, EeTicketActions? actions) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          ticketProvider(
            _ticketId,
          ).overrideWith((ref) => Stream.value(_ticket())),
          ticketCommentsProvider(_ticketId).overrideWith(
            (ref) => Stream.value([
              _comment('C1', 'Ben Ayla, hat 3 duruyor.'),
              _comment('C2', 'Masanın yanıtı.'),
            ]),
          ),
          eeTicketActionsProvider(
            _ticketId,
          ).overrideWith((ref) async => actions),
          // Everything else the screen watches, quiet (see the attachments
          // test for why each one is here).
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
          // EE-279's section, quiet: this test is about something else.
          eeChangesRaisedFromProvider(
            _ticketId,
          ).overrideWith((ref) async => const []),
          canProvider('changes.create').overrideWith((ref) => false),
          eeKbSuggestionsProvider(
            'Pres 2 yağ kaçırıyor',
          ).overrideWith((ref) async => const []),
          eeKbOfTicketProvider(_ticketId).overrideWith((ref) async => const []),
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
        ],
        child: MaterialApp(
          theme: buildAwTheme(Brightness.light),
          home: const EeTicketDetailScreen(ticketId: _ticketId),
        ),
      ),
    );
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    // Fixed pumps, the attachments test's reason: this screen's history tab
    // never settles in a test with no server.
    for (var i = 0; i < 3; i += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('AW-E04: the request and ONLY the reply that could not be '
      'checked say so', (tester) async {
    await pump(
      tester,
      const EeTicketActions(
        status: 'new',
        priority: 'normal',
        senderUnverified: true,
        unverifiedCommentIds: {'C1'},
      ),
    );
    expect(find.byKey(const Key('ticket-sender-unverified')), findsOneWidget);
    expect(find.textContaining('Gönderen doğrulanmadı'), findsNWidgets(2));
    expect(
      find.byKey(const Key('ticket-comment-unverified-C1')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('ticket-comment-unverified-C2')), findsNothing);
  });

  testWidgets('a server that says nothing draws nothing', (tester) async {
    await pump(tester, null);
    expect(find.byKey(const Key('ticket-sender-unverified')), findsNothing);
    expect(find.textContaining('Gönderen doğrulanmadı'), findsNothing);
  });

  test('the actions carry the two facts the server sends', () {
    final parsed = EeTicketActions.fromJson(const {
      'status': 'new',
      'priority': 'normal',
      'senderUnverified': true,
      'unverifiedCommentIds': ['C1', 'C3'],
    });
    expect(parsed.senderUnverified, isTrue);
    expect(parsed.unverifiedCommentIds, {'C1', 'C3'});
    final silent = EeTicketActions.fromJson(const {
      'status': 'new',
      'priority': 'normal',
    });
    expect(silent.senderUnverified, isFalse);
    expect(silent.unverifiedCommentIds, isEmpty);
  });
}
