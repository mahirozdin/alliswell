import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/data/identity_models.dart';
import 'package:alliswell/src/features/ee/identity_providers.dart';
import 'package:alliswell/src/features/ee/ui/team_identity_screen.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';

/// OPH-287 — the identity-source screen, asserted where it would mislead.
///
/// The sharpest case is the switch. An enabled provider is the ONLY authority
/// for the addresses it owns, so a screen that let somebody turn on a
/// half-filled one would turn a typo into an outage for everyone whose
/// account the directory holds. The server refuses it too; this asserts that
/// the control refuses BEFORE the round trip, because a switch that flips and
/// then snaps back teaches people to ignore it.
///
/// The others: a stored credential is four characters and never a field, and
/// an incomplete provider says WHICH settings it is missing rather than only
/// that it is unhappy — "still needs: baseDn" is the difference between a
/// screen somebody can finish and one they have to guess at.
class _Fixed extends EeIdentityController {
  _Fixed(this._value);
  final List<EeIdentityProvider>? _value;
  @override
  Future<List<EeIdentityProvider>?> build() async => _value;
}

class _FixedStatus extends EeIdentityStatusController {
  _FixedStatus(this._value);
  final EeIdentityStatus? _value;
  @override
  Future<EeIdentityStatus?> build() async => _value;
}

EeIdentityStatus _status({
  List<EeIdentityEvent> events = const [],
  List<EeScimClient> clients = const [],
  int linked = 3,
  int total = 4,
}) => EeIdentityStatus(
  providers: const [],
  scimClients: clients,
  events: events,
  totalMembers: total,
  inactiveMembers: 0,
  linkedMembers: linked,
);

EeIdentityEvent _event({
  String id = 'E1',
  String outcome = 'refused',
  String code = 'NO_MEMBER_ACCOUNT',
  String? subject = 'ada@corp.example',
  String? detail = 'no account here, and this provider may not create one',
}) => EeIdentityEvent(
  id: id,
  kind: 'sign_in',
  outcome: outcome,
  code: code,
  subject: subject,
  detail: detail,
  at: DateTime(2026, 9, 1, 9, 15),
);

EeIdentityProvider _provider({
  String id = 'P1',
  String type = 'ldap',
  String displayName = 'Corp directory',
  bool enabled = false,
  String status = 'active',
  bool secretSet = true,
  String? secretLast4 = '4417',
  String? secretField = 'bindPassword',
  String? lastError,
  List<String> missingRequired = const [],
}) => EeIdentityProvider(
  id: id,
  type: type,
  displayName: displayName,
  enabled: enabled,
  priority: 100,
  status: status,
  config: const {'url': 'ldaps://dc1.corp.example', 'baseDn': 'dc=corp'},
  secretSet: secretSet,
  secretLast4: secretLast4,
  secretField: secretField,
  lastError: lastError,
  missingRequired: missingRequired,
);

Future<void> _pump(
  WidgetTester tester,
  List<EeIdentityProvider>? value, {
  Brightness brightness = Brightness.light,
  EeIdentityStatus? status,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        eeIdentityProvidersProvider.overrideWith(() => _Fixed(value)),
        eeIdentityStatusProvider.overrideWith(() => _FixedStatus(status)),
      ],
      child: MaterialApp(
        theme: buildAwTheme(brightness),
        home: const EeTeamIdentityScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Switch _switchFor(WidgetTester tester, String id) =>
    tester.widget<Switch>(find.byKey(Key('identity-enable-$id')));

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('en'));
  });

  group('the switch', () {
    testWidgets('AN INCOMPLETE PROVIDER CANNOT BE SWITCHED ON', (tester) async {
      await _pump(tester, [
        _provider(missingRequired: const ['baseDn']),
      ]);
      // Disabled, not merely refused after a round trip: a control that flips
      // and snaps back teaches people to ignore it.
      expect(_switchFor(tester, 'P1').onChanged, isNull);
    });

    testWidgets('nor one whose credential is missing', (tester) async {
      await _pump(tester, [_provider(secretSet: false, secretLast4: null)]);
      expect(_switchFor(tester, 'P1').onChanged, isNull);
    });

    testWidgets('a complete one can', (tester) async {
      await _pump(tester, [_provider()]);
      expect(_switchFor(tester, 'P1').onChanged, isNotNull);
    });

    testWidgets('a type with no credential is complete without one', (
      tester,
    ) async {
      // SAML trusts a signature, not a shared key. A screen that demanded one
      // would make a correctly-configured provider unusable.
      await _pump(tester, [
        _provider(
          type: 'saml',
          secretSet: false,
          secretLast4: null,
          secretField: null,
        ),
      ]);
      expect(_switchFor(tester, 'P1').onChanged, isNotNull);
    });
  });

  group('what the screen may say about a credential', () {
    testWidgets('four characters, and never a field', (tester) async {
      await _pump(tester, [_provider()]);
      expect(find.textContaining('4417'), findsOneWidget);
      // No text field anywhere on the list surface: replacing a credential is
      // an act inside the editor, and a box on the tile would imply the old
      // value could be read back into it.
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('says nothing at all when none is stored', (tester) async {
      await _pump(tester, [_provider(secretSet: false, secretLast4: null)]);
      expect(find.textContaining('••••'), findsNothing);
    });
  });

  group('what an incomplete provider tells you', () {
    testWidgets(
      'names the settings it is missing, not just that it is unhappy',
      (tester) async {
        await _pump(tester, [
          _provider(missingRequired: const ['baseDn', 'url']),
        ]);
        expect(find.textContaining('baseDn'), findsOneWidget);
        expect(find.textContaining('url'), findsOneWidget);
      },
    );

    testWidgets('counts a missing credential among them', (tester) async {
      await _pump(tester, [_provider(secretSet: false, secretLast4: null)]);
      expect(find.textContaining('bindPassword'), findsOneWidget);
    });
  });

  group('state is a word, not only a colour', () {
    testWidgets('a failing provider says so in text AND carries its reason', (
      tester,
    ) async {
      await _pump(tester, [
        _provider(status: 'error', lastError: 'connect ECONNREFUSED'),
      ]);
      expect(find.textContaining('Not answering'), findsOneWidget);
      expect(find.textContaining('ECONNREFUSED'), findsOneWidget);
    });

    testWidgets('and a working one does too', (tester) async {
      await _pump(tester, [_provider()]);
      expect(find.textContaining('Working'), findsOneWidget);
    });
  });

  group('the empty and unavailable states are different things', () {
    testWidgets('no providers yet invites connecting one', (tester) async {
      await _pump(tester, const []);
      expect(find.textContaining('No identity source yet'), findsOneWidget);
      // The way in is still offered.
      expect(find.byKey(const Key('identity-add')), findsOneWidget);
    });

    testWidgets('no team here offers nothing, because there is nothing to do', (
      tester,
    ) async {
      await _pump(tester, null);
      expect(find.textContaining('No team here'), findsOneWidget);
      expect(find.byKey(const Key('identity-add')), findsNothing);
    });
  });

  group('the status section (OPH-289)', () {
    testWidgets(
      'SAYS WHETHER ANYTHING IS HAPPENING, not only whether it broke',
      (tester) async {
        // The failure this section is named after is a sync that stops
        // silently, and an empty error list looks exactly like a healthy one.
        await _pump(
          tester,
          [_provider()],
          status: _status(
            linked: 0,
            total: 40,
            clients: const [
              EeScimClient(id: 'C1', name: 'Entra', enabled: true),
            ],
          ),
        );
        // Zero of forty is a configuration that has never once worked, and it
        // is legible without a single error row.
        expect(find.textContaining('0'), findsWidgets);
        expect(find.textContaining('never provisioned'), findsOneWidget);
        expect(find.byKey(const Key('identity-no-problems')), findsOneWidget);
      },
    );

    testWidgets('A REFUSAL NAMES THE PERSON AND THE REASON', (tester) async {
      // "Sign-in refused" answers nothing at nine in the morning.
      await _pump(tester, [_provider()], status: _status(events: [_event()]));
      expect(find.textContaining('ada@corp.example'), findsOneWidget);
      expect(find.textContaining('may not create one'), findsOneWidget);
    });

    testWidgets('shows the address AS IT ARRIVED, not a tidied one', (
      tester,
    ) async {
      // EE-123's import-report rule: a report that shows the cleaned value
      // cannot explain what was wrong with the value.
      await _pump(tester, [
        _provider(),
      ], status: _status(events: [_event(subject: '  Ada@CORP.example ')]));
      expect(find.textContaining('Ada@CORP.example'), findsOneWidget);
    });

    testWidgets('successful events are not shown as problems', (tester) async {
      await _pump(
        tester,
        [_provider()],
        status: _status(
          events: [_event(id: 'E9', outcome: 'ok', code: 'CONNECTED')],
        ),
      );
      expect(find.byKey(const Key('identity-no-problems')), findsOneWidget);
      expect(find.byKey(const Key('identity-event-E9')), findsNothing);
    });

    testWidgets('and the section is absent entirely when there is no team', (
      tester,
    ) async {
      await _pump(tester, [_provider()], status: null);
      expect(find.byKey(const Key('identity-linked-count')), findsNothing);
    });
  });
}
