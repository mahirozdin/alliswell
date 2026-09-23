import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/api_exception.dart';
import 'package:alliswell/src/core/reachability.dart';
import 'package:alliswell/src/features/ee/assignments_providers.dart';
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
  Future<void> comment(
    String ticketId, {
    required String body,
    required bool internal,
  }) async {
    if (failWith != null) throw failWith!;
    sent.add((body: body, internal: internal));
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
}
