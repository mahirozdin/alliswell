import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/ee/data/requester_ticket_api.dart';
import 'package:alliswell/src/features/ee/data/ticket_archive_api.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/requester_ticket_providers.dart';
import 'package:alliswell/src/features/ee/ticket_archive_providers.dart';
import 'package:alliswell/src/features/ee/tickets_providers.dart';
import 'package:alliswell/src/features/ee/ui/requester_ticket_screen.dart';
import 'package:alliswell/src/features/ee/ui/ticket_detail_screen.dart';
import 'package:alliswell/src/features/ee/ui/ticket_queue_screen.dart';
import 'package:alliswell/src/features/workspaces/workspaces.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/search/search.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/providers.dart';
import 'package:alliswell/src/theme/theme.dart';

/// EE-266 — AW-E17: the archive, readable.
///
/// The report's scenario, as written: a manager opens the link to #1042 from
/// three months ago and reads how it was solved; the same request is found by
/// searching. Before this, the link opened "this request is no longer on the
/// device" and the queue's empty search said "look in the archive on the
/// server" — an archive the app could not open.
///
/// The screens are pumped against the REAL clients over a fake HTTP layer, so
/// the server's JSON shape is what gets parsed — a fake at the provider level
/// would have agreed with whatever the model expected.
const _id = '01JARCH1VED1042AAAAAAAAAAA';
const _ws = '01WSAAAAAAAAAAAAAAAAAAAAAA';
const _otherWs = '01WSKKKKKKKKKKKKKKKKKKKKKK';

/// The server, as far as these screens reach it. Each case sets what the
/// live and archive doors answer; [asked] records every request.
class _Server implements HttpClientAdapter {
  ResponseBody Function(RequestOptions options)? live;
  ResponseBody Function(RequestOptions options)? archive;
  ResponseBody Function(RequestOptions options)? search;
  bool offline = false;
  final List<RequestOptions> asked = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    asked.add(options);
    if (offline) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );
    }
    final path = options.path;
    if (path == '/api/v1/ee/team/tickets/archive') return search!(options);
    if (path.startsWith('/api/v1/ee/team/tickets/archive/')) {
      return archive!(options);
    }
    return live!(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int status, Object data) => ResponseBody.fromString(
  jsonEncode(data),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

final _notFound = {
  'statusCode': 404,
  'error': 'Not Found',
  'message': 'Not found',
};

/// #1042 as the archive detail endpoint returns it (EE-257's schema, EE-265's
/// additions).
final _archived = {
  'id': _id,
  'workspaceId': _ws,
  'number': 1042,
  'serviceId': '01SVCAAAAAAAAAAAAAAAAAAAAA',
  'requesterId': null,
  'requesterName': 'Deniz Yılmaz',
  'requesterEmail': 'deniz@musteri.example',
  'requesterDisplayName': 'Deniz Yılmaz',
  'subject': 'Hat 3 pres yağ kaçırıyor',
  'status': 'closed',
  'priority': 'high',
  'source': 'email',
  'commentCount': 2,
  'createdAt': '2026-06-18T07:30:00.000Z',
  'terminalAt': '2026-06-20T10:00:00.000Z',
  'archivedAt': '2026-09-18T10:05:00.000Z',
  'body': 'Pres 2 altında yağ birikiyor.',
  'service': {'id': '01SVCAAAAAAAAAAAAAAAAAAAAA', 'name': 'Hat arızası'},
  'requester': null,
  'comments': [
    {
      'id': 'C1',
      'authorId': 'U1',
      'authorName': 'Barış Bakım',
      'body': 'Conta değiştirildi, sızıntı durdu.',
      'internal': false,
      'createdAt': '2026-06-19T09:00:00.000Z',
      'deletedAt': null,
    },
    {
      'id': 'C2',
      'authorId': 'U1',
      'authorName': 'Barış Bakım',
      'body': 'Conta stoğu bitti, sipariş verildi.',
      'internal': true,
      'createdAt': '2026-06-19T09:05:00.000Z',
      'deletedAt': null,
    },
  ],
  'assignees': [],
  'taskLinks': [],
  'slaStatus': 'met',
  'slaDueAt': null,
  'slaClocks': [],
  'approvals': [
    {
      'id': 'A1',
      'status': 'approved',
      'approverUserId': null,
      'approverName': null,
      'approverRoleKey': 'manager',
      'requestReason': 'Conta bütçesi',
      'decidedBy': 'U2',
      'decidedByName': 'Ayla Yönetici',
      'decidedAt': '2026-06-19T08:00:00.000Z',
      'decisionReason': null,
      'createdAt': '2026-06-18T08:00:00.000Z',
    },
  ],
  'fields': [
    {
      'key': 'line',
      'label': 'Hangi hat?',
      'type': 'select',
      'value': '3',
      'number': null,
      'date': null,
      'formVersion': 1,
    },
  ],
  'rating': {
    'score': 5,
    'comment': null,
    'sentAt': '2026-06-20T10:00:00.000Z',
    'ratedAt': '2026-06-20T12:00:00.000Z',
  },
  'labour': {'minutes': 90, 'unpricedMinutes': 0, 'byCurrency': []},
  'links': [],
};

void main() {
  late AwDatabase db;
  late _Server server;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('tr'));
    db = AwDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    server = _Server();
  });

  tearDown(() => db.close());

  List<Override> overrides() {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.alliswell.test'))
      ..httpClientAdapter = server;
    return [
      // An empty replica: this device holds no copy of #1042.
      databaseProvider.overrideWithValue(db),
      eeRequesterTicketApiProvider.overrideWithValue(EeRequesterTicketApi(dio)),
      eeTicketArchiveApiProvider.overrideWithValue(EeTicketArchiveApi(dio)),
      eeFeatureProvider.overrideWith((ref, name) => true),
      canProvider.overrideWith((ref, permission) => false),
      // Who is signed in, without a session (whose restore leaves a timer).
      currentUserIdProvider.overrideWithValue('01USERMEAAAAAAAAAAAAAAAAAA'),
      workspacesProvider.overrideWith(
        (ref) async => const [
          WorkspaceSummary(
            id: _ws,
            name: 'Bakım',
            slug: 'bakim',
            colorRgb: '#2563EB',
            role: 'member',
          ),
          WorkspaceSummary(
            id: _otherWs,
            name: 'Kalite',
            slug: 'kalite',
            colorRgb: '#16A34A',
            role: 'member',
          ),
        ],
      ),
    ];
  }

  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    List<Override> extra = const [],
  }) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        // The app's own retry policy (main.dart), not Riverpod's default ten.
        retry: awRetry,
        overrides: [...overrides(), ...extra],
        child: MaterialApp(theme: buildAwTheme(Brightness.light), home: home),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('AW-E17: the manager opens the three-month-old #1042 link and '
      'reads how it was solved', (tester) async {
    server.live = (_) => _json(404, _notFound);
    server.archive = (_) => _json(200, _archived);
    await pump(tester, const EeTicketDetailScreen(ticketId: _id));

    // Not "no longer on the device": the archive, and it says so first.
    expect(find.text('ee.tickets.goneTitle'.tr()), findsNothing);
    expect(find.byKey(const Key('archive-strip')), findsOneWidget);
    expect(find.text('#1042'), findsOneWidget);
    expect(find.text('Hat 3 pres yağ kaçırıyor'), findsOneWidget);
    // The earlier solution — the reason the manager opened it.
    expect(find.text('Conta değiştirildi, sızıntı durdu.'), findsOneWidget);
    // The desk's own note is still marked as the desk's.
    expect(
      find.descendant(
        of: find.byKey(const Key('archive-comment-C2')),
        matching: find.text('ee.tickets.internalNote'.tr()),
      ),
      findsOneWidget,
    );
    // What the request left behind (EE-265): the answer and who approved it.
    expect(find.text('Hangi hat?'), findsOneWidget);
    expect(find.byKey(const Key('archive-approval')), findsOneWidget);
    expect(find.textContaining('Ayla Yönetici'), findsOneWidget);
    // Read-only: nothing on this screen writes.
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('AW-E17: the same request is found by searching — the queue '
      'hands its words to the archive', (tester) async {
    server.search = (options) => _json(200, {
      'tickets': [_archived],
      'nextCursor': null,
    });
    server.archive = (_) => _json(200, _archived);
    await pump(
      tester,
      const EeTicketQueueScreen(),
      extra: [
        ticketQueueProvider.overrideWith((ref) => Stream.value(const [])),
        ticketAssigneesProvider.overrideWith((ref) => Stream.value(const {})),
        // The device's own search: nothing on the device matches.
        ticketSearchResultsProvider.overrideWith(
          (ref) async => const <SearchHit>[],
        ),
      ],
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(EeTicketQueueScreen)),
    );
    container.read(ticketSearchQueryProvider.notifier).set('yag kaciriyor');
    await tester.pumpAndSettle();

    // The empty search no longer points at an archive nobody can open.
    expect(find.byKey(const Key('ticket-search-empty')), findsOneWidget);
    await tester.tap(find.byKey(const Key('ticket-search-archive')));
    await tester.pumpAndSettle();

    // The archive was asked with the words the person typed.
    final asked = server.asked.firstWhere(
      (o) => o.path == '/api/v1/ee/team/tickets/archive',
    );
    expect(asked.queryParameters['q'], 'yag kaciriyor');
    expect(find.byKey(const Key('archive-row-$_id')), findsOneWidget);

    await tester.tap(find.byKey(const Key('archive-row-$_id')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('archive-strip')), findsOneWidget);
    expect(find.text('Conta değiştirildi, sızıntı durdu.'), findsOneWidget);
  });

  testWidgets('EE-266: a live request in another unit says so, and offers the '
      'switch — it is not "closed and dropped"', (tester) async {
    server.live = (_) => _json(200, {
      'id': _id,
      'workspaceId': _otherWs,
      'subject': 'Kalibrasyon sapması',
      'status': 'in_progress',
      'viewer': 'desk',
    });
    await pump(tester, const EeTicketDetailScreen(ticketId: _id));

    expect(find.byKey(const Key('ticket-elsewhere-unit')), findsOneWidget);
    expect(find.text('ee.tickets.goneTitle'.tr()), findsNothing);
    expect(
      find.text('ee.tickets.elsewhere.switch'.tr(args: {'unit': 'Kalite'})),
      findsOneWidget,
    );
    // The archive was not asked: a live request answered first.
    expect(server.asked.where((o) => o.path.contains('/archive')), isEmpty);
  });

  testWidgets('EE-266: in neither table for this person — "not found", not '
      '"dropped"', (tester) async {
    server.live = (_) => _json(404, _notFound);
    server.archive = (_) => _json(404, _notFound);
    await pump(tester, const EeTicketDetailScreen(ticketId: _id));
    expect(find.byKey(const Key('ticket-elsewhere-nowhere')), findsOneWidget);
    expect(find.text('ee.tickets.goneTitle'.tr()), findsNothing);
  });

  testWidgets('EE-266: with no signal it names the connection it needs', (
    tester,
  ) async {
    server.offline = true;
    await pump(tester, const EeTicketDetailScreen(ticketId: _id));
    // Past the app's own three quick retries (awRetry), the answer settles
    // on the connection.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ticket-elsewhere-offline')), findsOneWidget);
  });

  testWidgets('EE-252 still holds: the person who asked gets their own view', (
    tester,
  ) async {
    server.live = (_) => _json(200, {
      'id': _id,
      'subject': 'Ekranım donuyor',
      'status': 'in_progress',
      'viewer': 'requester',
    });
    await pump(tester, const EeTicketDetailScreen(ticketId: _id));
    expect(find.byType(EeRequesterTicketScreen), findsOneWidget);
    expect(find.byKey(const Key('archive-strip')), findsNothing);
  });
}
