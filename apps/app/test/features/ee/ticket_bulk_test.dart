import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/api_exception.dart';
import 'package:alliswell/src/core/reachability.dart';
import 'package:alliswell/src/features/ee/assignments_providers.dart';
import 'package:alliswell/src/features/ee/data/ticket_write_api.dart';
import 'package:alliswell/src/features/ee/data/unit_tickets_api.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/ticket_write_providers.dart';
import 'package:alliswell/src/features/ee/tickets_providers.dart';
import 'package:alliswell/src/features/ee/unit_tickets_providers.dart';
import 'package:alliswell/src/features/ee/ui/ticket_queue_screen.dart';
import 'package:alliswell/src/features/workspaces/workspaces.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/providers.dart';
import 'package:alliswell/src/theme/theme.dart';

/// EE-227 — one action on many requests, from the queue.
///
/// The server's half — every row through the single door's checks, a missing
/// verb refusing the batch, a requester unable to staff a request in bulk as
/// on the single door (EE-245) — is `tickets-bulk.integration.test.js`. These
/// pin what the person meets: the selection, the moves the SERVER offers
/// (asked once per status held, never typed out here), the second taps the
/// single sheet asks for, and a partial answer told row by row.
const _me = '01USAAAAAAAAAAAAAAAAAAAAAA';
const _other = '01USBBBBBBBBBBBBBBBBBBBBBB';

TicketRecord _ticket(String id, String subject, {String status = 'new'}) =>
    TicketRecord(
      id: id,
      workspaceId: 'W1',
      subject: subject,
      status: status,
      priority: 'normal',
      source: 'internal',
      revision: 1,
      createdAt: DateTime.utc(2026, 9, 24),
    );

EeTicketActions _actions(
  String status, {
  List<String> moves = const [],
  bool canAssignOthers = false,
}) => EeTicketActions(
  status: status,
  priority: 'normal',
  allowedTransitions: moves,
  waitingReasons: const ['requester_info', 'supplier', 'spare_part'],
  priorities: const ['low', 'normal', 'high', 'urgent'],
  canAssignOthers: canAssignOthers,
);

class _FakeWrite extends Fake implements EeTicketWriteApi {
  _FakeWrite(this.byStatus, this.statusOf);

  final Map<String, EeTicketActions> byStatus;
  final String Function(String ticketId) statusOf;
  final asked = <String>[];
  final sent = <({List<String> ids, Map<String, Object> action})>[];
  EeBulkResult? answer;
  Object? failWith;

  @override
  Future<EeTicketActions?> actions(String ticketId) async {
    asked.add(ticketId);
    return byStatus[statusOf(ticketId)];
  }

  @override
  Future<EeBulkResult> bulk(
    List<String> ticketIds,
    Map<String, Object> action,
  ) async {
    if (failWith != null) throw failWith!;
    sent.add((ids: ticketIds, action: action));
    return answer ??
        EeBulkResult(
          changed: ticketIds.length,
          skipped: 0,
          rows: [
            for (final id in ticketIds) EeBulkRow(ticketId: id, changed: true),
          ],
        );
  }
}

void main() {
  late ProviderContainer container;
  late _FakeWrite api;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('tr'));
  });

  final three = [
    _ticket('T1', 'Pres 2 yağ kaçırıyor'),
    _ticket('T2', 'Hat 1 durdu'),
    _ticket('T3', 'Kompresör sesi', status: 'in_progress'),
  ];

  Future<void> pumpQueue(
    WidgetTester tester, {
    List<TicketRecord>? rows,
    bool canAssignOthers = false,
    bool mayCreate = false,
    bool offline = false,
  }) async {
    final tickets = rows ?? three;
    api = _FakeWrite({
      'new': _actions(
        'new',
        moves: const ['triage', 'in_progress', 'cancelled'],
        canAssignOthers: canAssignOthers,
      ),
      'in_progress': _actions(
        'in_progress',
        moves: const ['waiting', 'resolved', 'cancelled'],
        canAssignOthers: canAssignOthers,
      ),
    }, (id) => tickets.firstWhere((t) => t.id == id).status);
    container = ProviderContainer(
      overrides: <Override>[
        ticketQueueProvider.overrideWith((ref) => Stream.value(tickets)),
        ticketAssigneesProvider.overrideWith(
          (ref) => Stream.value(const <String, List<Assignee>>{}),
        ),
        currentUserIdProvider.overrideWithValue(_me),
        canProvider.overrideWith(
          (ref, permission) => mayCreate && permission == 'tickets.create',
        ),
        eeFeatureProvider.overrideWith((ref, feature) => true),
        eeTicketWriteApiProvider.overrideWithValue(api),
        syncEngineProvider.overrideWithValue(null),
        // EE-267: the queue's strip of other units' SLA alerts is a SERVER
        // read with its own suite (my_units_test); this one is about the
        // replica's rows, so the strip has nothing to say here.
        eeOtherUnitsAlertsProvider.overrideWith(
          (ref) async => const EeUnitTicketsPage(),
        ),
        workspaceRosterOfProvider.overrideWith(
          (ref, workspaceId) => Stream.value([
            for (final (id, name) in [(_me, 'Ayla Servis'), (_other, 'Barış')])
              MemberProfile(
                id: 'P-$id',
                workspaceId: workspaceId,
                userId: id,
                displayName: name,
                colorRgb: '#2563EB',
                revision: 1,
              ),
          ]),
        ),
      ],
    );
    addTearDown(container.dispose);
    if (offline) {
      container.read(serverReachabilityProvider.notifier).unreachable();
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
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
  }

  Finder key(String value) => find.byKey(Key(value));
  String count(WidgetTester tester) =>
      tester.widget<Text>(key('bulk-count')).data!;
  bool enabled(WidgetTester tester, String k) =>
      tester.widget<IconButton>(key(k)).onPressed != null;

  Future<void> select(WidgetTester tester, List<String> ids) async {
    await tester.longPress(key('ticket-${ids.first}'));
    await tester.pumpAndSettle();
    for (final id in ids.skip(1)) {
      await tester.tap(key('ticket-$id'));
      await tester.pumpAndSettle();
    }
  }

  Future<void> openSheet(WidgetTester tester, String action) async {
    await tester.tap(key(action));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'a long press starts a selection; taps then tick, and the bar counts',
    (tester) async {
      await pumpQueue(tester);
      expect(key('bulk-count'), findsNothing);
      await tester.longPress(key('ticket-T1'));
      await tester.pumpAndSettle();
      expect(count(tester), '1 seçili');
      expect(key('ticket-select-T2'), findsOneWidget, reason: 'boxes appear');

      await tester.tap(key('ticket-T2'));
      await tester.pumpAndSettle();
      expect(count(tester), '2 seçili');
      await tester.tap(key('ticket-T1'));
      await tester.pumpAndSettle();
      expect(count(tester), '1 seçili');

      await tester.tap(key('bulk-exit'));
      await tester.pumpAndSettle();
      expect(key('bulk-count'), findsNothing);
      expect(key('ticket-select-T2'), findsNothing);
    },
  );

  testWidgets('while selecting, "new request" steps aside', (tester) async {
    await pumpQueue(tester, mayCreate: true);
    expect(key('ticket-new'), findsOneWidget);
    await select(tester, ['T1']);
    expect(key('ticket-new'), findsNothing);
  });

  testWidgets(
    'select all takes what is on screen, and a filter drops what it hides',
    (tester) async {
      await pumpQueue(tester);
      await select(tester, ['T1']);
      await tester.tap(key('bulk-select-all'));
      await tester.pumpAndSettle();
      expect(count(tester), '3 seçili');

      // Narrow to `new`: the in-progress one leaves the screen and the batch.
      container.read(ticketFilterProvider.notifier).toggleStatus('new');
      await tester.pumpAndSettle();
      expect(count(tester), '2 seçili');

      // …and it is DROPPED, not hidden: lifting the filter does not bring it
      // back ticked behind the person's back.
      container.read(ticketFilterProvider.notifier).clear();
      await tester.pumpAndSettle();
      expect(count(tester), '2 seçili');
      expect(tester.widget<Checkbox>(key('ticket-select-T3')).value, isFalse);
    },
  );

  testWidgets('no signal: selecting works, sending does not, and it says why', (
    tester,
  ) async {
    await pumpQueue(tester, offline: true);
    await select(tester, ['T1', 'T2']);
    expect(count(tester), '2 seçili');
    for (final action in ['bulk-status', 'bulk-priority', 'bulk-assign']) {
      expect(enabled(tester, action), isFalse, reason: action);
    }
    expect(find.textContaining('Bağlantı yok'), findsOneWidget);
    expect(api.asked, isEmpty);
  });

  testWidgets('more than a hundred: the bar says to narrow it', (tester) async {
    await pumpQueue(
      tester,
      rows: [for (var i = 0; i < 101; i += 1) _ticket('T$i', 'Talep $i')],
    );
    // The list builds what is on screen; press whichever card that is.
    await tester.longPress(
      find
          .byWidgetPredicate(
            (w) =>
                w.key is ValueKey<String> &&
                (w.key! as ValueKey<String>).value.startsWith('ticket-T'),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(key('bulk-select-all'));
    await tester.pumpAndSettle();
    expect(count(tester), '101 seçili');
    expect(enabled(tester, 'bulk-status'), isFalse);
    expect(find.textContaining('en çok 100'), findsOneWidget);
  });

  testWidgets(
    'status: the moves are the server\'s, asked once per status held',
    (tester) async {
      await pumpQueue(tester);
      await select(tester, ['T1', 'T2', 'T3']);
      await openSheet(tester, 'bulk-status');
      // Two statuses in the selection → two questions, not three.
      expect(api.asked.toSet(), {'T1', 'T3'});
      for (final to in [
        'triage',
        'in_progress',
        'cancelled',
        'waiting',
        'resolved',
      ]) {
        expect(key('bulk-status-$to'), findsOneWidget, reason: to);
      }
      expect(
        key('bulk-status-closed'),
        findsNothing,
        reason: 'nobody offered it',
      );

      await tester.tap(key('bulk-status-resolved'));
      await tester.pumpAndSettle();
      expect(api.sent.single.ids, ['T1', 'T2', 'T3']);
      expect(api.sent.single.action, {'type': 'status', 'status': 'resolved'});
      expect(find.text('3 talep değişti.'), findsOneWidget);
      expect(key('bulk-count'), findsNothing, reason: 'the selection is done');
    },
  );

  testWidgets('waiting asks for a reason first, from the server\'s list', (
    tester,
  ) async {
    await pumpQueue(tester);
    await select(tester, ['T3']);
    await openSheet(tester, 'bulk-status');
    await tester.tap(key('bulk-status-waiting'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(key('bulk-confirm')).onPressed,
      isNull,
      reason: 'no reason picked yet',
    );
    await tester.tap(key('bulk-reason-spare_part'));
    await tester.pumpAndSettle();
    await tester.tap(key('bulk-confirm'));
    await tester.pumpAndSettle();
    expect(api.sent.single.action, {
      'type': 'status',
      'status': 'waiting',
      'waitingReason': 'spare_part',
    });
  });

  testWidgets('an ending asks for a yes, with the count in it', (tester) async {
    await pumpQueue(tester);
    await select(tester, ['T1', 'T2']);
    await openSheet(tester, 'bulk-status');
    await tester.tap(key('bulk-status-cancelled'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(key('bulk-confirm-text')).data,
      contains('2 talep iptal edilecek'),
    );
    expect(api.sent, isEmpty);
    await tester.tap(key('bulk-confirm'));
    await tester.pumpAndSettle();
    expect(api.sent.single.action, {'type': 'status', 'status': 'cancelled'});
  });

  testWidgets('a partial answer names each refused request under its reason', (
    tester,
  ) async {
    await pumpQueue(tester);
    api.answer = const EeBulkResult(
      changed: 1,
      skipped: 2,
      rows: [
        EeBulkRow(ticketId: 'T1', changed: false, reason: 'NO_CHANGE'),
        EeBulkRow(ticketId: 'T2', changed: true),
        EeBulkRow(
          ticketId: 'T3',
          changed: false,
          reason: 'TICKET_APPROVAL_PENDING',
        ),
      ],
    );
    await select(tester, ['T1', 'T2', 'T3']);
    await openSheet(tester, 'bulk-status');
    await tester.tap(key('bulk-status-triage'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(key('bulk-result-title')).data,
      '3 talepten 1 tanesi değişti',
    );
    expect(find.textContaining('onay bekliyor'), findsOneWidget);
    expect(find.text('• Kompresör sesi'), findsOneWidget);
    expect(find.textContaining('Zaten öyleydi'), findsOneWidget);
    // The rows that need a look lead; "it already was" comes last.
    expect(
      tester.getTopLeft(key('bulk-result-TICKET_APPROVAL_PENDING')).dy,
      lessThan(tester.getTopLeft(key('bulk-result-NO_CHANGE')).dy),
    );
    await tester.tap(key('bulk-result-ok'));
    await tester.pumpAndSettle();
    expect(key('bulk-count'), findsNothing);
  });

  testWidgets(
    'a batch refused whole stays in its sheet, in the server\'s words',
    (tester) async {
      await pumpQueue(tester);
      api.failWith = const ApiException('PERM_DENIED', 'Missing permission');
      await select(tester, ['T1']);
      await openSheet(tester, 'bulk-status');
      await tester.tap(key('bulk-status-triage'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(key('bulk-error')).data,
        'Bunu yapmaya yetkin yok.',
      );
      expect(
        key('bulk-status-triage'),
        findsOneWidget,
        reason: 'sheet still open',
      );
    },
  );

  testWidgets('priority: the server\'s tiers', (tester) async {
    await pumpQueue(tester);
    await select(tester, ['T1', 'T3']);
    await openSheet(tester, 'bulk-priority');
    await tester.tap(key('bulk-priority-high'));
    await tester.pumpAndSettle();
    expect(api.sent.single.action, {'type': 'priority', 'priority': 'high'});
  });

  testWidgets('assign: yourself without the verb — and nobody else', (
    tester,
  ) async {
    await pumpQueue(tester);
    await select(tester, ['T1', 'T2']);
    await openSheet(tester, 'bulk-assign');
    expect(key('bulk-assign-self-only'), findsOneWidget);
    expect(key('bulk-assign-$_other'), findsNothing);
    await tester.tap(key('bulk-assign-me'));
    await tester.pumpAndSettle();
    expect(api.sent.single.action, {'type': 'assign', 'userId': _me});
  });

  testWidgets('assign: with the verb, the unit\'s people are offered too', (
    tester,
  ) async {
    await pumpQueue(tester, canAssignOthers: true);
    await select(tester, ['T1']);
    await openSheet(tester, 'bulk-assign');
    expect(key('bulk-assign-self-only'), findsNothing);
    expect(
      key('bulk-assign-$_me'),
      findsNothing,
      reason: 'offered once, as "me"',
    );
    await tester.tap(key('bulk-assign-$_other'));
    await tester.pumpAndSettle();
    expect(api.sent.single.action, {'type': 'assign', 'userId': _other});
  });
}
