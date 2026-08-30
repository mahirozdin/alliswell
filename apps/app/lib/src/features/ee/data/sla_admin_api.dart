import 'package:dio/dio.dart';

import '../../../core/api_exception.dart';
import 'sla_admin_models.dart';

/// The SLA admin client (EE-099).
///
/// One class for all three families because they sit behind ONE verb
/// (`sla.manage`) and one screen: splitting them would give three clients that
/// can only ever be used together, and three chances for their error handling
/// to drift apart.
///
/// `load()` returns null for 403/404 — "not yours" or "no team here" — the
/// same shape the catalogue client uses, because neither is an error to show.
class EeSlaAdminApi {
  const EeSlaAdminApi(this._dio);
  final Dio _dio;

  static const _policies = '/api/v1/ee/team/sla/policies';
  static const _calendars = '/api/v1/ee/team/sla/calendars';
  static const _checks = '/api/v1/ee/team/sla/checks';

  Future<EeSlaAdminData?> load() async {
    try {
      final results = await Future.wait([
        _dio.get<Map<String, dynamic>>(_policies),
        _dio.get<Map<String, dynamic>>(_calendars),
        _dio.get<Map<String, dynamic>>(_checks),
      ]);
      return EeSlaAdminData(
        policies: ((results[0].data?['policies'] as List?) ?? const [])
            .map((p) => EeSlaPolicy.fromJson(p as Map<String, dynamic>))
            .toList(),
        calendars: ((results[1].data?['calendars'] as List?) ?? const [])
            .map((c) => EeBusinessCalendar.fromJson(c as Map<String, dynamic>))
            .toList(),
        checks: ((results[2].data?['checks'] as List?) ?? const [])
            .map((c) => EeHealthCheck.fromJson(c as Map<String, dynamic>))
            .toList(),
      );
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

  // ── policies ──────────────────────────────────────────────────────────

  Future<void> savePolicy({
    String? id,
    required String name,
    String? calendarId,
    bool? isDefault,
    int? warnPercent,
    int? escalationMinutes,
  }) => _run(() async {
    // `key: ?value` is the null-aware ELEMENT: the entry is omitted when the
    // value is null, which is what "not edited" means here. `calendarId` is
    // deliberately NOT null-aware — sending it as null is how a policy is
    // moved back to 24/7, and an omitted key would leave it alone.
    final body = <String, dynamic>{
      'name': name,
      'calendarId': calendarId,
      'isDefault': ?isDefault,
      'warnPercent': ?warnPercent,
      'escalationMinutes': ?escalationMinutes,
    };
    if (id == null) {
      await _dio.post<Map<String, dynamic>>(_policies, data: body);
    } else {
      await _dio.patch<Map<String, dynamic>>('$_policies/$id', data: body);
    }
  });

  Future<void> saveTarget({
    required String policyId,
    required String priority,
    int? firstResponseMinutes,
    int? resolutionMinutes,
  }) => _run(() async {
    await _dio.put<void>(
      '$_policies/$policyId/targets/$priority',
      // Sent explicitly as null rather than omitted: clearing a target is a
      // real edit, and an API that cannot express it cannot undo a promise.
      data: {
        'firstResponseMinutes': firstResponseMinutes,
        'resolutionMinutes': resolutionMinutes,
      },
    );
  });

  Future<void> deletePolicy(String id) =>
      _run(() async => _dio.delete<void>('$_policies/$id'));

  // ── calendars ─────────────────────────────────────────────────────────

  Future<void> saveCalendar({
    String? id,
    required String name,
    String? timezone,
  }) => _run(() async {
    final body = {'name': name, 'timezone': timezone};
    if (id == null) {
      await _dio.post<Map<String, dynamic>>(_calendars, data: body);
    } else {
      await _dio.patch<void>('$_calendars/$id', data: body);
    }
  });

  /// The whole week, replaced. See the server's `setCalendarHours` for why
  /// this is a set rather than one interval at a time.
  Future<void> saveHours(String calendarId, List<EeBusinessHour> hours) =>
      _run(() async {
        await _dio.put<void>(
          '$_calendars/$calendarId/hours',
          data: {'hours': hours.map((h) => h.toJson()).toList()},
        );
      });

  Future<void> saveHolidays(String calendarId, List<EeHoliday> holidays) =>
      _run(() async {
        await _dio.put<void>(
          '$_calendars/$calendarId/holidays',
          data: {'holidays': holidays.map((h) => h.toJson()).toList()},
        );
      });

  Future<void> deleteCalendar(String id) =>
      _run(() async => _dio.delete<void>('$_calendars/$id'));

  // ── monitors ──────────────────────────────────────────────────────────

  Future<void> saveCheck({
    String? id,
    required String name,
    required String url,
    String? serviceId,
    int? intervalSec,
    int? failureThreshold,
    int? expectStatus,
    String? expectBody,
    bool? enabled,
  }) => _run(() async {
    final body = <String, dynamic>{
      'name': name,
      'url': url,
      // These three travel even as null: clearing a service link, a status
      // expectation or an expected string is a real edit, and an omitted key
      // would silently leave the old value in place.
      'serviceId': serviceId,
      'expectStatus': expectStatus,
      'expectBody': expectBody,
      'intervalSec': ?intervalSec,
      'failureThreshold': ?failureThreshold,
      'enabled': ?enabled,
    };
    if (id == null) {
      await _dio.post<Map<String, dynamic>>(_checks, data: body);
    } else {
      await _dio.patch<void>('$_checks/$id', data: body);
    }
  });

  Future<void> deleteCheck(String id) =>
      _run(() async => _dio.delete<void>('$_checks/$id'));
}
