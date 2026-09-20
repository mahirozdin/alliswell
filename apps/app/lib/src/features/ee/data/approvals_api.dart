import 'package:dio/dio.dart';

import '../../../core/api_exception.dart';
import 'approvals_models.dart';

/// The approvals client (EE-184).
///
/// Shaped after `EeTeamWebhooksApi`: a 403 or 404 on the LIST is an empty
/// answer rather than an error, because "no team here" and "not yours" are
/// both things to draw as nothing, not as a red box.
///
/// A decision is different and its failures travel intact. Three of them are
/// sentences somebody has to read: you are not the one being asked
/// (`APPROVAL_NOT_YOURS`), somebody answered first
/// (`APPROVAL_ALREADY_DECIDED`), and the reason is missing. Replacing those
/// with a generic failure would hide the only actionable thing in them.
///
/// THERE IS NO `create` HERE, and that absence is deliberate: EE-184's asking
/// path belongs to the flows that need a signature — the catalogue (EE-185)
/// and change management (EE-186) — and a button that manufactured approvals
/// from this screen would be a way to gate somebody else's request for fun.
class EeApprovalsApi {
  const EeApprovalsApi(this._dio);
  final Dio _dio;

  static const _base = '/api/v1/ee/team/approvals';

  /// `mine` is the default because the screen this serves is one person's
  /// queue. `team` is the widening, for somebody looking at the whole desk.
  Future<List<EeApproval>> list({
    String status = 'pending',
    bool mine = true,
  }) async {
    try {
      final res = await _dio.get<List<dynamic>>(
        _base,
        queryParameters: {'status': status, 'scope': mine ? 'mine' : 'team'},
      );
      return (res.data ?? const [])
          .map((e) => EeApproval.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 403 || code == 404) return const [];
      throw asApiException(e);
    }
  }

  Future<EeApproval> decide(
    String id, {
    required bool approve,
    required String reason,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '$_base/$id/decision',
        data: {'decision': approve ? 'approved' : 'rejected', 'reason': reason},
      );
      return EeApproval.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }
}
