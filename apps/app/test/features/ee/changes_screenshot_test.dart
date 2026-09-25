// Change management on the phone (EE-269, AW-E09): the list and one change.
//
// Run locally with:
//
//   flutter test --update-goldens --dart-define=screenshots=true \
//       test/features/ee/changes_screenshot_test.dart
//
// Inert without the dart-define, like every other shot file here.
//
// WHY THESE SHOTS.
//
//   • THE LIST, SPLIT BY THE CLOCK: what is coming up (soonest window first),
//     what has no window yet, what is past — each row with its type, its risk
//     (high risk carries an icon, never colour alone) and its status.
//   • THE CHANGE THE BOARD IS SIGNING: the plan, the signature asked of the
//     person holding the phone with its two buttons, and the calendar naming
//     the freeze and the other change on the same service — the report's
//     scenario in one picture.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/changes_providers.dart';
import 'package:alliswell/src/features/ee/data/changes_models.dart';
import 'package:alliswell/src/features/ee/data/services_models.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/services_providers.dart';
import 'package:alliswell/src/features/ee/tickets_providers.dart';
import 'package:alliswell/src/features/ee/ui/change_detail_screen.dart';
import 'package:alliswell/src/features/ee/ui/changes_screen.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/sync/db/database.dart';

import '../../design_screenshots_test.dart' show screenshotLocale;
import 'support/shot.dart';

const bool _enabled = bool.fromEnvironment('screenshots');

const _disk = 'C1';
const _hat3 = 'S1';
const _ticketId = 'T1';

class _Catalogue extends EeServicesController {
  _Catalogue(this.name);
  final String name;

  @override
  Future<List<EeService>?> build() async => [EeService(id: _hat3, name: name)];
}

void main() {
  if (!_enabled) return;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(screenshotLocale('tr'));
  });

  bool tr() => AwI18n.instance.locale.languageCode == 'tr';

  // Fixed instants, so the pictures do not move with the day they are taken.
  final start = DateTime(2026, 9, 26, 14);
  final end = DateTime(2026, 9, 26, 21);

  EeChange change(
    String id,
    String titleTr,
    String titleEn, {
    String type = 'normal',
    String status = 'awaiting_approval',
    String risk = 'medium',
    DateTime? from,
    DateTime? to,
  }) => EeChange(
    id: id,
    workspaceId: 'W1',
    title: tr() ? titleTr : titleEn,
    type: type,
    status: status,
    risk: risk,
    impact: tr()
        ? 'Hat 3 iki saat durur; vardiya amiri önceden bilgilendirilir.'
        : 'Line 3 stops for two hours; the shift lead is told in advance.',
    rollbackPlan: tr()
        ? 'Eski diski geri tak, RAID dizisini yeniden kur, PLC yedeğinden dön.'
        : 'Put the old disk back, rebuild the RAID array, restore the PLC backup.',
    windowStart: from,
    windowEnd: to,
    serviceIds: const [_hat3],
    sourceTicketId: _ticketId,
    fromServer: true,
  );

  List<Override> common() => [
    eeFeatureProvider.overrideWith((ref, name) => true),
    canProvider.overrideWith((ref, id) => true),
    eeServicesProvider.overrideWith(
      () => _Catalogue(tr() ? 'Hat 3 PLC' : 'Line 3 PLC'),
    ),
  ];

  for (final brightness in Brightness.values) {
    testWidgets('the list, split by the clock (${brightness.name})', (
      tester,
    ) async {
      await eeShoot(
        tester,
        brightness: brightness,
        name: 'ee-changes',
        size: const Size(900, 1700),
        overrides: [
          ...common(),
          changeSearchResultsProvider.overrideWith((ref) async => null),
          eeChangeListProvider.overrideWith(
            (ref) => Stream.value(
              EeChangeList(
                ahead: [
                  change(
                    _disk,
                    'Hat 3 sunucu disk değişimi',
                    'Line 3 server disk replacement',
                    risk: 'high',
                    from: start,
                    to: end,
                  ),
                  change(
                    'C2',
                    'Hat 3 PLC yedeği',
                    'Line 3 PLC backup',
                    type: 'standard',
                    status: 'scheduled',
                    risk: 'low',
                    from: start,
                    to: start.add(const Duration(hours: 2)),
                  ),
                ],
                unscheduled: [
                  change(
                    'C3',
                    'WMS etiket yazıcısı sürücüsü',
                    'WMS label printer driver',
                    status: 'draft',
                    risk: 'low',
                  ),
                ],
                past: [
                  change(
                    'C4',
                    'Pres hattı PLC yazılımı',
                    'Press line PLC software',
                    type: 'emergency',
                    status: 'implemented',
                    from: DateTime(2026, 9, 19, 22),
                    to: DateTime(2026, 9, 20, 1),
                  ),
                ],
              ),
            ),
          ),
        ],
        screen: const EeChangesScreen(),
      );
    });

    testWidgets('the change the board is signing (${brightness.name})', (
      tester,
    ) async {
      final disk = change(
        _disk,
        'Hat 3 sunucu disk değişimi',
        'Line 3 server disk replacement',
        risk: 'high',
        from: start,
        to: end,
      );
      await eeShoot(
        tester,
        brightness: brightness,
        name: 'ee-change-detail',
        size: const Size(900, 2600),
        overrides: [
          ...common(),
          eeChangeOnDeviceProvider(
            _disk,
          ).overrideWith((ref) => Stream.value(disk)),
          ticketProvider(_ticketId).overrideWith(
            (ref) => Stream.value(
              TicketRecord(
                id: _ticketId,
                workspaceId: 'W1',
                subject: tr()
                    ? 'Hat 3 sunucusu disk hatası veriyor'
                    : 'Line 3 server reports a disk error',
                number: 1042,
                status: 'in_progress',
                priority: 'high',
                source: 'internal',
                revision: 1,
                createdAt: DateTime.utc(2026, 9, 24),
              ),
            ),
          ),
          eeChangeLiveProvider(_disk).overrideWith(
            (ref) async => EeChangeLive(
              change: disk,
              approvals: [
                EeChangeApproval(
                  id: 'A1',
                  status: 'pending',
                  createdAt: DateTime(2026, 9, 25, 9),
                  canDecide: true,
                  approverRoleKey: 'admin',
                  requestReason: disk.title,
                ),
              ],
              assets: [
                EeChangeAsset(
                  assetId: 'AS1',
                  tag: 'SRV-3',
                  name: tr() ? 'Hat 3 sunucusu' : 'Line 3 server',
                  status: 'in_use',
                  location: tr() ? 'Sunucu odası' : 'Server room',
                ),
              ],
              conflicts: EeChangeConflicts(
                clashes: [
                  EeChangeClash(
                    changeId: 'C2',
                    title: tr() ? 'Hat 3 PLC yedeği' : 'Line 3 PLC backup',
                    status: 'scheduled',
                    windowStart: start,
                    windowEnd: start.add(const Duration(hours: 2)),
                  ),
                ],
                freezes: [
                  EeChangeFreeze(
                    id: 'F1',
                    startsAt: DateTime(2026, 9, 26, 19),
                    endsAt: DateTime(2026, 9, 28, 8),
                    reason: tr() ? 'Yıl sonu sayımı' : 'Year-end stock count',
                  ),
                ],
              ),
            ),
          ),
        ],
        screen: const EeChangeDetailScreen(changeId: _disk),
      );
    });
  }
}
