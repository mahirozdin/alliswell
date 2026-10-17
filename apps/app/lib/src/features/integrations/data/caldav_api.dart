import 'package:dio/dio.dart';

import '../../../core/api_exception.dart';

/// iCloud / CalDAV calendar client (OPH-380) over
/// `apps/api/src/routes/integrations-caldav.js` (ADR-0059).
///
/// REST, not sync — like Google's (`google_api.dart`): a calendar connection
/// is per-user server state. The password goes UP once, on connect, and never
/// comes back: the server has no serializer path to it.

/// A connected CalDAV account.
class CaldavAccount {
  const CaldavAccount({
    required this.id,
    required this.server,
    required this.serverHost,
    required this.username,
    required this.status,
    this.serverUrl,
    this.calendarUrl,
    this.calendarName,
    this.lastSyncedAt,
    this.lastError,
  });

  factory CaldavAccount.fromJson(Map<String, dynamic> json) => CaldavAccount(
    id: json['id'] as String,
    server: (json['server'] as String?) ?? 'generic',
    serverHost: (json['serverHost'] as String?) ?? '',
    username: (json['username'] as String?) ?? '',
    status: json['status'] as String,
    serverUrl: json['serverUrl'] as String?,
    calendarUrl: json['calendarUrl'] as String?,
    calendarName: json['calendarName'] as String?,
    lastSyncedAt: json['lastSyncedAt'] == null
        ? null
        : DateTime.tryParse(json['lastSyncedAt'] as String),
    lastError: json['lastError'] as String?,
  );

  final String id;

  /// `icloud` | `generic`.
  final String server;
  final String serverHost;

  /// What the user typed for a generic server (null for iCloud) — prefills a
  /// reconnect.
  final String? serverUrl;
  final String username;

  /// `active` | `error` | `revoked` | `disconnected`.
  final String status;
  final String? calendarUrl;
  final String? calendarName;
  final DateTime? lastSyncedAt;
  final String? lastError;

  bool get isIcloud => server == 'icloud';

  /// Connected, but nothing mirrors until a calendar is picked.
  bool get needsCalendar => status == 'active' && calendarUrl == null;

  /// The server rejected the stored password — only reconnecting fixes it.
  bool get needsReconnect => status == 'error' || status == 'revoked';
}

class CaldavCalendar {
  const CaldavCalendar({required this.url, required this.name, this.color});

  factory CaldavCalendar.fromJson(Map<String, dynamic> json) => CaldavCalendar(
    url: json['url'] as String,
    name: (json['name'] as String?) ?? json['url'] as String,
    color: json['color'] as String?,
  );

  /// The collection's path on the server — what the account mirrors into.
  final String url;
  final String name;

  /// `#RRGGBB` as the server reports it; informational only.
  final String? color;
}

/// Whether the SERVER offers the connector (`CALDAV_ENABLED`), plus this
/// user's account in the current workspace.
class CaldavStatus {
  const CaldavStatus({required this.enabled, required this.accounts});

  final bool enabled;
  final List<CaldavAccount> accounts;

  CaldavAccount? get account => accounts.isEmpty ? null : accounts.first;
}

class CaldavConnectResult {
  const CaldavConnectResult({required this.account, required this.calendars});

  final CaldavAccount account;
  final List<CaldavCalendar> calendars;
}

class CaldavIntegrationsApi {
  CaldavIntegrationsApi(this._dio);

  final Dio _dio;

  Future<CaldavStatus> status(String workspaceId) => _run(() async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/api/v1/workspaces/$workspaceId/integrations/caldav',
    );
    final items = (res.data?['items'] as List?) ?? const [];
    return CaldavStatus(
      enabled: (res.data?['enabled'] as bool?) ?? false,
      accounts: items
          .map((a) => CaldavAccount.fromJson(a as Map<String, dynamic>))
          .toList(),
    );
  });

  /// Verified on the server BEFORE anything is stored: a wrong password
  /// answers `CALDAV_AUTH_FAILED` and leaves nothing behind.
  Future<CaldavConnectResult> connect(
    String workspaceId, {
    required String server,
    String? url,
    required String username,
    required String password,
  }) => _run(() async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/api/v1/workspaces/$workspaceId/integrations/caldav',
      data: {
        'server': server,
        if (url != null && url.isNotEmpty) 'url': url,
        'username': username,
        'password': password,
      },
    );
    final data = res.data!;
    return CaldavConnectResult(
      account: CaldavAccount.fromJson(data['account'] as Map<String, dynamic>),
      calendars: ((data['calendars'] as List?) ?? const [])
          .map((c) => CaldavCalendar.fromJson(c as Map<String, dynamic>))
          .toList(),
    );
  });

  Future<List<CaldavCalendar>> calendars(String accountId) => _run(() async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/api/v1/integrations/caldav/accounts/$accountId/calendars',
    );
    return ((res.data?['items'] as List?) ?? const [])
        .map((c) => CaldavCalendar.fromJson(c as Map<String, dynamic>))
        .toList();
  });

  /// Picking the calendar backfills: the server sweeps every task into it.
  Future<CaldavAccount> chooseCalendar(String accountId, String calendarUrl) =>
      _run(() async {
        final res = await _dio.patch<Map<String, dynamic>>(
          '/api/v1/integrations/caldav/accounts/$accountId',
          data: {'calendarUrl': calendarUrl},
        );
        return CaldavAccount.fromJson(res.data!);
      });

  Future<void> disconnect(String accountId) => _run(() async {
    await _dio.delete<void>('/api/v1/integrations/caldav/accounts/$accountId');
  });

  Future<T> _run<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }
}
