import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/theme/theme.dart';
import 'package:alliswell/src/widgets/fab_clearance.dart';

/// OPH-362 — UI-AUDIT #57: the docked Quick Access bubble's lane is kept free
/// by the page transitions, for EVERY page route — the ones go_router builds
/// and the ones a screen pushes itself (an approval, a request, a policy) —
/// with no screen knowing.
void main() {
  const lane = 80.0;

  Future<void> pumpDocked(
    WidgetTester tester, {
    double height = lane,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAwTheme(brightness),
        builder: (context, child) => AwBubbleDock(
          edge: AwDockEdge.right,
          height: height,
          width: 72,
          child: child!,
        ),
        home: const Scaffold(body: Text('home')),
      ),
    );
  }

  NavigatorState root(WidgetTester tester) =>
      Navigator.of(tester.element(find.text('home')), rootNavigator: true);

  Future<void> push(
    WidgetTester tester,
    NavigatorState navigator, {
    String? name,
  }) async {
    navigator.push(
      MaterialPageRoute<void>(
        settings: RouteSettings(name: name),
        builder: (context) =>
            const Scaffold(key: Key('pushed'), body: SizedBox.expand()),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final brightness in Brightness.values) {
    testWidgets('a page pushed on the root navigator ends above the lane, and '
        'the safe area below it is the lane\'s (${brightness.name})', (
      tester,
    ) async {
      await pumpDocked(tester, brightness: brightness);
      await push(tester, root(tester));
      final page = find.byKey(const Key('pushed'));
      expect(tester.getRect(page).bottom, 844 - lane);
      expect(MediaQuery.paddingOf(tester.element(page)).bottom, 0);
      expect(MediaQuery.viewPaddingOf(tester.element(page)).bottom, 0);
    });
  }

  testWidgets('the shell page keeps the whole screen — it docks the button '
      'beside its own bar', (tester) async {
    await pumpDocked(tester);
    await push(tester, root(tester), name: kAwShellPageName);
    expect(tester.getRect(find.byKey(const Key('pushed'))).bottom, 844);
  });

  testWidgets('a page inside a nested navigator (a shell section) is left '
      'alone — the bar is under it', (tester) async {
    final nested = GlobalKey<NavigatorState>();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAwTheme(Brightness.light),
        builder: (context, child) => AwBubbleDock(
          edge: AwDockEdge.right,
          height: lane,
          width: 72,
          child: child!,
        ),
        // The root's one page is the shell, and the section's pages live in
        // the shell's own navigator — the go_router shape.
        onGenerateRoute: (_) => MaterialPageRoute<void>(
          settings: const RouteSettings(name: kAwShellPageName),
          builder: (_) => Navigator(
            key: nested,
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('home')),
            ),
          ),
        ),
      ),
    );
    await push(tester, nested.currentState!);
    expect(tester.getRect(find.byKey(const Key('pushed'))).bottom, 844);
  });

  testWidgets('no dock (wide, no button, parked elsewhere, a keyboard up): '
      'nothing changes', (tester) async {
    await pumpDocked(tester, height: 0);
    await push(tester, root(tester));
    expect(tester.getRect(find.byKey(const Key('pushed'))).bottom, 844);
  });
}
