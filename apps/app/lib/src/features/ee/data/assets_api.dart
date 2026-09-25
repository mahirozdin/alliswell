import 'package:dio/dio.dart';

import '../../../core/api_exception.dart';
import 'assets_models.dart';

/// The equipment register (EE-191…EE-194).
///
/// Shaped after `EeTicketLinksApi`: a 403 or 404 on a LIST is an empty answer
/// rather than an error, because a register a team has closed is something to
/// draw as nothing. The writes travel intact.
class EeAssetsApi {
  const EeAssetsApi(this._dio);
  final Dio _dio;

  static const _base = '/api/v1/ee/team/assets';

  /// The register as the SERVER holds it — every workspace the caller
  /// reaches, the retired records EE-219 took off devices included.
  ///
  /// [q] (EE-238): every word somewhere in the tag or the name, the same two
  /// fields the device's own search folds.
  Future<List<EeAsset>> list({
    String? type,
    String? status,
    String? location,
    int? expiringWithinDays,
    String? q,
  }) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        _base,
        queryParameters: {
          'type': ?type,
          'status': ?status,
          if (location != null && location.trim().isNotEmpty)
            'location': location.trim(),
          'expiringWithinDays': ?expiringWithinDays,
          if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
        },
      );
      return ((res.data?['assets'] as List<dynamic>?) ?? const [])
          .map((e) => EeAsset.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
    } on DioException catch (error) {
      final code = error.response?.statusCode;
      if (code == 403 || code == 404) return const [];
      throw asApiException(error);
    }
  }

  /// One machine. A 404 travels: this is reached by a QR code, and a scan
  /// that silently shows an empty card is worse than one that says the tag is
  /// not in this register.
  Future<EeAsset> get(String assetId) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('$_base/$assetId');
      return EeAsset.fromJson(res.data ?? const {});
    } on DioException catch (error) {
      throw asApiException(error);
    }
  }

  Future<EeAssetTypes> types() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('$_base/types');
      return EeAssetTypes.fromJson(res.data ?? const {});
    } on DioException catch (error) {
      final code = error.response?.statusCode;
      if (code == 403 || code == 404) return const EeAssetTypes();
      throw asApiException(error);
    }
  }

  /// Everything that ever happened to it, archive included, plus the counts.
  Future<EeAssetHistory> history(String assetId, {int? months}) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '$_base/$assetId/tickets',
        queryParameters: {'months': ?months},
      );
      final data = res.data ?? const <String, dynamic>{};
      return EeAssetHistory(
        tickets: ((data['tickets'] as List<dynamic>?) ?? const [])
            .map((e) => EeAssetTicket.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        stats: EeAssetStats.fromJson(
          (data['stats'] as Map<String, dynamic>?) ?? const {},
        ),
      );
    } on DioException catch (error) {
      final code = error.response?.statusCode;
      if (code == 403 || code == 404) {
        return const EeAssetHistory(
          stats: EeAssetStats(
            months: 12,
            ticketCount: 0,
            openTicketCount: 0,
            openMinutes: 0,
          ),
        );
      }
      throw asApiException(error);
    }
  }

  Future<EeAsset> update(String assetId, Map<String, dynamic> patch) async {
    try {
      final res = await _dio.patch<Map<String, dynamic>>(
        '$_base/$assetId',
        data: patch,
      );
      return EeAsset.fromJson(res.data ?? const {});
    } on DioException catch (error) {
      throw asApiException(error);
    }
  }

  Future<EeAsset> setStatus(String assetId, String status) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '$_base/$assetId/status',
        data: {'status': status},
      );
      return EeAsset.fromJson(res.data ?? const {});
    } on DioException catch (error) {
      throw asApiException(error);
    }
  }
}
