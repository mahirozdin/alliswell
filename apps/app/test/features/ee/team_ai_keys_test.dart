import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/data/team_ai_models.dart';
import 'package:alliswell/src/features/ee/team_ai_providers.dart';
import 'package:alliswell/src/features/ee/ui/team_ai_keys_screen.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';

/// EE-111 — the key screen, asserted where it would mislead.
///
/// The sharpest case is the one the server cannot protect anybody from: an
/// admin turning personal keys OFF while the team has no key of its own. That
/// combination means nobody in the team can use AI at all, and it is reachable
/// in one tap from a switch whose label says nothing about it. So the screen
/// says it, and this file proves the sentence appears exactly when the state
/// is real — and not when only half of it is.
///
/// The others are the same family: four characters of a key are the MOST that
/// can appear anywhere, the policy sentence changes with the policy rather
/// than sitting there as a fixed caption, and each state mark carries its own
/// key because the tile also holds a delete button (E11 lost three CI runs to
/// finders that matched more than they meant).
class _Fixed extends EeTeamAiController {
  _Fixed(this._value);
  final EeTeamAiData? _value;
  @override
  Future<EeTeamAiData?> build() async => _value;
}

EeTeamAiConnection _conn({
  String id = 'C1',
  String provider = 'anthropic',
  EeTeamAiStatus status = EeTeamAiStatus.active,
  String? keyLast4 = '9911',
  String? baseUrl,
}) => EeTeamAiConnection(
  id: id,
  provider: provider,
  status: status,
  keyLast4: keyLast4,
  baseUrl: baseUrl,
);

EeTeamAiData _data({
  List<EeTeamAiConnection> items = const [],
  bool personalKeysAllowed = true,
}) => EeTeamAiData(
  items: items,
  personalKeysAllowed: personalKeysAllowed,
  providers: const ['anthropic', 'openai', 'ollama'],
);

Future<void> _pump(
  WidgetTester tester,
  EeTeamAiData? value, {
  Brightness brightness = Brightness.light,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [eeTeamAiProvider.overrideWith(() => _Fixed(value))],
      child: MaterialApp(
        theme: buildAwTheme(brightness),
        home: const EeTeamAiKeysScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Text inside ONE tile. The policy card above the list carries sentences that
/// mention keys too, so an unscoped finder would match more than a row.
Finder _inTile(String id, String text) => find.descendant(
  of: find.byKey(Key('team-ai-$id')),
  matching: find.textContaining(text),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('en'));
  });

  testWidgets('a configured key shows four characters and nothing more', (
    tester,
  ) async {
    await _pump(tester, _data(items: [_conn()]));

    expect(_inTile('C1', '9911'), findsOneWidget);
    expect(_inTile('C1', 'Working'), findsOneWidget);
    // The mark is findable as ITSELF: the tile also holds a delete button.
    expect(find.byKey(const Key('team-ai-mark-C1')), findsOneWidget);
    // Nothing that looks like a key. The model has no field for one, so this
    // is really an assertion about the model — which is the point: the test
    // fails the day somebody adds the field that would make it possible.
    expect(find.textContaining('sk-'), findsNothing);
  });

  testWidgets('a refused key says so in words, not only in colour', (
    tester,
  ) async {
    await _pump(tester, _data(items: [_conn(status: EeTeamAiStatus.error)]));
    expect(_inTile('C1', 'Key refused'), findsOneWidget);
  });

  // One pump per case. Pumping twice in one test and expecting the second
  // override to win does not work here — the provider is already built, so the
  // screen goes on rendering the first answer and the assertion fails for a
  // reason that has nothing to do with the screen.
  testWidgets('the policy sentence says members may use their own', (
    tester,
  ) async {
    await _pump(tester, _data(items: [_conn()]));
    expect(find.textContaining('Members may add and use'), findsOneWidget);
    expect(find.byKey(const Key('team-ai-stranded')), findsNothing);
  });

  testWidgets('and says only the team key works when they may not', (
    tester,
  ) async {
    await _pump(tester, _data(items: [_conn()], personalKeysAllowed: false));
    expect(find.textContaining("Only the team's key works"), findsOneWidget);
    // A team WITH a key is not stranded, so the warning must not appear.
    expect(find.byKey(const Key('team-ai-stranded')), findsNothing);
  });

  testWidgets('personal keys off AND no team key is called out', (
    tester,
  ) async {
    await _pump(tester, _data(personalKeysAllowed: false));
    expect(find.byKey(const Key('team-ai-stranded')), findsOneWidget);
    expect(
      find.textContaining('Nobody in this team can use AI'),
      findsOneWidget,
    );
  });

  testWidgets('neither half of that combination is enough on its own', (
    tester,
  ) async {
    // No key, but personal keys allowed: an ordinary empty state.
    await _pump(tester, _data());
    expect(find.byKey(const Key('team-ai-stranded')), findsNothing);
    expect(find.textContaining('No team key yet'), findsOneWidget);
  });

  testWidgets(
    'a keyless provider shows its address instead of four characters',
    (tester) async {
      await _pump(
        tester,
        _data(
          items: [
            _conn(
              id: 'C2',
              provider: 'ollama',
              keyLast4: null,
              baseUrl: 'http://ollama.internal:11434',
            ),
          ],
        ),
      );
      expect(_inTile('C2', 'ollama.internal'), findsOneWidget);
      expect(_inTile('C2', '••••'), findsNothing);
    },
  );

  testWidgets('no team, no screen: the door says why rather than failing', (
    tester,
  ) async {
    await _pump(tester, null);
    expect(find.textContaining('No team here'), findsOneWidget);
    // And no way to add a key to a team that is not there.
    expect(find.byKey(const Key('team-ai-add')), findsNothing);
  });

  testWidgets('the dark theme renders the same claims', (tester) async {
    await _pump(
      tester,
      _data(items: [_conn()], personalKeysAllowed: false),
      brightness: Brightness.dark,
    );
    expect(_inTile('C1', '9911'), findsOneWidget);
    expect(find.textContaining("Only the team's key works"), findsOneWidget);
  });
}
