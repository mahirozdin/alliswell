import 'package:dio/dio.dart';

import '../../../core/api_exception.dart';
import 'rules_models.dart';

/// EE-308 — the rules screen's client: automation rules (EE-179) and routing
/// rules (EE-202), both behind `sla.manage`.
///
/// The loads return null on 403/404 — "not yours" or "no team here" — the
/// shape every admin client here uses, because neither is an error to show.
/// Every other refusal arrives as an [ApiException] with the server's code,
/// which the editors place on the field it is about.
class EeRulesApi {
  const EeRulesApi(this._dio);
  final Dio _dio;

  static const _automation = '/api/v1/ee/team/sla/rules';
  static const _routing = '/api/v1/ee/team/classification/rules';

  Future<T?> _load<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 403 || code == 404) return null;
      throw asApiException(e);
    }
  }

  Future<T> _run<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }

  // ── automation ────────────────────────────────────────────────────────

  Future<List<EeAutomationRule>?> loadAutomation() => _load(() async {
    final res = await _dio.get<Map<String, dynamic>>(_automation);
    return ((res.data?['rules'] as List?) ?? const [])
        .map((r) => EeAutomationRule.fromJson(r as Map<String, dynamic>))
        .toList();
  });

  Future<EeRuleOptions?> options() => _load(() async {
    final res = await _dio.get<Map<String, dynamic>>('$_automation/options');
    return EeRuleOptions.fromJson(res.data ?? const {});
  });

  Future<String> createAutomation(Map<String, dynamic> body) => _run(() async {
    final res = await _dio.post<Map<String, dynamic>>(_automation, data: body);
    return res.data?['id'] as String? ?? '';
  });

  Future<void> patchAutomation(String id, Map<String, dynamic> body) =>
      _run(() async => _dio.patch<void>('$_automation/$id', data: body));

  Future<void> deleteAutomation(String id) =>
      _run(() async => _dio.delete<void>('$_automation/$id'));

  Future<String> duplicateAutomation(String id) => _run(() async {
    final res = await _dio.post<Map<String, dynamic>>(
      '$_automation/$id/duplicate',
    );
    return res.data?['id'] as String? ?? '';
  });

  Future<void> reorderAutomation(List<String> ids) => _run(
    () async => _dio.put<void>('$_automation/order', data: {'ids': ids}),
  );

  /// The UNSAVED draft against request #[ticketNumber]; [id] lays it over the
  /// stored rule (its pause, its ceiling). A read on the server.
  Future<EeRuleTestResult> testAutomation({
    String? id,
    required Map<String, dynamic> draft,
    required int ticketNumber,
  }) => _run(() async {
    final res = await _dio.post<Map<String, dynamic>>(
      '$_automation/test',
      data: {
        for (final e in draft.entries)
          if (e.value != null) e.key: e.value,
        'id': ?(id == null || id.isEmpty ? null : id),
        'ticketNumber': ticketNumber,
      },
    );
    return EeRuleTestResult.fromJson(res.data ?? const {});
  });

  // ── routing ───────────────────────────────────────────────────────────

  Future<List<EeClassificationRule>?> loadRouting() => _load(() async {
    final res = await _dio.get<Map<String, dynamic>>(_routing);
    return ((res.data?['rules'] as List?) ?? const [])
        .map((r) => EeClassificationRule.fromJson(r as Map<String, dynamic>))
        .toList();
  });

  Future<String> createRouting(Map<String, dynamic> body) => _run(() async {
    final res = await _dio.post<Map<String, dynamic>>(_routing, data: body);
    return res.data?['id'] as String? ?? '';
  });

  Future<void> patchRouting(String id, Map<String, dynamic> body) =>
      _run(() async => _dio.patch<void>('$_routing/$id', data: body));

  Future<void> deleteRouting(String id) =>
      _run(() async => _dio.delete<void>('$_routing/$id'));

  Future<String> duplicateRouting(String id) => _run(() async {
    final res = await _dio.post<Map<String, dynamic>>(
      '$_routing/$id/duplicate',
    );
    return res.data?['id'] as String? ?? '';
  });

  Future<void> reorderRouting(List<String> ids) =>
      _run(() async => _dio.put<void>('$_routing/order', data: {'ids': ids}));

  Future<EeClassificationDryRun> dryRunRouting({
    String? id,
    required Map<String, dynamic> draft,
  }) => _run(() async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/api/v1/ee/team/classification/dry-run',
      data: {
        for (final e in draft.entries)
          if (e.value != null) e.key: e.value,
        'id': ?(id == null || id.isEmpty ? null : id),
      },
    );
    return EeClassificationDryRun.fromJson(res.data ?? const {});
  });
}
