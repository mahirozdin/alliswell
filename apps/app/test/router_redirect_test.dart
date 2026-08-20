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

  test('signed out: only /login and /register are reachable', () {
    expect(redirect(at: '/home'), '/login');
    expect(redirect(at: '/settings'), '/login');
    expect(redirect(at: '/splash'), '/login');
    expect(redirect(at: '/login'), isNull);
    expect(redirect(at: '/register'), isNull);
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
