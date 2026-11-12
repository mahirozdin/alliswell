import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:alliswell/src/widgets/route_leading.dart';

/// awRouteLeading (OPH-359, W-08): a screen opened by its address keeps a
/// way out however often it rebuilds under a sheet or a pushed page.
class _Screen extends StatelessWidget {
  const _Screen(this.tick);

  /// Stands in for a provider the screen watches: it changes while a page or
  /// sheet sits on top.
  final ValueNotifier<int> tick;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: tick,
    builder: (context, _, _) => Scaffold(
      appBar: AppBar(leading: awRouteLeading(context), title: const Text('S')),
      body: Column(
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (c) => Scaffold(
                  appBar: AppBar(leading: awRouteLeading(c)),
                  body: TextButton(
                    onPressed: () => Navigator.of(c).pop(),
                    child: const Text('done'),
                  ),
                ),
              ),
            ),
            child: const Text('page'),
          ),
          TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              useRootNavigator: true,
              builder: (c) => TextButton(
                onPressed: () => Navigator.of(c).pop(),
                child: const Text('close'),
              ),
            ),
            child: const Text('sheet'),
          ),
        ],
      ),
    ),
  );
}

Future<ValueNotifier<int>> _pump(
  WidgetTester tester, {
  String initialLocation = '/screen',
}) async {
  final tick = ValueNotifier<int>(0);
  addTearDown(tick.dispose);
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/home',
        builder: (context, _) => Scaffold(
          key: const Key('home'),
          body: TextButton(
            onPressed: () => context.push('/screen'),
            child: const Text('open'),
          ),
        ),
      ),
      GoRoute(path: '/screen', builder: (_, _) => _Screen(tick)),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
  return tick;
}

void main() {
  final home = find.byKey(const Key('aw-route-home'));

  testWidgets('the Home button survives a rebuild under a pushed page', (
    tester,
  ) async {
    final tick = await _pump(tester);
    expect(home, findsOneWidget);

    await tester.tap(find.text('page'));
    await tester.pumpAndSettle();
    // The page on top has something below it: AppBar's own back button.
    expect(find.byType(BackButton), findsOneWidget);
    tick.value++;
    await tester.pump();
    await tester.tap(find.text('done'));
    await tester.pumpAndSettle();
    expect(home, findsOneWidget);

    await tester.tap(home);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('home')), findsOneWidget);
  });

  testWidgets('the Home button stays while a sheet is open over a rebuild', (
    tester,
  ) async {
    final tick = await _pump(tester);
    await tester.tap(find.text('sheet'));
    await tester.pumpAndSettle();
    tick.value++;
    await tester.pump();
    // Still drawn behind the sheet's scrim: no flicker.
    expect(home, findsOneWidget);
    await tester.tap(find.text('close'));
    await tester.pumpAndSettle();
    expect(home, findsOneWidget);
  });

  testWidgets('a screen with something below it gets the back button, not '
      'Home', (tester) async {
    await _pump(tester, initialLocation: '/home');
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(home, findsNothing);
    expect(find.byType(BackButton), findsOneWidget);
  });

  testWidgets('without a router there is no Home to go to', (tester) async {
    await tester.pumpWidget(MaterialApp(home: _Screen(ValueNotifier<int>(0))));
    expect(home, findsNothing);
    expect(find.byType(BackButton), findsNothing);
  });
}
