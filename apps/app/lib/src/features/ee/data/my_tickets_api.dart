import 'package:dio/dio.dart';

import 'team_address_api.dart';

/// One of my own requests, as the server lists it (EE-087).
///
/// Thinner than the queue's row on purpose. The asker does not need — and is
/// not given — the workspace that answers them: which desk handles a request
/// is the team's internal shape. What they recognise is what they asked FOR,
/// so the service's NAME travels instead of its id (they cannot read the
/// catalogue endpoint; it is admin-gated).
class EeMyTicket {
  const EeMyTicket({
    required this.id,
    required this.subject,
    required this.status,
    required this.priority,
    required this.createdAt,
    this.serviceName,
    this.updatedAt,
    this.waitingReason,
  });

  factory EeMyTicket.fromJson(Map<String, dynamic> json) => EeMyTicket(
    id: json['id'] as String,
    subject: json['subject'] as String,
    status: json['status'] as String,
    priority: json['priority'] as String,
    serviceName: json['serviceName'] as String?,
    createdAt: DateTime.parse(json['createdAt'] as String),
    // EE-252: "what happened last" — the server always sent it; the list
    // dropped it, so a row could not say whether anything had moved.
    updatedAt: json['updatedAt'] is String
        ? DateTime.tryParse(json['updatedAt'] as String)
        : null,
    waitingReason: json['waitingReason'] as String?,
  );

  final String id;
  final String subject;
  final String status;
  final String priority;
  final String? serviceName;
  final DateTime createdAt;
  final DateTime? updatedAt;

  /// EE-253: which wait, when it is one — the server's word, one of five.
  final String? waitingReason;

  /// Only `requester_info` is the asker's move; the other four are not.
  bool get waitsOnRequester =>
      status == 'waiting' && waitingReason == 'requester_info';
}

/// "My requests" — an ONLINE list, and the only honest one (ADR-0011 §3).
///
/// The replica cannot answer this. A requester is by definition not a member of
/// the unit that answers them, and the sync engine runs one workspace at a
/// time, so a replica-backed list would silently omit every request filed with
/// a unit this device does not sync — which is most of them. The choice was
/// between an online list and a quietly incomplete one; the screen carries the
/// cost of the first by saying so when there is no connection.
class EeMyTicketsApi {
  const EeMyTicketsApi(this._dio);
  final Dio _dio;

  Future<List<EeMyTicket>?> list() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/api/v1/ee/team/tickets/mine',
      );
      return ((res.data?['tickets'] as List?) ?? const [])
          .map((t) => EeMyTicket.fromJson(t as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      // 404 — no team answers at this address. NOT null (OPH-356, UI-AUDIT
      // #7): the screen drew null as "you have not asked for anything yet" to
      // somebody with forty requests. Typed, so it can say what it means.
      throwTeamError(e);
    }
  }
}
