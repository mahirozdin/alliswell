import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/data/kb_api.dart';
import 'package:alliswell/src/features/ee/data/kb_models.dart';
import 'package:alliswell/src/features/ee/kb_providers.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/services_providers.dart';
import 'package:alliswell/src/features/ee/ui/kb_article_screen.dart';
import 'package:alliswell/src/features/ee/ui/kb_editor_sheet.dart';
import 'package:alliswell/src/features/ee/ui/kb_screen.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/theme/theme.dart';

import '../../support/list_rhythm.dart';

/// EE-196 — the knowledge base, as the person uses it.
///
///   1. THE LIST SHOWS WIP, AND SHOWS IT FIRST. A captured question with no
///      answer is the one thing the status exists to make visible; a screen
///      that buried it would defeat the feature quietly.
///   2. A `wip` ARTICLE SAYS SO INSTEAD OF SHOWING AN EMPTY BOX. "Missing" and
///      "nobody has written it yet" are different answers to the same blank.
///   3. THE FLOW OFFERS WHAT THE SERVER ALLOWS. `wip` leads only to `draft`,
///      and `retired` leads nowhere — a button that answers 409 is the thing
///      this repo tests for by name.
///   4. THE PUBLISH GATE IS DRAWN, NOT HIDDEN. A writer without `kb.publish`
///      sees the button disabled with a reason, rather than a flow that
///      silently ends and leaves them wondering which of them is finished.
const _ws = '01WSAAAAAAAAAAAAAAAAAAAAAA';

KbArticleRecord _article(
  String id, {
  required String title,
  required String status,
  String symptom = 'Uykudan sonra ilk baskıda sıkışıyor',
  String? solution,
}) => KbArticleRecord(
  id: id,
  workspaceId: _ws,
  title: title,
  symptom: symptom,
  status: status,
  solution: solution,
  revision: 1,
  updatedAt: DateTime.utc(2026, 9, 20),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('tr'));
  });

  final rows = [
    _article(
      'K1',
      title: 'Yayında olan',
      status: 'published',
      solution: 'Bir çözüm',
    ),
    _article('K2', title: 'Açık soru', status: 'wip'),
    _article(
      'K3',
      title: 'Emekli olan',
      status: 'retired',
      solution: 'Eski çözüm',
    ),
  ];

  Future<void> pump(
    WidgetTester tester,
    Widget screen, {
    List<Override> overrides = const [],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          eeKbArticlesProvider.overrideWith((ref) => Stream.value(rows)),
          // The server's counters (OPH-358): none unless a test asks.
          eeKbArticleCountsProvider.overrideWith((ref, id) async => null),
          ...overrides,
        ],
        child: MaterialApp(
          // The real theme: EE screens read AllisWell Glass's token extension
          // and a bare theme makes them throw.
          theme: buildAwTheme(Brightness.light),
          home: screen,
        ),
      ),
    );
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpAndSettle();
  }

  testWidgets('the list shows every article, and a WIP one is not hidden', (
    tester,
  ) async {
    await pump(
      tester,
      const EeKbScreen(),
      // Overridden even though this test asserts nothing about it: the real
      // provider pulls in the auth controller and its retry timer, and a
      // pending timer fails the pump rather than the assertion.
      overrides: [canProvider('kb.write').overrideWith((ref) => true)],
    );

    for (final row in rows) {
      expect(
        find.byKey(Key('kb-row-${row.id}')),
        findsOneWidget,
        reason: '${row.status} articles belong in the list',
      );
    }
    // The status travels with every row rather than being inferred from where
    // it sits: a reader who scrolls past the WIP group must still be able to
    // tell an unreviewed answer from a published one.
    expect(find.byKey(const Key('kb-status-wip')), findsOneWidget);
    expect(find.byKey(const Key('kb-status-published')), findsOneWidget);
    // OPH-353: card rows in the list rhythm, not the full-width tiles they
    // were (DESIGN §4 has no divider-less bare rows either).
    expectCardRhythm(tester, [
      for (final row in rows) cardAround(Key('kb-row-${row.id}')),
    ]);
  });

  testWidgets('a WIP article says it has no answer yet', (tester) async {
    await pump(
      tester,
      const EeKbArticleScreen(articleId: 'K2'),
      overrides: [
        eeKbArticleProvider('K2').overrideWith((ref) => Stream.value(rows[1])),
        canProvider('kb.write').overrideWith((ref) => true),
        canProvider('kb.publish').overrideWith((ref) => false),
      ],
    );

    // Not an empty box: "missing" and "nobody has written it yet" are
    // different answers, and only one of them tells the reader whether to
    // wait or to write it.
    expect(find.text('ee.kb.noSolutionYet'.tr()), findsOneWidget);
    // `wip` leads only to `draft` — the other three statuses are not offered,
    // because the server would refuse them.
    expect(find.byKey(const Key('kb-move-draft')), findsOneWidget);
    expect(find.byKey(const Key('kb-move-approved')), findsNothing);
    expect(find.byKey(const Key('kb-move-published')), findsNothing);
    expect(find.byKey(const Key('kb-move-retired')), findsNothing);
  });

  testWidgets('without kb.publish the publish step is shown and disabled', (
    tester,
  ) async {
    final approved = _article(
      'K4',
      title: 'Onaylı',
      status: 'approved',
      solution: 'Bir çözüm',
    );
    await pump(
      tester,
      const EeKbArticleScreen(articleId: 'K4'),
      overrides: [
        eeKbArticleProvider('K4').overrideWith((ref) => Stream.value(approved)),
        canProvider('kb.write').overrideWith((ref) => true),
        canProvider('kb.publish').overrideWith((ref) => false),
      ],
    );

    // DRAWN, not hidden. A writer who cannot publish should see where the
    // flow goes and why they cannot take it — hiding the step would leave
    // them unable to tell whether the article is finished or they are.
    final publish = find.byKey(const Key('kb-move-published'));
    expect(publish, findsOneWidget);
    expect(tester.widget<FilledButton>(publish).onPressed, isNull);
    // The step they CAN take is still live, so the screen is not simply dead.
    final back = find.byKey(const Key('kb-move-draft'));
    expect(tester.widget<FilledButton>(back).onPressed, isNotNull);
  });

  testWidgets('with kb.publish the same button is live', (tester) async {
    final approved = _article(
      'K5',
      title: 'Onaylı',
      status: 'approved',
      solution: 'Bir çözüm',
    );
    await pump(
      tester,
      const EeKbArticleScreen(articleId: 'K5'),
      overrides: [
        eeKbArticleProvider('K5').overrideWith((ref) => Stream.value(approved)),
        canProvider('kb.write').overrideWith((ref) => true),
        canProvider('kb.publish').overrideWith((ref) => true),
      ],
    );

    // The two-way half: the same screen, the same article, one permission
    // apart. Without this the test above would pass against a button that is
    // disabled for everybody.
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('kb-move-published')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('a retired article offers nothing and says why', (tester) async {
    await pump(
      tester,
      const EeKbArticleScreen(articleId: 'K3'),
      overrides: [
        eeKbArticleProvider('K3').overrideWith((ref) => Stream.value(rows[2])),
        canProvider('kb.write').overrideWith((ref) => true),
        canProvider('kb.publish').overrideWith((ref) => true),
      ],
    );

    expect(find.byType(FilledButton), findsNothing);
    // Terminal is explained rather than merely empty: the reader's next
    // question is "why can I not un-retire it", and the answer is that the
    // honest exit is a new article.
    expect(find.text('ee.kb.terminal'.tr()), findsOneWidget);
    // And the edit action is gone too — the server refuses every later edit.
    expect(find.byKey(const Key('kb-edit')), findsNothing);
  });

  // ── OPH-358 ──────────────────────────────────────────────────────────────

  final published = KbArticleRecord(
    id: 'K6',
    workspaceId: _ws,
    title: 'VPN bağlantısı kopuyorsa',
    symptom: 'VPN her 10 dakikada kopuyor',
    status: 'published',
    solution: 'İstemciyi güncelleyin',
    revision: 1,
    updatedAt: DateTime.utc(2026, 9, 20),
  );

  testWidgets(
    'UI-AUDIT #75: "retire" asks first — cancelling moves nothing, confirming retires',
    (tester) async {
      final api = _FakeKbApi();
      await pump(
        tester,
        const EeKbArticleScreen(articleId: 'K6'),
        overrides: [
          eeKbArticleProvider(
            'K6',
          ).overrideWith((ref) => Stream.value(published)),
          canProvider('kb.write').overrideWith((ref) => true),
          canProvider('kb.publish').overrideWith((ref) => true),
          eeKbApiProvider.overrideWithValue(api),
        ],
      );
      await tester.tap(find.byKey(const Key('kb-move-retired')));
      await tester.pumpAndSettle();
      expect(find.text('ee.kb.retireBody'.tr()), findsOneWidget);
      await tester.tap(find.byKey(const Key('kb-retire-cancel')));
      await tester.pumpAndSettle();
      expect(api.moves, isEmpty);

      await tester.tap(find.byKey(const Key('kb-move-retired')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('kb-retire-confirm')));
      await tester.pumpAndSettle();
      expect(api.moves, ['retired']);
    },
  );

  testWidgets(
    'UI-AUDIT #38: the desk reads what the article did at the door — offered, asked anyway, prevented',
    (tester) async {
      await pump(
        tester,
        const EeKbArticleScreen(articleId: 'K6'),
        overrides: [
          eeKbArticleProvider(
            'K6',
          ).overrideWith((ref) => Stream.value(published)),
          canProvider('kb.write').overrideWith((ref) => true),
          canProvider('kb.publish').overrideWith((ref) => true),
          eeKbArticleCountsProvider('K6').overrideWith(
            (ref) async => const EeKbArticle(
              id: 'K6',
              title: 'VPN bağlantısı kopuyorsa',
              symptom: 'VPN her 10 dakikada kopuyor',
              status: 'published',
              suggestedCount: 5,
              convertedCount: 2,
              deflectedCount: 3,
            ),
          ),
        ],
      );
      expect(
        find.text(
          '5 kez önerildi · 2 kez okunup yine talep açıldı · 3 talep önlendi',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'UI-AUDIT #36: an article with no service says it is offered to nobody, and the editor sets one',
    (tester) async {
      final api = _FakeKbApi();
      await pump(
        tester,
        const EeKbArticleScreen(articleId: 'K6'),
        overrides: [
          eeKbArticleProvider(
            'K6',
          ).overrideWith((ref) => Stream.value(published)),
          canProvider('kb.write').overrideWith((ref) => true),
          canProvider('kb.publish').overrideWith((ref) => true),
          eeKbApiProvider.overrideWithValue(api),
          eeServiceGlancesProvider.overrideWithValue(const {
            'S1': EeServiceGlance(
              id: 'S1',
              name: 'Ağ ve VPN',
              hasForm: false,
              archived: false,
            ),
          }),
        ],
      );
      expect(find.byKey(const Key('kb-no-service')), findsOneWidget);

      await tester.tap(find.byKey(const Key('kb-edit')));
      await tester.pumpAndSettle();
      expect(find.text('ee.kb.fieldServiceNone'.tr()), findsOneWidget);
      await tester.tap(find.byKey(const Key('kb-field-service')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ağ ve VPN').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('kb-save')));
      await tester.pumpAndSettle();
      expect(api.patches.single, {'serviceId': 'S1'});
    },
  );

  testWidgets('UI-AUDIT #36: a new article is written with its service', (
    tester,
  ) async {
    final api = _FakeKbApi();
    await pump(
      tester,
      Consumer(
        builder: (context, ref, _) => Scaffold(
          body: TextButton(
            onPressed: () => showKbEditorSheet(context, ref),
            child: const Text('new'),
          ),
        ),
      ),
      overrides: [
        eeKbApiProvider.overrideWithValue(api),
        eeServiceGlancesProvider.overrideWithValue(const {
          'S1': EeServiceGlance(
            id: 'S1',
            name: 'Ağ ve VPN',
            hasForm: false,
            archived: false,
          ),
        }),
      ],
    );
    await tester.tap(find.text('new'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('kb-field-title')), 'VPN');
    await tester.enterText(
      find.byKey(const Key('kb-field-symptom')),
      'Kopuyor',
    );
    await tester.tap(find.byKey(const Key('kb-field-service')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ağ ve VPN').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('kb-save')));
    await tester.pumpAndSettle();
    expect(api.createdWith, ['S1']);
  });
}

/// The knowledge base's server half, recording what the screen asked.
class _FakeKbApi extends Fake implements EeKbApi {
  final moves = <String>[];
  final patches = <Map<String, dynamic>>[];
  final createdWith = <String?>[];

  EeKbArticle _article(String id, String status) =>
      EeKbArticle(id: id, title: 't', symptom: 's', status: status);

  @override
  Future<EeKbArticle> setStatus(String articleId, String status) async {
    moves.add(status);
    return _article(articleId, status);
  }

  @override
  Future<EeKbArticle> update(
    String articleId,
    Map<String, dynamic> patch,
  ) async {
    patches.add(patch);
    return _article(articleId, 'published');
  }

  @override
  Future<EeKbArticle> create({
    required String title,
    required String symptom,
    String? environment,
    String? solution,
    String? serviceId,
  }) async {
    createdWith.add(serviceId);
    return _article('K9', 'wip');
  }
}
