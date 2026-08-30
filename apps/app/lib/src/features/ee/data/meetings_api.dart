import 'package:dio/dio.dart';

import '../../../core/api_exception.dart';
import 'meeting_models.dart';

/// The meetings client (EE-113/114/115).
///
/// [list] and [detail] hit different endpoints and return different types,
/// because the server deliberately keeps the transcript out of the list: an
/// hour of one is 228 KiB and a screen of ten meetings would download 2 MiB of
/// text before anybody asked to read a word of it.
class EeMeetingsApi {
  const EeMeetingsApi(this._dio);
  final Dio _dio;

  static const _base = '/api/v1/ee/team/meetings';

  Future<List<EeMeetingSummary>?> list(String workspaceId) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        _base,
        queryParameters: {'workspaceId': workspaceId},
      );
      return ((res.data?['items'] as List<dynamic>?) ?? const [])
          .map((e) => EeMeetingSummary.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 403 || code == 404) return null;
      throw asApiException(e);
    }
  }

  Future<EeMeetingDetail> detail(String meetingId) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('$_base/$meetingId');
      return EeMeetingDetail.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }

  /// Replaces the whole map. An empty name removes that speaker's name, which
  /// is how a screen says "I was wrong about that one".
  Future<EeMeetingDetail> nameSpeakers(
    String meetingId,
    Map<String, String> names,
  ) async {
    try {
      final res = await _dio.patch<Map<String, dynamic>>(
        '$_base/$meetingId/speakers',
        data: {'names': names},
      );
      return EeMeetingDetail.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }

  /// A short-lived link to the recording, minted on demand.
  ///
  /// Never cached in a model: it is a credential with an expiry, and a field
  /// holding one is a field somebody eventually persists.
  Future<String> audioUrl(String meetingId) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '$_base/$meetingId/audio',
      );
      return res.data?['url'] as String;
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }
}
