import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/ui/sla_chip.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/theme/theme.dart';
import 'package:alliswell/src/theme/tokens.dart';

/// EE-097 — the SLA badge, asserted rather than photographed.
///
/// The screenshot file next door is inert without `--dart-define=screenshots`
/// and its goldens are not committed, so it protects nothing on CI. This file
/// is what does: it runs everywhere and states the two decisions the badge
/// exists to keep.
///
///   • THE COLOUR IS THE MARK, THE MEANING IS THE WORD. `AwTokens.warning`
///     measures 3.46 against the light surface — a legal icon and an illegal
///     sentence — so the amber state must NOT tint its label. That is asserted
///     here as a colour comparison, because `contrast.py` can only check pairs
///     somebody listed, and the thing it cannot see is which widget picked
///     which colour (DESIGN §7.1).
///
///   • A TICKET WITH NO PROMISE DRAWS NOTHING. A desk with no SLA configured
///     must look exactly as it did before this feature, not carry an empty
///     badge on every row.
TicketRecord _ticket({String? slaStatus, DateTime? slaDueAt}) => TicketRecord(
  id: 'T1',
  workspaceId: 'W1',
  subject: 'Dolum bandı durdu',
  status: 'in_progress',
  priority: 'high',
  source: 'internal',
  revision: 1,
  slaStatus: slaStatus,
  slaDueAt: slaDueAt,
);

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.light,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAwTheme(brightness),
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

/// The colour the badge's LABEL was actually painted in.
Color? _labelColour(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('sla-chip-label'))).style?.color;

Color? _iconColour(WidgetTester tester) =>
    tester.widget<Icon>(find.byType(Icon)).color;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('en'));
  });

  testWidgets('a ticket with no promise draws nothing at all', (tester) async {
    await _pump(tester, AwSlaChip(ticket: _ticket()));
    expect(find.byKey(const Key('sla-chip-label')), findsNothing);
    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('a breach says so, in the colour that passes at text strength', (
    tester,
  ) async {
    await _pump(tester, AwSlaChip(ticket: _ticket(slaStatus: 'breached')));
    final context = tester.element(find.byType(AwSlaChip));
    expect(find.text('SLA missed'), findsOneWidget);
    // #D70015 on white measures 5.38 — a label may take it.
    expect(_labelColour(tester), Theme.of(context).colorScheme.error);
  });

  testWidgets('a kept promise says so too', (tester) async {
    await _pump(tester, AwSlaChip(ticket: _ticket(slaStatus: 'met')));
    final context = tester.element(find.byType(AwSlaChip));
    expect(find.text('SLA met'), findsOneWidget);
    expect(_labelColour(tester), context.awTokens.success);
  });

  testWidgets('THE WARNING TINTS ITS MARK AND NOT ITS LABEL — 3.46 is not 4.5', (
    tester,
  ) async {
    final due = DateTime(2026, 8, 30, 12);
    await _pump(
      tester,
      AwSlaChip(
        ticket: _ticket(slaStatus: 'warned', slaDueAt: due),
        now: DateTime(2026, 8, 30, 10, 30),
      ),
    );
    final context = tester.element(find.byType(AwSlaChip));
    final tokens = context.awTokens;
    // The icon carries the accent (3.0 is its bar)…
    expect(_iconColour(tester), tokens.warning);
    // …and the label must NOT, or the gate's `FAILURES: 0` would be describing
    // a screen nobody can read.
    expect(_labelColour(tester), isNot(tokens.warning));
    expect(find.text('1 h 30 m left'), findsOneWidget);
  });

  testWidgets('an overdue countdown says over, not a negative number', (
    tester,
  ) async {
    await _pump(
      tester,
      AwSlaChip(
        ticket: _ticket(slaStatus: 'ok', slaDueAt: DateTime(2026, 8, 30, 9)),
        now: DateTime(2026, 8, 30, 9, 45),
      ),
    );
    expect(find.text('45 m over'), findsOneWidget);
  });

  testWidgets('the dark theme paints it too, and differently', (tester) async {
    await _pump(
      tester,
      AwSlaChip(ticket: _ticket(slaStatus: 'breached')),
      brightness: Brightness.dark,
    );
    final context = tester.element(find.byType(AwSlaChip));
    expect(_labelColour(tester), Theme.of(context).colorScheme.error);
  });

  testWidgets('the detail countdown carries the same badge', (tester) async {
    await _pump(
      tester,
      AwSlaCountdown(
        ticket: _ticket(slaStatus: 'ok', slaDueAt: DateTime(2026, 8, 30, 12)),
        now: DateTime(2026, 8, 30, 10),
      ),
    );
    expect(find.byKey(const Key('sla-countdown')), findsOneWidget);
    expect(find.text('Response due'), findsOneWidget);
    expect(find.text('2 h 0 m left'), findsOneWidget);
  });

  testWidgets('a settled ticket mutes the badge rather than hiding it', (
    tester,
  ) async {
    await _pump(
      tester,
      AwSlaChip(ticket: _ticket(slaStatus: 'breached'), muted: true),
    );
    final context = tester.element(find.byType(AwSlaChip));
    // Finished work sinks, it does not disappear — the queue's own rule, and
    // a breach on a closed ticket is exactly the row somebody searches for.
    expect(find.text('SLA missed'), findsOneWidget);
    expect(_labelColour(tester), Theme.of(context).disabledColor);
  });

  group('the countdown is coarse on purpose', () {
    setUp(() => AwI18n.instance.setActiveCached(const Locale('en')));

    test('days, then hours and minutes, then minutes', () {
      expect(formatSlaDuration(const Duration(days: 2, hours: 3)), '2 d');
      expect(
        formatSlaDuration(const Duration(hours: 4, minutes: 5)),
        '4 h 5 m',
      );
      expect(formatSlaDuration(const Duration(minutes: 12)), '12 m');
      // No seconds anywhere: the underlying number is BUSINESS time, which
      // stops at 17:00, so a second-by-second countdown would be a lie told
      // precisely.
      expect(formatSlaDuration(const Duration(seconds: 30)), '0 m');
    });

    test('a negative duration formats its magnitude', () {
      expect(formatSlaDuration(const Duration(minutes: -45)), '45 m');
    });
  });

  test('an unknown status is treated as no promise, not as a bug', () {
    // The server's vocabulary can grow; a replica that has not been updated
    // must draw nothing rather than throw on a queue it cannot render.
    expect(slaBadgeStateOf('something_new'), isNull);
    expect(slaBadgeStateOf(null), isNull);
    expect(slaBadgeStateOf('breached'), SlaBadgeState.breached);
  });
}
