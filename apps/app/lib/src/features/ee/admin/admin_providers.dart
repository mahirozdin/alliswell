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
