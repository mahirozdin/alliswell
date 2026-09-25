import 'package:dio/dio.dart';

import '../../../core/api_exception.dart';
import 'problems_models.dart';

/// The problem client (EE-188's REST, read and written by EE-270's screens).
///
/// The LIST is not here, for the change screens' reason: the list is the
/// device's copy. What is here is what the copy cannot carry — the requests a
/// problem explains (a link that lives on the request's side) — the server's
/// copy of a record this device does not hold, and the one write, raising a
/// record. Moving a problem's status is absent: the server has no "moves this
/// person may make" answer, and the app does not copy the map (§0.0/6).
class EeProblemsApi {
  const EeProblemsApi(this._dio);
  final Dio _dio;

  static const _base = '/api/v1/ee/team/problems';

  Future<EeProblem> get(String id) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('$_base/$id');
      return EeProblem.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }

  /// EE-270 — the requests this problem explains, as this person may see
  /// them.
  Future<EeProblemTickets> tickets(String id) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('$_base/$id/tickets');
      return EeProblemTickets.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }

  /// Raises one (`problems.manage`). From a request ([sourceTicketId]) the
  /// server files it in the request's desk and links the two in one step —
  /// which also takes `tickets.link` (EE-280); otherwise it is filed in the
  /// desk on screen. Exactly one of the two is sent.
  Future<EeProblem> create({
    required String title,
    required String symptom,
    String? workaround,
    String? sourceTicketId,
    String? workspaceId,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        _base,
        data: {
          'title': title,
          'symptom': symptom,
          if (workaround != null && workaround.isNotEmpty)
            'workaround': workaround,
          'sourceTicketId': ?sourceTicketId,
          if (sourceTicketId == null) 'workspaceId': ?workspaceId,
        },
      );
      return EeProblem.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }
}
