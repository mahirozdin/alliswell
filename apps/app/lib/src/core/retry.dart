import 'api_exception.dart';

/// How the app retries failed providers.
///
/// Riverpod 3 retries EVERY failed provider by default — 10 times, backing off
/// 200 ms → 6.4 s (`ProviderContainer.defaultRetry`, which only declines for
/// `Error`/`ProviderException`). Our [ApiException] is a plain `Exception`, so
/// it qualifies, and that default is wrong for us twice over:
///
///  1. The server has already answered. A `502 CALENDAR_ACCOUNT_REAUTH_REQUIRED`
///     or a `404` cannot be talked out of it by asking ten more times.
///  2. While it retries, the provider keeps flipping back to `loading`, so the
///     screen sits on a spinner and the error state we designed is effectively
///     unreachable — for ~38 s.
///
/// Found live in OPH-080's calendar picker: a dead Google credential was asked
/// eleven times and the user never saw the "sign in again" message. Widget
/// tests missed it because they build their own `ProviderScope`, which is
/// exactly why this policy is applied to the test scopes too.
///
/// So: retry only what a retry could actually fix — failing to reach the
/// server at all. Everything else surfaces immediately.
Duration? awRetry(int retryCount, Object error) {
  if (error is! ApiException || error.code != 'NETWORK_ERROR') return null;
  if (retryCount >= 3) return null;
  return Duration(milliseconds: 250 * (1 << retryCount)); // 250ms, 500ms, 1s
}
