import 'package:dio/dio.dart';

import '../../../core/api_exception.dart';

/// One request, as the person who ASKED reads it (EE-252, ADR-0017 D17.6).
///
/// Read from the server and never from the replica: the requester is not a
/// member of the unit that answers them, so the device never syncs this row
/// (ADR-0011 §3). `viewer` is the server's word on whose eyes the answer is
/// for — a person who both asked and staffs the unit is the desk, and their
/// screen is the desk's.
class EeRequesterTicket {
  const EeRequesterTicket({
    required this.id,
    required this.subject,
    required this.status,
    required this.viewer,
    this.number,
    this.body,
    this.waitingReason,
    this.serviceName,
    this.createdAt,
    this.updatedAt,
    this.allowedTransitions = const [],
  });

  factory EeRequesterTicket.fromJson(Map<String, dynamic> json) =>
      EeRequesterTicket(
        id: json['id'] as String,
        subject: json['subject'] as String,
        status: json['status'] as String,
        viewer: (json['viewer'] as String?) ?? 'desk',
        number: (json['number'] as num?)?.toInt(),
        body: json['body'] as String?,
        waitingReason: json['waitingReason'] as String?,
        serviceName: json['serviceName'] as String?,
        createdAt: _date(json['createdAt']),
        updatedAt: _date(json['updatedAt']),
        allowedTransitions: ((json['allowedTransitions'] as List?) ?? const [])
            .cast<String>(),
      );

  final String id;
  final String subject;
  final String status;

  /// `requester` or `desk` — whose view the server answered with.
  final String viewer;
  final int? number;
  final String? body;
  final String? waitingReason;
  final String? serviceName;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// The requester's own moves, from the server (`requester-rules.js`): from
  /// `resolved`, `closed` and `in_progress`; otherwise none.
  final List<String> allowedTransitions;

  bool get isRequesterView => viewer == 'requester';

  /// A finished request takes no reply: the server refuses one
  /// (`TICKET_TERMINAL`), so the screen offers a new request instead.
  bool get isClosed => status == 'closed' || status == 'cancelled';

  /// "Waiting for you" is ONE of the five reasons, not waiting as such.
  bool get waitsOnRequester =>
      status == 'waiting' && waitingReason == 'requester_info';
}

/// One visible line of the conversation. The server has already dropped the
/// desk's internal notes for this reader (EE-087) — the screen never sees
/// them, so it cannot show one by mistake.
class EeRequesterComment {
  const EeRequesterComment({
    required this.id,
    required this.body,
    this.authorId,
    this.createdAt,
  });

  factory EeRequesterComment.fromJson(Map<String, dynamic> json) =>
      EeRequesterComment(
        id: json['id'] as String,
        body: json['body'] as String,
        authorId: json['authorId'] as String?,
        createdAt: _date(json['createdAt']),
      );

  final String id;
  final String body;
  final String? authorId;
  final DateTime? createdAt;
}

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

/// The requester's read side. Writing reuses the desk's client
/// (`EeTicketWriteApi.comment` / `setStatus`): the doors are the same, and
/// the server decides what this caller may do through them.
class EeRequesterTicketApi {
  const EeRequesterTicketApi(this._dio);
  final Dio _dio;

  static const _tickets = '/api/v1/ee/team/tickets';

  /// Null when the request is not this person's to read — the server
  /// answers 404 for "not yours" and "does not exist" alike.
  Future<EeRequesterTicket?> detail(String ticketId) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('$_tickets/$ticketId');
      final data = res.data;
      return data == null ? null : EeRequesterTicket.fromJson(data);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw asApiException(e);
    }
  }

  Future<List<EeRequesterComment>> comments(String ticketId) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '$_tickets/$ticketId/comments',
      );
      return ((res.data?['comments'] as List?) ?? const [])
          .map((c) => EeRequesterComment.fromJson(c as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }
}
