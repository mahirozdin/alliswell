import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/providers.dart';
import 'data/identity_api.dart';
import 'data/identity_models.dart';
import 'providers.dart';

/// Identity-provider state (OPH-287).
///
/// Every mutation re-reads the whole list rather than patching state — the
/// idiom EE-099 settled and EE-111 repeated. Here the reason is sharper than
/// usual: the server derives `missingRequired` and `ready` from a dictionary
/// this client does not have, so a patched row would be a row whose "can I
/// switch this on" answer the client invented.
final eeIdentityApiProvider = Provider<EeIdentityApi>(
  (ref) => EeIdentityApi(ref.watch(apiClientProvider)),
);

final eeIdentityProvidersProvider =
    AsyncNotifierProvider<EeIdentityController, List<EeIdentityProvider>?>(
      EeIdentityController.new,
    );

class EeIdentityController extends AsyncNotifier<List<EeIdentityProvider>?> {
  @override
  Future<List<EeIdentityProvider>?> build() async {
    // The `directory` entitlement, not `teams`: on an instance without it the
    // routes do not exist, and asking would be a 404 the screen has to explain
    // away. Absent entitlement means the screen is never reachable anyway —
    // the settings row is gated too — but a provider that asks regardless is
    // one refresh away from putting a 404 in front of somebody.
    if (!ref.watch(eeFeatureProvider('directory'))) return null;
    return ref.watch(eeIdentityApiProvider).list();
  }

  Future<void> create({
    required String type,
    required String displayName,
    Map<String, dynamic>? config,
    String? secret,
  }) => _then(
    (api) => api.create(
      type: type,
      displayName: displayName,
      config: config,
      secret: secret,
    ),
  );

  /// Named `patch` and not `update`: riverpod's own AsyncNotifier already has
  /// an `update`, and shadowing it compiles into an invalid override rather
  /// than a confusing one.
  Future<void> patch(
    String id, {
    String? displayName,
    bool? enabled,
    int? priority,
    Map<String, dynamic>? config,
    Object? secret = eeKeepSecret,
  }) => _then(
    (api) => api.update(
      id,
      displayName: displayName,
      enabled: enabled,
      priority: priority,
      config: config,
      secret: secret,
    ),
  );

  Future<void> remove(String id) => _then((api) => api.remove(id));

  /// Testing is NOT a mutation of this list from the client's point of view —
  /// but the server records what it learned on the provider row, so the list
  /// is re-read afterwards and a screen that just tested sees the new status
  /// without asking for it.
  Future<EeIdentityTestResult> test(
    String id, {
    String? secret,
    String? username,
    String? password,
  }) async {
    final api = ref.read(eeIdentityApiProvider);
    final result = await api.test(
      id,
      secret: secret,
      username: username,
      password: password,
    );
    state = await AsyncValue.guard(api.list);
    return result;
  }

  Future<void> _then(Future<void> Function(EeIdentityApi api) action) async {
    state = await AsyncValue.guard(() async {
      final api = ref.read(eeIdentityApiProvider);
      await action(api);
      return api.list();
    });
  }
}
