import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/theme/tokens.dart';
import 'package:alliswell/src/widgets/fab_clearance.dart';
import 'package:alliswell/src/widgets/status_views.dart';

/// R3-1 (OPH-363): a page's OWN floating button is cleared by asking for it —
/// `fab:` on [awListPadding] / [awPagePadding] / [awScrollEndPadding] — and
/// every Scaffold that carries one asks. The docked Quick Access bubble
/// (OPH-362) no longer hides a screen that forgot.
void main() {
  Future<BuildContext> pump(WidgetTester tester, {double bubble = 0}) async {
    late BuildContext captured;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(),
        child: AwBubbleClearance(
          extent: bubble,
          child: Builder(
            builder: (context) {
              captured = context;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    return captured;
  }

  testWidgets('fab: adds the FAB lane to the end of every padding helper', (
    tester,
  ) async {
    final context = await pump(tester);
    expect(awScrollEndPadding(context, AwSpace.x4), AwSpace.x4);
    expect(
      awScrollEndPadding(context, AwSpace.x4, fab: true),
      AwSpace.x4 + AwFabClearance.lane,
    );
    expect(
      awPagePadding(context, AwSpace.x4, fab: true).bottom,
      AwSpace.x4 + AwFabClearance.lane,
    );
    expect(
      awListPadding(context, fab: true).bottom,
      AwSpace.x6 + AwFabClearance.lane,
    );
    expect(awListPadding(context).bottom, AwSpace.x6);
  });

  testWidgets('a bubble parked higher than the button still wins', (
    tester,
  ) async {
    final context = await pump(tester, bubble: 200);
    expect(awScrollEndPadding(context, AwSpace.x4, fab: true), 200);
  });

  test('every Scaffold with its own floating button clears it at the end of '
      'its list', () {
    // The shell's buttons are published by AwFabClearance instead.
    const exempt = {'lib/src/screens/home_shell.dart'};
    final fabUse = RegExp(r'floatingActionButton:');
    final asks = RegExp(r'\bfab: ');
    final missing = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final path = file.path.replaceAll(r'\', '/');
      if (exempt.contains(path)) continue;
      final source = file.readAsStringSync();
      final fabs = fabUse.allMatches(source).length;
      if (fabs == 0) continue;
      if (asks.allMatches(source).length < fabs) missing.add(path);
    }
    expect(
      missing,
      isEmpty,
      reason:
          'these screens draw a floating button over a list that does not '
          'scroll out from under it — pass fab: to its padding helper',
    );
  });
}
