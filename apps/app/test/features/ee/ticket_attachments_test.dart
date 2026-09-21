import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/data/ticket_links_models.dart';
import 'package:alliswell/src/features/ee/kb_providers.dart';
import 'package:alliswell/src/features/ee/ticket_links_providers.dart';
import 'package:alliswell/src/features/ee/tickets_providers.dart';
import 'package:alliswell/src/features/ee/ui/ticket_detail_screen.dart';
import 'package:alliswell/src/features/files/providers.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/theme/theme.dart';
import 'package:alliswell/src/features/ee/worklog_providers.dart';

/// EE-198 — the warning half of quarantine.
///
/// The server half is tested where it lives (an anonymous download route does
/// not exist, and `portal-attachments.integration.test.js` asserts that as an
/// absence). THIS is the other direction the contract names: a unit member
/// downloads, and sees that the file came from outside.
///
///   1. THE BADGE IS ON THE EXTERNAL FILE AND ONLY ON IT. A test that only
///      checked "the warning appears" would pass against a screen that
///      warned about every attachment, which would teach people to ignore it.
///   2. THE WORDS ARE ABOUT ORIGIN, NOT SAFETY. There is no scanner in this
///      product, so the screen must not claim one.
///   3. A SERVER THAT DOES NOT ANSWER MEANS NO BADGE, NOT AN ERROR. The list
///      is an addition to a screen that already worked.
const _ticketId = '01TKAAAAAAAAAAAAAAAAAAAAAA';
const _fromOutside = '01FIAAAAAAAAAAAAAAAAAAAAAA';
const _fromColleague = '01FIBBBBBBBBBBBBBBBBBBBBBB';

TicketRecord _ticket() => TicketRecord(
  id: _ticketId,
  workspaceId: 'W1',
  subject: 'Fotoğraflı arıza',
  status: 'new',
  priority: 'normal',
  source: 'public',
  revision: 1,
  createdAt: DateTime.utc(2026, 9, 20),
);

FileAttachment _file(String id, String name) => FileAttachment(
  id: id,
  workspaceId: 'W1',
  targetType: 'ticket',
  targetId: _ticketId,
  name: name,
  mime: 'image/jpeg',
  sizeBytes: 1024,
  createdAt: DateTime.utc(2026, 9, 20),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('tr'));
  });

  final files = [
    _file(_fromOutside, 'musteri-fotografi.jpg'),
    _file(_fromColleague, 'teknisyen-notu.jpg'),
  ];

  Future<void> pump(
    WidgetTester tester, {
    required Set<String> external,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          ticketProvider(
            _ticketId,
          ).overrideWith((ref) => Stream.value(_ticket())),
          targetFilesProvider((
            targetType: 'ticket',
            targetId: _ticketId,
          )).overrideWith((ref) => Stream.value(files)),
          eeTicketExternalFilesProvider(
            _ticketId,
          ).overrideWith((ref) async => external),
          eeTicketRelationsProvider(
            _ticketId,
          ).overrideWith((ref) async => const EeTicketRelations()),
          // Everything else this screen watches, overridden so the tree has no
          // live provider left to spin on: the comment thread and the
          // knowledge section otherwise reach the auth controller, whose
          // retry timer outlives the test and fails it on teardown.
          ticketCommentsProvider(
            _ticketId,
          ).overrideWith((ref) => Stream.value(const [])),
          eeKbSuggestionsProvider(
            'Fotoğraflı arıza',
          ).overrideWith((ref) async => const []),
          eeKbOfTicketProvider(_ticketId).overrideWith((ref) async => const []),
          canProvider('kb.write').overrideWith((ref) => false),
          canProvider('tickets.convert').overrideWith((ref) => false),
          canProvider('tickets.create').overrideWith((ref) => false),
          // EE-208's section, for the reason written above it: an un-overridden
          // provider here reaches the auth controller, whose retry timer
          // outlives the test. `null` is the "not yours / no team" answer, so
          // the section draws nothing and this test stays about attachments.
          eeWorklogProvider(_ticketId).overrideWith((ref) async => null),
        ],
        child: MaterialApp(
          theme: buildAwTheme(Brightness.light),
          home: const EeTicketDetailScreen(ticketId: _ticketId),
        ),
      ),
    );
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    // Fixed pumps rather than `pumpAndSettle`: this screen carries a comment
    // thread and a history tab whose own loaders spin forever in a test with
    // no server, so "settle" never arrives. Three frames is enough for the
    // two overridden providers to resolve, and waiting for quiet would be
    // waiting for something that is not coming.
    for (var i = 0; i < 3; i += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('the badge marks the file from outside, and ONLY that one', (
    tester,
  ) async {
    await pump(tester, external: {_fromOutside});

    // Both files are listed: a warning is not a reason to hide the evidence
    // somebody sent.
    expect(find.byKey(const Key('ticket-file-$_fromOutside')), findsOneWidget);
    expect(
      find.byKey(const Key('ticket-file-$_fromColleague')),
      findsOneWidget,
    );

    // THE POINT. A screen that warned about every attachment would teach
    // people to ignore the warning, which is worse than not having one.
    expect(
      find.byKey(const Key('ticket-file-external-$_fromOutside')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('ticket-file-external-$_fromColleague')),
      findsNothing,
    );

    // And the words are about ORIGIN. There is no scanner in this product, so
    // the screen must not imply one has passed or failed.
    // The key is ON the Text, so it is read directly — `find.descendant` of a
    // Text matching Text finds nothing, which is how this assertion first
    // failed rather than passing vacuously.
    final text = tester.widget<Text>(
      find.byKey(const Key('ticket-file-external-$_fromOutside')),
    );
    expect(text.data, contains('Dışarıdan'));
    expect(text.data, contains('taranmadı'));
  });

  testWidgets('a server that says nothing means no badge, not an error', (
    tester,
  ) async {
    // An older server, or a desk without the overlay's newer half: the files
    // still draw, with no claim about any of them.
    await pump(tester, external: const {});
    expect(find.byKey(const Key('ticket-file-$_fromOutside')), findsOneWidget);
    expect(
      find.byKey(const Key('ticket-file-external-$_fromOutside')),
      findsNothing,
    );
  });
}
