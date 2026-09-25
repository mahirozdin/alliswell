// The request archive, readable (EE-266, AW-E17).
//
// Run locally with:
//
//   flutter test --update-goldens --dart-define=screenshots=true \
//       test/features/ee/ticket_archive_screenshot_test.dart
//
// Inert without the dart-define, like every other shot file here.
//
// WHY THESE TWO SHOTS.
//
//   • THE ARCHIVED REQUEST. The report's scene: a manager opens a link to a
//     request that closed three months ago. The picture has to show that it
//     is read-only BEFORE it shows anything else (the strip), that the desk's
//     own note is still marked as the desk's, and that what the request left
//     behind — the answer, who approved it — came along (EE-265).
//   • THE ARCHIVE'S SEARCH. A separate screen, asked for by name, so "no
//     results" here can never be confused with the queue's device search.
//   • THE SAME REQUEST, AS THE PERSON WHO ASKED READS IT. Their words, the
//     reply as "the support desk", their own score — and none of the desk's
//     record: no note, no names, no hours, no priority. The picture is the
//     review of that allow-list.
//   • THEIR OWN ARCHIVE. "My requests", the part the sweep moved: the
//     service's name on each line, never the unit, and older pages on request.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/data/ticket_archive_api.dart';
import 'package:alliswell/src/features/ee/data/ticket_write_api.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/ticket_archive_providers.dart';
import 'package:alliswell/src/features/ee/ui/ticket_archive_screen.dart';
import 'package:alliswell/src/features/workspaces/workspaces.dart';
import 'package:alliswell/src/i18n/i18n.dart';

import '../../design_screenshots_test.dart' show screenshotLocale;
import 'support/shot.dart';

const bool _enabled = bool.fromEnvironment('screenshots');

EeArchivedTicket _ticket(bool tr) => EeArchivedTicket(
  summary: EeArchivedTicketSummary(
    id: '01JARCH1VED1042AAAAAAAAAAA',
    number: 1042,
    subject: tr ? 'Hat 3 pres yağ kaçırıyor' : 'Line 3 press is leaking oil',
    status: 'closed',
    priority: 'high',
    requesterDisplayName: 'Deniz Yılmaz',
    terminalAt: DateTime.utc(2026, 6, 20, 10),
    archivedAt: DateTime.utc(2026, 9, 18, 10),
  ),
  body: tr
      ? 'Pres 2 altında yağ birikiyor, zemin kaygan.'
      : 'Oil is pooling under press 2 and the floor is slippery.',
  serviceName: tr ? 'Hat arızası' : 'Line fault',
  slaStatus: 'met',
  answers: [
    EeTicketAnswer(
      label: tr ? 'Hangi hat?' : 'Which line?',
      type: 'select',
      value: '3',
    ),
  ],
  approvals: [
    EeArchivedApproval(
      status: 'approved',
      decidedByName: 'Ayla Yönetici',
      decidedAt: DateTime.utc(2026, 6, 19, 8),
    ),
  ],
  ratingScore: 5,
  labourMinutes: 90,
  comments: [
    EeArchivedComment(
      id: 'C1',
      authorName: 'Barış Bakım',
      body: tr
          ? 'Conta değiştirildi, sızıntı durdu. Yağ seviyesi normal.'
          : 'Seal replaced, the leak stopped. Oil level is normal.',
      internal: false,
      createdAt: DateTime.utc(2026, 6, 19, 9),
    ),
    EeArchivedComment(
      id: 'C2',
      authorName: 'Barış Bakım',
      body: tr
          ? 'Conta stoğu bitti, sipariş verildi.'
          : 'Seals are out of stock, ordered more.',
      internal: true,
      createdAt: DateTime.utc(2026, 6, 19, 9, 5),
    ),
  ],
);

const _me = '01USERMEAAAAAAAAAAAAAAAAAA';

/// #1042 as the person who asked reads it (EE-266): what the server's
/// allow-list sends them.
EeArchivedTicket _asAsker(bool tr) {
  final desk = _ticket(tr);
  return EeArchivedTicket(
    summary: desk.summary,
    viewer: 'requester',
    body: desk.body,
    serviceName: desk.serviceName,
    answers: desk.answers,
    ratingScore: 5,
    comments: [
      EeArchivedComment(
        id: 'M1',
        authorId: _me,
        body: tr
            ? 'Zemin kaygan, lütfen önce oraya bakın.'
            : 'The floor is slippery, please look there first.',
        internal: false,
        createdAt: DateTime.utc(2026, 6, 18, 8),
      ),
      EeArchivedComment(
        id: 'C1',
        authorId: 'U1',
        body: desk.comments.first.body,
        internal: false,
        createdAt: DateTime.utc(2026, 6, 19, 9),
      ),
    ],
  );
}

void main() {
  if (!_enabled) return;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(screenshotLocale('tr'));
  });

  bool tr() => AwI18n.instance.locale.languageCode == 'tr';

  List<Override> overrides({bool asker = false}) => [
    eeFeatureProvider.overrideWith((ref, name) => true),
    currentUserIdProvider.overrideWithValue(_me),
    eeArchivedTicketProvider.overrideWith(
      (ref, id) async => asker ? _asAsker(tr()) : _ticket(tr()),
    ),
    eeArchiveSearchProvider.overrideWith(
      (ref, query) async => EeArchivePage(
        tickets: [
          _ticket(tr()).summary,
          EeArchivedTicketSummary(
            id: '01JARCH1VED0987AAAAAAAAAAA',
            number: 987,
            subject: tr()
                ? 'Pres 1 hidrolik yağ değişimi'
                : 'Press 1 hydraulic oil change',
            status: 'closed',
            priority: 'normal',
            terminalAt: DateTime.utc(2026, 5, 2, 14),
          ),
        ],
      ),
    ),
  ];

  for (final brightness in Brightness.values) {
    testWidgets(
      'an archived request, opened from a link (${brightness.name})',
      (tester) async {
        await eeShoot(
          tester,
          brightness: brightness,
          name: 'ee-ticket-archived',
          size: const Size(900, 1900),
          overrides: overrides(),
          screen: const EeArchivedTicketScreen(
            ticketId: '01JARCH1VED1042AAAAAAAAAAA',
          ),
        );
      },
    );

    testWidgets('the archive, searched (${brightness.name})', (tester) async {
      await eeShoot(
        tester,
        brightness: brightness,
        name: 'ee-ticket-archive-search',
        size: const Size(900, 1000),
        overrides: overrides(),
        screen: const EeTicketArchiveSearchScreen(initialQuery: 'pres'),
      );
    });

    testWidgets(
      'the same request, as the person who asked reads it (${brightness.name})',
      (tester) async {
        await eeShoot(
          tester,
          brightness: brightness,
          name: 'ee-ticket-archived-requester',
          size: const Size(900, 1500),
          overrides: overrides(asker: true),
          screen: const EeArchivedTicketScreen(
            ticketId: '01JARCH1VED1042AAAAAAAAAAA',
          ),
        );
      },
    );

    testWidgets('their own archive (${brightness.name})', (tester) async {
      await eeShoot(
        tester,
        brightness: brightness,
        name: 'ee-my-archive',
        size: const Size(900, 900),
        overrides: [
          ...overrides(),
          eeMyArchivePageProvider.overrideWith(
            (ref, before) async => EeArchivePage(
              tickets: [
                EeArchivedTicketSummary(
                  id: '01JARCH1VED1042AAAAAAAAAAA',
                  number: 1042,
                  subject: tr()
                      ? 'Hat 3 pres yağ kaçırıyor'
                      : 'Line 3 press is leaking oil',
                  status: 'closed',
                  priority: 'high',
                  serviceName: tr() ? 'Hat arızası' : 'Line fault',
                  terminalAt: DateTime.utc(2026, 6, 20, 10),
                ),
                EeArchivedTicketSummary(
                  id: '01JARCH1VED0987AAAAAAAAAAA',
                  number: 987,
                  subject: tr()
                      ? 'Klima su damlatıyor'
                      : 'The air conditioner is dripping',
                  status: 'cancelled',
                  priority: 'normal',
                  terminalAt: DateTime.utc(2026, 5, 2, 14),
                ),
              ],
              nextCursor: '2026-05-02T14:00:00.000Z',
            ),
          ),
        ],
        screen: const EeMyArchivedTicketsScreen(),
      );
    });
  }
}
