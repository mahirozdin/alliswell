import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/home/month_calendar.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/sync_overrides.dart';

Future<Widget> signedInApp(FakeApi api) async {
  SharedPreferences.setMockInitialValues({});
  final store = InMemorySecretStore();
  await TokenStorage(store).save(fakeSession());
  return ProviderScope(
    retry: awRetry,
    overrides: [
      ...syncTestOverrides(),
      secretStoreProvider.overrideWithValue(store),
      apiClientProvider.overrideWithValue(
        fakeDio(FakeHttpClientAdapter(api.handle)),
      ),
    ],
    child: const AllisWellApp(),
  );
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void main() {
  // OPH-103: on phones the month calendar used to be a fixed header eating half
  // the screen. It must now scroll away with the list.
  testWidgets('the month calendar scrolls off with the list, then returns', (
    tester,
  ) async {
    _phone(tester);
    final api = FakeApi();
    for (var i = 0; i < 25; i++) {
      api.seedTask(title: 'İş ${i.toString().padLeft(2, '0')}');
    }
    await tester.pumpWidget(await signedInApp(api));
    await tester.pumpAndSettle();

    // Visible by default, at the top of the scroll view.
    expect(find.byType(MonthCalendar).hitTestable(), findsOneWidget);

    // Scroll the list up — the calendar leaves the viewport (not pinned).
    await tester.drag(
      find.byKey(const Key('home-scroll')),
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    expect(
      find.byType(MonthCalendar).hitTestable(),
      findsNothing,
      reason: 'the calendar must scroll away, not stay fixed at the top',
    );

    // Scroll back to the top — it comes back.
    await tester.drag(
      find.byKey(const Key('home-scroll')),
      const Offset(0, 700),
    );
    await tester.pumpAndSettle();
    expect(find.byType(MonthCalendar).hitTestable(), findsOneWidget);
  });

  testWidgets('Hide calendar removes it while the quick-add stays pinned', (
    tester,
  ) async {
    _phone(tester);
    final api = FakeApi();
    await tester.pumpWidget(await signedInApp(api));
    await tester.pumpAndSettle();

    expect(find.byType(MonthCalendar), findsOneWidget);
    await tester.tap(find.byKey(const Key('toggle-calendar')));
    await tester.pumpAndSettle();
    expect(find.byType(MonthCalendar), findsNothing);

    // The quick-add bar is fixed above the scroll view and still captures.
    await tester.enterText(find.byKey(const Key('home-quick-add')), 'Yeni iş');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(api.tasks.any((t) => t['title'] == 'Yeni iş'), isTrue);
  });
}
