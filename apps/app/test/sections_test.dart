import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/sections.dart';

/// EE-084 — the navigation's index arithmetic, held still.
///
/// `NavigationBar.selectedIndex` is a position among the DESTINATIONS and
/// `goBranch` takes a position among the BRANCHES. Those were the same list
/// until a section arrived that is not always drawn, and the failure mode of
/// getting it wrong is the quietest kind there is: every tab after a hidden one
/// opens the wrong screen, with no compiler error, no exception, and no
/// existing test that would notice.
///
/// The acceptance ("sekme CE'de görünmez") is the first test here. The rest
/// exist because today's answer is accidentally safe — `tickets` is the LAST
/// enum member, so hiding it shifts nothing — and an assertion that only ever
/// saw the identity mapping would pass on a broken implementation. So the
/// mapping is also exercised against a MIDDLE-hidden list, which is the case
/// the next hidden section will actually be.
void main() {
  group('which sections are drawn', () {
    test('without the entitlement the service desk is absent', () {
      final visible = visibleAppSections(itsm: false);
      expect(visible, isNot(contains(AppSection.tickets)));
      expect(visible.length, AppSection.values.length - 1);
    });

    test('with it, every section is drawn, in enum order', () {
      final visible = visibleAppSections(itsm: true);
      expect(visible, AppSection.values);
    });

    test('only the service desk is conditional', () {
      final conditional = AppSection.values
          .where((s) => s.hiddenWithoutEntitlement)
          .toList();
      expect(conditional, [AppSection.tickets]);
    });
  });

  group('destination ↔ branch', () {
    test('a tap lands on the branch that draws the section it shows', () {
      for (final itsm in [true, false]) {
        final visible = visibleAppSections(itsm: itsm);
        for (var i = 0; i < visible.length; i++) {
          final branch = branchIndexFor(visible, i);
          expect(
            AppSection.values[branch],
            visible[i],
            reason:
                'tapping destination $i (itsm=$itsm) must open ${visible[i]}',
          );
          // …and back again, so the highlight follows the screen.
          expect(destinationIndexFor(visible, branch), i);
        }
      }
    });

    test('the mapping survives a section hidden in the MIDDLE', () {
      // Not today's list: today's hidden section is last, so the identity
      // mapping would pass even if these functions were `(i) => i`.
      final visible = [...AppSection.values]..remove(AppSection.projects);
      final projects = AppSection.values.indexOf(AppSection.projects);
      for (var i = 0; i < visible.length; i++) {
        expect(AppSection.values[branchIndexFor(visible, i)], visible[i]);
        expect(destinationIndexFor(visible, branchIndexFor(visible, i)), i);
      }
      // Every destination at or after the gap points PAST its own position —
      // which is precisely the shift a naive `selectedIndex: currentIndex`
      // would get wrong.
      expect(branchIndexFor(visible, projects), projects + 1);
      // And a branch nobody draws answers -1 rather than throwing.
      expect(destinationIndexFor(visible, projects), -1);
    });
  });
}
