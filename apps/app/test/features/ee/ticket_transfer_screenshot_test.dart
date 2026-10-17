// The desk sends a request to another service or unit (EE-307).
//
// Run locally with:
//
//   flutter test --update-goldens --dart-define=screenshots=true \
//       test/features/ee/ticket_transfer_screenshot_test.dart
//
// Inert without the dart-define, like every other shot file here; what the
// screen DOES is asserted in `ticket_transfer_test.dart`.
//
// WHAT THE PICTURES ARE FOR. The sheet's argument is made before the tap:
// the destinations grouped by the unit that answers them, where the request
// is now shown and not pickable, and — once another unit is picked — the
// sentence saying what that will do (people taken off, the new desk told,
// the SLA still counting from when the request was opened). Light and dark,
// a phone and a desktop width, and Turkish once for label overflow. The
// history row closes the loop: from where, to where, and only THAT a reason
// was written.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/assignments_providers.dart';
import 'package:alliswell/src/features/ee/changes_providers.dart';
import 'package:alliswell/src/features/ee/data/history_models.dart';
import 'package:alliswell/src/features/ee/data/ticket_links_models.dart';
import 'package:alliswell/src/features/ee/data/ticket_write_api.dart';
import 'package:alliswell/src/features/ee/history_providers.dart';
import 'package:alliswell/src/features/ee/kb_providers.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/ticket_links_providers.dart';
import 'package:alliswell/src/features/ee/ticket_write_providers.dart';
import 'package:alliswell/src/features/ee/tickets_providers.dart';
import 'package:alliswell/src/features/ee/ui/ticket_detail_screen.dart';
import 'package:alliswell/src/features/ee/worklog_providers.dart';
import 'package:alliswell/src/features/files/providers.dart';
import 'package:alliswell/src/features/workspaces/workspaces.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/providers.dart';

import 'support/shot.dart';

const bool _enabled = bool.fromEnvironment('screenshots');

const _ticketId = '01TKSHOTAAAAAAAAAAAAAAAAAA';
const _maint = '01UNMAINTAAAAAAAAAAAAAAAAA';
const _it = '01UNITAAAAAAAAAAAAAAAAAAAA';
const _facilities = '01UNFACAAAAAAAAAAAAAAAAAAA';

bool get _tr => AwI18n.instance.locale.languageCode == 'tr';

List<EeTransferTarget> _targets() => [
  EeTransferTarget(
    serviceId: 'S1',
    serviceName: _tr ? 'Elektrik arızası' : 'Electrical fault',
    unitId: _maint,
    unitName: _tr ? 'Bakım' : 'Maintenance',
    current: true,
  ),
  EeTransferTarget(
    serviceId: 'S2',
    serviceName: _tr ? 'Pres bakımı' : 'Press servicing',
    unitId: _maint,
    unitName: _tr ? 'Bakım' : 'Maintenance',
  ),
  EeTransferTarget(
    serviceId: 'S3',
    serviceName: _tr ? 'Bilgisayar arızası' : 'Computer fault',
    unitId: _it,
    unitName: _tr ? 'Bilgi İşlem' : 'IT',
  ),
  EeTransferTarget(
    serviceId: 'S4',
    serviceName: _tr ? 'Yazılım sorunu' : 'Software problem',
    unitId: _it,
    unitName: _tr ? 'Bilgi İşlem' : 'IT',
  ),
  EeTransferTarget(
    serviceId: 'S5',
    serviceName: _tr ? 'Klima ve ısıtma' : 'Heating and cooling',
    unitId: _facilities,
    unitName: _tr ? 'İdari İşler' : 'Facilities',
  ),
];

class _ShotApi extends Fake implements EeTicketWriteApi {
  @override
  Future<EeTicketActions?> actions(String ticketId) async =>
      const EeTicketActions(
        status: 'in_progress',
        priority: 'high',
        canTransfer: true,
      );

  @override
  Future<List<EeTransferTarget>> transferTargets(String ticketId) async =>
      _targets();
}

TicketRecord _ticket() => TicketRecord(
  id: _ticketId,
  workspaceId: 'W1',
  number: 1042,
  subject: _tr
      ? 'Muhasebe programı açılışta donuyor'
      : 'The accounting program freezes on start',
  status: 'in_progress',
  priority: 'high',
  source: 'app',
  revision: 1,
  createdAt: DateTime.utc(2026, 10, 14, 8, 10),
);

List<Override> _overrides({List<EeHistoryEvent> history = const []}) {
  final ticket = _ticket();
  return [
    ticketProvider(_ticketId).overrideWith((ref) => Stream.value(ticket)),
    ticketCommentsProvider(_ticketId).overrideWith(
      (ref) => Stream.value([
        TicketCommentRecord(
          id: '01CMSHOTAAAAAAAAAAAAAAAAAA',
          workspaceId: 'W1',
          ticketId: _ticketId,
          body: _tr
              ? 'Ekran açılır açılmaz donuyor, yeniden başlatmak da işe yaramadı.'
              : 'It freezes as soon as it opens; restarting did not help.',
          internal: false,
          revision: 1,
          createdAt: DateTime.utc(2026, 10, 14, 8, 12),
        ),
      ]),
    ),
    targetFilesProvider.overrideWith((ref, target) => Stream.value(const [])),
    eeTicketExternalFilesProvider.overrideWith(
      (ref, id) async => EeExternalFiles.none,
    ),
    eeTicketRelationsProvider.overrideWith(
      (ref, id) async => const EeTicketRelations(),
    ),
    eeChangesRaisedFromProvider.overrideWith((ref, id) async => const []),
    eeKbSuggestionsProvider.overrideWith((ref, subject) async => const []),
    eeKbOfTicketProvider.overrideWith((ref, id) async => const []),
    eeWorklogProvider.overrideWith((ref, id) async => null),
    ticketAssigneesForProvider(
      _ticketId,
    ).overrideWith((ref) => Stream.value(const [])),
    workspaceRosterOfProvider.overrideWith(
      (ref, workspaceId) => Stream.value(const []),
    ),
    eeMemberNamesProvider.overrideWith((ref) => Stream.value(const {})),
    currentUserIdProvider.overrideWithValue('01USDESKAAAAAAAAAAAAAAAAAA'),
    canProvider.overrideWith((ref, verb) => false),
    eeFeatureProvider.overrideWith((ref, feature) => true),
    eeTicketWriteApiProvider.overrideWithValue(_ShotApi()),
    syncEngineProvider.overrideWithValue(null),
    eeHistoryProvider.overrideWith(
      (ref, target) async => EeHistoryPage(items: history),
    ),
  ];
}

/// The sheet, opened, with another unit picked and a reason typed.
Future<void> _openAndPick(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('ticket-transfer')));
  await tester.pumpAndSettle();
  final pick = find.byKey(const Key('ticket-transfer-$_it-S4'));
  await tester.ensureVisible(pick);
  await tester.pumpAndSettle();
  await tester.tap(pick);
  await tester.pumpAndSettle();
  final reason = find.byKey(const Key('ticket-transfer-reason'));
  await tester.ensureVisible(reason);
  await tester.enterText(
    reason,
    _tr
        ? 'Donanım sağlam; açılışta lisans sunucusuna bağlanamıyor.'
        : 'The hardware is fine; it cannot reach the licence server on start.',
  );
  await tester.pumpAndSettle();
  final apply = find.byKey(const Key('ticket-transfer-apply'));
  await tester.ensureVisible(apply);
  await tester.pumpAndSettle();
}

EeHistoryEvent _event(
  String id,
  String verb,
  Map<String, dynamic>? diff,
  int minute,
) => EeHistoryEvent(
  id: id,
  occurredAt: DateTime.utc(2026, 10, 14, 9, minute),
  actor: 'user',
  verb: verb,
  entityType: 'ee_ticket',
  entityId: _ticketId,
  actorName: 'Barış Demir',
  actorInitials: 'BD',
  actorColorRgb: '#2563EB',
  diff: diff,
);

List<EeHistoryEvent> _history() => [
  _event('01EVSHOT00000000000000000C', 'transferred', {
    'service': [
      _tr ? 'Elektrik arızası' : 'Electrical fault',
      _tr ? 'Yazılım sorunu' : 'Software problem',
    ],
    'unit': [_tr ? 'Bakım' : 'Maintenance', _tr ? 'Bilgi İşlem' : 'IT'],
    'released': 1,
    'reasonCommentId': [null, '01CMREASONAAAAAAAAAAAAAAAA'],
  }, 30),
  _event('01EVSHOT00000000000000000B', 'released', {
    'assignee': ['01USAAAAAAAAAAAAAAAAAAAAAA', null],
    'reason': [null, 'transferred'],
  }, 30),
  _event('01EVSHOT00000000000000000A', 'created', null, 10),
];

void main() {
  if (!_enabled) return;

  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final brightness in Brightness.values) {
    testWidgets('the transfer door on a request — ${brightness.name}', (
      tester,
    ) async {
      AwI18n.instance.setActiveCached(const Locale('en'));
      await eeShoot(
        tester,
        brightness: brightness,
        name: 'ee-ticket-transfer-door',
        size: const Size(900, 900),
        overrides: _overrides(),
        screen: const EeTicketDetailScreen(ticketId: _ticketId),
      );
    });

    testWidgets(
      'the transfer sheet, another unit picked — ${brightness.name}',
      (tester) async {
        AwI18n.instance.setActiveCached(const Locale('en'));
        await eeShoot(
          tester,
          brightness: brightness,
          name: 'ee-ticket-transfer',
          size: const Size(900, 1700),
          overrides: _overrides(),
          screen: const EeTicketDetailScreen(ticketId: _ticketId),
          afterPump: _openAndPick,
        );
      },
    );

    testWidgets('the transfer sheet at desktop width — ${brightness.name}', (
      tester,
    ) async {
      AwI18n.instance.setActiveCached(const Locale('en'));
      await eeShoot(
        tester,
        brightness: brightness,
        name: 'ee-ticket-transfer-wide',
        size: const Size(2400, 1600),
        overrides: _overrides(),
        screen: const EeTicketDetailScreen(ticketId: _ticketId),
        afterPump: _openAndPick,
      );
    });

    testWidgets('the transfer in the history — ${brightness.name}', (
      tester,
    ) async {
      AwI18n.instance.setActiveCached(const Locale('en'));
      await eeShoot(
        tester,
        brightness: brightness,
        name: 'ee-ticket-transfer-history',
        size: const Size(900, 900),
        overrides: _overrides(history: _history()),
        screen: const EeTicketDetailScreen(ticketId: _ticketId),
        afterPump: (t) async {
          await t.tap(find.text('ee.tickets.tabHistory'.tr()));
          await t.pumpAndSettle();
        },
      );
    });
  }

  testWidgets('the transfer sheet in Turkish — light', (tester) async {
    AwI18n.instance.setActiveCached(const Locale('tr'));
    await eeShoot(
      tester,
      brightness: Brightness.light,
      name: 'ee-ticket-transfer',
      size: const Size(900, 1700),
      overrides: _overrides(),
      screen: const EeTicketDetailScreen(ticketId: _ticketId),
      afterPump: _openAndPick,
    );
  });
}
