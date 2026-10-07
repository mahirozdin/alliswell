import 'dart:async';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:alliswell/src/features/ee/notifications_providers.dart';
import 'package:alliswell/src/features/ee/requester_ticket_providers.dart';
import 'package:alliswell/src/features/ee/tickets_providers.dart';
import 'package:alliswell/src/features/ee/ui/new_ticket_screen.dart';
import 'package:alliswell/src/features/ee/ui/notification_center_screen.dart';
import 'package:alliswell/src/features/ee/ui/ticket_detail_screen.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/router.dart';
import 'package:alliswell/src/screens/home_shell.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/providers.dart';
import 'package:alliswell/src/theme/theme.dart';

import '../shell/shell_harness.dart';

/// EE-251 — a request has an address. Before it the detail screen was only
/// ever pushed from the queue, so a notification that named a ticket went
/// nowhere and a pasted link fell to "not found".
void main() {
  const id = '01JABCDEFGHJKMNPQRSTVWXYZ0';

  group('eeTicketRoutes — the list the router uses', () {
    RouteMatchList match(String location) => GoRouter(
      routes: eeTicketRoutes(),
    ).configuration.findMatch(Uri.parse(location));

    test('an id opens the detail, with the id as its parameter', () {
      final m = match('/tickets/$id');
      expect(m.last.route.path, '/tickets/:ticketId');
      expect(m.pathParameters['ticketId'], id);
    });

    test('"new" is the filing form, not an id — the order is the contract', () {
      // go_router matches in declaration order; with the detail first, this
      // would open a request whose id is "new".
      final m = match('/tickets/new');
      expect(m.last.route.path, '/tickets/new');
    });
  });

  group('AW-E02: a ticket notification opens the ticket', () {
    late AwDatabase db;

    setUp(() {
      db = AwDatabase(DatabaseConnection(NativeDatabase.memory()));
      AwI18n.instance.setActiveCached(const Locale('en'));
    });
    tearDown(() => db.close());

    NotificationItem assigned() => NotificationItem(
      id: 'N1',
      eventClass: 'ticket.assigned',
      titleKey: 'ee.notif.ticket.assigned.title',
      bodyKey: 'ee.notif.ticket.assigned.body',
      params: const {'ticketRef': '#1042', 'subject': 'Hat 3 durdu'},
      entityType: 'ee_ticket',
      entityId: id,
      readAt: null,
      createdAt: DateTime.utc(2026, 9, 24, 10),
    );

    testWidgets('tapping "assigned to you" lands on that request by its '
        'address', (tester) async {
      final router = GoRouter(
        initialLocation: '/notifications',
        routes: [
          GoRoute(
            path: '/notifications',
            builder: (context, state) => const EeNotificationCenterScreen(),
          ),
          ...eeTicketRoutes(),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            notificationCenterProvider.overrideWith(
              (ref) => Stream.value([assigned()]),
            ),
            unreadNotificationCountProvider.overrideWith(
              (ref) => Stream.value(1),
            ),
            // The detail's replica-miss path: this test is about getting
            // there, not about what a present row draws.
            ticketProvider.overrideWith((ref, ticketId) => Stream.value(null)),
            // …which opens the requester's view at the same address (EE-252);
            // a request that is not theirs either is the gone state.
            eeRequesterTicketProvider.overrideWith(
              (ref, ticketId) async => null,
            ),
          ],
          // The product's theme: the routes wrap their page in the app
          // background, which reads AllisWell Glass's tokens.
          child: MaterialApp.router(
            theme: buildAwTheme(Brightness.light),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('notif-N1')));
      await tester.pumpAndSettle();

      final detail = tester.widget<EeTicketDetailScreen>(
        find.byType(EeTicketDetailScreen),
      );
      expect(detail.ticketId, id);
      // Built by the route, at the address — not a widget pushed around it.
      final state = GoRouterState.of(
        tester.element(find.byType(EeTicketDetailScreen)),
      );
      expect(state.uri.toString(), '/tickets/$id');
      // Back returns to the centre — it was a push, not a replacement.
      expect(router.canPop(), isTrue);
      expect(find.byType(EeNewTicketScreen), findsNothing);
    });
  });

  // OPH-359 — UI-AUDIT #30, #32 and #59.
  group('UI-AUDIT #30: a request opened by its address has a way out', () {
    late AwDatabase db;

    setUp(() {
      db = AwDatabase(DatabaseConnection(NativeDatabase.memory()));
      AwI18n.instance.setActiveCached(const Locale('en'));
    });
    tearDown(() => db.close());

    testWidgets('nothing under it → a Home button, and it goes Home', (
      tester,
    ) async {
      final router = GoRouter(
        initialLocation: '/tickets/$id',
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, state) => const Scaffold(body: Text('HOME')),
          ),
          ...eeTicketRoutes(),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            ticketProvider.overrideWith((ref, ticketId) => Stream.value(null)),
            eeRequesterTicketProvider.overrideWith(
              (ref, ticketId) async => null,
            ),
          ],
          child: MaterialApp.router(
            theme: buildAwTheme(Brightness.light),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(router.canPop(), isFalse);
      final home = find.byKey(const Key('aw-route-home'));
      expect(home, findsOneWidget);
      await tester.tap(home);
      await tester.pumpAndSettle();
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets('something under it → the ordinary back button, no Home', (
      tester,
    ) async {
      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, state) => const Scaffold(body: Text('HOME')),
          ),
          ...eeTicketRoutes(),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            ticketProvider.overrideWith((ref, ticketId) => Stream.value(null)),
            eeRequesterTicketProvider.overrideWith(
              (ref, ticketId) async => null,
            ),
          ],
          child: MaterialApp.router(
            theme: buildAwTheme(Brightness.light),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      router.push('/tickets/$id');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('aw-route-home')), findsNothing);
      expect(find.byType(BackButton), findsOneWidget);
    });
  });

  group('UI-AUDIT #32 / #59: the whole app', () {
    setUp(() => AwI18n.instance.setActiveCached(const Locale('en')));

    testWidgets('#32: a request link opened cold keeps the replica syncing — '
        'the shell never mounted, the engines run anyway', (tester) async {
      sizeTo(tester, const Size(1280, 900));
      final api = teamApi();
      await tester.pumpWidget(
        await teamApp(
          api,
          more: [
            pendingDeepLinkProvider.overrideWith(() => _Parked('/tickets/$id')),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(appRouter().state.uri.path, '/tickets/$id');
      expect(find.byType(HomeShell), findsNothing);
      expect(
        api.requests.where((r) => r.contains('/sync/pull')),
        isNotEmpty,
        reason: 'nothing pulled: the detail would wait forever for its row',
      );
    });

    testWidgets('#59: a pushed screen carries its own address in the URL', (
      tester,
    ) async {
      sizeTo(tester, const Size(1280, 900));
      await tester.pumpWidget(await teamApp(teamApi()));
      await tester.pumpAndSettle();
      final router = appRouter();
      unawaited(router.push('/settings'));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/settings');
      unawaited(router.push('/kb'));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/kb');
    });

    test('#59: the desk\'s boards have addresses', () {
      final config = GoRouter(routes: eeDeskBoardRoutes()).configuration;
      for (final path in const ['/sla', '/performance', '/my-units']) {
        expect(config.findMatch(Uri.parse(path)).last.route.path, path);
      }
    });
  });
}

class _Parked extends PendingDeepLink {
  _Parked(this._location);
  final String _location;
  @override
  String? build() => _location;
}
