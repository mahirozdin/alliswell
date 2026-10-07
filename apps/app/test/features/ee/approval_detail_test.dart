import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/api_exception.dart';
import 'package:alliswell/src/core/day_boundary.dart';
import 'package:alliswell/src/core/error_messages.dart';
import 'package:alliswell/src/features/ee/approvals_providers.dart';
import 'package:alliswell/src/features/ee/data/approvals_api.dart';
import 'package:alliswell/src/features/ee/data/approvals_models.dart';
import 'package:alliswell/src/features/ee/data/changes_models.dart';
import 'package:alliswell/src/features/ee/data/new_ticket_api.dart';
import 'package:alliswell/src/features/ee/data/ticket_write_api.dart';
import 'package:alliswell/src/features/ee/ui/approval_detail_screen.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';

/// EE-295 — the approver's window onto what they are asked to decide.
///
/// The owner (2026-09-30): "the approver sees every detail of the request —
/// the internal notes and their files too — and may correct what was written
/// wrongly before approving; the correction lands in the request's history".
///
///   1. THE WINDOW IS WHOLE for the approver: who asked and when, the text,
///      the answers, the files and the conversation, internal ones marked.
///   2. SOMEBODY NOT ASKED IS TOLD SO, and reads the summary.
///   3. A CORRECTION SENDS WHAT CHANGED, and a required answer cannot be
///      emptied on the way.
///   4. NO BUTTON THE DOOR WOULD REFUSE: after the decision there is nothing
///      to answer and nothing to correct.
class _FakeApi extends EeApprovalsApi {
  _FakeApi() : super(Dio());

  final corrections = <Map<String, Object?>>[];
  final decisions = <(String, bool, String)>[];

  @override
  Future<EeApprovalDetail> correct(
    String id, {
    String? subject,
    String? body,
    Map<String, Object?>? answers,
  }) async {
    corrections.add({'subject': subject, 'body': body, 'answers': answers});
    return _window();
  }

  @override
  Future<EeApproval> decide(
    String id, {
    required bool approve,
    required String reason,
  }) async {
    decisions.add((id, approve, reason));
    return _window().approval;
  }
}

final _now = DateTime(2026, 9, 30, 12);

EeApprovalDetail _window({
  String status = 'pending',
  bool full = true,
  bool edit = true,
  bool openTarget = false,
  String reason = 'Donanım talebi',
}) {
  final pending = status == 'pending';
  return EeApprovalDetail(
    approval: EeApproval(
      id: 'A1',
      targetType: 'ee_ticket',
      targetId: 'T1',
      status: status,
      createdAt: _now.subtract(const Duration(hours: 3)),
      approverUserId: 'U-MGR',
      requestReason: reason,
      target: const EeApprovalTarget(
        kind: 'ee_ticket',
        title: 'Dizüstü bilgisayar',
        status: 'new',
        number: 1042,
      ),
      canDecide: pending,
      requestedByName: 'Rana Rapor',
      decidedByName: pending ? null : 'Mert Yönetici',
      decisionReason: pending ? null : 'Uygun',
    ),
    signatures: [
      EeChangeApproval(
        id: 'A1',
        status: status,
        createdAt: _now.subtract(const Duration(hours: 3)),
        canDecide: pending,
        approverUserId: 'U-MGR',
        approverName: 'Mert Yönetici',
      ),
    ],
    access: EeApprovalAccess(
      full: full,
      edit: edit && pending,
      openTarget: openTarget,
    ),
    request: full
        ? EeApprovalRequestView(
            id: 'T1',
            number: 1042,
            ref: '#1042',
            subject: 'Dizüstü bilgisayar',
            body: 'Yeni gelen çalışana 16 GB bellekli dizüstü',
            status: 'new',
            priority: 'high',
            createdAt: _now.subtract(const Duration(days: 2)),
            requester: const EeApprovalRequester(
              userId: 'U-REP',
              name: 'Rana Rapor',
              email: 'rana@example.com',
              kind: 'member',
            ),
            serviceId: 'S1',
            serviceName: 'Donanım talebi',
            fields: const [
              EeFormField(
                key: 'adet',
                label: 'Adet',
                type: 'number',
                required: true,
              ),
              EeFormField(key: 'neden', label: 'Neden', type: 'text'),
            ],
            unitName: 'Bilgi İşlem',
            answers: const [
              EeTicketAnswer(label: 'Adet', type: 'number', value: '2'),
              EeTicketAnswer(
                label: 'Neden',
                type: 'text',
                value: 'Yeni personel',
              ),
            ],
            answerValues: const {'adet': '2', 'neden': 'Yeni personel'},
            comments: [
              EeApprovalComment(
                id: 'C1',
                body: 'Stokta bir tane var',
                internal: true,
                authorName: 'Deniz Masa',
                createdAt: _now.subtract(const Duration(days: 1)),
              ),
            ],
            files: const [
              EeApprovalFile(
                id: 'F1',
                name: 'teklif-ic.pdf',
                mime: 'application/pdf',
                sizeBytes: 2048,
                internal: true,
              ),
              EeApprovalFile(
                id: 'F2',
                name: 'teklif.pdf',
                mime: 'application/pdf',
                sizeBytes: 1024,
                internal: false,
              ),
            ],
          )
        : null,
  );
}

Future<_FakeApi> _pump(
  WidgetTester tester, {
  Future<EeApprovalDetail> Function()? window,
}) async {
  final api = _FakeApi();
  tester.view.physicalSize = const Size(900, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        eeApprovalsApiProvider.overrideWithValue(api),
        eeApprovalDetailProvider.overrideWith(
          (ref, id) => (window ?? () async => _window())(),
        ),
        // The list the actions re-read: quiet.
        eeApprovalsProvider.overrideWith(_Empty.new),
        nowProvider.overrideWithValue(() => _now),
      ],
      child: MaterialApp(
        theme: buildAwTheme(Brightness.light),
        home: const EeApprovalDetailScreen(approvalId: 'A1'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return api;
}

class _Empty extends EeApprovalsController {
  @override
  Future<List<EeApproval>> build() async => const [];
}

Finder _key(String key) => find.byKey(Key(key));

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('en'));
  });

  testWidgets('the approver reads the request whole — internal notes and '
      'their files marked', (tester) async {
    await _pump(tester);

    expect(_key('ee-approval-detail-status'), findsOneWidget);
    expect(find.text('Your decision is awaited'), findsOneWidget);
    expect(find.text('#1042 · Dizüstü bilgisayar'), findsOneWidget);
    final requester = tester.widget<Text>(_key('ee-approval-detail-requester'));
    expect(requester.data, 'Rana Rapor');
    final opened = tester.widget<Text>(_key('ee-approval-detail-opened'));
    expect(opened.data, contains('time.ago.days'.tr(args: {'n': '2'})));
    expect(find.text('rana@example.com'), findsOneWidget);
    expect(
      find.text('Yeni gelen çalışana 16 GB bellekli dizüstü'),
      findsOneWidget,
    );
    // The answers, the files, the conversation — internal ones marked.
    expect(find.text('Yeni personel'), findsOneWidget);
    expect(_key('ee-approval-file-F1'), findsOneWidget);
    expect(
      find.descendant(
        of: _key('ee-approval-file-F1'),
        matching: find.textContaining('Internal note'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _key('ee-approval-file-F2'),
        matching: find.textContaining('Internal note'),
      ),
      findsNothing,
    );
    expect(_key('ee-approval-comment-internal-C1'), findsOneWidget);
    // Who else was asked, and the two answers at the bottom.
    expect(_key('ee-signature-A1'), findsOneWidget);
    expect(_key('ee-approval-detail-approve'), findsOneWidget);
    expect(_key('ee-approval-detail-reject'), findsOneWidget);
    expect(_key('ee-approval-correct'), findsOneWidget);
    // Said once each: the answers under the window's own heading (the
    // ticket's view brings a title of its own), and a rule's reason — the
    // service's name, already on the pills — not again under the ask.
    expect(find.text('Form answers'), findsOneWidget);
    expect(find.text('Donanım talebi'), findsOneWidget);
    expect(find.text('“Donanım talebi”'), findsNothing);
  });

  testWidgets('a reason somebody wrote is said under the ask', (tester) async {
    await _pump(tester, window: () async => _window(reason: 'Bütçe aşımı'));
    expect(find.text('“Bütçe aşımı”'), findsOneWidget);
  });

  testWidgets('somebody not asked is told so, and reads the summary', (
    tester,
  ) async {
    await _pump(tester, window: () async => _window(full: false, edit: false));
    expect(_key('ee-approval-detail-summary-only'), findsOneWidget);
    expect(_key('ee-approval-detail-body'), findsNothing);
    expect(_key('ee-approval-correct'), findsNothing);
  });

  testWidgets('a correction sends what changed, and says where it went', (
    tester,
  ) async {
    final api = await _pump(tester);
    await tester.tap(_key('ee-approval-correct'));
    await tester.pumpAndSettle();

    // Seeded with what the request says now.
    expect(
      tester
          .widget<TextField>(_key('ee-approval-correct-subject'))
          .controller!
          .text,
      'Dizüstü bilgisayar',
    );
    await tester.enterText(
      _key('ee-approval-correct-subject'),
      'Dizüstü bilgisayar (3 adet)',
    );
    await tester.enterText(_key('ee-approval-correct-field-adet'), '3');
    await tester.pumpAndSettle();
    await tester.tap(_key('ee-approval-correct-save'));
    await tester.pumpAndSettle();

    expect(api.corrections, hasLength(1));
    final sent = api.corrections.single;
    expect(sent['subject'], 'Dizüstü bilgisayar (3 adet)');
    // The text was not touched, so it does not travel.
    expect(sent['body'], isNull);
    // A number field hands back a number — the filing door's own shape.
    expect((sent['answers']! as Map)['adet'], 3);
    expect(
      find.text(
        'Correction saved — it shows in the request\'s history under your name',
      ),
      findsOneWidget,
    );
    // The snackbar's own timer (LESSONS flutter-app).
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('a required answer cannot be emptied on the way', (tester) async {
    final api = await _pump(tester);
    await tester.tap(_key('ee-approval-correct'));
    await tester.pumpAndSettle();
    await tester.enterText(_key('ee-approval-correct-field-adet'), '');
    await tester.pumpAndSettle();
    await tester.tap(_key('ee-approval-correct-save'));
    await tester.pumpAndSettle();
    expect(api.corrections, isEmpty);
    expect(find.text('"Adet" needs an answer'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('the decision goes through the reason dialog to the door', (
    tester,
  ) async {
    final api = await _pump(tester);
    await tester.tap(_key('ee-approval-detail-approve'));
    await tester.pumpAndSettle();
    await tester.enterText(_key('ee-approval-reason'), 'Bütçe uygun');
    await tester.pumpAndSettle();
    await tester.tap(_key('ee-approval-confirm'));
    await tester.pumpAndSettle();
    expect(api.decisions.single, ('A1', true, 'Bütçe uygun'));
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('after the decision: nothing to answer, nothing to correct', (
    tester,
  ) async {
    await _pump(tester, window: () async => _window(status: 'approved'));
    expect(_key('ee-approval-detail-approve'), findsNothing);
    expect(_key('ee-approval-correct'), findsNothing);
    // …and whoever answered still reads what they signed.
    expect(_key('ee-approval-detail-body'), findsOneWidget);
  });

  testWidgets('the request opens where it lives only when the door says so', (
    tester,
  ) async {
    await _pump(tester, window: () async => _window(openTarget: true));
    expect(_key('ee-approval-open-target'), findsOneWidget);
    expect(find.text('Open the request'), findsOneWidget);
  });

  testWidgets('a gone approval says so, with the way back', (tester) async {
    await _pump(
      tester,
      window: () async => throw const ApiException('HTTP_404', 'Not found'),
    );
    expect(find.text('This approval is gone'), findsOneWidget);
    expect(_key('ee-approval-gone-back'), findsOneWidget);
  });

  test('the door\'s refusals read in Turkish too', () {
    AwI18n.instance.setActiveCached(const Locale('tr'));
    expect(
      localizedError(const ApiException('APPROVAL_ALREADY_DECIDED', 'x')),
      startsWith('Bu onay zaten karara bağlandı'),
    );
    expect(
      localizedError(const ApiException('APPROVAL_NOT_YOURS', 'x')),
      'Bu onay sizden istenmedi.',
    );
  });

  // ── OPH-358 ──────────────────────────────────────────────────────────────

  testWidgets(
    'UI-AUDIT #14: an approval withdrawn with its request reads "Withdrawn"; a state this build does not know reads neutral',
    (tester) async {
      await _pump(tester, window: () async => _window(status: 'withdrawn'));
      final banner = tester.widget<Text>(
        find.descendant(
          of: _key('ee-approval-detail-status'),
          matching: find.byType(Text),
        ),
      );
      expect(banner.data, startsWith('Withdrawn'));
      expect(find.textContaining('ee.approvals.status'), findsNothing);
      expect(find.textContaining('withdrawn'), findsNothing);
    },
  );

  testWidgets(
    'UI-AUDIT #14: a state this build does not know reads neutral, never the key',
    (tester) async {
      await _pump(tester, window: () async => _window(status: 'superseded'));
      final neutral = tester.widget<Text>(
        find.descendant(
          of: _key('ee-approval-detail-status'),
          matching: find.byType(Text),
        ),
      );
      expect(neutral.data, startsWith('Status unknown'));
      expect(find.textContaining('superseded'), findsNothing);
    },
  );

  testWidgets(
    'UI-AUDIT #74: back from "open the request", the page is read again — a note written there shows here',
    (tester) async {
      var reads = 0;
      final router = GoRouter(
        initialLocation: '/approvals/A1',
        routes: [
          GoRoute(
            path: '/approvals/:id',
            builder: (_, _) => const EeApprovalDetailScreen(approvalId: 'A1'),
          ),
          GoRoute(
            path: '/tickets/:id',
            builder: (context, _) => Scaffold(
              body: TextButton(
                key: const Key('back-from-ticket'),
                onPressed: () => context.pop(),
                child: const Text('back'),
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      tester.view.physicalSize = const Size(900, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            eeApprovalsApiProvider.overrideWithValue(_FakeApi()),
            eeApprovalDetailProvider.overrideWith((ref, id) async {
              reads += 1;
              return _window(openTarget: true);
            }),
            eeApprovalsProvider.overrideWith(_Empty.new),
            nowProvider.overrideWithValue(() => _now),
          ],
          child: MaterialApp.router(
            theme: buildAwTheme(Brightness.light),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(reads, 1);
      await tester.tap(_key('ee-approval-open-target'));
      await tester.pumpAndSettle();
      await tester.tap(_key('back-from-ticket'));
      await tester.pumpAndSettle();
      expect(reads, 2);
    },
  );

  testWidgets(
    'UI-AUDIT #77: a change still waiting for a signature on a window that has passed says so',
    (tester) async {
      await _pump(
        tester,
        window: () async =>
            _changeWindow(_now.subtract(const Duration(days: 2))),
      );
      expect(_key('change-window-passed'), findsOneWidget);
    },
  );

  testWidgets('UI-AUDIT #77: a window still ahead carries no warning', (
    tester,
  ) async {
    await _pump(
      tester,
      window: () async => _changeWindow(_now.add(const Duration(days: 2))),
    );
    expect(_key('change-window-passed'), findsNothing);
  });
}

EeApprovalDetail _changeWindow(DateTime end) => EeApprovalDetail(
  approval: EeApproval(
    id: 'A1',
    targetType: 'ee_change',
    targetId: 'CH1',
    status: 'pending',
    createdAt: _now.subtract(const Duration(days: 9)),
    canDecide: true,
  ),
  signatures: const [],
  access: const EeApprovalAccess(full: true, edit: false, openTarget: false),
  change: EeApprovalChangeView(
    id: 'CH1',
    title: 'Disk ve RAID kartı değişimi',
    status: 'awaiting_approval',
    windowStart: end.subtract(const Duration(hours: 4)),
    windowEnd: end,
  ),
);
