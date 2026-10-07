import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/day_boundary.dart';
import 'package:alliswell/src/features/ee/approvals_providers.dart';
import 'package:alliswell/src/core/api_exception.dart';
import 'package:alliswell/src/features/ee/data/approvals_api.dart';
import 'package:alliswell/src/features/ee/data/approvals_models.dart';
import 'package:alliswell/src/features/ee/data/team_address_api.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/team_origin.dart';
import 'package:alliswell/src/features/ee/ui/approvals_screen.dart';
import 'package:alliswell/src/features/ee/ui/approval_detail_screen.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';

import '../../support/list_rhythm.dart';
import '../auth/test_support.dart';

/// EE-184 / EE-294 — the approvals screen, asserted where a redesign would
/// mislead.
///
///   1. NEITHER ANSWER WORKS WITHOUT A REASON. The server refuses both ways;
///      the screen refusing too keeps the person's hands on the form.
///   2. A ROW SAYS WHO ASKED, WHEN, AND WHAT FOR (the owner's report,
///      2026-09-30) — and when the target is gone, it says that.
///   3. TWO TABS, EACH WITH ITS OWN COUNT, and the counts are the rows a
///      decision can still change — not a cancelled request, not somebody
///      else's row.
///   4. NO BUTTON THE DOOR WOULD REFUSE: a decided row, a row that is not
///      mine to answer, a row nothing can change any more.
class _Fixed extends EeApprovalsController {
  _Fixed(this._items);
  final List<EeApproval> _items;
  @override
  Future<List<EeApproval>> build() async => _items;
}

final _now = DateTime(2026, 9, 30, 12);

EeApproval _approval({
  String id = 'A1',
  String status = 'pending',
  String targetType = 'ee_ticket',
  String? requestReason = 'Bütçe dışı bir parça gerekiyor',
  String? decisionReason,
  EeApprovalTarget? target = const EeApprovalTarget(
    kind: 'ee_ticket',
    title: 'Bant arızası',
    status: 'new',
    number: 1042,
  ),
  DateTime? dueAt,
  String addressedTo = 'me',
  bool? canDecide,
  bool? live,
  EeApprovalContext? context,
  EeApprovalProgress progress = const EeApprovalProgress(total: 1, pending: 1),
  String? requestedByName,
}) => EeApproval(
  id: id,
  targetType: targetType,
  targetId: 'T-$id',
  status: status,
  createdAt: _now.subtract(const Duration(hours: 2)),
  approverUserId: addressedTo == 'me' ? 'U1' : null,
  approverRoleKey: addressedTo == 'me' ? null : 'admin',
  requestReason: requestReason,
  decisionReason: decisionReason,
  dueAt: dueAt,
  target: target,
  addressedTo: addressedTo,
  canDecide: canDecide ?? status == 'pending',
  live: live ?? target != null,
  context: context,
  progress: progress,
  requestedByName: requestedByName,
);

Future<void> _pump(
  WidgetTester tester,
  List<EeApproval> items, {
  EeApprovalsSummary summary = const EeApprovalsSummary(
    authority: true,
    answersForRole: false,
    personal: 0,
    role: 0,
  ),
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        eeApprovalsProvider.overrideWith(() => _Fixed(items)),
        eeApprovalsSummaryProvider.overrideWith((ref) async => summary),
        nowProvider.overrideWithValue(() => _now),
        // The approval a row opens: quiet, so the test is about the row.
        eeApprovalDetailProvider.overrideWith(
          (ref, id) async => throw const ApiException('HTTP_404', 'gone'),
        ),
      ],
      child: MaterialApp(
        theme: buildAwTheme(Brightness.light),
        home: const EeApprovalsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('en'));
  });

  testWidgets('EE-295: every row opens its approval — a change\'s too, whose '
      'page opens the change', (tester) async {
    await _pump(tester, [
      _approval(
        id: 'A2',
        targetType: 'ee_change',
        addressedTo: 'me',
        requestReason: 'Hat 3 sunucu disk değişimi',
        target: const EeApprovalTarget(
          kind: 'ee_change',
          title: 'Hat 3 sunucu disk değişimi',
          status: 'awaiting_approval',
        ),
      ),
    ]);

    await tester.tap(find.byKey(const Key('ee-approval-open-A2')));
    await tester.pumpAndSettle();
    expect(find.byType(EeApprovalDetailScreen), findsOneWidget);
  });

  testWidgets('EE-295: a request\'s row opens too — it was a line with '
      'nowhere to go', (tester) async {
    await _pump(tester, [_approval()]);
    await tester.tap(find.byKey(const Key('ee-approval-open-A1')));
    await tester.pumpAndSettle();
    expect(find.byType(EeApprovalDetailScreen), findsOneWidget);
  });

  testWidgets('OPH-353: the rows keep the list rhythm, like every card list', (
    tester,
  ) async {
    await _pump(tester, [_approval(), _approval(id: 'A2')]);
    expectCardRhythm(tester, [
      cardAround(const Key('ee-approval-open-A1')),
      cardAround(const Key('ee-approval-open-A2')),
    ]);
  });

  testWidgets('an empty queue says nothing is waiting, not that it failed', (
    tester,
  ) async {
    await _pump(tester, const []);
    expect(find.text('Nothing is waiting on you'), findsOneWidget);
  });

  testWidgets('a row carries the kind, the number, the title and why it was '
      'asked', (tester) async {
    await _pump(tester, [_approval()]);
    expect(find.text('Request'), findsOneWidget);
    expect(find.text('#1042 · Bant arızası'), findsOneWidget);
    expect(find.text('“Bütçe dışı bir parça gerekiyor”'), findsOneWidget);
    expect(find.byKey(const Key('ee-approval-approve-A1')), findsOneWidget);
    expect(find.byKey(const Key('ee-approval-reject-A1')), findsOneWidget);
  });

  testWidgets('EE-294: a row says who asked, when, what for, and how far the '
      'signatures have got', (tester) async {
    await _pump(tester, [
      _approval(
        requestReason: 'Donanım talebi',
        requestedByName: 'Ayşe Masa',
        progress: const EeApprovalProgress(total: 2, approved: 1, pending: 1),
        context: EeApprovalContext(
          openedAt: _now.subtract(const Duration(days: 2)),
          requesterName: 'Mehmet Kaya',
          requesterKind: 'portal',
          serviceName: 'Donanım talebi',
          unitName: 'Bilgi İşlem',
          excerpt: 'Yeni başlayan çalışan için 16 GB bellekli bir dizüstü',
          priority: 'high',
        ),
      ),
    ]);

    final requester = tester.widget<Text>(
      find.byKey(const Key('ee-approval-requester-A1')),
    );
    expect(requester.data, contains('Mehmet Kaya'));
    expect(requester.data, contains('via the portal'));
    expect(requester.data, contains('time.ago.days'.tr(args: {'n': '2'})));
    expect(find.text('Donanım talebi · Bilgi İşlem · High'), findsOneWidget);
    expect(
      find.text('Yeni başlayan çalışan için 16 GB bellekli bir dizüstü'),
      findsOneWidget,
    );
    final asked = tester.widget<Text>(
      find.byKey(const Key('ee-approval-asked-A1')),
    );
    final twoHours = 'time.ago.hours'.tr(args: {'n': '2'});
    expect(asked.data, contains('Asked $twoHours'));
    expect(asked.data, contains('asked by Ayşe Masa'));
    expect(asked.data, contains('1 of 2 signed'));
    // A service rule's reason IS the service's name — said once, not twice.
    expect(find.text('“Donanım talebi”'), findsNothing);
    // The initials of somebody the approver holds no roster copy of.
    expect(find.text('MK'), findsOneWidget);
  });

  testWidgets('neither answer is possible until a reason is typed', (
    tester,
  ) async {
    await _pump(tester, [_approval()]);
    await tester.tap(find.byKey(const Key('ee-approval-approve-A1')));
    await tester.pumpAndSettle();

    final confirm = find.byKey(const Key('ee-approval-confirm'));
    expect(
      tester.widget<FilledButton>(confirm).onPressed,
      isNull,
      reason: 'the server refuses an empty reason; so does the form',
    );

    // Whitespace is not a reason either — the server trims before it checks.
    await tester.enterText(find.byKey(const Key('ee-approval-reason')), '   ');
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('ee-approval-reason')),
      'Bütçe uygun',
    );
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
  });

  testWidgets('a target that is gone says so — among the rows no decision '
      'can change, not among the work', (tester) async {
    await _pump(tester, [_approval(target: null)]);
    // Nothing live: the tab says there is nothing to decide…
    expect(find.byKey(const Key('ee-approvals-empty-me')), findsOneWidget);
    expect(find.text('What this was about is gone'), findsNothing);
    // …and the gone row waits, folded, with what it is.
    await tester.tap(find.byKey(const Key('ee-approvals-settled-me')));
    await tester.pumpAndSettle();
    expect(find.text('What this was about is gone'), findsOneWidget);
    expect(
      find.text('What this was about is gone — no decision is needed'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('ee-approval-approve-A1')), findsNothing);
  });

  testWidgets('a decided row offers no buttons, and lapsed is its own word', (
    tester,
  ) async {
    await _pump(tester, [
      _approval(
        id: 'A2',
        status: 'expired',
        decisionReason: null,
        requestReason: null,
      ),
    ]);
    expect(find.byKey(const Key('ee-approval-approve-A2')), findsNothing);
    expect(find.byKey(const Key('ee-approval-reject-A2')), findsNothing);
    // Not "rejected": nobody decided anything, and the word has to say that.
    expect(find.text('Lapsed — nobody answered in time'), findsOneWidget);
  });

  testWidgets('EE-294: two tabs, each with its own count — only what a '
      'decision can still change', (tester) async {
    await _pump(
      tester,
      [
        _approval(id: 'M1'),
        _approval(id: 'M2'),
        // Cancelled underneath: still a row, not a count.
        _approval(
          id: 'M3',
          live: false,
          target: const EeApprovalTarget(
            kind: 'ee_ticket',
            title: 'Vazgeçilen',
            status: 'cancelled',
          ),
        ),
        _approval(id: 'R1', addressedTo: 'role'),
      ],
      summary: const EeApprovalsSummary(
        authority: true,
        answersForRole: true,
        personal: 2,
        role: 1,
      ),
    );

    expect(find.byKey(const Key('ee-approvals-tab-mine')), findsOneWidget);
    expect(find.byKey(const Key('ee-approvals-tab-team')), findsOneWidget);
    Text badge(String tab) => tester.widget<Text>(
      find.descendant(
        of: find.byKey(Key('ee-approvals-badge-$tab')),
        matching: find.byType(Text),
      ),
    );
    expect(badge('mine').data, '2');
    expect(badge('team').data, '1');
    expect(find.byKey(const Key('ee-approval-approve-M1')), findsOneWidget);
    expect(find.byKey(const Key('ee-approval-approve-R1')), findsNothing);

    await tester.tap(find.byKey(const Key('ee-approvals-tab-team')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ee-approval-approve-R1')), findsOneWidget);
    // The rest of the team's queue is one folded group away, not a tab.
    expect(find.byKey(const Key('ee-approvals-others')), findsOneWidget);
  });

  testWidgets('somebody who answers for no role sees one list', (tester) async {
    await _pump(tester, [_approval()]);
    expect(find.byType(TabBar), findsNothing);
    expect(find.byKey(const Key('ee-approval-approve-A1')), findsOneWidget);
  });

  testWidgets('a row that is not mine to answer draws no buttons', (
    tester,
  ) async {
    await _pump(tester, [_approval(canDecide: false)]);
    expect(find.byKey(const Key('ee-approval-approve-A1')), findsNothing);
    expect(find.byKey(const Key('ee-approval-reject-A1')), findsNothing);
  });

  // UI-AUDIT #7 (OPH-356): the approvals list answered 404 on the service's
  // own address, and the client drew it as "nothing is waiting on you" — to
  // a person with two approvals waiting on their team's address.
  group('UI-AUDIT #7: a 404 is not an empty queue', () {
    Dio notFound() {
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
      dio.httpClientAdapter = FakeHttpClientAdapter(
        (options, body) async =>
            jsonBody(404, {'statusCode': 404, 'message': 'Not found'}),
      );
      return dio;
    }

    test('the client throws it, typed — never an empty list', () async {
      final api = EeApprovalsApi(notFound());
      await expectLater(api.list(), throwsA(isA<EeNoTeamHereException>()));
      await expectLater(api.summary(), throwsA(isA<EeNoTeamHereException>()));
    });

    Future<void> pumpOn404(WidgetTester tester, {AwTeamOrigin? origin}) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            eeFeatureProvider.overrideWith((ref, name) => true),
            eeApprovalsApiProvider.overrideWithValue(
              EeApprovalsApi(notFound()),
            ),
            eeApprovalsSummaryProvider.overrideWith(
              (ref) async => EeApprovalsSummary.none,
            ),
            teamOriginProvider.overrideWithValue(origin),
            eeTeamAddressHintProvider.overrideWithValue(
              const EeMyTeam(
                slug: 'acme',
                name: 'Demir Çelik Fabrikası',
                origin: 'https://acme.example.com',
              ),
            ),
            nowProvider.overrideWithValue(() => _now),
          ],
          child: MaterialApp(
            theme: buildAwTheme(Brightness.light),
            home: const EeApprovalsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('off the team\'s address: "your team\'s address is needed", '
        'with the way there', (tester) async {
      await pumpOn404(tester);
      expect(find.byKey(const Key('ee-team-address-required')), findsOneWidget);
      expect(find.text('Switch to acme.example.com'), findsOneWidget);
      expect(find.text('Nothing is waiting on you'), findsNothing);
    });

    testWidgets('on a team\'s address: "not in this team", not "nothing '
        'waiting"', (tester) async {
      await pumpOn404(
        tester,
        origin: teamOriginOf('https://globex.example.com', 'example.com'),
      );
      expect(find.byKey(const Key('ee-not-in-team')), findsOneWidget);
      expect(find.byKey(const Key('ee-team-address-required')), findsNothing);
    });
  });
}
