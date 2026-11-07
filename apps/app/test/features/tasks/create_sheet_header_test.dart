import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// OPH-403 (U-11) — the new-task sheet's own header: "Cancel" on the left,
/// "Add" on the right (dead while the title is empty), the keyboard's Done
/// creates, Ctrl/⌘+Enter creates on a desktop, where the form is a dialog,
/// and a swipe down never throws away what was typed without asking.
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

const _phone = Size(393, 852);
const _desktop = Size(1280, 900);

final _title = find.byKey(const Key('task-sheet-title'));
final _add = find.byKey(const Key('task-sheet-create'));
final _cancel = find.byKey(const Key('task-sheet-cancel'));

Future<void> _surface(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  if (size == _phone) {
    tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 59, bottom: 34);
  }
  addTearDown(tester.view.reset);
}

Future<void> _open(WidgetTester tester, FakeApi api) async {
  await tester.pumpWidget(await _app(api));
  await tester.pumpAndSettle();
  final context = tester.element(find.byType(Scaffold).first);
  // ignore: unawaited_futures
  showTaskCreateSheet(context);
  await tester.pumpAndSettle();
  expect(_title, findsOneWidget);
}

bool _enabled(WidgetTester tester) =>
    tester.widget<TextButton>(_add).onPressed != null;

/// A finger pulling the sheet down by its drag handle, far and fast enough
/// that a sheet with nothing in it closes.
Future<void> _swipeDown(WidgetTester tester) async {
  final top = tester.getTopLeft(find.byType(BottomSheet));
  await tester.flingFrom(
    top + const Offset(196, 12),
    const Offset(0, 500),
    2000,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('phone: Cancel and Add sit in the header on the first screen; '
      'Add is dead until the title has text, then creates', (tester) async {
    await _surface(tester, _phone);
    final api = FakeApi();
    await _open(tester, api);

    // The keyboard is up under the focused title.
    tester.view.viewInsets = const FakeViewPadding(bottom: 336);
    await tester.pumpAndSettle();

    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);
    final keyboardTop = 852.0 - 336;
    expect(tester.getRect(_add).bottom, lessThan(keyboardTop));
    expect(tester.getRect(_cancel).bottom, lessThan(keyboardTop));
    // Both are full tap targets (DESIGN G-taps).
    expect(tester.getSize(_add).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(_cancel).height, greaterThanOrEqualTo(48));
    // Add is the header's right end, Cancel its left.
    expect(
      tester.getCenter(_add).dx,
      greaterThan(tester.getCenter(_cancel).dx),
    );

    expect(_enabled(tester), isFalse);
    await tester.enterText(_title, '   ');
    await tester.pump();
    expect(_enabled(tester), isFalse, reason: 'blank is not a title');

    await tester.enterText(_title, 'Kira öde');
    await tester.pump();
    expect(_enabled(tester), isTrue);

    await tester.tap(_add);
    await tester.pumpAndSettle();
    expect(api.tasks, hasLength(1));
    expect(api.tasks.single['title'], 'Kira öde');
    expect(_title, findsNothing);
  });

  testWidgets("the keyboard's Done creates when the title has text, and "
      'does nothing when it is empty', (tester) async {
    await _surface(tester, _phone);
    final api = FakeApi();
    await _open(tester, api);

    await tester.showKeyboard(_title);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(api.tasks, isEmpty);
    expect(_title, findsOneWidget, reason: 'an empty Done keeps the sheet');

    await tester.enterText(_title, 'Faturayı öde');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(api.tasks, hasLength(1));
    expect(api.tasks.single['title'], 'Faturayı öde');
    expect(_title, findsNothing);
  });

  testWidgets('desktop: the form opens as a dialog, and Ctrl+Enter or '
      '⌘+Enter creates from any field', (tester) async {
    await _surface(tester, _desktop);
    final api = FakeApi();
    await _open(tester, api);

    expect(find.byType(BottomSheet), findsNothing);
    expect(
      find.ancestor(of: _title, matching: find.byType(Dialog)),
      findsOneWidget,
    );
    expect(tester.getSize(find.byType(TaskCreateSheet)).width, 640);

    // Empty title: the shortcut does nothing.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(api.tasks, isEmpty);
    expect(_title, findsOneWidget);

    await tester.enterText(_title, 'Rapor yaz');
    // Typed from the description, a multi-line field where plain Enter is a
    // new line.
    await tester.enterText(
      find.byKey(const Key('task-sheet-description')),
      'ilk taslak',
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(api.tasks, hasLength(1));
    expect(api.tasks.single['description'], 'ilk taslak');
    expect(_title, findsNothing);

    final context = tester.element(find.byType(Scaffold).first);
    // ignore: unawaited_futures
    showTaskCreateSheet(context);
    await tester.pumpAndSettle();
    await tester.enterText(_title, 'Mail at');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(api.tasks, hasLength(2));
    expect(_title, findsNothing);
  });

  testWidgets('a swipe down on an empty sheet closes it at once', (
    tester,
  ) async {
    await _surface(tester, _phone);
    final api = FakeApi();
    await _open(tester, api);

    await _swipeDown(tester);
    expect(_title, findsNothing);
    expect(find.text('Discard what you typed?'), findsNothing);
  });

  testWidgets('a swipe down with text asks first; Keep editing keeps it, '
      'Discard closes without a task', (tester) async {
    await _surface(tester, _phone);
    final api = FakeApi();
    await _open(tester, api);
    await tester.enterText(_title, 'Yarım kalan');
    await tester.pump();

    await _swipeDown(tester);
    expect(find.text('Discard what you typed?'), findsOneWidget);
    expect(_title, findsOneWidget, reason: 'the sheet is still there');

    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('Discard what you typed?'), findsNothing);
    expect(find.text('Yarım kalan'), findsOneWidget);
    // Back where it was: the sheet's top is on screen again, not parked
    // below the fold by the drag.
    expect(tester.getTopLeft(find.byType(BottomSheet)).dy, lessThan(852 / 2));

    await _swipeDown(tester);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(_title, findsNothing);
    expect(api.tasks, isEmpty);
  });

  testWidgets('Cancel and the scrim ask too once something is typed; '
      'Cancel on an empty sheet just closes', (tester) async {
    await _surface(tester, _phone);
    final api = FakeApi();
    await _open(tester, api);

    await tester.tap(_cancel);
    await tester.pumpAndSettle();
    expect(_title, findsNothing);
    expect(find.text('Discard what you typed?'), findsNothing);

    final context = tester.element(find.byType(Scaffold).first);
    // ignore: unawaited_futures
    showTaskCreateSheet(context);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('task-sheet-description')),
      'not alınacak',
    );
    await tester.pump();

    await tester.tap(_cancel);
    await tester.pumpAndSettle();
    expect(find.text('Discard what you typed?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();

    // The dimmed strip above the sheet (OPH-395).
    await tester.tapAt(const Offset(196, 59 + 24));
    await tester.pumpAndSettle();
    expect(find.text('Discard what you typed?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(_title, findsNothing);
    expect(api.tasks, isEmpty);
  });

  testWidgets('desktop: Escape on a dialog with text asks before closing', (
    tester,
  ) async {
    await _surface(tester, _desktop);
    final api = FakeApi();
    await _open(tester, api);
    await tester.enterText(_title, 'Taslak');
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Discard what you typed?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(_title, findsNothing);
    expect(api.tasks, isEmpty);
  });
}
