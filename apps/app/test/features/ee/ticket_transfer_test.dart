import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/api_exception.dart';
import 'package:alliswell/src/core/reachability.dart';
import 'package:alliswell/src/features/ee/data/ticket_links_models.dart';
import 'package:alliswell/src/features/ee/data/ticket_write_api.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/ticket_links_providers.dart';
import 'package:alliswell/src/features/ee/ticket_write_providers.dart';
import 'package:alliswell/src/features/ee/tickets_providers.dart';
import 'package:alliswell/src/features/ee/ui/ticket_actions.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/providers.dart';
import 'package:alliswell/src/sync/sync_engine.dart';
import 'package:alliswell/src/theme/theme.dart';

/// EE-307 — the desk sends a request to another service or unit.
///
/// The server decides who may, where to and what follows (its own suite);
/// these pin what the person sees: the door, the destinations grouped the way
/// the desk thinks of them (by unit), what a move to another unit will do
/// said BEFORE the tap, exactly what is sent, a refusal kept on screen, and
/// the screen left when the request is no longer this person's to see.
const _ticketId = '01TKAAAAAAAAAAAAAAAAAAAAAA';
const _unitA = '01UNAAAAAAAAAAAAAAAAAAAAAA';
const _unitB = '01UNBBBBBBBBBBBBBBBBBBBBBB';

const _targets = [
  EeTransferTarget(
    serviceId: 'S-ELEC',
    serviceName: 'Elektrik arızası',
    unitId: _unitA,
    unitName: 'Bakım',
    current: true,
  ),
  EeTransferTarget(
    serviceId: 'S-PRES',
    serviceName: 'Pres bakımı',
    unitId: _unitA,
    unitName: 'Bakım',
  ),
  EeTransferTarget(
    serviceId: 'S-IT',
    serviceName: 'Yazılım sorunu',
    unitId: _unitB,
    unitName: 'Bilgi İşlem',
  ),
];

class _FakeWriteApi extends Fake implements EeTicketWriteApi {
  EeTicketActions? answer = const EeTicketActions(
    status: 'in_progress',
    priority: 'normal',
    canTransfer: true,
  );
  List<EeTransferTarget> targets = _targets;
  EeTransferResult result = const EeTransferResult(
    changed: true,
    moved: true,
    stillDesk: false,
    serviceName: 'Yazılım sorunu',
    unitName: 'Bilgi İşlem',
  );
  Object? failWith;
  final sent = <Map<String, Object?>>[];
  int targetReads = 0;

  @override
  Future<EeTicketActions?> actions(String ticketId) async => answer;

  @override
  Future<List<EeTransferTarget>> transferTargets(String ticketId) async {
    targetReads++;
    return targets;
  }

  @override
  Future<EeTransferResult> transfer(
    String ticketId, {
    required String serviceId,
    String? unitId,
    String? reason,
  }) async {
    if (failWith != null) throw failWith!;
    sent.add({'serviceId': serviceId, 'unitId': unitId, 'reason': reason});
    return result;
  }
}

class _CountingEngine extends Fake implements SyncEngine {
  int syncs = 0;

  @override
  Future<bool> syncNow() async {
    syncs++;
    return true;
  }
}

TicketRecord _ticket() => TicketRecord(
  id: _ticketId,
  workspaceId: 'W1',
  subject: 'Muhasebe programı açılmıyor',
  status: 'in_progress',
  priority: 'normal',
  source: 'app',
  revision: 1,
  createdAt: DateTime.utc(2026, 10, 1),
);

void main() {
  late _FakeWriteApi api;
  late _CountingEngine engineA;
  late _CountingEngine engineB;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('en'));
    api = _FakeWriteApi();
    engineA = _CountingEngine();
    engineB = _CountingEngine();
  });

  /// A detail-like host: a pushed route holding the chip, so "leave the
  /// screen" has somewhere to go back to.
  Future<void> pump(
    WidgetTester tester, {
    bool offline = false,
    Brightness brightness = Brightness.light,
  }) async {
    final container = ProviderContainer(
      overrides: [
        eeTicketWriteApiProvider.overrideWithValue(api),
        eeFeatureProvider('teams').overrideWithValue(true),
        ticketProvider(
          _ticketId,
        ).overrideWith((ref) => Stream.value(_ticket())),
        eeTicketRelationsProvider(
          _ticketId,
        ).overrideWith((ref) async => const EeTicketRelations()),
        syncEnginesProvider.overrideWithValue({'A': engineA, 'B': engineB}),
        if (offline)
          serverReachabilityProvider.overrideWith(_DownReachability.new),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAwTheme(brightness),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  key: const Key('open-detail'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                        appBar: AppBar(title: const Text('detail')),
                        body: Column(
                          children: [EeTicketTransferAction(ticket: _ticket())],
                        ),
                      ),
                    ),
                  ),
                  child: const Text('queue'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open-detail')));
    await tester.pumpAndSettle();
  }

  Finder key(String k) => find.byKey(Key(k));

  /// The sheet scrolls; a control below the fold is brought into view first.
  Future<void> tapIn(WidgetTester tester, String k) async {
    await tester.ensureVisible(key(k));
    await tester.pumpAndSettle();
    await tester.tap(key(k));
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(key('ticket-transfer'));
    await tester.pumpAndSettle();
  }

  testWidgets('offline the door is grey and asks nothing', (tester) async {
    await pump(tester, offline: true);
    expect(tester.widget<ActionChip>(key('ticket-transfer')).onPressed, isNull);
    expect(api.targetReads, 0);
  });

  testWidgets(
    'the destinations, grouped by unit; where it is now cannot be picked',
    (tester) async {
      await pump(tester);
      expect(api.targetReads, 0, reason: 'read when the sheet opens');
      await open(tester);
      expect(api.targetReads, 1);

      expect(key('ticket-transfer-unit-$_unitA'), findsOneWidget);
      expect(key('ticket-transfer-unit-$_unitB'), findsOneWidget);
      expect(find.text('Now: Bakım · Elektrik arızası'), findsOneWidget);
      final current = tester.widget<RadioListTile<EeTransferTarget>>(
        key('ticket-transfer-$_unitA-S-ELEC'),
      );
      expect(current.enabled, isFalse);
      expect(key('ticket-transfer-current'), findsOneWidget);
      // Nothing picked, nothing to send.
      expect(
        tester
            .widget<ButtonStyleButton>(key('ticket-transfer-apply'))
            .onPressed,
        isNull,
      );

      // The search narrows by service or unit, folded.
      await tester.enterText(key('ticket-transfer-search'), 'bilgi islem');
      await tester.pumpAndSettle();
      expect(key('ticket-transfer-$_unitA-S-PRES'), findsNothing);
      expect(key('ticket-transfer-$_unitB-S-IT'), findsOneWidget);
    },
  );

  testWidgets(
    'another unit is explained before the tap; the same desk is not',
    (tester) async {
      await pump(tester);
      await open(tester);

      await tester.tap(key('ticket-transfer-$_unitA-S-PRES'));
      await tester.pumpAndSettle();
      expect(key('ticket-transfer-same-unit'), findsOneWidget);
      expect(key('ticket-transfer-cross-unit'), findsNothing);

      await tester.tap(key('ticket-transfer-$_unitB-S-IT'));
      await tester.pumpAndSettle();
      expect(key('ticket-transfer-cross-unit'), findsOneWidget);
      expect(find.textContaining('Bilgi İşlem receives it'), findsOneWidget);
    },
  );

  testWidgets(
    'what is sent is the pick and the reason; a request that left the desk leaves the screen',
    (tester) async {
      await pump(tester);
      await open(tester);
      await tester.tap(key('ticket-transfer-$_unitB-S-IT'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(key('ticket-transfer-reason'));
      await tester.enterText(key('ticket-transfer-reason'), '  yazılım işi  ');
      await tapIn(tester, 'ticket-transfer-apply');

      expect(api.sent, [
        {'serviceId': 'S-IT', 'unitId': _unitB, 'reason': 'yazılım işi'},
      ]);
      // Both units' engines catch up: the request left one, joined the other.
      expect(engineA.syncs, 1);
      expect(engineB.syncs, 1);
      // stillDesk: false — back on the queue, with the sentence.
      expect(key('ticket-transfer'), findsNothing);
      expect(find.text('queue'), findsOneWidget);
      expect(
        find.text('Transferred to Bilgi İşlem · Yazılım sorunu'),
        findsOneWidget,
      );
    },
  );

  testWidgets('still on the desk: the screen stays, the sentence says where', (
    tester,
  ) async {
    api.result = const EeTransferResult(
      changed: true,
      moved: false,
      stillDesk: true,
      serviceName: 'Pres bakımı',
      unitName: 'Bakım',
    );
    await pump(tester);
    await open(tester);
    await tester.tap(key('ticket-transfer-$_unitA-S-PRES'));
    await tester.pumpAndSettle();
    await tapIn(tester, 'ticket-transfer-apply');

    expect(
      api.sent.single['reason'],
      isNull,
      reason: 'an empty reason is none',
    );
    expect(key('ticket-transfer'), findsOneWidget);
    expect(find.text('Transferred to Bakım · Pres bakımı'), findsOneWidget);
  });

  testWidgets('a refusal stays in the sheet, in words', (tester) async {
    api.failWith = const ApiException(
      'TICKET_APPROVAL_PENDING',
      'That request is waiting on an approval',
      statusCode: 409,
    );
    await pump(tester);
    await open(tester);
    await tester.tap(key('ticket-transfer-$_unitB-S-IT'));
    await tester.pumpAndSettle();
    await tapIn(tester, 'ticket-transfer-apply');

    expect(key('ticket-transfer-error'), findsOneWidget);
    expect(find.textContaining('waiting on an approval'), findsOneWidget);
    expect(key('ticket-transfer-apply'), findsOneWidget, reason: 'still open');
  });

  testWidgets('a role without the verb is told so, and offered nothing', (
    tester,
  ) async {
    api.answer = const EeTicketActions(
      status: 'in_progress',
      priority: 'normal',
    );
    await pump(tester);
    await open(tester);
    expect(key('ticket-transfer-unavailable'), findsOneWidget);
    expect(key('ticket-transfer-apply'), findsNothing);
  });

  testWidgets('in Turkish the sheet speaks Turkish', (tester) async {
    AwI18n.instance.setActiveCached(const Locale('tr'));
    await pump(tester);
    expect(find.text('Aktar'), findsOneWidget);
    await open(tester);
    expect(find.text('Talebi aktar'), findsOneWidget);
    expect(find.text('Şu anki'), findsOneWidget);
    await tester.tap(key('ticket-transfer-$_unitB-S-IT'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Talebi Bilgi İşlem alır'), findsOneWidget);
  });
}

class _DownReachability extends ServerReachability {
  @override
  bool? build() => false;
}
