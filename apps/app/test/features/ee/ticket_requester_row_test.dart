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
import 'package:alliswell/src/features/ee/ui/ticket_queue_screen.dart';
import 'package:alliswell/src/features/workspaces/workspaces.dart';
import 'package:alliswell/src/features/ee/worklog_providers.dart';
import 'package:alliswell/src/features/files/providers.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/theme/theme.dart';

/// EE-258 (AW-E07) — the desk sees who asked, and where the answer goes.
///
/// From the replica (v33 keeps the name and the address of somebody with no
/// account; an account's name comes from the rosters the device syncs), so it
/// reads with no signal. The server fills in only for a request this device
/// pulled before it kept them — and only where somebody outside certainly
/// asked.
const _ticketId = '01TKBBBBBBBBBBBBBBBBBBBBBB';

TicketRecord _ticket({
  String source = 'email',
  String? requesterId,
  String? requesterName,
  String? requesterEmail,
}) => TicketRecord(
  id: _ticketId,
  workspaceId: 'W1',
  subject: 'Pres 2 yağ kaçırıyor',
  status: 'new',
  priority: 'normal',
  source: source,
  requesterId: requesterId,
  requesterName: requesterName,
  requesterEmail: requesterEmail,
  revision: 1,
  createdAt: DateTime.utc(2026, 9, 24),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('tr'));
  });

  late List<String> mailedTo;
  // How many times the detail asked the server for this request.
  late int asked;

  Future<void> pump(
    WidgetTester tester,
    TicketRecord ticket, {
    EeTicketActions? fromServer,
    Map<String, String> names = const {},
  }) async {
    mailedTo = [];
    asked = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          ticketProvider(_ticketId).overrideWith((ref) => Stream.value(ticket)),
          ticketCommentsProvider(
            _ticketId,
          ).overrideWith((ref) => Stream.value(const [])),
          eeTicketActionsProvider(_ticketId).overrideWith((ref) async {
            asked += 1;
            return fromServer;
          }),
          eeMemberNamesProvider.overrideWith((ref) => Stream.value(names)),
          eeMailLauncherProvider.overrideWithValue((address) async {
            mailedTo.add(address);
          }),
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
          canProvider('problems.manage').overrideWith((ref) => false),
          canProvider('tickets.link').overrideWith((ref) => false),
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

  String? textOf(WidgetTester tester, String key) {
    final found = find.byKey(Key(key));
    if (found.evaluate().isEmpty) return null;
    return tester.widget<Text>(found).data;
  }

  testWidgets('AW-E07: a customer who wrote in by mail — who, where the answer '
      'goes, and how it came — from the device', (tester) async {
    await pump(
      tester,
      _ticket(
        requesterName: 'Ada Lovelace',
        requesterEmail: 'ada@musteri.example',
      ),
    );
    expect(textOf(tester, 'ticket-requester-name'), 'Ada Lovelace');
    expect(find.text('ada@musteri.example'), findsOneWidget);
    expect(textOf(tester, 'ticket-requester-origin'), 'E-postayla geldi');

    // The address is the way back: a tap hands it to the mail app.
    await tester.ensureVisible(find.byKey(const Key('ticket-requester-email')));
    await tester.tap(find.byKey(const Key('ticket-requester-email')));
    await tester.pump();
    expect(mailedTo, ['ada@musteri.example']);
  });

  testWidgets('somebody with an account is named by it', (tester) async {
    await pump(
      tester,
      _ticket(source: 'internal', requesterId: 'U1'),
      names: const {'U1': 'Ceren Saha'},
    );
    expect(textOf(tester, 'ticket-requester-name'), 'Ceren Saha');
    expect(find.byKey(const Key('ticket-requester-email')), findsNothing);
    expect(find.byKey(const Key('ticket-requester-origin')), findsNothing);
  });

  testWidgets('…and by nothing made up when the device has not met them', (
    tester,
  ) async {
    await pump(tester, _ticket(source: 'internal', requesterId: 'U2'));
    expect(textOf(tester, 'ticket-requester-name'), 'Takım üyesi');
  });

  testWidgets('a mail pulled before the device kept them: the answer the '
      'detail already asks for fills in who asked', (tester) async {
    await pump(
      tester,
      _ticket(),
      fromServer: const EeTicketActions(
        status: 'new',
        priority: 'normal',
        requesterDisplayName: 'Ada Lovelace',
        requesterEmail: 'ada@musteri.example',
      ),
    );
    expect(textOf(tester, 'ticket-requester-name'), 'Ada Lovelace');
    expect(find.text('ada@musteri.example'), findsOneWidget);
    expect(textOf(tester, 'ticket-requester-origin'), 'E-postayla geldi');
  });

  testWidgets('…and nowhere else is a question added: an old portal row asks '
      'the server nothing', (tester) async {
    await pump(
      tester,
      _ticket(source: 'public'),
      fromServer: const EeTicketActions(
        status: 'new',
        priority: 'normal',
        requesterDisplayName: 'Ada Lovelace',
      ),
    );
    expect(asked, 0);
    expect(find.byKey(const Key('ticket-requester')), findsNothing);
  });

  testWidgets('filed by a colleague for somebody with no account — said so', (
    tester,
  ) async {
    await pump(
      tester,
      _ticket(source: 'internal', requesterName: 'Mehmet Usta'),
    );
    expect(textOf(tester, 'ticket-requester-name'), 'Mehmet Usta');
    expect(
      textOf(tester, 'ticket-requester-origin'),
      'Bir çalışma arkadaşı onun adına açtı',
    );
    expect(find.byKey(const Key('ticket-requester-email')), findsNothing);
  });

  testWidgets('a request a monitor opened was asked by nobody — no row', (
    tester,
  ) async {
    await pump(tester, _ticket(source: 'health'));
    expect(find.byKey(const Key('ticket-requester')), findsNothing);
  });

  testWidgets('the queue row says who asked — for either shape, and for nobody '
      'says nothing', (tester) async {
    TicketRecord row(String id, {String? requesterId, String? requesterName}) =>
        TicketRecord(
          id: id,
          workspaceId: 'W1',
          subject: 'Talep $id',
          status: 'new',
          priority: 'normal',
          source: 'internal',
          requesterId: requesterId,
          requesterName: requesterName,
          revision: 1,
          createdAt: DateTime.utc(2026, 9, 24),
        );
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          ticketQueueProvider.overrideWith(
            (ref) => Stream.value([
              row('R1', requesterName: 'Ada Lovelace'),
              row('R2', requesterId: 'U1'),
              row('R3'),
            ]),
          ),
          ticketAssigneesProvider.overrideWith(
            (ref) => Stream.value(const <String, List<Assignee>>{}),
          ),
          eeMemberNamesProvider.overrideWith(
            (ref) => Stream.value(const {'U1': 'Ceren Saha'}),
          ),
          currentUserIdProvider.overrideWithValue('01USAAAAAAAAAAAAAAAAAAAAAA'),
          canProvider.overrideWith((ref, permission) => false),
        ],
        child: MaterialApp(
          theme: buildAwTheme(Brightness.light),
          home: const EeTicketQueueScreen(),
        ),
      ),
    );
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpAndSettle();

    String line(String id) => tester
        .widgetList<Text>(
          find.descendant(
            of: find.byKey(Key('ticket-$id')),
            matching: find.byType(Text),
          ),
        )
        .map((t) => t.data ?? '')
        .join(' | ');
    expect(line('R1'), contains('Ada Lovelace'));
    expect(line('R2'), contains('Ceren Saha'));
    expect(line('R3'), isNot(contains(' · · ')));
    expect(line('R3'), contains('Yeni · Normal'));
  });
}
