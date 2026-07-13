import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/app.dart';

void main() {
  testWidgets('app shell renders the Today section by default', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: AllisWellApp()));
    await tester.pumpAndSettle();

    // Initial route is /today: the section title appears in the page body
    // and in the navigation destinations.
    expect(find.text('Today'), findsWidgets);
    expect(
      find.text('Everything due, scheduled or urgent today.'),
      findsOneWidget,
    );
  });

  testWidgets('navigating to another section swaps the placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: AllisWellApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Projects').last);
    await tester.pumpAndSettle();

    expect(
      find.text('Projects with colors, tasks, notes and documents.'),
      findsOneWidget,
    );
  });
}
