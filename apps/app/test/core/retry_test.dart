import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/core/api_exception.dart';
import 'package:alliswell/src/core/retry.dart';

/// Riverpod 3 retries every failed provider by default (10×, 200ms → 6.4s),
/// which put OPH-080's calendar picker behind a permanent spinner while it
/// asked a dead Google credential eleven times. This is the policy that
/// replaced it.
void main() {
  test('an error the server already decided is never retried', () {
    // The server has spoken — asking again cannot change its mind, and while
    // we ask, the screen shows a spinner instead of the error.
    for (final code in [
      'CALENDAR_ACCOUNT_REAUTH_REQUIRED',
      'GOOGLE_NOT_CONFIGURED',
      'AUTH_WORKSPACE_FORBIDDEN',
      'HTTP_500',
    ]) {
      expect(
        awRetry(0, ApiException(code, 'nope')),
        isNull,
        reason: '$code must surface immediately',
      );
    }
  });

  test('not reaching the server at all is worth retrying — briefly', () {
    const offline = ApiException('NETWORK_ERROR', 'Could not reach the server');
    expect(awRetry(0, offline), const Duration(milliseconds: 250));
    expect(awRetry(1, offline), const Duration(milliseconds: 500));
    expect(awRetry(2, offline), const Duration(seconds: 1));
    // …and then it gives up, rather than spinning for the ~38 s Riverpod's
    // default would take to exhaust itself.
    expect(awRetry(3, offline), isNull);
  });

  test('anything that is not our own exception surfaces too', () {
    expect(awRetry(0, Exception('boom')), isNull);
    expect(awRetry(0, StateError('boom')), isNull);
  });
}
