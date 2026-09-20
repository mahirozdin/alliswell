import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/approvals_providers.dart';
import 'package:alliswell/src/features/ee/data/approvals_models.dart';
import 'package:alliswell/src/features/ee/ui/team_approvals_screen.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';

/// EE-184 — the approval screen, asserted where a redesign would mislead.
///
///   1. NEITHER ANSWER WORKS WITHOUT A REASON. The server refuses both ways;
///      the screen refusing too is what keeps the person's hands on the form
///      when they learn it, instead of after the button.
///   2. A MISSING TARGET SAYS SO. `target` is genuinely nullable — core can
///      delete the task, the archive can sweep the request — and an empty row
///      would read as a bug rather than as the fact it is.
///   3. A DECIDED ROW OFFERS NO BUTTONS. Drawing Approve on something already
///      approved invites a second decision that the server will refuse, which
///      is a screen making a promise it cannot keep.
class _Fixed extends EeApprovalsController {
  _Fixed(this._items);
  final List<EeApproval> _items;
  @override
  Future<List<EeApproval>> build() async => _items;
}

EeApproval _approval({
  String id = 'A1',
  String status = 'pending',
  String? requestReason = 'Bütçe dışı bir parça gerekiyor',
  String? decisionReason,
  EeApprovalTarget? target = const EeApprovalTarget(
    kind: 'ee_ticket',
    title: 'Bant arızası',
    status: 'new',
    number: 1042,
  ),
  DateTime? dueAt,
}) => EeApproval(
  id: id,
  targetType: 'ee_ticket',
  targetId: 'T1',
  status: status,
  createdAt: DateTime(2026, 9, 20, 9),
  approverUserId: 'U1',
  requestReason: requestReason,
  decisionReason: decisionReason,
  dueAt: dueAt,
  target: target,
);

Future<void> _pump(WidgetTester tester, List<EeApproval> items) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [eeApprovalsProvider.overrideWith(() => _Fixed(items))],
      child: MaterialApp(
        theme: buildAwTheme(Brightness.light),
        home: const EeTeamApprovalsScreen(),
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

  testWidgets('an empty queue says nothing is waiting, not that it failed', (
    tester,
  ) async {
    await _pump(tester, const []);
    expect(find.text('Nothing is waiting on you'), findsOneWidget);
  });

  testWidgets('a row carries the number, the title and why it was asked', (
    tester,
  ) async {
    await _pump(tester, [_approval()]);
    expect(find.text('#1042 · Bant arızası'), findsOneWidget);
    expect(find.text('Bütçe dışı bir parça gerekiyor'), findsOneWidget);
    expect(find.byKey(const Key('ee-approval-approve-A1')), findsOneWidget);
    expect(find.byKey(const Key('ee-approval-reject-A1')), findsOneWidget);
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

  testWidgets(
    'a target that is gone says so rather than drawing an empty row',
    (tester) async {
      await _pump(tester, [_approval(target: null)]);
      expect(find.text('What this was about is gone'), findsOneWidget);
    },
  );

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
}
