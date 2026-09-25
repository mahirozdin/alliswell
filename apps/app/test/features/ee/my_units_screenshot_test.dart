// "Birimlerim" — open requests across every unit a person works in (EE-267,
// AW-E19).
//
// Run locally with:
//
//   flutter test --update-goldens --dart-define=screenshots=true \
//       test/features/ee/my_units_screenshot_test.dart
//
// Inert without the dart-define, like every other shot file here.
//
// WHY THIS SHOT.
//
//   • THE REPORT'S MANAGER, ALL HER UNITS AT ONCE: Bakım and BT on one list,
//     latest promise first — BT's server room and Bakım's compressor broken,
//     BT's VPN about to be, the rest on time or promised nothing — each row
//     naming the unit it lives in, and the top saying what the list is: live,
//     and needing a connection, because the device holds one unit at a time.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/data/unit_tickets_api.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/ui/my_units_screen.dart';
import 'package:alliswell/src/features/ee/unit_tickets_providers.dart';
import 'package:alliswell/src/i18n/i18n.dart';

import '../../design_screenshots_test.dart' show screenshotLocale;
import 'support/shot.dart';

const bool _enabled = bool.fromEnvironment('screenshots');

void main() {
  if (!_enabled) return;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(screenshotLocale('tr'));
  });

  bool tr() => AwI18n.instance.locale.languageCode == 'tr';

  List<Override> overrides() {
    // Deadlines relative to the moment of the shot, with half a minute to
    // spare, so "in 20 min" reads the same however long the run takes.
    final now = DateTime.now();
    DateTime inMinutes(int m) => now.add(Duration(minutes: m, seconds: 30));
    final bakim = tr() ? 'Bakım' : 'Maintenance';
    final bt = tr() ? 'BT' : 'IT';
    EeUnitTicket row(
      String id,
      int number,
      String subject,
      String unit,
      String workspaceId, {
      String? sla,
      DateTime? due,
      String status = 'in_progress',
    }) => EeUnitTicket(
      id: id,
      number: number,
      subject: subject,
      status: status,
      priority: 'high',
      slaStatus: sla,
      slaDueAt: due,
      unitId: 'U-$unit',
      unitName: unit,
      workspaceId: workspaceId,
    );
    const wsBakim = '01WSBAKIMAAAAAAAAAAAAAAAAA';
    const wsBt = '01WSBTAAAAAAAAAAAAAAAAAAAA';
    return [
      eeFeatureProvider.overrideWith((ref, name) => true),
      eeUnitTicketsPageProvider.overrideWith(
        (ref, key) async => EeUnitTicketsPage(
          units: [
            EeUnitScope(unitId: 'U1', unitName: bakim, workspaceId: wsBakim),
            EeUnitScope(unitId: 'U2', unitName: bt, workspaceId: wsBt),
          ],
          breached: 2,
          warned: 1,
          nextCursor: 'more',
          tickets: [
            row(
              '01TSERVERAAAAAAAAAAAAAAAAA',
              214,
              tr()
                  ? 'Sunucu odası sıcaklık alarmı'
                  : 'Server room temperature alarm',
              bt,
              wsBt,
              sla: 'breached',
            ),
            row(
              '01TCOMPRESSORAAAAAAAAAAAAA',
              1042,
              tr() ? 'Kompresör arızası — hat 3' : 'Compressor fault — line 3',
              bakim,
              wsBakim,
              sla: 'breached',
            ),
            row(
              '01TVPNAAAAAAAAAAAAAAAAAAAA',
              219,
              tr() ? 'VPN bağlantısı kopuyor' : 'VPN keeps dropping',
              bt,
              wsBt,
              sla: 'warned',
              due: inMinutes(20),
            ),
            row(
              '01TBELTAAAAAAAAAAAAAAAAAAA',
              1051,
              tr() ? 'Konveyör bandı gıcırdıyor' : 'Conveyor belt squeaks',
              bakim,
              wsBakim,
              sla: 'ok',
              due: inMinutes(300),
            ),
            row(
              '01TLAMPAAAAAAAAAAAAAAAAAAA',
              1057,
              tr() ? 'Atölye lambası' : 'Workshop lamp',
              bakim,
              wsBakim,
              status: 'new',
            ),
          ],
        ),
      ),
    ];
  }

  for (final brightness in Brightness.values) {
    testWidgets('every unit of hers, live (${brightness.name})', (
      tester,
    ) async {
      await eeShoot(
        tester,
        brightness: brightness,
        name: 'ee-my-units',
        size: const Size(900, 1100),
        overrides: overrides(),
        screen: const EeMyUnitsScreen(),
      );
    });
  }
}
