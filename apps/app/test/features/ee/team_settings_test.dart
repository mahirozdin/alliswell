import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/data/team_settings.dart';
import 'package:alliswell/src/features/ee/data/team_settings_api.dart';
import 'package:alliswell/src/features/ee/team_settings_providers.dart';
import 'package:alliswell/src/features/ee/ui/team_settings_screen.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';
import 'package:alliswell/src/widgets/status_views.dart';

/// EE-037 — the team settings form. The behaviour worth pinning is not that
/// the fields render: it is that NULL SURVIVES (a team that chose nothing is
/// never shown a default it did not pick) and that the SERVER'S ANSWER WINS
/// (what is on screen is what is stored, even when a save is refused).

EeTeamSettings settings({
  String name = 'Ayarlar A.Ş.',
  String? locale,
  String? timezone,
  String? colorRgb,
  String? logoUrl,
  bool hasLogo = false,
}) => EeTeamSettings(
  name: name,
  slug: 'ayarlar',
  locale: locale,
  timezone: timezone,
  colorRgb: colorRgb,
  logoUrl: logoUrl,
  hasLogo: hasLogo,
);

/// Records what the screen asked for and answers with whatever the test set.
class FakeApi implements EeTeamSettingsApi {
  FakeApi(this._current);

  EeTeamSettings _current;
  final List<Map<String, dynamic>> calls = [];
  Object? failWith;

  @override
  Future<EeTeamSettings> read() async => _current;

  @override
  Future<EeTeamSettings> update({
    String? name,
    String? locale,
    String? timezone,
    String? colorRgb,
    Set<String> clear = const {},
  }) async {
    calls.add({
      'name': ?name,
      'locale': ?locale,
      'timezone': ?timezone,
      'colorRgb': ?colorRgb,
      for (final field in clear) field: null,
    });
    if (failWith != null) throw failWith!;
    _current = _current.copyWith(
      name: name,
      locale: locale,
      timezone: timezone,
      colorRgb: colorRgb,
    );
    return _current;
  }

  @override
  Future<EeLogoTicket> startLogoUpload({
    required String contentType,
    required int sizeBytes,
  }) async => const EeLogoTicket(key: 'k', url: 'u', headers: {});

  @override
  Future<EeTeamSettings> completeLogo({
    required String key,
    required int sizeBytes,
  }) async => _current;

  @override
  Future<EeTeamSettings> removeLogo() async {
    calls.add({'logo': null});
    _current = settings(name: _current.name);
    return _current;
  }
}

Widget harness(FakeApi api) => ProviderScope(
  overrides: [eeTeamSettingsApiProvider.overrideWithValue(api)],
  child: MaterialApp(
    theme: buildAwTheme(Brightness.light),
    home: const EeTeamSettingsScreen(),
  ),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('en'));
  });

  testWidgets('an unchosen team is shown as unchosen, not as defaults', (
    tester,
  ) async {
    await tester.pumpWidget(harness(FakeApi(settings())));
    await tester.pumpAndSettle();

    expect(find.text('Ayarlar A.Ş.'), findsOneWidget);
    // The two "nothing chosen" labels, spelled out rather than implied by an
    // empty picker.
    expect(find.text('Follow each person’s own choice'), findsOneWidget);
    expect(find.text('Not set (UTC)'), findsOneWidget);
    // Nothing to remove when there is no logo.
    expect(find.text('Remove'), findsNothing);
  });

  testWidgets('the address is shown as fixed, with the reason', (tester) async {
    await tester.pumpWidget(harness(FakeApi(settings())));
    await tester.pumpAndSettle();
    expect(find.textContaining('Address stays ayarlar'), findsOneWidget);
  });

  testWidgets('a stored zone outside the short list is still shown', (
    tester,
  ) async {
    // Otherwise opening the screen would silently offer to replace a real
    // choice with "not set".
    await tester.pumpWidget(
      harness(FakeApi(settings(timezone: 'Pacific/Auckland'))),
    );
    await tester.pumpAndSettle();
    expect(find.text('Pacific/Auckland'), findsOneWidget);
  });

  testWidgets('the name is sent trimmed, and the stored answer replaces it', (
    tester,
  ) async {
    final api = FakeApi(settings());
    await tester.pumpWidget(harness(api));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '   Yeni Ad   ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(api.calls.single, {'name': 'Yeni Ad'});
    expect(find.text('Yeni Ad'), findsOneWidget);
  });

  testWidgets('choosing a colour saves it; choosing "derived" clears it', (
    tester,
  ) async {
    final api = FakeApi(settings());
    await tester.pumpWidget(harness(api));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('#16A34A'));
    await tester.pumpAndSettle();
    expect(api.calls.single, {'colorRgb': '#16A34A'});

    await tester.tap(find.bySemanticsLabel('Derived from the address'));
    await tester.pumpAndSettle();
    // An explicit null — the difference between "leave it" and "clear it".
    expect(api.calls.last, {'colorRgb': null});
  });

  testWidgets('a language is saved by its own endonym', (tester) async {
    final api = FakeApi(settings());
    await tester.pumpWidget(harness(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Follow each person’s own choice'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Türkçe').last);
    await tester.pumpAndSettle();

    expect(api.calls.single, {'locale': 'tr'});
    expect(find.text('Türkçe'), findsOneWidget);
  });

  testWidgets('a refused save leaves the screen showing what is stored', (
    tester,
  ) async {
    // The picker is controlled by the loaded settings, so a rejection cannot
    // leave the form claiming a value the server never took.
    final api = FakeApi(settings(locale: 'tr'))..failWith = Exception('nope');
    await tester.pumpWidget(harness(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Türkçe'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English').last);
    await tester.pumpAndSettle();

    expect(api.calls.single, {'locale': 'en'});
    expect(find.byType(AwErrorState), findsOneWidget);
  });

  testWidgets('a stored logo the server cannot show is still removable', (
    tester,
  ) async {
    // hasLogo without a url is a real state: the instance has no object
    // storage configured. "No logo" and "cannot show you the logo" are
    // different truths and the screen must not collapse them.
    final api = FakeApi(settings(hasLogo: true));
    await tester.pumpWidget(harness(api));
    await tester.pumpAndSettle();

    expect(find.text('Remove'), findsOneWidget);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(api.calls.single, {'logo': null});
    expect(find.text('Remove'), findsNothing);
  });

  testWidgets('an unreachable server is an error with a way back', (
    tester,
  ) async {
    final api = _DeadApi();
    await tester.pumpWidget(harness(api));
    await tester.pumpAndSettle();
    expect(find.byType(AwErrorState), findsOneWidget);
  });
}

class _DeadApi extends FakeApi {
  _DeadApi() : super(settings());

  @override
  Future<EeTeamSettings> read() async => throw Exception('offline');
}
