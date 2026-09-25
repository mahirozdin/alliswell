import 'package:dio/dio.dart';

import '../../../core/api_exception.dart';
import 'ticket_write_api.dart' show EeTicketAnswer;

/// EE-266 (AW-E17) — the request archive, as the desk reads it.
///
/// A finished request leaves every device after the retention window (EE-091:
/// that is the whole point of the sweep), so the archive is read from the
/// server and nowhere else — and it says so on screen rather than looking
/// like the queue. Read-only by construction: nothing here writes.
class EeArchivedTicketSummary {
  const EeArchivedTicketSummary({
    required this.id,
    required this.subject,
    required this.status,
    required this.priority,
    this.number,
    this.requesterDisplayName,
    this.terminalAt,
    this.archivedAt,
  });

  factory EeArchivedTicketSummary.fromJson(Map<String, dynamic> json) =>
      EeArchivedTicketSummary(
        id: json['id'] as String,
        subject: json['subject'] as String,
        status: json['status'] as String,
        priority: (json['priority'] as String?) ?? 'normal',
        number: (json['number'] as num?)?.toInt(),
        requesterDisplayName: json['requesterDisplayName'] as String?,
        terminalAt: _date(json['terminalAt']),
        archivedAt: _date(json['archivedAt']),
      );

  final String id;
  final String subject;
  final String status;
  final String priority;
  final int? number;
  final String? requesterDisplayName;
  final DateTime? terminalAt;
  final DateTime? archivedAt;
}

/// One page of an archive search. [hasMore] means the server holds older
/// matches than this page — the screen asks for a narrower search rather than
/// pretending the page is the whole answer.
class EeArchivePage {
  const EeArchivePage({this.tickets = const [], this.hasMore = false});

  final List<EeArchivedTicketSummary> tickets;
  final bool hasMore;
}

/// One line of an archived conversation — the desk's view, internal notes
/// included (ADR-0011 §3: the archive is a desk surface).
class EeArchivedComment {
  const EeArchivedComment({
    required this.id,
    required this.body,
    required this.internal,
    this.authorName,
    this.createdAt,
  });

  factory EeArchivedComment.fromJson(Map<String, dynamic> json) =>
      EeArchivedComment(
        id: json['id'] as String,
        body: (json['body'] as String?) ?? '',
        internal: json['internal'] == true,
        authorName: json['authorName'] as String?,
        createdAt: _date(json['createdAt']),
      );

  final String id;
  final String body;
  final bool internal;
  final String? authorName;
  final DateTime? createdAt;
}

/// Who decided an approval the request waited on (EE-265 kept it).
class EeArchivedApproval {
  const EeArchivedApproval({
    required this.status,
    this.decidedByName,
    this.decidedAt,
    this.requestReason,
  });

  factory EeArchivedApproval.fromJson(Map<String, dynamic> json) =>
      EeArchivedApproval(
        status: json['status'] as String,
        decidedByName: json['decidedByName'] as String?,
        decidedAt: _date(json['decidedAt']),
        requestReason: json['requestReason'] as String?,
      );

  final String status;
  final String? decidedByName;
  final DateTime? decidedAt;
  final String? requestReason;
}

/// An archived request, whole: what the sweep copied and what the request
/// left behind in its own tables (EE-265).
class EeArchivedTicket {
  const EeArchivedTicket({
    required this.summary,
    this.body,
    this.serviceName,
    this.comments = const [],
    this.answers = const [],
    this.slaStatus,
    this.approvals = const [],
    this.ratingScore,
    this.labourMinutes = 0,
  });

  factory EeArchivedTicket.fromJson(Map<String, dynamic> json) {
    final rating = json['rating'] as Map<String, dynamic>?;
    final labour = json['labour'] as Map<String, dynamic>?;
    final service = json['service'] as Map<String, dynamic>?;
    return EeArchivedTicket(
      summary: EeArchivedTicketSummary.fromJson(json),
      body: json['body'] as String?,
      serviceName: service?['name'] as String?,
      comments: [
        for (final c in (json['comments'] as List?) ?? const [])
          EeArchivedComment.fromJson(c as Map<String, dynamic>),
      ],
      answers: [
        for (final f in (json['fields'] as List?) ?? const [])
          EeTicketAnswer.fromJson(f as Map<String, dynamic>),
      ],
      slaStatus: json['slaStatus'] as String?,
      approvals: [
        for (final a in (json['approvals'] as List?) ?? const [])
          EeArchivedApproval.fromJson(a as Map<String, dynamic>),
      ],
      ratingScore: (rating?['score'] as num?)?.toInt(),
      labourMinutes: (labour?['minutes'] as num?)?.toInt() ?? 0,
    );
  }

  final EeArchivedTicketSummary summary;
  final String? body;
  final String? serviceName;
  final List<EeArchivedComment> comments;
  final List<EeTicketAnswer> answers;

  /// The promise's outcome on the day it closed — `met`, `breached`, … — or
  /// null when nothing was promised (or it was archived before EE-265 kept it).
  final String? slaStatus;
  final List<EeArchivedApproval> approvals;

  /// 1–5, or null when the requester was never asked or never answered.
  final int? ratingScore;
  final int labourMinutes;
}

class EeTicketArchiveApi {
  const EeTicketArchiveApi(this._dio);
  final Dio _dio;

  static const _base = '/api/v1/ee/team/tickets/archive';

  /// A number (`#1042`, `1042`) or every word somewhere in the subject, with
  /// the house fold — "isikli" finds "Işıklı" (ADR-0013).
  Future<EeArchivePage> search(String query, {int limit = 50}) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        _base,
        queryParameters: {'q': query.trim(), 'limit': limit},
      );
      final data = res.data ?? const <String, dynamic>{};
      return EeArchivePage(
        tickets: [
          for (final t in (data['tickets'] as List?) ?? const [])
            EeArchivedTicketSummary.fromJson(t as Map<String, dynamic>),
        ],
        hasMore: data['nextCursor'] != null,
      );
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }

  /// One archived request, or null when there is none THIS caller may read —
  /// the server answers "not yours" and "never was" with the same 404, on
  /// purpose (AGENTS §1.7), and so does this.
  Future<EeArchivedTicket?> detail(String ticketId) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('$_base/$ticketId');
      final data = res.data;
      return data == null ? null : EeArchivedTicket.fromJson(data);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw asApiException(e);
    }
  }
}

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toLocal() : null;
