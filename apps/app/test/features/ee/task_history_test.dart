import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/data/history_models.dart';
import 'package:alliswell/src/features/ee/history_providers.dart';
import 'package:alliswell/src/features/ee/ui/task_history_screen.dart';
import 'package:alliswell/src/core/date_format.dart';
import 'package:alliswell/src/core/persisted_prefs.dart';
import 'package:alliswell/src/i18n/i18n.dart';

/// EE-069 — item 10's task half, on screen.
///
/// The acceptance is a sentence about READING: "üstüne aldı / bıraktı / alt işi
/// tamamladı, saatleriyle". So this test reads the screen the way a person
/// does — three acts, three names, three times — rather than asserting that a
/// provider was called.
///
/// The tab widget is EE-026's, unchanged. What EE-069 adds is the wiring, and
/// the failure this guards against is the quiet one: a screen that renders an
/// empty list because the entity type was spelled differently at one of the
/// two ends would look exactly like a task nothing has happened to.
void main() {
  const taskId = 'T1';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('en'));
  });

  EeHistoryEvent event({
    required String id,
    required String verb,
    required String actorName,
    required DateTime at,
    Map<String, dynamic>? diff,
  }) => EeHistoryEvent(
    id: id,
    occurredAt: at,
    actor: 'user',
    actorId: 'U1',
    actorName: actorName,
    verb: verb,
    entityType: 'task',
    entityId: taskId,
    diff: diff,
  );

  Future<void> pump(WidgetTester tester, List<EeHistoryEvent> items) =>
      tester.pumpWidget(
        ProviderScope(
          overrides: [
            // Pinned so the assertion below is about the ROW carrying a time,
            // not about which of the app's date formats happens to be default.
            dateFormatProvider.overrideWith(() => _FixedFormat()),
            eeHistoryProvider.overrideWith((ref, target) async {
              // The wiring under test: the screen must ask for THIS task, by
              // the same entity type the server records against.
              expect(target.entityType, 'task');
              expect(target.entityId, taskId);
              return EeHistoryPage(items: items);
            }),
          ],
          child: const MaterialApp(home: EeTaskHistoryScreen(taskId: taskId)),
        ),
      );

  testWidgets('the three acts item 10 names all read as sentences', (
    tester,
  ) async {
    await pump(tester, [
      event(
        id: 'E3',
        verb: 'released',
        actorName: 'Barış Saha',
        at: DateTime(2026, 8, 22, 14, 05),
      ),
      event(
        id: 'E2',
        verb: 'status_changed',
        actorName: 'Barış Saha',
        at: DateTime(2026, 8, 22, 13, 40),
        diff: {
          'subtask': ['Kabloyu çek', 'done'],
        },
      ),
      event(
        id: 'E1',
        verb: 'assigned',
        actorName: 'Barış Saha',
        at: DateTime(2026, 8, 22, 9, 15),
      ),
    ]);
    await tester.pumpAndSettle();

    // Who — once per row, so the reader never has to guess whose act it was.
    expect(
      find.textContaining('Barış Saha', findRichText: true),
      findsNWidgets(3),
    );
    // What — the closed verb dictionary means every verb has a sentence.
    expect(
      find.textContaining('assigned this', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('released this', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('changed the status', findRichText: true),
      findsOneWidget,
    );
    // When — "saatleriyle" is the part of the mandate a list of verbs alone
    // would quietly drop. Rendered through the app's own formatter, so the
    // row shows the user's chosen format rather than a second one invented
    // for history.
    for (final at in [
      DateTime(2026, 8, 22, 14, 05),
      DateTime(2026, 8, 22, 13, 40),
      DateTime(2026, 8, 22, 9, 15),
    ]) {
      expect(
        find.textContaining(awFormatShort(at, format: _kFormat)),
        findsOneWidget,
        reason: 'the row must carry $at',
      );
    }
  });

  testWidgets('a task nothing has happened to says so, and does not pretend', (
    tester,
  ) async {
    await pump(tester, const []);
    await tester.pumpAndSettle();
    // EE-026's stance, inherited: an empty list is a CLAIM about the past, so
    // it has to be stated rather than shown as a blank screen.
    expect(find.byType(ListView), findsNothing);
    expect(find.textContaining('Nothing'), findsWidgets);
  });
}

/// A 24-hour format, pinned so the assertion is about the row, not the default.
const String _kFormat = 'dmy_dot';

class _FixedFormat extends PersistedChoice {
  _FixedFormat() : super('alliswell_date_format', fallback: _kFormat);

  @override
  String build() => _kFormat;
}
