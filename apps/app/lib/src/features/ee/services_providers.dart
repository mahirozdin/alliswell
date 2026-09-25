import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/providers.dart';
import 'data/new_ticket_api.dart';
import 'data/services_api.dart';
import 'data/services_models.dart';
import 'new_ticket_providers.dart';
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

  /// EE-229 — the designer's publish: the WHOLE schema in one PATCH, which
  /// the server turns into the next version (EE-214). No fields at all is
  /// null, "the plain subject + body form" — not `{fields: []}`, which the
  /// server would store as a different form that asks the same nothing.
  Future<void> publishForm(String serviceId, List<EeServiceField> fields) =>
      _then(
        () => ref.read(eeServicesApiProvider).patch(serviceId, {
          'formSchema': fields.isEmpty
              ? null
              : {'fields': fields.map((f) => f.toJson()).toList()},
        }),
      );
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

/// What a screen that does not EDIT the catalogue may say about a service
/// (EE-284): its name, whether it asks questions, whether it is archived.
class EeServiceGlance {
  const EeServiceGlance({
    required this.id,
    required this.name,
    required this.hasForm,
    this.archived = false,
  });

  final String id;
  final String name;
  final bool hasForm;
  final bool archived;
}

/// Every service this person may name, by id (EE-284).
///
/// The admin list above answers only `services.manage`; everybody else gets
/// null from it. Three screens read it anyway — the request's form answers
/// (EE-278), a change's services and the new change's picker (EE-269) — so for
/// an agent the answers never showed and every chip read "a service the
/// catalogue does not name". Measured by EE-272's read of the handbooks.
///
/// So: the admin list where it answers (it also knows archived services and
/// forms nobody can file today), and otherwise the member catalogue EE-225
/// reads to file a request — live, routed services with the form in force,
/// open to every member. Nothing new is asked while the admin list is still
/// loading, so an admin never pays for the second read.
final eeServiceGlancesProvider = Provider<Map<String, EeServiceGlance>>((ref) {
  final admin = ref.watch(eeServicesProvider);
  if (!admin.hasValue) return const {};
  final services = admin.value;
  if (services != null) {
    return {
      for (final s in services)
        s.id: EeServiceGlance(
          id: s.id,
          name: s.name,
          hasForm: s.formFields.isNotEmpty,
          archived: s.archived,
        ),
    };
  }
  final catalog = ref.watch(eeCatalogProvider).value;
  return {
    for (final s in catalog?.services ?? const <EeCatalogService>[])
      s.id: EeServiceGlance(
        id: s.id,
        name: s.name,
        hasForm: s.fields.isNotEmpty,
      ),
  };
});
