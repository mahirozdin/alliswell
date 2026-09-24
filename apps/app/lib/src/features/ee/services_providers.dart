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

  /// EE-228 — a service's whole setup, saved in the order that matters: who
  /// answers it first (the routing decides whether it works at all), then the
  /// shelf, then one PATCH with every other key that changed.
  Future<void> saveSetup(
    String serviceId, {
    List<String>? units,
    bool moveShelf = false,
    String? categoryId,
    Map<String, Object?> patch = const {},
  }) => _then(() async {
    final api = ref.read(eeServicesApiProvider);
    if (units != null) await api.setUnits(serviceId, units);
    if (moveShelf) await api.setCategory(serviceId, categoryId);
    if (patch.isNotEmpty) await api.patch(serviceId, patch);
  });
}

/// The catalogue's shelves (EE-212, EE-228). Null = not yours to shape.
final eeServiceCategoriesProvider =
    AsyncNotifierProvider<
      EeServiceCategoriesController,
      List<EeServiceCategory>?
    >(EeServiceCategoriesController.new);

class EeServiceCategoriesController
    extends AsyncNotifier<List<EeServiceCategory>?> {
  @override
  Future<List<EeServiceCategory>?> build() async {
    if (!ref.watch(eeFeatureProvider('teams'))) return null;
    try {
      return await ref.watch(eeServicesApiProvider).categories();
    } catch (_) {
      return null;
    }
  }

  /// Re-read, never patched in place — the depth rule is the server's, and a
  /// refused move must leave the screen showing what is true.
  Future<void> _then(Future<void> Function() action) async {
    state = await AsyncValue.guard(() async {
      await action();
      return ref.read(eeServicesApiProvider).categories();
    });
  }

  Future<void> create({required String name, String? parentId, String? icon}) =>
      _then(
        () => ref
            .read(eeServicesApiProvider)
            .createCategory(name: name, parentId: parentId, icon: icon),
      );

  Future<void> edit(String categoryId, Map<String, Object?> patch) => _then(
    () => ref.read(eeServicesApiProvider).updateCategory(categoryId, patch),
  );

  /// The services on it fall back to the root, so the list is asked again too.
  Future<void> remove(String categoryId) async {
    await _then(
      () => ref.read(eeServicesApiProvider).deleteCategory(categoryId),
    );
    ref.invalidate(eeServicesProvider);
  }
}

/// Should a "Services" entry exist at all? Same shape as the units answer:
/// null means the server handed back nothing to manage, and `false` while
/// loading keeps a settings row from flickering in on every launch.
final eeServicesVisibleProvider = Provider<bool>(
  (ref) => ref.watch(eeServicesProvider).value != null,
);
