import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/widgets/list_detail.dart';

/// R-15 — the pane tells its host when it stops showing an item: closed, or
/// the list left with the pane open. The request queue gives back a unit it
/// opened only to show a request there; a pane that went away silently kept
/// that unit open everywhere else.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required ValueNotifier<bool> shown,
    required VoidCallback onClose,
  }) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: shown,
          builder: (context, on, _) => on
              ? AwListDetailScope(
                  kind: 'demo',
                  onClose: onClose,
                  child: AwListDetailPane(
                    kind: 'demo',
                    detailBuilder: (context, id, close) =>
                        Scaffold(body: Text('detail $id')),
                    child: Builder(
                      builder: (context) => Scaffold(
                        body: TextButton(
                          key: const Key('row'),
                          onPressed: () => AwListDetailScope.maybeOf(
                            context,
                            'demo',
                            listen: false,
                          )?.open('A'),
                          child: const Text('row A'),
                        ),
                      ),
                    ),
                  ),
                )
              : const Scaffold(body: Text('elsewhere')),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Escape closes the pane and says so once', (tester) async {
    var closed = 0;
    final shown = ValueNotifier(true);
    addTearDown(shown.dispose);
    await pump(tester, shown: shown, onClose: () => closed += 1);
    await tester.tap(find.byKey(const Key('row')));
    await tester.pumpAndSettle();
    expect(find.text('detail A'), findsOneWidget);
    expect(closed, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('detail A'), findsNothing);
    expect(closed, 1);
  });

  testWidgets('leaving the list with the pane open says so too', (
    tester,
  ) async {
    var closed = 0;
    final shown = ValueNotifier(true);
    addTearDown(shown.dispose);
    await pump(tester, shown: shown, onClose: () => closed += 1);
    await tester.tap(find.byKey(const Key('row')));
    await tester.pumpAndSettle();

    shown.value = false;
    await tester.pumpAndSettle();
    expect(find.text('elsewhere'), findsOneWidget);
    expect(closed, 1);
  });

  testWidgets('a list left with nothing open says nothing', (tester) async {
    var closed = 0;
    final shown = ValueNotifier(true);
    addTearDown(shown.dispose);
    await pump(tester, shown: shown, onClose: () => closed += 1);
    shown.value = false;
    await tester.pumpAndSettle();
    expect(closed, 0);
  });
}
