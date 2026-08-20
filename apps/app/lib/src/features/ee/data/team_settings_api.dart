import 'package:dio/dio.dart';

import '../../../core/api_exception.dart';
import 'team_settings.dart';

/// What a logo upload needs before the bytes can go anywhere: the object key
/// the server will later be asked to adopt, plus the presigned destination.
class EeLogoTicket {
  const EeLogoTicket({
    required this.key,
    required this.url,
    required this.headers,
  });

  final String key;
  final String url;

  /// Signed headers the PUT MUST carry — they are part of the signature.
  final Map<String, String> headers;
}

/// Team settings client (EE-037).
///
/// The logo follows core's three-step attachment handshake: ask, PUT straight
/// to storage, then tell the server to adopt what it can verify. The bytes
/// never pass through the API, which is why step 2 is not on this class at
/// all — it is the shared upload transport (files/providers.dart).
class EeTeamSettingsApi {
  const EeTeamSettingsApi(this._dio);
  final Dio _dio;

  static const _base = '/api/v1/ee/team/settings';
  static const _logo = '/api/v1/ee/team/logo';

  Future<EeTeamSettings> read() => _run(() async {
    final res = await _dio.get<Map<String, dynamic>>(_base);
    return EeTeamSettings.fromJson(res.data ?? const {});
  });

  /// Sends ONLY what changed. A key that is absent is left alone; a key sent
  /// as null is cleared — pass [clear] to say which nulls are deliberate,
  /// because a Dart null argument cannot tell the two apart on its own.
  Future<EeTeamSettings> update({
    String? name,
    String? locale,
    String? timezone,
    String? colorRgb,
    Set<String> clear = const {},
  }) => _run(() async {
    final body = <String, dynamic>{
      'name': ?name,
      'locale': ?locale,
      'timezone': ?timezone,
      'colorRgb': ?colorRgb,
      for (final field in clear) field: null,
    };
    final res = await _dio.patch<Map<String, dynamic>>(_base, data: body);
    return EeTeamSettings.fromJson(res.data ?? const {});
  });

  Future<EeLogoTicket> startLogoUpload({
    required String contentType,
    required int sizeBytes,
  }) => _run(() async {
    final res = await _dio.post<Map<String, dynamic>>(
      '$_logo/upload',
      data: {'contentType': contentType, 'sizeBytes': sizeBytes},
    );
    final body = res.data ?? const {};
    final upload =
        (body['upload'] as Map?)?.cast<String, dynamic>() ?? const {};
    return EeLogoTicket(
      key: body['key'] as String? ?? '',
      url: upload['url'] as String? ?? '',
      headers: ((upload['headers'] as Map?) ?? const {}).map(
        (k, v) => MapEntry('$k', '$v'),
      ),
    );
  });

  Future<EeTeamSettings> completeLogo({
    required String key,
    required int sizeBytes,
  }) => _run(() async {
    final res = await _dio.post<Map<String, dynamic>>(
      '$_logo/complete',
      data: {'key': key, 'sizeBytes': sizeBytes},
    );
    return EeTeamSettings.fromJson(res.data ?? const {});
  });

  Future<EeTeamSettings> removeLogo() => _run(() async {
    final res = await _dio.delete<Map<String, dynamic>>(_logo);
    return EeTeamSettings.fromJson(res.data ?? const {});
  });

  Future<T> _run<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }
}
