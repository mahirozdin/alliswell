import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/widgets/snackbars.dart';

/// OPH-257 — the guard on `persist: false`.
///
/// This is deliberately the *bare* helper, with no undo window and no pending
/// delete behind it. Three of the app's four action bars (board move, AI
/// confirm, broken quick link) have nothing but this flag keeping them from
/// staying on screen forever, so the flag needs a test that fails when it is
/// removed — and a test that goes through `awDeleteWithUndo` cannot be that
/// test: its commit timer takes the bar down on its own, and would pass with
/// `persist` left at Flutter's default. (Measured: it did.)
void main() {
  Widget host({required Duration duration}) => MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => showAwActionSnackBar(
            ScaffoldMessenger.of(context),
            key: const Key('aw-bar'),
            content: const Text('Moved to Done'),
            actionLabel: 'Undo',
            onAction: () {},
            duration: duration,
          ),
          child: const Text('show'),
        ),
      ),
    ),
  );

  testWidgets('an action snackbar still dismisses itself', (tester) async {
    await tester.pumpWidget(host(duration: const Duration(seconds: 2)));

    await tester.tap(find.text('show'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('aw-bar')), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('aw-bar')),
      findsNothing,
      reason:
          'Flutter defaults `persist` to `action != null`; without an explicit '
          '`persist: false` this bar waits for a swipe that may never come',
    );
  });

  testWidgets('tapping the action still takes the bar away', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAwActionSnackBar(
                ScaffoldMessenger.of(context),
                key: const Key('aw-bar'),
                content: const Text('Moved to Done'),
                actionLabel: 'Undo',
                onAction: () => tapped++,
                duration: const Duration(seconds: 30),
              ),
              child: const Text('show'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('show'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(tapped, 1);
    expect(find.byKey(const Key('aw-bar')), findsNothing);
  });
}
