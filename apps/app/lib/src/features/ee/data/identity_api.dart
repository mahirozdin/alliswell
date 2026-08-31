import 'package:dio/dio.dart';

import '../../../core/api_exception.dart';
import 'identity_models.dart';

/// The identity-provider client (OPH-287), behind `team.manage_identity`.
///
/// Shaped after `EeTeamAiApi`: [list] returns null for 403/404 — "not yours"
/// or "no team here" — because neither is an error to put in front of
/// somebody, and on an instance without the feature the routes do not exist
/// at all.
///
/// There is no `get(id)` and no method that could return a credential, and
/// that is not a gap to fill later: no endpoint exists to back one. The class
/// shape is the client-side half of the same promise the serializer keeps.
class EeIdentityApi {
  const EeIdentityApi(this._dio);
  final Dio _dio;

  static const _base = '/api/v1/ee/team/identity/providers';

  Future<List<EeIdentityProvider>?> list() async {
    try {
      final res = await _dio.get<List<dynamic>>(_base);
      return (res.data ?? const [])
          .map((e) => EeIdentityProvider.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 403 || code == 404) return null;
      throw asApiException(e);
    }
  }

  /// Creates one. It arrives disabled whatever this sends — the server has no
  /// parameter for creating one switched on.
  Future<void> create({
    required String type,
    required String displayName,
    Map<String, dynamic>? config,
    String? secret,
  }) => _run(
    () => _dio.post<void>(
      _base,
      data: {
        'type': type,
        'displayName': displayName,
        'config': ?config,
        'secret': ?secret,
      },
    ),
  );

  /// Absent `secret` leaves the stored one alone; explicit null removes it.
  /// The distinction is the server's and it is carried here rather than
  /// flattened, so editing a base DN does not re-encrypt a bind password.
  Future<void> update(
    String id, {
    String? displayName,
    bool? enabled,
    int? priority,
    Map<String, dynamic>? config,
    Object? secret = eeKeepSecret,
  }) => _run(
    () => _dio.patch<void>(
      '$_base/$id',
      data: {
        'displayName': ?displayName,
        'enabled': ?enabled,
        'priority': ?priority,
        'config': ?config,
        if (!identical(secret, eeKeepSecret)) 'secret': secret,
      },
    ),
  );

  Future<void> remove(String id) => _run(() => _dio.delete<void>('$_base/$id'));

  /// Asks the server to try the connection. A refusal is a 200 with `ok:false`
  /// — the admin asked a question and got an answer — so this does not throw
  /// for a directory that simply says no.
  Future<EeIdentityTestResult> test(
    String id, {
    String? secret,
    String? username,
    String? password,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '$_base/$id/test',
        data: {'secret': ?secret, 'username': ?username, 'password': ?password},
      );
      return EeIdentityTestResult.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }

  Future<void> _run(Future<void> Function() call) async {
    try {
      await call();
    } on DioException catch (e) {
      // The server's sentences reach the screen intact — among them "this
      // provider still needs: baseDn", which is the only actionable thing in
      // a refusal to switch one on.
      throw asApiException(e);
    }
  }
}

/// "Do not touch the stored secret" — distinct from null, which REMOVES it.
/// Exported because the screen and the controller both have to be able to
/// say it, and a second private sentinel in either file would be a value
/// `identical` refuses to recognise and the server would receive as a
/// nonsense body.
const Object eeKeepSecret = Object();
