import 'package:dio/dio.dart';

import '../../../core/api_exception.dart';

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
  });

  factory EeMyTicket.fromJson(Map<String, dynamic> json) => EeMyTicket(
    id: json['id'] as String,
    subject: json['subject'] as String,
    status: json['status'] as String,
    priority: json['priority'] as String,
    serviceName: json['serviceName'] as String?,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );

  final String id;
  final String subject;
  final String status;
  final String priority;
  final String? serviceName;
  final DateTime createdAt;
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
      // 404 — no team at this address at all. Null, not an error: there is no
      // requester surface to draw, which is a state and not a failure.
      if (e.response?.statusCode == 404) return null;
      throw asApiException(e);
    }
  }
}
