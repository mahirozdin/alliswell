import 'package:dio/dio.dart';

import '../../../core/api_exception.dart';
import 'team_mail_models.dart';

/// The team mail client (OPH-290), behind `team.manage_mail`.
///
/// Shaped after `EeIdentityApi`: [read] returns null for 403/404 — "not yours"
/// or "no team here" — because neither is an error to put in front of
/// somebody, and on an instance without the feature the routes do not exist.
///
/// There is no method that could return a password, and that is not a gap to
/// fill later: no endpoint exists to back one. The class shape is the client
/// half of the same promise the serializer keeps.
class EeTeamMailApi {
  const EeTeamMailApi(this._dio);
  final Dio _dio;

  static const _base = '/api/v1/ee/team/mail';

  Future<EeTeamMail?> read() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(_base);
      return EeTeamMail.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 403 || code == 404) return null;
      throw asApiException(e);
    }
  }

  /// Only the fields that are passed travel. Omitting `password` LEAVES the
  /// stored one — editing a port must not require retyping a credential —
  /// and passing null clears it, which is a different act on purpose.
  Future<EeTeamMail> save({
    String? host,
    int? port,
    bool? secure,
    Object? username = _absent,
    Object? password = _absent,
    String? fromAddress,
    Object? fromName = _absent,
    bool? enabled,
  }) async {
    final body = <String, dynamic>{
      'host': ?host,
      'port': ?port,
      'secure': ?secure,
      if (!identical(username, _absent)) 'username': username,
      if (!identical(password, _absent)) 'password': password,
      'fromAddress': ?fromAddress,
      if (!identical(fromName, _absent)) 'fromName': fromName,
      'enabled': ?enabled,
    };
    try {
      final res = await _dio.put<Map<String, dynamic>>(_base, data: body);
      return EeTeamMail.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }

  /// Sends one real message through the relay. `password` lets a form check a
  /// credential BEFORE saving it; omitted, the stored one is used.
  Future<EeTeamMailTestResult> test({String? password, String? to}) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '$_base/test',
        data: <String, dynamic>{'password': ?password, 'to': ?to},
      );
      return EeTeamMailTestResult.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }
}

/// Distinguishes "not mentioned" from "explicitly null" in [EeTeamMailApi.save].
const Object _absent = Object();
