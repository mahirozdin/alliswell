import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/widgets/tab_capsule.dart';

/// A shell destination by its title, at any width.
///
/// OPH-396: the phone capsule writes every tab's label (ADR-0062), so a
/// phone test finds a tab by its text inside the capsule; the rail (wide)
/// writes every label too. A section behind the phone's "More" slot has no
/// tab of its own — open "More" first.
Finder navTab(String title) {
  final bar = find.byType(AwTabCapsule);
  if (bar.evaluate().isNotEmpty) {
    return find.descendant(of: bar, matching: find.text(title)).last;
  }
  return find.text(title).last;
}
