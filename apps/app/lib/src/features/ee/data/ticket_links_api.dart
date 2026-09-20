import 'package:dio/dio.dart';

import '../../../core/api_exception.dart';
import 'ticket_links_models.dart';

/// Links, linked work and the "came up again" flow (EE-189, EE-190).
///
/// Shaped after `EeApprovalsApi`: a 403 or 404 on the READ is an empty answer
/// rather than an error, because a request on a desk this person is not on is
/// something to draw as nothing. The WRITES travel intact — an agent pressing
/// "this has come up again" and getting silence would press it twice.
class EeTicketLinksApi {
  const EeTicketLinksApi(this._dio);
  final Dio _dio;

  static const _base = '/api/v1/ee/team/tickets';

  /// Two calls, one object. The links come from EE-189's endpoint and the
  /// linked WORK from the ticket itself, because `linkedTaskIds` has been on
  /// the ticket since EE-085 and moving it would break every other reader.
  Future<EeTicketRelations> read(String ticketId) async {
    try {
      final results = await Future.wait([
        _dio.get<Map<String, dynamic>>('$_base/$ticketId/links'),
        _dio.get<Map<String, dynamic>>('$_base/$ticketId'),
      ]);
      final links = results[0].data ?? const <String, dynamic>{};
      final ticket = results[1].data ?? const <String, dynamic>{};
      return EeTicketRelations(
        links: ((links['links'] as List<dynamic>?) ?? const [])
            .map((e) => EeTicketLink.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        problems: ((links['problems'] as List<dynamic>?) ?? const [])
            .map((e) => EeLinkedProblem.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        taskIds: ((ticket['linkedTaskIds'] as List<dynamic>?) ?? const [])
            .cast<String>()
            .toList(growable: false),
        waitingReason: ticket['waitingReason'] as String?,
      );
    } on DioException catch (error) {
      final code = error.response?.statusCode;
      if (code == 403 || code == 404) return const EeTicketRelations();
      throw asApiException(error);
    }
  }

  /// EE-190 — the same matter, a NEW request, and the old one untouched.
  ///
  /// Returns the new request's id so the caller can go straight to it. The
  /// server does the linking; passing it back as two calls would leave a
  /// window where a new request exists with nothing tying it to the old one.
  Future<String> openRelated(
    String ticketId, {
    String? subject,
    String? body,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '$_base/$ticketId/related',
        data: {
          if (subject != null && subject.trim().isNotEmpty)
            'subject': subject.trim(),
          if (body != null && body.trim().isNotEmpty) 'body': body.trim(),
        },
      );
      return (res.data ?? const <String, dynamic>{})['id'] as String;
    } on DioException catch (error) {
      throw asApiException(error);
    }
  }

  /// Opening one more piece of work from the same request (GAP §3.11).
  ///
  /// The data model always allowed several — `ee_ticket_task_links` has no
  /// unique on `ticket_id`, only on `task_id` — and what was missing was a
  /// way to ask for a second one.
  Future<void> convertToTask(String ticketId, {String? title}) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '$_base/$ticketId/convert',
        data: {
          if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
        },
      );
    } on DioException catch (error) {
      throw asApiException(error);
    }
  }
}
