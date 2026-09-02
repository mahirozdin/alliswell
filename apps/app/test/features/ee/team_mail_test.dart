import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/data/team_mail_models.dart';
import 'package:alliswell/src/features/ee/team_mail_providers.dart';
import 'package:alliswell/src/features/ee/ui/team_mail_screen.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';

/// OPH-290 — the team mail screen, asserted where it would mislead.
///
/// Two of these are the whole point of the screen existing.
///
/// The first is the sentence for a team that has not configured anything. Mail
/// used to leave through the operator's relay and no team thought about it;
/// now an unconfigured team sends nothing, and the fear that creates —
/// "have we been silently losing notifications?" — has a good answer that the
/// screen must actually say. A screen that only reported "mail is off" would
/// leave somebody to guess.
///
/// The second is the switch. A relay that is enabled and wrong FAILS every
/// message in the queue instead of leaving them for the moment it works, so
/// the control must refuse before the round trip rather than flip and snap
/// back — the identity screen's rule, for a sharper reason.
class _Fixed extends EeTeamMailController {
  _Fixed(this._value);
  final EeTeamMail? _value;
  @override
  Future<EeTeamMail?> build() async => _value;
}

EeTeamMail _mail({
  bool configured = true,
  bool enabled = false,
  String? host = 'smtp.corp.example',
  String? fromAddress = 'desk@corp.example',
  bool passwordSet = true,
  String? passwordLast4 = '4417',
  String status = 'active',
  String? lastError,
  List<String> missingRequired = const [],
}) => EeTeamMail(
  configured: configured,
  enabled: enabled,
  host: host,
  port: 587,
  secure: false,
  username: 'desk@corp.example',
  fromAddress: fromAddress,
  fromName: 'Corp Service Desk',
  passwordSet: passwordSet,
  passwordLast4: passwordLast4,
  status: status,
  lastError: lastError,
  missingRequired: missingRequired,
);

Future<void> _pump(WidgetTester tester, EeTeamMail? value) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [eeTeamMailProvider.overrideWith(() => _Fixed(value))],
      child: MaterialApp(
        theme: buildAwTheme(Brightness.light),
        home: const EeTeamMailScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The enable switch and the test button sit below the fold of an 800x600 test
/// viewport, and a `ListView` does not BUILD what it has not laid out — so
/// `find.byKey` returns nothing and the failure reads as "the widget is
/// missing" rather than "the widget is further down". Scroll to it first, the
/// idiom `share_log_screen_test` already uses.
Future<Finder> _reveal(WidgetTester tester, Key key) async {
  final target = find.byKey(key);
  await tester.scrollUntilVisible(
    target,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  return target;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('en'));
  });

  testWidgets('AN UNCONFIGURED TEAM IS TOLD NOTHING IS LOST', (tester) async {
    await _pump(
      tester,
      _mail(
        configured: false,
        host: null,
        fromAddress: null,
        passwordSet: false,
        passwordLast4: null,
        missingRequired: const ['host', 'fromAddress'],
      ),
    );

    expect(find.text('ee.mail.stateOff'.tr()), findsOneWidget);
    // The answer to the fear. Without this the screen reports a problem and
    // leaves the consequence to the imagination.
    expect(find.text('ee.mail.stateOffHint'.tr()), findsOneWidget);
  });

  testWidgets(
    'a half-finished relay cannot be switched on, and says which fields',
    (tester) async {
      await _pump(tester, _mail(missingRequired: const ['host', 'password']));

      final sw = tester.widget<SwitchListTile>(
        await _reveal(tester, const Key('ee-mail-enabled')),
      );
      // Refuses BEFORE the round trip: a switch that flips and snaps back
      // teaches people to ignore it.
      expect(sw.onChanged, isNull);
      expect(sw.value, isFalse);
      // And names them, so the screen can be finished rather than guessed at.
      expect(
        find.text(
          'ee.mail.enabledBlocked'.tr(args: {'fields': 'host, password'}),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('a complete relay CAN be switched on', (tester) async {
    await _pump(tester, _mail());
    final sw = tester.widget<SwitchListTile>(
      await _reveal(tester, const Key('ee-mail-enabled')),
    );
    expect(sw.onChanged, isNotNull);
  });

  testWidgets('a stored password is four characters and never a value', (
    tester,
  ) async {
    await _pump(tester, _mail());

    // The label says what is stored; the field itself is empty, because there
    // is nothing to prefill it WITH and an obscured box implies otherwise.
    expect(
      find.text('ee.mail.passwordStored'.tr(args: {'last4': '4417'})),
      findsOneWidget,
    );
    final fields = tester.widgetList<TextField>(find.byType(TextField));
    final obscured = fields.where((f) => f.obscureText).toList();
    expect(obscured, hasLength(1));
    expect(obscured.single.controller?.text ?? '', isEmpty);
  });

  // Two tests rather than two pumps in one: a second `pumpWidget` reuses the
  // ProviderScope's container, so the override does not take and the screen
  // keeps rendering the first value. The failure reads as "the error state is
  // missing" when what actually happened is that it was never shown.
  testWidgets('a relay that is on says so', (tester) async {
    await _pump(tester, _mail(enabled: true));
    expect(find.text('ee.mail.stateOn'.tr()), findsOneWidget);
  });

  testWidgets('...and one that failed says that, in the relay OWN words', (
    tester,
  ) async {
    await _pump(
      tester,
      _mail(
        enabled: true,
        status: 'error',
        lastError: '535 authentication failed',
      ),
    );
    expect(find.text('ee.mail.stateError'.tr()), findsOneWidget);
    // Not a generic failure: that string is what somebody pastes into a search
    // or hands to their mail admin.
    expect(find.text('535 authentication failed'), findsOneWidget);
  });

  testWidgets('testing is refused until something is saved', (tester) async {
    await _pump(
      tester,
      _mail(configured: false, host: null, fromAddress: null),
    );
    final button = tester.widget<OutlinedButton>(
      await _reveal(tester, const Key('ee-mail-test')),
    );
    // Testing an unsaved host would prove something about a relay this team is
    // not using.
    expect(button.onPressed, isNull);
  });
}
