import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/providers.dart';
import 'data/performance_api.dart';
import 'data/performance_models.dart';
import 'providers.dart';

/// EE-205's panel provider, shaped exactly like EE-098's.
///
/// The window is a piece of UI state rather than a constructor argument, so
/// changing it re-runs the read without rebuilding the controller — a manager
/// comparing "this week" with "this quarter" does it twice a minute.
final eePerformanceApiProvider = Provider<EePerformanceApi>(
  (ref) => EePerformanceApi(ref.watch(apiClientProvider)),
);

/// Days back. Thirty is the endpoint's own default and what the screen opens
/// with; the other two are the questions people actually ask next.
///
/// A `Notifier` rather than a `StateProvider`, which this Riverpod does not
/// have — the house pattern, written down in `kb_providers.dart` and pointing
/// at `TicketFilterController` before it.
class EePerformanceRange extends Notifier<int> {
  @override
  int build() => 30;

  void set(int days) => state = days;
}

final eePerformanceRangeProvider = NotifierProvider<EePerformanceRange, int>(
  EePerformanceRange.new,
);

final eePerformanceProvider =
    AsyncNotifierProvider<EePerformanceController, EePerformance?>(
      EePerformanceController.new,
    );

class EePerformanceController extends AsyncNotifier<EePerformance?> {
  @override
  Future<EePerformance?> build() async {
    // No entitlement → the endpoint does not exist; asking would be a 404 on
    // every open (the house idiom: no entitlement, no capability).
    if (!ref.watch(eeFeatureProvider('teams'))) return null;
    final days = ref.watch(eePerformanceRangeProvider);
    return ref.watch(eePerformanceApiProvider).load(days: days);
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    final days = ref.read(eePerformanceRangeProvider);
    state = await AsyncValue.guard(
      () => ref.read(eePerformanceApiProvider).load(days: days),
    );
  }
}
