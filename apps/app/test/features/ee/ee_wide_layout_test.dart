import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/features/ee/assignments_providers.dart';
import 'package:alliswell/src/features/ee/data/performance_models.dart';
import 'package:alliswell/src/features/ee/data/unit_tickets_api.dart';
import 'package:alliswell/src/features/ee/performance_providers.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/tickets_providers.dart';
import 'package:alliswell/src/features/ee/ui/new_problem_screen.dart';
import 'package:alliswell/src/features/ee/ui/performance_screen.dart';
import 'package:alliswell/src/features/ee/ui/ticket_detail_screen.dart';
import 'package:alliswell/src/features/ee/ui/ticket_queue_screen.dart';
import 'package:alliswell/src/features/ee/unit_scope_providers.dart';
import 'package:alliswell/src/features/ee/unit_tickets_providers.dart';
import 'package:alliswell/src/features/workspaces/workspaces.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/providers.dart';
import 'package:alliswell/src/theme/theme.dart';
import 'package:alliswell/src/theme/tokens.dart';
import 'package:alliswell/src/widgets/form_width.dart';

/// OPH-410 — the extension's screens at a desktop width (U-23, U-08's
/// extension half): from 1200 px a request opens in the pane beside its
/// list (OPH-405's pattern), the queue is one aligned line per request, the
/// workload report is one sortable table, and a form stays 720 px wide.
/// Below 1200 every one of them is what it was.
const _bt = WorkspaceSummary(
  id: '01HWS00000000000000000BTWS',
  name: 'BT',
  slug: 'bt',
  colorRgb: '#2563EB',
  role: 'member',
);
const _units = [
  EeUnitScope(
    unitId: 'U-BT',
    unitName: 'BT',
    workspaceId: '01HWS00000000000000000BTWS',
  ),
];
const _requester = '01USREQUESTERAAAAAAAAAAAAA';

const _desktop = Size(1440, 900);
const _laptop = Size(1000, 900);
const _phone = Size(390, 844);

TicketRecord _ticket(String id, int number) => TicketRecord(
  id: id,
  workspaceId: _bt.id,
  number: number,
  subject: 'Yazıcı $id kağıt sıkıştırıyor',
  status: 'new',
  priority: 'high',
  source: 'app',
  requesterId: _requester,
  revision: 1,
  createdAt: DateTime.utc(2026, 11, 1),
);

class _FakeUnitsApi extends Fake implements EeUnitTicketsApi {
  @override
  Future<EeUnitTicketsPage> list({
    bool alertsOnly = false,
    String? except,
    String? cursor,
    int? limit,
  }) async => EeUnitTicketsPage.fromJson(const {'tickets': []});
}

class _Selected extends SelectedWorkspace {
  @override
  String? build() => _bt.id;
}

class _Perf extends EePerformanceController {
  _Perf(this._value);
  final EePerformance? _value;
  @override
  Future<EePerformance?> build() async => _value;
}

EePerformanceRow _row(
  String key,
  String label, {
  required int opened,
  double? mttr,
  double? compliance,
  int? judged,
}) => EePerformanceRow.fromJson({
  'key': key,
  'label': label,
  'opened': opened,
  'answered': opened,
  'resolved': opened - 1,
  'backlogDelta': 1,
  'mtta': {'minutes': 14.0, 'measured': opened, 'total': opened},
  'mttr': {'minutes': mttr, 'measured': opened, 'total': opened},
  'csat': {'average': 4.5, 'answered': 2, 'sent': 4},
  'compliance': ?compliance,
  'judged': ?judged,
});

final _panel = EePerformance(
  from: '2026-10-09',
  to: '2026-11-07',
  closedIsNotPerformance: 'Kapanan talep sayısı performans değildir.',
  units: [
    _row('U1', 'Bakım', opened: 40, mttr: 300, compliance: 92, judged: 38),
    _row('U2', 'BT', opened: 144, mttr: 900, compliance: 51.4, judged: 144),
    _row('U3', 'Arşiv', opened: 3, compliance: 0, judged: 0),
  ],
  agents: const [],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('tr'));
    await localKv.remove('${kEeMyUnitsCachePrefix}user-1');
  });

  void sizeTo(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// The detail in the pane never finishes loading here: what is under test
  /// is where it opens and how it closes, not what it shows.
  final details = <String, StreamController<TicketRecord?>>{};
  tearDown(() async {
    for (final c in details.values) {
      await c.close();
    }
    details.clear();
  });

  List<Override> queueOverrides() => [
    eeFeatureProvider.overrideWith((ref, name) => true),
    currentUserIdProvider.overrideWithValue('user-1'),
    workspacesProvider.overrideWith((ref) async => const [_bt]),
    selectedWorkspaceIdProvider.overrideWith(_Selected.new),
    eeMyUnitsScopeProvider.overrideWith((ref) async => _units),
    eeUnitTicketsApiProvider.overrideWithValue(_FakeUnitsApi()),
    eeCurrentUnitPulledAtProvider.overrideWith((ref) => Stream.value(null)),
    syncEngineProvider.overrideWithValue(null),
    ticketQueueProvider.overrideWith(
      (ref) => Stream.value([
        _ticket('T1', 11),
        _ticket('T2', 12),
        _ticket('T3', 13),
      ]),
    ),
    ticketAssigneesProvider.overrideWith(
      (ref) => Stream.value(const <String, List<Assignee>>{}),
    ),
    eeMemberNamesProvider.overrideWith(
      (ref) => Stream.value(const {_requester: 'Onur Depo'}),
    ),
    canProvider.overrideWith((ref, permission) => false),
    ticketProvider.overrideWith(
      (ref, id) =>
          details.putIfAbsent(id, StreamController<TicketRecord?>.new).stream,
    ),
  ];

  Future<void> pump(
    WidgetTester tester,
    Widget screen, {
    required Size size,
    List<Override> overrides = const [],
  }) async {
    sizeTo(tester, size);
    final container = ProviderContainer(overrides: overrides);
    addTearDown(container.dispose);
    // The app's shell watches the open unit all the time; only the queue
    // is handed the workspaces to watch.
    if (screen is EeTicketQueueScreen) {
      container.listen(currentWorkspaceProvider, (_, _) {});
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: buildAwTheme(Brightness.light), home: screen),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The pane's detail spins; step the clock instead of settling.
  Future<void> step(WidgetTester tester) async {
    for (var i = 0; i < 6; i += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  final pane = find.byKey(const Key('list-detail-pane'));
  String? paneTicket(WidgetTester tester) {
    final found = find.descendant(
      of: pane,
      matching: find.byType(EeTicketDetailScreen),
    );
    if (found.evaluate().isEmpty) return null;
    return tester.widget<EeTicketDetailScreen>(found).ticketId;
  }

  bool rowSelected(WidgetTester tester, String id) =>
      tester
          .getSemantics(find.byKey(Key('ticket-$id')))
          .flagsCollection
          .isSelected ==
      Tristate.isTrue;

  group('the request queue at a desktop width', () {
    testWidgets('one aligned line per request under named columns', (
      tester,
    ) async {
      await pump(
        tester,
        const EeTicketQueueScreen(),
        size: _desktop,
        overrides: queueOverrides(),
      );
      expect(find.byKey(const Key('ticket-dense-header')), findsOneWidget);
      expect(find.text('Açan · Alan'), findsOneWidget);
      for (final id in ['T1', 'T2', 'T3']) {
        // A line, not a card: well under the phone card's ~110.
        expect(
          tester.getSize(find.byKey(Key('ticket-$id'))).height,
          lessThanOrEqualTo(60),
        );
      }
      // The columns line up: every subject starts where the first does.
      final x = tester
          .getTopLeft(find.byKey(const Key('ticket-dense-subject-T1')))
          .dx;
      expect(
        tester.getTopLeft(find.byKey(const Key('ticket-dense-subject-T3'))).dx,
        x,
      );
      expect(find.text('#11'), findsOneWidget);
      expect(find.text('Açan: Onur Depo · Alan: atanmadı'), findsNWidgets(3));
    });

    testWidgets('a request opens in the 480 px pane; the list stays, the row '
        'is marked, ↑/↓ walk the list and Esc closes', (tester) async {
      await pump(
        tester,
        const EeTicketQueueScreen(),
        size: _desktop,
        overrides: queueOverrides(),
      );
      await tester.tap(find.byKey(const Key('ticket-T1')));
      await step(tester);

      expect(pane, findsOneWidget);
      expect(tester.getSize(pane).width, kAwDetailPaneWidth);
      expect(paneTicket(tester), 'T1');
      expect(find.byKey(const Key('ticket-T2')), findsOneWidget);
      expect(rowSelected(tester, 'T1'), isTrue);
      expect(rowSelected(tester, 'T2'), isFalse);
      // The pane sits right of the list, never over it.
      expect(
        tester.getTopRight(find.byKey(const Key('ticket-T1'))).dx,
        lessThanOrEqualTo(tester.getTopLeft(pane).dx),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await step(tester);
      expect(paneTicket(tester), 'T2');
      expect(rowSelected(tester, 'T2'), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await step(tester);
      expect(paneTicket(tester), 'T1');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await step(tester);
      expect(pane, findsNothing);
      expect(find.byKey(const Key('ticket-T1')), findsOneWidget);
    });

    testWidgets('the pane\'s way out is a close button, not a back that '
        'would leave the list', (tester) async {
      await pump(
        tester,
        const EeTicketQueueScreen(),
        size: _desktop,
        overrides: queueOverrides(),
      );
      await tester.tap(find.byKey(const Key('ticket-T2')));
      await step(tester);
      final close = find.descendant(
        of: pane,
        matching: find.byKey(const Key('list-detail-close')),
      );
      expect(close, findsOneWidget);
      expect(
        find.descendant(of: pane, matching: find.byType(BackButton)),
        findsNothing,
      );
      await tester.tap(close);
      await step(tester);
      expect(pane, findsNothing);
      expect(find.byType(EeTicketQueueScreen), findsOneWidget);
    });

    testWidgets('below 1200 the queue keeps its cards and pushes the detail', (
      tester,
    ) async {
      await pump(
        tester,
        const EeTicketQueueScreen(),
        size: _laptop,
        overrides: queueOverrides(),
      );
      expect(find.byKey(const Key('ticket-dense-header')), findsNothing);
      expect(
        tester.getSize(find.byKey(const Key('ticket-T1'))).height,
        greaterThan(60),
      );
      await tester.tap(find.byKey(const Key('ticket-T1')));
      await step(tester);
      expect(pane, findsNothing);
      expect(find.byType(EeTicketDetailScreen), findsOneWidget);
      expect(find.byKey(const Key('list-detail-close')), findsNothing);
    });
  });

  group('the workload report at a desktop width', () {
    List<Override> perf() => [
      eeFeatureProvider.overrideWith((ref, name) => true),
      eePerformanceProvider.overrideWith(() => _Perf(_panel)),
    ];

    List<String> unitOrder(WidgetTester tester) {
      final rows =
          find
              .byWidgetPredicate(
                (w) =>
                    w.key is ValueKey<String> &&
                    (w.key! as ValueKey<String>).value.startsWith('perf-row-U'),
              )
              .evaluate()
              .toList()
            ..sort(
              (a, b) => tester
                  .getTopLeft(find.byWidget(a.widget))
                  .dy
                  .compareTo(tester.getTopLeft(find.byWidget(b.widget)).dy),
            );
      return [
        for (final e in rows)
          (e.widget.key! as ValueKey<String>).value.substring(9),
      ];
    }

    testWidgets('one table, figures right-aligned in their columns', (
      tester,
    ) async {
      await pump(
        tester,
        const EePerformanceScreen(),
        size: _desktop,
        overrides: perf(),
      );
      expect(
        find.byKey(const Key('perf-table-ee.perfPanel.byUnit')),
        findsOneWidget,
      );
      // Every unit's share ends at the same x: one column, not a card each.
      final ends = {
        for (final id in ['U1', 'U2', 'U3'])
          tester.getTopRight(find.byKey(Key('perf-compliance-$id'))).dx,
      };
      expect(ends, hasLength(1));
      // A share of nothing is a dash, and the denominator is beside a share.
      expect(
        find.descendant(
          of: find.byKey(const Key('perf-compliance-U3')),
          matching: find.text('—'),
        ),
        findsOneWidget,
      );
      expect(find.text('144 talepten'), findsOneWidget);
      expect(unitOrder(tester), ['U1', 'U2', 'U3']);
    });

    testWidgets('a header sorts by its column, a second tap the other way; '
        'nothing measured stays last', (tester) async {
      await pump(
        tester,
        const EePerformanceScreen(),
        size: _desktop,
        overrides: perf(),
      );
      await tester.tap(find.byKey(const Key('perf-sort-byUnit-opened')));
      await tester.pumpAndSettle();
      expect(unitOrder(tester), ['U2', 'U1', 'U3']);
      await tester.tap(find.byKey(const Key('perf-sort-byUnit-opened')));
      await tester.pumpAndSettle();
      expect(unitOrder(tester), ['U3', 'U1', 'U2']);

      await tester.tap(find.byKey(const Key('perf-sort-byUnit-mttr')));
      await tester.pumpAndSettle();
      expect(unitOrder(tester), ['U2', 'U1', 'U3']);
      await tester.tap(find.byKey(const Key('perf-sort-byUnit-mttr')));
      await tester.pumpAndSettle();
      expect(unitOrder(tester), ['U1', 'U2', 'U3']);

      await tester.tap(find.byKey(const Key('perf-sort-byUnit-name')));
      await tester.pumpAndSettle();
      expect(unitOrder(tester), ['U3', 'U1', 'U2']);
    });

    testWidgets('a phone keeps a card per row', (tester) async {
      await pump(
        tester,
        const EePerformanceScreen(),
        size: _phone,
        overrides: perf(),
      );
      expect(
        find.byKey(const Key('perf-table-ee.perfPanel.byUnit')),
        findsNothing,
      );
      expect(find.byKey(const Key('perf-row-U1')), findsOneWidget);
    });
  });

  group('form width', () {
    testWidgets('a form is never wider than 720 on a desktop', (tester) async {
      await pump(
        tester,
        const EeNewProblemScreen(),
        size: _desktop,
        overrides: [eeFeatureProvider.overrideWith((ref, name) => true)],
      );
      final title = find.byKey(const Key('problem-new-title'));
      expect(tester.getSize(title).width, lessThanOrEqualTo(kAwFormMaxWidth));
      // Centred in the window.
      final rect = tester.getRect(title);
      expect((rect.center.dx - _desktop.width / 2).abs(), lessThanOrEqualTo(1));
    });

    testWidgets('on a phone the form keeps the whole width', (tester) async {
      sizeTo(tester, _phone);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AwFormWidth(child: SizedBox.expand(key: Key('form'))),
          ),
        ),
      );
      expect(tester.getSize(find.byKey(const Key('form'))).width, 390);
    });
  });
}
