import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/core/reachability.dart';
import 'package:alliswell/src/i18n/i18n.dart';

import '../projects/fake_api.dart';
import '../tasks/tasks_flow_test.dart' show signedInAppWith;

/// OPH-392 (E-22) — a phone says when the server stopped answering.
///
/// A wide window's refresh button reports its own failure; a phone has no
/// such button, and with the network cut it showed nothing at all — the
/// persona review's web run at 393 px. The strip follows
/// [serverReachabilityProvider] (fed by every request, `reachability_test`),
/// so it appears on the first unanswered pull and leaves on the first answer.
void main() {
  Future<ProviderContainer> pumpAt(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(await signedInAppWith(FakeApi()));
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(AllisWellApp)));
  }

  final strip = find.byKey(const Key('offline-strip'));

  testWidgets('phone width: unreachable shows the strip under the status bar, '
      'and the first answer clears it', (tester) async {
    tester.view.padding = const FakeViewPadding(top: 47);
    final container = await pumpAt(tester, const Size(393, 852));
    expect(strip, findsNothing);

    container.read(serverReachabilityProvider.notifier).unreachable();
    await tester.pumpAndSettle();
    expect(strip, findsOneWidget);
    expect(find.text('common.offline'.tr()), findsOneWidget);
    // Below the status bar, not under it — and the section's app bar does
    // not add the inset a second time beneath the strip.
    expect(
      tester.getTopLeft(find.text('common.offline'.tr())).dy,
      greaterThanOrEqualTo(47),
    );
    final appBar = find.byType(AppBar).first;
    expect(
      tester.getTopLeft(appBar).dy,
      moreOrLessEquals(tester.getBottomLeft(strip).dy),
    );
    expect(tester.getSemantics(find.text('common.offline'.tr())), isNotNull);

    container.read(serverReachabilityProvider.notifier).answered();
    await tester.pumpAndSettle();
    expect(strip, findsNothing);
  });

  testWidgets('unknown is not offline: no strip before anything was asked', (
    tester,
  ) async {
    final container = await pumpAt(tester, const Size(393, 852));
    container.invalidate(serverReachabilityProvider);
    await tester.pumpAndSettle();
    expect(container.read(serverReachabilityProvider), isNull);
    expect(strip, findsNothing);
  });
}
