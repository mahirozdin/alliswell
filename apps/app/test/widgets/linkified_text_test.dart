import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/theme/theme.dart';
import 'package:alliswell/src/widgets/linkified_text.dart';

/// OPH-164 — tappable URLs in body text.
void main() {
  Widget host(Widget child) => MaterialApp(
    theme: buildAwTheme(Brightness.light),
    home: Scaffold(body: Center(child: child)),
  );

  testWidgets('tapping a link fires onOpen with the launchable uri', (
    tester,
  ) async {
    final opened = <Uri>[];
    await tester.pumpWidget(
      host(LinkifiedText('www.alliswell.dev', onOpen: opened.add)),
    );

    await tester.tap(find.byType(LinkifiedText));
    expect(opened.single.toString(), 'https://www.alliswell.dev');
  });

  testWidgets('mixed text renders losslessly around the link', (tester) async {
    await tester.pumpWidget(
      host(LinkifiedText('önce https://x.dev sonra', onOpen: (_) {})),
    );

    expect(
      find.text('önce https://x.dev sonra', findRichText: true),
      findsOneWidget,
    );
  });
}
