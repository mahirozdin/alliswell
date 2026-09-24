import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/reachability.dart';
import 'package:alliswell/src/features/ee/data/my_tickets_api.dart';
import 'package:alliswell/src/features/ee/data/requester_ticket_api.dart';
import 'package:alliswell/src/features/ee/data/ticket_write_api.dart';
import 'package:alliswell/src/features/ee/my_tickets_providers.dart';
import 'package:alliswell/src/features/ee/new_ticket_providers.dart';
import 'package:alliswell/src/features/ee/requester_ticket_providers.dart';
import 'package:alliswell/src/features/ee/ticket_write_providers.dart';
import 'package:alliswell/src/features/ee/ticket_drafts_providers.dart';
import 'package:alliswell/src/features/ee/tickets_providers.dart';
import 'package:alliswell/src/features/ee/ui/my_tickets_screen.dart';
import 'package:alliswell/src/features/ee/ui/requester_ticket_screen.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/workspaces/workspaces.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/router.dart';
import 'package:alliswell/src/theme/theme.dart';

/// EE-252 — the person who ASKED runs their request from the app: reads it,
/// answers the desk, and ends or disputes it once the desk calls it resolved.
/// Everything the screen offers is what the doors accept
/// (`requester-rules.js`); the server tests hold the doors, these hold that
/// the screen never offers more.
const _id = '01TKAAAAAAAAAAAAAAAAAAAAAA';
const _me = 'U-ME';

class _FakeWriteApi extends Fake implements EeTicketWriteApi {
  final comments = <({String body, bool internal})>[];
  final moves = <String>[];

  @override
  Future<void> comment(
    String ticketId, {
    required String body,
    required bool internal,
  }) async => comments.add((body: body, internal: internal));

  @override
  Future<void> setStatus(
    String ticketId,
    String status, {
    String? waitingReason,
  }) async => moves.add(status);
}

EeRequesterTicket _ticket({
  String status = 'waiting',
  String? waitingReason = 'requester_info',
  List<String> moves = const [],
  String viewer = 'requester',
}) => EeRequesterTicket(
  id: _id,
  subject: 'Hat 3 durdu',
  status: status,
  viewer: viewer,
  number: 1042,
  body: 'Hat 3 sabahtan beri çalışmıyor.',
  waitingReason: waitingReason,
  serviceName: 'Üretim hattı arızası',
  updatedAt: DateTime.utc(2026, 9, 24, 9, 30),
  allowedTransitions: moves,
);

void main() {
  late _FakeWriteApi api;
  late ProviderContainer container;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('tr'));
    api = _FakeWriteApi();
  });

  List<Override> overrides(EeRequesterTicket? ticket) => [
    eeTicketWriteApiProvider.overrideWithValue(api),
    currentUserIdProvider.overrideWithValue(_me),
    eeRequesterTicketProvider.overrideWith((ref, id) async => ticket),
    eeRequesterCommentsProvider.overrideWith(
      (ref, id) async => const [
        EeRequesterComment(id: 'C1', body: 'Hangi hat?', authorId: 'U-AGENT'),
        EeRequesterComment(id: 'C2', body: 'Üçüncü hat.', authorId: _me),
      ],
    ),
  ];

  Future<void> pump(WidgetTester tester, EeRequesterTicket? ticket) async {
    container = ProviderContainer(overrides: overrides(ticket));
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAwTheme(Brightness.light),
          home: const EeRequesterTicketScreen(ticketId: _id),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  bool enabled(WidgetTester tester, Key key) =>
      tester.widget<ButtonStyleButton>(find.byKey(key)).onPressed != null;

  testWidgets(
    'AW-E03: "Sizden bilgi bekleniyor" — the requester writes the answer and it '
    'goes as a visible reply',
    (tester) async {
      await pump(tester, _ticket());
      expect(
        find.byKey(const Key('ee-requester-waiting-on-you')),
        findsOneWidget,
      );
      expect(find.text('Hat 3 durdu'), findsOneWidget);
      expect(find.textContaining('#1042'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('ee-requester-reply')),
        'Hat 3, B vardiyası',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('ee-requester-send')));
      await tester.pumpAndSettle();

      expect(api.comments, [(body: 'Hat 3, B vardiyası', internal: false)]);
    },
  );

  testWidgets('no internal note is offered — the box is a reply and nothing '
      'else', (tester) async {
    await pump(tester, _ticket());
    expect(find.text('İç not'), findsNothing);
    expect(find.byType(SegmentedButton<bool>), findsNothing);
  });

  testWidgets('the lines say who wrote them: you, or the desk', (tester) async {
    await pump(tester, _ticket());
    expect(find.textContaining('Siz'), findsWidgets);
    expect(find.textContaining('Destek ekibi'), findsOneWidget);
    expect(find.text('Talebiniz'), findsOneWidget);
  });

  testWidgets('a resolved request offers exactly its two moves; closing asks '
      'first', (tester) async {
    await pump(
      tester,
      _ticket(
        status: 'resolved',
        waitingReason: null,
        moves: const ['closed', 'in_progress'],
      ),
    );
    await tester.tap(find.byKey(const Key('ee-requester-close')));
    await tester.pumpAndSettle();
    expect(api.moves, isEmpty, reason: 'an ending asks before it is sent');
    await tester.tap(find.byKey(const Key('ee-requester-close-confirm')));
    await tester.pumpAndSettle();
    expect(api.moves, ['closed']);
  });

  testWidgets('"Çözülmedi" sends it back to the desk', (tester) async {
    await pump(
      tester,
      _ticket(
        status: 'resolved',
        waitingReason: null,
        moves: const ['closed', 'in_progress'],
      ),
    );
    await tester.tap(find.byKey(const Key('ee-requester-dispute')));
    await tester.pumpAndSettle();
    expect(api.moves, ['in_progress']);
  });

  testWidgets('an open request offers no move — none is the requester\'s', (
    tester,
  ) async {
    await pump(tester, _ticket(status: 'in_progress', waitingReason: null));
    expect(find.byKey(const Key('ee-requester-outcome')), findsNothing);
    expect(find.byKey(const Key('ee-requester-reply')), findsOneWidget);
  });

  testWidgets('a closed request offers a new request instead of a box', (
    tester,
  ) async {
    await pump(tester, _ticket(status: 'closed', waitingReason: null));
    expect(find.byKey(const Key('ee-requester-closed')), findsOneWidget);
    expect(find.byKey(const Key('ee-requester-reply')), findsNothing);
    expect(find.byKey(const Key('ee-requester-new')), findsOneWidget);
  });

  testWidgets('offline: the box and the moves are grey, and it says why', (
    tester,
  ) async {
    await pump(
      tester,
      _ticket(
        status: 'resolved',
        waitingReason: null,
        moves: const ['closed', 'in_progress'],
      ),
    );
    container.read(serverReachabilityProvider.notifier).unreachable();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ee-requester-offline')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('ee-requester-reply')))
          .enabled,
      isFalse,
    );
    expect(enabled(tester, const Key('ee-requester-close')), isFalse);
    expect(enabled(tester, const Key('ee-requester-dispute')), isFalse);
  });

  testWidgets('the desk\'s answer is not drawn as the requester\'s view', (
    tester,
  ) async {
    await pump(tester, _ticket(viewer: 'desk'));
    expect(find.byKey(const Key('ee-requester-ticket')), findsNothing);
    expect(find.text('ee.tickets.goneTitle'.tr()), findsOneWidget);
  });

  testWidgets('"Taleplerim": a row says what happened last and opens the '
      'request at its address', (tester) async {
    final router = GoRouter(
      initialLocation: '/mine',
      routes: [
        GoRoute(
          path: '/mine',
          builder: (context, state) => const EeMyTicketsScreen(),
        ),
        ...eeTicketRoutes(),
      ],
    );
    addTearDown(router.dispose);
    container = ProviderContainer(
      overrides: [
        ...overrides(_ticket()),
        eeFeatureProvider.overrideWith((ref, feature) => true),
        eeMyTicketsProvider.overrideWith(
          (ref) async => [
            EeMyTicket(
              id: _id,
              subject: 'Hat 3 durdu',
              status: 'waiting',
              priority: 'high',
              serviceName: 'Üretim hattı arızası',
              createdAt: DateTime.utc(2026, 9, 24, 8),
              updatedAt: DateTime.utc(2026, 9, 24, 9, 30),
            ),
          ],
        ),
        // The requester holds no copy of the unit's request (ADR-0011 §3).
        ticketProvider.overrideWith((ref, id) => Stream.value(null)),
        // The list's neighbours, quiet: no drafts, no catalogue, no "new".
        draftStatusesProvider.overrideWith((ref) => const []),
        eeCatalogProvider.overrideWith((ref) async => null),
        canProvider.overrideWith((ref, permission) => false),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: buildAwTheme(Brightness.light),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Son güncelleme'), findsOneWidget);
    await tester.tap(find.byKey(const Key('my-ticket-$_id')));
    await tester.pumpAndSettle();
    expect(find.byType(EeRequesterTicketScreen), findsOneWidget);
    expect(
      find.byKey(const Key('ee-requester-waiting-on-you')),
      findsOneWidget,
    );
  });
}
