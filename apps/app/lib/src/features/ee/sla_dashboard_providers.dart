import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/providers.dart';
import 'data/sla_dashboard_api.dart';
import 'data/sla_dashboard_models.dart';
import 'providers.dart';

/// EE-098's dashboard provider.
///
/// Online-only, and that is the one thing worth stating here. Every other EE
/// ticket surface reads the replica so it works on a factory floor with no
/// signal; this one cannot, because a percentage is a fact about the WHOLE
/// desk and a device holds only its own units' rows. Showing 100 % because a
/// phone has not synced the breaches yet would be worse than showing nothing.
final eeSlaDashboardApiProvider = Provider<EeSlaDashboardApi>(
  (ref) => EeSlaDashboardApi(ref.watch(apiClientProvider)),
);

final eeSlaDashboardProvider =
    AsyncNotifierProvider<EeSlaDashboardController, EeSlaDashboard?>(
      EeSlaDashboardController.new,
    );

class EeSlaDashboardController extends AsyncNotifier<EeSlaDashboard?> {
  @override
  Future<EeSlaDashboard?> build() async {
    // No entitlement → the endpoint does not exist; asking would be a 404 on
    // every open (the house idiom: no entitlement, no capability).
    if (!ref.watch(eeFeatureProvider('teams'))) return null;
    return ref.watch(eeSlaDashboardApiProvider).load();
  }

  /// Pull to refresh. The numbers move as the sweep runs, so a manager
  /// watching a breach get resolved needs a way to ask again.
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(eeSlaDashboardApiProvider).load(),
    );
  }
}
