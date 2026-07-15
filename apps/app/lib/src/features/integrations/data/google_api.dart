import 'package:dio/dio.dart';

import '../../../core/api_exception.dart';

/// Google Calendar integration client (OPH-080) over the Epic 08 endpoints
/// (`apps/api/src/routes/integrations-google.js`).
///
/// Deliberately REST, not the sync protocol: calendar accounts are per-user
/// server state, not a synced entity — there is nothing to replicate offline,
/// and a stale cached "connected" would be a lie. This is the one other place
/// besides `/me` where a screen may talk to the API directly (AGENTS.md §4).

/// A connected Google account. Token material has no serializer path on the
/// server, so nothing secret can arrive here.
class GoogleAccount {
  const GoogleAccount({
    required this.id,
    required this.providerAccountId,
    required this.status,
    this.defaultCalendarId,
    this.lastSyncedAt,
    this.lastError,
  });

  factory GoogleAccount.fromJson(Map<String, dynamic> json) => GoogleAccount(
    id: json['id'] as String,
    providerAccountId: json['providerAccountId'] as String,
    status: json['status'] as String,
    defaultCalendarId: json['defaultCalendarId'] as String?,
    lastSyncedAt: json['lastSyncedAt'] == null
        ? null
        : DateTime.tryParse(json['lastSyncedAt'] as String),
    lastError: json['lastError'] as String?,
  );

  final String id;

  /// The Google identity — an email address in practice.
  final String providerAccountId;

  /// `active` | `error` | `revoked` | `disconnected`.
  final String status;
  final String? defaultCalendarId;
  final DateTime? lastSyncedAt;
  final String? lastError;

  /// Connected but not finished: nothing mirrors until a calendar is picked
  /// (OPH-071).
  bool get needsCalendar => status == 'active' && defaultCalendarId == null;

  /// Google rejected our credentials — only reconnecting fixes it.
  bool get needsReconnect => status == 'error' || status == 'revoked';
}

class GoogleCalendar {
  const GoogleCalendar({
    required this.id,
    required this.summary,
    required this.primary,
  });

  factory GoogleCalendar.fromJson(Map<String, dynamic> json) => GoogleCalendar(
    id: json['id'] as String,
    summary: (json['summary'] as String?) ?? json['id'] as String,
    primary: (json['primary'] as bool?) ?? false,
  );

  final String id;
  final String summary;
  final bool primary;
}

/// Whether the SERVER has Google credentials at all, plus the accounts we know
/// about. The integration is optional by design — a self-hoster without an
/// OAuth client is not broken, so the UI hides rather than errors.
class GoogleIntegrationStatus {
  const GoogleIntegrationStatus({
    required this.configured,
    required this.accounts,
  });

  final bool configured;
  final List<GoogleAccount> accounts;

  GoogleAccount? get account => accounts.isEmpty ? null : accounts.first;
}

class GoogleIntegrationsApi {
  GoogleIntegrationsApi(this._dio);

  final Dio _dio;

  Future<GoogleIntegrationStatus> status(String workspaceId) => _run(() async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/api/v1/workspaces/$workspaceId/integrations/google',
    );
    final items = (res.data?['items'] as List?) ?? const [];
    return GoogleIntegrationStatus(
      configured: (res.data?['configured'] as bool?) ?? false,
      accounts: items
          .map((a) => GoogleAccount.fromJson(a as Map<String, dynamic>))
          .toList(),
    );
  });

  /// Returns the consent URL to open in a browser. The callback lands on the
  /// server unauthenticated — identity rides in a 10-minute signed state
  /// (ADR-0006), which is why the app never handles a code itself.
  Future<String> connectUrl(String workspaceId) => _run(() async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/api/v1/workspaces/$workspaceId/integrations/google/connect',
    );
    return res.data!['authUrl'] as String;
  });

  Future<List<GoogleCalendar>> calendars(String accountId) => _run(() async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/api/v1/integrations/google/accounts/$accountId/calendars',
    );
    return ((res.data?['items'] as List?) ?? const [])
        .map((c) => GoogleCalendar.fromJson(c as Map<String, dynamic>))
        .toList();
  });

  /// Picking the calendar also backfills: the server sweeps every
  /// mirror-enabled task into it (OPH-071).
  Future<GoogleAccount> chooseCalendar(String accountId, String calendarId) =>
      _run(() async {
        final res = await _dio.patch<Map<String, dynamic>>(
          '/api/v1/integrations/google/accounts/$accountId',
          data: {'defaultCalendarId': calendarId},
        );
        return GoogleAccount.fromJson(res.data!);
      });

  Future<void> disconnect(String accountId) => _run(() async {
    await _dio.delete<void>('/api/v1/integrations/google/accounts/$accountId');
  });

  Future<T> _run<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }
}
