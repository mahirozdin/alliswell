// The extension's screens at 1440 (OPH-410): the request queue as one line
// per request under named columns, and the workload report as one sortable
// table.
//
// Run locally with:
//
//   flutter test --update-goldens --dart-define=screenshots=true \
//       test/features/ee/wide_screens_screenshot_test.dart
//
// Inert without the dart-define, like every other shot file here. The
// behaviour itself is held by ee_wide_layout_test.dart.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/assignments_providers.dart';
import 'package:alliswell/src/features/ee/data/performance_models.dart';
import 'package:alliswell/src/features/ee/data/unit_tickets_api.dart';
import 'package:alliswell/src/features/ee/performance_providers.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/tickets_providers.dart';
import 'package:alliswell/src/features/ee/ui/performance_screen.dart';
import 'package:alliswell/src/features/ee/ui/ticket_queue_screen.dart';
import 'package:alliswell/src/features/ee/unit_scope_providers.dart';
import 'package:alliswell/src/features/ee/unit_tickets_providers.dart';
import 'package:alliswell/src/features/workspaces/workspaces.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/providers.dart';

import '../../design_screenshots_test.dart' show screenshotLocale;
import 'support/shot.dart';

const bool _enabled = bool.fromEnvironment('screenshots');

/// 1440 × 900 logical at the harness's device pixel ratio of 2.
const Size _desktop = Size(2880, 1800);

const _bakim = WorkspaceSummary(
  id: '01HWS000000000000000BAKIMW',
  name: 'Bakım',
  slug: 'bakim',
  colorRgb: '#16A34A',
  role: 'member',
);

class _Selected extends SelectedWorkspace {
  @override
  String? build() => _bakim.id;
}

class _FakeUnitsApi extends Fake implements EeUnitTicketsApi {
  @override
  Future<EeUnitTicketsPage> list({
    bool alertsOnly = false,
    String? except,
    String? cursor,
    int? limit,
  }) async => EeUnitTicketsPage.fromJson(const {'tickets': []});
}

class _Perf extends EePerformanceController {
  _Perf(this.value);
  final EePerformance value;
  @override
  Future<EePerformance?> build() async => value;
}

bool _tr() => AwI18n.instance.locale.languageCode == 'tr';

TicketRecord _ticket(
  String id,
  int number,
  String subjectTr,
  String subjectEn, {
  String status = 'new',
  String priority = 'normal',
  String? sla,
  Duration due = const Duration(hours: 5),
  DateTime? terminalAt,
}) => TicketRecord(
  id: id,
  workspaceId: _bakim.id,
  number: number,
  subject: _tr() ? subjectTr : subjectEn,
  status: status,
  priority: priority,
  source: 'app',
  requesterId: 'R-$id',
  slaStatus: sla,
  slaDueAt: sla == null ? null : DateTime.now().add(due),
  revision: 1,
  createdAt: DateTime.utc(2026, 11, 1),
  terminalAt: terminalAt,
);

Assignee _person(String id, String name, String initials) => Assignee(
  assignmentId: 'AS-$id',
  userId: id,
  displayName: name,
  initials: initials,
  colorRgb: '#2563EB',
);

EePerformanceRow _row(
  String key,
  String? label, {
  required int opened,
  required double mttr,
  double? compliance,
  int? judged,
  double? csat,
}) => EePerformanceRow.fromJson({
  'key': key,
  'label': label,
  'opened': opened,
  'answered': opened,
  'resolved': opened - 2,
  'backlogDelta': 2,
  'mtta': {'minutes': 18.0, 'measured': opened, 'total': opened},
  'mttr': {'minutes': mttr, 'measured': opened - 2, 'total': opened},
  'csat': {
    'average': csat,
    'answered': csat == null ? 0 : opened ~/ 3,
    'sent': opened ~/ 2,
  },
  'compliance': ?compliance,
  'judged': ?judged,
});

void main() {
  if (!_enabled) return;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(screenshotLocale('tr'));
  });

  List<Override> queue() => [
    eeFeatureProvider.overrideWith((ref, name) => true),
    currentUserIdProvider.overrideWithValue('user-1'),
    workspacesProvider.overrideWith((ref) async => const [_bakim]),
    selectedWorkspaceIdProvider.overrideWith(_Selected.new),
    eeMyUnitsScopeProvider.overrideWith(
      (ref) async => const [
        EeUnitScope(
          unitId: 'U-BAKIM',
          unitName: 'Bakım',
          workspaceId: '01HWS000000000000000BAKIMW',
        ),
      ],
    ),
    eeUnitTicketsApiProvider.overrideWithValue(_FakeUnitsApi()),
    eeCurrentUnitPulledAtProvider.overrideWith((ref) => Stream.value(null)),
    syncEngineProvider.overrideWithValue(null),
    canProvider.overrideWith(
      (ref, permission) => permission == 'tickets.create',
    ),
    ticketQueueProvider.overrideWith(
      (ref) => Stream.value([
        _ticket(
          'T1',
          164,
          'Fırın 2 sıcaklık sensörü hata veriyor',
          'Oven 2 temperature sensor fails',
          priority: 'urgent',
          sla: 'breached',
          due: const Duration(hours: -26),
        ),
        _ticket(
          'T2',
          163,
          'Hat 3 konveyör bandı kayıyor',
          'Line 3 conveyor belt slips',
          status: 'in_progress',
          priority: 'high',
          sla: 'warned',
          due: const Duration(hours: 2),
        ),
        _ticket(
          'T3',
          161,
          'Kompresör yağ değişimi',
          'Compressor oil change',
          sla: 'ok',
          due: const Duration(days: 2, hours: 3),
        ),
        _ticket(
          'T4',
          158,
          'Forklift aküsü şarj tutmuyor',
          'Forklift battery does not hold a charge',
          status: 'waiting',
          priority: 'low',
          sla: 'ok',
          due: const Duration(days: 4),
        ),
        _ticket(
          'T5',
          150,
          'Kalıp presi bakım kaydı',
          'Moulding press service record',
          status: 'resolved',
          sla: 'met',
          terminalAt: DateTime.utc(2026, 11, 5),
        ),
      ]),
    ),
    ticketAssigneesProvider.overrideWith(
      (ref) => Stream.value({
        'T2': [_person('U2', 'Kemal Usta', 'KU')],
        'T3': [_person('U3', 'Ayla Servis', 'AS')],
        'T4': [_person('U2', 'Kemal Usta', 'KU')],
        'T5': [_person('U3', 'Ayla Servis', 'AS')],
      }),
    ),
    eeMemberNamesProvider.overrideWith(
      (ref) => Stream.value(const {
        'R-T1': 'Onur Depo',
        'R-T2': 'Selin Üretim',
        'R-T3': 'Onur Depo',
        'R-T4': 'Murat Lojistik',
        'R-T5': 'Selin Üretim',
      }),
    ),
  ];

  List<Override> performance() => [
    eeFeatureProvider.overrideWith((ref, name) => true),
    eePerformanceProvider.overrideWith(
      () => _Perf(
        EePerformance(
          from: '2026-10-09',
          to: '2026-11-07',
          closedIsNotPerformance: _tr()
              ? 'Kapanan talep sayısı bir performans ölçüsü değildir: zor talepleri alan kişi daha az kapatır.'
              : 'The number of closed requests is not a measure of performance: whoever takes the hard ones closes fewer.',
          processTypes: [
            _row(
              'incident',
              null,
              opened: 58,
              mttr: 330,
              compliance: 81.0,
              judged: 54,
            ),
            _row(
              'request',
              null,
              opened: 96,
              mttr: 1260,
              compliance: 93.2,
              judged: 90,
            ),
          ],
          units: [
            _row(
              'U1',
              _tr() ? 'Bakım' : 'Maintenance',
              opened: 72,
              mttr: 408,
              compliance: 94.1,
              judged: 68,
              csat: 4.6,
            ),
            _row(
              'U2',
              'BT',
              opened: 144,
              mttr: 5587,
              compliance: 51.4,
              judged: 144,
              csat: 3.9,
            ),
            _row(
              'U3',
              _tr() ? 'Lojistik' : 'Logistics',
              opened: 31,
              mttr: 760,
              compliance: 88.0,
              judged: 25,
            ),
          ],
          agents: [
            _row('A1', 'Kerem Bakım', opened: 41, mttr: 380, csat: 4.8),
            _row('A2', 'Ayla Servis', opened: 37, mttr: 445, csat: 4.3),
            _row('A3', 'Kemal Usta', opened: 29, mttr: 1210, csat: 4.1),
          ],
        ),
      ),
    ),
  ];

  for (final brightness in Brightness.values) {
    testWidgets('the queue at 1440 (${brightness.name})', (tester) async {
      await eeShoot(
        tester,
        brightness: brightness,
        name: 'ee-queue-1440',
        size: _desktop,
        overrides: queue(),
        screen: const EeTicketQueueScreen(),
      );
    });

    testWidgets('the workload report at 1440 (${brightness.name})', (
      tester,
    ) async {
      await eeShoot(
        tester,
        brightness: brightness,
        name: 'ee-performance-1440',
        size: _desktop,
        overrides: performance(),
        screen: const EePerformanceScreen(),
        // Sorted by resolution time, to show the arrow.
        afterPump: (tester) async {
          await tester.tap(find.byKey(const Key('perf-sort-byUnit-mttr')));
        },
      );
    });
  }
}
