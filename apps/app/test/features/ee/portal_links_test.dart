import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alliswell/src/features/quick_access/ui/bubble_physics.dart';
import 'package:alliswell/src/widgets/fab_clearance.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/data/portal_links_models.dart';
import 'package:alliswell/src/features/ee/data/services_models.dart';
import 'package:alliswell/src/features/ee/portal_links_providers.dart';
import 'package:alliswell/src/features/ee/services_providers.dart';
import 'package:alliswell/src/features/ee/ui/portal_links_screen.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';
import 'package:alliswell/src/theme/tokens.dart';
import 'package:alliswell/src/features/ee/providers.dart';

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
  final calls = <String>[];
  @override
  Future<EePortalLinksData?> build() async => _value;

  @override
  Future<void> extend(String id, int ttlHours) async =>
      calls.add('extend $id $ttlHours');

  @override
  Future<void> revoke(String id) async => calls.add('revoke $id');

  @override
  Future<EePortalLinkCreated> create({
    String? serviceId,
    List<String>? serviceIds,
    String? unitId,
    int? ttlHours,
  }) async {
    calls.add('create $serviceId $ttlHours');
    return EePortalLinkCreated(
      link: _link(),
      url: 'https://team.example.com/p/TOKEN',
    );
  }
}

late _Fixed _controller;

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
  double bubbleClearance = 0,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        eePortalLinksProvider.overrideWith(() => _controller = _Fixed(value)),
        eeServicesProvider.overrideWith(() => _FixedServices(_services)),
        // OPH-356: the create button waits for a yes.
        canProvider.overrideWith((ref, id) => true),
      ],
      child: AwBubbleClearance(
        extent: bubbleClearance,
        child: MaterialApp(
          theme: buildAwTheme(brightness),
          home: const EePortalLinksScreen(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Text inside ONE tile.
///
/// The quota card above the list says "Live links", so an unscoped
/// `textContaining('Live')` matches twice — which is how CI found this. A
/// state word is a claim about a ROW, so the finder is scoped to the row.
Finder _inTile(String id, String text) => find.descendant(
  of: find.byKey(Key('portal-link-$id')),
  matching: find.textContaining(text),
);

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
      final icon = tester.widget<Icon>(find.byKey(const Key('portal-mark-L1')));
      expect(icon.icon, Icons.schedule);
      expect(icon.color, theme.disabledColor);
      // …and the meaning is a word, in body colour.
      expect(_inTile('L1', 'Expired'), findsOneWidget);
    });

    testWidgets('a live link is marked with the success colour', (
      tester,
    ) async {
      await _pump(
        tester,
        EePortalLinksData(
          links: [_link()],
          linkQuota: const EePortalQuota(used: 1),
          ticketQuota: const EePortalQuota(used: 0),
        ),
      );
      final tokens = buildAwTheme(Brightness.light).extension<AwTokens>()!;
      final icon = tester.widget<Icon>(find.byKey(const Key('portal-mark-L1')));
      expect(icon.color, tokens.success);
      expect(_inTile('L1', 'Live'), findsOneWidget);
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
      expect(_inTile('L1', 'Revoked'), findsOneWidget);
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
      expect(
        EePortalLinkState.parse('something_new'),
        EePortalLinkState.revoked,
      );
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

  // EE-260 — whether files through these doors are virus-scanned, said
  // beside the doors, to the person who opens them.
  group('scanning', () {
    testWidgets(
      'AW-E12: when files through these links are not scanned, the screen that opens them says so',
      (tester) async {
        await _pump(
          tester,
          EePortalLinksData(
            links: [_link()],
            linkQuota: const EePortalQuota(used: 1),
            ticketQuota: const EePortalQuota(used: 0),
            attachmentScanOn: false,
          ),
        );
        final card = find.byKey(const Key('portal-scan-off'));
        expect(card, findsOneWidget);
        expect(
          find.descendant(
            of: card,
            matching: find.textContaining('not virus-scanned'),
          ),
          findsOneWidget,
        );
        // The mark carries the warning colour; the words stay body text.
        final theme = buildAwTheme(Brightness.light);
        final icon = tester.widget<Icon>(
          find.descendant(of: card, matching: find.byType(Icon)),
        );
        expect(icon.color, theme.extension<AwTokens>()!.warning);
        for (final text in tester.widgetList<Text>(
          find.descendant(of: card, matching: find.byType(Text)),
        )) {
          expect(
            text.style?.color,
            isNot(theme.extension<AwTokens>()!.warning),
          );
        }
      },
    );

    testWidgets('a server that scans shows no card', (tester) async {
      await _pump(
        tester,
        EePortalLinksData(
          links: [_link()],
          linkQuota: const EePortalQuota(used: 1),
          ticketQuota: const EePortalQuota(used: 0),
        ),
      );
      expect(find.byKey(const Key('portal-scan-off')), findsNothing);
    });

    test(
      'only an explicit "on" counts — a server that says nothing does not scan',
      () {
        EePortalLinksData read(Map<String, dynamic> extra) =>
            EePortalLinksData.fromJson({'links': const [], ...extra});
        expect(read({'attachmentScan': 'on'}).attachmentScanOn, isTrue);
        expect(read({'attachmentScan': 'off'}).attachmentScanOn, isFalse);
        expect(read({}).attachmentScanOn, isFalse);
      },
    );
  });

  group('UI-AUDIT OPH-360', () {
    EePortalLinksData one(EePortalLink link) => EePortalLinksData(
      links: [link],
      linkQuota: const EePortalQuota(used: 1),
      ticketQuota: const EePortalQuota(used: 0),
    );

    testWidgets(
      'UI-AUDIT #13: extend asks how long, shows the end it adds to, and never sends a fixed 48',
      (tester) async {
        final end = DateTime.now().add(const Duration(days: 30));
        await _pump(
          tester,
          one(
            EePortalLink(
              id: 'L1',
              serviceId: 'S1',
              state: EePortalLinkState.active,
              enabled: true,
              expiresAt: end,
            ),
          ),
        );
        await tester.tap(find.byKey(const Key('portal-menu-L1')));
        await tester.pumpAndSettle();
        expect(find.textContaining('48'), findsNothing);
        await tester.tap(find.text('Extend…'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('portal-extend-dialog')), findsOneWidget);
        // Nothing has been sent yet: extending is a decision now.
        expect(_controller.calls, isEmpty);
        final l10n = MaterialLocalizations.of(
          tester.element(find.byKey(const Key('portal-extend-dialog'))),
        );
        // The new end is counted from the present end, as the server does.
        expect(
          find.textContaining(
            l10n.formatShortDate(end.add(const Duration(days: 7))),
          ),
          findsOneWidget,
        );
        for (final label in ['1 day', '2 days', '7 days', '30 days']) {
          expect(find.text(label), findsOneWidget);
        }
        await tester.tap(find.byKey(const Key('portal-extend-7')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('portal-extend-confirm')));
        await tester.pumpAndSettle();
        expect(_controller.calls, ['extend L1 168']);
      },
    );

    testWidgets(
      'UI-AUDIT #13: walking away from the extend dialog sends nothing',
      (tester) async {
        await _pump(tester, one(_link()));
        await tester.tap(find.byKey(const Key('portal-menu-L1')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Extend…'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Keep it'));
        await tester.pumpAndSettle();
        expect(_controller.calls, isEmpty);
      },
    );

    testWidgets(
      'UI-AUDIT #68: validity is offered in days, never "720 hours"',
      (tester) async {
        await _pump(tester, one(_link()));
        await tester.tap(find.byKey(const Key('portal-create')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('portal-ttl')));
        await tester.pumpAndSettle();
        expect(find.textContaining('hours'), findsNothing);
        expect(find.text('30 days'), findsWidgets);
        await tester.tap(find.text('30 days').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('portal-create-confirm')));
        await tester.pumpAndSettle();
        // The wire still speaks hours.
        expect(_controller.calls, ['create S1 720']);
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle(const Duration(seconds: 5));
      },
    );

    testWidgets(
      'UI-AUDIT #67: a row names its services, its desk and the day it was made',
      (tester) async {
        final made = DateTime(2026, 9, 20);
        await _pump(
          tester,
          one(
            EePortalLink(
              id: 'L1',
              serviceCount: 2,
              serviceNames: const ['Elektrik arızası', 'Aydınlatma'],
              unitName: 'Bakım',
              state: EePortalLinkState.active,
              enabled: true,
              expiresAt: DateTime(2026, 11, 6),
              createdAt: made,
            ),
          ),
        );
        expect(_inTile('L1', 'Elektrik arızası, Aydınlatma'), findsOneWidget);
        expect(_inTile('L1', 'Bakım'), findsOneWidget);
        expect(_inTile('L1', 'made'), findsOneWidget);
        expect(_inTile('L1', '2 services'), findsNothing);
      },
    );

    testWidgets(
      'UI-AUDIT #67: three links for one service, desk and day differ by the '
      'minute they were made — and twins in the same minute by their reference',
      (tester) async {
        EePortalLink made(String id, DateTime at) => EePortalLink(
          id: id,
          serviceId: 'S1',
          serviceNames: const ['Yazılım kurulumu'],
          unitName: 'Bilgi İşlem',
          state: EePortalLinkState.active,
          enabled: true,
          expiresAt: DateTime(2026, 11, 6),
          createdAt: at,
        );
        await _pump(
          tester,
          EePortalLinksData(
            links: [
              made('01LINKAAAAAAAAAAAAAAAAAAA1', DateTime(2026, 10, 7, 9, 15)),
              made('01LINKAAAAAAAAAAAAAAAQRST2', DateTime(2026, 10, 7, 14, 2)),
              made('01LINKAAAAAAAAAAAAAAAWXYZ3', DateTime(2026, 10, 7, 14, 2)),
            ],
            linkQuota: const EePortalQuota(used: 3),
            ticketQuota: const EePortalQuota(used: 0),
          ),
        );
        String subtitleOf(String id) =>
            (tester
                        .widget<ListTile>(find.byKey(Key('portal-link-$id')))
                        .subtitle!
                    as Text)
                .data!;
        final rows = [
          subtitleOf('01LINKAAAAAAAAAAAAAAAAAAA1'),
          subtitleOf('01LINKAAAAAAAAAAAAAAAQRST2'),
          subtitleOf('01LINKAAAAAAAAAAAAAAAWXYZ3'),
        ];
        expect(rows.toSet(), hasLength(3), reason: rows.join('\n'));
        // The lone 09:15 row needs no reference; the 14:02 twins carry one.
        expect(rows[0], isNot(contains('ref.')));
        expect(rows[1], contains('ref. AQRST2'));
        expect(rows[2], contains('ref. AWXYZ3'));
      },
    );

    testWidgets(
      'UI-AUDIT #57 (retest): on a phone the last row\'s menu can always be '
      'scrolled up from under the Quick Access bubble',
      (tester) async {
        const viewport = Size(390, 844);
        tester.view.physicalSize = viewport;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final origin = bubbleOrigin(
          kBubbleFactoryPosition,
          viewport,
          EdgeInsets.zero,
          0,
        );
        final bubble = origin & const Size.square(kBubbleDiameter);
        await _pump(
          tester,
          EePortalLinksData(
            links: [for (var i = 1; i <= 6; i++) _link(id: 'L$i')],
            linkQuota: const EePortalQuota(used: 6),
            ticketQuota: const EePortalQuota(used: 0),
          ),
          bubbleClearance: bubbleClearance(origin, viewport),
        );
        await tester.drag(find.byType(ListView), const Offset(0, -2000));
        await tester.pumpAndSettle();
        // Scrolled to the end, no row's menu is left under the button — the
        // end of the list is room, not rows (on a 4-row list the 4th row's
        // menu used to stay under it for good).
        for (var i = 1; i <= 6; i++) {
          final finder = find.byKey(Key('portal-menu-L$i'));
          if (finder.evaluate().isEmpty) continue;
          final menu = tester.getRect(finder);
          expect(
            menu.overlaps(bubble),
            isFalse,
            reason: 'L$i menu $menu stays under the bubble $bubble',
          );
        }
      },
    );

    test('UI-AUDIT #67: an older server without the fields still parses', () {
      final link = EePortalLink.fromJson({
        'id': 'L1',
        'serviceId': null,
        'serviceCount': 2,
        'state': 'active',
        'enabled': true,
        'expiresAt': '2026-09-01T12:00:00.000Z',
      });
      expect(link.serviceNames, isEmpty);
      expect(link.unitName, isNull);
      expect(link.createdAt, isNull);
    });

    testWidgets(
      'UI-AUDIT #65 #64: revoking asks "Keep it" or "Revoke link" in the error role, and the dialog is named',
      (tester) async {
        await _pump(tester, one(_link()));
        await tester.tap(find.byKey(const Key('portal-menu-L1')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Revoke'));
        await tester.pumpAndSettle();
        expect(find.text('Keep it'), findsOneWidget);
        expect(find.text('Cancel'), findsNothing);
        final confirm = tester.widget<FilledButton>(
          find.byKey(const Key('portal-revoke-confirm')),
        );
        expect(find.text('Revoke link'), findsOneWidget);
        final scheme = buildAwTheme(Brightness.light).colorScheme;
        expect(confirm.style?.backgroundColor?.resolve(const {}), scheme.error);
        final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
        expect(dialog.semanticLabel, isNotEmpty);
        await tester.tap(find.byKey(const Key('portal-revoke-confirm')));
        await tester.pumpAndSettle();
        expect(_controller.calls, ['revoke L1']);
      },
    );

    testWidgets(
      'UI-AUDIT D2: a refused clipboard says so instead of failing silently',
      (tester) async {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              throw PlatformException(code: 'denied');
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        await _pump(tester, one(_link()));
        await tester.tap(find.byKey(const Key('portal-create')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('portal-create-confirm')));
        await tester.pumpAndSettle();
        final dialog = tester.widget<AlertDialog>(
          find.byKey(const Key('portal-url-once')),
        );
        expect(dialog.semanticLabel, 'Link created');
        await tester.tap(find.byKey(const Key('portal-url-copy')));
        await tester.pumpAndSettle();
        expect(find.textContaining('Could not copy'), findsOneWidget);
        expect(find.text('Copied'), findsNothing);
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle(const Duration(seconds: 5));
      },
    );
  });
}
