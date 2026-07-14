import '../data/models.dart';

/// Human-readable text for the API's stable error codes (AGENTS.md §4).
String friendlyAuthMessage(Object error) {
  if (error is AuthException) {
    switch (error.code) {
      case 'AUTH_INVALID_CREDENTIALS':
        return 'Email or password is incorrect.';
      case 'AUTH_EMAIL_TAKEN':
        return 'An account with this email already exists.';
      case 'AUTH_INVALID_REFRESH_TOKEN':
      case 'AUTH_REFRESH_REUSED':
        return 'Your session has expired. Please sign in again.';
      case 'NETWORK_ERROR':
        return 'Could not reach the server. Check your connection '
            'and the server address.';
    }
    return error.message;
  }
  return 'Something went wrong. Please try again.';
}
