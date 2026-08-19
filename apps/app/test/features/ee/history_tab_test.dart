import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/data/history_models.dart';
import 'package:alliswell/src/features/ee/history_providers.dart';
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
}
