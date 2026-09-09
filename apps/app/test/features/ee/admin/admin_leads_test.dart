import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/admin/admin_providers.dart';
import 'package:alliswell/src/features/ee/admin/data/admin_models.dart';
import 'package:alliswell/src/features/ee/admin/ui/admin_leads_screen.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';

/// EE-160 — the sales inbox's screens.
///
/// Two things these prove that no other gate can.
///
/// FIRST, the five statuses. The screen builds their labels by INTERPOLATION
/// (`'ee.admin.leads.status.$status'.tr()`), and `check:i18n` reads source text
/// — a key assembled at runtime is invisible to it. So a missing Turkish word
/// would ship as the raw key on an operator's screen with every gate green.
/// That is the shape of a defect this epic already shipped once, from the same
/// blind spot. Both languages are asserted, one word at a time.
///
/// SECOND, the erasure dialog. The acceptance asks it to say the outcome BY
/// NAME: an operator pressing it needs to know that the enquiry stays in the
/// list and the figures do not move, because that is the whole design of
/// EE-156's table and "Are you sure?" would leave them guessing.
Widget harness(Widget child, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: buildAwTheme(Brightness.light),
        home: Scaffold(body: child),
      ),
    );

AdminLead lead({
  String id = '01JLEAD0000000000000000001',
  String status = 'new',
  bool erased = false,
  String? company = 'Aydın Metal A.Ş.',
  int? seats = 250,
  String? message = 'Üç fabrikamız için teklif istiyoruz.',
}) => AdminLead.fromJson({
  'id': id,
  'status': status,
  'locale': 'tr',
  'erased': erased,
  'fullName': erased ? null : 'Aydın Yılmaz',
  'companyName': erased ? null : company,
  'workEmail': erased ? null : 'satinalma@aydinmetal.example',
  'phone': erased ? null : '+90 212 555 00 00',
  'seatCount': seats,
  'unitCount': 12,
  'packageInterest': 'Enterprise',
  'message': erased ? null : message,
  'notes': null,
  'consentVersion': '2026-09',
  'consentAt': '2026-09-08T10:00:00.000Z',
  'sourceIp': erased ? null : '198.51.100.44',
  'userAgent': erased ? null : 'Mozilla/5.0',
  'referrer': erased ? null : 'https://alliswell.space/enterprise/tr',
  'statusChangedAt': null,
  'erasedAt': erased ? '2026-09-09T08:00:00.000Z' : null,
  'createdAt': '2026-09-08T10:00:00.000Z',
});

List<Override> listOf(List<AdminLead> items, {String? nextCursor}) => [
  adminLeadsProvider.overrideWith(
    () => _StubLeads(AdminLeadPage(items: items, nextCursor: nextCursor)),
  ),
];

class _StubLeads extends AdminLeadsController {
  _StubLeads(this._page);
  final AdminLeadPage _page;
  @override
  Future<AdminLeadPage> build() async => _page;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('en'));
  });

  /// A surface tall enough to build the whole detail screen.
  ///
  /// Not cosmetic: a `ListView` does not create the children it cannot show,
  /// so on the default 800px surface the notes field and the erase button do
  /// not exist in the tree at all and `find` reports them missing. Three tests
  /// failed that way before this — and the failure reads exactly like "the
  /// widget is not there", which is the wrong diagnosis.
  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  group('the list', () {
    testWidgets('draws an enquiry with its company, status and seats', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(const AdminLeadsScreen(), overrides: listOf([lead()])),
      );
      await tester.pumpAndSettle();

      expect(find.text('Aydın Metal A.Ş.'), findsOneWidget);
      expect(find.textContaining('New'), findsWidgets);
      expect(find.textContaining('250 seats'), findsOneWidget);
    });

    testWidgets('says so when there is nothing, rather than showing a void', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(const AdminLeadsScreen(), overrides: listOf(const [])),
      );
      await tester.pumpAndSettle();
      expect(find.text('No enquiries yet.'), findsOneWidget);
    });

    testWidgets('no "load more" when the list has ended', (tester) async {
      // `nextCursor` null is an ANSWER: the end. Offering a button would
      // invite the operator to discover it by pressing.
      //
      // Two separate cases rather than two pumps in one: re-pumping the same
      // widget type reuses the element and its ProviderScope keeps the state
      // the first override produced, so the second half silently measured the
      // first half's list.
      await tester.pumpWidget(
        harness(const AdminLeadsScreen(), overrides: listOf([lead()])),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('admin-leads-more')), findsNothing);
    });

    testWidgets('a "load more" when the server handed back a cursor', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(
          const AdminLeadsScreen(),
          overrides: listOf([lead()], nextCursor: '01JLEAD0000000000000000001'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('admin-leads-more')), findsOneWidget);
    });

    testWidgets('an erased enquiry keeps its row and says why', (tester) async {
      // It must NOT disappear: removing it would move the funnel's own numbers
      // whenever somebody exercises a right, which is exactly what the table
      // was shaped to prevent.
      await tester.pumpWidget(
        harness(
          const AdminLeadsScreen(),
          overrides: listOf([lead(erased: true)]),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text("Erased at the sender's request"), findsOneWidget);
      expect(find.text('Aydın Metal A.Ş.'), findsNothing);
    });
  });

  group('THE FIVE STATUSES ARE TRANSLATED IN BOTH LANGUAGES', () {
    // The interpolated-key blind spot. `check:i18n` cannot see
    // `'…status.$status'.tr()`, so without this a missing word ships as the
    // raw key with every gate green.
    const english = {
      'new': 'New',
      'contacted': 'Contacted',
      'qualified': 'Qualified',
      'won': 'Won',
      'lost': 'Lost',
    };
    const turkish = {
      'new': 'Yeni',
      'contacted': 'Görüşüldü',
      'qualified': 'Nitelikli',
      'won': 'Kazanıldı',
      'lost': 'Kaybedildi',
    };

    for (final (locale, words) in [('en', english), ('tr', turkish)]) {
      testWidgets('in $locale', (tester) async {
        AwI18n.instance.setActiveCached(Locale(locale));
        await tester.pumpWidget(
          harness(
            const AdminLeadsScreen(),
            overrides: listOf([
              for (final (i, status) in kAdminLeadStatuses.indexed)
                lead(id: '01JLEAD000000000000000000$i', status: status),
            ]),
          ),
        );
        await tester.pumpAndSettle();

        for (final status in kAdminLeadStatuses) {
          expect(
            find.textContaining(words[status]!),
            findsWidgets,
            reason: '$locale is missing a word for "$status"',
          );
          // And the raw key must not be on screen anywhere — the failure mode
          // a missing translation actually produces.
          expect(
            find.textContaining('ee.admin.leads.status.'),
            findsNothing,
            reason: '$locale rendered a key instead of a word',
          );
        }
      });
    }

    test('the client list matches the five the server accepts', () {
      // Duplicated from the server's enum on purpose; held to it here so a
      // sixth state cannot appear on one side alone.
      expect(kAdminLeadStatuses, [
        'new',
        'contacted',
        'qualified',
        'won',
        'lost',
      ]);
    });
  });

  group('the detail screen', () {
    List<Override> detailOf(AdminLead value) => [
      adminLeadProvider(value.id).overrideWith((ref) async => value),
    ];

    testWidgets('shows what was asked for and who asked', (tester) async {
      tall(tester);
      final row = lead();
      await tester.pumpWidget(
        harness(
          AdminLeadDetailScreen(leadId: row.id),
          overrides: detailOf(row),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Aydın Yılmaz'), findsOneWidget);
      expect(find.text('satinalma@aydinmetal.example'), findsOneWidget);
      expect(find.text('Enterprise'), findsWidgets);
      expect(find.textContaining('teklif istiyoruz'), findsOneWidget);
      // The forensic three answer "was this real or a script", asked once,
      // here, while triaging.
      expect(find.text('198.51.100.44'), findsOneWidget);
    });

    testWidgets('AN ERASED ENQUIRY EXPLAINS ITS BLANKS', (tester) async {
      // Without the notice, a discharged legal obligation reads as a broken
      // record — the same blank a malformed row would show.
      tall(tester);
      final row = lead(erased: true);
      await tester.pumpWidget(
        harness(
          AdminLeadDetailScreen(leadId: row.id),
          overrides: detailOf(row),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('admin-lead-erased')), findsOneWidget);
      expect(
        find.textContaining("personal details were erased at the sender's"),
        findsOneWidget,
      );
      // And it says what SURVIVED, because that is the operator's next
      // question: did the figures just move?
      expect(find.textContaining('did not change the figures'), findsOneWidget);
      // The contact block is gone, and the erase button with it: there is
      // nothing left to erase.
      expect(find.text('satinalma@aydinmetal.example'), findsNothing);
      expect(find.byKey(const Key('admin-lead-erase')), findsNothing);
    });

    testWidgets('THE ERASE DIALOG NAMES THE OUTCOME, BOTH HALVES OF IT', (
      tester,
    ) async {
      tall(tester);
      final row = lead();
      await tester.pumpWidget(
        harness(
          AdminLeadDetailScreen(leadId: row.id),
          overrides: detailOf(row),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('admin-lead-erase')));
      await tester.pumpAndSettle();

      // What goes…
      expect(
        find.textContaining('name, e-mail address, phone number'),
        findsOneWidget,
      );
      // …and what stays. "Are you sure?" would leave the operator guessing
      // whether this removes the enquiry from the funnel's numbers.
      expect(find.textContaining('stays in the list'), findsOneWidget);
      expect(find.textContaining('figures do not change'), findsOneWidget);
      expect(find.textContaining('cannot be undone'), findsOneWidget);
      expect(find.byKey(const Key('admin-lead-erase-confirm')), findsOneWidget);
    });

    testWidgets('the note field says what the audit log will record', (
      tester,
    ) async {
      // The operator is told, at the point of typing, that the words stay out
      // of the history — which is the promise `admin/sales-routes.js` keeps.
      tall(tester);
      final row = lead();
      await tester.pumpWidget(
        harness(
          AdminLeadDetailScreen(leadId: row.id),
          overrides: detailOf(row),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('never what it says'), findsOneWidget);
    });
  });
}
