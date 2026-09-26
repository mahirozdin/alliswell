import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/features/auth/providers.dart'
    show apiBaseUrlProvider;
import 'package:alliswell/src/features/ee/ui/tickets_home.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/router.dart';

import '../projects/fake_api.dart';
import '../settings/settings_groups_test.dart' show app;

/// EE-290 — the service desk is a TEAM's, not the instance's.
///
/// The tab used to be drawn wherever the instance was licensed for it, so on
/// the hosted service's own address somebody on their own met "Requests" in
/// the navigation: a list that could not load and a form that could not send
/// (every request endpoint answers only on a team's address). It is now drawn
/// only in a team's window, and a shell left on its branch — an address typed
/// or restored on the web — moves to Home once the answer is settled.
FakeApi _licensed() => FakeApi()
  ..eeState = 'active'
  ..eeFeatures = ['teams', 'itsm']
  ..eeBaseDomain = 'example.com';

void main() {
  setUp(() async {
    AwI18n.instance.setActiveCached(const Locale('en'));
    // The status cache is a process-wide singleton (see ee_status_test).
    await localKv.remove('alliswell_ee_status::user-1');
  });

  GoRouter routerOf() => GoRouter.of(awRootNavigatorKey.currentContext!);
  Finder desk() => find.text('nav.tickets'.tr());

  Future<void> pumpAt(WidgetTester tester, String serverUrl) async {
    await tester.pumpWidget(
      await app(
        _licensed(),
        extra: [apiBaseUrlProvider.overrideWithValue(serverUrl)],
      ),
    );
    await tester.pumpAndSettle();
    // The shell is up, and the navigation is drawn.
    expect(find.text('nav.home'.tr()), findsWidgets);
  }

  testWidgets('on the service\'s own address a licensed instance draws no '
      'desk', (tester) async {
    await pumpAt(tester, 'https://api.example.com');
    expect(desk(), findsNothing);
  });

  testWidgets('on a team\'s address the desk is drawn, and stays', (
    tester,
  ) async {
    await pumpAt(tester, 'https://acme.example.com');
    expect(desk(), findsOneWidget);

    routerOf().go('/tickets');
    await tester.pumpAndSettle();
    expect(routerOf().state.uri.toString(), '/tickets');
    expect(find.byType(EeTicketsHome), findsOneWidget);
  });

  testWidgets('a shell left on the desk\'s branch where there is no desk moves '
      'home', (tester) async {
    await pumpAt(tester, 'https://api.example.com');

    routerOf().go('/tickets');
    await tester.pumpAndSettle();

    expect(routerOf().state.uri.toString(), '/home');
    expect(find.byType(EeTicketsHome), findsNothing);
  });

  testWidgets('a license with no extension behind it draws no desk even on a '
      'team-shaped address', (tester) async {
    await tester.pumpWidget(
      await app(
        _licensed()..eeOverlay = 'absent',
        extra: [
          apiBaseUrlProvider.overrideWithValue('https://acme.example.com'),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('nav.home'.tr()), findsWidgets);
    expect(desk(), findsNothing);
  });
}
