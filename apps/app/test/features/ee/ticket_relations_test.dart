import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/data/ticket_links_models.dart';
import 'package:alliswell/src/i18n/i18n.dart';

import 'support/ticket_detail_harness.dart';

/// OPH-358 (UI-AUDIT #33) — the links between requests.
///
/// The report's scenario: #209 "came up again" opened #230 and linked the two
/// on the server, and neither detail showed the other; nobody could link two
/// requests by hand. These pin the half the desk sees: every request-to-
/// request link is a row, read from THIS side, opening the other; the desk
/// with `tickets.link` can add one and take one back; and "came up again"
/// goes to the request it opened.
const _other = '01TKBBBBBBBBBBBBBBBBBBBBBB';
const _third = '01TKCCCCCCCCCCCCCCCCCCCCCC';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('tr'));
  });

  final reopened = harnessTicket(
    id: _other,
    number: 230,
    subject: 'Kompresör yine durdu',
  );

  testWidgets(
    'UI-AUDIT #33: the "came up again" link shows on both requests, by number and subject, and opens the other',
    (tester) async {
      const link = EeTicketLink(
        id: '01LKAAAAAAAAAAAAAAAAAAAAAA',
        ticketId: _other,
        type: 'related',
        relatedTicketId: kHarnessTicketId,
      );
      await pumpTicketDetail(
        tester,
        ticket: harnessTicket(number: 209, status: 'resolved'),
        relations: const EeTicketRelations(links: [link]),
        others: {_other: reopened},
      );
      final row = find.byKey(Key('ticket-link-${link.id}'));
      await tester.ensureVisible(row);
      expect(
        find.descendant(
          of: row,
          matching: find.text('#230 · Kompresör yine durdu'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text('İlişkili')),
        findsOneWidget,
      );
      // Without `tickets.link` there is nothing to take back or add.
      expect(find.byKey(Key('ticket-unlink-${link.id}')), findsNothing);
      expect(find.byKey(const Key('ticket-link-add')), findsNothing);

      await tester.tap(row);
      await settleDetail(tester);
      expect(find.byKey(const Key('opened-$_other')), findsOneWidget);
    },
  );

  testWidgets(
    'UI-AUDIT #33: a directional link reads from each side, and only its maker cuts it',
    (tester) async {
      const mine = EeTicketLink(
        id: '01LKBBBBBBBBBBBBBBBBBBBBBB',
        ticketId: kHarnessTicketId,
        type: 'duplicate_of',
        relatedTicketId: _other,
      );
      const theirs = EeTicketLink(
        id: '01LKCCCCCCCCCCCCCCCCCCCCCC',
        ticketId: _third,
        type: 'child_of',
        relatedTicketId: kHarnessTicketId,
      );
      final links = FakeLinksApi();
      await pumpTicketDetail(
        tester,
        ticket: harnessTicket(),
        relations: const EeTicketRelations(links: [mine, theirs]),
        others: {_other: reopened},
        verbs: {'tickets.link'},
        links: links,
      );
      await tester.ensureVisible(find.byKey(const Key('ticket-links')));
      expect(find.text('Bunun kopyası olduğu talep'), findsOneWidget);
      expect(find.text('Alt talep'), findsOneWidget);
      // A request this device does not hold is still a row.
      expect(find.text('Bu cihazda olmayan bir talep'), findsOneWidget);
      // The claim this request made can be taken back here; the other's not.
      expect(find.byKey(Key('ticket-unlink-${mine.id}')), findsOneWidget);
      expect(find.byKey(Key('ticket-unlink-${theirs.id}')), findsNothing);

      await tester.tap(find.byKey(Key('ticket-unlink-${mine.id}')));
      await settleDetail(tester);
      expect(links.unlinked, [mine.id]);
    },
  );

  testWidgets(
    'UI-AUDIT #33: with tickets.link the desk links two requests by hand — a kind, then the request',
    (tester) async {
      final links = FakeLinksApi();
      await pumpTicketDetail(
        tester,
        ticket: harnessTicket(),
        verbs: {'tickets.link'},
        links: links,
        candidates: [harnessTicket(), reopened],
      );
      await tester.ensureVisible(find.byKey(const Key('ticket-link-add')));
      expect(find.text('Başka bir talebe bağlı değil.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('ticket-link-add')));
      await settleDetail(tester);

      // The request itself is not offered as its own link.
      expect(
        find.byKey(const Key('ticket-link-candidate-$kHarnessTicketId')),
        findsNothing,
      );
      await tester.tap(find.text('Kopyası'));
      await settleDetail(tester);
      await tester.enterText(
        find.byKey(const Key('ticket-link-search')),
        '#230',
      );
      await settleDetail(tester);
      await tester.tap(find.byKey(const Key('ticket-link-candidate-$_other')));
      await settleDetail(tester);

      expect(links.linked.single, (
        type: 'duplicate_of',
        relatedTicketId: _other,
      ));
    },
  );

  testWidgets(
    'UI-AUDIT #33: "came up again" goes to the new request it opened',
    (tester) async {
      final links = FakeLinksApi()..opened = _other;
      await pumpTicketDetail(
        tester,
        ticket: harnessTicket(number: 209, status: 'resolved'),
        verbs: {'tickets.create'},
        links: links,
      );
      await tester.ensureVisible(find.text('ee.tickets.relatedAction'.tr()));
      await tester.tap(find.text('ee.tickets.relatedAction'.tr()));
      await settleDetail(tester);
      await tester.tap(find.text('common.ok'.tr()));
      await settleDetail(tester);

      expect(find.byKey(const Key('opened-$_other')), findsOneWidget);
    },
  );
}
