import '../../../i18n/i18n.dart';
import '../data/models.dart';

/// Localized human-readable text for the API's stable error codes (AGENTS.md §4,
/// OPH-125). The server returns a language-neutral `code`; the app maps it to an
/// `error.<CODE>` key, falling back to the server message then a generic string.
String friendlyAuthMessage(Object error) {
  if (error is AuthException) {
    switch (error.code) {
      case 'AUTH_INVALID_CREDENTIALS':
        return 'error.AUTH_INVALID_CREDENTIALS'.tr();
      case 'AUTH_EMAIL_TAKEN':
        return 'error.AUTH_EMAIL_TAKEN'.tr();
      case 'AUTH_INVALID_REFRESH_TOKEN':
      case 'AUTH_REFRESH_REUSED':
        return 'error.sessionExpired'.tr();
      case 'NETWORK_ERROR':
        return 'error.NETWORK_ERROR'.tr();
    }
    return error.message;
  }
  return 'error.unknown'.tr();
}
