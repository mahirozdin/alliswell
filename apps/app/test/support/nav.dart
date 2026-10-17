import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A shell destination by its title, at any width.
///
/// OPH-374: on a phone the bottom bar writes only the SELECTED tab's label
/// when a tab is narrower than 64 px — which, with the search button beside
/// the bar, is most phones. The other tabs keep their icon and their tooltip,
/// so a phone test finds a tab by its tooltip; the rail (wide) still writes
/// every label.
Finder navTab(String title) {
  final bar = find.byType(NavigationBar);
  if (bar.evaluate().isNotEmpty) {
    return find.descendant(of: bar, matching: find.byTooltip(title)).last;
  }
  return find.text(title).last;
}
