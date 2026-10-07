import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/ee/data/worklog_models.dart';
import 'package:alliswell/src/features/ee/ui/ticket_worklog_section.dart';
import 'package:alliswell/src/features/ee/worklog_providers.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';

/// EE-208 — the three claims the screen is responsible for.
///
/// The arithmetic and the refusals are the server's and are proven there. What
/// only a widget test can show is that the SHAPE of the answer survives being
/// drawn: a cost that is absent stays absent rather than becoming "0", two
/// currencies stay two lines rather than being added on the way to the pixel,
/// and time with no price still says so.
const _ticketId = '01JB0000000000000000000009';

EeWorklog _log({
  required String id,
  int minutes = 90,
  int? costMinor,
  String? currency,
}) => EeWorklog(
  id: id,
  userId: 'u1',
  minutes: minutes,
  workedOn: '2026-09-18',
  rateMinor: costMinor == null ? null : 30000,
  currency: currency,
  costMinor: costMinor,
);

Future<void> _pump(WidgetTester tester, EeWorklogPanel panel) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        eeWorklogProvider(_ticketId).overrideWith((ref) async => panel),
      ],
      child: MaterialApp(
        theme: buildAwTheme(Brightness.light),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: EeTicketWorklogSection(ticketId: _ticketId),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an unpriced entry shows NO cost — absent, not zero', (
    tester,
  ) async {
    // Zero is a claim about what an hour is worth, and a desk whose people sit
    // on base roles has no rates at all. The acceptance line asks for the field
    // to be hidden, so the assertion is that nothing is drawn — not that a
    // placeholder is.
    await _pump(
      tester,
      EeWorklogPanel(
        worklogs: [_log(id: 'w1')],
        totals: const EeWorklogTotals(
          minutes: 90,
          unpricedMinutes: 90,
          byCurrency: [],
        ),
      ),
    );
    expect(find.byKey(const Key('worklog-w1')), findsOneWidget);
    expect(find.byKey(const Key('worklog-cost-w1')), findsNothing);
    expect(find.textContaining('0.00'), findsNothing);
    // …and the minutes are still said, with a sentence that stops an empty
    // cost reading as "this was free".
    expect(find.byKey(const Key('worklog-unpriced')), findsOneWidget);
  });

  testWidgets('a priced entry shows its own currency, from the server', (
    tester,
  ) async {
    await _pump(
      tester,
      EeWorklogPanel(
        worklogs: [_log(id: 'w2', costMinor: 45000, currency: 'TRY')],
        totals: const EeWorklogTotals(
          minutes: 90,
          unpricedMinutes: 0,
          byCurrency: [
            EeMoneyByCurrency(currency: 'TRY', costMinor: 45000, minutes: 90),
          ],
        ),
      ),
    );
    expect(find.byKey(const Key('worklog-cost-w2')), findsOneWidget);
    expect(find.textContaining('450.00'), findsWidgets);
    expect(find.byKey(const Key('worklog-unpriced')), findsNothing);
  });

  testWidgets('TWO CURRENCIES ARE TWO LINES, and there is no third', (
    tester,
  ) async {
    // The point of the whole shape. A widget that summed these would produce a
    // figure in a currency nobody chose, which is worse than showing none
    // because it looks like an answer.
    await _pump(
      tester,
      EeWorklogPanel(
        worklogs: [
          _log(id: 'w3', costMinor: 45000, currency: 'TRY'),
          _log(id: 'w4', minutes: 60, costMinor: 6000, currency: 'EUR'),
        ],
        totals: const EeWorklogTotals(
          minutes: 150,
          unpricedMinutes: 0,
          byCurrency: [
            EeMoneyByCurrency(currency: 'EUR', costMinor: 6000, minutes: 60),
            EeMoneyByCurrency(currency: 'TRY', costMinor: 45000, minutes: 90),
          ],
        ),
      ),
    );
    expect(find.byKey(const Key('worklog-total-TRY')), findsOneWidget);
    expect(find.byKey(const Key('worklog-total-EUR')), findsOneWidget);
    // 450,00 + 60,00 is 510 in no currency at all. If a future change adds a
    // total line, this is what catches it.
    expect(find.textContaining('510'), findsNothing);
    // Minutes DO add, because minutes are one unit everywhere.
    expect(find.byKey(const Key('worklog-total-hours')), findsOneWidget);
  });

  testWidgets('an empty panel invites an entry rather than showing zeros', (
    tester,
  ) async {
    await _pump(tester, EeWorklogPanel.empty);
    expect(find.byKey(const Key('worklog-empty')), findsOneWidget);
    expect(find.byKey(const Key('worklog-total-hours')), findsNothing);
    expect(find.byKey(const Key('worklog-add')), findsOneWidget);
  });

  testWidgets('a null panel draws nothing at all', (tester) async {
    // "Not yours" or "no team here" is not an empty list: a section titled
    // "Time spent" on a screen somebody cannot log time on is a dead control.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          eeWorklogProvider(_ticketId).overrideWith((ref) async => null),
        ],
        child: MaterialApp(
          theme: buildAwTheme(Brightness.light),
          home: const Scaffold(
            body: EeTicketWorklogSection(ticketId: _ticketId),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('worklog-add')), findsNothing);
    expect(find.byKey(const Key('worklog-empty')), findsNothing);
  });

  // ── OPH-358 (UI-AUDIT #71) ───────────────────────────────────────────────

  testWidgets(
    'UI-AUDIT #71: the day in the reader\'s format, and minutes as said — "45 dk", "1 sa 30 dk"',
    (tester) async {
      AwI18n.instance.setActiveCached(const Locale('tr'));
      addTearDown(() => AwI18n.instance.setActiveCached(const Locale('en')));
      await _pump(
        tester,
        EeWorklogPanel(
          worklogs: [
            _log(id: 'w5', minutes: 45),
            _log(id: 'w6'),
          ],
          totals: const EeWorklogTotals(
            minutes: 135,
            unpricedMinutes: 135,
            byCurrency: [],
          ),
        ),
      );
      expect(find.text('18.09.2026 — 45 dk'), findsOneWidget);
      expect(find.text('18.09.2026 — 1 sa 30 dk'), findsOneWidget);
      expect(find.text('Toplam 2 sa 15 dk'), findsOneWidget);
      expect(find.textContaining('2026-09-18'), findsNothing);
      expect(find.textContaining('0.8'), findsNothing);
    },
  );

  testWidgets(
    'UI-AUDIT #71: withdrawing an entry is a visible menu, and asks first',
    (tester) async {
      AwI18n.instance.setActiveCached(const Locale('tr'));
      addTearDown(() => AwI18n.instance.setActiveCached(const Locale('en')));
      final removed = <String>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            eeWorklogProvider(_ticketId).overrideWith(
              (ref) async => EeWorklogPanel(
                worklogs: [_log(id: 'w7')],
                totals: const EeWorklogTotals(
                  minutes: 90,
                  unpricedMinutes: 90,
                  byCurrency: [],
                ),
              ),
            ),
            eeWorklogActionsProvider(
              _ticketId,
            ).overrideWith((ref) => _Actions(ref, removed)),
          ],
          child: MaterialApp(
            theme: buildAwTheme(Brightness.light),
            home: const Scaffold(
              body: SingleChildScrollView(
                child: EeTicketWorklogSection(ticketId: _ticketId),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('worklog-menu-w7')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('worklog-remove-w7')));
      await tester.pumpAndSettle();
      expect(find.text('Bu kayıt geri çekilsin mi?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('worklog-remove-confirm')));
      await tester.pumpAndSettle();
      expect(removed, ['w7']);
    },
  );

  testWidgets(
    'UI-AUDIT #71: zero minutes is "at least one minute", not "a whole number"',
    (tester) async {
      AwI18n.instance.setActiveCached(const Locale('tr'));
      addTearDown(() => AwI18n.instance.setActiveCached(const Locale('en')));
      await _pump(tester, EeWorklogPanel.empty);
      await tester.tap(find.byKey(const Key('worklog-add')));
      await tester.pumpAndSettle();
      // The day the sheet offers is in the reader's format too.
      expect(find.textContaining('Çalışılan gün: '), findsOneWidget);
      expect(find.textContaining(RegExp(r'\d{4}-\d{2}-\d{2}')), findsNothing);
      await tester.enterText(find.byKey(const Key('worklog-minutes')), '0');
      await tester.tap(find.byKey(const Key('worklog-save')));
      await tester.pumpAndSettle();
      expect(find.text('En az 1 dakika girin.'), findsOneWidget);
      expect(find.text('Tam sayı olarak dakika girin.'), findsNothing);
    },
  );
}

class _Actions extends EeWorklogActions {
  _Actions(Ref ref, this.removed) : super(ref, _ticketId);

  final List<String> removed;

  @override
  Future<void> remove(String worklogId) async => removed.add(worklogId);
}
