// OPH-398 (polish 2, R-03): a menu's or a sheet's barrier only closes it.
//
// Material's popup menu gives its barrier ("Dismiss menu") the whole screen
// as its accessibility rect, so the rect's centre — where VoiceOver draws the
// focus and where an accessibility tap lands — sat on the menu. Pressing it
// picked the item under the middle of the screen: on the iOS simulator the
// Home view menu switched the order to "Title". These tests pin the barrier's
// node to the free area beside the menu (or above the sheet), check that a
// tap at its centre closes without choosing, and that items still work.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alliswell/src/core/list_sort.dart';
import 'package:alliswell/src/features/home/home_view_menu.dart';
import 'package:alliswell/src/features/tasks/data/task_sort.dart';
import 'package:alliswell/src/theme/theme.dart';
import 'package:alliswell/src/widgets/popup_menu.dart';

const _choices = kTaskSortChoices;

void main() {
  late List<String> calls;

  setUp(() => calls = []);

  Future<void> pumpHome(WidgetTester tester, {required Widget body}) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAwTheme(Brightness.dark),
        home: Scaffold(
          appBar: AppBar(
            title: const Text('Home'),
            actions: [
              HomeViewMenuButton(
                isBoard: false,
                calendarVisible: true,
                sortChoices: _choices,
                sort: const AwSortState('date', descending: false),
                onView: (v) => calls.add('view:$v'),
                onToggleCalendar: () => calls.add('calendar'),
                onSort: (s) => calls.add('sort:${s.encode()}'),
                onEditColumns: () => calls.add('columns'),
              ),
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.settings_outlined),
                tooltip: 'Settings',
              ),
            ],
          ),
          body: body,
        ),
      ),
    );
  }

  SemanticsNode barrierNode(WidgetTester tester, String label) {
    final node = tester.getSemantics(find.bySemanticsLabel(label));
    // The barrier spans the overlay, which is the screen here, so its rect
    // is in screen coordinates.
    expect(node.transform, isNull);
    return node;
  }

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('the view menu barrier sits beside the menu, not on it '
        '(${platform.name})', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      final handle = tester.ensureSemantics();
      await pumpHome(tester, body: const SizedBox.expand());

      await tester.tap(find.byKey(const Key('home-view-menu')));
      await tester.pumpAndSettle();

      final menu = tester.getRect(find.byType(ListBody).last);
      final barrier = barrierNode(tester, 'Dismiss menu');
      expect(
        barrier.rect.overlaps(menu),
        isFalse,
        reason: 'barrier ${barrier.rect} vs menu $menu',
      );
      // Not a sliver: a target a finger and VoiceOver can find.
      expect(barrier.rect.width, greaterThanOrEqualTo(44));
      expect(barrier.rect.height, greaterThanOrEqualTo(44));

      // A tap where the node says it is closes the menu and picks nothing.
      await tester.tapAt(barrier.rect.center);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sort-option-title')), findsNothing);
      expect(calls, isEmpty);

      handle.dispose();
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('the barrier\'s own tap action closes the menu without '
      'choosing', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final handle = tester.ensureSemantics();
    await pumpHome(tester, body: const SizedBox.expand());
    await tester.tap(find.byKey(const Key('home-view-menu')));
    await tester.pumpAndSettle();

    barrierNode(tester, 'Dismiss menu');
    tester.semantics.tap(find.semantics.byLabel('Dismiss menu'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sort-option-title')), findsNothing);
    expect(calls, isEmpty);

    handle.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('an item still chooses, and the menu keeps Material\'s '
      'placement', (tester) async {
    await pumpHome(tester, body: const SizedBox.expand());
    final button = tester.getRect(find.byKey(const Key('home-view-menu')));
    await tester.tap(find.byKey(const Key('home-view-menu')));
    await tester.pumpAndSettle();

    final menu = tester.getRect(find.byType(ListBody).last);
    // Over the button, its right edge on the button's (the button is nearer
    // the right edge), inside the safe area. The list sits 8 px inside the
    // menu's surface.
    expect(menu.top - 8, greaterThanOrEqualTo(59 + 8));
    expect(menu.top - 8, lessThanOrEqualTo(button.top + 8));
    expect(menu.right, moreOrLessEquals(button.right, epsilon: 0.5));

    await tester.tap(find.byKey(const Key('sort-option-title')));
    await tester.pumpAndSettle();
    expect(calls, ['sort:title:asc']);
    expect(find.byKey(const Key('sort-option-title')), findsNothing);
  });

  testWidgets('a bottom sheet barrier is the strip above the sheet, and a tap '
      'at its centre closes it', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final handle = tester.ensureSemantics();
    await pumpHome(
      tester,
      body: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              useRootNavigator: true,
              isScrollControlled: true,
              useSafeArea: true,
              builder: (_) => const SizedBox(
                height: 420,
                child: Center(child: Text('sheet body')),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final sheet = tester.getRect(find.byType(BottomSheet));
    final barrier = barrierNode(tester, 'Scrim');
    expect(barrier.rect.overlaps(sheet), isFalse);
    await tester.tapAt(barrier.rect.center);
    await tester.pumpAndSettle();
    expect(find.text('sheet body'), findsNothing);

    handle.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  group('awBarrierSemanticsClip', () {
    const screen = Size(400, 800);

    test('takes the largest free strip', () {
      // A wide menu at the top: the strip below is the largest.
      expect(
        awBarrierSemanticsClip(screen, const Rect.fromLTRB(100, 60, 390, 500)),
        const EdgeInsets.only(top: 500),
      );
      // Menu low on the screen: the strip above.
      expect(
        awBarrierSemanticsClip(screen, const Rect.fromLTRB(10, 600, 390, 790)),
        const EdgeInsets.only(bottom: 200),
      );
      // A tall menu on the right: the strip to its left.
      expect(
        awBarrierSemanticsClip(screen, const Rect.fromLTRB(250, 8, 392, 792)),
        const EdgeInsets.only(right: 150),
      );
      // A tall menu on the left: the strip to its right.
      expect(
        awBarrierSemanticsClip(screen, const Rect.fromLTRB(8, 8, 150, 792)),
        const EdgeInsets.only(left: 150),
      );
    });
  });
}
