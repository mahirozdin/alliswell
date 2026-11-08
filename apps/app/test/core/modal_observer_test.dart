import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/core/modal_observer.dart';
import 'package:alliswell/src/widgets/fab_clearance.dart';

/// OPH-391 (E-09): the observer tells the Quick Access layer whether the top
/// page on the ROOT navigator is outside the shell — where a docked button
/// steps aside instead of the page giving up a lane for it.
void main() {
  late AwModalRouteObserver observer;
  final root = GlobalKey<NavigatorState>();
  final nested = GlobalKey<NavigatorState>();

  setUp(() => observer = AwModalRouteObserver());
  tearDown(() => observer.dispose());

  Route<void> page(String? name, {Widget? child}) => MaterialPageRoute<void>(
    settings: RouteSettings(name: name),
    builder: (_) => child ?? const SizedBox.expand(),
  );

  Future<void> pumpShell(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: root,
        navigatorObservers: [observer],
        onGenerateRoute: (_) => page(
          kAwShellPageName,
          // A section's own navigator, as go_router builds a branch — the
          // root's observer is merged into it.
          child: Navigator(
            key: nested,
            observers: [AwModalRouteObserver()],
            onGenerateRoute: (_) => page('section'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the shell is not outside the shell', (tester) async {
    await pumpShell(tester);
    expect(observer.outsideShell.value, isFalse);
  });

  testWidgets('a page pushed on the root is; popping it comes back', (
    tester,
  ) async {
    await pumpShell(tester);
    root.currentState!.push(page('/settings'));
    await tester.pumpAndSettle();
    expect(observer.outsideShell.value, isTrue);
    root.currentState!.pop();
    await tester.pumpAndSettle();
    expect(observer.outsideShell.value, isFalse);
  });

  testWidgets('a page inside a section stays in the shell', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: root,
        onGenerateRoute: (_) => page(
          kAwShellPageName,
          child: Navigator(
            key: nested,
            observers: [observer],
            onGenerateRoute: (_) => page('section'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    nested.currentState!.push(page('/projects/p1'));
    await tester.pumpAndSettle();
    expect(observer.outsideShell.value, isFalse);
  });

  testWidgets('a dialog is not a page', (tester) async {
    await pumpShell(tester);
    showDialog<void>(
      context: root.currentContext!,
      builder: (_) => const Text('dialog'),
    );
    await tester.pumpAndSettle();
    expect(observer.outsideShell.value, isFalse);
    expect(observer.depth.value, 1);
  });
}
