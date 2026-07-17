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
    final byCode = AwI18n.instance.maybeTranslate('error.${error.code}');
    if (byCode != null) return byCode;
    return error.message.isNotEmpty ? error.message : 'error.unknown'.tr();
  }
  return 'error.unknown'.tr();
}
