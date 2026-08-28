import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/providers.dart';
import 'data/services_api.dart';
import 'data/services_models.dart';
import 'providers.dart';

/// Service catalogue providers (EE-082).
///
/// Shaped after the units controller (EE-057) with one difference that is
/// worth stating rather than inheriting by accident: `services.manage` is a
/// plain role-based verb, so gating on [canProvider] here WOULD be honest.
/// The list endpoint is still the gate, for a different reason — the answer
/// distinguishes "not yours" (null) from "yours, and empty" (`[]`), and only
/// the server can tell those apart on a device that has never synced.

final eeServicesApiProvider = Provider<EeServicesApi>(
  (ref) => EeServicesApi(ref.watch(apiClientProvider)),
);

final eeServicesProvider =
    AsyncNotifierProvider<EeServicesController, List<EeService>?>(
      EeServicesController.new,
    );

class EeServicesController extends AsyncNotifier<List<EeService>?> {
  @override
  Future<List<EeService>?> build() async {
    // No entitlement → the endpoints do not exist; asking would be a 404 on
    // every app start (the house idiom: no entitlement, no capability).
    if (!ref.watch(eeFeatureProvider('teams'))) return null;
    try {
      return await ref.watch(eeServicesApiProvider).list();
    } catch (_) {
      // Offline, or no team at this address. Either way there is no catalogue
      // to draw, and an error screen would blame the user for their signal.
      return null;
    }
  }

  /// Every mutation re-reads the list rather than patching it: the server may
  /// have refused, trimmed a name, or rejected a routing change wholesale. One
  /// request, and the screen cannot disagree with the server.
  Future<void> _then(Future<void> Function() action) async {
    state = await AsyncValue.guard(() async {
      await action();
      return ref.read(eeServicesApiProvider).list();
    });
  }

  Future<void> create({required String name, String? description}) => _then(
    () => ref
        .read(eeServicesApiProvider)
        .create(name: name, description: description),
  );

  Future<void> rename(
    String serviceId, {
    required String name,
    String? description,
  }) => _then(
    () => ref
        .read(eeServicesApiProvider)
        .update(
          serviceId,
          name: name,
          description: description,
          // An emptied description is a CLEAR, not an omission: the field was
          // there and the admin wiped it.
          clear: (description == null || description.isEmpty)
              ? const {'description'}
              : const {},
        ),
  );

  Future<void> setArchived(String serviceId, {required bool archived}) => _then(
    () => ref
        .read(eeServicesApiProvider)
        .setArchived(serviceId, archived: archived),
  );

  Future<void> setUnits(String serviceId, List<String> unitIds) =>
      _then(() => ref.read(eeServicesApiProvider).setUnits(serviceId, unitIds));

  Future<void> setFields(
    String serviceId,
    List<EeServiceField> fields,
  ) => _then(
    () => ref
        .read(eeServicesApiProvider)
        .update(
          serviceId,
          formSchema: fields.isEmpty
              ? null
              : {'fields': fields.map((f) => f.toJson()).toList()},
          // No fields at all is null, not `{fields: []}` — the server treats null
          // as "the plain subject + body form", which is what an emptied list means.
          clear: fields.isEmpty ? const {'formSchema'} : const {},
        ),
  );
}

/// Should a "Services" entry exist at all? Same shape as the units answer:
/// null means the server handed back nothing to manage, and `false` while
/// loading keeps a settings row from flickering in on every launch.
final eeServicesVisibleProvider = Provider<bool>(
  (ref) => ref.watch(eeServicesProvider).value != null,
);
