import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/ee/my_tickets_providers.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/tokens.dart';
import 'package:alliswell/src/widgets/section_fab.dart';

import 'shell_harness.dart';

/// OPH-397 (polish 2, R-02) — a screen's own create button inside a section
/// joins the shell's action cluster (DESIGN §44 F3) instead of floating in
/// its own Scaffold under the microphone. Before: the microphone sat on the
/// extended "new request" button and its label read "New r…", on the phone
/// and on the desktop, at 1× and 2× text.
void main() {
  setUp(() => AwI18n.instance.setActiveCached(const Locale('en')));

  Future<void> openRequests(
    WidgetTester tester,
    Size size, {
    double textScale = 1,
    bool desk = true,
  }) async {
    sizeTo(tester, size);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final api = teamApi()..seedAiConnection(provider: 'anthropic');
    await tester.pumpWidget(
      await teamApp(
        api,
        more: [
          if (!desk) ...[
            eeDeskProvider.overrideWithValue(false),
            eeMyTicketsProvider.overrideWith((ref) async => const []),
          ],
        ],
      ),
    );
    await tester.pumpAndSettle();
    appRouter().go('/tickets');
    await tester.pumpAndSettle();
  }

  void expectOneCluster(WidgetTester tester, Key create, double gutter) {
    final mic = find.byKey(const Key('ai-fab'));
    final button = find.byKey(create);
    expect(mic, findsOneWidget);
    expect(button, findsOneWidget);
    final m = tester.getRect(mic);
    final b = tester.getRect(button);
    expect(
      m.overlaps(b),
      isFalse,
      reason: 'the microphone covers the screen\'s create button',
    );
    // F3: the create button on the gutter, the microphone 8 to its left,
    // one centre line.
    final width = tester.view.physicalSize.width;
    expect(b.right, moreOrLessEquals(width - gutter, epsilon: 0.5));
    expect(b.left - m.right, moreOrLessEquals(kAwFabClusterGap, epsilon: 0.5));
    expect(m.center.dy, moreOrLessEquals(b.center.dy, epsilon: 0.5));
    // The label is whole: "New request", not "New r…".
    final label = find.descendant(
      of: button,
      matching: find.text('ee.tickets.new.fab'.tr()),
    );
    expect(label, findsOneWidget);
    expect(b.contains(tester.getRect(label).centerRight), isTrue);
  }

  testWidgets('phone: the queue\'s "new request" and the microphone are '
      'one cluster', (tester) async {
    await openRequests(tester, const Size(390, 844));
    expectOneCluster(tester, const Key('ticket-new'), kAwFloatGutter);
  });

  testWidgets('phone at 2× text: still one cluster, nothing covered', (
    tester,
  ) async {
    await openRequests(tester, const Size(390, 844), textScale: 2);
    expectOneCluster(tester, const Key('ticket-new'), kAwFloatGutter);
  });

  testWidgets('desktop: the cluster at the window\'s end, the button whole', (
    tester,
  ) async {
    await openRequests(tester, const Size(1440, 900));
    expectOneCluster(tester, const Key('ticket-new'), kAwFloatGutter);
  });

  testWidgets('member\'s "my requests": the same cluster', (tester) async {
    await openRequests(tester, const Size(390, 844), desk: false);
    expectOneCluster(tester, const Key('my-tickets-new'), kAwFloatGutter);
  });

  testWidgets('the hosted button still opens the form', (tester) async {
    await openRequests(tester, const Size(390, 844));
    await tester.tap(find.byKey(const Key('ticket-new')));
    await tester.pumpAndSettle();
    expect(appRouter().state.uri.path, '/tickets/new');
  });

  testWidgets('it leaves the cluster with its screen: another section, '
      'another tab', (tester) async {
    await openRequests(tester, const Size(390, 844));
    expect(find.byKey(const Key('ticket-new')), findsOneWidget);

    // The SLA tab draws no create button.
    await tester.tap(find.text('ee.tickets.tabs.sla'.tr()).first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ticket-new')), findsNothing);

    appRouter().go('/notes');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ticket-new')), findsNothing);
    // Notes' own "+" is back on the gutter.
    expect(find.byKey(const Key('shell-fab-cluster')), findsOneWidget);
  });

  // H-2 (polish 3): on the SLA board and the workload report the
  // microphone stood alone on the gutter and covered the right-hand
  // figures of the unit rows. In the requests section the microphone
  // floats only as part of the cluster, beside the create button a screen
  // lent; a board with no create button floats nothing over its figures.
  for (final size in const [Size(390, 844), Size(1440, 900)]) {
    testWidgets('${size.width.toInt()} px: the SLA and workload tabs float '
        'no lone microphone', (tester) async {
      await openRequests(tester, size);
      expect(find.byKey(const Key('ai-fab')), findsOneWidget);

      await tester.tap(find.byKey(const Key('ticket-tab-sla')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ai-fab')), findsNothing);
      expect(find.byKey(const Key('shell-fab-cluster')), findsNothing);

      await tester.tap(find.byKey(const Key('ticket-tab-workload')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ai-fab')), findsNothing);
      expect(find.byKey(const Key('shell-fab-cluster')), findsNothing);

      // Back on the queue the cluster returns whole.
      await tester.tap(find.byKey(const Key('ticket-tab-queue')));
      await tester.pumpAndSettle();
      expectOneCluster(tester, const Key('ticket-new'), kAwFloatGutter);
    });
  }

  testWidgets('outside a shell the button floats in its own Scaffold', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            floatingActionButton: AwSectionFab(
              child: FloatingActionButton(
                key: const Key('own'),
                onPressed: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('own')), findsOneWidget);
  });
}
