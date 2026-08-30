import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/data/portal_links_models.dart';
import 'package:alliswell/src/features/ee/data/services_models.dart';
import 'package:alliswell/src/features/ee/portal_links_providers.dart';
import 'package:alliswell/src/features/ee/services_providers.dart';
import 'package:alliswell/src/features/ee/ui/portal_links_screen.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';
import 'package:alliswell/src/theme/tokens.dart';

/// EE-106 — the management screen, asserted where it would mislead.
///
/// The sharpest case is the ceiling. `max == null` means the plan has NO
/// limit, and a screen that printed the number would turn "unlimited" into
/// "your ceiling is zero" — the same misreading `limits.js` guards against on
/// the server and the same one EE-102 had to re-prove. It is tested directly.
///
/// The others are the same family: an EXPIRED link is drawn neutral rather
/// than amber, because running out is what a link with an expiry is supposed
/// to do and a warning colour would make the ordinary end of its life look
/// like a fault; a REVOKED link carries no controls at all rather than a menu
/// of things that would every one of them refuse; and the created URL appears
/// in exactly one place and says out loud that it will not appear again.
class _Fixed extends EePortalLinksController {
  _Fixed(this._value);
  final EePortalLinksData? _value;
  @override
  Future<EePortalLinksData?> build() async => _value;
}

class _FixedServices extends EeServicesController {
  _FixedServices(this._value);
  final List<EeService>? _value;
  @override
  Future<List<EeService>?> build() async => _value;
}

final _services = [
  const EeService(id: 'S1', name: 'Elektrik arızası', unitIds: ['U1']),
  const EeService(id: 'S2', name: 'Aydınlatma', unitIds: ['U1', 'U2']),
];

EePortalLink _link({
  String id = 'L1',
  String serviceId = 'S1',
  EePortalLinkState state = EePortalLinkState.active,
  bool enabled = true,
  bool custom = false,
}) => EePortalLink(
  id: id,
  serviceId: serviceId,
  state: state,
  enabled: enabled,
  expiresAt: DateTime(2026, 9, 1, 12),
  hasCustomFields: custom,
);

Future<void> _pump(
  WidgetTester tester,
  EePortalLinksData? value, {
  Brightness brightness = Brightness.light,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        eePortalLinksProvider.overrideWith(() => _Fixed(value)),
        eeServicesProvider.overrideWith(() => _FixedServices(_services)),
      ],
      child: MaterialApp(
        theme: buildAwTheme(brightness),
        home: const EePortalLinksScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('en'));
  });

  group('the ceiling', () {
    testWidgets('AN UNLIMITED PLAN SAYS "unlimited", NOT A NUMBER', (
      tester,
    ) async {
      await _pump(
        tester,
        EePortalLinksData(
          links: [_link()],
          linkQuota: const EePortalQuota(used: 1),
          ticketQuota: const EePortalQuota(used: 4),
        ),
      );
      expect(find.textContaining('unlimited'), findsNWidgets(2));
      // The failure this guards is "1 of 0" — the shape a nullable max takes
      // when somebody reaches for `?? 0`.
      expect(find.textContaining('of 0'), findsNothing);
    });

    testWidgets('a configured ceiling shows what is spent against it', (
      tester,
    ) async {
      await _pump(
        tester,
        EePortalLinksData(
          links: [_link()],
          linkQuota: const EePortalQuota(used: 1, max: 2, remaining: 1),
          ticketQuota: const EePortalQuota(used: 40, max: 100, remaining: 60),
        ),
      );
      expect(find.text('1 of 2'), findsOneWidget);
      expect(find.text('40 of 100'), findsOneWidget);
    });
  });

  group('state is a mark plus a word', () {
    testWidgets('EXPIRED IS NEUTRAL, NOT A WARNING', (tester) async {
      await _pump(
        tester,
        EePortalLinksData(
          links: [_link(state: EePortalLinkState.expired)],
          linkQuota: const EePortalQuota(used: 0),
          ticketQuota: const EePortalQuota(used: 0),
        ),
      );
      final theme = buildAwTheme(Brightness.light);
      final icon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const Key('portal-link-L1')),
          matching: find.byType(Icon),
        ),
      );
      expect(icon.icon, Icons.schedule);
      expect(icon.color, theme.disabledColor);
      // …and the meaning is a word, in body colour.
      expect(find.textContaining('Expired'), findsOneWidget);
    });

    testWidgets('a live link is marked with the success colour', (tester) async {
      await _pump(
        tester,
        EePortalLinksData(
          links: [_link()],
          linkQuota: const EePortalQuota(used: 1),
          ticketQuota: const EePortalQuota(used: 0),
        ),
      );
      final tokens = buildAwTheme(Brightness.light).extension<AwTokens>()!;
      final icon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const Key('portal-link-L1')),
          matching: find.byType(Icon),
        ),
      );
      expect(icon.color, tokens.success);
      expect(find.textContaining('Live'), findsOneWidget);
    });

    testWidgets('A REVOKED LINK CARRIES NO CONTROLS AT ALL', (tester) async {
      await _pump(
        tester,
        EePortalLinksData(
          links: [_link(state: EePortalLinkState.revoked)],
          linkQuota: const EePortalQuota(used: 0),
          ticketQuota: const EePortalQuota(used: 0),
        ),
      );
      // Every action would refuse; offering them would be a menu of dead ends.
      expect(find.byKey(const Key('portal-menu-L1')), findsNothing);
      expect(find.textContaining('Revoked'), findsOneWidget);
    });

    testWidgets('a paused link offers to resume, not to pause again', (
      tester,
    ) async {
      await _pump(
        tester,
        EePortalLinksData(
          links: [_link(state: EePortalLinkState.disabled, enabled: false)],
          linkQuota: const EePortalQuota(used: 0),
          ticketQuota: const EePortalQuota(used: 0),
        ),
      );
      await tester.tap(find.byKey(const Key('portal-menu-L1')));
      await tester.pumpAndSettle();
      expect(find.text('Resume'), findsOneWidget);
      expect(find.text('Pause'), findsNothing);
    });
  });

  group('the model', () {
    test('an unknown state from a newer server reads as shut, not open', () {
      // The safe misreading of "I do not know what this is" on a door to the
      // public is "assume it is closed".
      expect(EePortalLinkState.parse('something_new'), EePortalLinkState.revoked);
      expect(EePortalLinkState.parse(null), EePortalLinkState.revoked);
      expect(EePortalLinkState.parse('active'), EePortalLinkState.active);
    });

    test('a link carries no token field to leak', () {
      final link = EePortalLink.fromJson({
        'id': 'L1',
        'serviceId': 'S1',
        'state': 'active',
        'enabled': true,
        'expiresAt': '2026-09-01T12:00:00.000Z',
        // A server that started sending one anyway would be ignored here: the
        // model has nowhere to put it.
        'url': 'https://team.example.com/p/SECRET',
      });
      expect(link.toString(), isNot(contains('SECRET')));
    });

    test('an unlimited quota is not a zero one', () {
      const quota = EePortalQuota(used: 3);
      expect(quota.isUnlimited, isTrue);
      expect(quota.max, isNull);
    });
  });

  group('the empty and the forbidden', () {
    testWidgets('no links yet is an invitation, not an error', (tester) async {
      await _pump(
        tester,
        const EePortalLinksData(
          links: [],
          linkQuota: EePortalQuota(used: 0),
          ticketQuota: EePortalQuota(used: 0),
        ),
      );
      expect(find.textContaining('No public links yet'), findsOneWidget);
      expect(find.byKey(const Key('portal-create')), findsOneWidget);
    });

    testWidgets('without the verb there is no screen and no create button', (
      tester,
    ) async {
      // `load()` answers null for 403/404 — "not yours" is not an error to put
      // in front of somebody, and a stale link can still land here.
      await _pump(tester, null);
      expect(find.textContaining('Not available'), findsOneWidget);
      expect(find.byKey(const Key('portal-create')), findsNothing);
    });
  });
}
