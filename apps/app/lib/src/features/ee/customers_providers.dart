import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/providers.dart';
import 'data/customers_api.dart';
import 'providers.dart';

/// The company screens' providers (OPH-360, UI-AUDIT #18).
///
/// Mutations re-read rather than patch, the house idiom: archiving changes
/// a row's state, and a reactivation may have been refused — one request back
/// and the screen cannot disagree with what was stored. A refusal reaches the
/// caller (a snackbar), never the list's own state.
final eeCustomersApiProvider = Provider<EeCustomersApi>(
  (ref) => EeCustomersApi(ref.watch(apiClientProvider)),
);

final eeCustomersProvider =
    AsyncNotifierProvider<EeCustomersController, List<EeCustomer>?>(
      EeCustomersController.new,
    );

class EeCustomersController extends AsyncNotifier<List<EeCustomer>?> {
  @override
  Future<List<EeCustomer>?> build() async {
    if (!ref.watch(eeFeatureProvider('teams'))) return null;
    return ref.watch(eeCustomersApiProvider).list();
  }

  Future<void> _then(Future<void> Function(EeCustomersApi api) action) async {
    final api = ref.read(eeCustomersApiProvider);
    try {
      await action(api);
    } finally {
      state = await AsyncValue.guard(api.list);
    }
  }

  Future<void> create(String name) => _then((api) => api.create(name));

  Future<void> rename(String id, String name) =>
      _then((api) => api.update(id, name: name));

  Future<void> setArchived(String id, {required bool archived}) =>
      _then((api) => api.update(id, archived: archived));
}

/// A company's contacts, page by page. The list is keyset-paged on the
/// server (a company may have thousands), so "more" is a button that asks
/// for the next page rather than a list that pretends to be complete.
final eeCustomerContactsProvider =
    AsyncNotifierProvider.family<
      EeCustomerContactsController,
      EeCustomerContactsPage,
      String
    >(EeCustomerContactsController.new);

class EeCustomerContactsController
    extends AsyncNotifier<EeCustomerContactsPage> {
  EeCustomerContactsController(this.customerId);
  final String customerId;

  @override
  Future<EeCustomerContactsPage> build() =>
      ref.watch(eeCustomersApiProvider).contacts(customerId);

  Future<void> loadMore() async {
    final current = state.value;
    if (current?.nextCursor == null) return;
    final next = await ref
        .read(eeCustomersApiProvider)
        .contacts(customerId, cursor: current!.nextCursor);
    state = AsyncData(
      EeCustomerContactsPage(
        contacts: [...current.contacts, ...next.contacts],
        nextCursor: next.nextCursor,
      ),
    );
  }

  Future<void> _then(Future<void> Function(EeCustomersApi api) action) async {
    final api = ref.read(eeCustomersApiProvider);
    try {
      await action(api);
    } finally {
      state = await AsyncValue.guard(() => api.contacts(customerId));
    }
  }

  Future<String> add({required String email, String? displayName}) async {
    late String id;
    await _then((api) async {
      id = await api.addContact(
        customerId,
        email: email,
        displayName: displayName,
      );
    });
    return id;
  }

  Future<void> setDeactivated(String contactId, {required bool off}) =>
      _then((api) => api.setDeactivated(contactId, off: off));
}
