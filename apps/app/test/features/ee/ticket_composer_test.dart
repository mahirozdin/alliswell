import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/api_exception.dart';
import 'package:alliswell/src/core/reachability.dart';
import 'package:alliswell/src/features/ee/assignments_providers.dart';
import 'package:alliswell/src/features/ee/changes_providers.dart';
import 'package:alliswell/src/features/ee/data/ticket_links_models.dart';
import 'package:alliswell/src/features/ee/data/ticket_write_api.dart';
import 'package:alliswell/src/features/ee/kb_providers.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/ticket_links_providers.dart';
import 'package:alliswell/src/features/ee/ticket_write_providers.dart';
import 'package:alliswell/src/features/ee/tickets_providers.dart';
import 'package:alliswell/src/features/ee/ui/ticket_composer.dart';
import 'package:alliswell/src/features/ee/ui/ticket_detail_screen.dart';
import 'package:alliswell/src/features/ee/worklog_providers.dart';
import 'package:alliswell/src/features/files/providers.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/providers.dart';
import 'package:alliswell/src/theme/theme.dart';

import 'support/ticket_detail_harness.dart';

/// EE-223 — writing on a request from the app.
///
/// The server half (`POST /comments`, who may mark a note internal) is tested
/// where it lives. These pin the half the person sees: that what they chose is
/// what is sent, that the choice is unmistakable before it is made for good,
/// and that a lost connection costs them a wait, never the paragraph.
const _ticketId = '01TKAAAAAAAAAAAAAAAAAAAAAA';

// `Fake`: the composer calls two of the API's methods, and a stand-in that
// had to restate the rest (EE-224's actions) would be a second copy of an
// interface this file does not test.
class _FakeWriteApi extends Fake implements EeTicketWriteApi {
  final sent = <({String body, bool internal})>[];
  Object? failWith;

  @override
  Future<String?> comment(
    String ticketId, {
    required String body,
    required bool internal,
  }) async {
    if (failWith != null) throw failWith!;
    sent.add((body: body, internal: internal));
    return '01CMAAAAAAAAAAAAAAAAAAAAA${sent.length}';
  }

  @override
  Future<List<EeCannedReply>> cannedReplies(String ticketId) async => const [];
}

const _canned = [
  EeCannedReply(
    id: 'C1',
    name: 'Parça bekleniyor',
    text: 'Parça siparişi verildi, gelince haber vereceğiz.',
  ),
];

void main() {
  late _FakeWriteApi api;
  late ProviderContainer container;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('tr'));
    api = _FakeWriteApi();
  });

  List<Override> composerOverrides() => [
    eeTicketWriteApiProvider.overrideWithValue(api),
    eeCannedRepliesProvider(_ticketId).overrideWith((ref) async => _canned),
    // No engine in a widget test; the composer's pull request is a no-op.
    syncEngineProvider.overrideWithValue(null),
  ];

  /// The composer alone, in a container the test can reach — the draft and
  /// the reachability signal both live in providers, and the tests move them.
  Future<void> pumpComposer(WidgetTester tester, {bool mounted = true}) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAwTheme(Brightness.light),
          home: Scaffold(
            body: SingleChildScrollView(
              child: mounted
                  ? const EeTicketComposer(ticketId: _ticketId)
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder field() => find.byKey(const Key('ticket-composer-text'));
  Finder send() => find.byKey(const Key('ticket-composer-send'));
  bool enabled(WidgetTester tester, Finder finder) =>
      tester.widget<ButtonStyleButton>(finder).onPressed != null;

  group('the composer', () {
    setUp(() => container = ProviderContainer(overrides: composerOverrides()));
    tearDown(() => container.dispose());

    testWidgets('a reply goes to the requester, and says so first', (
      tester,
    ) async {
      await pumpComposer(tester);
      expect(find.text('Bunu talep sahibi okur.'), findsOneWidget);
      expect(find.text('Talep sahibine gönder'), findsOneWidget);
      expect(enabled(tester, send()), isFalse, reason: 'nothing to send yet');

      await tester.enterText(field(), 'Yarın sabah bakacağız.');
      await tester.pump();
      await tester.tap(send());
      await tester.pumpAndSettle();

      expect(api.sent, [(body: 'Yarın sabah bakacağız.', internal: false)]);
      expect(find.text('Yanıt gönderildi'), findsOneWidget);
      expect(tester.widget<TextField>(field()).controller!.text, isEmpty);
    });

    testWidgets('an internal note wears all three signals before it is sent', (
      tester,
    ) async {
      await pumpComposer(tester);
      await tester.tap(find.text('İç not'));
      await tester.pumpAndSettle();

      // The surface, the lock and the word — EE-084's three, on the box.
      final card = tester.widget<Card>(
        find.byKey(const Key('ticket-composer')),
      );
      final scheme = Theme.of(
        tester.element(find.byKey(const Key('ticket-composer'))),
      ).colorScheme;
      expect(card.color, scheme.surfaceContainerHighest);
      expect(
        find.descendant(
          of: find.byKey(const Key('ticket-composer')),
          matching: find.byIcon(Icons.lock_outline),
        ),
        findsWidgets,
      );
      expect(
        find.text('Bunu yalnız ekibin okur — talep sahibi asla.'),
        findsOneWidget,
      );
      expect(find.text('İç not olarak ekle'), findsOneWidget);

      await tester.enterText(field(), 'Müşteri üçüncü kez arıyor.');
      await tester.pump();
      await tester.tap(send());
      await tester.pumpAndSettle();
      expect(api.sent.single.internal, isTrue);
      expect(find.text('İç not eklendi'), findsOneWidget);
    });

    testWidgets('the kind can change until the send, and what shows is sent', (
      tester,
    ) async {
      await pumpComposer(tester);
      await tester.enterText(field(), 'Aslında bu bir yanıt.');
      await tester.tap(find.text('İç not'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yanıt'));
      await tester.pumpAndSettle();
      await tester.tap(send());
      await tester.pumpAndSettle();
      expect(api.sent.single, (body: 'Aslında bu bir yanıt.', internal: false));
    });

    testWidgets('a saved reply is ADDED to the text, and nothing is sent', (
      tester,
    ) async {
      await pumpComposer(tester);
      await tester.enterText(field(), 'Merhaba,');
      await tester.tap(find.byKey(const Key('ticket-composer-canned')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('canned-C1')));
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(field()).controller!.text,
        'Merhaba,\n\nParça siparişi verildi, gelince haber vereceğiz.',
      );
      expect(api.sent, isEmpty, reason: 'sending is still the person');
    });

    testWidgets(
      'offline: disabled BEFORE the tap, with the reason, text kept',
      (tester) async {
        await pumpComposer(tester);
        await tester.enterText(field(), 'Yarım kalan bir cümle');
        await tester.pump();

        container.read(serverReachabilityProvider.notifier).unreachable();
        await tester.pumpAndSettle();

        expect(tester.widget<TextField>(field()).enabled, isFalse);
        expect(enabled(tester, send()), isFalse);
        expect(
          find.byKey(const Key('ticket-composer-offline')),
          findsOneWidget,
        );
        expect(
          tester.widget<TextField>(field()).controller!.text,
          'Yarım kalan bir cümle',
        );

        // The next answer from the server — a sync pull, in the app — and the
        // box is back, with the sentence still in it.
        container.read(serverReachabilityProvider.notifier).answered();
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(field()).enabled, isTrue);
        expect(find.byKey(const Key('ticket-composer-offline')), findsNothing);
        await tester.tap(send());
        await tester.pumpAndSettle();
        expect(api.sent.single.body, 'Yarım kalan bir cümle');
      },
    );

    testWidgets('a send that got no answer keeps the text and says why', (
      tester,
    ) async {
      api.failWith = const ApiException('NETWORK_ERROR', 'no answer');
      await pumpComposer(tester);
      await tester.enterText(field(), 'Gitmedi ama kaybolmadı');
      await tester.pump();
      await tester.tap(send());
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(field()).controller!.text,
        'Gitmedi ama kaybolmadı',
      );
      expect(find.byKey(const Key('ticket-composer-offline')), findsOneWidget);
    });

    testWidgets(
      'AW-E03: offline, the box says the reply does not go on its own — no queue is promised (EE-283)',
      (tester) async {
        api.failWith = const ApiException('NETWORK_ERROR', 'no answer');
        await pumpComposer(tester);
        await tester.enterText(field(), 'Bekleyen yanıt');
        await tester.pump();
        await tester.tap(send());
        await tester.pumpAndSettle();

        expect(
          find.textContaining('kendiliğinden gönderilmez'),
          findsOneWidget,
        );
        expect(
          find.textContaining('bağlantı gelene kadar bekler'),
          findsNothing,
        );
      },
    );

    testWidgets('backing out does not lose what was typed', (tester) async {
      await pumpComposer(tester);
      await tester.enterText(field(), 'Sonra devam ederim');
      await tester.tap(find.text('İç not'));
      await tester.pumpAndSettle();

      await pumpComposer(tester, mounted: false); // the screen is gone
      await pumpComposer(tester); // and back

      expect(
        tester.widget<TextField>(field()).controller!.text,
        'Sonra devam ederim',
      );
      expect(find.text('İç not olarak ekle'), findsOneWidget);
    });
  });

  group('on the request', () {
    TicketRecord ticket({DateTime? terminalAt}) => TicketRecord(
      id: _ticketId,
      workspaceId: 'W1',
      subject: 'Kompresör arızası',
      status: terminalAt == null ? 'in_progress' : 'closed',
      priority: 'high',
      source: 'app',
      revision: 1,
      createdAt: DateTime.utc(2026, 9, 20),
      terminalAt: terminalAt,
    );

    Future<void> pumpDetail(
      WidgetTester tester, {
      required bool canComment,
      DateTime? terminalAt,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            ...composerOverrides(),
            ticketProvider(_ticketId).overrideWith(
              (ref) => Stream.value(ticket(terminalAt: terminalAt)),
            ),
            ticketCommentsProvider(
              _ticketId,
            ).overrideWith((ref) => Stream.value(const [])),
            targetFilesProvider((
              targetType: 'ticket',
              targetId: _ticketId,
            )).overrideWith((ref) => Stream.value(const [])),
            eeTicketRelationsProvider(
              _ticketId,
            ).overrideWith((ref) async => const EeTicketRelations()),
            // EE-279's section, quiet: this test is about something else.
            eeChangesRaisedFromProvider(
              _ticketId,
            ).overrideWith((ref) async => const []),
            canProvider('changes.create').overrideWith((ref) => false),
            canProvider('problems.manage').overrideWith((ref) => false),
            canProvider('tickets.link').overrideWith((ref) => false),
            eeKbSuggestionsProvider(
              'Kompresör arızası',
            ).overrideWith((ref) async => const []),
            eeKbOfTicketProvider(
              _ticketId,
            ).overrideWith((ref) async => const []),
            eeWorklogProvider(_ticketId).overrideWith((ref) async => null),
            // EE-224's "who is on it" row reads the device's copy.
            ticketAssigneesForProvider(
              _ticketId,
            ).overrideWith((ref) => Stream.value(const [])),
            workspaceRosterOfProvider.overrideWith(
              (ref, workspaceId) => Stream.value(const []),
            ),
            canProvider('kb.write').overrideWith((ref) => false),
            canProvider('tickets.convert').overrideWith((ref) => false),
            canProvider('tickets.create').overrideWith((ref) => false),
            canProvider('tickets.comment').overrideWith((ref) => canComment),
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
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('without tickets.comment there is no box at all (not a 403)', (
      tester,
    ) async {
      await pumpDetail(tester, canComment: false);
      expect(find.byKey(const Key('ticket-composer')), findsNothing);
      expect(find.byKey(const Key('ticket-composer-closed')), findsNothing);
    });

    testWidgets('with it, the box sits under the conversation', (tester) async {
      await pumpDetail(tester, canComment: true);
      expect(find.byKey(const Key('ticket-composer')), findsOneWidget);
    });

    testWidgets('a closed request says its thread is closed instead', (
      tester,
    ) async {
      await pumpDetail(
        tester,
        canComment: true,
        terminalAt: DateTime.utc(2026, 9, 21),
      );
      expect(find.byKey(const Key('ticket-composer')), findsNothing);
      expect(find.byKey(const Key('ticket-composer-closed')), findsOneWidget);
    });
  });

  // ── OPH-358 ──────────────────────────────────────────────────────────────

  group('OPH-358: who wrote, where it goes, and whose portal shows it', () {
    const desk = '01USDESKAAAAAAAAAAAAAAAAAA';
    const asker = '01USASKERAAAAAAAAAAAAAAAAA';

    testWidgets(
      'UI-AUDIT #21: every reply names its author, side and channel, and sits on its side',
      (tester) async {
        await pumpTicketDetail(
          tester,
          ticket: harnessTicket(
            source: 'email',
            requesterEmail: 'deniz@ornek.com',
          ),
          comments: [
            harnessComment('C1', authorId: desk, body: 'Bakıyoruz.'),
            harnessComment('C2', body: 'Etkilenen 3 adet.'),
          ],
          relations: const EeTicketRelations(
            commentMeta: {
              'C1': EeCommentMeta(
                commentId: 'C1',
                side: 'desk',
                channel: 'app',
                authorName: 'Kerem Bakım',
              ),
              'C2': EeCommentMeta(
                commentId: 'C2',
                side: 'requester',
                channel: 'email',
                authorName: 'Deniz Yılmaz',
              ),
            },
          ),
        );
        Text author(String id) =>
            tester.widget<Text>(find.byKey(Key('ticket-comment-author-$id')));
        expect(author('C1').data, 'Kerem Bakım · Masa');
        expect(author('C2').data, 'Deniz Yılmaz · Talep sahibi · e-posta');
        // The desk's words at the end, the other party's at the start.
        expect(
          tester
              .widget<Align>(find.byKey(const Key('ticket-comment-align-C1')))
              .alignment,
          AlignmentDirectional.centerEnd,
        );
        expect(
          tester
              .widget<Align>(find.byKey(const Key('ticket-comment-align-C2')))
              .alignment,
          AlignmentDirectional.centerStart,
        );
      },
    );

    testWidgets(
      'UI-AUDIT #21: a server that sends no meta still names a colleague from the roster — and guesses no side',
      (tester) async {
        await pumpTicketDetail(
          tester,
          ticket: harnessTicket(),
          comments: [harnessComment('C1', authorId: desk, body: 'Bakıyoruz.')],
          names: const {desk: 'Kerem Bakım'},
        );
        expect(
          tester
              .widget<Text>(find.byKey(const Key('ticket-comment-author-C1')))
              .data,
          'Kerem Bakım',
        );
        expect(find.byKey(const Key('ticket-comment-align-C1')), findsNothing);
      },
    );

    testWidgets(
      'UI-AUDIT #21: the person who asked writes to the desk, not "to the requester"',
      (tester) async {
        await pumpTicketDetail(
          tester,
          ticket: harnessTicket(requesterId: asker),
          me: asker,
          verbs: {'tickets.comment'},
        );
        await tester.ensureVisible(find.byKey(const Key('ticket-composer')));
        expect(find.text('Masaya yaz'), findsOneWidget);
        expect(find.text('Bunu masa okur.'), findsOneWidget);
        expect(find.text('Bunu talep sahibi okur.'), findsNothing);
      },
    );

    testWidgets(
      'UI-AUDIT #21: on a request that came by mail the box says the reply leaves as mail',
      (tester) async {
        await pumpTicketDetail(
          tester,
          ticket: harnessTicket(
            source: 'email',
            requesterEmail: 'deniz@ornek.com',
          ),
          verbs: {'tickets.comment'},
        );
        await tester.ensureVisible(find.byKey(const Key('ticket-composer')));
        expect(
          find.byKey(const Key('ticket-composer-by-email')),
          findsOneWidget,
        );
        // An internal note goes nowhere outside, and says nothing of mail.
        await tester.tap(find.text('İç not'));
        await settleDetail(tester);
        expect(find.byKey(const Key('ticket-composer-by-email')), findsNothing);
      },
    );

    testWidgets(
      'UI-AUDIT #48: the company the request is filed under, that its portal shows it, and the picker for customers.manage',
      (tester) async {
        final links = FakeLinksApi();
        await pumpTicketDetail(
          tester,
          ticket: harnessTicket(),
          relations: const EeTicketRelations(
            customerId: '01CUAAAAAAAAAAAAAAAAAAAAAA',
            customerName: 'Anadolu Otomotiv',
            customerKnown: true,
          ),
          verbs: {'customers.manage', 'tickets.comment'},
          links: links,
        );
        expect(find.text('Firma: Anadolu Otomotiv'), findsOneWidget);
        expect(
          find.textContaining('firmanın portalında görünür'),
          findsOneWidget,
        );
        // And the reply box says the reply shows there too.
        await tester.ensureVisible(find.byKey(const Key('ticket-composer')));
        expect(
          find.byKey(const Key('ticket-composer-customer')),
          findsOneWidget,
        );

        await tester.ensureVisible(
          find.byKey(const Key('ticket-customer-change')),
        );
        await tester.tap(find.byKey(const Key('ticket-customer-change')));
        await settleDetail(tester);
        await tester.tap(find.byKey(const Key('ticket-customer-clear')));
        await settleDetail(tester);
        expect(links.customersSet, [null]);
      },
    );

    testWidgets(
      'UI-AUDIT #48: a server that does not say draws no company line; one that says "none" offers the link only with the verb',
      (tester) async {
        await pumpTicketDetail(
          tester,
          ticket: harnessTicket(),
          verbs: {'customers.manage'},
        );
        expect(find.byKey(const Key('ticket-customer')), findsNothing);
      },
    );

    testWidgets(
      'UI-AUDIT #48: an unfiled request is linked to a company from the picker',
      (tester) async {
        final links = FakeLinksApi();
        await pumpTicketDetail(
          tester,
          ticket: harnessTicket(),
          relations: const EeTicketRelations(customerKnown: true),
          verbs: {'customers.manage'},
          links: links,
        );
        expect(find.text('Bir firmaya bağlı değil'), findsOneWidget);
        await tester.tap(find.byKey(const Key('ticket-customer-change')));
        await settleDetail(tester);
        await tester.tap(
          find.byKey(
            const Key('ticket-customer-choice-01CUAAAAAAAAAAAAAAAAAAAAAA'),
          ),
        );
        await settleDetail(tester);
        expect(links.customersSet, ['01CUAAAAAAAAAAAAAAAAAAAAAA']);
      },
    );

    testWidgets(
      'UI-AUDIT #48: without customers.manage the company is read, not changed',
      (tester) async {
        await pumpTicketDetail(
          tester,
          ticket: harnessTicket(),
          relations: const EeTicketRelations(
            customerId: '01CUAAAAAAAAAAAAAAAAAAAAAA',
            customerName: 'Anadolu Otomotiv',
            customerKnown: true,
          ),
        );
        expect(find.text('Firma: Anadolu Otomotiv'), findsOneWidget);
        expect(find.byKey(const Key('ticket-customer-change')), findsNothing);
      },
    );

    testWidgets(
      'UI-AUDIT #34: a file picked for an internal note is uploaded onto THAT note, in the request\'s unit',
      (tester) async {
        final uploads = _RecordingUploads();
        final write = FakeThreadWriteApi();
        await pumpTicketDetail(
          tester,
          ticket: harnessTicket(),
          verbs: {'tickets.comment'},
          write: write,
          extra: [
            uploadsProvider.overrideWith(() => uploads),
            attachSourcesProvider.overrideWithValue(const [
              AttachSource.anyFile,
            ]),
            filePickerProvider.overrideWithValue(
              (source) async => [
                PickedUpload.fromBytes(
                  name: 'olcum.pdf',
                  bytes: harnessBytes(),
                ),
              ],
            ),
          ],
        );
        await tester.ensureVisible(find.byKey(const Key('ticket-composer')));
        await tester.tap(find.text('İç not'));
        await settleDetail(tester);
        await tester.tap(find.byKey(const Key('ticket-composer-attach')));
        await settleDetail(tester);
        expect(find.text('olcum.pdf'), findsOneWidget);
        // The note's files are the desk's, and the box says so.
        expect(find.textContaining('yalnız masa görür'), findsOneWidget);
        await tester.enterText(
          find.byKey(const Key('ticket-composer-text')),
          'Ölçüm ekte.',
        );
        await settleDetail(tester);
        await tester.ensureVisible(
          find.byKey(const Key('ticket-composer-send')),
        );
        await settleDetail(tester);
        expect(
          tester
              .widget<ButtonStyleButton>(
                find.byKey(const Key('ticket-composer-send')),
              )
              .onPressed,
          isNotNull,
        );
        await tester.tap(find.byKey(const Key('ticket-composer-send')));
        await settleDetail(tester);

        expect(write.sent.single, (body: 'Ölçüm ekte.', internal: true));
        expect(uploads.started.single, (
          workspaceId: 'W1',
          targetType: 'ticket_comment',
          targetId: '01CMNEWAAAAAAAAAAAAAAAAAAA',
        ));
      },
    );

    testWidgets('UI-AUDIT #34: a reply\'s files show under it', (tester) async {
      await pumpTicketDetail(
        tester,
        ticket: harnessTicket(),
        comments: [harnessComment('C1', authorId: desk)],
        commentFiles: {
          'C1': [
            FileAttachment(
              id: 'F1',
              workspaceId: 'W1',
              targetType: 'ticket_comment',
              targetId: 'C1',
              name: 'olcum.pdf',
              mime: 'application/pdf',
              sizeBytes: 3,
              createdAt: DateTime.utc(2026, 10, 7),
            ),
          ],
        },
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('ticket-comment-C1')),
          matching: find.text('olcum.pdf'),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'UI-AUDIT #73: a cancelled request says it was cancelled, a closed one that it closed',
      (tester) async {
        await pumpTicketDetail(
          tester,
          ticket: harnessTicket(
            status: 'cancelled',
            terminalAt: DateTime(2026, 10, 7, 12),
          ),
        );
        expect(
          tester
              .widget<Text>(
                find.descendant(
                  of: find.byKey(const Key('ticket-terminal-on')),
                  matching: find.byType(Text),
                ),
              )
              .data,
          '07.10.2026 tarihinde iptal edildi',
        );
      },
    );
  });
}

/// Core's upload walk, recording which file went onto which target.
class _RecordingUploads extends UploadsNotifier {
  final started =
      <({String workspaceId, String targetType, String targetId})>[];

  @override
  Future<String?> start({
    required String workspaceId,
    required String targetType,
    required String targetId,
    String? folderId,
    required PickedUpload source,
  }) async {
    started.add((
      workspaceId: workspaceId,
      targetType: targetType,
      targetId: targetId,
    ));
    return 'F-${started.length}';
  }
}
