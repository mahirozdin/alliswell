import 'package:dio/dio.dart';

import '../../../core/api_exception.dart';

/// EE-267 (AW-E19) — open requests across every unit this person works in.
///
/// Read from the SERVER and nowhere else: the device holds one unit's queue
/// at a time (the sync engine follows the selected workspace), so a list
/// spanning units drawn from the replica would be as stale as the last visit
/// to each unit. The screens that show this say it is live and needs a
/// connection, and show nothing rather than an old copy when it cannot be
/// asked.
class EeUnitTicket {
  const EeUnitTicket({
    required this.id,
    required this.subject,
    required this.status,
    required this.priority,
    required this.unitId,
    required this.unitName,
    required this.workspaceId,
    this.number,
    this.slaStatus,
    this.slaDueAt,
    this.updatedAt,
  });

  factory EeUnitTicket.fromJson(Map<String, dynamic> json) => EeUnitTicket(
    id: json['id'] as String,
    number: (json['number'] as num?)?.toInt(),
    subject: json['subject'] as String,
    status: json['status'] as String,
    priority: (json['priority'] as String?) ?? 'normal',
    slaStatus: json['slaStatus'] as String?,
    slaDueAt: _date(json['slaDueAt']),
    unitId: json['unitId'] as String,
    unitName: json['unitName'] as String,
    workspaceId: json['workspaceId'] as String,
    updatedAt: _date(json['updatedAt']),
  );

  final String id;
  final int? number;
  final String subject;
  final String status;
  final String priority;
  final String? slaStatus;
  final DateTime? slaDueAt;
  final String unitId;
  final String unitName;

  /// The desk to open to reach it — the device syncs one at a time.
  final String workspaceId;
  final DateTime? updatedAt;
}

/// A unit in the list's scope: the ones this person works in.
class EeUnitScope {
  const EeUnitScope({
    required this.unitId,
    required this.unitName,
    required this.workspaceId,
  });

  factory EeUnitScope.fromJson(Map<String, dynamic> json) => EeUnitScope(
    unitId: json['unitId'] as String,
    unitName: json['unitName'] as String,
    workspaceId: json['workspaceId'] as String,
  );

  final String unitId;
  final String unitName;
  final String workspaceId;
}

/// One page. [breached] and [warned] count the whole scope, not the page.
class EeUnitTicketsPage {
  const EeUnitTicketsPage({
    this.units = const [],
    this.tickets = const [],
    this.breached = 0,
    this.warned = 0,
    this.nextCursor,
  });

  factory EeUnitTicketsPage.fromJson(Map<String, dynamic> json) {
    final alerts = (json['alerts'] as Map?)?.cast<String, dynamic>() ?? {};
    return EeUnitTicketsPage(
      units: [
        for (final u in (json['units'] as List? ?? const []))
          EeUnitScope.fromJson((u as Map).cast<String, dynamic>()),
      ],
      tickets: [
        for (final t in (json['tickets'] as List? ?? const []))
          EeUnitTicket.fromJson((t as Map).cast<String, dynamic>()),
      ],
      breached: (alerts['breached'] as num?)?.toInt() ?? 0,
      warned: (alerts['warned'] as num?)?.toInt() ?? 0,
      nextCursor: json['nextCursor'] as String?,
    );
  }

  final List<EeUnitScope> units;
  final List<EeUnitTicket> tickets;
  final int breached;
  final int warned;
  final String? nextCursor;

  bool get hasMore => nextCursor != null;
}

class EeUnitTicketsApi {
  EeUnitTicketsApi(this._dio);

  final Dio _dio;

  /// [alertsOnly] keeps breached and warned requests; [except] leaves out a
  /// desk the screen is already showing.
  Future<EeUnitTicketsPage> list({
    bool alertsOnly = false,
    String? except,
    String? cursor,
    int? limit,
  }) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/api/v1/ee/team/tickets/my-units',
        queryParameters: {
          if (alertsOnly) 'alerts': true,
          'except': ?except,
          'cursor': ?cursor,
          'limit': ?limit,
        },
      );
      return EeUnitTicketsPage.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }
}

DateTime? _date(Object? raw) =>
    raw is String ? DateTime.tryParse(raw)?.toUtc() : null;
