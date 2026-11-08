import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/router.dart';

void main() {
  String? redirect({
    bool restoring = false,
    bool loggedIn = false,
    required String at,
  }) => computeAuthRedirect(
    isRestoring: restoring,
    isLoggedIn: loggedIn,
    location: at,
  );

  test('while restoring, everything parks on /splash', () {
    expect(redirect(restoring: true, at: '/home'), '/splash');
    expect(redirect(restoring: true, at: '/login'), '/splash');
    expect(redirect(restoring: true, at: '/splash'), isNull);
  });

  test('OPH-413 (K3): "Start free" lands on the sign-up form, not sign-in', () {
    String? signup(
      String at, {
      bool loggedIn = false,
      bool restoring = false,
    }) => computeAuthRedirect(
      isRestoring: restoring,
      isLoggedIn: loggedIn,
      location: at,
      preferSignup: true,
    );
    // The cold start: the restore parks on the splash, then signed out.
    expect(signup('/splash', restoring: true), isNull);
    expect(signup('/home', restoring: true), '/splash');
    expect(signup('/splash'), '/register');
    expect(signup('/'), '/register');
    expect(signup('/home'), '/register');
    // A form the person chose stays where it is: "Sign in instead" works.
    expect(signup('/login'), isNull);
    expect(signup('/register'), isNull);
    // Signed in, the hint means nothing.
    expect(signup('/register', loggedIn: true), '/home');
    expect(signup('/home', loggedIn: true), isNull);
  });

  test(
    'OPH-413: only signup=1 on the page address asks for the sign-up form',
    () {
      expect(
        awWantsSignup(Uri.parse('https://alliswell.space/app/?signup=1')),
        isTrue,
      );
      expect(
        awWantsSignup(
          Uri.parse('https://alliswell.space/app/?signup=1#/splash'),
        ),
        isTrue,
      );
      expect(awWantsSignup(Uri.parse('https://alliswell.space/app/')), isFalse);
      expect(
        awWantsSignup(Uri.parse('https://alliswell.space/app/?signup=0')),
        isFalse,
      );
      expect(
        awWantsSignup(Uri.parse('https://alliswell.space/app/#/login')),
        isFalse,
      );
    },
  );

  test('OPH-413: the sign-up hint is spent once it has been used', () {
    final container = ProviderContainer(
      overrides: [signupIntentProvider.overrideWith(() => SignupIntent(true))],
    );
    addTearDown(container.dispose);
    expect(container.read(signupIntentProvider), isTrue);
    container.read(signupIntentProvider.notifier).spend();
    expect(container.read(signupIntentProvider), isFalse);
    // Off the web (and in this test VM) nothing asks for it.
    final plain = ProviderContainer();
    addTearDown(plain.dispose);
    expect(plain.read(signupIntentProvider), isFalse);
  });

  test('signed out: only /login and /register are reachable', () {
    expect(redirect(at: '/home'), '/login');
    expect(redirect(at: '/settings'), '/login');
    expect(redirect(at: '/splash'), '/login');
    expect(redirect(at: '/login'), isNull);
    expect(redirect(at: '/register'), isNull);
  });

  test('UI-AUDIT #5: an invitation opens signed OUT — its reader may have '
      'no account yet, and the team address refuses free sign-up', () {
    // Before OPH-356 this was '/login': the invitee was sent to sign in on
    // the service's own address, with no account and no way to make one.
    expect(redirect(at: '/join/tok_1234567890abcdef'), isNull);
    expect(redirect(loggedIn: true, at: '/join/tok_1234567890abcdef'), isNull);
    // …and mid-restore too: parked on the splash, a cold start lost it.
    expect(redirect(restoring: true, at: '/join/tok_1234567890abcdef'), isNull);
    expect(isJoinLocation('/join/x'), isTrue);
    expect(isJoinLocation('/joined'), isFalse);
  });

  test('OPH-406: the forgot form opens signed out, a reset link even '
      'mid-restore, and both send a signed-in person Home', () {
    expect(redirect(at: '/forgot-password'), isNull);
    expect(redirect(loggedIn: true, at: '/forgot-password'), '/home');
    expect(redirect(at: '/reset-password'), isNull);
    // A cold start on the web opens at the link: parked on the splash, the
    // token in its address was lost.
    expect(redirect(restoring: true, at: '/reset-password'), isNull);
    expect(redirect(loggedIn: true, at: '/reset-password'), '/home');
  });

  test('signed in: auth and splash pages bounce to Home', () {
    expect(redirect(loggedIn: true, at: '/login'), '/home');
    expect(redirect(loggedIn: true, at: '/register'), '/home');
    expect(redirect(loggedIn: true, at: '/splash'), '/home');
    expect(redirect(loggedIn: true, at: '/home'), isNull);
    expect(redirect(loggedIn: true, at: '/settings'), isNull);
  });

  group('the operator console is its own realm (EE-033)', () {
    String? adminRedirect({
      bool restoring = false,
      bool loggedIn = false,
      bool isAdmin = false,
      required String at,
    }) => computeAuthRedirect(
      isRestoring: restoring,
      isLoggedIn: loggedIn,
      location: at,
      isInstanceAdmin: isAdmin,
    );

    test('a workspace user cannot see /admin — this is the acceptance', () {
      // Signed in as a PERSON is not signed in as the OPERATOR. The console
      // holds the buttons that suspend customers, and a workspace session
      // grants none of them.
      for (final at in [
        '/admin',
        '/admin/teams',
        '/admin/teams/abc',
        '/admin/packages',
      ]) {
        expect(
          adminRedirect(loggedIn: true, at: at),
          '/admin/login',
          reason: at,
        );
      }
    });

    test('signed out is no different — the person is irrelevant here', () {
      expect(adminRedirect(at: '/admin'), '/admin/login');
      // ...and /admin/login itself is reachable while signed OUT, because a
      // self-hosted operator may hold no AllisWell account at all.
      expect(adminRedirect(at: '/admin/login'), isNull);
      expect(adminRedirect(loggedIn: true, at: '/admin/login'), isNull);
    });

    test('an operator passes, with or without a personal session', () {
      for (final loggedIn in [true, false]) {
        expect(
          adminRedirect(isAdmin: true, loggedIn: loggedIn, at: '/admin'),
          isNull,
        );
        expect(
          adminRedirect(isAdmin: true, loggedIn: loggedIn, at: '/admin/teams'),
          isNull,
        );
        // Already in: the sign-in page is not a place to stay.
        expect(
          adminRedirect(isAdmin: true, loggedIn: loggedIn, at: '/admin/login'),
          '/admin',
        );
      }
    });

    test('restoring the PERSON does not park the console on /splash', () {
      // The two sessions restore independently; parking the operator on the
      // app's splash would tie one realm's readiness to the other's.
      expect(
        adminRedirect(restoring: true, isAdmin: true, at: '/admin'),
        isNull,
      );
      expect(adminRedirect(restoring: true, at: '/admin'), '/admin/login');
      // ...while everything else still parks, unchanged.
      expect(adminRedirect(restoring: true, at: '/home'), '/splash');
    });

    test('the prefix does not leak onto lookalike routes', () {
      // `/administration` is not the console, and neither is `/admin-notes`.
      expect(isAdminLocation('/admin'), isTrue);
      expect(isAdminLocation('/admin/teams'), isTrue);
      expect(isAdminLocation('/administration'), isFalse);
      expect(isAdminLocation('/admin-notes'), isFalse);
      expect(adminRedirect(loggedIn: true, at: '/administration'), isNull);
    });
  });

  test('OPH-390 (R-07): a remembered page that belongs to somebody is only '
      'replayed for them', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final pending = container.read(pendingDeepLinkProvider.notifier);

    pending.remember('/settings', owner: 'user-1');
    expect(pending.take(forUser: 'user-2'), isNull);
    // Dropped, not kept for later.
    expect(container.read(pendingDeepLinkProvider), isNull);
    expect(pending.take(forUser: 'user-1'), isNull);

    pending.remember('/settings', owner: 'user-1');
    expect(pending.take(forUser: 'user-1'), '/settings');

    // A link that arrived signed out is anybody's.
    pending.remember('/tasks/t1');
    expect(pending.take(forUser: 'user-2'), '/tasks/t1');
    pending.rememberIfNone('/notes/n1');
    expect(pending.take(forUser: 'user-2'), '/notes/n1');
  });

  group('the router error exit (OPH-189)', () {
    test(
      '/ is a real route now, not the dead end the error page linked to',
      () {
        // go_router's DEFAULT error page sends the user to '/'. Until OPH-189
        // that was not a route either, so the recovery button produced a SECOND
        // error ("no routes for location: /") — the error screen's own way out
        // was broken. The redirect below is what the route resolves to.
        expect(redirect(loggedIn: true, at: '/'), isNull);
        expect(redirect(at: '/'), '/login');
      },
    );
  });
}
