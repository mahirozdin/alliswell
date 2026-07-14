import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/auth_api.dart';
import 'data/auth_interceptor.dart';
import 'data/auth_repository.dart';
import 'data/models.dart';
import 'data/secret_store.dart';
import 'data/secure_secret_store.dart';
import 'data/token_storage.dart';

/// Where the API lives. Override at build time:
/// `flutter run --dart-define=ALLISWELL_API_URL=https://your-host`.
final apiBaseUrlProvider = Provider<String>(
  (_) => const String.fromEnvironment(
    'ALLISWELL_API_URL',
    defaultValue: 'http://localhost:3000',
  ),
);

/// Platform secret storage (OPH-025): Keychain/Keystore-backed on
/// mobile/desktop, in-memory on web (see secure_secret_store.dart).
/// Tests override this with a seeded [InMemorySecretStore].
final secretStoreProvider = Provider<SecretStore>((_) => defaultSecretStore());

final tokenStorageProvider = Provider<TokenStorage>(
  (ref) => TokenStorage(ref.watch(secretStoreProvider)),
);

/// Bare client for the auth endpoints themselves (no interceptor — the
/// interceptor's refresh path must not recurse through itself).
final authApiProvider = Provider<AuthApi>(
  (ref) => AuthApi(Dio(BaseOptions(baseUrl: ref.watch(apiBaseUrlProvider)))),
);

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final repository = AuthRepository(
    api: ref.watch(authApiProvider),
    storage: ref.watch(tokenStorageProvider),
  );
  ref.onDispose(repository.dispose);
  return repository;
});

/// Authenticated dio for every feature API (tasks, projects, /me, …):
/// attaches the access token and transparently refreshes it once on a 401.
final apiClientProvider = Provider<Dio>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  final dio = Dio(BaseOptions(baseUrl: ref.watch(apiBaseUrlProvider)));
  dio.interceptors.add(
    AuthInterceptor(
      getAccessToken: () => repository.accessToken,
      refreshAccessToken: repository.refreshAccessToken,
    ),
  );
  return dio;
});

/// App-wide auth state: `null` data = signed out, loading = restoring the
/// persisted session at startup.
final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthSession?>(AuthController.new);

class AuthController extends AsyncNotifier<AuthSession?> {
  @override
  Future<AuthSession?> build() async {
    final repository = ref.watch(authRepositoryProvider);
    // Mirror every repository-side change (rotation, forced sign-out on a
    // failed refresh, logout) into the exposed state.
    final sub = repository.sessionChanges.listen(
      (session) => state = AsyncData(session),
    );
    ref.onDispose(sub.cancel);
    return repository.restore();
  }

  /// Throws [AuthException] on failure — screens turn codes into messages.
  /// Success lands in [state] via the repository's change stream.
  Future<void> login({required String email, required String password}) =>
      ref.read(authRepositoryProvider).login(email: email, password: password);

  Future<void> register({
    required String email,
    required String password,
    String? displayName,
  }) => ref
      .read(authRepositoryProvider)
      .register(email: email, password: password, displayName: displayName);

  Future<void> logout({bool allDevices = false}) =>
      ref.read(authRepositoryProvider).logout(allDevices: allDevices);
}
