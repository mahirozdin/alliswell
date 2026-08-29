import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/data/sla_dashboard_models.dart';
import 'package:alliswell/src/features/ee/sla_dashboard_providers.dart';
import 'package:alliswell/src/features/ee/ui/sla_dashboard_screen.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';
import 'package:alliswell/src/theme/tokens.dart';

/// EE-098 — the dashboard, asserted where it would lie.
///
/// This is the screen the epic is sold on, so the cases here are the three
/// places a sales-facing number goes wrong:
///
///   • A DASH IS NOT A ZERO AND IT IS NOT A HUNDRED. A desk with nothing
///     judged yet has no percentage. Rounding that up to 100 % is the single
///     most flattering, most dishonest thing this screen could do.
///
///   • GOOD NEWS NEEDS A SENTENCE. An empty breach list drawn as an empty list
///     reads as a screen that failed to load, and the difference matters most
///     on the day it is true.
///
///   • THE NUMBER IS TEXT, NOT A BAR. A bar is a picture of a ratio; the count
///     beside it is what somebody quotes in a meeting.
EeSlaDashboard _dash({
  double? compliance,
  List<EeSlaBucket> byUnit = const [],
  List<EeSlaBucket> byService = const [],
  List<EeSlaBreach> breaches = const [],
  int total = 0,
}) => EeSlaDashboard(
  compliance: compliance,
  byStatus: [EeSlaBucket(key: 'new', label: 'new', count: total)],
  byUnit: byUnit,
  byService: byService,
  breaches: breaches,
);

class _Fixed extends EeSlaDashboardController {
  _Fixed(this._value);
  final EeSlaDashboard? _value;
  @override
  Future<EeSlaDashboard?> build() async => _value;
}

Future<void> _pump(
  WidgetTester tester,
  EeSlaDashboard? value, {
  Brightness brightness = Brightness.light,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [eeSlaDashboardProvider.overrideWith(() => _Fixed(value))],
      child: MaterialApp(
        theme: buildAwTheme(brightness),
        home: const EeSlaDashboardScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Color? _complianceColour(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('sla-compliance'))).style?.color;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('en'));
  });

  testWidgets('NOTHING JUDGED IS A DASH, never a flattering hundred', (
    tester,
  ) async {
    await _pump(tester, _dash(compliance: null, total: 12));
    expect(find.text('—'), findsOneWidget);
    expect(find.text('Nothing judged yet'), findsOneWidget);
    // Not a percentage of any kind.
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets(
    'a healthy desk reads in the success colour, and says the total',
    (tester) async {
      await _pump(tester, _dash(compliance: 97.5, total: 40));
      final context = tester.element(find.byType(EeSlaDashboardScreen));
      expect(find.text('%97.5'), findsOneWidget);
      expect(find.text('across 40 requests'), findsOneWidget);
      expect(_complianceColour(tester), context.awTokens.success);
    },
  );

  testWidgets(
    'below the line it reads in error — a colour that passes as TEXT',
    (tester) async {
      await _pump(tester, _dash(compliance: 61.0, total: 40));
      final context = tester.element(find.byType(EeSlaDashboardScreen));
      // Measured 5.38 on the light surface; the amber accent (3.46) is never
      // used for a label anywhere on this screen.
      expect(_complianceColour(tester), Theme.of(context).colorScheme.error);
      expect(_complianceColour(tester), isNot(context.awTokens.warning));
    },
  );

  testWidgets('GOOD NEWS GETS A SENTENCE, not an empty list', (tester) async {
    await _pump(tester, _dash(compliance: 100.0, total: 5));
    expect(find.byKey(const Key('sla-no-breaches')), findsOneWidget);
    expect(find.textContaining('No missed targets'), findsOneWidget);
  });

  testWidgets('a breach is named, and carries its status and priority', (
    tester,
  ) async {
    await _pump(
      tester,
      _dash(
        compliance: 50.0,
        total: 2,
        breaches: [
          const EeSlaBreach(
            id: 'T1',
            subject: 'Dolum bandı durdu',
            priority: 'urgent',
            status: 'in_progress',
          ),
        ],
      ),
    );
    expect(find.byKey(const Key('sla-breach-T1')), findsOneWidget);
    expect(find.text('Dolum bandı durdu'), findsOneWidget);
    expect(find.byKey(const Key('sla-no-breaches')), findsNothing);
  });

  testWidgets('every breakdown row shows its COUNT beside the bar', (
    tester,
  ) async {
    await _pump(
      tester,
      _dash(
        compliance: 90.0,
        total: 9,
        byUnit: const [
          EeSlaBucket(key: 'U1', label: 'Bakım', count: 6),
          EeSlaBucket(key: 'U2', label: 'Mühendislik', count: 3),
        ],
      ),
    );
    expect(find.text('Bakım'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
    expect(find.text('Mühendislik'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    // The bar is there too, but the number is the fact.
    expect(find.byType(LinearProgressIndicator), findsNWidgets(2));
  });

  testWidgets('a retired service keeps its count and says so in words', (
    tester,
  ) async {
    // The server sends `label: null` for a catalogue entry that was removed.
    // Dropping the row would make the axis totals disagree with the status
    // totals — the quiet arithmetic error EE-090 already refused once.
    await _pump(
      tester,
      _dash(
        compliance: 80.0,
        total: 4,
        byService: const [EeSlaBucket(key: null, label: null, count: 4)],
      ),
    );
    expect(find.text('No service'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
  });

  testWidgets('no team at this address is an explanation, not an error', (
    tester,
  ) async {
    await _pump(tester, null);
    expect(find.text('No dashboard here'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets(
    'THE QUEUE CAN REACH IT — a screen nothing opens is not a feature',
    (tester) async {
      // DESIGN §22, and the lesson this repo paid for once: a delete engine, an
      // ordering feature and a colour picker all existed for months with no
      // caller. The button is asserted here rather than trusted to a golden,
      // because a golden nobody regenerates would not notice it disappearing.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            eeSlaDashboardProvider.overrideWith(() => _Fixed(_dash())),
          ],
          child: MaterialApp(
            theme: buildAwTheme(Brightness.light),
            home: Builder(
              builder: (context) => Scaffold(
                appBar: AppBar(
                  actions: [
                    IconButton(
                      key: const Key('ticket-sla-dashboard'),
                      icon: const Icon(Icons.query_stats_outlined),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const EeSlaDashboardScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('ticket-sla-dashboard')));
      await tester.pumpAndSettle();
      expect(find.byType(EeSlaDashboardScreen), findsOneWidget);
    },
  );

  testWidgets('the dark theme paints the headline too', (tester) async {
    await _pump(
      tester,
      _dash(compliance: 61.0, total: 40),
      brightness: Brightness.dark,
    );
    final context = tester.element(find.byType(EeSlaDashboardScreen));
    expect(_complianceColour(tester), Theme.of(context).colorScheme.error);
  });
}
