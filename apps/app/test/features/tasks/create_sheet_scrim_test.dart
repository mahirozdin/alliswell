import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/tasks/ui/task_create_sheet.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/sync_overrides.dart';

/// OPH-395 (E-24) — the new-task sheet closes when the dimmed area is tapped.
///
/// With the keyboard up, the sheet (its content plus the keyboard inset) grew
/// to the very top of the safe area, so the scrim — "Close" to VoiceOver —
/// had no visible area left: a tap on it landed on the sheet, and only a drag
/// on the handle closed it. The sheet now always leaves a strip of scrim at
/// the top, at least one tap target tall.
Future<Widget> _app(FakeApi api) async {
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

void main() {
  testWidgets(
    'a tap on the scrim above the sheet closes it, keyboard up on a phone',
    (tester) async {
      // iPhone 15-ish: 393 × 852 pt, 59 pt status area, 336 pt keyboard.
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
      tester.view.viewPadding = const FakeViewPadding(top: 59, bottom: 34);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(await _app(FakeApi()));
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(Scaffold).first);
      // ignore: unawaited_futures
      showTaskCreateSheet(context);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('task-sheet-title')), findsOneWidget);

      // The keyboard comes up under the focused title field.
      tester.view.viewInsets = const FakeViewPadding(bottom: 336);
      await tester.pumpAndSettle();

      final sheetTop = tester.getTopLeft(find.byType(BottomSheet)).dy;
      expect(
        sheetTop - 59,
        greaterThanOrEqualTo(kMinInteractiveDimension),
        reason: 'no tappable scrim left above the sheet',
      );

      await tester.tapAt(const Offset(196, 59 + 24));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('task-sheet-title')), findsNothing);
    },
  );
}
