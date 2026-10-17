import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/calendar/apple/apple_calendar_gateway.dart';
import 'package:alliswell/src/features/calendar/apple/providers.dart';
import 'package:alliswell/src/features/integrations/providers.dart';
import 'package:alliswell/src/features/integrations/ui/caldav_calendar_card.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/sync_overrides.dart';

class _Gateway extends Fake implements AppleCalendarGateway {
  _Gateway(this.isSupported);

  @override
  final bool isSupported;
}

/// OPH-380 — Settings → iCloud or CalDAV calendar (ADR-0059).
void main() {
  late List<Uri> launched;

  Future<Widget> cardWith(FakeApi api, {bool appleDevice = false}) async {
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
        urlLauncherProvider.overrideWithValue((url) async {
          launched.add(url);
          return true;
        }),
        appleCalendarGatewayProvider.overrideWithValue(_Gateway(appleDevice)),
      ],
      child: MaterialApp(
        theme: buildAwTheme(Brightness.light),
        home: const Scaffold(
          body: SingleChildScrollView(child: CaldavCalendarCard()),
        ),
      ),
    );
  }

  setUp(() => launched = []);

  testWidgets('connector off and nothing connected → the card is absent', (
    tester,
  ) async {
    final api = FakeApi();
    await tester.pumpWidget(await cardWith(api));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('caldav-card')), findsNothing);
  });

  testWidgets('connector off with an account → status and disconnect only', (
    tester,
  ) async {
    final api = FakeApi()..seedCaldavAccount();
    await tester.pumpWidget(await cardWith(api));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('caldav-card')), findsOneWidget);
    expect(find.byKey(const Key('caldav-server-off')), findsOneWidget);
    expect(find.byKey(const Key('caldav-calendar-row')), findsNothing);
    expect(find.byKey(const Key('caldav-disconnect')), findsOneWidget);
  });

  testWidgets(
    'off Apple: iCloud is offered, the consent names this server, connect posts the form',
    (tester) async {
      final api = FakeApi()..caldavEnabled = true;
      await tester.pumpWidget(await cardWith(api));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('caldav-connect')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('caldav-server')), findsOneWidget);
      final consent = tester.widget<Text>(
        find.byKey(const Key('caldav-consent')),
      );
      expect(consent.data, contains('appleid.apple.com'));
      expect(consent.data, contains('alliswell.test'));

      await tester.tap(find.byKey(const Key('caldav-help')));
      await tester.pumpAndSettle();
      expect(launched.single.host, 'support.apple.com');

      await tester.enterText(
        find.byKey(const Key('caldav-username')),
        'ben@icloud.com',
      );
      await tester.enterText(
        find.byKey(const Key('caldav-password')),
        'abcd-efgh-ijkl-mnop',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('caldav-submit')));
      await tester.pumpAndSettle();

      expect(api.caldavConnectBodies.single, {
        'server': 'icloud',
        'username': 'ben@icloud.com',
        'password': 'abcd-efgh-ijkl-mnop',
      });
      // One calendar → chosen by the server; the card shows it.
      expect(find.byKey(const Key('caldav-calendar-row')), findsOneWidget);
      expect(find.text('Ev'), findsOneWidget);
      expect(find.text('ben@icloud.com · caldav.icloud.com'), findsOneWidget);
    },
  );

  testWidgets('on an iPhone or Mac: no iCloud option, the generic form only', (
    tester,
  ) async {
    final api = FakeApi()..caldavEnabled = true;
    await tester.pumpWidget(await cardWith(api, appleDevice: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('caldav-connect')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('caldav-server')), findsNothing);
    expect(find.byKey(const Key('caldav-url')), findsOneWidget);
    final consent = tester.widget<Text>(
      find.byKey(const Key('caldav-consent')),
    );
    expect(consent.data, isNot(contains('appleid.apple.com')));

    await tester.enterText(
      find.byKey(const Key('caldav-url')),
      'https://cloud.example.org',
    );
    await tester.enterText(find.byKey(const Key('caldav-username')), 'ben');
    await tester.enterText(find.byKey(const Key('caldav-password')), 'pw');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('caldav-submit')));
    await tester.pumpAndSettle();
    expect(api.caldavConnectBodies.single, {
      'server': 'generic',
      'url': 'https://cloud.example.org',
      'username': 'ben',
      'password': 'pw',
    });
  });

  testWidgets('every server answer becomes a sentence next to the form', (
    tester,
  ) async {
    final api = FakeApi()..caldavEnabled = true;
    await tester.pumpWidget(await cardWith(api));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('caldav-connect')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('caldav-username')), 'ben');
    await tester.enterText(find.byKey(const Key('caldav-password')), 'x');
    await tester.pumpAndSettle();

    final expected = {
      'CALDAV_AUTH_FAILED': 'calendar.caldav.authFailedIcloud',
      'CALDAV_NOT_CALDAV': 'calendar.caldav.notCaldav',
      'CALDAV_NO_CALENDARS': 'calendar.caldav.noCalendars',
      'CALDAV_BLOCKED_ADDRESS': 'calendar.caldav.blockedAddress',
      'CALDAV_REDIRECT_OFF_HOST': 'calendar.caldav.redirectOffHost',
      'CALDAV_UNREACHABLE': 'calendar.caldav.unreachable',
      'CALDAV_ALREADY_CONNECTED': 'calendar.caldav.alreadyConnected',
    };
    for (final MapEntry(key: code, value: message) in expected.entries) {
      api.caldavConnectError = code;
      await tester.ensureVisible(find.byKey(const Key('caldav-submit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('caldav-submit')));
      await tester.pumpAndSettle();
      expect(
        find.text(message.tr()),
        findsOneWidget,
        reason: '$code → $message',
      );
    }
    // Nothing was stored for any of them: the sheet is still open.
    expect(api.caldavAccounts, isEmpty);
    expect(find.byKey(const Key('caldav-submit')), findsOneWidget);
  });

  testWidgets('several calendars → the picker opens at once; choosing PATCHes', (
    tester,
  ) async {
    final api = FakeApi()
      ..caldavEnabled = true
      ..caldavCalendars = [
        {'url': '/c/home/', 'name': 'Ev', 'color': null},
        {'url': '/c/work/', 'name': 'İş', 'color': null},
      ];
    await tester.pumpWidget(await cardWith(api));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('caldav-connect')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('caldav-username')), 'ben');
    await tester.enterText(find.byKey(const Key('caldav-password')), 'pw');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('caldav-submit')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('caldav-calendar-/c/work/')));
    await tester.pumpAndSettle();
    expect(
      api.requests,
      contains(
        'PATCH /api/v1/integrations/caldav/accounts/${'CAL1'.padRight(26, '0')}',
      ),
    );
    expect(find.text('İş'), findsOneWidget);
  });

  testWidgets('disconnecting iCloud tells the user to revoke the password', (
    tester,
  ) async {
    final api = FakeApi()
      ..caldavEnabled = true
      ..seedCaldavAccount();
    await tester.pumpWidget(await cardWith(api));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('caldav-disconnect')));
    await tester.pumpAndSettle();
    expect(
      find.text('calendar.caldav.disconnectBodyIcloud'.tr()),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('confirm-delete')));
    await tester.pumpAndSettle();
    expect(api.caldavAccounts, isEmpty);
    expect(find.byKey(const Key('caldav-connect')), findsOneWidget);
  });

  testWidgets('a rejected password shows reconnect, prefilled', (tester) async {
    final api = FakeApi()
      ..caldavEnabled = true
      ..seedCaldavAccount(status: 'error');
    await tester.pumpWidget(await cardWith(api, appleDevice: true));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('caldav-reauth')), findsOneWidget);
    await tester.tap(find.byKey(const Key('caldav-reconnect')));
    await tester.pumpAndSettle();
    // Reconnecting an iCloud account works even on an Apple device.
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('caldav-username')))
          .controller!
          .text,
      'ben@icloud.com',
    );
    expect(find.byKey(const Key('caldav-url')), findsNothing);
  });

  testWidgets('loading the status records whether the server mirrors iCloud', (
    tester,
  ) async {
    final api = FakeApi()
      ..caldavEnabled = true
      ..seedCaldavAccount();
    await tester.pumpWidget(await cardWith(api));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CaldavCalendarCard)),
    );
    expect(container.read(serverMirrorsIcloudProvider), '1');
    expect(await localKv.get('caldav_icloud_active'), '1');

    api.caldavAccounts.clear();
    container.invalidate(caldavIntegrationProvider);
    await tester.pumpAndSettle();
    expect(container.read(serverMirrorsIcloudProvider), '');
  });
}
