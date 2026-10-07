import '../i18n/i18n.dart';
import 'api_exception.dart';

/// A localized, user-facing message for any error surfaced in the UI (OPH-125).
///
/// The API returns a language-neutral `code`; we map it to an `error.<CODE>` key
/// and, if that isn't translated, fall back to the server's own message, then a
/// generic string. Use this instead of `'$error'` in `AwErrorState`/snackbars so
/// a `NETWORK_ERROR` reads "Could not reach the server…" in the active language
/// rather than `ApiException(NETWORK_ERROR): …`.
String localizedError(Object? error) {
  if (error is ApiException) {
    return localizedErrorCode(
      error.code,
      error.message,
      statusCode: error.statusCode,
      retryAfter: error.retryAfter,
    );
  }
  return 'error.unknown'.tr();
}

/// The same mapping for any coded failure (auth uses its own exception type).
///
/// OPH-357 (UI-AUDIT #24): a response with no `code` — a 404 from a proxy, a
/// codeless 429 from an older server, a 5xx — is mapped by its STATUS, never
/// shown as the client's English placeholder; a 429 says how long to wait
/// when the server said so.
String localizedErrorCode(
  String code,
  String message, {
  int? statusCode,
  int? retryAfter,
}) {
  final status =
      statusCode ??
      (code.startsWith('HTTP_') ? int.tryParse(code.substring(5)) : null);

  if (code == 'RATE_LIMITED' || status == 429) {
    if (retryAfter != null && retryAfter > 0) {
      return 'error.RATE_LIMITED'.tr(args: {'seconds': '$retryAfter'});
    }
    return 'error.HTTP_429'.tr();
  }

  final byCode = AwI18n.instance.maybeTranslate('error.$code');
  if (byCode != null) return byCode;

  if (code.startsWith('HTTP_')) {
    // Codeless: the text is the client's own placeholder, never the user's.
    if (status == 404) return 'error.notFound'.tr();
    if (status != null && status >= 500) return 'error.server'.tr();
    return 'error.unknown'.tr();
  }
  return message.isNotEmpty ? message : 'error.unknown'.tr();
}
