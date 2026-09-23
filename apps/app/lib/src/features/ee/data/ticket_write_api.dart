import 'package:dio/dio.dart';

import '../../../core/api_exception.dart';

/// One of the desk's saved replies (EE-201), as the composer offers it (EE-223).
class EeCannedReply {
  const EeCannedReply({
    required this.id,
    required this.name,
    required this.text,
  });

  factory EeCannedReply.fromJson(Map<String, dynamic> json) => EeCannedReply(
    id: json['id'] as String,
    name: json['name'] as String,
    // The server's rendering against THIS request when it made one — the
    // `{{...}}` vocabulary is the server's (EE-201: "a vocabulary implemented
    // three times is three vocabularies") — and the raw text otherwise.
    text: (json['rendered'] as String?) ?? json['body'] as String,
  );

  final String id;
  final String name;

  /// What goes into the text box.
  final String text;
}

/// Writing on a request from the app (EE-223).
///
/// ONLINE, by decision (E19): a request is server-canonical, and a reply that
/// waited in a queue would reach the requester whenever the phone next found a
/// signal, in an order nobody chose. So a failure travels back intact — the
/// composer keeps the text and says why — and nothing is retried behind the
/// person's back.
class EeTicketWriteApi {
  const EeTicketWriteApi(this._dio);
  final Dio _dio;

  static const _tickets = '/api/v1/ee/team/tickets';

  /// A reply (the requester reads it) or an internal note (only the unit
  /// does). The rest is the server's: who may mark a note internal, what is
  /// mailed, what reaches a linked child request (EE-182, EE-189).
  Future<void> comment(
    String ticketId, {
    required String body,
    required bool internal,
  }) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '$_tickets/$ticketId/comments',
        data: {'body': body, 'internal': internal},
      );
    } on DioException catch (error) {
      throw asApiException(error);
    }
  }

  /// The desk's saved replies, rendered against [ticketId]. Archived ones are
  /// not offered: the desk retired that wording. A 403/404 is "none" — the
  /// composer then has no list to open, rather than an error to explain.
  Future<List<EeCannedReply>> cannedReplies(String ticketId) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/v1/ee/team/canned-replies',
        queryParameters: {'ticketId': ticketId},
      );
      final rows = (response.data?['replies'] as List<dynamic>?) ?? const [];
      return [
        for (final row in rows.cast<Map<String, dynamic>>())
          if (row['archived'] != true) EeCannedReply.fromJson(row),
      ];
    } on DioException catch (error) {
      final code = error.response?.statusCode;
      if (code == 403 || code == 404) return const [];
      throw asApiException(error);
    }
  }
}
