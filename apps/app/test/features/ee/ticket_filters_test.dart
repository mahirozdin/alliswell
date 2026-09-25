import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/assignments_providers.dart'
    show Assignee;
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/tickets_providers.dart';
import 'package:alliswell/src/features/ee/ui/ticket_queue_screen.dart';
import 'package:alliswell/src/features/workspaces/workspaces.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/theme/theme.dart';

/// EE-171 — the filter row, as the person uses it.
///
/// The predicates themselves are proved against the real providers in
/// `tickets_offline_test.dart`; what THIS file proves is the half a provider
/// test cannot see: that a chip is wired to the notifier, that picking one
/// narrows the list on screen, that picking two narrows it further rather than
/// one winning, and that the two "who is on it" chips turn each other off —
/// because a filter that cannot be unpicked is one the person has to leave the
/// screen to clear (DESIGN §16's invisible filter, read on a chip row).
const _me = '01USAAAAAAAAAAAAAAAAAAAAAA';

TicketRecord _ticket(
  String id, {
  required String subject,
  String status = 'new',
  String priority = 'normal',
  String source = 'internal',
  String? slaStatus,
  String? processType,
  String? tagNames,
}) => TicketRecord(
  id: id,
  workspaceId: 'W1',
  subject: subject,
  status: status,
  priority: priority,
  source: source,
  slaStatus: slaStatus,
  processType: processType,
  tagNames: tagNames,
  revision: 1,
  createdAt: DateTime.utc(2026, 8, 10),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('tr'));
  });

  final rows = [
    _ticket(
      'T1',
      subject: 'İhlal edilmiş',
      slaStatus: 'breached',
      processType: 'incident',
      tagNames: '["Garanti","Hidrolik"]',
    ),
    _ticket(
      'T2',
      subject: 'Portaldan gelen',
      source: 'public',
      processType: 'request',
      tagNames: '["Garanti"]',
    ),
    // Pulled before the replica had the column: no kind yet.
    _ticket('T3', subject: 'Kimsede olmayan'),
  ];

  /// T1 is on me; the other two are on nobody.
  const assignees = {
    'T1': [
      Assignee(
        assignmentId: 'A1',
        userId: _me,
        displayName: 'Ayla',
        initials: 'A',
        colorRgb: '#2563EB',
      ),
    ],
  };

  Future<void> pumpQueue(WidgetTester tester, {bool mayCreate = false}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ticketQueueProvider.overrideWith((ref) => Stream.value(rows)),
          ticketAssigneesProvider.overrideWith(
            (ref) => Stream.value(assignees),
          ),
          currentUserIdProvider.overrideWithValue(_me),
          // EE-225's "new request" button asks the permission cache, which
          // would otherwise go looking for a session (and leave its timer
          // running past the test).
          canProvider.overrideWith(
            (ref, permission) => mayCreate && permission == 'tickets.create',
          ),
        ],
        child: MaterialApp(
          // The real theme, not a bare MaterialApp: the row's priority mark
          // and SLA chip read AllisWell Glass's token extension and a plain
          // theme makes them throw. A widget test of a screen has to build the
          // screen the product builds.
          theme: buildAwTheme(Brightness.light),
          home: const EeTicketQueueScreen(),
        ),
      ),
    );
    // A phone-sized surface: the default 800x600 test window makes the queue's
    // list tile complain that its leading widget fills the row.
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpAndSettle();
  }

  /// The chip row scrolls horizontally, so a chip further along is laid out but
  /// outside the viewport — and a tap on one of those lands on whatever IS at
  /// that point, silently. Scrolling it into view first is what makes the tap
  /// the gesture the person makes.
  Future<void> tapChip(WidgetTester tester, String key) async {
    final finder = find.byKey(Key(key));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Iterable<String> visible(WidgetTester tester) => rows
      .map((t) => t.id)
      .where((id) => find.byKey(Key('ticket-$id')).evaluate().isNotEmpty);

  testWidgets('a chip narrows the queue, and two narrow it together', (
    tester,
  ) async {
    await pumpQueue(tester);
    expect(visible(tester), ['T1', 'T2', 'T3']);

    await tapChip(tester, 'ticket-filter-sla-breached');
    expect(visible(tester), ['T1']);

    // A second chip that excludes the first leaves nothing — the filters AND,
    // they do not race. The screen then says which emptiness this is.
    await tapChip(tester, 'ticket-filter-source-public');
    expect(visible(tester), isEmpty);
    expect(find.byKey(const Key('ticket-search-empty')), findsNothing);
  });

  testWidgets('EE-268 (AW-E21): "only incidents" keeps the incidents — and a '
      'request the device has no kind for stays out rather than guessed', (
    tester,
  ) async {
    await pumpQueue(tester);
    await tapChip(tester, 'ticket-filter-type-incident');
    expect(visible(tester), ['T1']);
    // Both kinds: everything that HAS a kind, still not the unknown one.
    await tapChip(tester, 'ticket-filter-type-request');
    expect(visible(tester), ['T1', 'T2']);
    // Off again, the queue is whole.
    await tapChip(tester, 'ticket-filter-type-incident');
    await tapChip(tester, 'ticket-filter-type-request');
    expect(visible(tester), ['T1', 'T2', 'T3']);
  });

  testWidgets('EE-235: a tag narrows the queue with no signal — its choices '
      'are the words on the desk\'s own rows, and tapping it again clears it', (
    tester,
  ) async {
    await pumpQueue(tester);
    await tapChip(tester, 'ticket-filter-tag');
    // Each word once, from the rows this device holds.
    expect(
      find.byKey(const Key('ticket-filter-tag-option-Garanti')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('ticket-filter-tag-option-Hidrolik')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const Key('ticket-filter-tag-option-Hidrolik')),
    );
    await tester.pumpAndSettle();
    expect(visible(tester), ['T1']);
    expect(find.text('Etiket: Hidrolik'), findsOneWidget);

    await tapChip(tester, 'ticket-filter-tag');
    expect(visible(tester), ['T1', 'T2', 'T3']);

    // A word on two rows keeps both, and a row with no words stays out.
    await tapChip(tester, 'ticket-filter-tag');
    await tester.tap(find.byKey(const Key('ticket-filter-tag-option-Garanti')));
    await tester.pumpAndSettle();
    expect(visible(tester), ['T1', 'T2']);
  });

  testWidgets(
    '"on me" and "on nobody" are the two questions, and they toggle',
    (tester) async {
      await pumpQueue(tester);

      await tapChip(tester, 'ticket-filter-mine');
      expect(visible(tester), ['T1']);

      // The costliest state a queue has, and the one that is invisible until
      // something asks for it.
      await tapChip(tester, 'ticket-filter-unassigned');
      expect(visible(tester), ['T2', 'T3']);

      // Tapping the one that is already on turns it OFF rather than doing
      // nothing: the two are mutually exclusive, so there is no other way back.
      await tapChip(tester, 'ticket-filter-unassigned');
      expect(visible(tester), ['T1', 'T2', 'T3']);
    },
  );

  // EE-225: the queue is where the desk already stands, so it is one of the
  // two ways in to filing a request — for whoever may file one, and nobody
  // else (a button that leads to a form the door refuses is a dead one).
  testWidgets('the queue offers a new request to whoever may file one', (
    tester,
  ) async {
    await pumpQueue(tester, mayCreate: true);
    expect(find.byKey(const Key('ticket-new')), findsOneWidget);
  });

  testWidgets('…and no button at all to whoever may not', (tester) async {
    await pumpQueue(tester);
    expect(find.byKey(const Key('ticket-new')), findsNothing);
  });
}
