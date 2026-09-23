// Filing a request from the app (EE-225).
//
// Run locally with:
//
//   flutter test --update-goldens --dart-define=screenshots=true \
//       test/features/ee/new_ticket_screenshot_test.dart
//
// Inert without the dart-define, like every other shot file here.
//
// TWO SHOTS, because the screen has two faces and the second is the reason
// it exists:
//
//   • ONLINE, a service picked: its form in force — the questions that
//     service asks, with the one a condition hides still hidden. The picture
//     is of a desk that decided what to ask, not of a free-text box.
//   • OFFLINE, the same form: it says the request will wait on the phone and
//     what a draft can carry, and its button says "save as draft". A form
//     that went grey instead would be the old answer to no signal.
//
// And a THIRD, of where those drafts are afterwards: "my requests" with the
// drafts section above the list — one on the phone, one waiting at the desk
// with the button that names its service, one refused in the server's words,
// one that went through this session — so every state is in one picture.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/reachability.dart';
import 'package:alliswell/src/features/ee/data/my_tickets_api.dart';
import 'package:alliswell/src/features/ee/data/new_ticket_api.dart';
import 'package:alliswell/src/features/ee/my_tickets_providers.dart';
import 'package:alliswell/src/features/ee/new_ticket_providers.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/ticket_drafts_providers.dart';
import 'package:alliswell/src/features/ee/ui/my_tickets_screen.dart';
import 'package:alliswell/src/features/ee/ui/new_ticket_screen.dart';
import 'package:alliswell/src/i18n/i18n.dart';

import '../../design_screenshots_test.dart' show screenshotLocale;
import 'support/shot.dart';

const bool _enabled = bool.fromEnvironment('screenshots');

/// A desk's line-stop service, as its catalogue would carry it. The demo
/// corpus has services but no forms; this one is written in the corpus's
/// voice (the paint shop, the compressor) so the two pictures agree.
EeCatalog _catalog(bool turkish) => EeCatalog(
  categories: [
    EeCatalogCategory(id: 'C1', name: turkish ? 'Arızalar' : 'Faults'),
  ],
  services: [
    EeCatalogService(
      id: 'S1',
      name: turkish ? 'Hat duruşu' : 'Line stop',
      description: turkish
          ? 'Bir hat ya da makine durduysa'
          : 'When a line or a machine has stopped',
      categoryId: 'C1',
      formVersion: 3,
      units: [EeCatalogUnit(id: 'U1', name: turkish ? 'Bakım' : 'Maintenance')],
      fields: [
        EeFormField(
          key: 'line',
          label: turkish ? 'Hangi hat' : 'Which line',
          type: 'select',
          required: true,
          options: turkish
              ? const ['Boyahane', 'Pres 1', 'Pres 2']
              : const ['Paint shop', 'Press 1', 'Press 2'],
        ),
        EeFormField(
          key: 'safety',
          label: turkish
              ? 'İş güvenliği riski var mı'
              : 'Is there a safety risk',
          type: 'checkbox',
          help: turkish
              ? 'Varsa önce vardiya amirine haber ver'
              : 'If so, tell the shift supervisor first',
        ),
        EeFormField(
          key: 'since',
          label: turkish ? 'Ne zamandan beri' : 'Since when',
          type: 'date',
          showIf: EeFormCondition(
            key: 'line',
            equals: turkish ? 'Pres 2' : 'Press 2',
          ),
        ),
      ],
    ),
  ],
);

void main() {
  if (!_enabled) return;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(screenshotLocale('tr'));
  });

  for (final brightness in Brightness.values) {
    for (final offline in [false, true]) {
      final name = offline ? 'ee-new-ticket-offline' : 'ee-new-ticket';
      testWidgets('$name — ${brightness.name}', (tester) async {
        final turkish = AwI18n.instance.locale.languageCode == 'tr';
        await eeShoot(
          tester,
          brightness: brightness,
          name: name,
          size: const Size(900, 1500),
          overrides: <Override>[
            eeCatalogProvider.overrideWith((ref) async => _catalog(turkish)),
            draftWorkspaceIdProvider.overrideWithValue('W-OWN'),
            canProvider.overrideWith(
              (ref, permission) => permission == 'tickets.create',
            ),
            if (offline)
              serverReachabilityProvider.overrideWith(_Unreachable.new),
          ],
          screen: const EeNewTicketScreen(),
          afterPump: (t) async {
            await t.tap(find.byKey(const Key('new-ticket-service')));
            await t.pumpAndSettle();
            await t.tap(find.byKey(const Key('catalog-service-S1')));
            await t.pumpAndSettle();
            await t.enterText(
              find.byKey(const Key('new-ticket-subject')),
              turkish
                  ? 'Boyahanede kompresör basıncı düştü'
                  : 'Compressor pressure dropped in the paint shop',
            );
          },
        );
      });
    }

    testWidgets('ee-my-tickets-drafts — ${brightness.name}', (tester) async {
      final turkish = AwI18n.instance.locale.languageCode == 'tr';
      await eeShoot(
        tester,
        brightness: brightness,
        name: 'ee-my-tickets-drafts',
        size: const Size(900, 1500),
        overrides: <Override>[
          eeCatalogProvider.overrideWith((ref) async => _catalog(turkish)),
          canProvider.overrideWith(
            (ref, permission) => permission == 'tickets.create',
          ),
          draftStatusesProvider.overrideWithValue([
            EeDraftStatus(
              id: 'M1',
              state: EeDraftState.rejected,
              subject: turkish
                  ? 'Pres 2 yağ kaçırıyor'
                  : 'Press 2 is leaking oil',
              errorCode: 'DRAFT_LIMIT_REACHED',
            ),
            EeDraftStatus(
              id: 'D1',
              state: EeDraftState.onDevice,
              subject: turkish
                  ? 'Boyahanede kompresör basıncı düştü'
                  : 'Compressor pressure dropped in the paint shop',
              serviceId: 'S1',
            ),
            EeDraftStatus(
              id: 'D2',
              state: EeDraftState.held,
              subject: turkish
                  ? 'Depo kapısı kapanmıyor'
                  : 'The store room door will not close',
              hold: EeDraftHold.noService,
            ),
            EeDraftStatus(
              id: 'D3',
              state: EeDraftState.sent,
              subject: turkish
                  ? 'Hat 1 konveyör sesi'
                  : 'Noise from the line 1 conveyor',
            ),
          ]),
          eeMyTicketsProvider.overrideWith(
            (ref) async => [
              EeMyTicket(
                id: 'T1',
                subject: turkish
                    ? 'Hat 1 konveyör sesi'
                    : 'Noise from the line 1 conveyor',
                status: 'new',
                priority: 'normal',
                serviceName: turkish ? 'Hat duruşu' : 'Line stop',
                createdAt: DateTime.utc(2026, 9, 24, 7, 40),
              ),
              EeMyTicket(
                id: 'T2',
                subject: turkish
                    ? 'Vardiya odasında ısıtıcı çalışmıyor'
                    : 'The heater in the shift room is off',
                status: 'in_progress',
                priority: 'normal',
                serviceName: turkish ? 'Tesis' : 'Facilities',
                createdAt: DateTime.utc(2026, 9, 23, 14, 5),
              ),
            ],
          ),
        ],
        screen: const EeMyTicketsScreen(),
      );
    });
  }
}

class _Unreachable extends ServerReachability {
  @override
  bool? build() => false;
}
