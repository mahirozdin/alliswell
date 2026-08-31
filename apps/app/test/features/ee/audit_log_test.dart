import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/data/history_models.dart';
import 'package:alliswell/src/features/ee/history_providers.dart';
import 'package:alliswell/src/features/ee/ui/audit_log_screen.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';

/// EE-130 — the team history screen, asserted where it would MISLEAD.
///
/// The sharpest thing about an audit screen is its empty state, because
/// "nothing here" can mean three different things and a compliance reviewer
/// acts differently on each:
///
///   • nothing has been recorded  → the team is new
///   • nothing MATCHES            → the filters are too narrow
///   • we could not ask           → the server refused, or was unreachable
///
/// Rendering all three as a blank list tells that reviewer nothing happened.
/// Each one is tested separately, and the failure case is tested hardest —
/// an empty list where an error belongs is the most misleading thing this
/// screen could do.
EeHistoryEvent _event({
  String id = 'E1',
  String verb = 'member_added',
  String actor = 'user',
  String? actorName = 'Ada Yönetici',
  String entityType = 'ee_team_member',
}) => EeHistoryEvent(
  id: id,
  occurredAt: DateTime(2026, 8, 31, 9, 5),
  actor: actor,
  verb: verb,
  entityType: entityType,
  entityId: 'X1',
  actorName: actorName,
);

Future<void> _pump(
  WidgetTester tester, {
  EeHistoryPage? page,
  Object? error,
  Brightness brightness = Brightness.light,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        eeTeamAuditProvider.overrideWith((ref, filters) async {
          if (error != null) throw error;
          return page ?? const EeHistoryPage(items: []);
        }),
      ],
      child: MaterialApp(
        theme: buildAwTheme(brightness),
        home: const EeAuditLogScreen(),
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

  group('the three empty states are three different sentences', () {
    testWidgets('AN UNREACHABLE SERVER IS AN ERROR, NOT AN EMPTY LIST', (
      tester,
    ) async {
      // The one that matters most: a blank audit screen reads as "nothing
      // happened", and that is exactly what must never be said on this screen
      // when the truth is "we could not ask".
      await _pump(tester, error: Exception('boom'));
      expect(find.byKey(const Key('audit-error')), findsOneWidget);
      expect(find.byKey(const Key('audit-empty')), findsNothing);
      expect(find.textContaining('could not be loaded'), findsOneWidget);
    });

    testWidgets('a new team is told nothing has been recorded YET', (
      tester,
    ) async {
      await _pump(tester, page: const EeHistoryPage(items: []));
      expect(find.byKey(const Key('audit-empty')), findsOneWidget);
      expect(find.textContaining('Nothing has been recorded'), findsOneWidget);
    });

    testWidgets('narrow filters are told the FILTERS matched nothing', (
      tester,
    ) async {
      await _pump(tester, page: const EeHistoryPage(items: []));
      // Pick a verb — now the empty list is a statement about the filters.
      await tester.tap(find.byKey(const Key('audit-filter-verb')));
      await tester.pumpAndSettle();
      // The dropdown shows the verb's SENTENCE, not its key.
      await tester.tap(find.text('deleted this').last);
      await tester.pumpAndSettle();

      expect(find.textContaining('No events match'), findsOneWidget);
      expect(find.textContaining('Nothing has been recorded'), findsNothing);
    });
  });

  group('the list', () {
    testWidgets('an event reads as a sentence: who, then what', (tester) async {
      await _pump(tester, page: EeHistoryPage(items: [_event()]));
      expect(find.byKey(const Key('audit-row-E1')), findsOneWidget);
      // `findRichText` because the row is a Text.rich — the actor is bold and
      // the verb is not, so the sentence is spans rather than a string.
      expect(
        find.text('Ada Yönetici added a member', findRichText: true),
        findsOneWidget,
      );
      // The verb dictionary is closed server-side precisely so every verb has
      // a sentence here; a raw key on screen means one slipped through.
      expect(find.textContaining('ee.verb.', findRichText: true), findsNothing);
    });

    testWidgets('a system actor is not blamed on the last human', (
      tester,
    ) async {
      await _pump(
        tester,
        page: EeHistoryPage(items: [_event(actor: 'system', actorName: null)]),
      );
      // Not "System": the product names itself, because a sweep is the
      // PRODUCT acting and "System" is a word every app uses for something
      // different.
      expect(
        find.text('AllisWell added a member', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('MORE ON THE SERVER IS SAID, not hidden behind a scroll', (
      tester,
    ) async {
      // An infinite scroll would let somebody believe they had reached the end
      // of the record when they had reached the end of a page.
      await _pump(
        tester,
        page: EeHistoryPage(items: [_event()], nextCursor: 'CURSOR'),
      );
      expect(find.byKey(const Key('audit-more')), findsOneWidget);
    });

    testWidgets('a complete page says nothing about more', (tester) async {
      await _pump(tester, page: EeHistoryPage(items: [_event()]));
      expect(find.byKey(const Key('audit-more')), findsNothing);
    });
  });

  group('the filters', () {
    testWidgets('clear appears only once something is filtered', (
      tester,
    ) async {
      await _pump(tester, page: EeHistoryPage(items: [_event()]));
      expect(find.byKey(const Key('audit-clear')), findsNothing);

      await tester.tap(find.byKey(const Key('audit-filter-verb')));
      await tester.pumpAndSettle();
      // The dropdown shows the verb's SENTENCE, not its key.
      await tester.tap(find.text('deleted this').last);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('audit-clear')), findsOneWidget);
    });

    testWidgets('clearing puts the screen back to no filters at all', (
      tester,
    ) async {
      // Clearing means ABSENCE, not an empty value: the family key returns to
      // the all-null record, which is a different request from `verb=''`.
      await _pump(tester, page: EeHistoryPage(items: [_event()]));
      await tester.tap(find.byKey(const Key('audit-filter-verb')));
      await tester.pumpAndSettle();
      // The dropdown shows the verb's SENTENCE, not its key.
      await tester.tap(find.text('deleted this').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('audit-clear')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('audit-clear')), findsNothing);
      expect(find.byKey(const Key('audit-row-E1')), findsOneWidget);
    });
  });
}
