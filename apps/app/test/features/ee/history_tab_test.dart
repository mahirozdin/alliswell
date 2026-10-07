import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/data/history_models.dart';
import 'package:alliswell/src/features/ee/data/ticket_write_api.dart';
import 'package:alliswell/src/features/ee/history_providers.dart';
import 'package:alliswell/src/features/ee/ticket_write_providers.dart';
import 'package:alliswell/src/features/ee/ui/history_tab.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';
import 'package:alliswell/src/widgets/status_views.dart';

/// EE-026 — the reusable history tab. What it must never do is claim
/// something about the past it has not been told: an unreachable server is an
/// ERROR, not an empty list that reads as "nothing ever happened here".
const target = (
  entityType: 'workspace',
  entityId: 'W0000000000000000000000000',
);

EeHistoryEvent event({
  String verb = 'created',
  String actor = 'user',
  String? name = 'Ada Yönetici',
  String? initials = 'AY',
  String? color = '#16A34A',
  String id = '01EVENT0000000000000000AA',
}) => EeHistoryEvent(
  id: id,
  occurredAt: DateTime.utc(2026, 8, 20, 9, 30),
  actor: actor,
  verb: verb,
  entityType: target.entityType,
  entityId: target.entityId,
  actorName: name,
  actorInitials: initials,
  actorColorRgb: color,
);

Widget harness(List<Override> overrides) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(
    theme: buildAwTheme(Brightness.light),
    home: Scaffold(
      body: EeHistoryTab(
        entityType: target.entityType,
        entityId: target.entityId,
      ),
    ),
  ),
);

Override withPage(EeHistoryPage page) =>
    eeHistoryProvider.overrideWith((ref, arg) async => page);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('en'));
  });

  testWidgets('a person, a verb and a time — no ULIDs on screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness([
        withPage(EeHistoryPage(items: [event(verb: 'archived')])),
      ]),
    );
    await tester.pumpAndSettle();

    // The row is ONE sentence (Text.rich), so assert the sentence — that is
    // what a reader actually sees.
    expect(
      find.text('Ada Yönetici archived this', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('AY'), findsOneWidget); // the roster's initials
    expect(
      find.textContaining('01EVENT', findRichText: true),
      findsNothing,
    ); // never a raw id
  });

  testWidgets('a repair is not blamed on a person', (tester) async {
    await tester.pumpWidget(
      harness([
        withPage(
          EeHistoryPage(
            items: [
              event(
                actor: 'system',
                verb: 'repaired',
                name: null,
                initials: null,
              ),
            ],
          ),
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('AllisWell repaired membership', findRichText: true),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.settings_suggest_outlined), findsOneWidget);
    expect(find.text('?'), findsNothing); // no initials invented for a sweep
  });

  testWidgets(
    'an unreachable server says so — it does not claim an empty past',
    (tester) async {
      await tester.pumpWidget(
        harness([
          eeHistoryProvider.overrideWith(
            (ref, arg) async => throw Exception('offline'),
          ),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AwErrorState), findsOneWidget);
      // The empty state would be a claim about the past we cannot make.
      expect(find.byType(AwEmptyState), findsNothing);
    },
  );

  testWidgets('a genuinely empty history says THAT, in its own words', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness([withPage(const EeHistoryPage(items: []))]),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AwEmptyState), findsOneWidget);
    expect(find.text('Nothing recorded yet'), findsOneWidget);
    expect(find.byType(AwErrorState), findsNothing);
  });

  testWidgets('a truncated page admits there is more on the server', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness([
        withPage(
          EeHistoryPage(
            items: [
              event(id: '01EVENT0000000000000000AA'),
              event(id: '01EVENT0000000000000000AB'),
            ],
            nextCursor: '01EVENT0000000000000000AB',
          ),
        ),
      ]),
    );
    await tester.pumpAndSettle();

    // A list that silently stops at the page size looks complete, and history
    // that looks complete but is not is worse than no history.
    expect(find.text('Older entries are kept on the server.'), findsOneWidget);
  });

  testWidgets('verbs and states follow the active language', (tester) async {
    AwI18n.instance.setActiveCached(const Locale('tr'));
    await tester.pumpWidget(
      harness([
        withPage(EeHistoryPage(items: [event(verb: 'member_added')])),
      ]),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Ada Yönetici bir üye ekledi', findRichText: true),
      findsOneWidget,
    );
  });

  // ── OPH-358: a request's history ─────────────────────────────────────────

  const ticketId = '01TKAAAAAAAAAAAAAAAAAAAAAA';

  EeHistoryEvent ticketEvent(
    String id,
    String verb,
    Map<String, dynamic> diff, {
    String name = 'Ayla Servis',
  }) => EeHistoryEvent(
    id: id,
    occurredAt: DateTime.utc(2026, 10, 7, 9, 30),
    actor: 'user',
    verb: verb,
    entityType: 'ee_ticket',
    entityId: ticketId,
    actorName: name,
    actorInitials: 'AS',
    diff: diff,
  );

  Widget ticketHarness(List<Override> overrides) => ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: buildAwTheme(Brightness.light),
      home: const Scaffold(
        body: EeHistoryTab(entityType: 'ee_ticket', entityId: ticketId),
      ),
    ),
  );

  testWidgets(
    'UI-AUDIT #6: a request row says who, when and WHAT moved — the status it left, and the questions an approver corrected, by their labels',
    (tester) async {
      AwI18n.instance.setActiveCached(const Locale('tr'));
      var asked = 0;
      await tester.pumpWidget(
        ticketHarness([
          withPage(
            EeHistoryPage(
              items: [
                ticketEvent('01EVENT0000000000000000A1', 'status_changed', {
                  'status': ['new', 'in_progress'],
                }),
                ticketEvent('01EVENT0000000000000000A2', 'updated', {
                  'answersChanged': ['tedarikci', 'tutar'],
                }),
                ticketEvent('01EVENT0000000000000000A3', 'status_changed', {
                  'status': ['waiting', 'in_progress'],
                  'reason': [null, 'requester_replied'],
                }, name: 'Deniz Yılmaz'),
              ],
            ),
          ),
          eeTicketActionsProvider(ticketId).overrideWith((ref) async {
            asked += 1;
            return const EeTicketActions(
              status: 'in_progress',
              priority: 'normal',
              answers: [
                EeTicketAnswer(
                  key: 'tutar',
                  label: 'Tahmini tutar (TL)',
                  type: 'number',
                  value: '15000',
                ),
                EeTicketAnswer(
                  key: 'tedarikci',
                  label: 'Tedarikçi',
                  type: 'text',
                  value: 'B',
                ),
              ],
            );
          }),
        ]),
      );
      await tester.pumpAndSettle();

      // Who did it.
      expect(
        find.textContaining('Ayla Servis', findRichText: true),
        findsWidgets,
      );
      // What moved — words, not keys.
      expect(find.text('Durum: Yeni → Devam ediyor'), findsOneWidget);
      expect(
        find.text('Form cevapları düzeltildi: Tedarikçi, Tahmini tutar (TL)'),
        findsOneWidget,
      );
      expect(
        find.text('Talep sahibi yanıtladı · Beklemede → Devam ediyor'),
        findsOneWidget,
      );
      expect(find.textContaining('in_progress'), findsNothing);
      expect(find.textContaining('tutar,'), findsNothing);
      // The labels were asked for once, because a row needed them.
      expect(asked, 1);
    },
  );

  testWidgets(
    'UI-AUDIT #6: a request history the server refuses offers a retry, and the retry asks again',
    (tester) async {
      var asked = 0;
      await tester.pumpWidget(
        ticketHarness([
          eeHistoryProvider.overrideWith((ref, arg) async {
            asked += 1;
            throw Exception('400');
          }),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AwErrorState), findsOneWidget);
      final before = asked;
      await tester.tap(
        find.descendant(
          of: find.byType(AwErrorState),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        ),
      );
      await tester.pumpAndSettle();
      expect(asked, greaterThan(before));
    },
  );
}
