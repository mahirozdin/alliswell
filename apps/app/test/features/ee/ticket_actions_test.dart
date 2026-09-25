import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/api_exception.dart';
import 'package:alliswell/src/core/reachability.dart';
import 'package:alliswell/src/features/ee/changes_providers.dart';
import 'package:alliswell/src/features/ee/data/ticket_links_models.dart';
import 'package:alliswell/src/features/ee/data/ticket_write_api.dart';
import 'package:alliswell/src/features/ee/assignments_providers.dart';
import 'package:alliswell/src/features/ee/kb_providers.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/ticket_links_providers.dart';
import 'package:alliswell/src/features/ee/ticket_write_providers.dart';
import 'package:alliswell/src/features/ee/tickets_providers.dart';
import 'package:alliswell/src/features/ee/ui/ticket_actions.dart';
import 'package:alliswell/src/features/ee/ui/ticket_detail_screen.dart';
import 'package:alliswell/src/features/ee/worklog_providers.dart';
import 'package:alliswell/src/features/files/providers.dart';
import 'package:alliswell/src/features/workspaces/workspaces.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/providers.dart';
import 'package:alliswell/src/theme/theme.dart';

/// EE-224 — moving a request and setting its priority from its own screen.
///
/// The server half (what the detail says a caller may do, generated from the
/// lifecycle map and checked against the doors) is tested where it lives.
/// These pin the half the person sees: that the sheet offers what the server
/// listed and nothing else, that the two moves with a second step ask for it,
/// and that without a connection nothing is offered that could not work.
const _ticketId = '01TKAAAAAAAAAAAAAAAAAAAAAA';

const _reasons = ['requester_info', 'supplier', 'spare_part'];
const _tiers = ['low', 'normal', 'high', 'urgent'];

/// The shipped 3×3 (EE-183), with ONE cell changed — `site.high` says `high`
/// here, not `urgent` — so a preview that read a copy of the default instead
/// of the table it was handed would say the wrong word.
const _matrixCells = {
  'person': {'low': 'low', 'medium': 'low', 'high': 'normal'},
  'unit': {'low': 'normal', 'medium': 'normal', 'high': 'high'},
  'site': {'low': 'normal', 'medium': 'high', 'high': 'high'},
};

EeTicketActions _actions({
  String status = 'in_progress',
  String priority = 'high',
  List<String> allowed = const ['waiting', 'resolved', 'cancelled'],
  List<String> waitingReasons = _reasons,
  bool approvalPending = false,
  String? impact,
  String? urgency,
  bool overridden = false,
  bool canOverride = false,
  bool canPause = false,
  bool pausable = false,
  List<String> held = const [],
  bool canAssignOthers = false,
}) => EeTicketActions(
  status: status,
  priority: priority,
  impact: impact,
  urgency: urgency,
  priorityOverridden: overridden,
  allowedTransitions: allowed,
  waitingReasons: waitingReasons,
  priorities: _tiers,
  approvalPending: approvalPending,
  canOverridePriority: canOverride,
  canPauseSla: canPause,
  canAssignOthers: canAssignOthers,
  slaPausable: pausable,
  slaHeld: held.isNotEmpty,
  slaHoldReasons: held,
);

class _FakeWriteApi extends Fake implements EeTicketWriteApi {
  EeTicketActions? answer = _actions();
  EePriorityMatrix? matrix = const EePriorityMatrix(cells: _matrixCells);
  Object? failWith;
  int reads = 0;

  final statuses = <({String status, String? reason})>[];
  final priorities = <String>[];
  final inputs = <({String impact, String urgency})>[];
  final pauses = <String>[];
  int resumes = 0;
  final assigned = <String>[];
  final released = <String>[];

  /// Holds an assignment write open, so a test can look at the sheet while it
  /// is in flight.
  Completer<void>? hold;

  void _maybeFail() {
    if (failWith != null) throw failWith!;
  }

  @override
  Future<EeTicketActions?> actions(String ticketId) async {
    reads++;
    return answer;
  }

  @override
  Future<EePriorityMatrix?> priorityMatrix() async => matrix;

  @override
  Future<void> setStatus(
    String ticketId,
    String status, {
    String? waitingReason,
  }) async {
    _maybeFail();
    statuses.add((status: status, reason: waitingReason));
  }

  @override
  Future<String?> setPriority(String ticketId, String priority) async {
    _maybeFail();
    priorities.add(priority);
    return priority;
  }

  @override
  Future<String?> setMatrixInputs(
    String ticketId, {
    required String impact,
    required String urgency,
  }) async {
    _maybeFail();
    inputs.add((impact: impact, urgency: urgency));
    return matrix?.derive(impact, urgency);
  }

  @override
  Future<void> pauseSla(String ticketId, String reason) async {
    _maybeFail();
    pauses.add(reason);
  }

  @override
  Future<void> resumeSla(String ticketId) async {
    _maybeFail();
    resumes++;
  }

  @override
  Future<String> assign(String ticketId, String userId) async {
    await hold?.future;
    _maybeFail();
    assigned.add(userId);
    return 'A-$userId';
  }

  @override
  Future<void> release(String ticketId, String assignmentId) async {
    _maybeFail();
    released.add(assignmentId);
  }
}

TicketRecord _ticket({DateTime? terminalAt}) => TicketRecord(
  id: _ticketId,
  workspaceId: 'W1',
  subject: 'Kompresör arızası',
  status: terminalAt == null ? 'in_progress' : 'closed',
  priority: 'high',
  source: 'app',
  revision: 1,
  createdAt: DateTime.utc(2026, 9, 20),
  terminalAt: terminalAt,
);

void main() {
  late _FakeWriteApi api;
  late ProviderContainer container;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('tr'));
    api = _FakeWriteApi();
    container = ProviderContainer(
      overrides: [
        eeTicketWriteApiProvider.overrideWithValue(api),
        eeFeatureProvider('teams').overrideWithValue(true),
        ticketProvider(
          _ticketId,
        ).overrideWith((ref) => Stream.value(_ticket())),
        syncEngineProvider.overrideWithValue(null),
      ],
    );
  });
  tearDown(() => container.dispose());

  Future<void> pumpChips(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAwTheme(Brightness.light),
          home: Scaffold(
            body: Column(
              children: [
                Wrap(
                  children: [
                    EeTicketStatusAction(ticket: _ticket()),
                    EeTicketPriorityAction(ticket: _ticket()),
                  ],
                ),
                const EeTicketActionsOffline(),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder key(String k) => find.byKey(Key(k));
  bool pressable(WidgetTester tester, String k) =>
      tester.widget<ActionChip>(key(k)).onPressed != null;
  bool enabled(WidgetTester tester, String k) =>
      tester.widget<ButtonStyleButton>(key(k)).onPressed != null;

  Future<void> openStatus(WidgetTester tester) async {
    await tester.tap(key('ticket-status'));
    await tester.pumpAndSettle();
  }

  Future<void> openPriority(WidgetTester tester) async {
    await tester.tap(key('ticket-priority'));
    await tester.pumpAndSettle();
  }

  group('the status sheet', () {
    testWidgets('offers exactly the moves the server listed — nothing else', (
      tester,
    ) async {
      // Two answers for the same state: the admin's, and the one for
      // somebody who may not end a matter. The sheet draws each verbatim.
      for (final allowed in [
        ['waiting', 'resolved', 'cancelled'],
        ['waiting', 'resolved'],
      ]) {
        api.answer = _actions(allowed: allowed);
        container.invalidate(eeTicketActionsProvider(_ticketId));
        await pumpChips(tester);
        await openStatus(tester);

        for (final status in [
          'new',
          'triage',
          'in_progress',
          'waiting',
          'resolved',
          'closed',
          'cancelled',
        ]) {
          expect(
            key('ticket-status-$status'),
            allowed.contains(status) ? findsOneWidget : findsNothing,
            reason: '$status with $allowed',
          );
        }
        await tester.tapAt(const Offset(10, 10)); // dismiss
        await tester.pumpAndSettle();
      }
    });

    testWidgets('an ordinary move is one tap, and says what happened', (
      tester,
    ) async {
      await pumpChips(tester);
      await openStatus(tester);
      await tester.tap(key('ticket-status-resolved'));
      await tester.pumpAndSettle();

      expect(api.statuses, [(status: 'resolved', reason: null)]);
      expect(key('ticket-status-resolved'), findsNothing, reason: 'closed');
      expect(find.text('Durum: Çözüldü'), findsOneWidget);
    });

    testWidgets("waiting asks why — from the server's list — before sending", (
      tester,
    ) async {
      api.answer = _actions(waitingReasons: ['requester_info', 'spare_part']);
      await pumpChips(tester);
      await openStatus(tester);
      await tester.tap(key('ticket-status-waiting'));
      await tester.pumpAndSettle();

      expect(api.statuses, isEmpty, reason: 'nothing sent without a reason');
      expect(enabled(tester, 'ticket-reason-apply'), isFalse);
      expect(key('ticket-reason-requester_info'), findsOneWidget);
      expect(key('ticket-reason-spare_part'), findsOneWidget);
      // Not in this server's list, so not on the screen.
      expect(key('ticket-reason-supplier'), findsNothing);

      await tester.tap(key('ticket-reason-spare_part'));
      await tester.pumpAndSettle();
      await tester.tap(key('ticket-reason-apply'));
      await tester.pumpAndSettle();

      expect(api.statuses, [(status: 'waiting', reason: 'spare_part')]);
    });

    testWidgets('an ending asks for a yes, and Back takes the question back', (
      tester,
    ) async {
      api.answer = _actions(
        status: 'resolved',
        allowed: ['closed', 'in_progress'],
      );
      await pumpChips(tester);
      await openStatus(tester);

      await tester.tap(key('ticket-status-closed'));
      await tester.pumpAndSettle();
      expect(key('ticket-status-confirm-text'), findsOneWidget);
      expect(api.statuses, isEmpty);

      await tester.tap(key('ticket-action-back'));
      await tester.pumpAndSettle();
      expect(key('ticket-status-closed'), findsOneWidget, reason: 'the list');
      expect(api.statuses, isEmpty);

      await tester.tap(key('ticket-status-closed'));
      await tester.pumpAndSettle();
      await tester.tap(key('ticket-status-confirm'));
      await tester.pumpAndSettle();
      expect(api.statuses, [(status: 'closed', reason: null)]);
    });

    testWidgets('a second step lasts only while the server still offers it', (
      tester,
    ) async {
      api.answer = _actions(
        status: 'resolved',
        allowed: ['closed', 'in_progress'],
      );
      await pumpChips(tester);
      await openStatus(tester);
      await tester.tap(key('ticket-status-closed'));
      await tester.pumpAndSettle();
      expect(key('ticket-status-confirm'), findsOneWidget);

      // A pull brings somebody else's reopening while the question is open:
      // "close" is no longer the server's offer, so it is no longer asked.
      api.answer = _actions(allowed: ['waiting', 'resolved']);
      container.invalidate(eeTicketActionsProvider(_ticketId));
      await tester.pumpAndSettle();
      expect(key('ticket-status-confirm'), findsNothing);
      expect(key('ticket-status-closed'), findsNothing);
      expect(key('ticket-status-waiting'), findsOneWidget);
      expect(api.statuses, isEmpty);
    });

    testWidgets('a pending approval is said out loud, not just obeyed', (
      tester,
    ) async {
      api.answer = _actions(approvalPending: true, allowed: ['cancelled']);
      await pumpChips(tester);
      await openStatus(tester);
      expect(key('ticket-approval-pending'), findsOneWidget);
      expect(key('ticket-status-cancelled'), findsOneWidget);
      expect(key('ticket-status-resolved'), findsNothing);

      // And for somebody who may not even cancel, the sheet explains the
      // empty list instead of showing one.
      api.answer = _actions(approvalPending: true, allowed: []);
      container.invalidate(eeTicketActionsProvider(_ticketId));
      await tester.pumpAndSettle();
      expect(key('ticket-status-none'), findsOneWidget);
      expect(key('ticket-approval-pending'), findsOneWidget);
    });

    testWidgets(
      'the clock: a pause asks why, and is offered only when it would stop something',
      (tester) async {
        api.answer = _actions(canPause: true, pausable: true);
        await pumpChips(tester);
        await openStatus(tester);
        expect(key('ticket-sla-pause'), findsOneWidget);
        expect(key('ticket-sla-resume'), findsNothing);

        await tester.tap(key('ticket-sla-pause'));
        await tester.pumpAndSettle();
        expect(find.text('Neden durduruldu?'), findsOneWidget);
        expect(enabled(tester, 'ticket-reason-apply'), isFalse);
        await tester.tap(key('ticket-reason-supplier'));
        await tester.pumpAndSettle();
        await tester.tap(key('ticket-reason-apply'));
        await tester.pumpAndSettle();

        expect(api.pauses, ['supplier']);
        expect(api.statuses, isEmpty, reason: 'the request did not move');
        expect(find.text('Saat durduruldu'), findsOneWidget);
      },
    );

    testWidgets(
      'resume is offered when something holds the clock, and says what',
      (tester) async {
        api.answer = _actions(canPause: true, held: ['spare_part']);
        await pumpChips(tester);
        await openStatus(tester);
        expect(key('ticket-sla-pause'), findsNothing);
        expect(
          find.text('Durduruldu — Yedek parça bekleniyor'),
          findsOneWidget,
        );

        await tester.tap(key('ticket-sla-resume'));
        await tester.pumpAndSettle();
        expect(api.resumes, 1);
      },
    );

    testWidgets('without the verb there is no clock section at all', (
      tester,
    ) async {
      api.answer = _actions(pausable: true, held: ['approval']);
      await pumpChips(tester);
      await openStatus(tester);
      expect(key('ticket-sla-pause'), findsNothing);
      expect(key('ticket-sla-resume'), findsNothing);
    });

    testWidgets("a refusal stays on the sheet, in the server's words", (
      tester,
    ) async {
      api.failWith = const ApiException(
        'TICKET_APPROVAL_PENDING',
        'That request is waiting on an approval',
      );
      await pumpChips(tester);
      await openStatus(tester);
      await tester.tap(key('ticket-status-resolved'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Bu talep bir onay bekliyor; karar verilene kadar yalnız iptal '
          'edilebilir.',
        ),
        findsOneWidget,
      );
      expect(key('ticket-status-resolved'), findsOneWidget, reason: 'open');
    });

    testWidgets('a write that finds no server greys the doors and says why', (
      tester,
    ) async {
      api.failWith = const ApiException('NETWORK_ERROR', 'no route');
      await pumpChips(tester);
      await openStatus(tester);
      await tester.tap(key('ticket-status-resolved'));
      await tester.pumpAndSettle();

      expect(container.read(serverReachabilityProvider), isFalse);
      // The sheet says why in place of the list; the page behind it says the
      // same under its now-grey chips.
      expect(
        tester.widget<Text>(key('ticket-actions-unavailable')).data,
        'Durum, öncelik ve atama bağlantı ister — sunucuya şu an '
        'ulaşılamıyor.',
      );
      expect(key('ticket-actions-offline'), findsOneWidget);
      expect(pressable(tester, 'ticket-status'), isFalse);
    });
  });

  group('offline', () {
    testWidgets(
      'both chips are grey before anybody presses them, with the reason',
      (tester) async {
        container.read(serverReachabilityProvider.notifier).unreachable();
        await pumpChips(tester);

        expect(pressable(tester, 'ticket-status'), isFalse);
        expect(pressable(tester, 'ticket-priority'), isFalse);
        expect(key('ticket-actions-offline'), findsOneWidget);
        await tester.tap(key('ticket-status'), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(key('ticket-status-resolved'), findsNothing);
        expect(api.reads, 0, reason: 'nothing asked of a server that is away');

        // The server answers something else — the doors open again.
        container.read(serverReachabilityProvider.notifier).answered();
        await tester.pumpAndSettle();
        expect(pressable(tester, 'ticket-status'), isTrue);
        expect(pressable(tester, 'ticket-priority'), isTrue);
        expect(key('ticket-actions-offline'), findsNothing);
      },
    );

    testWidgets(
      'unknown is not offline: nothing is greyed before the first answer',
      (tester) async {
        expect(container.read(serverReachabilityProvider), isNull);
        await pumpChips(tester);
        expect(pressable(tester, 'ticket-status'), isTrue);
        expect(key('ticket-actions-offline'), findsNothing);
      },
    );
  });

  group('the entitlement, both ways', () {
    test('without the feature nothing is asked of the server', () async {
      final off = ProviderContainer(
        overrides: [
          eeTicketWriteApiProvider.overrideWithValue(api),
          eeFeatureProvider('teams').overrideWithValue(false),
          ticketProvider(
            _ticketId,
          ).overrideWith((ref) => Stream.value(_ticket())),
        ],
      );
      addTearDown(off.dispose);
      final sub = off.listen(eeTicketActionsProvider(_ticketId), (_, _) {});
      addTearDown(sub.close);
      expect(await off.read(eeTicketActionsProvider(_ticketId).future), isNull);
      expect(await off.read(eePriorityMatrixProvider.future), isNull);
      expect(api.reads, 0);
    });

    test('with it, the answer is the server\'s', () async {
      final sub = container.listen(
        eeTicketActionsProvider(_ticketId),
        (_, _) {},
      );
      addTearDown(sub.close);
      final answer = await container.read(
        eeTicketActionsProvider(_ticketId).future,
      );
      expect(answer?.allowedTransitions, ['waiting', 'resolved', 'cancelled']);
      expect(api.reads, 1);
    });
  });

  test(
    'a pull that moves the request makes the server be asked again',
    () async {
      final rows = StreamController<TicketRecord?>();
      addTearDown(rows.close);
      final live = ProviderContainer(
        overrides: [
          eeTicketWriteApiProvider.overrideWithValue(api),
          eeFeatureProvider('teams').overrideWithValue(true),
          ticketProvider(_ticketId).overrideWith((ref) => rows.stream),
        ],
      );
      addTearDown(live.dispose);
      final sub = live.listen(eeTicketActionsProvider(_ticketId), (_, _) {});
      addTearDown(sub.close);

      rows.add(_ticket());
      await live.read(eeTicketActionsProvider(_ticketId).future);
      await pumpEventQueue();
      expect(api.reads, 1, reason: 'the row arriving is not a move');

      rows.add(_ticket().copyWith(status: 'waiting', revision: 2));
      await pumpEventQueue();
      await live.read(eeTicketActionsProvider(_ticketId).future);
      expect(api.reads, 2);
    },
  );

  group('who is on it', () {
    const me = 'U-BARIS';
    MemberProfile person(String id, String name) => MemberProfile(
      id: 'P-$id',
      workspaceId: 'W1',
      userId: id,
      displayName: name,
      initials: name.substring(0, 2).toUpperCase(),
      colorRgb: '#2563EB',
      revision: 1,
    );
    final roster = [
      person('U-AYLA', 'Ayla Yönetici'),
      person(me, 'Barış Saha'),
      person('U-DENIZ', 'Deniz Koordinatör'),
    ];
    late StreamController<List<Assignee>> onIt;

    Future<void> pumpSection(
      WidgetTester tester, {
      DateTime? terminalAt,
      List<MemberProfile>? people,
    }) async {
      onIt = StreamController<List<Assignee>>.broadcast();
      // Closed without being awaited: `close()`'s future waits for the done
      // event to reach a subscriber the container is still holding, and a
      // teardown that awaits it never finishes (measured — the run hung).
      addTearDown(() {
        onIt.close();
      });
      container.dispose();
      container = ProviderContainer(
        overrides: [
          eeTicketWriteApiProvider.overrideWithValue(api),
          eeFeatureProvider('teams').overrideWithValue(true),
          ticketProvider(_ticketId).overrideWith(
            (ref) => Stream.value(_ticket(terminalAt: terminalAt)),
          ),
          syncEngineProvider.overrideWithValue(null),
          currentUserIdProvider.overrideWithValue(me),
          ticketAssigneesForProvider(
            _ticketId,
          ).overrideWith((ref) => onIt.stream),
          workspaceRosterOfProvider(
            'W1',
          ).overrideWith((ref) => Stream.value(people ?? roster)),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildAwTheme(Brightness.light),
            home: Scaffold(
              body: Column(
                children: [
                  EeTicketAssigneeSection(
                    ticket: _ticket(terminalAt: terminalAt),
                  ),
                  const EeTicketActionsOffline(),
                ],
              ),
            ),
          ),
        ),
      );
      onIt.add(const []);
      await tester.pumpAndSettle();
    }

    Future<void> openSheet(WidgetTester tester) async {
      await tester.tap(key('ticket-assignees-open'));
      await tester.pumpAndSettle();
    }

    CheckboxListTile option(WidgetTester tester, String userId) =>
        tester.widget<CheckboxListTile>(key('assignee-option-$userId'));

    testWidgets(
      "the avatars are the device's copy; the door is for a live request",
      (tester) async {
        await pumpSection(tester);
        expect(find.text('Bu talebi henüz kimse almadı'), findsOneWidget);
        onIt.add(const [Assignee(assignmentId: 'A1', userId: 'U-AYLA')]);
        await tester.pumpAndSettle();
        expect(key('assignee-U-AYLA'), findsOneWidget);
        expect(key('ticket-assignees-open'), findsOneWidget);
        expect(api.reads, 0, reason: 'the avatars ask the server nothing');
      },
    );

    testWidgets('a finished request keeps its avatars and loses the door', (
      tester,
    ) async {
      await pumpSection(tester, terminalAt: DateTime.utc(2026, 9, 21));
      onIt.add(const [Assignee(assignmentId: 'A1', userId: 'U-AYLA')]);
      await tester.pumpAndSettle();
      expect(key('assignee-U-AYLA'), findsOneWidget);
      expect(key('ticket-assignees-open'), findsNothing);
    });

    testWidgets('nobody to pick from: no door (DESIGN §22)', (tester) async {
      await pumpSection(tester, people: const []);
      expect(key('ticket-assignees-open'), findsNothing);
    });

    testWidgets(
      'without the verb only the caller is offered, and the sheet says why',
      (tester) async {
        api.answer = _actions();
        await pumpSection(tester);
        await openSheet(tester);
        expect(key('ticket-assign-self-only'), findsOneWidget);
        expect(key('assignee-option-$me'), findsOneWidget);
        expect(key('assignee-option-U-AYLA'), findsNothing);
        expect(key('assignee-option-U-DENIZ'), findsNothing);

        await tester.tap(key('assignee-option-$me'));
        await tester.pumpAndSettle();
        expect(api.assigned, [me]);
        expect(option(tester, me).value, isTrue);
      },
    );

    testWidgets(
      'with the verb anybody; the switch holds until the pull catches up',
      (tester) async {
        api.answer = _actions(canAssignOthers: true);
        await pumpSection(tester);
        await openSheet(tester);
        expect(key('ticket-assign-self-only'), findsNothing);
        for (final p in roster) {
          expect(key('assignee-option-${p.userId}'), findsOneWidget);
        }

        await tester.tap(key('assignee-option-U-DENIZ'));
        await tester.pumpAndSettle();
        expect(api.assigned, ['U-DENIZ']);
        // The device's copy has not heard yet; the switch says what the server
        // said, not what the stale copy says.
        expect(option(tester, 'U-DENIZ').value, isTrue);

        // Taken off again BEFORE the pull brought the row: the release names
        // the id the server answered with.
        await tester.tap(key('assignee-option-U-DENIZ'));
        await tester.pumpAndSettle();
        expect(api.released, ['A-U-DENIZ']);
        expect(option(tester, 'U-DENIZ').value, isFalse);

        // And once the copy has the row, its own id is the one named.
        onIt.add(const [Assignee(assignmentId: 'A9', userId: 'U-AYLA')]);
        await tester.pumpAndSettle();
        expect(option(tester, 'U-AYLA').value, isTrue);
        await tester.tap(key('assignee-option-U-AYLA'));
        await tester.pumpAndSettle();
        expect(api.released, ['A-U-DENIZ', 'A9']);
      },
    );

    testWidgets(
      'one write at a time: every switch waits for the one in flight',
      (tester) async {
        api.answer = _actions(canAssignOthers: true);
        api.hold = Completer<void>();
        await pumpSection(tester);
        await openSheet(tester);
        await tester.tap(key('assignee-option-U-AYLA'));
        await tester.pump();
        for (final p in roster) {
          expect(option(tester, p.userId).onChanged, isNull, reason: p.userId);
        }
        api.hold!.complete();
        await tester.pumpAndSettle();
        expect(option(tester, 'U-DENIZ').onChanged, isNotNull);
        expect(api.assigned, ['U-AYLA']);
      },
    );

    testWidgets("a refusal stays in the sheet, in the server's words", (
      tester,
    ) async {
      api.answer = _actions(canAssignOthers: true);
      api.failWith = const ApiException(
        'TICKET_TERMINAL',
        'That ticket is closed',
      );
      await pumpSection(tester);
      await openSheet(tester);
      await tester.tap(key('assignee-option-U-AYLA'));
      await tester.pumpAndSettle();
      expect(
        find.text('Bu talep kapandı; artık değiştirilemez.'),
        findsOneWidget,
      );
      expect(option(tester, 'U-AYLA').value, isFalse);
    });

    testWidgets(
      'offline: the door is grey before it is pressed, with the reason',
      (tester) async {
        await pumpSection(tester);
        container.read(serverReachabilityProvider.notifier).unreachable();
        await tester.pumpAndSettle();
        expect(
          tester.widget<IconButton>(key('ticket-assignees-open')).onPressed,
          isNull,
        );
        expect(
          find.text(
            'Durum, öncelik ve atama bağlantı ister — sunucuya şu an '
            'ulaşılamıyor.',
          ),
          findsOneWidget,
        );
      },
    );
  });

  group('the priority sheet', () {
    testWidgets('a desk without the matrix picks the priority itself', (
      tester,
    ) async {
      await pumpChips(tester);
      await openPriority(tester);

      expect(key('ticket-impact'), findsNothing);
      expect(key('ticket-priority-matrix-only'), findsNothing);
      for (final tier in _tiers) {
        expect(key('ticket-priority-$tier'), findsOneWidget);
      }
      await tester.tap(key('ticket-priority-urgent'));
      await tester.pumpAndSettle();
      expect(api.priorities, ['urgent']);
      expect(api.inputs, isEmpty);
      expect(find.text('Öncelik: Acil'), findsOneWidget);
    });

    testWidgets(
      "a matrix desk asks impact × urgency and previews the table's answer",
      (tester) async {
        api.matrix = const EePriorityMatrix(
          cells: _matrixCells,
          customised: true,
        );
        await pumpChips(tester);
        await openPriority(tester);

        // No hand-picked tier without the override verb — and the sheet says so.
        expect(key('ticket-priority-urgent'), findsNothing);
        expect(key('ticket-priority-matrix-only'), findsOneWidget);
        expect(enabled(tester, 'ticket-matrix-apply'), isFalse);

        await tester.tap(find.text('Tüm tesis'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: key('ticket-urgency'),
            matching: find.text('Yüksek'),
          ),
        );
        await tester.pumpAndSettle();
        // The changed cell, not the shipped default's `urgent`.
        expect(find.text('Matrisin vereceği öncelik: Yüksek'), findsOneWidget);

        await tester.tap(key('ticket-matrix-apply'));
        await tester.pumpAndSettle();
        expect(api.inputs, [(impact: 'site', urgency: 'high')]);
        expect(api.priorities, isEmpty, reason: 'the server derives it');
      },
    );

    testWidgets(
      'on a request in the matrix, a hand-picked tier needs the verb',
      (tester) async {
        api.answer = _actions(
          impact: 'unit',
          urgency: 'medium',
          canOverride: true,
        );
        await pumpChips(tester);
        await openPriority(tester);

        expect(key('ticket-impact'), findsOneWidget, reason: 'the matrix too');
        expect(find.text('Elle öncelik — matrisi ezer'), findsOneWidget);
        expect(key('ticket-priority-matrix-only'), findsNothing);
        await tester.tap(key('ticket-priority-urgent'));
        await tester.pumpAndSettle();
        expect(api.priorities, ['urgent']);
      },
    );

    testWidgets('an overridden request can be handed back to the matrix', (
      tester,
    ) async {
      api.answer = _actions(
        priority: 'low',
        impact: 'site',
        urgency: 'medium',
        overridden: true,
      );
      await pumpChips(tester);
      await openPriority(tester);

      expect(key('ticket-priority-overridden'), findsOneWidget);
      expect(find.text('Matrisin değerine dön (Yüksek)'), findsOneWidget);
      await tester.tap(key('ticket-priority-rematrix'));
      await tester.pumpAndSettle();
      // Naming the matrix's own answer — an agreement, which needs no verb.
      expect(api.priorities, ['high']);
    });
  });

  group('on the request', () {
    Future<void> pumpDetail(WidgetTester tester, {DateTime? terminalAt}) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            eeTicketWriteApiProvider.overrideWithValue(api),
            syncEngineProvider.overrideWithValue(null),
            ticketProvider(_ticketId).overrideWith(
              (ref) => Stream.value(_ticket(terminalAt: terminalAt)),
            ),
            ticketCommentsProvider(
              _ticketId,
            ).overrideWith((ref) => Stream.value(const [])),
            targetFilesProvider((
              targetType: 'ticket',
              targetId: _ticketId,
            )).overrideWith((ref) => Stream.value(const [])),
            eeTicketRelationsProvider(
              _ticketId,
            ).overrideWith((ref) async => const EeTicketRelations()),
            // EE-279's section, quiet: this test is about something else.
            eeChangesRaisedFromProvider(
              _ticketId,
            ).overrideWith((ref) async => const []),
            eeKbSuggestionsProvider(
              'Kompresör arızası',
            ).overrideWith((ref) async => const []),
            eeKbOfTicketProvider(
              _ticketId,
            ).overrideWith((ref) async => const []),
            eeWorklogProvider(_ticketId).overrideWith((ref) async => null),
            ticketAssigneesForProvider(
              _ticketId,
            ).overrideWith((ref) => Stream.value(const [])),
            workspaceRosterOfProvider.overrideWith(
              (ref, workspaceId) => Stream.value(const []),
            ),
            canProvider.overrideWith((ref, permission) => false),
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
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('a live request wears the two doors, and asks nothing yet', (
      tester,
    ) async {
      await pumpDetail(tester);
      expect(key('ticket-status'), findsOneWidget);
      expect(key('ticket-priority'), findsOneWidget);
      // The actions are read when a sheet opens, not with every visit.
      expect(api.reads, 0);
    });

    testWidgets('a finished request keeps plain chips — nothing to refuse', (
      tester,
    ) async {
      await pumpDetail(tester, terminalAt: DateTime.utc(2026, 9, 21));
      expect(key('ticket-status'), findsNothing);
      expect(key('ticket-priority'), findsNothing);
      expect(find.text('Kapandı'), findsOneWidget);
    });
  });
}
