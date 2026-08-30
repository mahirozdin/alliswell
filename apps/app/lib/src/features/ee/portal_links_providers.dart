import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/providers.dart';
import 'data/portal_links_api.dart';
import 'data/portal_links_models.dart';
import 'providers.dart';

/// Public-link providers (EE-106).
///
/// Every mutation re-reads the whole area rather than patching state — the
/// idiom EE-099 settled, and it earns its keep here: revoking changes a link's
/// state AND frees a slot against the ceiling, extending an expired link
/// consumes one, and the quota block beside the list has to move with both. A
/// screen that patched one field would show a stale "1 of 2 used".
final eePortalLinksApiProvider = Provider<EePortalLinksApi>(
  (ref) => EePortalLinksApi(ref.watch(apiClientProvider)),
);

final eePortalLinksProvider =
    AsyncNotifierProvider<EePortalLinksController, EePortalLinksData?>(
      EePortalLinksController.new,
    );

class EePortalLinksController extends AsyncNotifier<EePortalLinksData?> {
  @override
  Future<EePortalLinksData?> build() async {
    if (!ref.watch(eeFeatureProvider('teams'))) return null;
    return ref.watch(eePortalLinksApiProvider).load();
  }

  /// Mints a link and hands the caller the URL ONCE.
  ///
  /// The credential is returned rather than stored in provider state on
  /// purpose: state is rebuilt, watched and inspected by anything that asks,
  /// and a secret living there would outlive the dialog that showed it. The
  /// caller gets it, shows it, and drops it.
  Future<EePortalLinkCreated> create({
    required String serviceId,
    String? unitId,
    int? ttlHours,
  }) async {
    final api = ref.read(eePortalLinksApiProvider);
    final created = await api.create(
      serviceId: serviceId,
      unitId: unitId,
      ttlHours: ttlHours,
    );
    state = await AsyncValue.guard(api.load);
    return created;
  }

  Future<void> revoke(String id) => _then((api) => api.revoke(id));

  Future<void> extend(String id, int ttlHours) =>
      _then((api) => api.extend(id, ttlHours));

  Future<void> setEnabled(String id, bool enabled) =>
      _then((api) => api.setEnabled(id, enabled));

  Future<void> _then(Future<void> Function(EePortalLinksApi api) action) async {
    state = await AsyncValue.guard(() async {
      final api = ref.read(eePortalLinksApiProvider);
      await action(api);
      return api.load();
    });
  }
}
