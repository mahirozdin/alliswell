import 'package:dio/dio.dart';

import '../../../core/api_exception.dart';
import 'worklog_models.dart';

/// The worklog client (EE-208).
///
/// Online-only, for the reason every EE panel is: these rows are the desk's
/// internal accounting and no device needs them offline (ADR-0016 — only what
/// is structurally necessary goes into core's replica). A phone holding its
/// own copy of hours would also be a phone holding a stale one, and the number
/// it would be stale about is what somebody may be billed.
class EeWorklogApi {
  const EeWorklogApi(this._dio);
  final Dio _dio;

  String _path(String ticketId) => '/api/v1/ee/team/tickets/$ticketId/worklogs';

  /// Null means "not yours" or "no team here" — not an error to be shown.
  Future<EeWorklogPanel?> load(String ticketId) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(_path(ticketId));
      final data = res.data;
      return data == null ? null : EeWorklogPanel.fromJson(data);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 403 || code == 404) return null;
      throw asApiException(e);
    }
  }

  /// `userId` absent means "my own hours", which is the ordinary case and the
  /// one that needs no permission.
  Future<void> add(
    String ticketId, {
    required int minutes,
    String? workedOn,
    String? note,
    String? userId,
  }) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        _path(ticketId),
        data: {
          'minutes': minutes,
          'workedOn': ?workedOn,
          if (note != null && note.isNotEmpty) 'note': note,
          'userId': ?userId,
        },
      );
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }

  /// There is no `edit`. A correction is a removal and a new entry, because a
  /// duration that could be edited would let a month's total change after the
  /// month was reported.
  Future<void> remove(String ticketId, String worklogId) async {
    try {
      await _dio.delete<void>('${_path(ticketId)}/$worklogId');
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }
}
