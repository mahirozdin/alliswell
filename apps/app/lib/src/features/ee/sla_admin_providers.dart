import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/providers.dart';
import 'data/sla_admin_api.dart';
import 'data/sla_admin_models.dart';
import 'providers.dart';

/// SLA admin providers (EE-099).
///
/// Every mutation re-reads the whole area rather than patching state, the
/// idiom the services controller settled: the server may have refused,
/// clamped a value (the interval floor does exactly that) or moved the default
/// off another policy. One request back, and the screen cannot disagree with
/// what was actually stored.
final eeSlaAdminApiProvider = Provider<EeSlaAdminApi>(
  (ref) => EeSlaAdminApi(ref.watch(apiClientProvider)),
);

final eeSlaAdminProvider =
    AsyncNotifierProvider<EeSlaAdminController, EeSlaAdminData?>(
      EeSlaAdminController.new,
    );

class EeSlaAdminController extends AsyncNotifier<EeSlaAdminData?> {
  @override
  Future<EeSlaAdminData?> build() async {
    if (!ref.watch(eeFeatureProvider('teams'))) return null;
    return ref.watch(eeSlaAdminApiProvider).load();
  }

  Future<void> _then(Future<void> Function(EeSlaAdminApi api) action) async {
    state = await AsyncValue.guard(() async {
      final api = ref.read(eeSlaAdminApiProvider);
      await action(api);
      return api.load();
    });
  }

  Future<void> savePolicy({
    String? id,
    required String name,
    String? calendarId,
    bool? isDefault,
    int? warnPercent,
    int? escalationMinutes,
  }) => _then(
    (api) => api.savePolicy(
      id: id,
      name: name,
      calendarId: calendarId,
      isDefault: isDefault,
      warnPercent: warnPercent,
      escalationMinutes: escalationMinutes,
    ),
  );

  Future<void> saveTarget({
    required String policyId,
    required String priority,
    int? firstResponseMinutes,
    int? resolutionMinutes,
  }) => _then(
    (api) => api.saveTarget(
      policyId: policyId,
      priority: priority,
      firstResponseMinutes: firstResponseMinutes,
      resolutionMinutes: resolutionMinutes,
    ),
  );

  Future<void> deletePolicy(String id) => _then((api) => api.deletePolicy(id));

  Future<void> saveCalendar({
    String? id,
    required String name,
    String? timezone,
  }) =>
      _then((api) => api.saveCalendar(id: id, name: name, timezone: timezone));

  Future<void> saveHours(String calendarId, List<EeBusinessHour> hours) =>
      _then((api) => api.saveHours(calendarId, hours));

  Future<void> saveHolidays(String calendarId, List<EeHoliday> holidays) =>
      _then((api) => api.saveHolidays(calendarId, holidays));

  Future<void> deleteCalendar(String id) =>
      _then((api) => api.deleteCalendar(id));

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
  }) => _then(
    (api) => api.saveCheck(
      id: id,
      name: name,
      url: url,
      serviceId: serviceId,
      intervalSec: intervalSec,
      failureThreshold: failureThreshold,
      expectStatus: expectStatus,
      expectBody: expectBody,
      enabled: enabled,
    ),
  );

  Future<void> deleteCheck(String id) => _then((api) => api.deleteCheck(id));
}
