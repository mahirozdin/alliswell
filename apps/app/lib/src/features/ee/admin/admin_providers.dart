import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/secret_store.dart';
import '../../auth/providers.dart' show apiBaseUrlProvider, secretStoreProvider;
import '../providers.dart';
import 'data/admin_api.dart';
import 'data/admin_models.dart';

/// The operator console's session (EE-033), deliberately parallel to — and
/// never mixed with — the person's own session.
///
/// A workspace user signing in changes nothing here, and an operator signing
/// in changes nothing there. On a self-hosted install the operator may have no
/// AllisWell account at all, which is exactly why `/admin` must work while the
/// rest of the app is signed out.

/// Its own Dio: the app's client carries the user's `AuthInterceptor`, and a
/// shared instance would let one realm's credentials ride on the other's
/// requests.
final adminApiProvider = Provider<AdminApi>(
  (ref) => AdminApi(Dio(BaseOptions(baseUrl: ref.watch(apiBaseUrlProvider)))),
);

/// Stored under its own key, so signing the PERSON out cannot take the
/// operator's session with it (and vice versa).
class AdminSessionStore {
  const AdminSessionStore(this._store);

  static const storageKey = 'alliswell_admin_session';

  final SecretStore _store;

  Future<AdminSession?> read() async {
    final raw = await _store.read(storageKey);
    if (raw == null) return null;
    try {
      final session = AdminSession.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      if (session.isExpired) {
        await clear();
        return null;
      }
      return session;
    } on Object {
      await clear();
      return null;
    }
  }

  Future<void> save(AdminSession session) =>
      _store.write(storageKey, jsonEncode(session.toJson()));

  Future<void> clear() => _store.delete(storageKey);
}

final adminSessionStoreProvider = Provider<AdminSessionStore>(
  (ref) => AdminSessionStore(ref.watch(secretStoreProvider)),
);

final adminSessionProvider =
    AsyncNotifierProvider<AdminSessionController, AdminSession?>(
      AdminSessionController.new,
    );

class AdminSessionController extends AsyncNotifier<AdminSession?> {
  @override
  Future<AdminSession?> build() => ref.watch(adminSessionStoreProvider).read();

  Future<void> signIn({
    required String email,
    required String password,
    required String totpCode,
  }) async {
    final session = await ref
        .read(adminApiProvider)
        .signIn(email: email, password: password, totpCode: totpCode);
    await ref.read(adminSessionStoreProvider).save(session);
    state = AsyncData(session);
  }

  Future<void> signOut() async {
    final session = state.value;
    if (session != null) {
      await ref.read(adminApiProvider).signOut(session.refreshToken);
    }
    await ref.read(adminSessionStoreProvider).clear();
    state = const AsyncData(null);
  }

  /// Rotates when a call comes back 401. The console asks for this rather than
  /// installing an interceptor, because a silent refresh loop on an operator
  /// console is a way to keep somebody signed in who should have been asked
  /// again.
  Future<String?> refreshed() async {
    final session = state.value;
    if (session == null) return null;
    try {
      final next = await ref
          .read(adminApiProvider)
          .refresh(session.refreshToken);
      await ref.read(adminSessionStoreProvider).save(next);
      state = AsyncData(next);
      return next.accessToken;
    } on Object {
      await signOut();
      return null;
    }
  }
}

/// `true` only when an operator is signed in on THIS device. The router's
/// guard reads it, and every admin screen assumes it.
final isInstanceAdminProvider = Provider<bool>(
  (ref) => ref.watch(adminSessionProvider).value != null,
);

/// The console exists only where the overlay does. Absent entitlements mean an
/// instance that has no operator realm at all, and a sign-in form for one
/// would be a promise nothing can keep.
final adminConsoleAvailableProvider = Provider<bool>(
  (ref) => ref.watch(eeFeatureProvider('teams')),
);

String? _token(Ref ref) => ref.watch(adminSessionProvider).value?.accessToken;

final adminUsageProvider = FutureProvider.autoDispose<InstanceUsage>((
  ref,
) async {
  final token = _token(ref);
  if (token == null) throw StateError('no admin session');
  return ref.watch(adminApiProvider).usage(token);
});

final adminTeamsProvider = FutureProvider.autoDispose<List<AdminTeam>>((
  ref,
) async {
  final token = _token(ref);
  if (token == null) throw StateError('no admin session');
  return ref.watch(adminApiProvider).teams(token);
});

final adminPackagesProvider = FutureProvider.autoDispose<List<AdminPackage>>((
  ref,
) async {
  final token = _token(ref);
  if (token == null) throw StateError('no admin session');
  return ref.watch(adminApiProvider).packages(token);
});

final adminLimitKeysProvider = FutureProvider.autoDispose<List<LimitKeyInfo>>((
  ref,
) async {
  final token = _token(ref);
  if (token == null) throw StateError('no admin session');
  return ref.watch(adminApiProvider).limitKeys(token);
});

/// The sales inbox (EE-160), and the one list in this console that pages.
///
/// An `AsyncNotifier` rather than a `FutureProvider` because the list has a
/// CURSOR: `loadMore` appends the next page to what is already on screen, and
/// the cursor is the last id of the page before it. That is the server's
/// contract (EE-159) and the reason it is not an offset — a lead arriving while
/// somebody reads page one would push every later page along by one, so page
/// two would repeat a row and skip another.
final adminLeadsProvider =
    AsyncNotifierProvider.autoDispose<AdminLeadsController, AdminLeadPage>(
      AdminLeadsController.new,
    );

class AdminLeadsController extends AsyncNotifier<AdminLeadPage> {
  String? _status;

  /// The filter, so the screen can render the chip that is selected.
  String? get status => _status;

  @override
  Future<AdminLeadPage> build() => _page(null);

  Future<AdminLeadPage> _page(String? cursor) {
    final token = _token(ref);
    if (token == null) throw StateError('no admin session');
    return ref
        .read(adminApiProvider)
        .leads(token, status: _status, cursor: cursor);
  }

  Future<void> filter(String? status) async {
    _status = status;
    state = const AsyncValue.loading();
    // A filter change starts a NEW list rather than continuing the old one:
    // the cursor is an anchor in one ordering, and carrying it across a filter
    // would silently skip everything newer than it in the new one.
    state = await AsyncValue.guard(() => _page(null));
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || current.nextCursor == null) return;
    final next = await _page(current.nextCursor);
    state = AsyncValue.data(
      AdminLeadPage(
        items: [...current.items, ...next.items],
        nextCursor: next.nextCursor,
      ),
    );
  }

  Future<void> reload() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _page(null));
  }
}

/// One lead, for the detail route. Separate from the list so opening a link
/// directly works — a detail screen that could only read from a loaded list
/// would be broken for exactly the person who was sent the URL.
final adminLeadProvider = FutureProvider.autoDispose.family<AdminLead, String>((
  ref,
  id,
) async {
  final token = _token(ref);
  if (token == null) throw StateError('no admin session');
  return ref.watch(adminApiProvider).lead(token, id);
});
