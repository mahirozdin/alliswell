// OPH-358 — one harness for the request detail as the thread, the company
// line and the linked requests meet it. Every provider the screen watches is
// answered here, so a test names only what it is about.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:alliswell/src/features/ee/assignments_providers.dart';
import 'package:alliswell/src/features/ee/changes_providers.dart';
import 'package:alliswell/src/features/ee/data/ticket_links_api.dart';
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
import 'package:alliswell/src/features/workspaces/workspaces.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/providers.dart';
import 'package:alliswell/src/theme/theme.dart';

const kHarnessTicketId = '01TKAAAAAAAAAAAAAAAAAAAAAA';

TicketRecord harnessTicket({
  String id = kHarnessTicketId,
  int? number = 218,
  String subject = 'Kompresör arızası',
  String status = 'in_progress',
  String source = 'app',
  String? requesterId,
  String? requesterEmail,
  DateTime? terminalAt,
}) => TicketRecord(
  id: id,
  workspaceId: 'W1',
  number: number,
  subject: subject,
  status: status,
  priority: 'normal',
  source: source,
  requesterId: requesterId,
  requesterEmail: requesterEmail,
  revision: 1,
  createdAt: DateTime.utc(2026, 9, 20),
  terminalAt: terminalAt,
);

TicketCommentRecord harnessComment(
  String id, {
  String? authorId,
  String body = 'Bir yanıt',
  bool internal = false,
}) => TicketCommentRecord(
  id: id,
  workspaceId: 'W1',
  ticketId: kHarnessTicketId,
  authorId: authorId,
  body: body,
  internal: internal,
  revision: 1,
  createdAt: DateTime.utc(2026, 10, 7, 9, 30),
);

/// Records what the screen asked the links door to do.
class FakeLinksApi extends Fake implements EeTicketLinksApi {
  final linked = <({String type, String relatedTicketId})>[];
  final unlinked = <String>[];
  final customersSet = <String?>[];
  String opened = '01TKNEWAAAAAAAAAAAAAAAAAAA';
  List<EeCustomerChoice> companies = const [
    EeCustomerChoice(
      id: '01CUAAAAAAAAAAAAAAAAAAAAAA',
      name: 'Anadolu Otomotiv',
    ),
  ];

  @override
  Future<void> link(
    String ticketId, {
    required String type,
    required String relatedTicketId,
  }) async => linked.add((type: type, relatedTicketId: relatedTicketId));

  @override
  Future<void> unlink(String ticketId, String linkId) async =>
      unlinked.add(linkId);

  @override
  Future<List<EeCustomerChoice>> customers() async => companies;

  @override
  Future<void> setCustomer(String ticketId, String? customerId) async =>
      customersSet.add(customerId);

  @override
  Future<String> openRelated(
    String ticketId, {
    String? subject,
    String? body,
  }) async => opened;
}

/// The reply door, recording what was sent; answers a comment id.
class FakeThreadWriteApi extends Fake implements EeTicketWriteApi {
  final sent = <({String body, bool internal})>[];

  @override
  Future<String?> comment(
    String ticketId, {
    required String body,
    required bool internal,
  }) async {
    sent.add((body: body, internal: internal));
    return '01CMNEWAAAAAAAAAAAAAAAAAAA';
  }

  @override
  Future<List<EeCannedReply>> cannedReplies(String ticketId) async => const [];
}

/// Pumps the detail of [ticket] under a router (so a tap that opens another
/// request lands on a route the test can see), with everything else quiet.
Future<GoRouter> pumpTicketDetail(
  WidgetTester tester, {
  required TicketRecord ticket,
  List<TicketCommentRecord> comments = const [],
  EeTicketRelations relations = const EeTicketRelations(),
  Map<String, String> names = const {},
  String? me = '01USDESKAAAAAAAAAAAAAAAAAA',
  Set<String> verbs = const {},
  FakeLinksApi? links,
  EeTicketWriteApi? write,
  Map<String, TicketRecord> others = const {},
  List<TicketRecord> candidates = const [],
  Map<String, List<FileAttachment>> commentFiles = const {},
  List<Override> extra = const [],
}) async {
  final router = GoRouter(
    initialLocation: '/tickets/${ticket.id}',
    routes: [
      GoRoute(
        path: '/tickets/:id',
        builder: (_, state) => state.pathParameters['id'] == ticket.id
            ? EeTicketDetailScreen(ticketId: ticket.id)
            : Scaffold(
                body: Text(
                  'opened ${state.pathParameters['id']}',
                  key: Key('opened-${state.pathParameters['id']}'),
                ),
              ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        ticketProvider(ticket.id).overrideWith((ref) => Stream.value(ticket)),
        ticketCommentsProvider(
          ticket.id,
        ).overrideWith((ref) => Stream.value(comments)),
        targetFilesProvider.overrideWith(
          (ref, target) => Stream.value(
            target.targetType == 'ticket_comment'
                ? commentFiles[target.targetId] ?? const []
                : const [],
          ),
        ),
        eeTicketExternalFilesProvider(
          ticket.id,
        ).overrideWith((ref) async => EeExternalFiles.none),
        eeTicketRelationsProvider(
          ticket.id,
        ).overrideWith((ref) async => relations),
        eeTicketActionsProvider(ticket.id).overrideWith((ref) async => null),
        eeChangesRaisedFromProvider(
          ticket.id,
        ).overrideWith((ref) async => const []),
        eeKbSuggestionsProvider(
          ticket.subject,
        ).overrideWith((ref) async => const []),
        eeKbOfTicketProvider(ticket.id).overrideWith((ref) async => const []),
        eeWorklogProvider(ticket.id).overrideWith((ref) async => null),
        ticketAssigneesForProvider(
          ticket.id,
        ).overrideWith((ref) => Stream.value(const [])),
        workspaceRosterOfProvider.overrideWith(
          (ref, workspaceId) => Stream.value(const []),
        ),
        eeMemberNamesProvider.overrideWith((ref) => Stream.value(names)),
        currentUserIdProvider.overrideWithValue(me),
        canProvider.overrideWith((ref, verb) => verbs.contains(verb)),
        eeFeatureProvider.overrideWith((ref, feature) => true),
        eeTicketLinksApiProvider.overrideWithValue(links ?? FakeLinksApi()),
        eeTicketWriteApiProvider.overrideWithValue(
          write ?? FakeThreadWriteApi(),
        ),
        eeCannedRepliesProvider(
          ticket.id,
        ).overrideWith((ref) async => const []),
        eeLinkedTicketsProvider.overrideWith(
          (ref, ids) =>
              Stream.value({for (final id in ids.split(',')) id: ?others[id]}),
        ),
        eeLinkCandidatesProvider.overrideWith(
          (ref, workspaceId) => Stream.value(candidates),
        ),
        syncEngineProvider.overrideWithValue(null),
        ...extra,
      ],
      child: MaterialApp.router(
        theme: buildAwTheme(Brightness.light),
        routerConfig: router,
      ),
    ),
  );
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await settleDetail(tester);
  return router;
}

/// The detail never settles (the SLA countdown ticks), so a test steps the
/// clock far enough for a sheet, a dialog or a route to finish moving.
Future<void> settleDetail(WidgetTester tester) async {
  for (var i = 0; i < 8; i += 1) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// A small file, as a picker hands it over.
Uint8List harnessBytes() => Uint8List.fromList(const [1, 2, 3]);
