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
    this.serviceId,
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
        serviceId: json['serviceId'] as String?,
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

  /// What a follow-up request is filed against again, when the person's
  /// catalogue still offers it.
  final String? serviceId;
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
    this.senderUnverified = false,
  });

  factory EeRequesterComment.fromJson(Map<String, dynamic> json) =>
      EeRequesterComment(
        id: json['id'] as String,
        body: json['body'] as String,
        authorId: json['authorId'] as String?,
        createdAt: _date(json['createdAt']),
        senderUnverified: json['senderUnverified'] == true,
      );

  final String id;
  final String body;
  final String? authorId;
  final DateTime? createdAt;

  /// EE-254: arrived as mail claiming a colleague's address it could not
  /// prove — never "the desk", whatever it says.
  final bool senderUnverified;
}

/// One file on the request, as its requester may see it (EE-252): on the
/// request itself or on a visible reply — the server never selects one that
/// rides an internal note. Read-only: the requester adds by writing.
class EeTicketFile {
  const EeTicketFile({
    required this.id,
    required this.name,
    required this.sizeBytes,
    this.mime,
    this.commentId,
  });

  factory EeTicketFile.fromJson(Map<String, dynamic> json) => EeTicketFile(
    id: json['id'] as String,
    name: json['name'] as String,
    sizeBytes: (json['sizeBytes'] as num).toInt(),
    mime: json['mime'] as String?,
    commentId: json['commentId'] as String?,
  );

  final String id;
  final String name;
  final int sizeBytes;
  final String? mime;

  /// The reply it came with; null for the request itself.
  final String? commentId;
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

  /// The files this reader may see (EE-252). Core's file doors ask for the
  /// unit's membership, which the requester does not hold; these ask what the
  /// server's conversation asks, plus core's own `files.view`.
  Future<List<EeTicketFile>> files(String ticketId) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '$_tickets/$ticketId/files',
      );
      return ((res.data?['files'] as List?) ?? const [])
          .map((f) => EeTicketFile.fromJson(f as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }

  /// A short-lived download address, minted per tap and never kept. Null
  /// when the server has no object storage to sign for.
  Future<String?> fileUrl(String ticketId, String fileId) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '$_tickets/$ticketId/files/$fileId',
      );
      return res.data?['downloadUrl'] as String?;
    } on DioException catch (e) {
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
