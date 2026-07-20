import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/integrations/providers.dart';
import 'package:alliswell/src/features/integrations/ui/google_calendar_card.dart';
import 'package:alliswell/src/theme/theme.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/sync_overrides.dart';

/// OPH-080 — Settings → Google Calendar. The API vertical (OPH-070…076) has
/// been complete for a while; these tests cover the part that makes it
/// reachable at all.
void main() {
  late List<Uri> launched;

  /// Pumps just the card (Settings' other rows have their own coverage), with
  /// the browser hand-off captured instead of performed.
  Future<Widget> cardWith(FakeApi api) async {
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
      ],
      child: MaterialApp(
        theme: buildAwTheme(Brightness.light),
        home: const Scaffold(
          body: SingleChildScrollView(child: GoogleCalendarCard()),
        ),
      ),
    );
  }

  setUp(() => launched = []);

  testWidgets('a server without Google credentials says so, quietly', (
    tester,
  ) async {
    final api = FakeApi()..googleConfigured = false;

    await tester.pumpWidget(await cardWith(api));
    await tester.pumpAndSettle();

    // Optional integration: not an error state, just a fact — and the hint a
    // self-hoster needs, since they are usually their own admin.
    expect(find.byKey(const Key('google-not-configured')), findsOneWidget);
    expect(find.byKey(const Key('google-connect')), findsNothing);
  });

  testWidgets('connecting opens the consent page in a real browser', (
    tester,
  ) async {
    final api = FakeApi();

    await tester.pumpWidget(await cardWith(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('google-connect')));
    await tester.pumpAndSettle();

    // The app never touches the OAuth code — identity rides in the server's
    // signed state and the callback is server-rendered (ADR-0006).
    expect(api.googleConnectCalls, hasLength(1));
    expect(launched.single.toString(), api.googleConnectCalls.single);
    expect(
      api.requests,
      contains(
        'POST /api/v1/workspaces/${api.workspaceId}/integrations/google/connect',
      ),
    );
  });

  testWidgets(
    'a connected account still needs a calendar before anything mirrors',
    (tester) async {
      final api = FakeApi()..seedGoogleAccount(email: 'mahir@gmail.com');

      await tester.pumpWidget(await cardWith(api));
      await tester.pumpAndSettle();

      expect(find.text('mahir@gmail.com'), findsOneWidget);
      expect(find.text('Choose which calendar to use'), findsOneWidget);

      await tester.tap(find.byKey(const Key('google-calendar-row')));
      await tester.pumpAndSettle();

      // The picker lists what Google returned…
      expect(find.text('Ana Takvim'), findsOneWidget);
      expect(find.text('İş'), findsOneWidget);

      // Nothing has pulled yet — the pull below is attributable to the choice.
      expect(
        api.requests.any((r) => r.startsWith('GET /api/v1/sync/pull')),
        isFalse,
      );

      await tester.tap(find.byKey(const Key('calendar-is-takvimi')));
      await tester.pumpAndSettle();

      // …and choosing it is what starts the mirroring (the server backfills).
      expect(api.googleAccounts.single['defaultCalendarId'], 'is-takvimi');
      expect(find.text('is-takvimi'), findsOneWidget);

      // OPH-160: choosing also pulls right away — the server enqueued the
      // first sync at choose time; events must not wait for the 60 s interval.
      expect(
        api.requests.where((r) => r.startsWith('GET /api/v1/sync/pull')),
        isNotEmpty,
      );
    },
  );

  testWidgets('an account Google signed out of asks to be reconnected', (
    tester,
  ) async {
    final api = FakeApi()
      ..seedGoogleAccount(
        status: 'error',
        defaultCalendarId: 'primary',
        lastError: 'refresh token rejected — reconnect the Google account',
      );

    await tester.pumpWidget(await cardWith(api));
    await tester.pumpAndSettle();

    // No silent decay: the account is visibly broken, with a way out.
    expect(find.byKey(const Key('google-reauth')), findsOneWidget);
    expect(find.byKey(const Key('google-calendar-row')), findsNothing);
    expect(find.byKey(const Key('google-disconnect')), findsOneWidget);
  });

  testWidgets('the picker offers a retry when Google rejects our credentials', (
    tester,
  ) async {
    final api = FakeApi()
      ..seedGoogleAccount()
      ..googleCalendars = null; // 502 CALENDAR_ACCOUNT_REAUTH_REQUIRED

    await tester.pumpWidget(await cardWith(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('google-calendar-row')));
    await tester.pumpAndSettle();

    expect(find.text('Google needs you to sign in again.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget); // never a dead end
  });

  testWidgets('disconnecting drops the account and offers to connect again', (
    tester,
  ) async {
    final api = FakeApi()..seedGoogleAccount(defaultCalendarId: 'primary');

    await tester.pumpWidget(await cardWith(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('google-disconnect')));
    await tester.pumpAndSettle();

    expect(api.googleAccounts, isEmpty);
    expect(find.byKey(const Key('google-connect')), findsOneWidget);
  });
}
