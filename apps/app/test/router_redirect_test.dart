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
}
