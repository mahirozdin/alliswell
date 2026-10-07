import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/ee/approvals_providers.dart';
import 'package:alliswell/src/features/ee/data/approvals_models.dart';
import 'package:alliswell/src/i18n/i18n.dart';

import 'shell_harness.dart';

/// OPH-359 — UI-AUDIT #12 and the rail half of #57.
///
/// ── THE ROOT CAUSE, MEASURED ──────────────────────────────────────────────
///
/// The rail was missing from the accessibility tree on every wide screen,
/// and the audit could not say why. Measured here: a section's Navigator
/// paints its page route's ModalBarrier, and a barrier is a `BlockSemantics`
/// — it drops every node painted BEFORE it in the same semantics container.
/// The shell had no container between the rail and the content, so the rail
/// (painted first in the Row) was dropped whole: no screen reader, and on the
/// web no Tab stop either, because Flutter web's focus follows the semantics
/// DOM. The phone's bar is painted after the body, which is why it survived.
///
/// A probe Semantics node placed before the content vanished the same way; a
/// container around the content brought both back.
void main() {
  setUp(() => AwI18n.instance.setActiveCached(const Locale('en')));

  const waiting = EeApprovalsSummary(
    authority: true,
    answersForRole: true,
    personal: 2,
    role: 1,
  );

  /// Whether a node whose label starts with [name] is in the compiled tree.
  bool inTree(String name) => find.semantics
      .byPredicate((node) => node.label.split('\n').first.startsWith(name))
      .evaluate()
      .isNotEmpty;

  Future<void> pumpWide(WidgetTester tester, {double width = 1440}) async {
    sizeTo(tester, Size(width, 900));
    await tester.pumpWidget(
      await teamApp(
        teamApi(),
        more: [eeApprovalsSummaryProvider.overrideWith((ref) async => waiting)],
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final width in const [1440.0, 1000.0]) {
    testWidgets('UI-AUDIT #12: at ${width.toInt()} px every rail destination '
        'and Approvals are in the accessibility tree', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpWide(tester, width: width);
      for (final key in const [
        'nav.home',
        'nav.inbox',
        'nav.projects',
        'nav.notes',
        'nav.files',
        'nav.tickets',
      ]) {
        final name = key.tr();
        expect(
          inTree(name),
          isTrue,
          reason: '"$name" is not in the semantics tree',
        );
      }
      expect(
        inTree('ee.approvals.title'.tr()),
        isTrue,
        reason: 'the Approvals entry is not in the semantics tree',
      );
      handle.dispose();
    });
  }

  testWidgets('UI-AUDIT #12: Tab walks into the rail and Enter opens '
      'Requests', (tester) async {
    await pumpWide(tester);
    final requests = find.ancestor(
      of: find.text('nav.tickets'.tr()),
      matching: find.byWidgetPredicate((w) => w is InkResponse),
    );
    expect(requests, findsWidgets);
    var reached = false;
    for (var i = 0; i < 150 && !reached; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final focused = FocusManager.instance.primaryFocus?.context;
      if (focused == null) continue;
      reached = find
          .descendant(of: requests.first, matching: find.byType(Focus))
          .evaluate()
          .any((e) => e == focused || _isAncestor(e, focused));
    }
    expect(reached, isTrue, reason: 'Tab never reached "Requests"');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(appRouter().state.uri.path, '/tickets');
  });

  testWidgets('UI-AUDIT #12 (retest): the Approvals node is a real button — '
      'focusable and tappable — and Tab then Enter opens it', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpWide(tester);
    // The node a screen reader (and Flutter web's DOM, where a focusable
    // node gets its tabindex) sees: it must carry the tap and the focus,
    // not just the word "button" over a subtree it hid.
    final node = tester.getSemantics(find.byKey(const Key('nav-approvals')));
    final data = node.getSemanticsData();
    expect(node.label, startsWith('ee.approvals.title'.tr()));
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    expect(data.hasAction(SemanticsAction.focus), isTrue);
    expect(data.flagsCollection.isFocused, isNot(Tristate.none));
    handle.dispose();

    final approvals = find.byKey(const Key('nav-approvals'));
    var reached = false;
    for (var i = 0; i < 150 && !reached; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final focused = FocusManager.instance.primaryFocus?.context;
      if (focused == null) continue;
      reached =
          find
              .descendant(of: approvals, matching: find.byType(Focus))
              .evaluate()
              .any((e) => e == focused || _isAncestor(e, focused)) ||
          _isAncestor(approvals.evaluate().first, focused);
    }
    expect(reached, isTrue, reason: 'Tab never reached "Approvals"');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(appRouter().state.uri.path, '/approvals');
  });

  testWidgets('UI-AUDIT #57: in the extended rail Approvals lines up with '
      'the destinations — icon column and label start', (tester) async {
    await pumpWide(tester);
    final homeIcon = tester.getCenter(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.byIcon(Icons.inbox_outlined),
      ),
    );
    final approvalsIcon = tester.getCenter(
      find.byKey(const Key('nav-approvals-icon')),
    );
    expect(approvalsIcon.dx, closeTo(homeIcon.dx, 0.5));

    final homeLabel = tester.getTopLeft(
      find
          .descendant(
            of: find.byType(NavigationRail),
            matching: find.text('nav.inbox'.tr()),
          )
          .first,
    );
    final approvalsLabel = tester.getTopLeft(
      find.descendant(
        of: find.byKey(const Key('nav-approvals')),
        matching: find.text('ee.approvals.title'.tr()),
      ),
    );
    expect(approvalsLabel.dx, closeTo(homeLabel.dx, 0.5));
  });
}

bool _isAncestor(Element ancestor, BuildContext descendant) {
  var found = false;
  descendant.visitAncestorElements((e) {
    if (e == ancestor) found = true;
    return !found;
  });
  return found;
}
